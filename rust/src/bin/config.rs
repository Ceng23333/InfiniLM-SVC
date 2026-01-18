//! Configuration for the babysitter

use clap::Parser;
use std::path::PathBuf;

#[derive(Parser, Debug, Clone)]
#[command(name = "infini-babysitter")]
#[command(about = "Enhanced Babysitter for InfiniLM Services")]
pub struct BabysitterConfig {
    /// Service name (auto-generated if not provided)
    #[arg(long)]
    pub name: Option<String>,

    /// Host address
    #[arg(long, default_value = "localhost")]
    pub host: String,

    /// Service port (babysitter will use port+1)
    /// Required if config_file is not provided
    #[arg(long)]
    pub port: Option<u16>,

    /// Service type: "InfiniLM", "InfiniLM-Rust", "vLLM", "mock", or "command"
    #[arg(long, default_value = "command")]
    pub service_type: String,

    /// Path to config file, model path, or command to run (depending on service_type)
    #[arg(long)]
    pub path: Option<PathBuf>,

    /// Command to run (for service_type="command")
    /// If provided, this command will be executed directly
    #[arg(long)]
    pub command: Option<String>,

    /// Command arguments (space-separated, for service_type="command")
    #[arg(long)]
    pub args: Option<String>,

    /// Working directory for the command
    #[arg(long)]
    pub work_dir: Option<PathBuf>,

    /// Registry URL (optional)
    #[arg(long)]
    pub registry_url: Option<String>,

    /// Router URL (optional, for future use)
    #[arg(long)]
    pub router_url: Option<String>,

    /// Maximum number of restarts
    #[arg(long, default_value = "10000")]
    pub max_restarts: u32,

    /// Delay between restarts (seconds)
    #[arg(long, default_value = "5")]
    pub restart_delay: u64,

    /// Heartbeat interval (seconds)
    #[arg(long, default_value = "30")]
    pub heartbeat_interval: u64,

    /// Configuration file (TOML format) - if provided, loads config from file
    /// CLI arguments override file values
    #[arg(long)]
    pub config_file: Option<PathBuf>,

    // InfiniLM Python specific
    /// Device type (for InfiniLM Python)
    #[arg(long)]
    pub dev: Option<String>,

    /// Number of devices (for InfiniLM Python)
    #[arg(long)]
    pub ndev: Option<u32>,

    /// Max batch size (for InfiniLM Python)
    #[arg(long)]
    pub max_batch: Option<u32>,

    /// Environment variables (key=value pairs, space-separated)
    /// Example: --env "CUDA_VISIBLE_DEVICES=0" "VLLM_WORKER_MULTIPROC_METHOD=spawn"
    #[arg(long, value_delimiter = ' ')]
    pub env: Vec<String>,
}

impl BabysitterConfig {
    pub fn service_name(&self) -> String {
        self.name.clone().unwrap_or_else(|| {
            let port_str = self
                .port
                .map(|p| p.to_string())
                .unwrap_or_else(|| "unknown".to_string());
            format!(
                "{}-{}",
                self.service_type.to_lowercase().replace(' ', "-"),
                port_str
            )
        })
    }

    pub fn is_command_based(&self) -> bool {
        self.service_type == "command" || self.command.is_some()
    }
}
