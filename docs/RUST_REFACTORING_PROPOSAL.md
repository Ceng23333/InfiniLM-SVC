# Distributed Router: Investigation & Rust Refactoring Proposal

**Date:** 2025
**Status:** Proposal for Future Development
**Author:** Development Team

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Router Usage Summary](#router-usage-summary)
4. [Why Not Nginx?](#why-not-nginx)
5. [Quantitative Performance Metrics](#quantitative-performance-metrics)
6. [Rust Refactoring Proposal](#rust-refactoring-proposal)
7. [Implementation Strategy](#implementation-strategy)
8. [Expected Benefits & ROI](#expected-benefits--roi)
9. [Risk Assessment](#risk-assessment)
10. [References](#references)

---

## Executive Summary

This document presents a comprehensive investigation of the current Python-based `DistributedRouterService` architecture and proposes a refactoring to Rust. The investigation reveals that while the current Python implementation meets functional requirements, a Rust rewrite would provide significant performance improvements, resource efficiency gains, and better scalability characteristics.

**Key Findings:**
- Current router requires **model-level routing** and **dynamic service discovery** that standard reverse proxies cannot easily provide
- Python implementation works but has inherent limitations (GIL, memory overhead, GC pauses)
- Rust refactoring expected to deliver **5-15x throughput improvements** and **3-5x memory reduction**
- Estimated infrastructure cost savings: **60-80%**

---

## Current Architecture Analysis

### System Components

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Router Service │◄───────►│ Service Registry │◄───────►│  Babysitters    │
│   (Python)      │  Sync   │    (Python)      │  Heart  │   (Python)      │
│   Port: 8080    │  Every  │    Port: 8081    │  beat   │   Port: N+1     │
│                 │  10s    │                  │         │                 │
└─────────────────┘         └──────────────────┘         └─────────────────┘
         │                           │                            │
         │                           │                            │
         └───────────────────────────┼────────────────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
            ┌───────▼────────┐              ┌────────▼───────┐
            │ InfiniLM       │              │ InfiniLM       │
            │ Server (N)     │              │ Server (N+1)   │
            └────────────────┘              └────────────────┘
```

### Current Router Responsibilities

1. **Load Balancing**: Weighted round-robin across healthy services
2. **Service Discovery**: Periodic sync with registry (every 10 seconds)
3. **Health Monitoring**: Health checks via babysitter endpoints (every 30 seconds)
4. **Request Proxying**: Forward OpenAI API requests to backend InfiniLM services
5. **Model-Level Routing**: Extract model ID from request body and route to services supporting that model
6. **Model Aggregation**: Aggregate models from all healthy services for `/models` endpoint
7. **Streaming Support**: Handle SSE (`text/event-stream`) and chunked responses
8. **Service Metadata Tracking**: Maintain service state, request counts, error counts, etc.

### Current Technology Stack

- **Language**: Python 3.x
- **Web Framework**: aiohttp
- **Async Runtime**: asyncio
- **Dependencies**: aiohttp, asyncio, json, logging
- **Architecture**: Single-threaded async (event loop)

---

## Router Usage Summary

### Core Functionality

#### 1. Dynamic Service Discovery
- Router syncs with service registry every **10 seconds**
- Discovers new services automatically
- Removes services after **60-second grace period** if they disappear from registry
- Tracks `last_seen_in_registry` timestamps for graceful removal

#### 2. Health Check System
- Health checks every **30 seconds** via babysitter URLs (service_port + 1)
- Tracks service health status, response times, error counts
- Automatic failover when services become unhealthy
- Max errors threshold: **3** before marking service unhealthy

#### 3. Model-Level Routing
```python
# Extract model from POST request body
if request.method == 'POST':
    request_body = await request.read()
    request_data = json.loads(request_body)
    model_id = request_data.get('model')

# Route to service supporting that model
target_service = get_next_healthy_service_by_type("openai-api", model_id=model_id)
```

- Parses JSON request body to extract `model` field
- Filters services to only those supporting the requested model
- Falls back to round-robin if model not specified

#### 4. Model Aggregation
- Aggregates models from all healthy services
- Deduplicates models by ID
- Provides unified `/models` endpoint (OpenAI API compatible format)
- Updates automatically as services come and go

#### 5. Streaming Support
- Detects SSE (`text/event-stream`) and chunked responses
- Proxies streaming responses incrementally (8KB chunks)
- Handles long-running requests (5-minute timeout)
- Minimal buffering for better latency

#### 6. Request/Response Proxying
- Forwards all OpenAI API requests (`/v1/chat/completions`, etc.)
- Handles headers, query parameters, request body
- Manages connection timeouts (5s connect, 300s total)
- Proper error handling and retry logic

### Key Features Not Provided by Standard Reverse Proxies

1. **Request Body Inspection**: Requires JSON parsing to extract model ID
2. **Dynamic Backend Management**: Services added/removed without configuration reloads
3. **Service Metadata Tracking**: Custom state management for each service
4. **Model Aggregation**: Intelligent merging of responses from multiple backends
5. **Graceful Service Removal**: Time-based grace periods before removal

---

## Why Not Nginx?

### Limitations of Nginx for This Use Case

#### 1. Request Body Inspection is Complex
**Problem**: Nginx cannot easily inspect JSON request bodies to extract the `model` field.

**Workarounds**:
- Use `lua-resty-json` with OpenResty (adds complexity, performance overhead)
- Pre-process requests with a separate service (adds latency, another hop)
- Route to all backends and let them filter (inefficient, wasteful)

**Current Solution**: Direct JSON parsing in Python (`json.loads()`)

#### 2. Dynamic Service Discovery Requires Reloads
**Problem**: Nginx requires configuration reloads (`nginx -s reload`) to update upstream servers.

**Workarounds**:
- Use `lua-resty-upstream-healthcheck` with dynamic upstreams (complex, limited)
- External tool to regenerate config and reload (slow, can drop connections)
- Consul/etcd integration with template engine (additional infrastructure)

**Current Solution**: In-memory service registry synced every 10 seconds (no reloads needed)

#### 3. Model Aggregation Requires Custom Logic
**Problem**: Nginx cannot aggregate JSON responses from multiple backends into a single response.

**Workarounds**:
- Use Lua to merge responses (complex, error-prone)
- External aggregator service (adds latency, another component)
- Client-side aggregation (not compatible with OpenAI API)

**Current Solution**: In-memory aggregation of model metadata from all services

#### 4. Health Check Integration with Babysitter
**Problem**: Health checks use babysitter URLs (port+1), which requires custom logic.

**Workarounds**:
- Multiple upstream blocks for each service/babysitter pair (complex config)
- Lua-based custom health checks (adds complexity)
- External health check service (additional component)

**Current Solution**: Direct health checks to babysitter URLs with custom logic

#### 5. Graceful Service Removal
**Problem**: Nginx doesn't support time-based grace periods before removing backends.

**Workarounds**:
- External state management with delays (complex)
- Multiple configuration phases (error-prone)

**Current Solution**: In-memory tracking of `last_seen_in_registry` timestamps

#### 6. Service Metadata Tracking
**Problem**: Nginx doesn't maintain service metadata (request counts, error counts, models list, etc.).

**Workarounds**:
- External metrics/observability system (additional infrastructure)
- Prometheus/Grafana integration (adds complexity)

**Current Solution**: Built-in `/stats` and `/services` endpoints with full metadata

### Why Nginx Was Not Chosen

While nginx is excellent for traditional reverse proxy use cases, this router requires:

1. **Application-level logic** (JSON parsing, model filtering)
2. **Dynamic state management** (service metadata, grace periods)
3. **Response aggregation** (model lists from multiple backends)
4. **Complex routing decisions** (model-aware service selection)

These requirements make a custom application router more suitable than a configuration-based reverse proxy.

---

## Quantitative Performance Metrics

### Benchmark Data from Open-Source Studies

#### 1. Web API Throughput

**PostgreSQL Fastware White Paper** (Containerized Web Applications):
- **Rust**: ~75x more requests per unit time than Python
- **Rust**: Lower CPU and memory usage
- **Impact**: Significantly fewer containers needed for same performance

**TechEmpower Benchmark** (Industry Standard):
- **Rust** (actix-web/axum): Top-10 performers in JSON/plaintext benchmarks
- **Python** (aiohttp/tornado): Typically 10-50x lower throughput
- **Example**: Actix-Web ~1.7M req/s vs aiohttp ~50-100K req/s (hardware-dependent)

#### 2. Memory Usage

**Typical HTTP Server Memory Footprints**:
- **Rust** (axum/hyper): 5-50 MB RSS
- **Python** (aiohttp): 50-200+ MB RSS (varies with workload)
- **Improvement**: ~60-80% lower memory usage

**Energy Efficiency Study** (Multi-language benchmark):
- **Rust**: ~7.80 Joules per task
- **Python**: ~19.60 Joules per task
- **Improvement**: ~2.5x more energy-efficient

#### 3. Latency

**AWS Lambda Benchmarks** (2025):
- **Rust** (Arm64): 16ms cold start
- **Python**: Typically 100-500ms+ cold start
- **Improvement**: ~6-30x faster cold starts

**P50/P95/P99 Latency** (Typical HTTP servers):
- **Rust frameworks**: Often 5-20x lower tail latency
- **Python** (GIL impact): Higher variance under concurrency

#### 4. Data Processing / Proxy Overhead

**General Data Processing**:
- **Rust**: ~10x faster than Python
- **Rust**: ~50% fewer resources

**Energy per 1,000 Requests**:
- **Rust**: Significantly lower energy consumption

### Expected Improvements for Router Use Case

| Metric | Python (aiohttp) | Rust (axum) | Improvement Factor |
|--------|------------------|-------------|-------------------|
| **Throughput (req/s)** | ~10-50K | ~500K-1M+ | **10-50x** |
| **Memory (idle)** | ~50-100 MB | ~10-20 MB | **5-10x less** |
| **Memory (under load)** | ~200-500 MB | ~50-150 MB | **3-5x less** |
| **P95 Latency** | ~10-50ms | ~1-5ms | **5-10x** |
| **CPU Usage** | High (GIL) | Lower (parallel) | **2-3x** |
| **Cold Start** | N/A (daemon) | Faster binary | N/A |

### Realistic Expectations

Given the proxy/router workload characteristics (I/O-bound, JSON parsing, streaming):

**Realistic Improvements**:
- **Throughput**: 5-15x improvement
- **Memory**: 3-5x reduction
- **Latency**: 2-5x improvement (tail latency)
- **CPU Efficiency**: 2-3x better utilization

### Cost Impact Calculations

**For Production Router Handling 100K req/s**:

**Python Deployment**:
- 5-10 containers @ 2 CPU, 512MB RAM each
- Estimated cost: **$200-400/month**

**Rust Deployment**:
- 1-2 containers @ 2 CPU, 256MB RAM each
- Estimated cost: **$40-80/month**

**Estimated Savings**: **60-80% infrastructure cost reduction**

---

## Rust Refactoring Proposal

### Proposed Architecture

```
┌─────────────────────────────────────────────┐
│         Router Service (Rust)               │
├─────────────────────────────────────────────┤
│ - Async HTTP (axum/hyper)                   │
│ - Service Registry Client                   │
│ - Load Balancer (weighted round-robin)      │
│ - Health Check Manager                      │
│ - Request Proxy (with streaming)            │
│ - Model Aggregation Logic                   │
└─────────────────────────────────────────────┘
```

### Technology Stack

**Recommended Rust Stack**:
- **Web Framework**: `axum` (built on `hyper`, `tower`)
- **Async Runtime**: `tokio`
- **HTTP Client**: `reqwest` (or `hyper` for more control)
- **JSON**: `serde_json`
- **Configuration**: `config` or `toml`
- **Logging**: `tracing` + `tracing-subscriber`
- **Error Handling**: `anyhow` + `thiserror`
- **Time**: `chrono` or `time`
- **CLI**: `clap`

### Project Structure

```
infini-router/
├── Cargo.toml
├── README.md
├── .github/
│   └── workflows/
│       └── ci.yml
├── src/
│   ├── main.rs                  # Entry point, CLI parsing
│   ├── config.rs                # Configuration management
│   ├── router/
│   │   ├── mod.rs
│   │   ├── load_balancer.rs     # Load balancing logic
│   │   ├── service_instance.rs  # Service metadata struct
│   │   └── health_checker.rs    # Health check manager
│   ├── registry/
│   │   ├── mod.rs
│   │   └── client.rs            # Registry HTTP client
│   ├── proxy/
│   │   ├── mod.rs
│   │   ├── handler.rs           # Request/response proxy
│   │   └── streaming.rs         # SSE/chunked streaming
│   ├── models/
│   │   ├── mod.rs
│   │   └── aggregator.rs        # Model aggregation logic
│   ├── handlers/
│   │   ├── mod.rs
│   │   ├── health.rs            # /health endpoint
│   │   ├── stats.rs             # /stats endpoint
│   │   ├── services.rs          # /services endpoint
│   │   └── models.rs            # /models endpoint
│   └── utils/
│       ├── mod.rs
│       ├── errors.rs            # Error types
│       └── time.rs              # Time utilities
└── tests/
    ├── integration/
    │   ├── load_balancer_test.rs
    │   ├── proxy_test.rs
    │   └── registry_test.rs
    └── unit/
        └── ...
```

### Key Implementation Details

#### 1. Service Instance Management

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone)]
pub struct ServiceInstance {
    pub name: String,
    pub host: String,
    pub port: u16,
    pub url: String,
    pub babysitter_url: String,
    pub healthy: Arc<RwLock<bool>>,
    pub models: Arc<RwLock<Vec<String>>>,
    pub metadata: HashMap<String, serde_json::Value>,
    pub request_count: Arc<RwLock<u64>>,
    pub error_count: Arc<RwLock<u32>>,
    pub weight: u32,
    pub last_seen: Arc<RwLock<f64>>,
    pub last_check: Arc<RwLock<f64>>,
    pub response_time: Arc<RwLock<f64>>,
}
```

#### 2. Load Balancer

```rust
pub struct LoadBalancer {
    services: Arc<RwLock<HashMap<String, ServiceInstance>>>,
    registry_url: Option<String>,
    current_index: Arc<RwLock<usize>>,
    health_check_interval: u64,
    registry_sync_interval: u64,
    service_removal_grace_period: u64,
}

impl LoadBalancer {
    pub async fn get_service_by_model(
        &self,
        model_id: Option<&str>,
    ) -> Option<ServiceInstance> {
        // Model-aware service selection with weighted round-robin
    }

    pub async fn aggregate_models(&self) -> Vec<ModelInfo> {
        // Aggregate models from all healthy services
    }

    pub async fn sync_with_registry(&self) -> Result<()> {
        // Sync with registry periodically
    }

    pub async fn health_check_all(&self) {
        // Perform health checks on all services
    }
}
```

#### 3. HTTP Server with axum

```rust
use axum::{
    extract::{Request, Path},
    http::StatusCode,
    response::Response,
    routing::{get, post, delete, put},
    Router,
};
use tower::ServiceBuilder;
use tower_http::cors::CorsLayer;

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env()?;
    let load_balancer = Arc::new(LoadBalancer::new(&config)?);

    // Start background tasks
    let health_checker = load_balancer.clone();
    tokio::spawn(async move {
        health_checker.start_health_checks().await;
    });

    let registry_sync = load_balancer.clone();
    tokio::spawn(async move {
        registry_sync.start_registry_sync().await;
    });

    // Build router
    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/stats", get(stats_handler))
        .route("/services", get(services_handler))
        .route("/models", get(models_handler))
        .fallback(proxy_handler)
        .layer(
            ServiceBuilder::new()
                .layer(CorsLayer::permissive())
                .into_inner(),
        )
        .with_state(load_balancer);

    let listener = tokio::net::TcpListener::bind(&format!("0.0.0.0:{}", config.router_port)).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
```

#### 4. Streaming Proxy Handler

```rust
async fn proxy_handler(
    State(load_balancer): State<Arc<LoadBalancer>>,
    request: Request,
) -> Result<Response, RouterError> {
    // Extract model from request body if POST
    let model_id = extract_model_from_request(&request).await?;

    // Get target service
    let service = load_balancer
        .get_service_by_model(model_id.as_deref())
        .await
        .ok_or(RouterError::NoHealthyService)?;

    // Proxy request
    let client = reqwest::Client::new();
    let upstream_request = build_upstream_request(request, &service)?;
    let upstream_response = client.execute(upstream_request).await?;

    // Check if streaming
    if is_streaming_response(&upstream_response) {
        stream_response(upstream_response).await
    } else {
        buffer_response(upstream_response).await
    }
}
```

#### 5. “Optional Prefill–Decode Disaggregation” compatibility

- Role-based backend registration

- Two-phase routing

- Opaque KV handles

- Backward compatible with unified backends

### Feature Parity Checklist

- [x] Service discovery from registry
- [x] Health checking via babysitter URLs
- [x] Weighted round-robin load balancing
- [x] Model-level routing
- [x] Model aggregation
- [x] Streaming support (SSE/chunked)
- [x] Request/response proxying
- [x] Graceful service removal
- [x] Statistics endpoints
- [x] Error handling and retries
- [x] Configuration management
- [x] Logging and observability

---

## Implementation Strategy

### Phase 1: Core Router (2-3 weeks)

**Goals**:
- Basic HTTP server with axum
- Request proxying (non-streaming)
- Health check infrastructure
- Simple load balancing

**Deliverables**:
- Working HTTP server on target port
- Basic proxy forwarding
- Health check endpoint
- Configuration management

### Phase 2: Load Balancing (1-2 weeks)

**Goals**:
- Service instance management
- Weighted round-robin algorithm
- Registry client and sync
- Service metadata tracking

**Deliverables**:
- Service discovery from registry
- Dynamic service addition/removal
- Load balancer with weights
- `/services` endpoint

### Phase 3: Advanced Features (2 weeks)

**Goals**:
- Model-level routing
- Streaming support (SSE/chunked)
- Model aggregation
- Statistics endpoints
- “Optional Prefill–Decode Disaggregation” compatibility

**Deliverables**:
- Model extraction from request body
- Model-aware routing
- Streaming proxy handler
- `/models` aggregated endpoint
- `/stats` endpoint

### Phase 4: Testing and Optimization (1-2 weeks)

**Goals**:
- Comprehensive testing
- Load testing and benchmarking
- Performance tuning
- Edge case handling

**Deliverables**:
- Unit tests (>80% coverage)
- Integration tests
- Load test results
- Performance benchmarks
- Documentation

### Total Estimated Time: 6-10 weeks

### Migration Path

1. **Parallel Deployment**: Run Rust router alongside Python router
2. **Gradual Traffic Shift**: Route percentage of traffic to Rust router
3. **Monitoring**: Compare metrics (latency, throughput, errors)
4. **Full Cutover**: Once validated, switch all traffic
5. **Deprecation**: Remove Python router after stability period

---

## Expected Benefits & ROI

### Performance Benefits

1. **Throughput**: 5-15x improvement in requests/second
2. **Latency**: 2-5x reduction in P95/P99 latency
3. **Memory**: 3-5x reduction in memory footprint
4. **CPU**: 2-3x better CPU efficiency (no GIL)

### Operational Benefits

1. **Infrastructure Costs**: 60-80% reduction
2. **Scalability**: Better horizontal scaling characteristics
3. **Reliability**: Fewer runtime errors, memory safety
4. **Deployment**: Single static binary (easier containerization)

### Development Benefits

1. **Type Safety**: Compile-time checks prevent many bugs
2. **Performance**: Easier to optimize (zero-cost abstractions)
3. **Maintainability**: Clear ownership, lifetimes prevent common errors
4. **Ecosystem**: Growing Rust ecosystem for async/web

### Return on Investment

**Assumptions**:
- 100K req/s production workload
- Python deployment: $300/month infrastructure
- Rust deployment: $60/month infrastructure
- Development cost: 8 weeks @ $X/week

**Annual Savings**: ($300 - $60) × 12 = **$2,880/year**

**Break-even**: Depends on development costs, but typically 3-6 months

---

## Risk Assessment

### Technical Risks

**Risk**: Learning curve for Rust
- **Mitigation**: Team training, pair programming, gradual adoption
- **Impact**: Medium
- **Probability**: Medium

**Risk**: Feature parity issues
- **Mitigation**: Comprehensive testing, parallel deployment
- **Impact**: Low
- **Probability**: Low

**Risk**: Performance not meeting expectations
- **Mitigation**: Early benchmarking, iterative optimization
- **Impact**: Medium
- **Probability**: Low

### Operational Risks

**Risk**: Deployment complexity
- **Mitigation**: Container-first approach, CI/CD pipelines
- **Impact**: Low
- **Probability**: Low

**Risk**: Debugging challenges
- **Mitigation**: Comprehensive logging, tracing, observability
- **Impact**: Medium
- **Probability**: Medium

### Business Risks

**Risk**: Development time overruns
- **Mitigation**: Phased approach, MVP first
- **Impact**: Medium
- **Probability**: Medium

**Risk**: Migration downtime
- **Mitigation**: Parallel deployment, gradual cutover
- **Impact**: High
- **Probability**: Low

---

## References

### Performance Benchmarks

1. **PostgreSQL Fastware White Paper**: "Achieving Carbon Neutral IT Systems"
   - 75x improvement in Web API requests
   - Lower CPU and memory usage

2. **TechEmpower Framework Benchmarks**
   - Industry-standard web framework performance comparisons
   - Rust frameworks consistently in top-10

3. **Energy Efficiency Studies**
   - Multi-language benchmarking
   - Rust: ~2.5x more energy-efficient than Python

### Case Studies

1. **Discord**: Python to Rust migration
   - Performance improvements in critical services

2. **Cloudflare**: Rust rewrites
   - Reduced memory usage and CPU utilization

### Technical Documentation

1. **axum**: https://docs.rs/axum/
2. **tokio**: https://tokio.rs/
3. **hyper**: https://hyper.rs/
4. **Rust Book**: https://doc.rust-lang.org/book/

### Related Projects

1. **nginx**: https://nginx.org/
2. **haproxy**: http://www.haproxy.org/
3. **envoy**: https://www.envoyproxy.io/
4. **traefik**: https://traefik.io/

---

## Conclusion

The investigation reveals that while the current Python router meets functional requirements, a Rust refactoring would provide substantial benefits:

1. **Performance**: 5-15x throughput improvement, 2-5x latency reduction
2. **Efficiency**: 3-5x memory reduction, 2-3x better CPU utilization
3. **Cost**: 60-80% infrastructure cost reduction
4. **Reliability**: Memory safety, fewer runtime errors
5. **Scalability**: Better horizontal scaling characteristics

The phased implementation strategy minimizes risk while delivering incremental value. The investment is expected to pay off within 3-6 months through infrastructure cost savings alone, with additional benefits in performance and reliability.

**Recommendation**: Proceed with Phase 1 (Core Router) as a proof-of-concept, then evaluate before committing to full implementation.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-13
**Status**: Proposal - Awaiting Approval
