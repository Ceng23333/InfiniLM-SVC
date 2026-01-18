//! InfiniLM Distributed Router Service
//! High-performance router for distributed InfiniLM services with service discovery,
//! load balancing, and model-aware routing.

use anyhow::Result;
use clap::Parser;
use std::sync::Arc;
use tokio::signal;
use tracing::{error, info};

mod config;
mod handlers;
mod models;
mod proxy;
mod registry;
mod router;
mod utils;

use config::Config;
use router::load_balancer::LoadBalancer;

/// InfiniLM Distributed Router Service
#[derive(Parser, Debug)]
#[command(name = "infini-router")]
#[command(about = "High-performance distributed router for InfiniLM services", long_about = None)]
struct Args {
    /// Router port
    #[arg(long, default_value = "8080")]
    router_port: u16,

    /// Service registry URL for dynamic service discovery
    #[arg(long)]
    registry_url: Option<String>,

    /// JSON file with static service configurations
    #[arg(long)]
    static_services: Option<String>,

    /// Health check interval in seconds
    #[arg(long, default_value = "30")]
    health_interval: u64,

    /// Health check timeout in seconds
    #[arg(long, default_value = "5")]
    health_timeout: u64,

    /// Max errors before marking service unhealthy
    #[arg(long, default_value = "3")]
    max_errors: u32,

    /// Registry sync interval in seconds
    #[arg(long, default_value = "10")]
    registry_sync_interval: u64,

    /// Grace period in seconds before removing services that disappear from registry
    #[arg(long, default_value = "60")]
    service_removal_grace_period: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let args = Args::parse();

    info!("Starting InfiniLM Distributed Router Service");
    info!("Router port: {}", args.router_port);
    info!("Registry URL: {:?}", args.registry_url);

    // Create configuration
    let config = Config::new(
        args.router_port,
        args.registry_url,
        args.static_services,
        args.health_interval,
        args.health_timeout,
        args.max_errors,
        args.registry_sync_interval,
        args.service_removal_grace_period,
    )?;

    // Create load balancer
    let load_balancer = Arc::new(LoadBalancer::new(&config).await?);

    // Start background tasks
    let health_checker = load_balancer.clone();
    tokio::spawn(async move {
        health_checker.start_health_checks().await;
    });

    let registry_sync = load_balancer.clone();
    if config.registry_url.is_some() {
        tokio::spawn(async move {
            registry_sync.start_registry_sync().await;
        });
    }

    // Build router
    let app = handlers::create_router(load_balancer.clone());

    // Start server
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", config.router_port)).await?;
    info!("Router listening on http://0.0.0.0:{}", config.router_port);

    // Handle graceful shutdown
    let shutdown_signal = async {
        let ctrl_c = async {
            signal::ctrl_c()
                .await
                .expect("failed to install Ctrl+C handler");
        };

        #[cfg(unix)]
        let terminate = async {
            signal::unix::signal(signal::unix::SignalKind::terminate())
                .expect("failed to install signal handler")
                .recv()
                .await;
        };

        #[cfg(not(unix))]
        let terminate = std::future::pending::<()>();

        tokio::select! {
            _ = ctrl_c => {},
            _ = terminate => {},
        }
    };

    // Run server with graceful shutdown
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal)
        .await?;

    info!("Router shutdown complete");
    Ok(())
}
