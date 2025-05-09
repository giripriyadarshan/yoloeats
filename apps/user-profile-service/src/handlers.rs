use crate::{
    errors::{AppError, Result},
    models::{AllergenInfo, UpdateProfilePayload, UserProfile},
    state::AppState,
};
use axum::{
    Json,
    extract::{Path, State},
};
use bson::doc;
use chrono::Utc;
use mongodb::{
    Collection,
    error::ErrorKind as MongoErrorKind,
    options::{FindOneAndUpdateOptions, ReturnDocument},
};
use redis::AsyncCommands;
use std::sync::Arc;
use tracing::{debug, error, info, instrument, warn};
use validator::Validate;

const PROFILE_CACHE_KEY_PREFIX: &str = "profile:";
const CACHE_EXPIRATION_SECONDS: u64 = 3600;

fn profile_cache_key(user_id: &str) -> String {
    format!("{}{}", PROFILE_CACHE_KEY_PREFIX, user_id)
}

#[instrument(skip(state), fields(user_id = %user_id_param))]
pub async fn get_profile(
    State(state): State<Arc<AppState>>,
    Path(user_id_param): Path<String>,
) -> Result<Json<UserProfile>> {
    info!("Attempting to get profile for user_id: {}", user_id_param);

    let cache_key = profile_cache_key(&user_id_param);

    let mut redis_conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            warn!(user_id = %user_id_param, "Failed to get Redis connection: {}. Proceeding without cache.", e);
            AppError::Redis(e)
        })?;

    match redis_conn.get::<_, String>(&cache_key).await {
        Ok(cached_profile_json) if !cached_profile_json.is_empty() => {
            match serde_json::from_str::<UserProfile>(&cached_profile_json) {
                Ok(profile) => {
                    info!(user_id = %user_id_param, "Cache hit for user profile");
                    return Ok(Json(profile));
                }
                Err(e) => {
                    error!(user_id = %user_id_param, "Failed to deserialize cached profile: {}. Fetching from DB.", e);
                }
            }
        }
        Ok(_) => {
            debug!(user_id = %user_id_param, "Cache miss for user profile (key not found or empty).");
        }
        Err(e) => {
            warn!(user_id = %user_id_param, "Redis GET command failed: {}. Fetching from DB.", e);
        }
    }

    debug!(user_id = %user_id_param, "Fetching profile from MongoDB");
    let collection: Collection<UserProfile> = state.mongo_db.collection("user_profiles");
    let filter = doc! { "user_id": user_id_param.clone() };

    let db_profile = collection.find_one(filter).await.map_err(|e| {
        error!(user_id = %user_id_param, "MongoDB find_one failed: {}", e);
        AppError::MongoDb(e)
    })?;

    match db_profile {
        Some(profile) => {
            info!(user_id = %user_id_param, "Profile found in DB");
            match serde_json::to_string(&profile) {
                Ok(profile_json) => {
                    match redis_conn
                        .set_ex::<_, _, ()>(&cache_key, &profile_json, CACHE_EXPIRATION_SECONDS)
                        .await
                    {
                        Ok(_) => {
                            info!(user_id = %user_id_param, key = %cache_key, "Successfully cached profile in Redis")
                        }
                        Err(e) => {
                            warn!(user_id = %user_id_param, key = %cache_key, "Failed to cache profile in Redis (SETEX): {}", e)
                        }
                    }
                }
                Err(e) => {
                    warn!(user_id = %user_id_param, "Failed to serialize profile for caching: {}", e);
                }
            }
            Ok(Json(profile))
        }
        None => {
            info!(user_id = %user_id_param, "Profile not found in DB");
            Err(AppError::NotFound(format!(
                "Profile for user {} not found",
                user_id_param
            )))
        }
    }
}

#[instrument(skip(state, payload), fields(user_id = %user_id_param))]
pub async fn update_profile(
    State(state): State<Arc<AppState>>,
    Path(user_id_param): Path<String>,
    Json(payload): Json<UpdateProfilePayload>,
) -> Result<Json<UserProfile>> {
    info!(
        "Attempting to update profile for user_id: {}",
        user_id_param
    );

    payload.validate().map_err(|e| {
        error!(user_id = %user_id_param, "Payload validation failed: {}", e);
        AppError::BadRequest(format!("Input validation failed: {}", e).replace('\n', ", "))
    })?;
    debug!(user_id = %user_id_param, "Payload validated successfully");

    let mut set_updates_doc = bson::to_document(&payload).map_err(AppError::BsonSerialize)?;

    if set_updates_doc.is_empty() {
        warn!(user_id = %user_id_param, "Update request received with no updatable fields from payload.");
        return Err(AppError::BadRequest(
            "No fields provided for update.".to_string(),
        ));
    }

    let now = Utc::now();
    set_updates_doc.insert("updated_at", bson::DateTime::from_chrono(now));

    let set_on_insert_doc = doc! {
        "user_id": user_id_param.clone(),
        "created_at": bson::DateTime::from_chrono(now)
    };

    let update_doc = doc! {
        "$set": set_updates_doc,
        "$setOnInsert": set_on_insert_doc
    };
    debug!(user_id = %user_id_param, update = ?update_doc, "Constructed upsert document");

    let collection: Collection<UserProfile> = state.mongo_db.collection("user_profiles");
    let filter = doc! { "user_id": user_id_param.clone() };
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
            info!(user_id = %user_id_param, id = updated_profile.id.map(|id| id.to_string()).unwrap_or_default(), "Successfully upserted user profile in DB");

            let cache_key = profile_cache_key(&user_id_param);
            debug!(user_id = %user_id_param, key = %cache_key, "Attempting to invalidate cache");
            match state.redis_client.get_multiplexed_async_connection().await {
                Ok(mut redis_conn) => match redis_conn.del::<_, i64>(&cache_key).await {
                    Ok(deleted_count) if deleted_count > 0 => {
                        info!(user_id = %user_id_param, key = %cache_key, count = deleted_count, "Successfully invalidated cache")
                    }
                    Ok(_) => {
                        debug!(user_id = %user_id_param, key = %cache_key, "Cache key did not exist for invalidation, or no keys deleted.")
                    }
                    Err(e) => {
                        warn!(user_id = %user_id_param, key = %cache_key, "Failed to invalidate cache (DEL command failed): {}", e)
                    }
                },
                Err(e) => {
                    warn!(user_id = %user_id_param, key = %cache_key, "Failed to get Redis connection for cache invalidation: {}", e)
                }
            }
            Ok(Json(updated_profile))
        }
        Ok(None) => {
            error!(user_id = %user_id_param, "Upsert operation returned None unexpectedly. This might indicate an issue with MongoDB's return behavior or query.");
            Err(AppError::Internal(
                "Profile update failed unexpectedly after upsert operation.".to_string(),
            ))
        }
        Err(e) => {
            if let MongoErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
                *e.kind.clone()
            {
                if write_error.code == 11000 {
                    error!(user_id = %user_id_param, "Duplicate key error on upsert: {}. This could indicate a race condition or an issue with the upsert logic if user_id is not the shard key or has a unique constraint being violated unexpectedly.", e);
                    return Err(AppError::BadRequest(
                                                     "Update failed due to a conflicting unique identifier. Please check data integrity.".to_string(),
                    ));
                }
            }
            error!(user_id = %user_id_param, "Failed to upsert profile in DB: {}", e);
            Err(AppError::MongoDb(e))
        }
    }
}

#[instrument(skip(state))]
pub async fn get_allergens(State(state): State<Arc<AppState>>) -> Result<Json<Vec<AllergenInfo>>> {
    info!("Fetching list of common allergens");

    let cache_key = "allergens:list_v1";

    let mut redis_conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            warn!(
                "Failed to get Redis connection for allergens: {}. Proceeding without cache.",
                e
            );
            AppError::Redis(e)
        })?;

    match redis_conn.get::<_, String>(&cache_key).await {
        Ok(cached_allergens_json) if !cached_allergens_json.is_empty() => {
            match serde_json::from_str::<Vec<AllergenInfo>>(&cached_allergens_json) {
                Ok(allergens) => {
                    info!("Cache hit for allergens list.");
                    return Ok(Json(allergens));
                }
                Err(e) => {
                    error!(
                        "Failed to deserialize cached allergens list: {}. Fetching from source.",
                        e
                    );
                }
            }
        }
        Ok(_) => {
            debug!("Cache miss for allergens list (key not found or empty).");
        }
        Err(e) => {
            warn!(
                "Redis GET command failed for allergens: {}. Fetching from source.",
                e
            );
        }
    }

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
    debug!("Generated allergens list ({} items)", allergens.len());

    match serde_json::to_string(&allergens) {
        Ok(allergens_json) => {
            match redis_conn
                .set_ex::<_, _, ()>(&cache_key, allergens_json, 86400)
                .await
            {
                Ok(_) => {
                    info!(key = %cache_key, "Successfully cached allergens list in Redis");
                }
                Err(e) => {
                    warn!(key = %cache_key, "Failed to cache allergens list in Redis (SETEX): {}", e);
                }
            }
        }
        Err(e) => {
            warn!("Failed to serialize allergens list for caching: {}", e);
        }
    }

    Ok(Json(allergens))
}
