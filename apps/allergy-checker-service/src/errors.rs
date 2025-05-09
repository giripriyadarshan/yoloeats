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
    #[error("HTTP request failed: {0}")]
    ReqwestError(#[from] reqwest::Error),

    #[error("Neo4j database error: {0}")]
    Neo4jError(#[from] neo4rs::Error),

    #[error("JSON serialization/deserialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Configuration error: Missing environment variable '{0}'")]
    MissingEnvVar(String),

    #[error("Resource not found: {0}")]
    NotFoundError(String),

    #[error("Error response from upstream service '{service}': Status {status}")]
    UpstreamServiceError { service: String, status: u16 },

    #[error("Failed to process user profile: {0}")]
    ProfileProcessingError(String),

    #[error("Failed to process product data: {0}")]
    ProductProcessingError(String),

    #[error("Invalid input: {0}")]
    BadRequest(String),

    #[error("Internal server error")]
    InternalServerError,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match &self {
            AppError::NotFoundError(msg) => (StatusCode::NOT_FOUND, msg.clone()),
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg.clone()),
            AppError::SerializationError(e) => {
                error!("Serialization error: {}", e);
                (StatusCode::BAD_REQUEST, "Invalid data format".to_string())
            }
            AppError::UpstreamServiceError { service, status } => {
                error!(
                    "Upstream service '{}' failed with status {}",
                    service, status
                );
                // Bad Gateway seems appropriate
                (
                    StatusCode::BAD_GATEWAY,
                    format!("Error communicating with {}", service),
                )
            }
            AppError::ProfileProcessingError(msg) | AppError::ProductProcessingError(msg) => {
                error!("Data processing error: {}", msg);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Failed to process data".to_string(),
                )
            }
            AppError::ReqwestError(e) => {
                error!("HTTP client error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal network error".to_string(),
                )
            }
            AppError::Neo4jError(e) => {
                error!("Neo4j error: {}", e);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Database error".to_string(),
                )
            }
            AppError::MissingEnvVar(var) => {
                error!("Missing configuration: {}", var);
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "Internal server configuration error".to_string(),
                )
            }
            AppError::InternalServerError => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "An internal server error occurred".to_string(),
            ),
        };

        let body = Json(json!({ "error": error_message }));
        (status, body).into_response()
    }
}

pub type Result<T, E = AppError> = std::result::Result<T, E>;
