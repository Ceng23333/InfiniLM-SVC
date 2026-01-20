//! Request/response proxy handler

use axum::{
    body::Body,
    extract::{Request, State},
    http::{Method, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use reqwest::Client;
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;
use tracing::{error, info};

use crate::proxy::model_extractor::extract_model_from_body;
use crate::proxy::streaming::handle_streaming_response;
use crate::router::load_balancer::LoadBalancer;

lazy_static::lazy_static! {
    static ref HTTP_CLIENT: Client = Client::builder()
        .timeout(Duration::from_secs(300)) // 5 minutes total timeout
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

    // Extract model from request body if it's a POST request
    let model_id = if method == Method::POST {
        extract_model_from_body(&body_bytes)
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
        // Get next healthy service, optionally filtered by model
        let service = match load_balancer
            .get_next_healthy_service_by_model(model_id.as_deref())
            .await
        {
            Some(s) => s,
            None => {
                // No more healthy services available
                let error_msg = if let Some(model) = model_id {
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
                last_error = Some((status, error_msg.clone()));

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

    response
}
