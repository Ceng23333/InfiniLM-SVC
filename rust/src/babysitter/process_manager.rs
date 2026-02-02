//! Process management for the babysitter

use crate::babysitter::BabysitterState;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command as TokioCommand;
use tokio::time::{sleep, timeout};
use tracing::{error, info, warn};

pub struct ProcessManager {
    state: Arc<BabysitterState>,
}

impl ProcessManager {
    pub fn new(state: Arc<BabysitterState>) -> Self {
        Self { state }
    }

    pub async fn run(&self) {
        loop {
            // Start the service
            if let Err(e) = self.start_service().await {
                error!("Failed to start service: {}", e);
            }

            // Monitor the service
            self.monitor_service().await;

            // Check restart limit
            let restart_count = {
                let count = self.state.restart_count.read().await;
                *count
            };

            if restart_count >= self.state.config.max_restarts {
                error!(
                    "Maximum restart limit ({}) reached",
                    self.state.config.max_restarts
                );
                break;
            }

            // Increment restart count
            {
                let mut count = self.state.restart_count.write().await;
                *count += 1;
            }

            info!(
                "Service crashed, restarting in {} seconds... (restart {}/{})",
                self.state.config.restart_delay,
                restart_count + 1,
                self.state.config.max_restarts
            );

            sleep(Duration::from_secs(self.state.config.restart_delay)).await;
        }
    }

    async fn start_service(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Clean up any existing process before starting a new one
        {
            let mut process = self.state.process.write().await;
            if let Some(mut child) = process.take() {
                let _ = child.kill().await;
                let _ = child.wait().await;
                info!("Cleaned up previous process");
            }
        }

        info!("Starting {} service...", self.state.config.service_type);

        let mut cmd = if self.state.config.is_command_based() {
            self.build_command_based()?
        } else if self.state.config.service_type == "InfiniLM-Rust" {
            self.build_rust_command()?
        } else if self.state.config.service_type == "InfiniLM" {
            self.build_python_command()?
        } else if self.state.config.service_type == "vLLM" {
            self.build_vllm_command()?
        } else if self.state.config.service_type == "mock" {
            self.build_mock_command()?
        } else {
            return Err(format!("Unknown service type: {}", self.state.config.service_type).into());
        };

        // Set working directory if specified
        if let Some(work_dir) = &self.state.config.work_dir {
            cmd.current_dir(work_dir);
        }

        // Set environment variables from config file if available
        if let Some(config_file) = &self.state.config_file {
            let env_vars = config_file.backend_env();
            if !env_vars.is_empty() {
                info!("Setting {} environment variables from config file", env_vars.len());
                for (key, value) in &env_vars {
                    info!("  {}={}", key, value);
                }
                // Inherit parent environment and merge with config env vars
                cmd.envs(std::env::vars());
                cmd.envs(env_vars);
            } else {
                warn!("Config file has no environment variables");
            }
        } else {
            warn!("No config file available for environment variables");
        }

        // Convert std::process::Command to tokio::process::Command for async I/O
        let mut tokio_cmd = TokioCommand::new(cmd.get_program());
        for arg in cmd.get_args() {
            tokio_cmd.arg(arg);
        }
        if let Some(dir) = cmd.get_current_dir() {
            tokio_cmd.current_dir(dir);
        }
        for (key, value) in cmd.get_envs() {
            if let Some(val) = value {
                tokio_cmd.env(key, val);
            }
        }
        tokio_cmd.stdout(Stdio::piped());
        tokio_cmd.stderr(Stdio::piped());

        // Start the process
        let mut child = tokio_cmd.spawn()?;

        let pid = child.id().expect("Failed to get process ID");
        info!("Service started with PID: {}", pid);

        // Capture stdout and stderr for logging
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let service_name = self.state.config.service_name().clone();

        // Spawn task to read stdout
        if let Some(stdout) = stdout {
            let service_name_clone = service_name.clone();
            tokio::spawn(async move {
                let reader = BufReader::new(stdout);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    info!("[{} stdout] {}", service_name_clone, line);
                }
            });
        }

        // Spawn task to read stderr
        if let Some(stderr) = stderr {
            let service_name_clone = service_name.clone();
            tokio::spawn(async move {
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    warn!("[{} stderr] {}", service_name_clone, line);
                }
            });
        }

        // Store the process
        {
            let mut process = self.state.process.write().await;
            *process = Some(child);
        }

        // Detect service port
        self.detect_service_port().await;

        Ok(())
    }

    fn build_command_based(&self) -> Result<Command, Box<dyn std::error::Error + Send + Sync>> {
        // Universal command-based backend support
        let command = self.state.config.command.as_ref().ok_or_else(|| {
            "Command not specified. Use --command to specify the command to run".to_string()
        })?;

        // Parse command (handle shell commands like "python3 -m vllm.entrypoints.openai.api_server")
        let parts: Vec<&str> = command.split_whitespace().collect();
        if parts.is_empty() {
            return Err("Empty command".into());
        }

        let mut cmd = Command::new(parts[0]);

        // Add remaining parts as arguments
        for part in parts.iter().skip(1) {
            cmd.arg(part);
        }

        // Add additional args if provided
        if let Some(args_str) = &self.state.config.args {
            for arg in args_str.split_whitespace() {
                cmd.arg(arg);
            }
        }

        // Add port if not already specified (many backends support --port)
        // This is a best-effort attempt - backends should specify port in their command
        info!("Using command-based backend: {}", command);
        Ok(cmd)
    }

    fn build_rust_command(&self) -> Result<Command, Box<dyn std::error::Error + Send + Sync>> {
        let path = self
            .state
            .config
            .path
            .as_ref()
            .ok_or_else(|| "Path not specified for InfiniLM-Rust service".to_string())?;

        let mut cmd = Command::new("xtask");
        cmd.arg("service")
            .arg(path.to_str().unwrap())
            .arg("-p")
            .arg(self.state.service_target_port().to_string());
        Ok(cmd)
    }

    fn build_python_command(&self) -> Result<Command, Box<dyn std::error::Error + Send + Sync>> {
        // For Python InfiniLM service
        // This is a simplified version - full implementation would handle all Python args
        let mut cmd = Command::new("python3");
        cmd.arg("launch_server.py") // Would need full path
            .arg("--port")
            .arg(self.state.service_target_port().to_string())
            .arg("--host")
            .arg(&self.state.config.host);
        Ok(cmd)
    }

    fn build_vllm_command(&self) -> Result<Command, Box<dyn std::error::Error + Send + Sync>> {
        // vLLM backend support
        let path = self
            .state
            .config
            .path
            .as_ref()
            .ok_or_else(|| "Model path not specified for vLLM service".to_string())?;

        let mut cmd = Command::new("python3");
        cmd.arg("-m")
            .arg("vllm.entrypoints.openai.api_server")
            .arg("--model")
            .arg(path.to_str().unwrap())
            .arg("--port")
            .arg(self.state.service_target_port().to_string())
            .arg("--host")
            .arg(&self.state.config.host);

        // Add optional vLLM arguments if provided
        if let Some(args_str) = &self.state.config.args {
            for arg in args_str.split_whitespace() {
                cmd.arg(arg);
            }
        }

        Ok(cmd)
    }

    fn build_mock_command(&self) -> Result<Command, Box<dyn std::error::Error + Send + Sync>> {
        // Mock backend support - can use the mock_service.py from integration tests
        let mut cmd = Command::new("python3");

        // Try to find mock_service.py
        let mock_script = std::env::current_dir().ok().and_then(|d| {
            let paths = vec![
                d.join("rust/tests/integration/mock_service.py"),
                d.join("tests/integration/mock_service.py"),
                d.join("mock_service.py"),
            ];
            paths.into_iter().find(|p| p.exists())
        });

        if let Some(script) = mock_script {
            cmd.arg(script.to_str().unwrap());
        } else {
            // Fallback: use command-based approach
            return self.build_command_based();
        }

        // Mock service arguments
        if let Some(name) = &self.state.config.name {
            cmd.arg("--name").arg(name);
        } else {
            cmd.arg("--name").arg(self.state.config.service_name());
        }

        cmd.arg("--port")
            .arg(self.state.service_target_port().to_string());

        if let Some(models) = &self.state.config.args {
            cmd.arg("--models").arg(models);
        } else {
            cmd.arg("--models").arg("test-model");
        }

        if let Some(registry_url) = &self.state.config.registry_url {
            cmd.arg("--registry-url").arg(registry_url);
        }

        Ok(cmd)
    }

    async fn detect_service_port(&self) {
        // Simplified port detection - in production, parse logs or check HTTP endpoint
        let target_port = self.state.service_target_port();

        // For fast services (like mock services), check more aggressively
        // Start with very short intervals and use shorter timeouts
        let mut wait_interval = Duration::from_millis(100); // Start with 100ms
        let max_wait = Duration::from_secs(30); // Maximum 30 seconds (CI may be slower)
        let start = std::time::Instant::now();

        // First, give the process a moment to start (100ms)
        sleep(Duration::from_millis(100)).await;

        loop {
            if start.elapsed() > max_wait {
                warn!(
                    "Could not detect service port within {}s, using target port {}",
                    max_wait.as_secs(),
                    target_port
                );
                let mut port = self.state.service_port.write().await;
                *port = Some(target_port);
                return;
            }

            if self.check_service_ready(target_port).await {
                info!(
                    "Service detected on port {} (took {:?})",
                    target_port,
                    start.elapsed()
                );
                let mut port = self.state.service_port.write().await;
                *port = Some(target_port);
                return;
            }

            sleep(wait_interval).await;
            // Exponential backoff, but cap at 1 second for fast services
            wait_interval = std::cmp::min(wait_interval * 2, Duration::from_secs(1));
        }
    }

    async fn check_service_ready(&self, port: u16) -> bool {
        // Check if port is listening with very short timeout
        let connect_timeout = Duration::from_millis(50);
        match timeout(
            connect_timeout,
            tokio::net::TcpStream::connect(format!("127.0.0.1:{}", port)),
        )
        .await
        {
            Ok(Ok(_)) => {
                // Port is listening, now verify HTTP endpoint is actually ready
                // Try /v1/models first (OpenAI API format), then fallback to /models
                let urls = vec![
                    format!("http://127.0.0.1:{}/v1/models", port),
                    format!("http://127.0.0.1:{}/models", port),
                ];
                let http_timeout = Duration::from_millis(500); // Give it a bit more time
                let client = reqwest::Client::builder()
                    .timeout(http_timeout)
                    .build()
                    .unwrap_or_else(|_| reqwest::Client::new());

                for url in urls {
                    match timeout(http_timeout, client.get(&url).send()).await {
                        Ok(Ok(response)) => {
                            // Service is ready if we get a successful response or 404 (endpoint exists)
                            if response.status().is_success() || response.status() == 404 {
                                return true;
                            }
                        }
                        _ => {
                            // Try next URL
                            continue;
                        }
                    }
                }
                // Port is listening but HTTP endpoint not ready yet
                false
            }
            _ => false,
        }
    }

    async fn monitor_service(&self) {
        loop {
            sleep(Duration::from_secs(5)).await;

            let process_died = {
                let mut process = self.state.process.write().await;
                match process.as_mut() {
                    Some(p) => {
                        // Check if process is still running
                        match p.try_wait() {
                            Ok(Some(status)) => {
                                error!("Service process exited with status: {:?}", status);
                                true
                            }
                            Ok(None) => false, // Still running
                            Err(e) => {
                                error!("Error checking process status: {}", e);
                                true
                            }
                        }
                    }
                    None => true,
                }
            };

            if process_died {
                info!("Service process died");
                break;
            }
        }
    }
}
