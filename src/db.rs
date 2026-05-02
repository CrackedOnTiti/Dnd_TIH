use sqlx::{sqlite::SqliteConnectOptions, SqlitePool};
use std::str::FromStr;

pub async fn init(database_url: &str) -> Result<SqlitePool, sqlx::Error> {
    let path = database_url.trim_start_matches("sqlite:");
    if let Some(parent) = std::path::Path::new(path).parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let options = SqliteConnectOptions::from_str(database_url)?
        .create_if_missing(true)
        .pragma("journal_mode", "WAL")
        .pragma("foreign_keys", "ON");

    let pool = SqlitePool::connect_with(options).await?;
    migrate(&pool).await?;
    Ok(pool)
}

async fn migrate(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS users (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT    NOT NULL UNIQUE,
            pin      TEXT    NOT NULL,
            role     TEXT    NOT NULL CHECK(role IN ('host','player'))
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS characters (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id       INTEGER NOT NULL REFERENCES users(id),
            name          TEXT    NOT NULL,
            sex           TEXT,
            age           INTEGER,
            power1        TEXT,
            power1_desc   TEXT,
            power2        TEXT,
            physical_desc TEXT,
            weapons       TEXT,
            curr_hp       INTEGER DEFAULT 100,
            max_hp        INTEGER DEFAULT 100,
            curr_stam     INTEGER DEFAULT 100,
            max_stam      INTEGER DEFAULT 100,
            copper        INTEGER DEFAULT 0,
            last_roll     INTEGER
        )",
    )
    .execute(pool)
    .await?;

    // Non-destructive migrations for existing databases
    let _ = sqlx::query("ALTER TABLE characters ADD COLUMN power1_desc TEXT").execute(pool).await;
    let _ = sqlx::query("ALTER TABLE characters ADD COLUMN physical_desc TEXT").execute(pool).await;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS change_requests (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            req_type     TEXT    NOT NULL CHECK(req_type IN ('profile','ability')),
            payload      TEXT    NOT NULL,
            status       TEXT    DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','modified')),
            host_note    TEXT,
            created_at   DATETIME DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS abilities (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            name         TEXT    NOT NULL,
            description  TEXT,
            drain_type   TEXT    CHECK(drain_type IN ('hp','stam','both')),
            drain_value  INTEGER,
            confirmed    INTEGER DEFAULT 0
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS inventory (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            item_name    TEXT    NOT NULL,
            amount       INTEGER DEFAULT 1
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS notes (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            content      TEXT    DEFAULT ''
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS host_messages (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            sender       TEXT    NOT NULL CHECK(sender IN ('host','player')),
            content      TEXT    NOT NULL,
            mode         TEXT    DEFAULT 'RP' CHECK(mode IN ('RP','HRP','???')),
            created_at   DATETIME DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS player_messages (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            sender_id   INTEGER NOT NULL REFERENCES characters(id),
            receiver_id INTEGER NOT NULL REFERENCES characters(id),
            content     TEXT    NOT NULL,
            created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS sessions (
            token      TEXT    PRIMARY KEY,
            user_id    INTEGER NOT NULL REFERENCES users(id),
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS dice_constraints (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id     INTEGER REFERENCES characters(id),
            is_host          INTEGER DEFAULT 0,
            allowed_die      INTEGER,
            range_min        INTEGER,
            range_max        INTEGER,
            fixed_value      INTEGER,
            always_over_half INTEGER DEFAULT 0
        )",
    )
    .execute(pool)
    .await?;

    sqlx::query(
        "CREATE TABLE IF NOT EXISTS character_specials (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            character_id INTEGER NOT NULL REFERENCES characters(id),
            key          TEXT    NOT NULL,
            value        INTEGER NOT NULL DEFAULT 0,
            UNIQUE(character_id, key)
        )",
    )
    .execute(pool)
    .await?;

    // Seed Joachim's stored_damage if not already present
    sqlx::query(
        "INSERT OR IGNORE INTO character_specials (character_id, key, value)
         SELECT c.id, 'stored_damage', 20
         FROM characters c JOIN users u ON u.id = c.user_id
         WHERE u.username = 'joachim_gruut'",
    )
    .execute(pool)
    .await?;

    Ok(())
}
