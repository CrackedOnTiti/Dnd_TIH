use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub id: i64,
    pub username: String,
    pub pin: String,
    pub role: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Character {
    pub id: i64,
    pub user_id: i64,
    pub name: String,
    pub sex: Option<String>,
    pub age: Option<i64>,
    pub power1: Option<String>,
    pub power2: Option<String>,
    pub description: Option<String>,
    pub weapons: Option<String>,
    pub curr_hp: i64,
    pub max_hp: i64,
    pub curr_stam: i64,
    pub max_stam: i64,
    pub copper: i64,
    pub last_roll: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ChangeRequest {
    pub id: i64,
    pub character_id: i64,
    pub req_type: String,
    pub payload: String,
    pub status: String,
    pub host_note: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Ability {
    pub id: i64,
    pub character_id: i64,
    pub name: String,
    pub description: Option<String>,
    pub drain_type: Option<String>,
    pub drain_value: Option<i64>,
    pub confirmed: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct InventoryItem {
    pub id: i64,
    pub character_id: i64,
    pub item_name: String,
    pub amount: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Note {
    pub id: i64,
    pub character_id: i64,
    pub content: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct HostMessage {
    pub id: i64,
    pub character_id: i64,
    pub sender: String,
    pub content: String,
    pub mode: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PlayerMessage {
    pub id: i64,
    pub sender_id: i64,
    pub receiver_id: i64,
    pub content: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct DiceConstraint {
    pub id: i64,
    pub character_id: Option<i64>,
    pub is_host: i64,
    pub allowed_die: Option<i64>,
    pub range_min: Option<i64>,
    pub range_max: Option<i64>,
    pub fixed_value: Option<i64>,
    pub always_over_half: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WsEnvelope {
    #[serde(rename = "type")]
    pub event_type: String,
    pub data: serde_json::Value,
}

impl WsEnvelope {
    pub fn new(event_type: &str, data: impl Serialize) -> String {
        serde_json::to_string(&serde_json::json!({
            "type": event_type,
            "data": data
        }))
        .unwrap_or_default()
    }
}
