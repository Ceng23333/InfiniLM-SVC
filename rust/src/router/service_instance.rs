//! Service instance representation

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;

/// Service instance metadata
#[derive(Clone, Debug)]
pub struct ServiceInstance {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub url: String,
    pub babysitter_url: String,
    pub healthy: Arc<RwLock<bool>>,
    pub models: Arc<RwLock<Vec<String>>>,
    pub metadata: HashMap<String, serde_json::Value>,
    pub request_count: Arc<RwLock<u64>>,
    pub error_count: Arc<RwLock<u32>>,
    pub weight: u32,
    pub last_seen: Arc<RwLock<f64>>,
    pub last_check: Arc<RwLock<f64>>,
    pub response_time: Arc<RwLock<f64>>,
}

impl ServiceInstance {
    /// Create a new service instance
    pub fn new(
        name: String,
        host: String,
        port: u16,
        weight: u32,
        metadata: HashMap<String, serde_json::Value>,
    ) -> Self {
        let url = format!("http://{}:{}", host, port);
        let babysitter_port = port + 1;
        let babysitter_url = format!("http://{}:{}", host, babysitter_port);

        // Extract models from metadata if available
        let models = metadata
            .get("models")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect()
            })
            .unwrap_or_default();

        let last_seen = crate::utils::time::current_timestamp();

        ServiceInstance {
            name,
            host,
            port,
            url,
            babysitter_url,
            healthy: Arc::new(RwLock::new(true)),
            models: Arc::new(RwLock::new(models)),
            metadata,
            request_count: Arc::new(RwLock::new(0)),
            error_count: Arc::new(RwLock::new(0)),
            weight,
            last_seen: Arc::new(RwLock::new(last_seen)),
            last_check: Arc::new(RwLock::new(0.0)),
            response_time: Arc::new(RwLock::new(0.0)),
        }
    }

    /// Check if service is healthy
    pub async fn is_healthy(&self) -> bool {
        *self.healthy.read().await
    }

    /// Increment request count
    pub async fn increment_request_count(&self) {
        let mut count = self.request_count.write().await;
        *count += 1;
    }

    /// Increment error count
    pub async fn increment_error_count(&self) {
        let mut count = self.error_count.write().await;
        *count += 1;
    }

    /// Update health status
    pub async fn set_healthy(&self, healthy: bool) {
        let mut status = self.healthy.write().await;
        *status = healthy;
    }

    /// Update last seen timestamp
    pub async fn update_last_seen(&self) {
        let mut last_seen = self.last_seen.write().await;
        *last_seen = crate::utils::time::current_timestamp();
    }

    /// Check if service supports a specific model
    pub async fn supports_model(&self, model_id: &str) -> bool {
        let models = self.models.read().await;
        models.contains(&model_id.to_string())
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceInfo {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub url: String,
    pub babysitter_url: String,
    pub healthy: bool,
    pub request_count: u64,
    pub error_count: u32,
    pub response_time: f64,
    pub weight: u32,
    pub models: Vec<String>,
    pub metadata: HashMap<String, serde_json::Value>,
}

impl ServiceInstance {
    /// Convert to serializable info
    pub async fn to_info(&self) -> ServiceInfo {
        ServiceInfo {
            name: self.name.clone(),
            host: self.host.clone(),
            port: self.port,
            url: self.url.clone(),
            babysitter_url: self.babysitter_url.clone(),
            healthy: *self.healthy.read().await,
            request_count: *self.request_count.read().await,
            error_count: *self.error_count.read().await,
            response_time: *self.response_time.read().await,
            weight: self.weight,
            models: self.models.read().await.clone(),
            metadata: self.metadata.clone(),
        }
    }
}
