use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserProfileData {
    pub user_id: String,
    #[serde(default)]
    pub allergens: HashSet<String>,
    #[serde(default)]
    pub dietary_prefs: HashSet<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProductData {
    pub id: Option<String>,
    pub barcode: Option<String>,
    pub ingredients_text: Option<String>,
    #[serde(default)]
    pub traces_tags: Vec<String>,
    #[serde(default)]
    pub labels_tags: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckRequest {
    pub product_identifier: String,
    pub user_id: String,
}

#[derive(Debug, Serialize, Clone, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum SafetyStatus {
    Safe,
    Unsafe,
    Caution,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckResult {
    pub status: SafetyStatus,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub conflicting_allergens: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub conflicting_diets: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub trace_allergens: Vec<String>,
    pub is_offline_result: bool, // Indicate if result was based on cached/offline data (TODO)
}
