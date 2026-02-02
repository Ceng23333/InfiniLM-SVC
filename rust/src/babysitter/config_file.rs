//! Configuration file support for the babysitter

use anyhow::Context;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;

/// Babysitter configuration file structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BabysitterConfigFile {
    /// Service name
    pub name: Option<String>,

    /// Host address
    #[serde(default = "default_host")]
    pub host: String,

    /// Service port (babysitter will use port+1)
    pub port: u16,

    /// Registry URL (optional)
    pub registry_url: Option<String>,

    /// Router URL (optional)
    pub router_url: Option<String>,

    /// Babysitter settings
    #[serde(default)]
    pub babysitter: BabysitterSettings,

    /// Backend configuration
    pub backend: BackendConfig,
}

fn default_host() -> String {
    "localhost".to_string()
}

/// Babysitter-specific settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BabysitterSettings {
    /// Maximum number of restarts
    #[serde(default = "default_max_restarts")]
    pub max_restarts: u32,

    /// Delay between restarts (seconds)
    #[serde(default = "default_restart_delay")]
    pub restart_delay: u64,

    /// Heartbeat interval (seconds)
    #[serde(default = "default_heartbeat_interval")]
    pub heartbeat_interval: u64,
}

fn default_max_restarts() -> u32 {
    10000
}

fn default_restart_delay() -> u64 {
    5
}

fn default_heartbeat_interval() -> u64 {
    30
}

impl Default for BabysitterSettings {
    fn default() -> Self {
        Self {
            max_restarts: default_max_restarts(),
            restart_delay: default_restart_delay(),
            heartbeat_interval: default_heartbeat_interval(),
        }
    }
}

/// Backend configuration - supports any backend type
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum BackendConfig {
    /// Command-based backend (universal)
    #[serde(rename = "command")]
    Command {
        /// Command to execute
        command: String,
        /// Command arguments (as array for better parsing)
        #[serde(default)]
        args: Vec<String>,
        /// Working directory
        work_dir: Option<PathBuf>,
        /// Environment variables
        #[serde(default)]
        env: HashMap<String, String>,
    },

    /// vLLM backend
    #[serde(rename = "vllm")]
    #[allow(clippy::upper_case_acronyms)]
    VLLM {
        /// Model path
        model: PathBuf,
        /// Additional vLLM arguments
        #[serde(default)]
        args: Vec<String>,
        /// Working directory
        work_dir: Option<PathBuf>,
        /// Environment variables
        #[serde(default)]
        env: HashMap<String, String>,
    },

    /// Mock backend
    #[serde(rename = "mock")]
    Mock {
        /// List of models to support
        models: Vec<String>,
    },

    /// InfiniLM-Rust backend
    #[serde(rename = "infinilm-rust")]
    InfiniLMRust {
        /// Config file path
        config_file: PathBuf,
        /// Working directory
        work_dir: Option<PathBuf>,
    },

    /// InfiniLM Python backend
    #[serde(rename = "infinilm")]
    InfiniLM {
        /// Model path
        model_path: PathBuf,
        /// Additional arguments
        #[serde(default)]
        args: Vec<String>,
        /// Working directory
        work_dir: Option<PathBuf>,
        /// Environment variables
        #[serde(default)]
        env: HashMap<String, String>,
    },
}

impl BabysitterConfigFile {
    /// Load configuration from a TOML file
    pub fn from_file<P: AsRef<std::path::Path>>(path: P) -> anyhow::Result<Self> {
        let content = std::fs::read_to_string(path.as_ref())
            .with_context(|| format!("Failed to read config file: {:?}", path.as_ref()))?;

        let config: BabysitterConfigFile = toml::from_str(&content)
            .with_context(|| format!("Failed to parse TOML config file: {:?}", path.as_ref()))?;

        Ok(config)
    }

    /// Convert to CLI-compatible config
    pub fn to_cli_config(&self) -> super::config::BabysitterConfig {
        use super::config::BabysitterConfig;

        BabysitterConfig {
            name: self.name.clone(),
            host: self.host.clone(),
            port: Some(self.port),
            service_type: self.backend.service_type_name().to_string(),
            path: self.backend.path(),
            command: self.backend.command(),
            args: self.backend.args_string(),
            work_dir: self.backend.work_dir(),
            registry_url: self.registry_url.clone(),
            router_url: self.router_url.clone(),
            max_restarts: self.babysitter.max_restarts,
            restart_delay: self.babysitter.restart_delay,
            heartbeat_interval: self.babysitter.heartbeat_interval,
            config_file: None,
            dev: None,
            ndev: None,
            max_batch: None,
            env: vec![], // Environment vars handled separately
        }
    }

    /// Get environment variables from backend config
    pub fn backend_env(&self) -> HashMap<String, String> {
        self.backend.env()
    }
}

impl BackendConfig {
    fn service_type_name(&self) -> &'static str {
        match self {
            BackendConfig::Command { .. } => "command",
            BackendConfig::VLLM { .. } => "vLLM",
            BackendConfig::Mock { .. } => "mock",
            BackendConfig::InfiniLMRust { .. } => "InfiniLM-Rust",
            BackendConfig::InfiniLM { .. } => "InfiniLM",
        }
    }

    fn path(&self) -> Option<PathBuf> {
        match self {
            BackendConfig::VLLM { model, .. } => Some(model.clone()),
            BackendConfig::InfiniLMRust { config_file, .. } => Some(config_file.clone()),
            BackendConfig::InfiniLM { model_path, .. } => Some(model_path.clone()),
            _ => None,
        }
    }

    fn command(&self) -> Option<String> {
        match self {
            BackendConfig::Command { command, .. } => Some(command.clone()),
            _ => None,
        }
    }

    fn args_string(&self) -> Option<String> {
        match self {
            BackendConfig::Command { args, .. }
            | BackendConfig::VLLM { args, .. }
            | BackendConfig::InfiniLM { args, .. } => {
                if args.is_empty() {
                    None
                } else {
                    Some(args.join(" "))
                }
            }
            BackendConfig::Mock { models } => Some(models.join(",")),
            _ => None,
        }
    }

    fn work_dir(&self) -> Option<PathBuf> {
        match self {
            BackendConfig::Command { work_dir, .. }
            | BackendConfig::VLLM { work_dir, .. }
            | BackendConfig::InfiniLMRust { work_dir, .. }
            | BackendConfig::InfiniLM { work_dir, .. } => work_dir.clone(),
            _ => None,
        }
    }

    pub fn env(&self) -> HashMap<String, String> {
        match self {
            BackendConfig::Command { env, .. }
            | BackendConfig::VLLM { env, .. }
            | BackendConfig::InfiniLM { env, .. } => env.clone(),
            _ => HashMap::new(),
        }
    }
}
