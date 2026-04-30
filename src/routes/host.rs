use crate::{
    auth::HostOnly,
    models::{Ability, ChangeRequest, Character, DiceConstraint, InventoryItem},
    AppState,
};
use axum::{
    extract::{Path, State},
    response::IntoResponse,
    Json,
};

pub async fn get_all_players(
    _auth: HostOnly,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let characters: Vec<Character> =
        sqlx::query_as("SELECT * FROM characters ORDER BY id ASC")
            .fetch_all(&state.db)
            .await
            .unwrap_or_default();

    let mut result = Vec::new();
    for c in characters {
        let inventory: Vec<InventoryItem> =
            sqlx::query_as("SELECT * FROM inventory WHERE character_id = ? ORDER BY id ASC")
                .bind(c.id)
                .fetch_all(&state.db)
                .await
                .unwrap_or_default();

        let abilities: Vec<Ability> =
            sqlx::query_as("SELECT * FROM abilities WHERE character_id = ? ORDER BY id ASC")
                .bind(c.id)
                .fetch_all(&state.db)
                .await
                .unwrap_or_default();

        let constraint: Option<DiceConstraint> = sqlx::query_as(
            "SELECT * FROM dice_constraints WHERE character_id = ? AND is_host = 0 LIMIT 1",
        )
        .bind(c.id)
        .fetch_optional(&state.db)
        .await
        .unwrap_or(None);

        result.push(serde_json::json!({
            "character": c,
            "inventory": inventory,
            "abilities": abilities,
            "dice_constraint": constraint
        }));
    }

    Json(result).into_response()
}

pub async fn get_change_requests(
    _auth: HostOnly,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let requests: Vec<ChangeRequest> = sqlx::query_as(
        "SELECT cr.*, c.name as player_name
         FROM change_requests cr
         JOIN characters c ON c.id = cr.character_id
         WHERE cr.status = 'pending'
         ORDER BY cr.created_at ASC",
    )
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    Json(serde_json::to_value(requests).unwrap()).into_response()
}

pub async fn get_dice_constraints(
    _auth: HostOnly,
    State(state): State<AppState>,
    Path(character_id): Path<i64>,
) -> impl IntoResponse {
    let constraint: Option<DiceConstraint> = sqlx::query_as(
        "SELECT * FROM dice_constraints WHERE character_id = ? AND is_host = 0 LIMIT 1",
    )
    .bind(character_id)
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    Json(serde_json::to_value(constraint).unwrap()).into_response()
}

pub async fn get_host_constraint(
    _auth: HostOnly,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let constraint: Option<DiceConstraint> = sqlx::query_as(
        "SELECT * FROM dice_constraints WHERE is_host = 1 LIMIT 1",
    )
    .fetch_optional(&state.db)
    .await
    .unwrap_or(None);

    Json(serde_json::to_value(constraint).unwrap()).into_response()
}

pub async fn get_player_messages(
    _auth: HostOnly,
    State(state): State<AppState>,
    Path(character_id): Path<i64>,
) -> impl IntoResponse {
    let messages = sqlx::query_as::<_, crate::models::HostMessage>(
        "SELECT * FROM host_messages WHERE character_id = ? ORDER BY created_at ASC",
    )
    .bind(character_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    Json(serde_json::to_value(messages).unwrap()).into_response()
}
