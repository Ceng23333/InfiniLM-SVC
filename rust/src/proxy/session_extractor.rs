//! Session ID extraction from requests

use axum::body::Bytes;
use axum::http::HeaderMap;
use serde_json::Value;
use sha2::{Digest, Sha256};
use tracing::debug;

/// Extract prompt_cache_key from request body
pub fn extract_prompt_cache_key_from_body(body: &Bytes) -> Option<String> {
    // Try to parse as JSON
    let json_value: Value = match serde_json::from_slice(body) {
        Ok(v) => v,
        Err(_) => {
            debug!("Failed to parse request body as JSON for prompt_cache_key extraction");
            return None;
        }
    };

    // Extract prompt_cache_key field
    json_value
        .get("prompt_cache_key")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

/// Generate session ID from IP address and User-Agent header
/// Returns None if IP address is unavailable
pub fn generate_session_from_ip(
    headers: &HeaderMap,
    remote_addr: Option<&str>,
) -> Option<String> {
    // Try to get IP from X-Forwarded-For header first (for proxy scenarios)
    let ip = headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.split(',').next())
        .map(|s| s.trim())
        .or_else(|| remote_addr)
        .filter(|s| !s.is_empty())?;

    // Get User-Agent header
    let user_agent = headers
        .get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");

    // Create hash from IP + User-Agent
    let mut hasher = Sha256::new();
    hasher.update(ip.as_bytes());
    hasher.update(user_agent.as_bytes());
    let hash = hasher.finalize();

    // Convert to hex string (first 16 characters for brevity)
    Some(format!("{:x}", hash)[..16].to_string())
}

/// Extract session ID from request
/// Priority: 1. prompt_cache_key, 2. IP-based hash, 3. None
/// Returns None if no session identifier is available
pub fn extract_session_id(
    headers: &HeaderMap,
    body: &Bytes,
    remote_addr: Option<&str>,
    model_id: Option<&str>,
) -> Option<String> {
    // Try prompt_cache_key first (primary method)
    if let Some(key) = extract_prompt_cache_key_from_body(body) {
        let model_prefix = model_id.unwrap_or("default");
        return Some(format!("{}:prompt_cache:{}", model_prefix, key));
    }

    // Try IP-based as fallback (secondary method)
    if let Some(ip_hash) = generate_session_from_ip(headers, remote_addr) {
        let model_prefix = model_id.unwrap_or("default");
        return Some(format!("{}:ip:{}", model_prefix, ip_hash));
    }

    // No session identifier available
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    #[test]
    fn test_extract_prompt_cache_key() {
        let body = br#"{"prompt_cache_key": "test-key-123", "messages": []}"#;
        let key = extract_prompt_cache_key_from_body(&Bytes::from(body.as_slice()));
        assert_eq!(key, Some("test-key-123".to_string()));
    }

    #[test]
    fn test_extract_prompt_cache_key_missing() {
        let body = br#"{"messages": []}"#;
        let key = extract_prompt_cache_key_from_body(&Bytes::from(body.as_slice()));
        assert_eq!(key, None);
    }

    #[test]
    fn test_generate_session_from_ip() {
        let mut headers = HeaderMap::new();
        headers.insert("user-agent", HeaderValue::from_static("test-agent"));
        let session = generate_session_from_ip(&headers, Some("192.168.1.1"));
        assert!(session.is_some());
    }

    #[test]
    fn test_generate_session_from_ip_with_x_forwarded_for() {
        let mut headers = HeaderMap::new();
        headers.insert("x-forwarded-for", HeaderValue::from_static("10.0.0.1"));
        headers.insert("user-agent", HeaderValue::from_static("test-agent"));
        let session = generate_session_from_ip(&headers, Some("192.168.1.1"));
        assert!(session.is_some());
        // Should use X-Forwarded-For IP, not remote_addr
    }

    #[test]
    fn test_generate_session_from_ip_no_ip() {
        let headers = HeaderMap::new();
        let session = generate_session_from_ip(&headers, None);
        assert_eq!(session, None);
    }

    #[test]
    fn test_extract_session_id_with_prompt_cache_key() {
        let body = br#"{"prompt_cache_key": "key-123"}"#;
        let headers = HeaderMap::new();
        let session_id = extract_session_id(&headers, &Bytes::from(body.as_slice()), None, Some("model-1"));
        assert_eq!(session_id, Some("model-1:prompt_cache:key-123".to_string()));
    }

    #[test]
    fn test_extract_session_id_with_ip() {
        let body = br#"{"messages": []}"#;
        let mut headers = HeaderMap::new();
        headers.insert("user-agent", HeaderValue::from_static("test-agent"));
        let session_id = extract_session_id(&headers, &Bytes::from(body.as_slice()), Some("192.168.1.1"), Some("model-1"));
        assert!(session_id.is_some());
        assert!(session_id.unwrap().starts_with("model-1:ip:"));
    }

    #[test]
    fn test_extract_session_id_no_identifier() {
        let body = br#"{"messages": []}"#;
        let headers = HeaderMap::new();
        let session_id = extract_session_id(&headers, &Bytes::from(body.as_slice()), None, Some("model-1"));
        assert_eq!(session_id, None);
    }
}
