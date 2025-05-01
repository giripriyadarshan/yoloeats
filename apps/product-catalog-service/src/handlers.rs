use crate::models::{CreateProductPayload, UpdateProductPayload};
use crate::{
    errors::{Result, ServiceError},
    models::{Product, SearchParams},
    state::AppState,
};
use axum::http::StatusCode;
use axum::{
    Json,
    extract::{Path, Query, State},
};
use bson::{doc, oid::ObjectId};
use chrono::Utc;
use futures::stream::TryStreamExt;
use mongodb::options::FindOptions;
use mongodb::{
    error::ErrorKind,
    options::{FindOneAndUpdateOptions, ReturnDocument},
};
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

    debug!("Constructed MongoDB filter: {:?}", filter);

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
        "Found {} products matching search criteria.",
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

    // TODO: Add payload validation using `validator` if enabled in models.rs
    // payload.validate().map_err(|e| ... ServiceError::BadRequest(...))?;

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
        allergens_tags: None,
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
