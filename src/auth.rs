use crate::{models::User, AppState};
use axum::{
    extract::FromRequestParts,
    http::{request::Parts, StatusCode},
};
use axum_extra::extract::CookieJar;
use sqlx::SqlitePool;
use uuid::Uuid;

pub async fn seed_host(pool: &SqlitePool) -> Result<(), sqlx::Error> {
    let username = std::env::var("HOST_USERNAME").unwrap_or_else(|_| "host".to_string());
    let pin = std::env::var("HOST_PIN").unwrap_or_else(|_| "0000".to_string());

    let existing: Option<User> =
        sqlx::query_as("SELECT * FROM users WHERE role = 'host'")
            .fetch_optional(pool)
            .await?;

    if existing.is_none() {
        let hashed = bcrypt::hash(&pin, bcrypt::DEFAULT_COST).expect("bcrypt failed");
        sqlx::query("INSERT INTO users (username, pin, role) VALUES (?, ?, 'host')")
            .bind(&username)
            .bind(&hashed)
            .execute(pool)
            .await?;
        tracing::info!("Host account created: {}", username);
    }

    Ok(())
}

pub async fn create_session(pool: &SqlitePool, user_id: i64) -> Result<String, sqlx::Error> {
    let token = Uuid::new_v4().to_string();
    sqlx::query("INSERT INTO sessions (token, user_id) VALUES (?, ?)")
        .bind(&token)
        .bind(user_id)
        .execute(pool)
        .await?;
    Ok(token)
}

pub async fn get_session_user(pool: &SqlitePool, token: &str) -> Option<User> {
    sqlx::query_as(
        "SELECT u.* FROM users u JOIN sessions s ON s.user_id = u.id WHERE s.token = ?",
    )
    .bind(token)
    .fetch_optional(pool)
    .await
    .ok()
    .flatten()
}

pub async fn delete_session(pool: &SqlitePool, token: &str) -> Result<(), sqlx::Error> {
    sqlx::query("DELETE FROM sessions WHERE token = ?")
        .bind(token)
        .execute(pool)
        .await?;
    Ok(())
}

#[derive(Clone)]
pub struct AuthUser {
    pub user: User,
    pub character_id: Option<i64>,
}

#[axum::async_trait]
impl FromRequestParts<AppState> for AuthUser {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let jar = CookieJar::from_headers(&parts.headers);
        let token = jar
            .get("session")
            .map(|c| c.value().to_string())
            .ok_or(StatusCode::UNAUTHORIZED)?;

        let user = get_session_user(&state.db, &token)
            .await
            .ok_or(StatusCode::UNAUTHORIZED)?;

        let character_id = if user.role == "player" {
            sqlx::query_scalar("SELECT id FROM characters WHERE user_id = ?")
                .bind(user.id)
                .fetch_optional(&state.db)
                .await
                .ok()
                .flatten()
        } else {
            None
        };

        Ok(AuthUser { user, character_id })
    }
}

#[allow(dead_code)]
pub struct HostOnly(pub AuthUser);

#[axum::async_trait]
impl FromRequestParts<AppState> for HostOnly {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = AuthUser::from_request_parts(parts, state).await?;
        if auth.user.role != "host" {
            return Err(StatusCode::FORBIDDEN);
        }
        Ok(HostOnly(auth))
    }
}
