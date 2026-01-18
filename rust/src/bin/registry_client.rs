//! Registry client for the babysitter

use super::BabysitterState;
use reqwest::Client;
use serde_json::json;
use std::sync::Arc;
use tokio::time::{sleep, Duration};
use tracing::{debug, error, info, warn};

pub struct BabysitterRegistryClient {
    registry_url: String,
    client: Client,
    state: Arc<BabysitterState>,
}

impl BabysitterRegistryClient {
    pub fn new(registry_url: String, state: Arc<BabysitterState>) -> Self {
        Self {
            registry_url: registry_url.trim_end_matches('/').to_string(),
            client: Client::new(),
            state,
        }
    }

    pub async fn run(&self) {
        // Register babysitter
        self.register_babysitter().await;

        // Register managed service when ready
        tokio::spawn({
            let client = self.clone();
            async move {
                client.register_managed_service().await;
            }
        });

        // Heartbeat loop
        loop {
            sleep(Duration::from_secs(self.state.config.heartbeat_interval)).await;

            // Send heartbeat for babysitter
            let service_name = self.state.config.service_name();
            self.send_heartbeat(&service_name).await;

            // Send heartbeat for managed service if registered
            let service_port = {
                let port = self.state.service_port.read().await;
                *port
            };

            if service_port.is_some() {
                let server_name = format!("{}-server", self.state.config.service_name());
                self.send_heartbeat(&server_name).await;
            }
        }
    }

    async fn register_babysitter(&self) {
        let service_name = self.state.config.service_name();
        let service_data = json!({
            "name": service_name,
            "host": self.state.config.host,
            "hostname": self.state.config.host,
            "port": self.state.babysitter_port(),
            "url": format!("http://{}:{}", self.state.config.host, self.state.babysitter_port()),
            "status": "running",
            "metadata": {
                "type": self.state.config.service_type,
                "babysitter": "enhanced"
            }
        });

        match self
            .client
            .post(&format!("{}/services", self.registry_url))
            .json(&service_data)
            .send()
            .await
        {
            Ok(response) => {
                if response.status().is_success() {
                    info!("✅ Babysitter registered with registry");
                } else {
                    warn!("Failed to register babysitter: {}", response.status());
                }
            }
            Err(e) => {
                error!("Error registering babysitter: {}", e);
            }
        }
    }

    async fn register_managed_service(&self) {
        // Wait for service to be ready
        loop {
            let service_port = {
                let port = self.state.service_port.read().await;
                *port
            };

            if service_port.is_none() {
                sleep(Duration::from_millis(100)).await; // Check very frequently (100ms)
                continue;
            }

            // Fetch models from service
            let models = self.fetch_models(service_port.unwrap()).await;
            
            if models.is_empty() {
                warn!("No models fetched from service, retrying registration...");
                sleep(Duration::from_secs(2)).await;
                continue;
            }

            // Register service
            let service_name = self.state.config.service_name();
            let service_data = json!({
                "name": format!("{}-server", service_name),
                "host": self.state.config.host,
                "hostname": self.state.config.host,
                "port": service_port.unwrap(),
                "url": format!("http://{}:{}", self.state.config.host, service_port.unwrap()),
                "status": "running",
                "metadata": {
                    "type": "openai-api",
                    "parent_service": service_name,
                    "babysitter": "enhanced",
                    "models": models.iter().map(|m| m.get("id").and_then(|v| v.as_str()).unwrap_or("")).collect::<Vec<_>>(),
                    "models_list": models
                }
            });

            match self
                .client
                .post(&format!("{}/services", self.registry_url))
                .json(&service_data)
                .send()
                .await
            {
                Ok(response) => {
                    if response.status().is_success() {
                        info!("✅ Managed service registered with registry ({} models)", models.len());
                        break;
                    } else {
                        let status_text = response.status().to_string();
                        let body = response.text().await.unwrap_or_default();
                        warn!("Failed to register managed service: {} - {}", status_text, body);
                    }
                }
                Err(e) => {
                    error!("Error registering managed service: {}", e);
                }
            }

            sleep(Duration::from_secs(2)).await; // Reduced from 5s to 2s
        }
    }

    async fn fetch_models(&self, port: u16) -> Vec<serde_json::Value> {
        // Try /v1/models first (OpenAI API format), fallback to /models
        let url = format!("http://{}:{}/v1/models", self.state.config.host, port);

        // Retry logic with faster polling since port detection already verified HTTP is ready
        // But give it more attempts in case the service needs a moment to fully initialize
        for attempt in 0..20 {
            match self.client.get(&url).send().await {
                Ok(response) => {
                    if response.status().is_success() {
                        if let Ok(data) = response.json::<serde_json::Value>().await {
                            if let Some(models) = data.get("data").and_then(|v| v.as_array()) {
                                let models: Vec<_> = models.clone();
                                if !models.is_empty() {
                                    info!("Fetched {} models from service", models.len());
                                    return models;
                                } else {
                                    debug!("Service returned empty models list, retrying...");
                                }
                            } else {
                                debug!("Service response missing 'data' field, retrying...");
                            }
                        } else {
                            debug!("Failed to parse JSON response, retrying...");
                        }
                    } else {
                        // Non-200 status, log and retry
                        if attempt % 5 == 0 {
                            debug!("Service returned status {} for /models, retrying... (attempt {})", response.status(), attempt);
                        }
                    }
                }
                Err(e) => {
                    // Connection error, retry
                    if attempt % 5 == 0 {
                        debug!("Error fetching models: {}, retrying... (attempt {})", e, attempt);
                    }
                }
            }

            if attempt < 19 {
                // Fast retry since port detection already verified HTTP is ready
                sleep(Duration::from_millis(300)).await;
            }
        }

        warn!("Failed to fetch models from service after 20 attempts");
        vec![]
    }

    async fn send_heartbeat(&self, service_name: &str) {
        match self
            .client
            .post(&format!("{}/services/{}/heartbeat", self.registry_url, service_name))
            .send()
            .await
        {
            Ok(response) => {
                if !response.status().is_success() {
                    warn!("Heartbeat failed for {}: {}", service_name, response.status());
                }
            }
            Err(e) => {
                warn!("Heartbeat error for {}: {}", service_name, e);
            }
        }
    }
}

impl Clone for BabysitterRegistryClient {
    fn clone(&self) -> Self {
        Self {
            registry_url: self.registry_url.clone(),
            client: self.client.clone(),
            state: self.state.clone(),
        }
    }
}
