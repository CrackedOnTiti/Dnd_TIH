# DnD_TIH

A real-time companion app for a homebrew tabletop campaign set in the *Tempered in Hate* universe.

One game master (the **host**) runs the session from a dashboard. Each player has their own interface. Rolls, stats, money, inventory and messages sync live over one WebSocket per client, so nobody reloads the page.

> **Status:** finished. It was used through a full campaign, with player feedback logged as GitHub issues and worked through between sessions (see [Player feedback](#player-feedback)). The last code change was in May 2026. The interface is in French.

---

## Features

### Per-player synced interfaces
- One account per player, logged in with a username and 4-digit PIN. Each player creates a character on first login.
- Character sheet: name, sex, age, two powers, power description, physical description and weapons.
- **HP and stamina bars** update instantly when the game master changes them.
- **Inventory**: players and the game master can both add, edit and remove items, and both views stay in sync.
- **Money** is stored as one integer in copper and shown as platinum / gold / silver / copper (1 P = 100 G = 10 000 S = 1 000 000 C).
- **Player-to-player money transfers** are rejected if the sender lacks the funds.
- **Private notepad** for each player, saved on the server.
- A connection indicator shows the link status. Clients reconnect automatically every 3 seconds if the link drops.

### Messaging
- **Private chat between each player and the game master.** Messages are tagged by mode: `RP` (in character), `HRP` (out of character) or `???` (lore / mystery). Each mode is styled differently.
- **Private messages between players.** The game master does not receive them.
- **Group message**: the game master can send one message to any subset of players.
- Unread indicators: players see a badge for new game-master messages, and the host sees a dot on each player who has written.

### Game-master dice control
- Players and the game master roll d6, d10, d20 or d100 on the server. The game master sees every player's latest roll live.
- The game master's own roll is broadcast to all players.
- The game master can set a **hidden dice constraint** on any player, or on their own die. The server applies it before sending the result, and players are never told it exists:
  - force a die type
  - map the result into a `[min, max]` range
  - fix the result to a single value
  - guarantee a roll in the upper half of the die

### Game-master tools
- One dashboard with every character's HP, stamina and money, and online/offline status.
- Quick buttons (−1 / −5 / −15 / −30), plus *set*, *deduct* and *set max* for HP and stamina.
- Direct editing of any character's profile.
- **Change requests**: players propose profile edits or new abilities. The game master can approve, reject or edit them, with an optional note. The player is notified, and approved changes are written to the database.
- **Abilities** can cost HP and/or stamina. Clicking a confirmed ability on the dashboard applies its cost to the character.
- **Per-character special counters**: a generic key/value table. It is currently used for a "stored damage" counter that grows automatically when the game master lowers that character's HP. The game master can deduct from it or reset it.

---

## Architecture

```
 Browser (player.html / host.html, plain JS)
        │  HTTPS: REST for initial load      WSS: /ws for everything live
        ▼
 ┌──────────────── Axum server (Rust, Tokio) ────────────────┐
 │  routes/auth.rs     login / register / logout (cookie)     │
 │  routes/player.rs   player REST API                        │
 │  routes/host.rs     host-only REST API (HostOnly guard)    │
 │  routes/ws_handler  dispatch on (event type, role)         │
 │  ws.rs  Hub: in-memory map user_id → client channel        │
 └──────────────────────────────┬─────────────────────────────┘
                                ▼
                       SQLite (WAL mode)
```

- **One WebSocket per client.** Every message uses the envelope `{ "type": string, "data": any }`. The server accepts 21 *(event, role)* pairs (8 for players, 13 for the host) and sends 18 event types.
- **Server-side authority for the important parts.** Rolls, dice constraints, balance checks and every database write happen on the server. After each change, the server sends the resulting state to the clients concerned.
- **Role-based routing.** Each event is dispatched on `(event_type, role)`, so a player cannot send host-only events. The `Hub` sends each update only to the clients concerned: one user, one character, the host, all players, or everyone.
- **Auth.** PINs are hashed with bcrypt. Sessions are random UUIDs stored in SQLite and sent in an `HttpOnly`, `SameSite=Lax` cookie. Two Axum extractors guard the routes: `AuthUser` and `HostOnly`.
- **Schema.** 11 tables, created at startup with `CREATE TABLE IF NOT EXISTS`. New columns are added with additive `ALTER TABLE … ADD COLUMN`, so existing databases keep working without a migration tool.
- **Accounts from the environment.** On every startup, the host account and up to 4 player accounts are created or updated from environment variables. Changing a PIN only takes a restart.

### Repository layout

```
src/
  main.rs            router, state, startup
  db.rs              SQLite init and schema
  auth.rs            account seeding, sessions, auth extractors
  ws.rs              WebSocket hub
  models.rs          DB structs and the WS envelope
  routes/            auth, player, host, ws_handler
static/
  index.html         login / register
  player.html        player interface
  host.html          game-master dashboard
  js/main.js         shared helpers (money, bars, chat)
  js/player.js, js/host.js
  css/style.css
Dockerfile           multi-stage Rust build → debian:bookworm-slim
docker-compose.yml   app service
Dockerfile.caddy     Caddy with the DuckDNS DNS plugin
Caddyfile            HTTPS reverse proxy config
```

---

## Stack

| Layer | Technology (versions from `Cargo.lock`) |
|---|---|
| Language | Rust, edition 2021 |
| Web framework | Axum 0.7.9 (WebSockets), axum-extra 0.9.6 (cookies), tower-http 0.5.2 (static files) |
| Async runtime | Tokio 1.52.1 |
| Database | SQLite via sqlx 0.7.4 |
| Auth | bcrypt 0.15.1, uuid 1.23.1 |
| Serialization | serde 1.0.228, serde_json 1.0.149 |
| Other | rand 0.8.6, chrono 0.4.44, tracing 0.1.44, dotenvy 0.15.7 |
| Frontend | Vanilla HTML / CSS / JavaScript, no build step |
| Deployment | Docker (multi-stage build), Docker Compose, Caddy 2 with `caddy-dns/duckdns` |

---

## Running it

### Configuration

Copy `.env.example` to `.env` and fill it in. The app reads these variables:

| Variable | Purpose | Default |
|---|---|---|
| `HOST_USERNAME`, `HOST_PIN` | Game-master account | `host` / `0000` |
| `PLAYER1_USERNAME` … `PLAYER4_USERNAME` | Pre-created player accounts (optional) | none |
| `PLAYER1_PIN` … `PLAYER4_PIN` | Their 4-digit PINs | `1234` |
| `DATABASE_URL` | SQLite path | `sqlite:./data/dnd.db` (`sqlite:/app/data/dnd.db` in Docker) |
| `BIND_ADDR` | Listen address | `0.0.0.0:3000` |
| `RUST_LOG` | Log level | `info` |
| `DUCKDNS_TOKEN` | Used by Caddy only, for the HTTPS certificate | none |

Change the default PINs before exposing the app to a network.

Example demo `.env`:

```env
HOST_USERNAME=gm
HOST_PIN=4821
PLAYER1_USERNAME=alice
PLAYER1_PIN=1357
PLAYER2_USERNAME=bob
PLAYER2_PIN=2468
```

### Locally

```bash
cargo run                 # serves on http://localhost:3000
RUST_LOG=debug cargo run  # verbose logging
```

The database is created in `./data/` on first launch.

### Docker

```bash
docker compose up --build -d
```

This builds the release binary in a multi-stage image and serves the app on host port **50080**. `./data` is mounted as a volume, so the SQLite database survives rebuilds.

### HTTPS with Caddy

`Dockerfile.caddy` builds Caddy with the DuckDNS DNS-challenge plugin. `Caddyfile` reverse-proxies a DuckDNS domain to `app:3000` with an automatic TLS certificate, and WebSockets pass through without extra config.

`docker-compose.yml` does **not** currently start Caddy; the service was removed from it in commit `7c75182`. To run it next to the app:

1. Change the domain in `Caddyfile` to your own DuckDNS subdomain.
2. Set `DUCKDNS_TOKEN` in `.env`.
3. Add a `docker-compose.override.yml` file:

```yaml
services:
  caddy:
    build: { context: ., dockerfile: Dockerfile.caddy }
    restart: unless-stopped
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    environment:
      - DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
    depends_on: [app]
volumes:
  caddy_data:
  caddy_config:
```

Then run `docker compose up --build -d` again.

### Using it

1. Open the site and log in as the host to reach the dashboard.
2. Players log in with their accounts, or register with a username and 4-digit PIN. They then create their character.
3. New characters appear on the host dashboard in real time.

---

## Known limitations

These are deliberate trade-offs for a private game among friends, not production hardening:

- No automated tests.
- Anyone who can reach the server can register a player account. The 4-player limit applies only to accounts pre-created from environment variables.
- Sessions do not expire until logout, and the 4-digit PIN is the only credential.
- Money transfers run as separate SQL statements, not in a single transaction.
- The interface is in French only.

---

## History

- **Nov 2025:** first prototype in Python (Flask + Flask-SocketIO) with PostgreSQL in Docker.
- **Jan–Mar 2026:** Flutter Web frontend served by nginx. Added host dashboard, live rolls, notes, JSON save files, database backup/restore scripts, and the money system ([#1](https://github.com/CrackedOnTiti/Dnd_TIH/issues/1)). Cleaned up the code ([#2](https://github.com/CrackedOnTiti/Dnd_TIH/issues/2)).
- **Apr–May 2026:** rewrote the app in Rust (Axum + SQLite) with a plain-JS frontend, then brought back every earlier feature. This is the version in this repository.

### Player feedback

The app was built while the campaign was running. Players' feedback and critiques were logged as GitHub issues and worked through between sessions:

| Issue | Status |
|---|---|
| [#1 Money](https://github.com/CrackedOnTiti/Dnd_TIH/issues/1): currency conversion, a balance display, transfers between players, host can grant money | Closed 2026-03-06 (`6eede38`, `4823fab`, `0a7538a`, `010d642`) |
| [#2 Clean up code](https://github.com/CrackedOnTiti/Dnd_TIH/issues/2) | Closed 2026-03-21 (`020abc7`) |
| [#3 Create action menu for players](https://github.com/CrackedOnTiti/Dnd_TIH/issues/3) | Open |
| [#4 Layout redesign for 1.0](https://github.com/CrackedOnTiti/Dnd_TIH/issues/4) | Open |

---

## License

MIT. See [LICENSE](LICENSE).
