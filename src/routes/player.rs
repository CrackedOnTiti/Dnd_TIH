use crate::{
    auth::AuthUser,
    models::{Ability, Character, HostMessage, InventoryItem, Note, PlayerMessage},
    AppState,
};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    Json,
};
use serde::Deserialize;

pub async fn get_me(auth: AuthUser) -> impl IntoResponse {
    Json(serde_json::json!({
        "id": auth.user.id,
        "username": auth.user.username,
        "role": auth.user.role,
        "character_id": auth.character_id
    }))
}

pub async fn get_my_character(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return (StatusCode::NOT_FOUND, Json(serde_json::json!({"error": "Pas de personnage"}))).into_response(),
    };

    match sqlx::query_as::<_, Character>("SELECT * FROM characters WHERE id = ?")
        .bind(char_id)
        .fetch_optional(&state.db)
        .await
    {
        Ok(Some(c)) => Json(serde_json::to_value(c).unwrap()).into_response(),
        _ => (StatusCode::NOT_FOUND, Json(serde_json::json!({"error": "Personnage introuvable"}))).into_response(),
    }
}

#[derive(Deserialize)]
pub struct CreateCharacterPayload {
    pub name: String,
    pub sex: Option<String>,
    pub age: Option<i64>,
    pub power1: Option<String>,
    pub power2: Option<String>,
    pub description: Option<String>,
    pub weapons: Option<String>,
}

pub async fn create_character(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<CreateCharacterPayload>,
) -> impl IntoResponse {
    if auth.character_id.is_some() {
        return (StatusCode::CONFLICT, Json(serde_json::json!({"error": "Vous avez deja un personnage"}))).into_response();
    }

    let id: i64 = sqlx::query_scalar(
        "INSERT INTO characters (user_id, name, sex, age, power1, power2, description, weapons)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING id",
    )
    .bind(auth.user.id)
    .bind(&payload.name)
    .bind(&payload.sex)
    .bind(payload.age)
    .bind(&payload.power1)
    .bind(&payload.power2)
    .bind(&payload.description)
    .bind(&payload.weapons)
    .fetch_one(&state.db)
    .await
    .expect("insert character failed");

    sqlx::query("INSERT INTO notes (character_id, content) VALUES (?, '')")
        .bind(id)
        .execute(&state.db)
        .await
        .ok();

    let character: Character = sqlx::query_as("SELECT * FROM characters WHERE id = ?")
        .bind(id)
        .fetch_one(&state.db)
        .await
        .expect("fetch character failed");

    // Notify host in real time
    state.hub.send_to_host(&crate::models::WsEnvelope::new(
        "character_created",
        serde_json::json!({
            "character":        &character,
            "inventory":        serde_json::json!([]),
            "abilities":        serde_json::json!([]),
            "dice_constraint":  serde_json::Value::Null
        }),
    )).await;

    (StatusCode::CREATED, Json(serde_json::to_value(character).unwrap())).into_response()
}

pub async fn get_host_messages(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return Json(serde_json::json!([])).into_response(),
    };

    let messages: Vec<HostMessage> = sqlx::query_as(
        "SELECT * FROM host_messages WHERE character_id = ? ORDER BY created_at ASC",
    )
    .bind(char_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    Json(serde_json::to_value(messages).unwrap()).into_response()
}

pub async fn get_player_dm(
    auth: AuthUser,
    State(state): State<AppState>,
    Path(other_id): Path<i64>,
) -> impl IntoResponse {
    let my_id = match auth.character_id {
        Some(id) => id,
        None => return Json(serde_json::json!([])).into_response(),
    };

    let messages: Vec<PlayerMessage> = sqlx::query_as(
        "SELECT * FROM player_messages
         WHERE (sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?)
         ORDER BY created_at ASC",
    )
    .bind(my_id)
    .bind(other_id)
    .bind(other_id)
    .bind(my_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    Json(serde_json::to_value(messages).unwrap()).into_response()
}

pub async fn get_players_list(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let my_id = auth.character_id.unwrap_or(-1);

    let rows = sqlx::query_as::<_, (i64, String)>(
        "SELECT c.id, c.name FROM characters c WHERE c.id != ?",
    )
    .bind(my_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let list: Vec<_> = rows
        .into_iter()
        .map(|(id, name)| serde_json::json!({"id": id, "name": name}))
        .collect();

    Json(list).into_response()
}

pub async fn get_notes(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return Json(serde_json::json!({"content": ""})).into_response(),
    };

    let note: Option<Note> =
        sqlx::query_as("SELECT * FROM notes WHERE character_id = ?")
            .bind(char_id)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

    Json(serde_json::json!({
        "content": note.map(|n| n.content).unwrap_or_default()
    }))
    .into_response()
}

#[derive(Deserialize)]
pub struct SaveNotesPayload {
    pub content: String,
}

pub async fn save_notes(
    auth: AuthUser,
    State(state): State<AppState>,
    Json(payload): Json<SaveNotesPayload>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return StatusCode::BAD_REQUEST.into_response(),
    };

    let existing: Option<Note> =
        sqlx::query_as("SELECT * FROM notes WHERE character_id = ?")
            .bind(char_id)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

    if existing.is_some() {
        sqlx::query("UPDATE notes SET content = ? WHERE character_id = ?")
            .bind(&payload.content)
            .bind(char_id)
            .execute(&state.db)
            .await
            .ok();
    } else {
        sqlx::query("INSERT INTO notes (character_id, content) VALUES (?, ?)")
            .bind(char_id)
            .bind(&payload.content)
            .execute(&state.db)
            .await
            .ok();
    }

    Json(serde_json::json!({"ok": true})).into_response()
}

pub async fn get_inventory(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return Json(serde_json::json!([])).into_response(),
    };

    let items: Vec<InventoryItem> =
        sqlx::query_as("SELECT * FROM inventory WHERE character_id = ? ORDER BY id ASC")
            .bind(char_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default();

    Json(serde_json::to_value(items).unwrap()).into_response()
}

pub async fn get_abilities(
    auth: AuthUser,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let char_id = match auth.character_id {
        Some(id) => id,
        None => return Json(serde_json::json!([])).into_response(),
    };

    let abilities: Vec<Ability> =
        sqlx::query_as("SELECT * FROM abilities WHERE character_id = ? ORDER BY id ASC")
            .bind(char_id)
            .fetch_all(&state.db)
            .await
            .unwrap_or_default();

    Json(serde_json::to_value(abilities).unwrap()).into_response()
}
