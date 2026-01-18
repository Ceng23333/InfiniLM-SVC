//! Streaming support for SSE and chunked responses

use axum::{
    body::Body,
    http::{HeaderName, HeaderValue, StatusCode},
    response::Response,
};
use futures::StreamExt;
use reqwest::Response as ReqwestResponse;
use tracing::info;

/// Handle streaming response from upstream service
pub async fn handle_streaming_response(
    upstream_response: ReqwestResponse,
    status: StatusCode,
    response_headers: Vec<(String, String)>,
    method: &str,
    path: &str,
    service_name: &str,
) -> Response {
    // Build response with streaming body
    let mut response_builder = Response::builder().status(status);

    // Copy headers (excluding hop-by-hop headers)
    for (name_str, value_str) in response_headers {
        if let Ok(header_name) = HeaderName::from_bytes(name_str.as_bytes()) {
            if let Ok(header_value) = HeaderValue::from_str(&value_str) {
                response_builder = response_builder.header(header_name, header_value);
            }
        }
    }

    // Create a streaming body from the upstream response
    let stream = upstream_response.bytes_stream();
    
    // Convert reqwest::Stream to axum::Body
    // Map reqwest::Bytes to axum::body::Bytes
    let body_stream = stream.map(|result| {
        match result {
            Ok(bytes) => Ok(axum::body::Bytes::from(bytes.to_vec())),
            Err(e) => {
                tracing::error!("Stream error: {}", e);
                Err(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    format!("Stream error: {}", e),
                ))
            }
        }
    });

    let body = Body::from_stream(body_stream);

    let response = match response_builder.body(body) {
        Ok(r) => r,
        Err(e) => {
            tracing::error!("Failed to build streaming response: {}", e);
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::from("Internal server error"))
                .unwrap();
        }
    };

    info!("Proxied (stream) {} {} -> {} ({})", method, path, service_name, status);
    response
}
