use crate::{
    errors::{AppError, Result},
    models::{CreateUserProfilePayload, UserProfile},
    state::AppState,
};
use axum::{Json, extract::State, http::StatusCode};
use bson::doc;
use mongodb::{Collection, error::ErrorKind};
use std::sync::Arc;
use tracing::{debug, error, info, instrument};
use validator::Validate;

const USER_PROFILE_COLLECTION: &str = "user_profiles"; // Define collection name centrally

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
