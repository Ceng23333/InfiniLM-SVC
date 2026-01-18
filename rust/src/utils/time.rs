//! Time utilities

use std::time::{SystemTime, UNIX_EPOCH};

/// Get current Unix timestamp as f64
pub fn current_timestamp() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs_f64()
}

/// Get current Unix timestamp as u64 (seconds)
#[allow(dead_code)]
pub fn current_timestamp_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}
