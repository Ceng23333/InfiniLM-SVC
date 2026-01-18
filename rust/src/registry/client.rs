//! Registry HTTP client

use anyhow::{Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::Duration;
use tracing::{info, warn};

/// Service information from registry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistryService {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub url: String,
    pub hostname: String,
    pub status: String,
    pub timestamp: String,
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
    #[serde(default)]
    pub is_healthy: bool,
    #[serde(default = "default_weight")]
    pub weight: u32,
}

fn default_weight() -> u32 {
    1
}

/// Registry services response
#[derive(Debug, Serialize, Deserialize)]
pub struct RegistryServicesResponse {
    pub services: Vec<RegistryService>,
    #[serde(default)]
    pub total: usize,
}

/// Registry client
pub struct RegistryClient {
    registry_url: String,
    client: Client,
}

impl RegistryClient {
    /// Create a new registry client
    pub fn new(registry_url: String) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .expect("Failed to create registry HTTP client");

        RegistryClient {
            registry_url,
            client,
        }
    }

    /// Fetch services from registry
    pub async fn fetch_services(&self, healthy_only: bool) -> Result<RegistryServicesResponse> {
        let url = if healthy_only {
            format!("{}/services?healthy=true", self.registry_url)
        } else {
            format!("{}/services", self.registry_url)
        };

        info!("Fetching services from registry: {}", url);

        let response = self
            .client
            .get(&url)
            .send()
            .await
            .context("Failed to send request to registry")?;

        if !response.status().is_success() {
            anyhow::bail!("Registry returned error status: {}", response.status());
        }

        let services_response: RegistryServicesResponse = response
            .json()
            .await
            .context("Failed to parse registry response")?;

        info!(
            "Fetched {} services from registry",
            services_response.services.len()
        );

        Ok(services_response)
    }

    /// Check if registry is available
    pub async fn check_health(&self) -> Result<bool> {
        let url = format!("{}/health", self.registry_url);
        match self.client.get(&url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(e) => {
                warn!("Registry health check failed: {}", e);
                Ok(false)
            }
        }
    }
}
