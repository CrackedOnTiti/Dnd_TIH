use axum::extract::ws::Message;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};

pub struct ClientInfo {
    pub user_id: i64,
    pub role: String,
    pub character_id: Option<i64>,
    pub tx: mpsc::UnboundedSender<Message>,
}

pub struct Hub {
    pub clients: Arc<RwLock<HashMap<i64, ClientInfo>>>,
}

impl Hub {
    pub fn new() -> Self {
        Hub {
            clients: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub async fn register(&self, info: ClientInfo) {
        let mut clients = self.clients.write().await;
        clients.insert(info.user_id, info);
    }

    pub async fn unregister(&self, user_id: i64) {
        let mut clients = self.clients.write().await;
        clients.remove(&user_id);
    }

    pub async fn send_to_user(&self, user_id: i64, msg: &str) {
        let clients = self.clients.read().await;
        if let Some(client) = clients.get(&user_id) {
            let _ = client.tx.send(Message::Text(msg.to_string()));
        }
    }

    pub async fn send_to_character(&self, character_id: i64, msg: &str) {
        let clients = self.clients.read().await;
        for client in clients.values() {
            if client.character_id == Some(character_id) {
                let _ = client.tx.send(Message::Text(msg.to_string()));
                break;
            }
        }
    }

    pub async fn send_to_host(&self, msg: &str) {
        let clients = self.clients.read().await;
        for client in clients.values() {
            if client.role == "host" {
                let _ = client.tx.send(Message::Text(msg.to_string()));
            }
        }
    }

    pub async fn send_to_all_players(&self, msg: &str) {
        let clients = self.clients.read().await;
        for client in clients.values() {
            if client.role == "player" {
                let _ = client.tx.send(Message::Text(msg.to_string()));
            }
        }
    }

    pub async fn send_to_all(&self, msg: &str) {
        let clients = self.clients.read().await;
        for client in clients.values() {
            let _ = client.tx.send(Message::Text(msg.to_string()));
        }
    }

    pub async fn get_connected_character_ids(&self) -> Vec<i64> {
        let clients = self.clients.read().await;
        clients
            .values()
            .filter_map(|c| c.character_id)
            .collect()
    }
}
