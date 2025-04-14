use crate::{
    errors::{AppError, Result},
    models::UserProfile,
    state::AppState,
};
use bson::{doc, oid::ObjectId};
use redis::AsyncCommands;
use std::sync::Arc;
use tracing::{debug, error, info, warn};

const CACHE_EXPIRATION_SECONDS: u64 = 300; // 5 minutes

fn cache_key(user_id: &ObjectId) -> String {
    format!("user_profile:{}", user_id)
}

pub async fn get_user_profile_by_id(
    state: &Arc<AppState>,
    user_id: ObjectId,
) -> Result<Option<UserProfile>> {
    let key = cache_key(&user_id);
    let mut redis_conn = state
        .redis_client
        .get_multiplexed_async_connection()
        .await
        .map_err(|e| {
            error!("Failed to get async Redis connection: {}", e);
            AppError::Redis(e)
        })?;

    match redis_conn.get::<_, String>(&key).await {
        Ok(cached_profile_json) => {
            if !cached_profile_json.is_empty() {
                match serde_json::from_str::<UserProfile>(&cached_profile_json) {
                    Ok(profile) => {
                        info!(user_id = %user_id, "Cache hit for user profile");
                        return Ok(Some(profile));
                    }
                    Err(e) => {
                        error!(user_id = %user_id, "Failed to deserialize cached profile: {}. Fetching from DB.", e);
                        // if cache data is corrupted
                        // Proceed to fetch from DB
                    }
                }
            } else {
                debug!(user_id = %user_id, "Cache miss for user profile (empty value).");
                // Proceed to fetch from DB
            }
        }
        Err(e) => {
            warn!(user_id = %user_id, "Redis GET command failed: {}. Fetching from DB.", e);
            // Proceed to fetch from DB
        }
    }

    debug!(user_id = %user_id, "Fetching profile from MongoDB");
    let collection = state
        .mongo_db
        .collection::<UserProfile>(crate::handlers::USER_PROFILE_COLLECTION);

    let db_profile = collection
        .find_one(doc! {"_id": user_id})
        .await
        .map_err(|e| {
            error!(user_id = %user_id, "MongoDB find_one failed: {}", e);
            AppError::MongoDb(e)
        })?;

    if let Some(profile) = &db_profile {
        debug!(user_id = %user_id, "Profile found in DB, attempting to cache.");
        match serde_json::to_string(profile) {
            Ok(profile_json) => {
                match redis_conn
                    .set_ex::<_, _, ()>(&key, &profile_json, CACHE_EXPIRATION_SECONDS)
                    .await
                {
                    Ok(_) => {
                        info!(user_id = %user_id, "Successfully cached profile in Redis");
                    }
                    Err(e) => {
                        // Log Redis error but don't fail the request
                        warn!(user_id = %user_id, "Failed to cache profile in Redis (SETEX): {}", e);
                    }
                }
            }
            Err(e) => {
                // Log serialization error but don't fail the request
                warn!(user_id = %user_id, "Failed to serialize profile for caching: {}", e);
            }
        }
    } else {
        info!(user_id = %user_id, "Profile not found in MongoDB.");
    }

    Ok(db_profile)
}
