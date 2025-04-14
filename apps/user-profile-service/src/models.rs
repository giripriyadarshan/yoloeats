use bson::{oid::ObjectId, DateTime};
use serde::{Deserialize, Serialize};


#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UserProfile {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<ObjectId>,
    pub username: String,
    pub email: String, // TODO: Add email validation
    #[serde(default)]
    pub allergies: Vec<String>,
    #[serde(default)]
    pub dietary_preferences: Vec<String>,
    pub created_at: DateTime,
    pub updated_at: DateTime,
}

impl UserProfile {
    pub fn new(username: String, email: String) -> Self {
        let now = DateTime::now();
        UserProfile {
            id: None, 
            username,
            email,
            allergies: Vec::new(),
            dietary_preferences: Vec::new(),
            created_at: now,
            updated_at: now,
        }
    }
}
