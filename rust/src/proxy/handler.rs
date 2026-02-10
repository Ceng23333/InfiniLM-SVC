//! Request/response proxy handler

use axum::{
    body::Body,
    extract::{Request, State},
    http::{Method, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use reqwest::Client;
use serde::Deserialize;
use std::borrow::Cow;
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info};

use crate::proxy::session_extractor::generate_session_from_ip;
use crate::proxy::streaming::handle_streaming_response;
use crate::router::load_balancer::LoadBalancer;

/// Get proxy timeout from environment variable or use default (30 minutes)
fn get_proxy_timeout() -> Duration {
    std::env::var("PROXY_TIMEOUT_SECONDS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok())
        .map(Duration::from_secs)
        .unwrap_or(Duration::from_secs(1800)) // Default: 30 minutes
}

lazy_static::lazy_static! {
    static ref HTTP_CLIENT: Client = Client::builder()
        .timeout(get_proxy_timeout())
        .connect_timeout(Duration::from_secs(5)) // 5 seconds connection timeout
        .build()
        .expect("Failed to create HTTP client");
}

/// Headers that should not be forwarded (hop-by-hop headers)
const HOP_BY_HOP_HEADERS: &[&str] = &[
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "host",
    "content-length", // Will be recalculated
];

/// Default routing threshold in bytes (50KB)
const DEFAULT_CACHE_TYPE_ROUTING_THRESHOLD: usize = 51200;

/// Get routing threshold from environment variable or use default
fn get_routing_threshold() -> usize {
    std::env::var("CACHE_TYPE_ROUTING_THRESHOLD")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .unwrap_or(DEFAULT_CACHE_TYPE_ROUTING_THRESHOLD)
}

/// Routing-relevant fields extracted from a request body.
/// We intentionally do NOT deserialize the full JSON into `serde_json::Value` for efficiency.
#[derive(Debug, Clone)]
struct RoutingFields {
    model_id: Option<String>,
    prompt_cache_key: Option<String>,
    message_size: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum Content<'a> {
    Str(#[serde(borrow)] Cow<'a, str>),
    Parts(Vec<ContentPart<'a>>),
}

#[derive(Debug, Deserialize)]
struct ContentPart<'a> {
    #[serde(default, borrow)]
    text: Option<Cow<'a, str>>,
    #[serde(default, borrow)]
    content: Option<Cow<'a, str>>,
}

impl<'a> Content<'a> {
    fn text_len(&self) -> usize {
        match self {
            Content::Str(s) => s.len(),
            Content::Parts(parts) => parts
                .iter()
                .map(|p| p.text.as_ref().map(|s| s.len()).unwrap_or(0)
                    + p.content.as_ref().map(|s| s.len()).unwrap_or(0))
                .sum(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct Message<'a> {
    #[serde(default, borrow)]
    content: Option<Content<'a>>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum Prompt<'a> {
    Str(#[serde(borrow)] Cow<'a, str>),
    Arr(Vec<Cow<'a, str>>),
}

impl<'a> Prompt<'a> {
    fn text_len(&self) -> usize {
        match self {
            Prompt::Str(s) => s.len(),
            Prompt::Arr(arr) => arr.iter().map(|s| s.len()).sum(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct RoutingRequest<'a> {
    #[serde(default, borrow)]
    model: Option<Cow<'a, str>>,
    #[serde(default, borrow)]
    prompt_cache_key: Option<Cow<'a, str>>,
    #[serde(default)]
    messages: Option<Vec<Message<'a>>>,
    #[serde(default)]
    prompt: Option<Prompt<'a>>,
}

fn extract_routing_fields(body_bytes: &[u8]) -> Option<RoutingFields> {
    let req: RoutingRequest<'_> = serde_json::from_slice(body_bytes).ok()?;

    let message_size = if let Some(messages) = req.messages {
        Some(
            messages
                .iter()
                .map(|m| m.content.as_ref().map(|c| c.text_len()).unwrap_or(0))
                .sum(),
        )
    } else if let Some(prompt) = req.prompt {
        Some(prompt.text_len())
    } else {
        None
    };

    Some(RoutingFields {
        model_id: req.model.map(|c| c.to_string()),
        prompt_cache_key: req.prompt_cache_key.map(|c| c.to_string()),
        message_size,
    })
}

/// Proxy handler - forwards requests to backend services
pub async fn proxy_handler(
    State(load_balancer): State<Arc<LoadBalancer>>,
    request: Request,
) -> Response {
    let method = request.method().clone();
    let uri = request.uri().clone();
    let headers = request.headers().clone();

    // Read request body first (needed for model extraction and forwarding)
    let body_bytes = match axum::body::to_bytes(request.into_body(), usize::MAX).await {
        Ok(bytes) => bytes,
        Err(e) => {
            error!("Failed to read request body: {}", e);
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "Failed to read request body"})),
            )
                .into_response();
        }
    };

    // Extract only routing-relevant fields; avoid building full JSON DOM.
    let routing_fields = if method == Method::POST {
        extract_routing_fields(&body_bytes)
    } else {
        None
    };
    let model_id = routing_fields.as_ref().and_then(|r| r.model_id.clone());
    let prompt_cache_key = routing_fields
        .as_ref()
        .and_then(|r| r.prompt_cache_key.clone());

    // Extract session ID (prompt_cache_key or IP-based)
    // Note: remote_addr is None here since we don't have direct access to it in axum Request.
    // We still use X-Forwarded-For as a fallback via generate_session_from_ip.
    let session_id = if let Some(key) = prompt_cache_key {
        let model_prefix = model_id.as_deref().unwrap_or("default");
        Some(format!("{}:prompt_cache:{}", model_prefix, key))
    } else if let Some(ip_hash) = generate_session_from_ip(&headers, None) {
        let model_prefix = model_id.as_deref().unwrap_or("default");
        Some(format!("{}:ip:{}", model_prefix, ip_hash))
    } else {
        None
    };

    // Try multiple services if one fails (retry logic for multi-server scenarios)
    let max_retries = 3;
    let mut last_error: Option<(StatusCode, String)> = None;

    // Convert axum Method to reqwest Method (only need to do this once)
    let reqwest_method = match reqwest::Method::from_bytes(method.as_str().as_bytes()) {
        Ok(m) => m,
        Err(e) => {
            error!("Invalid HTTP method: {}", e);
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": "Invalid HTTP method"})),
            )
                .into_response();
        }
    };

    for attempt in 0..max_retries {
        // Get service: size-based routing if enabled, else session-aware routing, else round-robin
        let service = if let Some(ref rf) = routing_fields {
            // Calculate message body size for size-based routing
            let message_size = rf.message_size.unwrap_or(0);
            let threshold = get_routing_threshold();

            // Size-based routing: large requests -> static cache, small requests -> paged cache
            let cache_type = if message_size > threshold {
                "static"
            } else {
                "paged"
            };

            match load_balancer
                .get_service_by_cache_type(cache_type, model_id.as_deref())
                .await
            {
                Some(s) => {
                    if attempt == 0 {
                        info!(
                            "Size-based routing: message_size={} bytes, threshold={} bytes, cache_type={}, service={}",
                            message_size, threshold, cache_type, s.name
                        );
                    }
                    s
                }
                None => {
                    // Fallback to session-aware routing if size-based routing fails
                    if let Some(ref session_key) = session_id {
                        match load_balancer
                            .get_service_by_session(session_key, model_id.as_deref())
                            .await
                        {
                            Some(s) => s,
                            None => {
                                // Fallback to round-robin
                                match load_balancer
                                    .get_next_healthy_service_by_model(model_id.as_deref())
                                    .await
                                {
                                    Some(s) => s,
                                    None => {
                                        let error_msg = if let Some(model) = &model_id {
                                            format!("No healthy services available for model '{}'", model)
                                        } else {
                                            "No healthy services available".to_string()
                                        };
                                        return (
                                            StatusCode::SERVICE_UNAVAILABLE,
                                            Json(json!({"error": error_msg})),
                                        )
                                            .into_response();
                                    }
                                }
                            }
                        }
                    } else {
                        // Fallback to round-robin
                        match load_balancer
                            .get_next_healthy_service_by_model(model_id.as_deref())
                            .await
                        {
                            Some(s) => s,
                            None => {
                                let error_msg = if let Some(model) = &model_id {
                                    format!("No healthy services available for model '{}'", model)
                                } else {
                                    "No healthy services available".to_string()
                                };
                                return (
                                    StatusCode::SERVICE_UNAVAILABLE,
                                    Json(json!({"error": error_msg})),
                                )
                                    .into_response();
                            }
                        }
                    }
                }
            }
        } else if let Some(ref session_key) = session_id {
            // Session-aware routing (fallback when body_json is not available)
            match load_balancer
                .get_service_by_session(session_key, model_id.as_deref())
                .await
            {
                Some(s) => s,
                None => {
                    // No more healthy services available
                    let error_msg = if let Some(model) = &model_id {
                        format!("No healthy services available for model '{}'", model)
                    } else {
                        "No healthy services available".to_string()
                    };
                    return (
                        StatusCode::SERVICE_UNAVAILABLE,
                        Json(json!({"error": error_msg})),
                    )
                        .into_response();
                }
            }
        } else {
            // Fallback to existing round-robin logic (no session identifier available)
            match load_balancer
                .get_next_healthy_service_by_model(model_id.as_deref())
                .await
            {
                Some(s) => s,
                None => {
                    // No more healthy services available
                    let error_msg = if let Some(model) = &model_id {
                        format!("No healthy services available for model '{}'", model)
                    } else {
                        "No healthy services available".to_string()
                    };
                    return (
                        StatusCode::SERVICE_UNAVAILABLE,
                        Json(json!({"error": error_msg})),
                    )
                        .into_response();
                }
            }
        };

        // Build target URL
        let target_url = format!(
            "{}{}",
            service.url,
            uri.path_and_query().map(|pq| pq.as_str()).unwrap_or("")
        );

        if let Some(model) = &model_id {
            if attempt > 0 {
                info!(
                    "Retrying {} {} (model: {}) -> {} (attempt {}/{})",
                    method,
                    uri.path(),
                    model,
                    service.name,
                    attempt + 1,
                    max_retries
                );
            } else {
                info!(
                    "Proxying {} {} (model: {}) -> {}",
                    method,
                    uri.path(),
                    model,
                    service.name
                );
            }
        } else {
            if attempt > 0 {
                info!(
                    "Retrying {} {} -> {} (attempt {}/{})",
                    method,
                    uri.path(),
                    service.name,
                    attempt + 1,
                    max_retries
                );
            } else {
                info!("Proxying {} {} -> {}", method, uri.path(), service.name);
            }
        }

        // Build upstream request
        let mut upstream_request = HTTP_CLIENT
            .request(reqwest_method.clone(), &target_url)
            .body(body_bytes.clone());

        // Copy headers (excluding hop-by-hop headers)
        for (name, value) in headers.iter() {
            let header_name_lower = name.as_str().to_lowercase();
            if HOP_BY_HOP_HEADERS.contains(&header_name_lower.as_str()) {
                continue;
            }
            // Convert axum HeaderValue to string for reqwest
            if let Ok(header_value_str) = value.to_str() {
                upstream_request = upstream_request.header(name.as_str(), header_value_str);
            }
        }

        // Execute request
        let upstream_response = match upstream_request.send().await {
            Ok(response) => response,
            Err(e) => {
                error!(
                    "Error proxying to service {} (URL: {}): {}",
                    service.name, target_url, e
                );

                // Mark service as unhealthy on connection errors
                service.increment_error_count().await;
                service.set_healthy(false).await;

                // Store error for potential retry
                let (status, error_msg) = if e.is_timeout() {
                    (StatusCode::GATEWAY_TIMEOUT, "Service timeout")
                } else if e.is_connect() {
                    (
                        StatusCode::SERVICE_UNAVAILABLE,
                        "Service unavailable - connection refused",
                    )
                } else {
                    (
                        StatusCode::BAD_GATEWAY,
                        "Bad gateway - error communicating with service",
                    )
                };
                last_error = Some((status, error_msg.to_string()));

                // If this is not the last attempt, continue to try another service
                if attempt < max_retries - 1 {
                    continue;
                }

                // Last attempt failed, return error
                return (status, Json(json!({"error": error_msg}))).into_response();
            }
        };

        // Success! Break out of retry loop
        // Increment request count on success
        service.increment_request_count().await;

        let status = StatusCode::from_u16(upstream_response.status().as_u16())
            .unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);

        // Extract headers before consuming the response
        let response_headers: Vec<(String, String)> = upstream_response
            .headers()
            .iter()
            .filter_map(|(name, value)| {
                let header_name_lower = name.as_str().to_lowercase();
                if HOP_BY_HOP_HEADERS.contains(&header_name_lower.as_str()) {
                    return None;
                }
                value
                    .to_str()
                    .ok()
                    .map(|v| (name.as_str().to_string(), v.to_string()))
            })
            .collect();

        // Check if this is a streaming response
        let content_type = upstream_response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");
        let transfer_encoding = upstream_response
            .headers()
            .get("transfer-encoding")
            .and_then(|v| v.to_str().ok())
            .unwrap_or("");

        let is_sse = content_type.contains("text/event-stream");
        let is_chunked = transfer_encoding.to_lowercase() == "chunked";

        if is_sse || is_chunked {
            // Handle streaming response
            return handle_streaming_response(
                upstream_response,
                status,
                response_headers,
                method.as_str(),
                uri.path(),
                &service.name,
            )
            .await;
        }

        // Read response body for non-streaming responses
        let response_body = match upstream_response.bytes().await {
            Ok(bytes) => bytes,
            Err(e) => {
                error!("Failed to read response body: {}", e);
                return (
                    StatusCode::BAD_GATEWAY,
                    Json(json!({"error": "Failed to read response from service"})),
                )
                    .into_response();
            }
        };

        // Build response
        let mut response_builder = Response::builder().status(status);

        // Copy headers (excluding hop-by-hop headers)
        for (name_str, value_str) in response_headers {
            if let Ok(header_name) = axum::http::HeaderName::from_bytes(name_str.as_bytes()) {
                if let Ok(header_value) = axum::http::HeaderValue::from_str(&value_str) {
                    response_builder = response_builder.header(header_name, header_value);
                }
            }
        }

        let response = match response_builder.body(Body::from(response_body.to_vec())) {
            Ok(r) => r,
            Err(e) => {
                error!("Failed to build response: {}", e);
                return (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({"error": "Internal server error"})),
                )
                    .into_response();
            }
        };

        info!(
            "Proxied {} {} -> {} ({})",
            method,
            uri.path(),
            service.name,
            status
        );

        return response.into_response();
    }

    // If we get here, all retries failed
    if let Some((status, error_msg)) = last_error {
        (status, Json(json!({"error": error_msg}))).into_response()
    } else {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"error": "No services available"})),
        )
            .into_response()
    }
}
