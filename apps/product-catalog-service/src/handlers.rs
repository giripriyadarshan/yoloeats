use crate::{
    errors::{Result, ServiceError},
    models::{Product, SearchParams},
    state::AppState,
};
use axum::{
    extract::{Path, Query, State},
    Json,
};
use bson::{doc, oid::ObjectId};
use futures::stream::TryStreamExt;
use mongodb::options::FindOptions;
use redis::AsyncCommands;
use std::sync::Arc;
use tracing::{debug, error, info, instrument, warn};

const CACHE_EXPIRATION_SECONDS: u64 = 300;
const DEFAULT_SEARCH_LIMIT: u64 = 20;
const MAX_SEARCH_LIMIT: u64 = 100;

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

    match redis_conn.get::<_, String>(&cache_key).await {
        Ok(cached_product_json) if !cached_product_json.is_empty() => {
            match serde_json::from_str::<Product>(&cached_product_json) {
                Ok(product) => {
                    info!(id = %object_id, "Cache hit for product ID");
                    return Ok(Json(product));
                }
                Err(e) => {
                    error!(id = %object_id, "Failed to deserialize cached product (ID): {}. Fetching from DB.", e);
                }
            }
        },
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
                    .await {
                    Ok(_) => info!(id = %object_id, key = %cache_key, "Successfully cached product (ID) in Redis"),
                    Err(e) => warn!(id = %object_id, key = %cache_key, "Failed to cache product (ID) in Redis (SETEX): {}", e),
                }
            }
            Err(e) => warn!(id = %object_id, "Failed to serialize product for caching (ID): {}", e),
        }
        Ok(Json(product))
    } else {
        info!(id = %object_id, "Product not found by ID");
        Err(ServiceError::NotFound(format!("Product with ID {} not found", object_id)))
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
        },
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
                    .await {
                    Ok(_) => info!(code = %barcode, key = %cache_key, "Successfully cached product (code) in Redis"),
                    Err(e) => warn!(code = %barcode, key = %cache_key, "Failed to cache product (code) in Redis (SETEX): {}", e),
                }
            }
            Err(e) => warn!(code = %barcode, "Failed to serialize product for caching (code): {}", e),
        }

        Ok(Json(product))
    } else {
        info!(code = %barcode, "Product not found by barcode");
        Err(ServiceError::NotFound(format!("Product with barcode {} not found", barcode)))
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

    debug!("Constructed MongoDB filter: {:?}", filter);
    
    let limit = params.limit.unwrap_or(DEFAULT_SEARCH_LIMIT).min(MAX_SEARCH_LIMIT);
    let skip = params.offset.unwrap_or(0);
    let find_options = FindOptions::builder().limit(limit as i64).skip(skip).build();
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

    info!("Found {} products matching search criteria.", products.len());

    Ok(Json(products))
}