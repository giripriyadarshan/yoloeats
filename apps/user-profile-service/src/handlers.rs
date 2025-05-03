use crate::{
    errors::{AppError, Result},
    models::{AllergenInfo, UpdateProfilePayload, UserProfile},
    state::AppState,
};
use axum::{Json, extract::State};
use bson::doc;
use chrono::Utc;
use mongodb::{
    Collection,
    error::ErrorKind,
    options::{FindOneAndUpdateOptions, ReturnDocument},
};
use redis::AsyncCommands;
use std::sync::Arc;
use tracing::{debug, error, info, instrument, warn};
use validator::Validate;

// TODO: Replace with actual user ID from authentication context
const DUMMY_USER_ID: &str = "dummy-user-123";
const PROFILE_CACHE_KEY_PREFIX: &str = "profile:";
const CACHE_EXPIRATION_SECONDS: u64 = 3600;

fn profile_cache_key(user_id: &str) -> String {
    format!("{}{}", PROFILE_CACHE_KEY_PREFIX, user_id)
}

#[instrument(skip(state), fields(user_id = DUMMY_USER_ID))] // Log hardcoded ID for now
pub async fn get_profile(State(state): State<Arc<AppState>>) -> Result<Json<UserProfile>> {
    // TODO: Extract actual user_id from token/session/authentication context
    let user_id = DUMMY_USER_ID;
    info!("Attempting to get profile for user_id: {}", user_id);

    let cache_key = profile_cache_key(user_id);

    let mut redis_conn = state.redis_client.get_multiplexed_async_connection().await
        .map_err(|e| {
            warn!(user_id = %user_id, "Failed to get Redis connection: {}. Proceeding without cache.", e);
            AppError::Redis(e)
        })?;

    match redis_conn.get::<_, String>(&cache_key).await {
        Ok(cached_profile_json) if !cached_profile_json.is_empty() => {
            match serde_json::from_str::<UserProfile>(&cached_profile_json) {
                Ok(profile) => {
                    info!(user_id = %user_id, "Cache hit for user profile");
                    return Ok(Json(profile));
                }
                Err(e) => {
                    error!(user_id = %user_id, "Failed to deserialize cached profile: {}. Fetching from DB.", e);
                }
            }
        }
        Ok(_) => {
            debug!(user_id = %user_id, "Cache miss for user profile.");
        }
        Err(e) => {
            warn!(user_id = %user_id, "Redis GET command failed: {}. Fetching from DB.", e);
        }
    }

    debug!(user_id = %user_id, "Fetching profile from MongoDB");
    let collection = state.mongo_db.collection::<UserProfile>("user_profiles");
    let filter = doc! { "user_id": user_id };

    let db_profile = collection.find_one(filter).await.map_err(|e| {
        error!(user_id = %user_id, "MongoDB find_one failed: {}", e);
        AppError::MongoDb(e)
    })?;

    match db_profile {
        Some(profile) => {
            info!(user_id = %user_id, "Profile found in DB");
            match serde_json::to_string(&profile) {
                Ok(profile_json) => {
                    match redis_conn
                        .set_ex::<_, _, ()>(&cache_key, &profile_json, CACHE_EXPIRATION_SECONDS)
                        .await
                    {
                        Ok(_) => {
                            info!(user_id = %user_id, key = %cache_key, "Successfully cached profile in Redis")
                        }
                        Err(e) => {
                            warn!(user_id = %user_id, key = %cache_key, "Failed to cache profile in Redis (SETEX): {}", e)
                        }
                    }
                }
                Err(e) => {
                    warn!(user_id = %user_id, "Failed to serialize profile for caching: {}", e)
                }
            }
            Ok(Json(profile))
        }
        None => {
            info!(user_id = %user_id, "Profile not found in DB");
            Err(AppError::NotFound(format!(
                "Profile for user {} not found",
                user_id
            )))
        }
    }
}

#[instrument(skip(state, payload), fields(user_id = DUMMY_USER_ID))] // Log hardcoded ID for now
pub async fn update_profile(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<UpdateProfilePayload>,
) -> Result<Json<UserProfile>> {
    // TODO: Extract actual user_id from token/session/authentication context
    let user_id = DUMMY_USER_ID;
    info!("Attempting to update profile for user_id: {}", user_id);

    payload.validate().map_err(|e| {
        error!(user_id = %user_id, "Payload validation failed: {}", e);
        AppError::BadRequest(format!("Input validation failed: {}", e).replace('\n', ", "))
    })?;
    debug!(user_id = %user_id, "Payload validated successfully");

    let mut set_doc = doc! {};
    if let Some(val) = payload.username {
        set_doc.insert("username", val);
    }
    if let Some(val) = payload.email {
        set_doc.insert("email", val);
    }
    if let Some(val) = payload.allergens {
        set_doc.insert("allergens", val);
    }
    if let Some(val) = payload.dietary_prefs {
        set_doc.insert("dietary_prefs", val);
    }
    if let Some(val) = payload.risk_tolerance {
        set_doc.insert("risk_tolerance", bson::to_bson(&val)?);
    }

    if set_doc.is_empty() {
        warn!(user_id = %user_id, "Update request received with no fields to update.");
        return Err(AppError::BadRequest(
            "No fields provided for update.".to_string(),
        ));
    }

    let now = Utc::now();
    set_doc.insert("updated_at", now);

    let set_on_insert_doc = doc! {
        "user_id": user_id,
        "created_at": now
    };

    let update_doc = doc! {
        "$set": set_doc,
        "$setOnInsert": set_on_insert_doc
    };
    debug!(user_id = %user_id, update = ?update_doc, "Constructed upsert document");

    let collection: Collection<UserProfile> = state.mongo_db.collection("user_profiles");
    let filter = doc! { "user_id": user_id };
    let options = FindOneAndUpdateOptions::builder()
        .upsert(true)
        .return_document(ReturnDocument::After)
        .build();

    let update_result = collection
        .find_one_and_update(filter, update_doc)
        .with_options(options)
        .await;

    match update_result {
        Ok(Some(updated_profile)) => {
            info!(user_id = %user_id, id = updated_profile.id.map(|id| id.to_string()).unwrap_or_default(), "Successfully upserted user profile in DB");

            let cache_key = profile_cache_key(user_id);
            debug!(user_id = %user_id, key = %cache_key, "Attempting to invalidate cache");
            match state.redis_client.get_multiplexed_async_connection().await {
                Ok(mut redis_conn) => match redis_conn.del::<_, i64>(&cache_key).await {
                    Ok(deleted_count) if deleted_count > 0 => {
                        info!(user_id = %user_id, key = %cache_key, "Successfully invalidated cache")
                    }
                    Ok(_) => {
                        debug!(user_id = %user_id, key = %cache_key, "Cache key did not exist for invalidation")
                    }
                    Err(e) => {
                        warn!(user_id = %user_id, key = %cache_key, "Failed to invalidate cache (DEL command failed): {}", e)
                    }
                },
                Err(e) => {
                    warn!(user_id = %user_id, key = %cache_key, "Failed to get Redis connection for cache invalidation: {}", e)
                }
            }

            Ok(Json(updated_profile))
        }
        Ok(None) => {
            error!(user_id = %user_id, "Upsert operation returned None unexpectedly.");
            Err(AppError::Internal(
                "Profile update failed unexpectedly.".to_string(),
            ))
        }
        Err(e) => {
            if let ErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
                *e.kind.clone()
            {
                if write_error.code == 11000 {
                    error!(user_id = %user_id, "Duplicate key error on upsert: {}", e);
                    return Err(AppError::BadRequest(
                        "Update failed due to conflicting unique key.".to_string(),
                    ));
                }
            }
            error!(user_id = %user_id, "Failed to upsert profile in DB: {}", e);
            Err(AppError::MongoDb(e))
        }
    }
}

#[instrument]
pub async fn get_allergens() -> Result<Json<Vec<AllergenInfo>>> {
    info!("Fetching list of common allergens");

    // TODO: Implement Redis caching for this list
    // 1. Define cache key: e.g., "allergens:list"
    // 2. Try fetching from Redis using state.redis_client
    // 3. If cache hit (and data deserializes ok), return cached Json(data)
    // 4. If cache miss or error: proceed to generate list below
    // 5. After generating list, serialize it to JSON and store in Redis cache
    //    using SETEX with a suitable TTL (e.g., 86400 seconds for 24 hours)
    // 6. Return Ok(Json(allergen_list))

    // Hardcoded list based on EU 14 major allergens
    let allergens = vec![
        AllergenInfo { id: "gluten".to_string(), name: "Cereals containing gluten".to_string(), description: Some("Includes wheat (such as spelt and khorasan wheat), rye, barley, oats.".to_string()) },
        AllergenInfo { id: "crustaceans".to_string(), name: "Crustaceans".to_string(), description: Some("Includes crabs, lobsters, prawns, scampi.".to_string()) },
        AllergenInfo { id: "eggs".to_string(), name: "Eggs".to_string(), description: None },
        AllergenInfo { id: "fish".to_string(), name: "Fish".to_string(), description: None },
        AllergenInfo { id: "peanuts".to_string(), name: "Peanuts".to_string(), description: None },
        AllergenInfo { id: "soybeans".to_string(), name: "Soybeans".to_string(), description: None },
        AllergenInfo { id: "milk".to_string(), name: "Milk".to_string(), description: Some("Including lactose.".to_string()) },
        AllergenInfo { id: "nuts".to_string(), name: "Nuts".to_string(), description: Some("Includes almonds, hazelnuts, walnuts, cashews, pecans, brazils, pistachios, macadamia nuts.".to_string()) },
        AllergenInfo { id: "celery".to_string(), name: "Celery".to_string(), description: None },
        AllergenInfo { id: "mustard".to_string(), name: "Mustard".to_string(), description: None },
        AllergenInfo { id: "sesame".to_string(), name: "Sesame seeds".to_string(), description: None },
        AllergenInfo { id: "sulphites".to_string(), name: "Sulphur dioxide and sulphites".to_string(), description: Some("At concentrations of more than 10mg/kg or 10mg/litre.".to_string()) },
        AllergenInfo { id: "lupin".to_string(), name: "Lupin".to_string(), description: None },
        AllergenInfo { id: "molluscs".to_string(), name: "Molluscs".to_string(), description: Some("Includes mussels, oysters, squid, snails.".to_string()) },
    ];

    Ok(Json(allergens))
}
