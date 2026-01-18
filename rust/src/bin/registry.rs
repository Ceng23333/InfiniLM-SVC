//! Service Registry Server
//! Provides service discovery and registration for distributed InfiniLM deployments

use axum::{
    extract::{Path, Query},
    http::StatusCode,
    response::Json,
    routing::{delete, get, post, put},
    Router,
};
use clap::Parser;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::signal;
use tokio::sync::RwLock;
use tokio::time::{sleep, Instant};
use tracing::info;

/// Service information stored in registry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServiceInfo {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub hostname: String,
    pub url: String,
    pub status: String,
    pub timestamp: String,
    #[serde(skip)]
    pub last_heartbeat: Arc<RwLock<f64>>,
    #[serde(skip)]
    pub health_status: Arc<RwLock<String>>,
    pub metadata: HashMap<String, Value>,
}

impl ServiceInfo {
    pub fn new(
        name: String,
        host: String,
        port: u16,
        hostname: String,
        url: String,
        status: String,
        metadata: HashMap<String, Value>,
    ) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
            .unwrap()
            .to_rfc3339();

        Self {
            name,
            host,
            port,
            hostname,
            url,
            status,
            timestamp,
            last_heartbeat: Arc::new(RwLock::new(now as f64)),
            health_status: Arc::new(RwLock::new("unknown".to_string())),
            metadata,
        }
    }

    pub async fn is_healthy(&self) -> bool {
        if self.status != "running" {
            return false;
        }

        let last_heartbeat = *self.last_heartbeat.read().await;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as f64;

        // Consider service unhealthy if no heartbeat for 2 minutes
        (now - last_heartbeat) < 120.0
    }

    pub async fn to_dict(&self) -> serde_json::Value {
        let last_heartbeat = *self.last_heartbeat.read().await;
        let health_status = self.health_status.read().await.clone();
        let is_healthy = self.is_healthy().await;

        json!({
            "name": self.name,
            "host": self.host,
            "port": self.port,
            "hostname": self.hostname,
            "url": self.url,
            "status": self.status,
            "timestamp": self.timestamp,
            "last_heartbeat": last_heartbeat,
            "health_status": health_status,
            "is_healthy": is_healthy,
            "metadata": self.metadata,
        })
    }

    pub async fn update_heartbeat(&self) {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as f64;
        *self.last_heartbeat.write().await = now;
    }
}

/// Registry state
#[derive(Clone)]
pub struct RegistryState {
    services: Arc<RwLock<HashMap<String, ServiceInfo>>>,
    start_time: Instant,
    health_check_interval: u64,
    health_check_timeout: u64,
    cleanup_interval: u64,
}

impl RegistryState {
    pub fn new(
        health_check_interval: u64,
        health_check_timeout: u64,
        cleanup_interval: u64,
    ) -> Self {
        Self {
            services: Arc::new(RwLock::new(HashMap::new())),
            start_time: Instant::now(),
            health_check_interval,
            health_check_timeout,
            cleanup_interval,
        }
    }
}

/// Command-line arguments
#[derive(Parser, Debug)]
#[command(name = "infini-registry")]
#[command(about = "Service Registry for InfiniLM Distributed Services")]
struct Args {
    /// Registry port
    #[arg(long, default_value = "8081")]
    port: u16,

    /// Health check interval in seconds
    #[arg(long, default_value = "30")]
    health_interval: u64,

    /// Health check timeout in seconds
    #[arg(long, default_value = "5")]
    health_timeout: u64,

    /// Cleanup interval in seconds
    #[arg(long, default_value = "60")]
    cleanup_interval: u64,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    let args = Args::parse();

    info!("Starting InfiniLM Service Registry on port {}", args.port);

    // Create registry state
    let state = RegistryState::new(
        args.health_interval,
        args.health_timeout,
        args.cleanup_interval,
    );

    // Start background tasks
    let state_clone = state.clone();
    tokio::spawn(async move {
        perform_health_checks(state_clone).await;
    });

    let state_clone = state.clone();
    tokio::spawn(async move {
        cleanup_stale_services(state_clone).await;
    });

    // Build router
    let app = create_router(state);

    // Start server
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", args.port)).await?;
    info!("Service registry listening on http://0.0.0.0:{}", args.port);

    // Graceful shutdown
    tokio::select! {
        result = axum::serve(listener, app) => {
            if let Err(e) = result {
                error!("Server error: {}", e);
            }
        }
        _ = signal::ctrl_c() => {
            info!("Received shutdown signal, shutting down gracefully...");
        }
    }

    info!("Service registry stopped");
    Ok(())
}

fn create_router(state: RegistryState) -> Router {
    Router::new()
        .route("/health", get(health_handler))
        .route("/services", get(services_handler))
        .route("/services", post(register_service_handler))
        .route("/services/:name", get(get_service_handler))
        .route("/services/:name", put(update_service_handler))
        .route("/services/:name", delete(unregister_service_handler))
        .route("/services/:name/health", get(service_health_handler))
        .route("/services/:name/heartbeat", post(heartbeat_handler))
        .route("/stats", get(stats_handler))
        .with_state(state)
}

async fn health_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
) -> Json<Value> {
    let services = state.services.read().await;
    let services_vec: Vec<_> = services.values().collect();
    let mut healthy_count = 0;
    for service in services_vec {
        if service.is_healthy().await {
            healthy_count += 1;
        }
    }
    let total = services.len();

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap()
        .to_rfc3339();

    Json(json!({
        "status": "healthy",
        "registry": "running",
        "registered_services": total,
        "healthy_services": healthy_count,
        "timestamp": timestamp
    }))
}

#[derive(Deserialize)]
struct ServicesQuery {
    status: Option<String>,
    healthy: Option<String>,
}

async fn services_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Query(params): Query<ServicesQuery>,
) -> Json<Value> {
    let services = state.services.read().await;
    let mut services_list: Vec<Value> = Vec::new();

    for service in services.values() {
        let service_dict = service.to_dict().await;
        services_list.push(service_dict);
    }

    // Filter by status if requested
    if let Some(status_filter) = &params.status {
        services_list.retain(|s| {
            s.get("status")
                .and_then(|v| v.as_str())
                .map(|s| s == status_filter)
                .unwrap_or(false)
        });
    }

    // Filter by health if requested
    if let Some(healthy_filter) = &params.healthy {
        let healthy_only = healthy_filter.to_lowercase() == "true";
        services_list.retain(|s| {
            s.get("is_healthy")
                .and_then(|v| v.as_bool())
                .map(|h| h == healthy_only)
                .unwrap_or(false)
        });
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap()
        .to_rfc3339();

    Json(json!({
        "services": services_list,
        "total": services_list.len(),
        "timestamp": timestamp
    }))
}

async fn get_service_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Path(name): Path<String>,
) -> Result<Json<Value>, StatusCode> {
    let services = state.services.read().await;
    if let Some(service) = services.get(&name) {
        Ok(Json(service.to_dict().await))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

#[derive(Deserialize)]
struct RegisterServiceRequest {
    name: String,
    host: String,
    port: u16,
    hostname: String,
    url: String,
    status: String,
    #[serde(default)]
    timestamp: Option<String>,
    #[serde(default)]
    metadata: HashMap<String, Value>,
}

async fn register_service_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Json(payload): Json<RegisterServiceRequest>,
) -> Result<(StatusCode, Json<Value>), StatusCode> {
    let service_info = ServiceInfo::new(
        payload.name.clone(),
        payload.host,
        payload.port,
        payload.hostname,
        payload.url.clone(),
        payload.status,
        payload.metadata,
    );

    let mut services = state.services.write().await;
    services.insert(payload.name.clone(), service_info.clone());

    info!("Registered service: {} at {}", payload.name, payload.url);

    Ok((
        StatusCode::CREATED,
        Json(json!({
            "message": format!("Service '{}' registered successfully", payload.name),
            "service": service_info.to_dict().await
        })),
    ))
}

#[derive(Deserialize)]
struct UpdateServiceRequest {
    #[serde(default)]
    host: Option<String>,
    #[serde(default)]
    port: Option<u16>,
    #[serde(default)]
    hostname: Option<String>,
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    metadata: Option<HashMap<String, Value>>,
}

async fn update_service_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Path(name): Path<String>,
    Json(payload): Json<UpdateServiceRequest>,
) -> Result<Json<Value>, StatusCode> {
    let mut services = state.services.write().await;
    let service = services.get_mut(&name).ok_or(StatusCode::NOT_FOUND)?;

    if let Some(host) = payload.host {
        service.host = host;
    }
    if let Some(port) = payload.port {
        service.port = port;
    }
    if let Some(hostname) = payload.hostname {
        service.hostname = hostname;
    }
    if let Some(url) = payload.url {
        service.url = url;
    }
    if let Some(status) = payload.status {
        service.status = status;
    }
    if let Some(metadata) = payload.metadata {
        service.metadata = metadata;
    }

    service.update_heartbeat().await;

    info!("Updated service: {}", name);

    Ok(Json(json!({
        "message": format!("Service '{}' updated successfully", name),
        "service": service.to_dict().await
    })))
}

async fn unregister_service_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Path(name): Path<String>,
) -> Result<Json<Value>, StatusCode> {
    let mut services = state.services.write().await;
    if services.remove(&name).is_some() {
        info!("Unregistered service: {}", name);
        Ok(Json(json!({
            "message": format!("Service '{}' unregistered successfully", name)
        })))
    } else {
        Err(StatusCode::NOT_FOUND)
    }
}

async fn service_health_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Path(name): Path<String>,
) -> Result<Json<Value>, StatusCode> {
    let services = state.services.read().await;
    let service = services.get(&name).ok_or(StatusCode::NOT_FOUND)?;

    // Perform actual health check
    let check_url = if service.metadata.get("type").and_then(|v| v.as_str()) == Some("openai-api") {
        // For openai-api services, check babysitter URL (port + 1)
        format!("http://{}:{}", service.host, service.port + 1)
    } else {
        service.url.clone()
    };

    let health_status = check_service_health(&check_url, state.health_check_timeout).await;
    *service.health_status.write().await = health_status.clone();

    if health_status == "healthy" {
        service.update_heartbeat().await;
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap()
        .to_rfc3339();

    Ok(Json(json!({
        "service": name,
        "health_status": health_status,
        "is_healthy": service.is_healthy().await,
        "last_heartbeat": *service.last_heartbeat.read().await,
        "timestamp": timestamp
    })))
}

async fn heartbeat_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
    Path(name): Path<String>,
    payload: Option<Json<Value>>,
) -> Result<Json<Value>, StatusCode> {
    let services = state.services.read().await;
    let service = services.get(&name).ok_or(StatusCode::NOT_FOUND)?;

    service.update_heartbeat().await;

    // Update status if provided
    if let Some(Json(data)) = payload {
        if let Some(status) = data.get("status").and_then(|v| v.as_str()) {
            drop(services);
            let mut services = state.services.write().await;
            if let Some(service) = services.get_mut(&name) {
                service.status = status.to_string();
            }
        }
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap()
        .to_rfc3339();

    Ok(Json(json!({
        "message": "Heartbeat received",
        "timestamp": timestamp
    })))
}

async fn stats_handler(
    axum::extract::State(state): axum::extract::State<RegistryState>,
) -> Json<Value> {
    let services = state.services.read().await;
    let services_vec: Vec<_> = services.values().collect();
    let mut healthy_count = 0;
    for service in services_vec {
        if service.is_healthy().await {
            healthy_count += 1;
        }
    }
    let total = services.len();

    let mut status_counts: HashMap<String, usize> = HashMap::new();
    let mut host_counts: HashMap<String, usize> = HashMap::new();

    for service in services.values() {
        *status_counts.entry(service.status.clone()).or_insert(0) += 1;
        *host_counts.entry(service.host.clone()).or_insert(0) += 1;
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let timestamp = chrono::DateTime::<chrono::Utc>::from_timestamp(now as i64, 0)
        .unwrap()
        .to_rfc3339();

    Json(json!({
        "total_services": total,
        "healthy_services": healthy_count,
        "unhealthy_services": total - healthy_count,
        "status_distribution": status_counts,
        "host_distribution": host_counts,
        "uptime": state.start_time.elapsed().as_secs(),
        "timestamp": timestamp
    }))
}

async fn check_service_health(url: &str, timeout_secs: u64) -> String {
    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(timeout_secs))
        .build()
        .unwrap_or_default();

    match client.get(format!("{}/health", url)).send().await {
        Ok(response) => {
            if response.status().is_success() {
                "healthy".to_string()
            } else {
                "unhealthy".to_string()
            }
        }
        Err(_) => "unhealthy".to_string(),
    }
}

async fn perform_health_checks(state: RegistryState) {
    loop {
        sleep(Duration::from_secs(state.health_check_interval)).await;

        let services = {
            let services_guard = state.services.read().await;
            services_guard.values().cloned().collect::<Vec<_>>()
        };

        if !services.is_empty() {
            let mut healthy_count = 0;
            for service in &services {
                let check_url = if service.metadata.get("type").and_then(|v| v.as_str())
                    == Some("openai-api")
                {
                    format!("http://{}:{}", service.host, service.port + 1)
                } else if service.metadata.get("type").and_then(|v| v.as_str())
                    == Some("babysitter")
                {
                    service.url.clone()
                } else {
                    service.url.clone()
                };

                let health_status =
                    check_service_health(&check_url, state.health_check_timeout).await;
                *service.health_status.write().await = health_status.clone();

                if health_status == "healthy" {
                    healthy_count += 1;
                }
            }

            info!(
                "Health check completed: {}/{} services healthy",
                healthy_count,
                services.len()
            );
        }
    }
}

async fn cleanup_stale_services(state: RegistryState) {
    loop {
        sleep(Duration::from_secs(state.cleanup_interval)).await;

        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as f64;

        // Collect stale service names (need to read heartbeats first)
        let stale_services: Vec<String> = {
            let services = state.services.read().await;
            let mut stale = Vec::new();
            for (name, service) in services.iter() {
                let last_heartbeat = *service.last_heartbeat.read().await;
                // Remove services that haven't sent heartbeat for 5 minutes
                if (now - last_heartbeat) > 300.0 {
                    stale.push(name.clone());
                }
            }
            stale
        };

        // Remove stale services
        if !stale_services.is_empty() {
            let mut services = state.services.write().await;
            for name in &stale_services {
                services.remove(name);
                info!("Removed stale service: {}", name);
            }
            info!("Cleaned up {} stale services", stale_services.len());
        }
    }
}
