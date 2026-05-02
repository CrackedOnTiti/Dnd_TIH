mod auth;
mod db;
mod models;
mod routes;
mod ws;

use axum::{
    routing::{get, post},
    Router,
};
use sqlx::SqlitePool;
use std::sync::Arc;
use tower_http::services::ServeDir;

use crate::ws::Hub;

#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub hub: Arc<Hub>,
}

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    tracing_subscriber::fmt()
        .with_env_filter(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        )
        .init();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "sqlite:./data/dnd.db".to_string());

    let pool = db::init(&database_url)
        .await
        .expect("Failed to initialize database");

    auth::seed_host(&pool)
        .await
        .expect("Failed to seed host account");

    auth::seed_players(&pool)
        .await
        .expect("Failed to seed player accounts");

    let hub = Arc::new(Hub::new());
    let state = AppState { db: pool, hub };

    let app = Router::new()
        // Auth
        .route("/auth/login", post(routes::auth::login))
        .route("/auth/logout", post(routes::auth::logout))
        .route("/auth/register", post(routes::auth::register))
        // Player API
        .route("/api/me", get(routes::player::get_me))
        .route("/api/character", get(routes::player::get_my_character))
        .route("/api/character/create", post(routes::player::create_character))
        .route("/api/messages/host", get(routes::player::get_host_messages))
        .route("/api/messages/player/:id", get(routes::player::get_player_dm))
        .route("/api/players", get(routes::player::get_players_list))
        .route("/api/notes", get(routes::player::get_notes).post(routes::player::save_notes))
        .route("/api/inventory", get(routes::player::get_inventory))
        .route("/api/abilities", get(routes::player::get_abilities))
        .route("/api/specials", get(routes::player::get_specials))
        // Host API
        .route("/api/host/players", get(routes::host::get_all_players))
        .route("/api/host/change_requests", get(routes::host::get_change_requests))
        .route("/api/host/constraints/:id", get(routes::host::get_dice_constraints))
        .route("/api/host/constraint/self", get(routes::host::get_host_constraint))
        .route("/api/host/messages/:id", get(routes::host::get_player_messages))
        // WebSocket
        .route("/ws", get(routes::ws_handler::ws_handler))
        // Static files
        .fallback_service(ServeDir::new("static"))
        .with_state(state);

    let addr = std::env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:3000".to_string());
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    tracing::info!("Listening on {}", addr);
    axum::serve(listener, app).await.unwrap();
}
