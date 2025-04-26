use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;
use thiserror::Error;
use tracing::error;

#[derive(Error, Debug)]
pub enum ServiceError {
    #[error("Input/output error: {0}")]
    Io(#[from] std::io::Error),

    #[error("MongoDB error: {0}")]
    MongoDb(#[from] mongodb::error::Error),

    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("BSON serialization error: {0}")]
    BsonSerialize(#[from] mongodb::bson::ser::Error),

    #[error("BSON deserialization error: {0}")]
    BsonDeserialize(#[from] mongodb::bson::de::Error),

    #[error("Configuration error: Missing environment variable '{0}'")]
    MissingVariable(String), // Specific variant for missing env vars
    #[error("Configuration error: Dotenv error: {0}")]
    Dotenv(#[from] dotenvy::Error),

    #[error("Invalid input: {0}")]
    BadRequest(String),

    #[error("Resource not found: {0}")]
    NotFound(String),

    #[error("Internal server error: {0}")]
    Internal(String),
}

impl From<rust_database_clients::ConfigError> for ServiceError {
    fn from(err: rust_database_clients::ConfigError) -> Self {
        match err {
            rust_database_clients::ConfigError::MissingVariable(var) => {
                ServiceError::MissingVariable(var)
            }
            rust_database_clients::ConfigError::Dotenv(e) => ServiceError::Dotenv(e),
        }
    }
}

impl IntoResponse for ServiceError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            ServiceError::Io(e) => {
                error!("IO error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal I/O error".to_string(),
                )
            }
            ServiceError::MongoDb(e) => {
                error!("MongoDB error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Database operation failed".to_string(),
                )
            }
            ServiceError::Redis(e) => {
                error!("Redis error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Cache operation failed".to_string(),
                )
            }
            ServiceError::BsonSerialize(e) => {
                error!("BSON serialization error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to serialize data".to_string(),
                )
            }
            ServiceError::BsonDeserialize(e) => {
                error!("BSON deserialization error: {}", e);
                (
                    StatusCode::BAD_REQUEST,
                    "Failed to deserialize data".to_string(),
                )
            }
            ServiceError::MissingVariable(var) => {
                error!("Configuration error: Missing env var {}", var);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal configuration error".to_string(),
                )
            }
            ServiceError::Dotenv(e) => {
                error!("Configuration error: Dotenv error {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal configuration error".to_string(),
                )
            }
            ServiceError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            ServiceError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            ServiceError::Internal(msg) => {
                error!("Internal server error: {}", msg);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "An internal error occurred".to_string(),
                )
            }
        };

        let body = Json(json!({ "error": error_message }));
        (status, body).into_response()
    }
}

pub type Result<T> = std::result::Result<T, ServiceError>;
