use crate::{
    cache,
    errors::{AppError, Result},
    models::{CreateUserProfilePayload, UpdateUserProfilePayload, UserProfile},
    state::AppState,
};
use axum::{
    Json,
    extract::{Path, State},
    http::StatusCode,
};
use bson::{DateTime, doc, oid::ObjectId};
use chrono::Utc;
use mongodb::{
    Collection,
    error::ErrorKind,
    options::{FindOneAndUpdateOptions, ReturnDocument},
};
use std::sync::Arc;
use tracing::{debug, error, info, instrument, warn};
use validator::Validate;

pub(crate) const USER_PROFILE_COLLECTION: &str = "user_profiles"; // Define collection name centrally

#[instrument(skip(state, payload), fields(username = %payload.username, email = %payload.email))]
pub async fn create_user_profile(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<CreateUserProfilePayload>,
) -> Result<(StatusCode, Json<UserProfile>)> {
    info!("Attempting to create user profile");

    payload.validate().map_err(|e| {
        error!("Payload validation failed: {}", e);
        AppError::BadRequest(format!("Input validation failed: {}", e).replace('\n', ", "))
    })?;
    debug!("Payload validated successfully");

    let new_profile = UserProfile::from_payload(payload);
    debug!(profile = ?new_profile, "Constructed new user profile struct");

    let collection: Collection<UserProfile> = state.mongo_db.collection(USER_PROFILE_COLLECTION);
    debug!("Obtained handle to collection: {}", USER_PROFILE_COLLECTION);

    let insert_result = collection.insert_one(&new_profile).await.map_err(|e| {
        if let ErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
            *e.kind.clone()
        {
            if write_error.code == 11000 {
                error!("Duplicate key error on insert: {}", e);
                return AppError::BadRequest("Username or email already exists.".to_string());
            }
        }
        error!("Failed to insert user profile into DB: {}", e);
        AppError::MongoDb(e)
    })?;
    info!(
        "Successfully inserted new user profile with ID: {}",
        insert_result.inserted_id
    );

    let created_id = insert_result.inserted_id.as_object_id().ok_or_else(|| {
        error!(
            "Failed to get ObjectId from insert result BSON: {:?}",
            insert_result.inserted_id
        );
        AppError::Internal("Failed to extract ObjectId after insert".to_string())
    })?;

    let created_profile = collection
        .find_one(doc! {"_id": created_id})
        .await
        .map_err(|e| {
            error!(
                "Failed to fetch newly created profile with ID {}: {}",
                created_id, e
            );
            AppError::MongoDb(e)
        })?
        .ok_or_else(|| {
            error!(
                "Newly created profile with ID {} not found immediately after insert",
                created_id
            );
            AppError::NotFound(format!(
                "Profile with ID {} could not be retrieved after creation",
                created_id
            ))
        })?;

    info!(id = %created_id, "Returning created profile");
    Ok((StatusCode::CREATED, Json(created_profile)))
}

#[instrument(skip(state), fields(user_id = %user_id_str))]
pub async fn get_user_profile_by_id(
    State(state): State<Arc<AppState>>,
    Path(user_id_str): Path<String>,
) -> Result<Json<UserProfile>> {
    info!("Attempting to get user profile by ID: {}", user_id_str);

    let user_id = ObjectId::parse_str(&user_id_str).map_err(|e| {
        error!(
            "Invalid ObjectId format for user_id '{}': {}",
            user_id_str, e
        );
        AppError::BadRequest(format!("Invalid user ID format: {}", user_id_str))
    })?;
    debug!("Parsed user ID: {}", user_id);

    // Use the caching logic from cache.rs
    match cache::get_user_profile_by_id(&state, user_id).await {
        Ok(Some(profile)) => {
            info!(user_id = %user_id, "Profile found (via cache or DB)");
            Ok(Json(profile))
        }
        Ok(None) => {
            info!(user_id = %user_id, "Profile not found");
            Err(AppError::NotFound(format!(
                "User profile with ID {} not found",
                user_id
            )))
        }
        Err(e) => {
            // Errors from cache::get_user_profile_by_id are already logged
            // Just propagate the AppError
            Err(e)
        }
    }
}

#[instrument(skip(state, payload), fields(user_id = %user_id_str))]
pub async fn update_user_profile(
    State(state): State<Arc<AppState>>,
    Path(user_id_str): Path<String>,
    Json(payload): Json<UpdateUserProfilePayload>,
) -> Result<Json<UserProfile>> {
    info!("Attempting to update user profile: {}", user_id_str);

    payload.validate().map_err(|e| {
        error!("Payload validation failed: {}", e);
        AppError::BadRequest(format!("Input validation failed: {}", e).replace('\n', ", "))
    })?;
    debug!("Payload validated successfully");

    let user_id = ObjectId::parse_str(&user_id_str).map_err(|e| {
        error!(
            "Invalid ObjectId format for user_id '{}': {}",
            user_id_str, e
        );
        AppError::BadRequest(format!("Invalid user ID format: {}", user_id_str))
    })?;
    debug!("Parsed user ID: {}", user_id);

    let mut set_doc = doc! {};
    if let Some(username) = payload.username {
        set_doc.insert("username", username);
    }
    if let Some(email) = payload.email {
        set_doc.insert("email", email);
    }
    if let Some(allergies) = payload.allergies {
        set_doc.insert("allergies", allergies);
    }
    if let Some(dietary_preferences) = payload.dietary_preferences {
        set_doc.insert("dietary_preferences", dietary_preferences);
    }

    if set_doc.is_empty() {
        warn!(user_id = %user_id, "Update request received with no fields to update.");
        return match cache::get_user_profile_by_id(&state, user_id).await {
            Ok(Some(profile)) => Ok(Json(profile)),
            Ok(None) => Err(AppError::NotFound(format!(
                "User profile with ID {} not found",
                user_id
            ))),
            Err(e) => Err(e),
        };
    }

    set_doc.insert("updated_at", DateTime::from_chrono(Utc::now()));

    let update_doc = doc! { "$set": set_doc };
    debug!(user_id = %user_id, update = ?update_doc, "Constructed update document");

    let collection: Collection<UserProfile> = state.mongo_db.collection(USER_PROFILE_COLLECTION);
    let options = FindOneAndUpdateOptions::builder()
        .return_document(ReturnDocument::After) // Return the document *after* the update
        .build();

    let update_result = collection
        .find_one_and_update(doc! {"_id": user_id}, update_doc)
        .with_options(options)
        .await;

    match update_result {
        Ok(Some(updated_profile)) => {
            info!(user_id = %user_id, "Successfully updated user profile in DB");

            // Cache Invalidation
            let cache_key = format!("user_profile:{}", user_id);
            debug!(user_id = %user_id, key = %cache_key, "Attempting to invalidate cache");
            match state.redis_client.get_multiplexed_async_connection().await {
                Ok(mut redis_conn) => {
                    match redis::cmd("DEL")
                        .arg(&cache_key)
                        .query_async::<i64>(&mut redis_conn)
                        .await
                    {
                        Ok(deleted_count) => {
                            if deleted_count > 0 {
                                info!(user_id = %user_id, key = %cache_key, "Successfully invalidated cache");
                            } else {
                                debug!(user_id = %user_id, key = %cache_key, "Cache key did not exist or was already expired");
                            }
                        }
                        Err(e) => {
                            warn!(user_id = %user_id, key = %cache_key, "Failed to invalidate cache (DEL command failed): {}", e);
                        }
                    }
                }
                Err(e) => {
                    warn!(user_id = %user_id, key = %cache_key, "Failed to get Redis connection for cache invalidation: {}", e);
                }
            }

            Ok(Json(updated_profile))
        }
        Ok(None) => {
            error!(user_id = %user_id, "User profile not found for update");
            Err(AppError::NotFound(format!(
                "User profile with ID {} not found",
                user_id
            )))
        }
        Err(e) => {
            if let ErrorKind::Write(mongodb::error::WriteFailure::WriteError(write_error)) =
                *e.kind.clone()
            {
                if write_error.code == 11000 {
                    error!("Duplicate key error on update: {}", e);
                    return Err(AppError::BadRequest(
                        "Username or email already exists.".to_string(),
                    ));
                }
            }
            error!(user_id = %user_id, "Failed to update user profile in DB: {}", e);
            Err(AppError::MongoDb(e))
        }
    }
}
