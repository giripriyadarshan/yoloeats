use bson::oid::ObjectId;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use validator::Validate;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum RiskLevel {
    Low,
    #[default]
    Medium,
    High,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct UserProfile {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<ObjectId>,

    pub user_id: String,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,

    #[serde(default)]
    pub allergens: Vec<String>,

    #[serde(default)]
    pub dietary_prefs: Vec<String>,

    #[serde(default)]
    pub risk_tolerance: RiskLevel,

    #[serde(with = "bson::serde_helpers::chrono_datetime_as_bson_datetime")]
    pub created_at: DateTime<Utc>,

    #[serde(with = "bson::serde_helpers::chrono_datetime_as_bson_datetime")]
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct UpdateProfilePayload {
    #[validate(length(min = 3, message = "Username must be at least 3 characters long"))]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,

    #[validate(email(message = "Invalid email format"))]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub allergens: Option<Vec<String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub dietary_prefs: Option<Vec<String>>,

    #[serde(skip_serializing_if = "Option::is_none")]
    pub risk_tolerance: Option<RiskLevel>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AllergenInfo {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
}
