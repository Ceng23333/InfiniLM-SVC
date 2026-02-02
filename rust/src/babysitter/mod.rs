//! Babysitter module for service lifecycle management

pub mod config;
pub mod config_file;
pub mod handlers;
pub mod process_manager;
pub mod registry_client;

use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use config::BabysitterConfig;
use config_file::BabysitterConfigFile;

/// Shared state for the babysitter
#[derive(Clone)]
pub struct BabysitterState {
    pub config: BabysitterConfig,
    pub config_file: Option<BabysitterConfigFile>,
    pub process: Arc<RwLock<Option<tokio::process::Child>>>,
    pub service_port: Arc<RwLock<Option<u16>>>,
    pub start_time: Instant,
    pub restart_count: Arc<RwLock<u32>>,
}

impl BabysitterState {
    pub fn babysitter_port(&self) -> u16 {
        self.config.port.expect("Port must be set") + 1
    }

    pub fn service_target_port(&self) -> u16 {
        self.config.port.expect("Port must be set")
    }
}
