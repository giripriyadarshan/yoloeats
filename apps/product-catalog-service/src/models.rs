use bson::serde_helpers::chrono_datetime_as_bson_datetime;
use chrono::{DateTime, Utc};
use mongodb::bson::oid::ObjectId;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Product {
    #[serde(rename = "_id", skip_serializing_if = "Option::is_none")]
    pub id: Option<ObjectId>,

    pub code: String, // Barcode is mandatory, and a string because it has leading zeros in mongodb
    pub product_name: Option<String>,
    pub generic_name: Option<String>,
    #[serde(rename = "brands_tags")]
    pub brands: Option<Vec<String>>,

    #[serde(rename = "categories_tags")]
    pub categories: Option<Vec<String>>,
    #[serde(rename = "main_category")]
    pub main_category: Option<String>,
    #[serde(rename = "labels_tags")]
    pub labels: Option<Vec<String>>,

    pub ingredients_text: Option<String>,
    #[serde(rename = "traces_tags")]
    pub traces_tags: Option<Vec<String>>,
    #[serde(default)]
    pub allergens_tags: Vec<String>,

    pub quantity: Option<String>, // Quantity contains number and unit ("500 g")
    pub image_url: Option<String>,
    pub image_small_url: Option<String>,
    #[serde(rename = "countries_tags")]
    pub countries: Option<Vec<String>>, // Need this to filter Germany (and maybe expand yoloeats to other countries)

    #[serde(rename = "nutrition_grade_fr")]
    pub nutrition_grade_fr: Option<String>,

    pub creator: Option<String>,
    pub source: Option<String>, // tracking origin of the data (e.g., OpenFoodFacts, user-contributed, etc.)

    #[serde(rename = "created_datetime", with = "chrono_datetime_as_bson_datetime")]
    pub created_at: DateTime<Utc>,
    #[serde(
        rename = "last_modified_datetime",
        with = "chrono_datetime_as_bson_datetime"
    )]
    pub last_modified_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreateProductPayload {
    pub code: String,
    pub product_name: Option<String>,
    pub ingredients_text: Option<String>,
    pub brands: Option<Vec<String>>,
    pub categories: Option<Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UpdateProductPayload {
    pub product_name: Option<String>,
    pub generic_name: Option<String>,
    pub image_url: Option<String>,
    pub ingredients_text: Option<String>,
    pub brands: Option<Vec<String>>,
    pub categories: Option<Vec<String>>,
    pub labels: Option<Vec<String>>,
    pub traces: Option<Vec<String>>,
    pub allergens_tags: Option<Vec<String>>, // Allow updating allergens
    pub quantity: Option<String>,
    pub countries: Option<Vec<String>>,
    pub nutrition_grade_fr: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct SearchParams {
    pub q: Option<String>,
    pub category: Option<String>,
    pub brand: Option<String>,
    pub label: Option<String>,
    pub country: Option<String>,
    pub nutriscore: Option<String>,
    pub limit: Option<u64>,
    pub offset: Option<u64>,
    #[serde(rename = "allergens")]
    pub user_allergens: Option<Vec<String>>,
    #[serde(rename = "diets")]
    pub user_diets: Option<Vec<String>>,
}
