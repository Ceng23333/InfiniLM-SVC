# Phase 0: File Structure Reorganization Plan

## Proposed Directory Structure

```
InfiniLM-SVC/
├── README.md                          # Main project README
├── RUST_REFACTORING_PROPOSAL.md       # Refactoring proposal (keep at root)
├── PHASE0_FILE_STRUCTURE.md           # This file
│
├── router/                            # Router implementations
│   ├── python/                        # Python router (current implementation)
│   │   ├── distributed_router.py     # Main router service
│   │   ├── router_client.py          # Router client library
│   │   └── README.md                  # Python router documentation
│   │
│   └── rust/                          # Rust router (new implementation)
│       ├── Cargo.toml                 # Rust project configuration
│       ├── README.md                  # Rust router documentation
│       ├── src/                       # Rust source code
│       │   ├── main.rs
│       │   ├── config.rs
│       │   ├── router/
│       │   ├── registry/
│       │   ├── proxy/
│       │   ├── models/
│       │   ├── handlers/
│       │   └── utils/
│       └── tests/                     # Rust tests
│
├── registry/                          # Service registry (Python)
│   ├── service_registry.py
│   ├── registry_client.py
│   └── register_service.py
│
├── babysitter/                       # Babysitter implementations
│   ├── enhanced_babysitter.py
│   └── launch_babysitter*.sh
│
├── shared/                           # Shared resources
│   ├── configs/                      # Configuration files
│   │   └── deployment_configs/       # (move from root)
│   │       ├── registry_config.json
│   │       ├── router_config.json
│   │       ├── server1_services.json
│   │       ├── server2_services.json
│   │       └── test_services.json
│   │
│   ├── scripts/                      # Shared scripts
│   │   ├── launch_all.sh
│   │   ├── launch_registry.sh
│   │   ├── launch_router.sh          # Updated to support both Python/Rust
│   │   ├── stop_all.sh
│   │   ├── stop_registry.sh
│   │   ├── stop_router.sh
│   │   └── deploy_services.sh
│   │
│   ├── templates/                     # Configuration templates
│   │   └── service.toml.template
│   │
│   └── tests/                         # Integration tests
│       ├── test_service.py
│       ├── test_max_concurrency.py
│       ├── test_timeout_recovery.py
│       └── validate_integration.py
│
├── docs/                             # Documentation
│   ├── DISTRIBUTED_DEPLOYMENT_README.md
│   ├── MULTI_SERVICE_README.md
│   └── ...
│
├── logs/                             # Log files (created at runtime)
│
├── requirements.txt                  # Python dependencies
├── activate_env.sh                   # Environment activation
├── docker_entrypoint.sh              # Docker entrypoint
├── Dockerfile.example                # Docker example
└── service_qwen.toml                 # Example service config
```

## Migration Steps

### Step 1: Create Directory Structure
- Create `router/python/` directory
- Create `router/rust/` directory
- Create `shared/configs/deployment_configs/` directory
- Create `shared/scripts/` directory
- Create `shared/tests/` directory
- Create `registry/` directory
- Create `babysitter/` directory
- Create `docs/` directory

### Step 2: Move Python Router Files
- Move `distributed_router.py` → `router/python/distributed_router.py`
- Move `router_client.py` → `router/python/router_client.py`

### Step 3: Move Registry Files
- Move `service_registry.py` → `registry/service_registry.py`
- Move `registry_client.py` → `registry/registry_client.py`
- Move `register_service.py` → `registry/register_service.py`

### Step 4: Move Babysitter Files
- Move `enhanced_babysitter.py` → `babysitter/enhanced_babysitter.py`
- Move `launch_babysitter*.sh` → `babysitter/`

### Step 5: Move Shared Files
- Move `deployment_configs/` → `shared/configs/deployment_configs/`
- Move `templates/` → `shared/templates/`
- Move launch/stop scripts → `shared/scripts/`
- Move test files → `shared/tests/`
- Move `generate_nginx_config.py` → `shared/scripts/`
- Move `render_service_config.py` → `shared/scripts/`

### Step 6: Move Documentation
- Move `DISTRIBUTED_DEPLOYMENT_README.md` → `docs/`
- Move `MULTI_SERVICE_README.md` → `docs/`

### Step 7: Update Scripts
- Update `shared/scripts/launch_router.sh` to:
  - Support both Python and Rust implementations
  - Use new file paths
  - Add `--implementation python|rust` flag
- Update `shared/scripts/deploy_services.sh` to use new paths
- Update `shared/scripts/stop_router.sh` to use new paths
- Update `shared/tests/validate_integration.py` to use new paths

### Step 8: Update Documentation
- Update main `README.md` with new structure
- Update `router/python/README.md` with Python-specific docs
- Update `docs/DISTRIBUTED_DEPLOYMENT_README.md` with new paths

### Step 9: Verify Python Router Still Works
- Test launching Python router from new location
- Test all functionality (health checks, routing, registry sync)
- Verify logs are created correctly
- Test integration with registry and services

## Alternative: Simpler Structure (if preferred)

If the above is too complex, a simpler structure:

```
InfiniLM-SVC/
├── router-python/                    # Python router
│   ├── distributed_router.py
│   └── router_client.py
│
├── router-rust/                       # Rust router (new)
│   ├── Cargo.toml
│   └── src/
│
├── registry/                           # Service registry
│   └── ...
│
├── deployment_configs/                 # Keep at root (simpler)
├── launch_*.sh                        # Keep at root (simpler)
└── ...
```

## Decision Points

1. **Script location**: Keep at root for convenience, or move to `shared/scripts/`?
2. **Config location**: Keep `deployment_configs/` at root, or move to `shared/configs/`?
3. **Documentation**: Keep at root, or move to `docs/`?
4. **Test files**: Keep at root, or move to `shared/tests/`?

## Recommendation

Use the **simpler structure** initially:
- Less disruption to existing workflows
- Easier to migrate incrementally
- Can reorganize further later if needed
- Clear separation between Python and Rust implementations
