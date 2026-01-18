# Why Python Registry in Integration Tests?

## Current Architecture

The integration tests use the **Python service registry** (`python/service_registry.py`) instead of a Rust implementation. Here's why:

## 1. No Rust Registry Server Implementation

**Current State:**
- ✅ **Rust Registry Client** exists (`rust/src/registry/client.rs`) - used by router to fetch services
- ✅ **Rust Babysitter Registry Client** exists (`rust/src/bin/registry_client.rs`) - used by babysitter to register services
- ❌ **Rust Registry Server** does NOT exist - there's no Rust implementation of the registry service itself

**What exists:**
- `rust/src/registry/client.rs` - HTTP client for router to query registry
- `rust/src/bin/registry_client.rs` - HTTP client for babysitter to register with registry
- `python/service_registry.py` - The actual registry server implementation

## 2. Registry is a Separate Service

The registry is designed as an **independent service** that:
- Provides service discovery and registration
- Maintains service health status
- Handles heartbeats
- Exposes HTTP API endpoints

Both Python and Rust components communicate with the registry via **HTTP**, so the registry implementation language doesn't matter to clients.

## 3. Registry API Contract

The registry provides these HTTP endpoints:
- `POST /services` - Register a service
- `POST /services/{name}/heartbeat` - Send heartbeat
- `GET /services` - List all services
- `GET /services?healthy=true` - List only healthy services
- `GET /health` - Registry health check

The Rust router and babysitter are **clients** that use these endpoints. They don't depend on the registry's implementation language.

## 4. Refactoring Scope

The Rust refactoring focused on:
- ✅ Router (Python → Rust) - **Completed**
- ✅ Babysitter (Python → Rust) - **Completed**
- ❌ Registry (Python → Rust) - **Not in scope**

The registry is a stable, working component that doesn't need refactoring for the current goals.

## 5. Benefits of Using Python Registry

1. **Proven and Stable**: The Python registry is already tested and working
2. **No Additional Development**: No need to implement a Rust registry just for tests
3. **Separation of Concerns**: Registry is independent of router/babysitter implementation
4. **Compatibility**: Both Python and Rust components can use the same registry

## Could We Use a Rust Registry?

**Yes, but it's not necessary:**

1. **For Testing**: The Python registry works perfectly fine for integration tests
2. **For Production**: The registry can remain Python while router/babysitter are Rust
3. **For Future**: A Rust registry could be implemented if needed, but it's not a priority

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│              Service Registry (Python)                   │
│         python/service_registry.py                       │
│         Port: 8901                                       │
│                                                           │
│  - Service registration                                  │
│  - Heartbeat management                                  │
│  - Health status tracking                                │
│  - Service discovery API                                 │
└───────────────┬─────────────────────────────────────────┘
                │
                │ HTTP API
                │
        ┌───────┴────────┐
        │                │
┌───────▼──────┐  ┌──────▼──────────┐
│ Rust Router  │  │ Rust Babysitter │
│              │  │                 │
│ Uses:        │  │ Uses:           │
│ - Registry   │  │ - Registry      │
│   Client     │  │   Client        │
│   (Rust)     │  │   (Rust)        │
└──────────────┘  └─────────────────┘
```

## Summary

**Why Python Registry?**
- No Rust registry server implementation exists
- Registry is a separate service (language-independent)
- Python registry is stable and works well
- Not in scope of current refactoring
- Both Python and Rust components can use it via HTTP

**Should we implement a Rust registry?**
- Not necessary for current goals
- Could be done in the future if needed
- Would provide consistency but no functional benefit
- Current architecture (Python registry, Rust router/babysitter) is valid

The integration test uses Python registry because it's the existing, working implementation. The Rust components communicate with it via HTTP, so the implementation language is transparent to them.
