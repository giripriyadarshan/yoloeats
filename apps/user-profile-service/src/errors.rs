use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;
use thiserror::Error;
use tracing::error;

#[derive(Error, Debug)]
pub enum AppError {
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

    #[error("Configuration error: {0}")]
    Config(#[from] rust_database_clients::ConfigError),

    #[error("Invalid input: {0}")]
    BadRequest(String),

    #[error("Resource not found: {0}")]
    NotFound(String),

    #[error("Internal server error: {0}")]
    Internal(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            AppError::Io(e) => {
                error!("IO error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "An internal input/output error occurred".to_string(),
                )
            }
            AppError::MongoDb(e) => {
                error!("MongoDB error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Database operation failed".to_string(),
                )
            }
            AppError::Redis(e) => {
                error!("Redis error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Cache or session operation failed".to_string(),
                )
            }
            AppError::BsonSerialize(e) => {
                error!("BSON serialization error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to serialize data".to_string(),
                )
            }
            AppError::BsonDeserialize(e) => {
                error!("BSON deserialization error: {}", e);
                (
                    StatusCode::BAD_REQUEST, // Assuming deserialization errors are client errors
                    "Failed to deserialize data".to_string(),
                )
            }
            AppError::Config(e) => {
                error!("Configuration error encountered during request: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal configuration problem".to_string(),
                )
            }
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::NotFound(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::Internal(msg) => {
                error!("Internal server error: {}", msg);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "An unexpected internal error occurred".to_string(), // Generic message to client
                )
            }
        };

        let body = Json(json!({
            "error": error_message,
        }));

        (status, body).into_response()
    }
}

pub type Result<T> = std::result::Result<T, AppError>;
