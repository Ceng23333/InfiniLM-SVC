//! Enhanced Babysitter for InfiniLM Services
//! Manages service lifecycle, health monitoring, and registry integration

use anyhow::Result;
use std::sync::Arc;
use std::time::Instant;
use tokio::signal;
use tokio::sync::RwLock;
use tracing::info;

mod config;
mod config_file;
mod handlers;
mod process_manager;
mod registry_client;

use anyhow::Context;
use config::BabysitterConfig;
use config_file::BabysitterConfigFile;
use handlers::BabysitterHandlers;
use process_manager::ProcessManager;
use registry_client::BabysitterRegistryClient;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    // Parse CLI arguments
    let cli_config = <BabysitterConfig as clap::Parser>::parse();

    // Load config from file if specified, otherwise use CLI config
    let config = if let Some(config_file) = &cli_config.config_file {
        // Load from TOML file and merge with CLI args (CLI takes precedence)
        let file_config = BabysitterConfigFile::from_file(config_file)
            .with_context(|| format!("Failed to load config file: {:?}", config_file))?;
        let mut merged = file_config.to_cli_config();

        // Override with CLI values if provided
        if cli_config.name.is_some() {
            merged.name = cli_config.name.clone();
        }
        if let Some(port) = cli_config.port {
            merged.port = Some(port);
        }
        if cli_config.registry_url.is_some() {
            merged.registry_url = cli_config.registry_url.clone();
        }
        // ... add more overrides as needed

        merged
    } else {
        // Validate required CLI arguments when not using config file
        if cli_config.port.is_none() {
            anyhow::bail!("--port is required when --config-file is not provided");
        }
        cli_config
    };

    info!("Starting Enhanced Babysitter");
    info!("Service: {}", config.service_name());
    let port = config.port.expect("Port must be set");
    info!("Port: {} (babysitter: {})", port, port + 1);
    info!("Registry: {:?}", config.registry_url);

    // Load config file if specified
    let config_file = if let Some(config_file_path) = &config.config_file {
        Some(
            BabysitterConfigFile::from_file(config_file_path)
                .with_context(|| format!("Failed to load config file: {:?}", config_file_path))?,
        )
    } else {
        None
    };

    // Create shared state
    let state = Arc::new(BabysitterState {
        config: config.clone(),
        config_file,
        process: Arc::new(RwLock::new(None)),
        service_port: Arc::new(RwLock::new(None)),
        start_time: Instant::now(),
        restart_count: Arc::new(RwLock::new(0)),
    });

    // Start HTTP server
    let handlers = BabysitterHandlers::new(state.clone());
    let server_handle = tokio::spawn(async move {
        if let Err(e) = handlers.start_server().await {
            tracing::error!("HTTP server error: {}", e);
        }
    });

    // Start process manager
    let process_manager = ProcessManager::new(state.clone());
    let process_handle = tokio::spawn(async move { process_manager.run().await });

    // Start registry client (if configured)
    if let Some(registry_url) = &config.registry_url {
        let registry_client = BabysitterRegistryClient::new(registry_url.clone(), state.clone());
        let registry_handle = tokio::spawn(async move { registry_client.run().await });

        // Wait for shutdown signal
        signal::ctrl_c().await?;
        info!("Received shutdown signal, cleaning up...");

        // Stop registry client
        registry_handle.abort();
    } else {
        // Wait for shutdown signal
        signal::ctrl_c().await?;
        info!("Received shutdown signal, cleaning up...");
    }

    // Stop process manager
    process_handle.abort();

    // Stop HTTP server
    server_handle.abort();

    info!("Babysitter stopped");
    Ok(())
}

/// Shared state for the babysitter
#[derive(Clone)]
pub struct BabysitterState {
    config: BabysitterConfig,
    config_file: Option<BabysitterConfigFile>,
    process: Arc<RwLock<Option<std::process::Child>>>,
    service_port: Arc<RwLock<Option<u16>>>,
    start_time: Instant,
    restart_count: Arc<RwLock<u32>>,
}

impl BabysitterState {
    pub fn babysitter_port(&self) -> u16 {
        self.config.port.expect("Port must be set") + 1
    }

    pub fn service_target_port(&self) -> u16 {
        self.config.port.expect("Port must be set")
    }
}
