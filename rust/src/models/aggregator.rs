//! Model aggregation logic

use crate::router::load_balancer::LoadBalancer;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use tracing::debug;

/// Model aggregator
pub struct ModelAggregator;

impl ModelAggregator {
    /// Aggregate models from all healthy services
    pub async fn aggregate_models(load_balancer: &Arc<LoadBalancer>) -> Vec<Value> {
        let services = load_balancer.get_all_services().await;
        let services_count = services.len();
        let mut aggregated_models: HashMap<String, Value> = HashMap::new();

        for service in services {
            // Only aggregate from healthy openai-api services
            let is_healthy = service.is_healthy().await;
            let service_type = service
                .metadata
                .get("type")
                .and_then(|v| v.as_str())
                .map(|s| s == "openai-api")
                .unwrap_or(false);

            if !is_healthy || !service_type {
                continue;
            }

            // Try to get full model info from metadata.models_list first
            if let Some(models_list) = service.metadata.get("models_list").and_then(|v| v.as_array()) {
                for model_info in models_list {
                    if let Some(model_obj) = model_info.as_object() {
                        if let Some(model_id) = model_obj.get("id").and_then(|v| v.as_str()) {
                            // Store full model info, deduplicate by model ID
                            if !aggregated_models.contains_key(model_id) {
                                aggregated_models.insert(
                                    model_id.to_string(),
                                    serde_json::json!(model_obj),
                                );
                            }
                        }
                    }
                }
            } else {
                // Fallback to model IDs from service.models
                let models = service.models.read().await;
                for model_id in models.iter() {
                    if !aggregated_models.contains_key(model_id) {
                        // Create minimal model info
                        aggregated_models.insert(
                            model_id.clone(),
                            json!({
                                "id": model_id
                            }),
                        );
                    }
                }
            }
        }

        // Convert to sorted vector for consistent output
        let mut models_vec: Vec<Value> = aggregated_models.into_values().collect();
        models_vec.sort_by(|a, b| {
            let id_a = a.get("id").and_then(|v| v.as_str()).unwrap_or("");
            let id_b = b.get("id").and_then(|v| v.as_str()).unwrap_or("");
            id_a.cmp(id_b)
        });

        debug!("Aggregated {} models from {} services", models_vec.len(), services_count);
        models_vec
    }
}
