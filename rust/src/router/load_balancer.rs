//! Load balancer implementation

use crate::config::Config;
use crate::registry::client::RegistryClient;
use crate::router::health_checker::HealthChecker;
use crate::router::service_instance::ServiceInstance;
use crate::utils::errors::RouterError;
use crate::utils::time::current_timestamp;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};

/// Load balancer for managing service instances
pub struct LoadBalancer {
    services: Arc<RwLock<HashMap<String, ServiceInstance>>>,
    pub registry_url: Option<String>,
    current_index: Arc<RwLock<usize>>,
    health_check_interval: u64,
    registry_sync_interval: u64,
    service_removal_grace_period: u64,
    #[allow(dead_code)]
    config: Config,
    health_checker: Arc<HealthChecker>,
    registry_client: Option<Arc<RegistryClient>>,
    running: Arc<RwLock<bool>>,
}

impl LoadBalancer {
    /// Create a new load balancer
    #[allow(clippy::too_many_arguments)]
    pub async fn new(config: &Config) -> Result<Self, RouterError> {
        let mut services = HashMap::new();

        // Add static services if configured
        if let Some(ref static_services) = config.static_services {
            for service_config in static_services {
                let metadata: HashMap<String, serde_json::Value> = service_config
                    .metadata
                    .as_object()
                    .map(|obj| obj.iter().map(|(k, v)| (k.clone(), v.clone())).collect())
                    .unwrap_or_default();

                let service = ServiceInstance::new(
                    service_config.name.clone(),
                    service_config.host.clone(),
                    service_config.port,
                    service_config.weight,
                    metadata,
                );

                info!("Added static service: {} at {}", service.name, service.url);
                services.insert(service_config.name.clone(), service);
            }
        }

        let health_checker = Arc::new(HealthChecker::new(
            Duration::from_secs(config.health_check_timeout),
            config.max_errors,
        ));

        let registry_client = config
            .registry_url
            .as_ref()
            .map(|url| Arc::new(RegistryClient::new(url.clone())));

        Ok(LoadBalancer {
            services: Arc::new(RwLock::new(services)),
            registry_url: config.registry_url.clone(),
            current_index: Arc::new(RwLock::new(0)),
            health_check_interval: config.health_check_interval,
            registry_sync_interval: config.registry_sync_interval,
            service_removal_grace_period: config.service_removal_grace_period,
            config: config.clone(),
            health_checker,
            registry_client,
            running: Arc::new(RwLock::new(true)),
        })
    }

    /// Get next healthy service using weighted round-robin
    #[allow(dead_code)]
    pub async fn get_next_healthy_service(&self) -> Option<ServiceInstance> {
        let services = self.services.read().await;
        let all_services: Vec<_> = services.values().cloned().collect();
        drop(services); // Release the lock

        // Check health status for all services
        let health_checks: Vec<bool> =
            futures::future::join_all(all_services.iter().map(|s| s.is_healthy())).await;

        let healthy_services: Vec<_> = all_services
            .into_iter()
            .zip(health_checks)
            .filter(|(_, healthy)| *healthy)
            .map(|(service, _)| service)
            .collect();

        if healthy_services.is_empty() {
            error!("No healthy services available");
            return None;
        }

        // Weighted round-robin selection
        let total_weight: u32 = healthy_services.iter().map(|s| s.weight).sum();
        if total_weight == 0 {
            // Fallback to simple round-robin
            let mut index = self.current_index.write().await;
            let service = healthy_services[*index % healthy_services.len()].clone();
            *index += 1;
            service.increment_request_count().await;
            return Some(service);
        }

        // Weighted selection
        let mut current_index = self.current_index.write().await;
        let target_weight = (*current_index % total_weight as usize) as u32;
        *current_index += 1;
        drop(current_index); // Release the lock

        let mut current_weight = 0;
        for service in &healthy_services {
            current_weight += service.weight;
            if current_weight > target_weight {
                service.increment_request_count().await;
                return Some(service.clone());
            }
        }

        // Fallback
        let service = healthy_services[0].clone();
        service.increment_request_count().await;
        Some(service)
    }

    /// Get next healthy service by model ID
    pub async fn get_next_healthy_service_by_model(
        &self,
        model_id: Option<&str>,
    ) -> Option<ServiceInstance> {
        let services = self.services.read().await;
        let all_services: Vec<_> = services.values().cloned().collect();
        drop(services); // Release the lock

        // Check health status for all services
        let health_checks: Vec<bool> =
            futures::future::join_all(all_services.iter().map(|s| s.is_healthy())).await;

        let mut healthy_services: Vec<_> = all_services
            .into_iter()
            .zip(health_checks)
            .filter(|(_, healthy)| *healthy)
            .map(|(service, _)| service)
            .collect();

        // Filter by model if specified
        if let Some(model_id) = model_id {
            let mut filtered_services = Vec::new();
            for service in &healthy_services {
                let models = service.models.read().await;
                if models.contains(&model_id.to_string()) {
                    filtered_services.push(service.clone());
                }
            }
            healthy_services = filtered_services;

            if healthy_services.is_empty() {
                warn!("No healthy services available for model '{}'", model_id);
                return None;
            }
        }

        if healthy_services.is_empty() {
            error!("No healthy services available");
            return None;
        }

        // Weighted round-robin selection (same as get_next_healthy_service)
        let total_weight: u32 = healthy_services.iter().map(|s| s.weight).sum();
        if total_weight == 0 {
            let mut index = self.current_index.write().await;
            let service = healthy_services[*index % healthy_services.len()].clone();
            *index += 1;
            service.increment_request_count().await;
            return Some(service);
        }

        let mut current_index = self.current_index.write().await;
        let target_weight = (*current_index % total_weight as usize) as u32;
        *current_index += 1;
        drop(current_index); // Release the lock

        let mut current_weight = 0;
        for service in &healthy_services {
            current_weight += service.weight;
            if current_weight > target_weight {
                service.increment_request_count().await;
                return Some(service.clone());
            }
        }

        let service = healthy_services[0].clone();
        service.increment_request_count().await;
        Some(service)
    }

    /// Start health check background task
    pub async fn start_health_checks(&self) {
        let services = self.services.clone();
        let health_checker = self.health_checker.clone();
        let interval = self.health_check_interval;
        let running = self.running.clone();

        info!("Health check task started (interval: {}s)", interval);

        std::mem::drop(tokio::spawn(async move {
            while *running.read().await {
                let services_clone = services.clone();
                let health_checker_clone = health_checker.clone();

                std::mem::drop(tokio::spawn(async move {
                    let services_guard = services_clone.read().await;
                    let services_list: Vec<_> = services_guard.values().cloned().collect();
                    drop(services_guard);

                    if !services_list.is_empty() {
                        // Perform health checks in parallel
                        let health_results: Vec<bool> =
                            futures::future::join_all(services_list.iter().map(|service| {
                                let health_checker = health_checker_clone.clone();
                                let service = service.clone();
                                async move { health_checker.check_health(&service).await }
                            }))
                            .await;

                        let healthy_count = health_results.iter().filter(|&&h| h).count();
                        info!(
                            "Health check completed: {}/{} services healthy",
                            healthy_count,
                            services_list.len()
                        );

                        // Log unhealthy services
                        for service in &services_list {
                            let error_count = *service.error_count.read().await;
                            let is_healthy = service.is_healthy().await;
                            if !is_healthy && error_count >= health_checker_clone.max_errors {
                                warn!(
                                    "Service {} is unhealthy (errors: {})",
                                    service.name, error_count
                                );
                            }
                        }
                    }
                }));

                sleep(Duration::from_secs(interval)).await;
            }
        }));
    }

    /// Start registry sync background task
    pub async fn start_registry_sync(&self) {
        let registry_client = match &self.registry_client {
            Some(client) => client.clone(),
            None => {
                warn!("Registry sync requested but no registry URL configured");
                return;
            }
        };

        let services = self.services.clone();
        let interval = self.registry_sync_interval;
        let grace_period = self.service_removal_grace_period;
        let running = self.running.clone();

        info!("Registry sync task started (interval: {}s)", interval);

        std::mem::drop(tokio::spawn(async move {
            while *running.read().await {
                let services_clone = services.clone();
                let registry_client_clone = registry_client.clone();

                std::mem::drop(tokio::spawn(async move {
                    match registry_client_clone.fetch_services(true).await {
                        Ok(registry_response) => {
                            let mut services_guard = services_clone.write().await;
                            let current_time = current_timestamp();
                            let registry_service_names: std::collections::HashSet<String> =
                                registry_response
                                    .services
                                    .iter()
                                    .map(|s| s.name.clone())
                                    .collect();

                            // Update or add services from registry
                            for registry_service in registry_response.services {
                                // Only add services that are OpenAI API services
                                let service_metadata = registry_service.metadata.clone();
                                if !service_metadata
                                    .get("type")
                                    .and_then(|v| v.as_str())
                                    .map(|s| s == "openai-api")
                                    .unwrap_or(false)
                                {
                                    continue;
                                }

                                let service_name = registry_service.name.clone();

                                if let Some(existing_service) =
                                    services_guard.get_mut(&service_name)
                                {
                                    // Update existing service
                                    existing_service.host = registry_service.host.clone();
                                    existing_service.port = registry_service.port;
                                    existing_service.url = registry_service.url.clone();
                                    existing_service
                                        .set_healthy(registry_service.is_healthy)
                                        .await;
                                    existing_service.metadata = service_metadata.clone();
                                    existing_service.update_last_seen().await;

                                    // Update models from metadata
                                    let models: Vec<String> = service_metadata
                                        .get("models")
                                        .and_then(|v| v.as_array())
                                        .map(|arr| {
                                            arr.iter()
                                                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                                .collect()
                                        })
                                        .unwrap_or_default();
                                    *existing_service.models.write().await = models;

                                    // Update babysitter URL
                                    let babysitter_port = existing_service.port + 1;
                                    existing_service.babysitter_url = format!(
                                        "http://{}:{}",
                                        existing_service.host, babysitter_port
                                    );
                                } else {
                                    // Add new service from registry
                                    let models: Vec<String> = service_metadata
                                        .get("models")
                                        .and_then(|v| v.as_array())
                                        .map(|arr| {
                                            arr.iter()
                                                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                                                .collect()
                                        })
                                        .unwrap_or_default();

                                    let models_for_log = models.clone();

                                    let new_service = ServiceInstance::new(
                                        registry_service.name.clone(),
                                        registry_service.host.clone(),
                                        registry_service.port,
                                        registry_service.weight,
                                        service_metadata,
                                    );

                                    *new_service.models.write().await = models;
                                    new_service.set_healthy(registry_service.is_healthy).await;
                                    new_service.update_last_seen().await;

                                    info!(
                                        "Added OpenAI API service from registry: {} at {} (babysitter: {}, models: {:?})",
                                        new_service.name, new_service.url, new_service.babysitter_url, models_for_log
                                    );

                                    services_guard.insert(service_name, new_service);
                                }
                            }

                            // Remove services that are no longer in registry (but keep static services)
                            let mut services_to_remove = Vec::new();
                            for (name, service) in services_guard.iter() {
                                if !registry_service_names.contains(name) {
                                    let is_static = service
                                        .metadata
                                        .get("static")
                                        .and_then(|v| v.as_bool())
                                        .unwrap_or(false);
                                    if !is_static {
                                        let last_seen = *service.last_seen.read().await;
                                        let time_since_last_seen = current_time - last_seen;
                                        if time_since_last_seen >= grace_period as f64 {
                                            services_to_remove.push(name.clone());
                                        }
                                    }
                                }
                            }

                            for service_name in services_to_remove {
                                services_guard.remove(&service_name);
                                info!(
                                    "Removed service from registry (after {}s grace period): {}",
                                    grace_period, service_name
                                );
                            }
                        }
                        Err(e) => {
                            warn!("Failed to sync with registry: {}", e);
                        }
                    }
                }));

                sleep(Duration::from_secs(interval)).await;
            }
        }));
    }

    /// Stop background tasks
    #[allow(dead_code)]
    pub async fn stop(&self) {
        let mut running = self.running.write().await;
        *running = false;
    }

    /// Get all services
    pub async fn get_all_services(&self) -> Vec<ServiceInstance> {
        let services = self.services.read().await;
        services.values().cloned().collect()
    }
}
