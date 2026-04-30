use crate::{auth as session, models::User, AppState};
use axum::{extract::State, http::StatusCode, response::IntoResponse, Json};
use axum_extra::extract::cookie::{Cookie, CookieJar, SameSite};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct LoginPayload {
    pub username: String,
    pub pin: String,
}

pub async fn login(
    State(state): State<AppState>,
    jar: CookieJar,
    Json(payload): Json<LoginPayload>,
) -> impl IntoResponse {
    let user: Option<User> =
        sqlx::query_as("SELECT * FROM users WHERE username = ?")
            .bind(&payload.username)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

    let user = match user {
        Some(u) => u,
        None => return (StatusCode::UNAUTHORIZED, jar, Json(serde_json::json!({"error": "Identifiants invalides"}))).into_response(),
    };

    let ok = bcrypt::verify(&payload.pin, &user.pin).unwrap_or(false);
    if !ok {
        return (StatusCode::UNAUTHORIZED, jar, Json(serde_json::json!({"error": "Identifiants invalides"}))).into_response();
    }

    let token = session::create_session(&state.db, user.id)
        .await
        .expect("session create failed");

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

    let cookie = Cookie::build(("session", token))
        .http_only(true)
        .same_site(SameSite::Lax)
        .path("/")
        .build();

    let jar = jar.add(cookie);
    (
        StatusCode::OK,
        jar,
        Json(serde_json::json!({
            "role": user.role,
            "username": user.username,
            "character_id": character_id
        })),
    )
        .into_response()
}

pub async fn register(
    State(state): State<AppState>,
    jar: CookieJar,
    Json(payload): Json<LoginPayload>,
) -> impl IntoResponse {
    if payload.pin.len() != 4 || !payload.pin.chars().all(|c| c.is_ascii_digit()) {
        return (StatusCode::BAD_REQUEST, jar, Json(serde_json::json!({"error": "Le mot de passe doit comporter 4 chiffres"}))).into_response();
    }

    let existing: Option<User> =
        sqlx::query_as("SELECT * FROM users WHERE username = ?")
            .bind(&payload.username)
            .fetch_optional(&state.db)
            .await
            .unwrap_or(None);

    if existing.is_some() {
        return (StatusCode::CONFLICT, jar, Json(serde_json::json!({"error": "Ce nom d'utilisateur existe deja"}))).into_response();
    }

    let hashed = bcrypt::hash(&payload.pin, bcrypt::DEFAULT_COST).expect("bcrypt failed");
    let user_id: i64 = sqlx::query_scalar(
        "INSERT INTO users (username, pin, role) VALUES (?, ?, 'player') RETURNING id",
    )
    .bind(&payload.username)
    .bind(&hashed)
    .fetch_one(&state.db)
    .await
    .expect("insert user failed");

    let token = session::create_session(&state.db, user_id)
        .await
        .expect("session create failed");

    let cookie = Cookie::build(("session", token))
        .http_only(true)
        .same_site(SameSite::Lax)
        .path("/")
        .build();

    let jar = jar.add(cookie);
    (
        StatusCode::CREATED,
        jar,
        Json(serde_json::json!({
            "role": "player",
            "username": payload.username,
            "character_id": null
        })),
    )
        .into_response()
}

pub async fn logout(
    State(state): State<AppState>,
    jar: CookieJar,
) -> impl IntoResponse {
    if let Some(cookie) = jar.get("session") {
        let _ = session::delete_session(&state.db, cookie.value()).await;
    }
    let jar = jar.remove("session");
    (StatusCode::OK, jar, Json(serde_json::json!({"ok": true}))).into_response()
}
