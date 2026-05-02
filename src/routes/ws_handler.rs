use crate::{
    auth,
    models::{DiceConstraint, User, WsEnvelope},
    ws::ClientInfo,
    AppState,
};
use axum::{
    extract::{
        ws::{Message, WebSocket},
        State, WebSocketUpgrade,
    },
    http::HeaderMap,
    response::Response,
};
use axum_extra::extract::CookieJar;
use futures_util::{SinkExt, StreamExt};
use rand::Rng;
use tokio::sync::mpsc;

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    headers: HeaderMap,
    State(state): State<AppState>,
) -> Response {
    let jar = CookieJar::from_headers(&headers);
    let token = jar.get("session").map(|c| c.value().to_string());
    ws.on_upgrade(move |socket| handle_socket(socket, state, token))
}

async fn handle_socket(socket: WebSocket, state: AppState, token: Option<String>) {
    let user = match token {
        Some(t) => match auth::get_session_user(&state.db, &t).await {
            Some(u) => u,
            None => return,
        },
        None => return,
    };

    let character_id: Option<i64> = if user.role == "player" {
        sqlx::query_scalar("SELECT id FROM characters WHERE user_id = ?")
            .bind(user.id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten()
    } else {
        None
    };

    let (mut ws_tx, mut ws_rx) = socket.split();
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    state
        .hub
        .register(ClientInfo {
            user_id: user.id,
            role: user.role.clone(),
            character_id,
            tx,
        })
        .await;

    // Notify host when a player comes online
    if user.role == "player" {
        if let Some(cid) = character_id {
            let name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
                .bind(cid)
                .fetch_one(&state.db)
                .await
                .unwrap_or_default();
            state.hub.send_to_host(&WsEnvelope::new(
                "player_online",
                serde_json::json!({ "character_id": cid, "name": name }),
            )).await;
        }
    }

    let send_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_tx.send(msg).await.is_err() {
                break;
            }
        }
    });

    while let Some(Ok(msg)) = ws_rx.next().await {
        match msg {
            Message::Text(text) => {
                let envelope: WsEnvelope = match serde_json::from_str(&text) {
                    Ok(e) => e,
                    Err(_) => continue,
                };
                process_message(envelope, &user, character_id, &state).await;
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    send_task.abort();
    state.hub.unregister(user.id).await;

    // Notify host when a player goes offline
    if user.role == "player" {
        if let Some(cid) = character_id {
            let name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
                .bind(cid)
                .fetch_one(&state.db)
                .await
                .unwrap_or_default();
            state.hub.send_to_host(&WsEnvelope::new(
                "player_offline",
                serde_json::json!({ "character_id": cid, "name": name }),
            )).await;
        }
    }
}

async fn process_message(
    env: WsEnvelope,
    user: &User,
    character_id: Option<i64>,
    state: &AppState,
) {
    match (env.event_type.as_str(), user.role.as_str()) {
        // ── Player events ─────────────────────────────────────────────────────
        ("roll", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let die_type = env.data["die_type"].as_i64().unwrap_or(20);
            handle_player_roll(char_id, die_type, state).await;
        }
        ("player_message", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let content = match env.data["content"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let mode = env.data["mode"].as_str().unwrap_or("RP").to_string();
            let mode = if ["RP", "HRP", "???"].contains(&mode.as_str()) {
                mode
            } else {
                "RP".to_string()
            };
            handle_player_message(char_id, content, mode, state).await;
        }
        ("player_dm", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let receiver_id = match env.data["receiver_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let content = match env.data["content"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            handle_player_dm(char_id, receiver_id, content, state).await;
        }
        ("change_request", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let req_type = match env.data["req_type"].as_str() {
                Some(t) if t == "profile" || t == "ability" => t.to_string(),
                _ => return,
            };
            let payload = env.data["payload"].clone();
            handle_change_request(char_id, req_type, payload, state).await;
        }
        ("money_transfer", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let to_id = match env.data["to_character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let amount = match env.data["amount"].as_i64() {
                Some(a) if a > 0 => a,
                _ => return,
            };
            handle_money_transfer(char_id, to_id, amount, state).await;
        }
        ("inventory_add", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let item_name = match env.data["item_name"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let amount = env.data["amount"].as_i64().unwrap_or(1);
            handle_inventory_add(char_id, item_name, amount, state).await;
        }
        ("inventory_remove", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let item_id = match env.data["item_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            handle_inventory_remove_by_id(char_id, item_id, state).await;
        }
        ("inventory_edit", "player") => {
            let char_id = match character_id {
                Some(id) => id,
                None => return,
            };
            let item_id = match env.data["item_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let item_name = match env.data["item_name"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let amount = env.data["amount"].as_i64().unwrap_or(1);
            handle_inventory_edit(char_id, item_id, item_name, amount, state).await;
        }

        // ── Host events ───────────────────────────────────────────────────────
        ("host_roll", "host") => {
            let die_type = env.data["die_type"].as_i64().unwrap_or(20);
            handle_host_roll(die_type, state).await;
        }
        ("host_message", "host") => {
            let character_ids: Vec<i64> = env.data["character_ids"]
                .as_array()
                .map(|a| a.iter().filter_map(|v| v.as_i64()).collect())
                .unwrap_or_default();
            let content = match env.data["content"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let mode = env.data["mode"].as_str().unwrap_or("RP").to_string();
            let mode = if ["RP", "HRP", "???"].contains(&mode.as_str()) {
                mode
            } else {
                "RP".to_string()
            };
            handle_host_message(character_ids, content, mode, state).await;
        }
        ("stat_update", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let field = match env.data["field"].as_str() {
                Some(f) if ["curr_hp", "max_hp", "curr_stam", "max_stam"].contains(&f) => {
                    f.to_string()
                }
                _ => return,
            };
            let value = match env.data["value"].as_i64() {
                Some(v) => v,
                None => return,
            };
            handle_stat_update(char_id, &field, value, state).await;
        }
        ("profile_update", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            handle_profile_update(char_id, env.data["changes"].clone(), state).await;
        }
        ("inventory_add", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let item_name = match env.data["item_name"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let amount = env.data["amount"].as_i64().unwrap_or(1);
            handle_inventory_add(char_id, item_name, amount, state).await;
        }
        ("inventory_remove", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let item_id = match env.data["item_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            handle_inventory_remove_by_id(char_id, item_id, state).await;
        }
        ("inventory_edit", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let item_id = match env.data["item_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let item_name = match env.data["item_name"].as_str() {
                Some(s) => s.to_string(),
                None => return,
            };
            let amount = env.data["amount"].as_i64().unwrap_or(1);
            handle_inventory_edit(char_id, item_id, item_name, amount, state).await;
        }
        ("money_update", "host") => {
            let char_id = match env.data["character_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let amount = match env.data["amount"].as_i64() {
                Some(a) => a,
                None => return,
            };
            handle_money_update(char_id, amount, state).await;
        }
        ("dice_constraint_set", "host") => {
            let character_id = env.data["character_id"].as_i64();
            let is_host = env.data["is_host"].as_bool().unwrap_or(false);
            let allowed_die = env.data["allowed_die"].as_i64();
            let range_min = env.data["range_min"].as_i64();
            let range_max = env.data["range_max"].as_i64();
            let fixed_value = env.data["fixed_value"].as_i64();
            let always_over_half = env.data["always_over_half"].as_bool().unwrap_or(false);
            handle_dice_constraint_set(
                character_id,
                is_host,
                allowed_die,
                range_min,
                range_max,
                fixed_value,
                always_over_half,
                state,
            )
            .await;
        }
        ("dice_constraint_clear", "host") => {
            let character_id = env.data["character_id"].as_i64();
            let is_host = env.data["is_host"].as_bool().unwrap_or(false);
            handle_dice_constraint_clear(character_id, is_host, state).await;
        }
        ("request_response", "host") => {
            let request_id = match env.data["request_id"].as_i64() {
                Some(id) => id,
                None => return,
            };
            let action = match env.data["action"].as_str() {
                Some(a) if ["approved", "rejected", "modified"].contains(&a) => a.to_string(),
                _ => return,
            };
            let host_note = env.data["host_note"].as_str().map(|s| s.to_string());
            let modified_payload = env.data.get("payload").cloned();
            handle_request_response(request_id, action, host_note, modified_payload, state).await;
        }
        ("special_deduct", "host") => {
            if let (Some(cid), Some(amount)) = (
                env.data["character_id"].as_i64(),
                env.data["amount"].as_i64(),
            ) {
                let key = env.data["key"].as_str().unwrap_or("stored_damage");
                special_add(cid, key, -amount, state).await;
            }
        }
        ("special_clear", "host") => {
            if let Some(cid) = env.data["character_id"].as_i64() {
                let key = env.data["key"].as_str().unwrap_or("stored_damage");
                special_set(cid, key, 0, state).await;
            }
        }
        _ => {}
    }
}

// ── Player roll ────────────────────────────────────────────────────────────────

async fn handle_player_roll(character_id: i64, mut die_type: i64, state: &AppState) {
    if ![6, 10, 20, 100].contains(&die_type) {
        die_type = 20;
    }

    let constraint: Option<DiceConstraint> = sqlx::query_as(
        "SELECT * FROM dice_constraints WHERE character_id = ? AND is_host = 0 LIMIT 1",
    )
    .bind(character_id)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    if let Some(ref c) = constraint {
        if let Some(allowed) = c.allowed_die {
            if [6, 10, 20, 100].contains(&allowed) {
                die_type = allowed;
            }
        }
    }

    let raw: i64 = rand::thread_rng().gen_range(1..=die_type);
    let result = apply_constraint(raw, die_type, constraint.as_ref());

    sqlx::query("UPDATE characters SET last_roll = ? WHERE id = ?")
        .bind(result)
        .bind(character_id)
        .execute(&state.db)
        .await
        .ok();

    let name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
        .bind(character_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();

    // Send result to rolling player
    state
        .hub
        .send_to_character(
            character_id,
            &WsEnvelope::new(
                "roll_result",
                serde_json::json!({
                    "character_id": character_id,
                    "result": result
                }),
            ),
        )
        .await;

    // Send to host with player context
    state
        .hub
        .send_to_host(&WsEnvelope::new(
            "player_rolled",
            serde_json::json!({
                "character_id": character_id,
                "player_name": name,
                "result": result,
                "die_type": die_type
            }),
        ))
        .await;
}

// ── Host roll ─────────────────────────────────────────────────────────────────

async fn handle_host_roll(mut die_type: i64, state: &AppState) {
    if ![6, 10, 20, 100].contains(&die_type) {
        die_type = 20;
    }

    let constraint: Option<DiceConstraint> = sqlx::query_as(
        "SELECT * FROM dice_constraints WHERE is_host = 1 LIMIT 1",
    )
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    let raw: i64 = rand::thread_rng().gen_range(1..=die_type);
    let result = apply_constraint(raw, die_type, constraint.as_ref());

    // Broadcast to all players (and back to host for display)
    let msg = WsEnvelope::new(
        "host_rolled",
        serde_json::json!({"result": result, "die_type": die_type}),
    );
    state.hub.send_to_all_players(&msg).await;
    state.hub.send_to_host(&msg).await;
}

// ── Constraint application (server-side, silent) ──────────────────────────────

fn apply_constraint(raw: i64, die_max: i64, constraint: Option<&DiceConstraint>) -> i64 {
    let c = match constraint {
        Some(c) => c,
        None => return raw,
    };

    if let Some(fixed) = c.fixed_value {
        return fixed.max(1).min(die_max);
    }

    let mut result = raw;

    if let (Some(min), Some(max)) = (c.range_min, c.range_max) {
        if max >= min && max >= 1 {
            let range_size = max - min + 1;
            result = min + ((result - 1).unsigned_abs() as i64 % range_size);
        }
    }

    if c.always_over_half == 1 {
        let half = die_max / 2;
        let upper = die_max - half;
        if result <= half && upper > 0 {
            result = half + 1 + ((result - 1).unsigned_abs() as i64 % upper);
        }
    }

    result.max(1).min(die_max)
}

// ── Player message to host ────────────────────────────────────────────────────

async fn handle_player_message(
    character_id: i64,
    content: String,
    mode: String,
    state: &AppState,
) {
    let id: i64 = sqlx::query_scalar(
        "INSERT INTO host_messages (character_id, sender, content, mode) VALUES (?, 'player', ?, ?) RETURNING id",
    )
    .bind(character_id)
    .bind(&content)
    .bind(&mode)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let created_at: String =
        sqlx::query_scalar("SELECT created_at FROM host_messages WHERE id = ?")
            .bind(id)
            .fetch_one(&state.db)
            .await
            .unwrap_or_default();

    let name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
        .bind(character_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();

    state
        .hub
        .send_to_host(&WsEnvelope::new(
            "message_received",
            serde_json::json!({
                "id": id,
                "character_id": character_id,
                "player_name": name,
                "sender": "player",
                "content": content,
                "mode": mode,
                "created_at": created_at
            }),
        ))
        .await;
}

// ── Host message to player(s) ─────────────────────────────────────────────────

async fn handle_host_message(
    character_ids: Vec<i64>,
    content: String,
    mode: String,
    state: &AppState,
) {
    for char_id in character_ids {
        let id: i64 = sqlx::query_scalar(
            "INSERT INTO host_messages (character_id, sender, content, mode) VALUES (?, 'host', ?, ?) RETURNING id",
        )
        .bind(char_id)
        .bind(&content)
        .bind(&mode)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0);

        let created_at: String =
            sqlx::query_scalar("SELECT created_at FROM host_messages WHERE id = ?")
                .bind(id)
                .fetch_one(&state.db)
                .await
                .unwrap_or_default();

        state
            .hub
            .send_to_character(
                char_id,
                &WsEnvelope::new(
                    "message_received",
                    serde_json::json!({
                        "id": id,
                        "character_id": char_id,
                        "sender": "host",
                        "content": content,
                        "mode": mode,
                        "created_at": created_at
                    }),
                ),
            )
            .await;
    }
}

// ── Player DM ─────────────────────────────────────────────────────────────────

async fn handle_player_dm(
    sender_id: i64,
    receiver_id: i64,
    content: String,
    state: &AppState,
) {
    let id: i64 = sqlx::query_scalar(
        "INSERT INTO player_messages (sender_id, receiver_id, content) VALUES (?, ?, ?) RETURNING id",
    )
    .bind(sender_id)
    .bind(receiver_id)
    .bind(&content)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let created_at: String =
        sqlx::query_scalar("SELECT created_at FROM player_messages WHERE id = ?")
            .bind(id)
            .fetch_one(&state.db)
            .await
            .unwrap_or_default();

    let sender_name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
        .bind(sender_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();

    let msg = WsEnvelope::new(
        "dm_received",
        serde_json::json!({
            "id": id,
            "sender_id": sender_id,
            "sender_name": sender_name,
            "receiver_id": receiver_id,
            "content": content,
            "created_at": created_at
        }),
    );

    state.hub.send_to_character(receiver_id, &msg).await;
    state.hub.send_to_character(sender_id, &msg).await;
}

// ── Change request ────────────────────────────────────────────────────────────

async fn handle_change_request(
    character_id: i64,
    req_type: String,
    payload: serde_json::Value,
    state: &AppState,
) {
    let payload_str = serde_json::to_string(&payload).unwrap_or_default();

    let id: i64 = sqlx::query_scalar(
        "INSERT INTO change_requests (character_id, req_type, payload) VALUES (?, ?, ?) RETURNING id",
    )
    .bind(character_id)
    .bind(&req_type)
    .bind(&payload_str)
    .fetch_one(&state.db)
    .await
    .unwrap_or(0);

    let created_at: String =
        sqlx::query_scalar("SELECT created_at FROM change_requests WHERE id = ?")
            .bind(id)
            .fetch_one(&state.db)
            .await
            .unwrap_or_default();

    let name: String = sqlx::query_scalar("SELECT name FROM characters WHERE id = ?")
        .bind(character_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();

    state
        .hub
        .send_to_host(&WsEnvelope::new(
            "change_request_received",
            serde_json::json!({
                "id": id,
                "character_id": character_id,
                "player_name": name,
                "req_type": req_type,
                "payload": payload,
                "created_at": created_at
            }),
        ))
        .await;
}

// ── Request response (host) ───────────────────────────────────────────────────

async fn handle_request_response(
    request_id: i64,
    action: String,
    host_note: Option<String>,
    modified_payload: Option<serde_json::Value>,
    state: &AppState,
) {
    let req: Option<crate::models::ChangeRequest> =
        sqlx::query_as("SELECT * FROM change_requests WHERE id = ?")
            .bind(request_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();

    let req = match req {
        Some(r) => r,
        None => return,
    };

    let status = match action.as_str() {
        "approved" => "approved",
        "rejected" => "rejected",
        "modified" => "modified",
        _ => return,
    };

    sqlx::query("UPDATE change_requests SET status = ?, host_note = ? WHERE id = ?")
        .bind(status)
        .bind(&host_note)
        .bind(request_id)
        .execute(&state.db)
        .await
        .ok();

    if action == "approved" || action == "modified" {
        let effective_payload: serde_json::Value = if action == "modified" {
            modified_payload.unwrap_or_else(|| {
                serde_json::from_str(&req.payload).unwrap_or(serde_json::Value::Null)
            })
        } else {
            serde_json::from_str(&req.payload).unwrap_or(serde_json::Value::Null)
        };

        if req.req_type == "profile" {
            apply_profile_changes(req.character_id, &effective_payload, state).await;
        } else if req.req_type == "ability" {
            apply_ability_from_request(req.character_id, &effective_payload, state).await;
        }
    }

    let character: Option<crate::models::Character> =
        sqlx::query_as("SELECT * FROM characters WHERE id = ?")
            .bind(req.character_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();

    state
        .hub
        .send_to_character(
            req.character_id,
            &WsEnvelope::new(
                "request_resolved",
                serde_json::json!({
                    "id": request_id,
                    "req_type": req.req_type,
                    "action": action,
                    "host_note": host_note,
                    "character": character
                }),
            ),
        )
        .await;
}

// ── Character specials ────────────────────────────────────────────────────────

async fn special_add(character_id: i64, key: &str, delta: i64, state: &AppState) {
    let new_val: Option<i64> = sqlx::query_scalar(
        "UPDATE character_specials SET value = value + ? WHERE character_id = ? AND key = ? RETURNING value",
    )
    .bind(delta)
    .bind(character_id)
    .bind(key)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    if let Some(v) = new_val {
        push_special_updated(character_id, key, v, state).await;
    }
}

async fn special_set(character_id: i64, key: &str, value: i64, state: &AppState) {
    let new_val: Option<i64> = sqlx::query_scalar(
        "UPDATE character_specials SET value = ? WHERE character_id = ? AND key = ? RETURNING value",
    )
    .bind(value)
    .bind(character_id)
    .bind(key)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();

    if let Some(v) = new_val {
        push_special_updated(character_id, key, v, state).await;
    }
}

async fn push_special_updated(character_id: i64, key: &str, value: i64, state: &AppState) {
    let msg = WsEnvelope::new(
        "special_updated",
        serde_json::json!({ "character_id": character_id, "key": key, "value": value }),
    );
    state.hub.send_to_character(character_id, &msg).await;
    state.hub.send_to_host(&msg).await;
}

// ── Stat update (host) ────────────────────────────────────────────────────────

async fn handle_stat_update(character_id: i64, field: &str, value: i64, state: &AppState) {
    // Auto-track stored_damage: if HP is being reduced, add the difference
    if field == "curr_hp" {
        if let Ok(Some(old_hp)) = sqlx::query_scalar::<_, i64>(
            "SELECT curr_hp FROM characters WHERE id = ?",
        )
        .bind(character_id)
        .fetch_optional(&state.db)
        .await
        {
            if value < old_hp {
                special_add(character_id, "stored_damage", old_hp - value, state).await;
            }
        }
    }

    let query = format!("UPDATE characters SET {} = ? WHERE id = ?", field);
    sqlx::query(&query)
        .bind(value)
        .bind(character_id)
        .execute(&state.db)
        .await
        .ok();

    let character: Option<crate::models::Character> =
        sqlx::query_as("SELECT * FROM characters WHERE id = ?")
            .bind(character_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();

    if let Some(c) = character {
        let msg = WsEnvelope::new(
            "stat_updated",
            serde_json::json!({
                "character_id": character_id,
                "curr_hp": c.curr_hp,
                "max_hp": c.max_hp,
                "curr_stam": c.curr_stam,
                "max_stam": c.max_stam
            }),
        );
        state.hub.send_to_character(character_id, &msg).await;
        state.hub.send_to_host(&WsEnvelope::new(
            "stat_updated",
            serde_json::json!({
                "character_id": character_id,
                "curr_hp": c.curr_hp,
                "max_hp": c.max_hp,
                "curr_stam": c.curr_stam,
                "max_stam": c.max_stam
            }),
        )).await;
    }
}

// ── Profile update (host) ─────────────────────────────────────────────────────

async fn handle_profile_update(
    character_id: i64,
    changes: serde_json::Value,
    state: &AppState,
) {
    apply_profile_changes(character_id, &changes, state).await;

    let character: Option<crate::models::Character> =
        sqlx::query_as("SELECT * FROM characters WHERE id = ?")
            .bind(character_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();

    if let Some(c) = &character {
        state
            .hub
            .send_to_character(
                character_id,
                &WsEnvelope::new("profile_updated", serde_json::to_value(c).unwrap()),
            )
            .await;
    }
}

async fn apply_profile_changes(
    character_id: i64,
    changes: &serde_json::Value,
    state: &AppState,
) {
    let allowed_fields = [
        "name", "sex", "age", "power1", "power1_desc", "power2", "physical_desc", "weapons",
    ];
    if let Some(obj) = changes.as_object() {
        for (key, val) in obj {
            if !allowed_fields.contains(&key.as_str()) {
                continue;
            }
            let query = format!("UPDATE characters SET {} = ? WHERE id = ?", key);
            match val {
                serde_json::Value::String(s) => {
                    sqlx::query(&query)
                        .bind(s)
                        .bind(character_id)
                        .execute(&state.db)
                        .await
                        .ok();
                }
                serde_json::Value::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        sqlx::query(&query)
                            .bind(i)
                            .bind(character_id)
                            .execute(&state.db)
                            .await
                            .ok();
                    }
                }
                serde_json::Value::Null => {
                    let query = format!("UPDATE characters SET {} = NULL WHERE id = ?", key);
                    sqlx::query(&query)
                        .bind(character_id)
                        .execute(&state.db)
                        .await
                        .ok();
                }
                _ => {}
            }
        }
    }
}

async fn apply_ability_from_request(
    character_id: i64,
    payload: &serde_json::Value,
    state: &AppState,
) {
    let name = payload["name"].as_str().unwrap_or("").to_string();
    let description = payload["description"].as_str().map(|s| s.to_string());
    let drain_type = payload["drain_type"].as_str().map(|s| s.to_string());
    let drain_value = payload["drain_value"].as_i64();

    sqlx::query(
        "INSERT INTO abilities (character_id, name, description, drain_type, drain_value, confirmed)
         VALUES (?, ?, ?, ?, ?, 1)",
    )
    .bind(character_id)
    .bind(&name)
    .bind(&description)
    .bind(&drain_type)
    .bind(drain_value)
    .execute(&state.db)
    .await
    .ok();

    let abilities: Vec<crate::models::Ability> =
        sqlx::query_as("SELECT * FROM abilities WHERE character_id = ? ORDER BY id ASC")
            .bind(character_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default();

    state
        .hub
        .send_to_character(
            character_id,
            &WsEnvelope::new(
                "abilities_updated",
                serde_json::to_value(&abilities).unwrap(),
            ),
        )
        .await;
}

// ── Inventory operations ──────────────────────────────────────────────────────

async fn handle_inventory_add(
    character_id: i64,
    item_name: String,
    amount: i64,
    state: &AppState,
) {
    sqlx::query(
        "INSERT INTO inventory (character_id, item_name, amount) VALUES (?, ?, ?)",
    )
    .bind(character_id)
    .bind(&item_name)
    .bind(amount)
    .execute(&state.db)
    .await
    .ok();

    push_inventory_update(character_id, state).await;
}

async fn handle_inventory_remove_by_id(
    character_id: i64,
    item_id: i64,
    state: &AppState,
) {
    sqlx::query("DELETE FROM inventory WHERE id = ? AND character_id = ?")
        .bind(item_id)
        .bind(character_id)
        .execute(&state.db)
        .await
        .ok();

    push_inventory_update(character_id, state).await;
}

async fn handle_inventory_edit(
    character_id: i64,
    item_id: i64,
    item_name: String,
    amount: i64,
    state: &AppState,
) {
    sqlx::query(
        "UPDATE inventory SET item_name = ?, amount = ? WHERE id = ? AND character_id = ?",
    )
    .bind(&item_name)
    .bind(amount)
    .bind(item_id)
    .bind(character_id)
    .execute(&state.db)
    .await
    .ok();

    push_inventory_update(character_id, state).await;
}

async fn push_inventory_update(character_id: i64, state: &AppState) {
    let items: Vec<crate::models::InventoryItem> =
        sqlx::query_as("SELECT * FROM inventory WHERE character_id = ? ORDER BY id ASC")
            .bind(character_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default();

    let msg = WsEnvelope::new(
        "inventory_updated",
        serde_json::json!({
            "character_id": character_id,
            "items": items
        }),
    );

    state.hub.send_to_character(character_id, &msg).await;
    state.hub.send_to_host(&msg).await;
}

// ── Money operations ──────────────────────────────────────────────────────────

async fn handle_money_transfer(
    from_id: i64,
    to_id: i64,
    amount: i64,
    state: &AppState,
) {
    let from_copper: i64 = sqlx::query_scalar("SELECT copper FROM characters WHERE id = ?")
        .bind(from_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0);

    if from_copper < amount {
        state
            .hub
            .send_to_character(
                from_id,
                &WsEnvelope::new(
                    "error",
                    serde_json::json!({"message": "Fonds insuffisants"}),
                ),
            )
            .await;
        return;
    }

    sqlx::query("UPDATE characters SET copper = copper - ? WHERE id = ?")
        .bind(amount)
        .bind(from_id)
        .execute(&state.db)
        .await
        .ok();

    sqlx::query("UPDATE characters SET copper = copper + ? WHERE id = ?")
        .bind(amount)
        .bind(to_id)
        .execute(&state.db)
        .await
        .ok();

    let from_copper_new: i64 = sqlx::query_scalar("SELECT copper FROM characters WHERE id = ?")
        .bind(from_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0);

    let to_copper_new: i64 = sqlx::query_scalar("SELECT copper FROM characters WHERE id = ?")
        .bind(to_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0);

    state
        .hub
        .send_to_character(
            from_id,
            &WsEnvelope::new("money_updated", serde_json::json!({"character_id": from_id, "copper": from_copper_new})),
        )
        .await;
    state
        .hub
        .send_to_character(
            to_id,
            &WsEnvelope::new("money_updated", serde_json::json!({"character_id": to_id, "copper": to_copper_new})),
        )
        .await;
    state
        .hub
        .send_to_host(&WsEnvelope::new(
            "money_transfer_done",
            serde_json::json!({
                "from_id": from_id,
                "to_id": to_id,
                "amount": amount,
                "from_copper": from_copper_new,
                "to_copper": to_copper_new
            }),
        ))
        .await;
}

async fn handle_money_update(character_id: i64, amount: i64, state: &AppState) {
    sqlx::query("UPDATE characters SET copper = MAX(0, copper + ?) WHERE id = ?")
        .bind(amount)
        .bind(character_id)
        .execute(&state.db)
        .await
        .ok();

    let copper: i64 = sqlx::query_scalar("SELECT copper FROM characters WHERE id = ?")
        .bind(character_id)
        .fetch_one(&state.db)
        .await
        .unwrap_or(0);

    let msg = WsEnvelope::new(
        "money_updated",
        serde_json::json!({"character_id": character_id, "copper": copper}),
    );
    state.hub.send_to_character(character_id, &msg).await;
    state.hub.send_to_host(&msg).await;
}

// ── Dice constraints (host, silent) ──────────────────────────────────────────

async fn handle_dice_constraint_set(
    character_id: Option<i64>,
    is_host: bool,
    allowed_die: Option<i64>,
    range_min: Option<i64>,
    range_max: Option<i64>,
    fixed_value: Option<i64>,
    always_over_half: bool,
    state: &AppState,
) {
    let is_host_int: i64 = if is_host { 1 } else { 0 };

    if is_host {
        sqlx::query("DELETE FROM dice_constraints WHERE is_host = 1")
            .execute(&state.db)
            .await
            .ok();
    } else if let Some(cid) = character_id {
        sqlx::query("DELETE FROM dice_constraints WHERE character_id = ? AND is_host = 0")
            .bind(cid)
            .execute(&state.db)
            .await
            .ok();
    }

    sqlx::query(
        "INSERT INTO dice_constraints
         (character_id, is_host, allowed_die, range_min, range_max, fixed_value, always_over_half)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(character_id)
    .bind(is_host_int)
    .bind(allowed_die)
    .bind(range_min)
    .bind(range_max)
    .bind(fixed_value)
    .bind(if always_over_half { 1i64 } else { 0i64 })
    .execute(&state.db)
    .await
    .ok();
}

async fn handle_dice_constraint_clear(
    character_id: Option<i64>,
    is_host: bool,
    state: &AppState,
) {
    if is_host {
        sqlx::query("DELETE FROM dice_constraints WHERE is_host = 1")
            .execute(&state.db)
            .await
            .ok();
    } else if let Some(cid) = character_id {
        sqlx::query("DELETE FROM dice_constraints WHERE character_id = ? AND is_host = 0")
            .bind(cid)
            .execute(&state.db)
            .await
            .ok();
    }
}
