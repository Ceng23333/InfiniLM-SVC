//! Health check manager

use crate::router::service_instance::ServiceInstance;
use reqwest::Client;
use std::time::Duration;
use tracing::warn;

/// Health checker
pub struct HealthChecker {
    client: Client,
    timeout: Duration,
    pub max_errors: u32,
}

impl HealthChecker {
    pub fn new(timeout: Duration, max_errors: u32) -> Self {
        let client = Client::builder()
            .timeout(timeout)
            .build()
            .expect("Failed to create health check HTTP client");

        HealthChecker {
            client,
            timeout,
            max_errors,
        }
    }

    /// Perform health check on a service instance using babysitter URL
    pub async fn check_health(&self, service: &ServiceInstance) -> bool {
        let check_url = format!("{}/health", service.babysitter_url);

        let start_time = std::time::Instant::now();

        match self.client.get(&check_url).send().await {
            Ok(response) => {
                let response_time = start_time.elapsed().as_secs_f64();
                *service.response_time.write().await = response_time;
                *service.last_check.write().await = crate::utils::time::current_timestamp();

                if response.status().is_success() {
                    service.set_healthy(true).await;
                    *service.error_count.write().await = 0;
                    true
                } else {
                    service.set_healthy(false).await;
                    let mut error_count = service.error_count.write().await;
                    *error_count += 1;
                    false
                }
            }
            Err(e) => {
                warn!(
                    "Health check failed for service {} (babysitter: {}): {}",
                    service.name, service.babysitter_url, e
                );
                service.set_healthy(false).await;
                let mut error_count = service.error_count.write().await;
                *error_count += 1;
                *service.last_check.write().await = crate::utils::time::current_timestamp();
                false
            }
        }
    }

    /// Check if service should be marked unhealthy based on error count
    pub fn should_mark_unhealthy(&self, error_count: u32) -> bool {
        error_count >= self.max_errors
    }
}
