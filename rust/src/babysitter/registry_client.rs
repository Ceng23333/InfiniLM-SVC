//! Registry client for the babysitter

use crate::babysitter::BabysitterState;
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
            if self.send_heartbeat(&service_name).await {
                // 404: registry lost our registration (e.g. master restarted) - re-register
                info!("Registry returned 404 for babysitter, re-registering...");
                self.register_babysitter().await;
            }

            // Send heartbeat for managed service if registered
            let service_port = {
                let port = self.state.service_port.read().await;
                *port
            };

            if let Some(port) = service_port {
                let server_name = format!("{}-server", self.state.config.service_name());
                if self.send_heartbeat(&server_name).await {
                    // 404: registry lost our registration - re-register managed service
                    info!("Registry returned 404 for managed service, re-registering...");
                    self.do_register_managed_service(port).await;
                }
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
            .post(format!("{}/services", self.registry_url))
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
        // Wait for service to be ready and register
        loop {
            let service_port = {
                let port = self.state.service_port.read().await;
                *port
            };

            if service_port.is_none() {
                sleep(Duration::from_millis(100)).await; // Check very frequently (100ms)
                continue;
            }

            let port = service_port.unwrap();
            if self.do_register_managed_service(port).await {
                break;
            }

            sleep(Duration::from_secs(2)).await;
        }
    }

    async fn fetch_models(&self, port: u16) -> Vec<serde_json::Value> {
        // Try /v1/models first (OpenAI API format), fallback to /models
        // Always use localhost for fetching models since the service runs locally
        // The config.host is for registration (external IP), not for local service access
        let urls = vec![
            format!("http://127.0.0.1:{}/v1/models", port),
            format!("http://127.0.0.1:{}/models", port),
        ];

        // Retry logic with faster polling since port detection already verified HTTP is ready
        // But give it more attempts in case the service needs a moment to fully initialize
        for attempt in 0..50 {
            // Try each URL in order
            for url in &urls {
                match self.client.get(url).send().await {
                    Ok(response) => {
                        if response.status().is_success() {
                            if let Ok(data) = response.json::<serde_json::Value>().await {
                                // Handle both OpenAI API format {"data": [...]} and direct array format
                                let models = if let Some(models) = data.get("data").and_then(|v| v.as_array()) {
                                    models.clone()
                                } else if data.is_array() {
                                    // Direct array format
                                    data.as_array().unwrap().clone()
                                } else {
                                    continue; // Try next URL
                                };

                                if !models.is_empty() {
                                    info!("Fetched {} models from service via {}", models.len(), url);
                                    return models;
                                } else {
                                    debug!("Service returned empty models list from {}, retrying...", url);
                                }
                            } else {
                                debug!("Failed to parse JSON response from {}, retrying...", url);
                            }
                        } else {
                            // Non-200 status, try next URL
                            if attempt % 5 == 0 {
                                debug!(
                                    "Service returned status {} for {}, trying next endpoint... (attempt {})",
                                    response.status(),
                                    url,
                                    attempt
                                );
                            }
                            continue; // Try next URL
                        }
                    }
                    Err(e) => {
                        // Connection error, try next URL
                        if attempt % 5 == 0 {
                            debug!(
                                "Error fetching models from {}: {}, trying next endpoint... (attempt {})",
                                url, e, attempt
                            );
                        }
                        continue; // Try next URL
                    }
                }
            }

            if attempt < 19 {
                // Fast retry since port detection already verified HTTP is ready
                sleep(Duration::from_millis(300)).await;
            } else {
                // Slower retry after initial attempts
                sleep(Duration::from_secs(1)).await;
            }
        }

        warn!("Failed to fetch models from service after 50 attempts");
        vec![]
    }

    /// Send heartbeat. Returns true if 404 (service not in registry - re-registration needed).
    async fn send_heartbeat(&self, service_name: &str) -> bool {
        match self
            .client
            .post(format!(
                "{}/services/{}/heartbeat",
                self.registry_url, service_name
            ))
            .send()
            .await
        {
            Ok(response) => {
                if response.status().as_u16() == 404 {
                    warn!(
                        "Heartbeat failed for {}: {} (registry may have restarted)",
                        service_name,
                        response.status()
                    );
                    return true;
                }
                if !response.status().is_success() {
                    warn!(
                        "Heartbeat failed for {}: {}",
                        service_name,
                        response.status()
                    );
                }
                false
            }
            Err(e) => {
                warn!("Heartbeat error for {}: {}", service_name, e);
                false
            }
        }
    }

    /// Register managed service at given port. Used for initial registration and re-registration after registry restart.
    /// Returns true if registration succeeded.
    async fn do_register_managed_service(&self, service_port: u16) -> bool {
        let models = self.fetch_models(service_port).await;

        if models.is_empty() {
            warn!("No models fetched from service, cannot register");
            return false;
        }

        let service_name = self.state.config.service_name();

        let mut metadata = json!({
            "type": "openai-api",
            "parent_service": service_name,
            "babysitter": "enhanced",
            "models": models.iter().map(|m| m.get("id").and_then(|v| v.as_str()).unwrap_or("")).collect::<Vec<_>>(),
            "models_list": models
        });

        if let Some(ref config_file) = self.state.config_file {
            if let Some(metadata_obj) = metadata.as_object_mut() {
                let config_metadata = config_file.metadata_json();
                for (key, value) in config_metadata {
                    metadata_obj.insert(key, value);
                }
            }
        }

        let service_data = json!({
            "name": format!("{}-server", service_name),
            "host": self.state.config.host,
            "hostname": self.state.config.host,
            "port": service_port,
            "url": format!("http://{}:{}", self.state.config.host, service_port),
            "status": "running",
            "metadata": metadata
        });

        match self
            .client
            .post(format!("{}/services", self.registry_url))
            .json(&service_data)
            .send()
            .await
        {
            Ok(response) => {
                if response.status().is_success() {
                    info!(
                        "✅ Managed service registered with registry ({} models)",
                        models.len()
                    );
                    true
                } else {
                    let status_text = response.status().to_string();
                    let body = response.text().await.unwrap_or_default();
                    warn!(
                        "Failed to register managed service: {} - {}",
                        status_text, body
                    );
                    false
                }
            }
            Err(e) => {
                error!("Error registering managed service: {}", e);
                false
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
