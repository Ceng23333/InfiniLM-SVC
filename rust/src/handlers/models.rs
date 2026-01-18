//! Models endpoint handler

use axum::{extract::State, response::Json};
use serde_json::json;
use std::sync::Arc;

use crate::models::aggregator::ModelAggregator;
use crate::router::load_balancer::LoadBalancer;

/// Models endpoint - aggregate models from all healthy services
pub async fn models_handler(
    State(load_balancer): State<Arc<LoadBalancer>>,
) -> Json<serde_json::Value> {
    let models = ModelAggregator::aggregate_models(&load_balancer).await;

    Json(json!({
        "object": "list",
        "data": models
    }))
}
