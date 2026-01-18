//! Error types for the router service

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;
use thiserror::Error;

/// Router error types
#[derive(Error, Debug)]
pub enum RouterError {
    #[error("No healthy services available")]
    NoHealthyService,

    #[error("Service not found: {0}")]
    ServiceNotFound(String),

    #[error("Registry error: {0}")]
    RegistryError(#[from] reqwest::Error),

    #[error("JSON parsing error: {0}")]
    JsonError(#[from] serde_json::Error),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Configuration error: {0}")]
    ConfigError(String),

    #[error("Internal error: {0}")]
    Internal(#[from] anyhow::Error),
}

impl IntoResponse for RouterError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            RouterError::NoHealthyService => (StatusCode::SERVICE_UNAVAILABLE, "No healthy services available".to_string()),
            RouterError::ServiceNotFound(_) => (StatusCode::NOT_FOUND, self.to_string()),
            RouterError::RegistryError(_) => (StatusCode::BAD_GATEWAY, "Registry communication error".to_string()),
            RouterError::JsonError(_) => (StatusCode::BAD_REQUEST, "Invalid JSON".to_string()),
            RouterError::IoError(_) => (StatusCode::INTERNAL_SERVER_ERROR, "IO error".to_string()),
            RouterError::ConfigError(_) => (StatusCode::INTERNAL_SERVER_ERROR, self.to_string()),
            RouterError::Internal(_) => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error".to_string()),
        };

        let body = Json(json!({
            "error": error_message
        }));

        (status, body).into_response()
    }
}
