//! HTTP request handlers

use axum::{routing::get, Router};
use std::sync::Arc;

use crate::proxy::handler::proxy_handler;
use crate::router::load_balancer::LoadBalancer;

mod health;
mod models;
mod services;
mod stats;

/// Create the main router
pub fn create_router(load_balancer: Arc<LoadBalancer>) -> Router {
    Router::new()
        .route("/health", get(health::health_handler))
        .route("/status", get(health::health_handler)) // Alias for /health
        .route("/stats", get(stats::stats_handler))
        .route("/services", get(services::services_handler))
        .route("/models", get(models::models_handler))
        .fallback(proxy_handler)
        .with_state(load_balancer)
}
