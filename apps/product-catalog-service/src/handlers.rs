use crate::{
    errors::{Result, ServiceError},
    models::{CreateProductPayload, Product, SearchParams, UpdateProductPayload},
    state::AppState,
};
use axum::{
    Json,
    extract::{Path, Query, State},
    http::StatusCode,
};
use bson::{doc, oid::ObjectId};
use chrono::Utc;
use futures::stream::TryStreamExt;
use mongodb::{
    error::ErrorKind,
    options::{FindOneAndUpdateOptions, FindOptions, ReturnDocument},
};
use redis::AsyncCommands;
use std::collections::HashSet;
use std::sync::Arc;
use tracing::{debug, error, info, instrument, warn};

use qdrant_client::qdrant::{
    Condition, FieldCondition, Filter, GetPointsBuilder, HasIdCondition, Match, PointId,
    RepeatedStrings, SearchPoints, WithPayloadSelector, condition::ConditionOneOf,
    r#match::MatchValue, value::Kind, vectors_output,
};
use reqwest::StatusCode as HttpStatus;

use serde::Deserialize;
use uuid::Uuid;

const CACHE_EXPIRATION_SECONDS: u64 = 300;
const DEFAULT_SEARCH_LIMIT: u64 = 20;
const MAX_SEARCH_LIMIT: u64 = 100;

const QDRANT_COLLECTION_NAME: &str = "product_vectors";
const QDRANT_CODE_PAYLOAD_KEY: &str = "code";

#[derive(Deserialize, Debug, Default)]
struct UserProfileResponse {
    #[serde(default)]
    allergens: Vec<String>,
    #[serde(default, rename = "dietaryPrefs")]
    dietary_prefs: Vec<String>,
}
fn product_id_cache_key(id: &ObjectId) -> String {
    format!("product:id:{}", id)
}

fn product_code_cache_key(code: &str) -> String {
    format!("product:code:{}", code)
}

#[instrument(skip(state), fields(id = %id_str))]
pub async fn get_product_by_id(
    State(state): State<Arc<AppState>>,
    Path(id_str): Path<String>,
) -> Result<Json<Product>> {
    info!("Attempting to get product by ID: {}", id_str);

    let object_id = ObjectId::parse_str(&id_str).map_err(|e| {
        error!("Invalid ObjectId format '{}': {}", id_str, e);
        ServiceError::BadRequest(format!("Invalid product ID format: {}", id_str))
    })?;
    debug!("Parsed ObjectId: {}", object_id);

    let cache_key = product_id_cache_key(&object_id);

    let mut redis_conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            error!("Failed to get async Redis connection: {}", e);
            warn!("Proceeding without cache check due to Redis connection error.");
            ServiceError::Redis(e)
        })?;

    match redis_conn.get::<_, Option<String>>(&cache_key).await {
        Ok(Some(cached_product_json_str)) if !cached_product_json_str.is_empty() => {
            match serde_json::from_str::<Product>(&cached_product_json_str) {
                Ok(product) => {
                    info!(id = %object_id, "Cache hit for product ID");
                    return Ok(Json(product));
                }
                Err(e) => {
                    error!(id = %object_id, "Failed to deserialize cached product (ID): {}. Fetching from DB.", e);
                }
            }
        }
        Ok(_) => {
            debug!(id = %object_id, "Cache miss for product ID (empty value).");
        }
        Err(e) => {
            warn!(id = %object_id, "Redis GET command failed (ID): {}. Fetching from DB.", e);
        }
    }

    debug!(id = %object_id, "Fetching product from MongoDB by ID");
    let collection = state.mongo_db.collection::<Product>("products");
    let db_product = collection
        .find_one(doc! { "_id": object_id })
        .await
        .map_err(|e| {
            error!(id = %object_id, "MongoDB find_one by ID failed: {}", e);
            ServiceError::MongoDb(e)
        })?;

    if let Some(product) = db_product {
        info!(id = %object_id, code = product.code, "Product found in DB by ID");

        match serde_json::to_string(&product) {
            Ok(product_json) => {
                match redis_conn
                    .set_ex::<_, _, ()>(&cache_key, &product_json, CACHE_EXPIRATION_SECONDS)
                    .await
                {
                    Ok(_) => {
                        info!(id = %object_id, key = %cache_key, "Successfully cached product (ID) in Redis")
                    }
                    Err(e) => {
                        warn!(id = %object_id, key = %cache_key, "Failed to cache product (ID) in Redis (SETEX): {}", e)
                    }
                }
            }
            Err(e) => warn!(id = %object_id, "Failed to serialize product for caching (ID): {}", e),
        }
        Ok(Json(product))
    } else {
        info!(id = %object_id, "Product not found by ID");
        Err(ServiceError::NotFound(format!(
            "Product with ID {} not found",
            object_id
        )))
    }
}

#[instrument(skip(state), fields(code = %barcode))]
pub async fn get_product_by_barcode(
    State(state): State<Arc<AppState>>,
    Path(barcode): Path<String>,
) -> Result<Json<Product>> {
    info!("Attempting to get product by barcode: {}", barcode);

    let cache_key = product_code_cache_key(&barcode);

    let mut redis_conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            error!("Failed to get async Redis connection: {}", e);
            warn!("Proceeding without cache check due to Redis connection error.");
            ServiceError::Redis(e)
        })?;

    match redis_conn.get::<_, String>(&cache_key).await {
        Ok(cached_product_json) if !cached_product_json.is_empty() => {
            match serde_json::from_str::<Product>(&cached_product_json) {
                Ok(product) => {
                    info!(code = %barcode, "Cache hit for product barcode");
                    return Ok(Json(product));
                }
                Err(e) => {
                    error!(code = %barcode, "Failed to deserialize cached product (code): {}. Fetching from DB.", e);
                }
            }
        }
        Ok(_) => {
            debug!(code = %barcode, "Cache miss for product barcode (empty value).");
        }
        Err(e) => {
            warn!(code = %barcode, "Redis GET command failed (code): {}. Fetching from DB.", e);
        }
    }

    debug!(code = %barcode, "Fetching product from MongoDB by barcode");
    let collection = state.mongo_db.collection::<Product>("products");
    let db_product = collection
        .find_one(doc! { "code": &barcode })
        .await
        .map_err(|e| {
            error!(code = %barcode, "MongoDB find_one by code failed: {}", e);
            ServiceError::MongoDb(e)
        })?;

    if let Some(product) = db_product {
        info!(id = product.id.as_ref().map(|id| id.to_string()).unwrap_or_default(), code = %barcode, "Product found in DB by barcode");

        match serde_json::to_string(&product) {
            Ok(product_json) => {
                match redis_conn
                    .set_ex::<_, _, ()>(&cache_key, &product_json, CACHE_EXPIRATION_SECONDS)
                    .await
                {
                    Ok(_) => {
                        info!(code = %barcode, key = %cache_key, "Successfully cached product (code) in Redis")
                    }
                    Err(e) => {
                        warn!(code = %barcode, key = %cache_key, "Failed to cache product (code) in Redis (SETEX): {}", e)
                    }
                }
            }
            Err(e) => {
                warn!(code = %barcode, "Failed to serialize product for caching (code): {}", e)
            }
        }

        Ok(Json(product))
    } else {
        info!(code = %barcode, "Product not found by barcode");
        Err(ServiceError::NotFound(format!(
            "Product with barcode {} not found",
            barcode
        )))
    }
}

#[instrument(skip(state, params), fields(query = ?params))]
pub async fn search_products(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SearchParams>,
) -> Result<Json<Vec<Product>>> {
    info!("Searching products with parameters: {:?}", params);

    let mut filter = doc! {};

    if let Some(q) = &params.q {
        if !q.trim().is_empty() {
            filter.insert("$text", doc! { "$search": q.trim() });
        }
    }
    if let Some(category) = &params.category {
        if !category.trim().is_empty() {
            filter.insert("categories_tags", category.trim());
        }
    }
    if let Some(brand) = &params.brand {
        if !brand.trim().is_empty() {
            filter.insert("brands_tags", brand.trim());
        }
    }
    if let Some(label) = &params.label {
        if !label.trim().is_empty() {
            filter.insert("labels_tags", label.trim());
        }
    }
    if let Some(country) = &params.country {
        if !country.trim().is_empty() {
            filter.insert("countries_tags", country.trim());
        }
    }
    if let Some(nutriscore) = &params.nutriscore {
        if !nutriscore.trim().is_empty() {
            filter.insert("nutrition_grade_fr", nutriscore.trim().to_lowercase());
        }
    }

    if let Some(user_allergens) = &params.user_allergens {
        if !user_allergens.is_empty() {
            info!("Applying allergen filter (excluding): {:?}", user_allergens);
            filter.insert("allergens_tags", doc! { "$nin": user_allergens });
        }
    }

    if let Some(user_diets) = &params.user_diets {
        if !user_diets.is_empty() {
            let user_diets_set: HashSet<&str> = user_diets.iter().map(String::as_str).collect();
            let mut conflicting_tags: Vec<&str> = Vec::new();
            if user_diets_set.contains("vegan") {
                conflicting_tags.extend(&[
                    "en:non-vegan",
                    "en:contains-milk",
                    "en:dairy",
                    "en:contains-eggs",
                    "en:eggs",
                    "en:contains-honey",
                    "en:honey",
                    "en:contains-meat",
                    "en:meat",
                    "en:contains-fish",
                    "en:fish",
                    "en:non-vegetarian",
                    "en:vegetarian-status-unknown",
                ]);
            } else if user_diets_set.contains("vegetarian") {
                conflicting_tags.extend(&[
                    "en:non-vegetarian",
                    "en:contains-meat",
                    "en:meat",
                    "en:contains-fish",
                    "en:fish",
                    "en:vegetarian-status-unknown",
                ]);
            }
            if user_diets_set.contains("gluten_free") {
                conflicting_tags.extend(&["en:contains-gluten", "en:gluten"]);
            }
            if user_diets_set.contains("lactose_free") {
                conflicting_tags.extend(&["en:contains-milk", "en:dairy"]);
            }
            conflicting_tags.sort();
            conflicting_tags.dedup();

            if !conflicting_tags.is_empty() {
                info!(
                    "Applying diet filter (excluding tags): {:?}",
                    conflicting_tags
                );
                filter.insert("labels_tags", doc! { "$nin": conflicting_tags });
            }
        }
    }
    debug!("Final MongoDB filter: {:?}", filter);
    let limit = params
        .limit
        .unwrap_or(DEFAULT_SEARCH_LIMIT)
        .min(MAX_SEARCH_LIMIT);
    let skip = params.offset.unwrap_or(0);
    let find_options = FindOptions::builder()
        .limit(limit as i64)
        .skip(skip)
        .build();
    debug!("Applying pagination: limit={}, skip={}", limit, skip);

    let collection = state.mongo_db.collection::<Product>("products");
    let cursor = collection
        .find(filter)
        .with_options(find_options)
        .await
        .map_err(|e| {
            error!("MongoDB find operation failed: {}", e);
            ServiceError::MongoDb(e)
        })?;

    let products: Vec<Product> = cursor.try_collect().await.map_err(|e| {
        error!("Error collecting results from MongoDB cursor: {}", e);
        ServiceError::MongoDb(e)
    })?;

    info!(
        "Search completed. Found {} products matching criteria.",
        products.len()
    );

    Ok(Json(products))
}

#[instrument(skip(state, payload), fields(code = %payload.code, name = ?payload.product_name))]
pub async fn create_product(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateProductPayload>,
) -> Result<(StatusCode, Json<Product>)> {
    info!("Attempting to create product");

    let now = Utc::now();
    let mut new_product = Product {
        id: None,
        code: payload.code,
        product_name: payload.product_name,
        generic_name: None,
        brands: payload.brands,
        quantity: None,
        categories: payload.categories,
        main_category: None,
        labels: None,
        ingredients_text: payload.ingredients_text,
        allergens_tags: Vec::new(),
        traces_tags: None,
        image_url: None,
        image_small_url: None,
        countries: None,
        nutrition_grade_fr: None,
        creator: Some("api_create".to_string()),
        source: Some("api_create_v1".to_string()),
        created_at: now,
        last_modified_at: now,
    };
    debug!(product = ?new_product, "Constructed new product struct");

    let collection = state.mongo_db.collection::<Product>("products");
    debug!("Obtained handle to collection: products");

    let insert_result = collection.insert_one(&new_product).await.map_err(|e| {
        if let ErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
            *e.kind.clone()
        {
            if write_error.code == 11000 {
                error!("Duplicate key error on insert: {}", e);
                return ServiceError::BadRequest(
                    "Product with this code already exists.".to_string(),
                );
            }
        }
        error!("Failed to insert product into DB: {}", e);
        ServiceError::MongoDb(e)
    })?;
    info!(
        "Successfully inserted new product with ID: {}",
        insert_result.inserted_id
    );

    // Assign the generated ID back to the product struct
    new_product.id = insert_result.inserted_id.as_object_id();

    info!(id = %new_product.id.unwrap(), "Returning created product");
    Ok((StatusCode::CREATED, Json(new_product)))
}

#[instrument(skip(state, payload), fields(id = %id_str))]
pub async fn update_product(
    State(state): State<Arc<AppState>>,
    Path(id_str): Path<String>,
    Json(payload): Json<UpdateProductPayload>,
) -> Result<Json<Product>> {
    info!("Attempting to update product ID: {}", id_str);

    let object_id = ObjectId::parse_str(&id_str).map_err(|e| {
        error!("Invalid ObjectId format '{}': {}", id_str, e);
        ServiceError::BadRequest(format!("Invalid product ID format: {}", id_str))
    })?;
    debug!("Parsed ObjectId: {}", object_id);

    let mut set_doc = doc! {};
    if let Some(val) = payload.product_name {
        set_doc.insert("product_name", val);
    }
    if let Some(val) = payload.generic_name {
        set_doc.insert("generic_name", val);
    }
    if let Some(val) = payload.image_url {
        set_doc.insert("image_url", val);
    }
    if let Some(val) = payload.ingredients_text {
        set_doc.insert("ingredients_text", val);
    }
    if let Some(val) = payload.brands {
        set_doc.insert("brands_tags", val);
    }
    if let Some(val) = payload.categories {
        set_doc.insert("categories_tags", val);
    }
    if let Some(val) = payload.labels {
        set_doc.insert("labels_tags", val);
    }
    if let Some(val) = payload.traces {
        set_doc.insert("traces_tags", val);
    }
    if let Some(val) = payload.quantity {
        set_doc.insert("quantity", val);
    }
    if let Some(val) = payload.countries {
        set_doc.insert("countries_tags", val);
    }
    if let Some(val) = payload.nutrition_grade_fr {
        set_doc.insert("nutrition_grade_fr", val);
    }

    if set_doc.is_empty() {
        warn!(id = %object_id, "Update request received with no fields to update.");
        let collection = state.mongo_db.collection::<Product>("products");
        return collection
            .find_one(doc! {"_id": object_id})
            .await
            .map_err(ServiceError::MongoDb)?
            .map(Json)
            .ok_or_else(|| {
                ServiceError::NotFound(format!("Product with ID {} not found", object_id))
            });
    }

    set_doc.insert("last_modified_datetime", Utc::now());

    let update_doc = doc! { "$set": set_doc };
    debug!(id = %object_id, update = ?update_doc, "Constructed update document");

    let collection = state.mongo_db.collection::<Product>("products");
    let options = FindOneAndUpdateOptions::builder()
        .return_document(ReturnDocument::After)
        .build();

    let update_result = collection
        .find_one_and_update(doc! {"_id": object_id}, update_doc)
        .with_options(options)
        .await;

    match update_result {
        Ok(Some(updated_product)) => {
            info!(id = %object_id, "Successfully updated product in DB");

            let id_key = product_id_cache_key(&object_id);
            let code_key = product_code_cache_key(&updated_product.code);

            debug!(id = %object_id, code=%updated_product.code, keys=format!("{}, {}", id_key, code_key), "Attempting to invalidate cache");
            match state.redis_client.get_multiplexed_async_connection().await {
                Ok(mut redis_conn) => {
                    match redis::cmd("DEL")
                        .arg(&[&id_key, &code_key])
                        .query_async::<i64>(&mut redis_conn)
                        .await
                    {
                        Ok(deleted_count) => {
                            info!(id = %object_id, count=deleted_count, "Cache invalidation DEL command successful ({} keys)", deleted_count)
                        }
                        Err(e) => {
                            warn!(id = %object_id, "Failed to invalidate cache (DEL command failed): {}", e)
                        }
                    }
                }
                Err(e) => {
                    warn!(id = %object_id, "Failed to get Redis connection for cache invalidation: {}", e)
                }
            }

            Ok(Json(updated_product))
        }
        Ok(None) => {
            error!(id = %object_id, "Product not found for update");
            Err(ServiceError::NotFound(format!(
                "Product with ID {} not found for update",
                object_id
            )))
        }
        Err(e) => {
            if let ErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
                *e.kind.clone()
            {
                if write_error.code == 11000 {
                    error!("Duplicate key error on update: {}", e);
                    return Err(ServiceError::BadRequest(
                        "Update failed due to duplicate key (e.g., code already exists)."
                            .to_string(),
                    ));
                }
            }
            error!(id = %object_id, "Failed to update product in DB: {}", e);
            Err(ServiceError::MongoDb(e))
        }
    }
}

#[instrument(skip(state), fields(id = %id_str))]
pub async fn delete_product(
    State(state): State<Arc<AppState>>,
    Path(id_str): Path<String>,
) -> Result<StatusCode> {
    info!("Attempting to delete product ID: {}", id_str);

    let object_id = ObjectId::parse_str(&id_str).map_err(|e| {
        error!("Invalid ObjectId format '{}': {}", id_str, e);
        ServiceError::BadRequest(format!("Invalid product ID format: {}", id_str))
    })?;
    debug!("Parsed ObjectId: {}", object_id);

    let collection = state.mongo_db.collection::<Product>("products");

    let product_to_delete = collection
        .find_one(doc! { "_id": object_id })
        .projection(doc! { "code": 1 })
        .await
        .map_err(|e| {
            error!(id = %object_id, "MongoDB find_one before delete failed: {}", e);
            ServiceError::MongoDb(e)
        })?;

    let product_code = match product_to_delete {
        Some(p) => p.code,
        None => {
            info!(id = %object_id, "Product not found for deletion");
            return Err(ServiceError::NotFound(format!(
                "Product with ID {} not found for deletion",
                object_id
            )));
        }
    };
    debug!(id = %object_id, code = %product_code, "Found product code for cache invalidation");

    let delete_result = collection
        .delete_one(doc! { "_id": object_id })
        .await
        .map_err(|e| {
            error!(id = %object_id, "MongoDB delete_one failed: {}", e);
            ServiceError::MongoDb(e)
        })?;

    if delete_result.deleted_count > 0 {
        info!(id = %object_id, code=%product_code, "Successfully deleted product from DB");

        let id_key = product_id_cache_key(&object_id);
        let code_key = product_code_cache_key(&product_code);

        debug!(id = %object_id, code=%product_code, keys=format!("{}, {}", id_key, code_key), "Attempting to invalidate cache");
        match state.redis_client.get_multiplexed_async_connection().await {
            Ok(mut redis_conn) => {
                match redis::cmd("DEL")
                    .arg(&[&id_key, &code_key])
                    .query_async::<i64>(&mut redis_conn)
                    .await
                {
                    Ok(deleted_count) => {
                        info!(id = %object_id, count=deleted_count, "Cache invalidation DEL command successful ({} keys)", deleted_count)
                    }
                    Err(e) => {
                        warn!(id = %object_id, "Failed to invalidate cache (DEL command failed): {}", e)
                    }
                }
            }
            Err(e) => {
                warn!(id = %object_id, "Failed to get Redis connection for cache invalidation: {}", e)
            }
        }

        Ok(StatusCode::NO_CONTENT)
    } else {
        warn!(id = %object_id, "Product found initially but delete_one reported 0 deleted count.");
        Err(ServiceError::NotFound(format!(
            "Product with ID {} found but failed to delete",
            object_id
        )))
    }
}

#[instrument(skip(state), fields(product_id = %product_id_str))]
pub async fn get_recommendations(
    State(state): State<Arc<AppState>>,
    Path(product_id_str): Path<String>, // This is the MongoDB ObjectId string of the source product
) -> Result<Json<Vec<Product>>> {
    info!(
        "Received recommendation request for source product (Mongo OID): {}",
        product_id_str
    );

    let source_qdrant_uuid = Uuid::new_v5(&Uuid::NAMESPACE_DNS, product_id_str.as_bytes());
    let source_qdrant_uuid_str = source_qdrant_uuid.to_string();
    let target_point_id_for_qdrant_vector_fetch: PointId = source_qdrant_uuid_str.clone().into();

    debug!(
        "Source product Mongo OID: {}, Qdrant UUID for vector fetch: {}",
        product_id_str, source_qdrant_uuid_str
    );

    let get_request = GetPointsBuilder::new(
        QDRANT_COLLECTION_NAME.to_string(),
        vec![target_point_id_for_qdrant_vector_fetch.clone()],
    )
    .with_payload(false)
    .with_vectors(true);

    let retrieve_result = state.qdrant_client.get_points(get_request).await?;

    let target_vector = retrieve_result
        .result
        .into_iter()
        .next()
        .and_then(|point| point.vectors)
        .and_then(|vectors| vectors.vectors_options)
        .and_then(|options| match options {
            vectors_output::VectorsOptions::Vector(v) => Some(v.data),
            _ => None,
        })
        .ok_or_else(|| {
            error!(
                "Target product vector not found in Qdrant for source Mongo OID: {} (Qdrant UUID: {})",
                product_id_str, source_qdrant_uuid_str
            );
            ServiceError::NotFound(format!(
                "Vector data not found for product OID {}",
                product_id_str
            ))
        })?;

    if target_vector.is_empty() {
        error!(
            "Retrieved empty target vector for source Mongo OID: {}",
            product_id_str
        );
        return Err(ServiceError::Internal(format!(
            "Empty vector found for product OID {}",
            product_id_str
        )));
    }
    debug!(
        "Target vector for source product (Mongo OID: {}) retrieved successfully (size: {})",
        product_id_str,
        target_vector.len()
    );

    const DUMMY_USER_ID: &str = "dummy-user-123";
    warn!(
        user_id = DUMMY_USER_ID,
        "Using DUMMY user ID for profile fetch. Replace with actual authenticated user ID."
    );

    let profile_url = format!(
        "{}/api/v1/users/{}/profile",
        state.user_profile_service_url, DUMMY_USER_ID
    );
    debug!("Fetching user profile from: {}", profile_url);

    let profile_resp = state
        .http_client
        .get(&profile_url)
        .send()
        .await
        .map_err(ServiceError::Reqwest)?;
    let (user_allergens, user_diets) = match profile_resp.status() {
        HttpStatus::OK => {
            let profile = profile_resp
                .json::<UserProfileResponse>()
                .await
                .map_err(|e| {
                    error!("Failed to deserialize user profile JSON: {}", e);
                    ServiceError::Internal(format!("Failed to parse profile data: {}", e))
                })?;
            debug!(allergens = ?profile.allergens, diets = ?profile.dietary_prefs, "User profile fetched successfully");
            (profile.allergens, profile.dietary_prefs)
        }
        HttpStatus::NOT_FOUND => {
            warn!(
                user_id = DUMMY_USER_ID,
                "User profile not found. Proceeding without personalization filters."
            );
            (Vec::new(), Vec::new())
        }
        status => {
            let error_body = profile_resp
                .text()
                .await
                .unwrap_or_else(|_| "Failed to read error body".to_string());
            error!(%status, body = %error_body, "User profile service request failed");
            return Err(ServiceError::Internal(format!(
                "User profile service failed with status {}",
                status
            )));
        }
    };

    let mut must_not_conditions: Vec<Condition> = Vec::new();
    must_not_conditions.push(Condition {
        condition_one_of: Some(ConditionOneOf::HasId(HasIdCondition {
            has_id: vec![target_point_id_for_qdrant_vector_fetch.clone()],
        })),
    });

    if !user_allergens.is_empty() {
        debug!(
            "Adding Qdrant filter for user_allergens on 'labels_tags': {:?}",
            user_allergens
        );
        must_not_conditions.push(Condition {
            condition_one_of: Some(ConditionOneOf::Field(FieldCondition {
                key: "labels_tags".to_string(), // Ensure this field is indexed for filtering in Qdrant
                r#match: Some(qdrant_client::qdrant::Match {
                    // Corrected: direct struct instantiation
                    match_value: Some(MatchValue::Keywords(RepeatedStrings {
                        strings: user_allergens,
                    })),
                }),
                ..Default::default() // Use default for other FieldCondition fields
            })),
        });
    }

    if user_diets.contains(&"vegan".to_string()) {
        debug!("Adding Qdrant filter for vegan diet (excluding 'non-vegan' from 'labels_tags')");
        let diet_exclusion_tags = vec!["non-vegan".to_string()]; // Example, adjust as per your tags
        must_not_conditions.push(Condition {
            condition_one_of: Some(ConditionOneOf::Field(FieldCondition {
                key: "labels_tags".to_string(), // Ensure this field is indexed
                r#match: Some(qdrant_client::qdrant::Match {
                    // Corrected: direct struct instantiation
                    match_value: Some(MatchValue::Keywords(RepeatedStrings {
                        strings: diet_exclusion_tags,
                    })),
                }),
                ..Default::default()
            })),
        });
    }

    let qdrant_filter = Filter {
        must: vec![],
        must_not: must_not_conditions,
        should: vec![],
        min_should: None,
    };
    debug!("Constructed Qdrant filter: {:?}", qdrant_filter);

    let search_request = SearchPoints {
        collection_name: QDRANT_COLLECTION_NAME.into(),
        vector: target_vector,
        filter: Some(qdrant_filter),
        limit: 20,
        offset: Some(0),
        with_payload: Some(WithPayloadSelector {
            selector_options: Some(
                qdrant_client::qdrant::with_payload_selector::SelectorOptions::Enable(true),
            ),
        }),
        with_vectors: None,
        score_threshold: None,
        params: None,
        vector_name: None,
        read_consistency: None,
        timeout: None,
        shard_key_selector: None,
        sparse_indices: None,
    };

    info!("Performing Qdrant similarity search...");
    let search_result = state.qdrant_client.search_points(search_request).await?;
    debug!(
        "Qdrant search returned {} results",
        search_result.result.len()
    );

    let mut candidate_barcodes: Vec<String> = Vec::new();
    for scored_point in search_result.result {
        if let Some(payload_value) = scored_point.payload.get(QDRANT_CODE_PAYLOAD_KEY) {
            if let Some(Kind::StringValue(barcode_str)) = &payload_value.kind {
                if !barcode_str.is_empty() {
                    candidate_barcodes.push(barcode_str.clone());
                } else {
                    warn!(
                        "Qdrant point ID {:?} had empty '{}' in payload.",
                        scored_point.id, QDRANT_CODE_PAYLOAD_KEY
                    );
                }
            } else {
                warn!(
                    "Qdrant payload field '{}' was not a StringValue for point ID: {:?}",
                    QDRANT_CODE_PAYLOAD_KEY, scored_point.id
                );
            }
        } else {
            warn!(
                "Qdrant point ID {:?} missing '{}' in payload",
                scored_point.id, QDRANT_CODE_PAYLOAD_KEY
            );
        }
    }

    if candidate_barcodes.is_empty() {
        info!("No suitable candidates found after Qdrant search (no valid barcodes extracted).");
        return Ok(Json(vec![]));
    }

    let unique_candidate_barcodes: Vec<String> = candidate_barcodes
        .into_iter()
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    debug!(
        "Unique candidate barcodes from Qdrant: {:?}",
        unique_candidate_barcodes
    );

    const FINAL_RECOMMENDATION_LIMIT: usize = 10;
    let final_barcodes_to_fetch: Vec<String> = unique_candidate_barcodes
        .into_iter()
        .take(FINAL_RECOMMENDATION_LIMIT)
        .collect();

    if final_barcodes_to_fetch.is_empty() {
        info!("No barcodes to fetch from MongoDB after limiting.");
        return Ok(Json(vec![]));
    }

    info!(
        "Fetching details for up to {} products by barcode from MongoDB",
        final_barcodes_to_fetch.len()
    );

    let mongo_filter = doc! { "code": { "$in": final_barcodes_to_fetch } };
    let collection = state.mongo_db.collection::<Product>("products");

    let cursor = collection
        .find(mongo_filter)
        .limit(FINAL_RECOMMENDATION_LIMIT as i64)
        .await?;
    let recommended_products: Vec<Product> = cursor.try_collect().await?;

    info!(
        "Returning {} recommended products.",
        recommended_products.len()
    );
    Ok(Json(recommended_products))
}
