//! HTTP handlers for the babysitter

use axum::{
    extract::State,
    http::StatusCode,
    response::Json,
    routing::get,
    Router,
};
use serde_json::json;
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{error, info};

use super::BabysitterState;

pub struct BabysitterHandlers {
    state: Arc<BabysitterState>,
}

impl BabysitterHandlers {
    pub fn new(state: Arc<BabysitterState>) -> Self {
        Self { state }
    }

    pub async fn start_server(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let app = Router::new()
            .route("/health", get(Self::health_handler))
            .route("/models", get(Self::models_handler))
            .route("/info", get(Self::info_handler))
            .with_state(self.state.clone());

        let port = self.state.babysitter_port();
        let addr = format!("0.0.0.0:{}", port);
        let listener = TcpListener::bind(&addr).await?;

        info!("Babysitter HTTP server started on port {}", port);

        axum::serve(listener, app).await?;
        Ok(())
    }

    async fn health_handler(
        State(state): State<Arc<BabysitterState>>,
    ) -> Result<Json<serde_json::Value>, StatusCode> {
        let process_running = {
            let process = state.process.read().await;
            process.as_ref().map_or(false, |p| {
                // Check if process is still running
                // Note: This is a simplified check - in production, use proper process status
                true // For now, assume running if process exists
            })
        };

        let service_port = {
            let port = state.service_port.read().await;
            *port
        };

        Ok(Json(json!({
            "status": "healthy",
            "service": state.config.service_name(),
            "babysitter": "enhanced",
            "infinilm_server_running": process_running,
            "infinilm_server_port": service_port,
            "timestamp": std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs()
        })))
    }

    async fn models_handler(
        State(state): State<Arc<BabysitterState>>,
    ) -> Result<Json<serde_json::Value>, StatusCode> {
        let service_port = {
            let port = state.service_port.read().await;
            *port
        };

        if service_port.is_none() {
            return Err(StatusCode::SERVICE_UNAVAILABLE);
        }

        // Proxy request to managed service
        let url = format!("http://{}:{}/models", state.config.host, service_port.unwrap());
        
        match reqwest::get(&url).await {
            Ok(response) => {
                if response.status().is_success() {
                    match response.json::<serde_json::Value>().await {
                        Ok(data) => Ok(Json(data)),
                        Err(e) => {
                            error!("Failed to parse models response: {}", e);
                            Err(StatusCode::INTERNAL_SERVER_ERROR)
                        }
                    }
                } else {
                    Err(StatusCode::SERVICE_UNAVAILABLE)
                }
            }
            Err(e) => {
                error!("Error proxying models request: {}", e);
                Err(StatusCode::SERVICE_UNAVAILABLE)
            }
        }
    }

    async fn info_handler(
        State(state): State<Arc<BabysitterState>>,
    ) -> Result<Json<serde_json::Value>, StatusCode> {
        let service_port = {
            let port = state.service_port.read().await;
            *port
        };

        let restart_count = {
            let count = state.restart_count.read().await;
            *count
        };

        let uptime = state.start_time.elapsed().as_secs();

        Ok(Json(json!({
            "name": state.config.service_name(),
            "host": state.config.host,
            "port": state.babysitter_port(),
            "url": format!("http://{}:{}", state.config.host, state.babysitter_port()),
            "service_type": state.config.service_type,
            "infinilm_server_port": service_port,
            "uptime": uptime,
            "restart_count": restart_count
        })))
    }
}
