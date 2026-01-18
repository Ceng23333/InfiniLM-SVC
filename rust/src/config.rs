//! Configuration management for the router service

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Router configuration
#[derive(Debug, Clone)]
pub struct Config {
    pub router_port: u16,
    pub registry_url: Option<String>,
    pub static_services: Option<Vec<StaticService>>,
    pub health_check_interval: u64,
    pub health_check_timeout: u64,
    pub max_errors: u32,
    pub registry_sync_interval: u64,
    pub service_removal_grace_period: u64,
}

/// Static service configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StaticService {
    pub name: String,
    pub host: String,
    pub port: u16,
    #[serde(default = "default_weight")]
    pub weight: u32,
    #[serde(default)]
    pub metadata: serde_json::Value,
}

fn default_weight() -> u32 {
    1
}

impl Config {
    /// Create a new configuration from command-line arguments
    pub fn new(
        router_port: u16,
        registry_url: Option<String>,
        static_services_file: Option<String>,
        health_check_interval: u64,
        health_check_timeout: u64,
        max_errors: u32,
        registry_sync_interval: u64,
        service_removal_grace_period: u64,
    ) -> Result<Self> {
        let static_services = if let Some(file_path) = static_services_file {
            Some(Self::load_static_services(&file_path)?)
        } else {
            None
        };

        Ok(Config {
            router_port,
            registry_url,
            static_services,
            health_check_interval,
            health_check_timeout,
            max_errors,
            registry_sync_interval,
            service_removal_grace_period,
        })
    }

    /// Load static services from a JSON file
    fn load_static_services<P: AsRef<Path>>(file_path: P) -> Result<Vec<StaticService>> {
        let content = fs::read_to_string(&file_path)
            .with_context(|| format!("Failed to read static services file: {:?}", file_path.as_ref()))?;

        let config: serde_json::Value = serde_json::from_str(&content)
            .context("Failed to parse static services JSON")?;

        // Handle multiple possible formats:
        // 1. Direct array: [...]
        // 2. Object with "services" key: {"services": [...]}
        // 3. Object with "static_services.services" key: {"static_services": {"services": [...]}}
        let services = if let Some(services_array) = config.get("static_services")
            .and_then(|v| v.get("services"))
            .and_then(|v| v.as_array()) {
            services_array
        } else if let Some(services_array) = config.get("services").and_then(|v| v.as_array()) {
            services_array
        } else if let Some(services_array) = config.as_array() {
            services_array
        } else {
            anyhow::bail!("Invalid static services format: expected array or object with 'services' or 'static_services.services' key");
        };

        let static_services: Vec<StaticService> = serde_json::from_value(
            serde_json::Value::Array(services.clone())
        ).context("Failed to deserialize static services")?;

        Ok(static_services)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_static_services() {
        let json = r#"
        {
            "services": [
                {
                    "name": "test-service",
                    "host": "localhost",
                    "port": 8080,
                    "weight": 1
                }
            ]
        }
        "#;

        let temp_file = std::env::temp_dir().join("test_services.json");
        std::fs::write(&temp_file, json).unwrap();

        let services = Config::load_static_services(&temp_file).unwrap();
        assert_eq!(services.len(), 1);
        assert_eq!(services[0].name, "test-service");
        assert_eq!(services[0].host, "localhost");
        assert_eq!(services[0].port, 8080);

        std::fs::remove_file(&temp_file).unwrap();
    }
}
