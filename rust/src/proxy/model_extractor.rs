//! Model extraction from request body

use axum::body::Bytes;
use serde_json::Value;
use tracing::debug;

/// Extract model ID from request body
#[allow(dead_code)]
pub fn extract_model_from_body(body: &Bytes) -> Option<String> {
    // Try to parse as JSON
    let json_value: Value = match serde_json::from_slice(body) {
        Ok(v) => v,
        Err(_) => {
            debug!("Failed to parse request body as JSON");
            return None;
        }
    };

    // Extract model field
    json_value
        .get("model")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_model() {
        let body = br#"{"model": "test-model-1", "messages": []}"#;
        let model = extract_model_from_body(&Bytes::from(body.as_slice()));
        assert_eq!(model, Some("test-model-1".to_string()));
    }

    #[test]
    fn test_extract_model_missing() {
        let body = br#"{"messages": []}"#;
        let model = extract_model_from_body(&Bytes::from(body.as_slice()));
        assert_eq!(model, None);
    }

    #[test]
    fn test_extract_model_invalid_json() {
        let body = b"not json";
        let model = extract_model_from_body(&Bytes::from(body.as_slice()));
        assert_eq!(model, None);
    }
}
