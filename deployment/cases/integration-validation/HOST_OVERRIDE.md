# Host Override for Cross-Server Registration

## Problem

When babysitters register with a remote registry, the `host` field in the registration must be the actual IP address or hostname that other services can use to connect to it, not `0.0.0.0`.

- `host = "0.0.0.0"` is correct for **binding/listening** (listen on all interfaces)
- But for **registration**, we need the actual IP address (e.g., `192.168.1.100`)

## Solution

The demo uses the `BABYSITTER_HOST` environment variable to override the host for registration.

### How It Works

1. **Config File**: Uses `host = "0.0.0.0"` for binding (listens on all interfaces)
2. **Environment Variable**: `BABYSITTER_HOST` is set to the server's actual IP
3. **Launch Script**: Passes `--host` CLI argument to override config file value
4. **Registration**: Uses the overridden host value for registry registration

### Example

**Server 2 Config (babysitter-c.toml):**
```toml
host = "0.0.0.0"  # For binding/listening
```

**Server 2 Start Script:**
```bash
-e BABYSITTER_HOST="${SERVER2_IP}"  # Override for registration
```

**Result:**
- Service binds on `0.0.0.0:8100` (all interfaces)
- Registers with host `192.168.1.100` (actual IP)
- Other services can connect using `http://192.168.1.100:8100`

## Implementation

1. **Launch Script** (`launch_all_rust.sh`):
   - Checks for `BABYSITTER_HOST` environment variable
   - Passes `--host` CLI argument if set

2. **Babysitter** (`babysitter.rs`):
   - CLI arguments override config file values
   - Host from CLI takes precedence over config file host

3. **Entrypoint** (`docker_entrypoint_rust.sh`):
   - Exports `BABYSITTER_HOST` for use by launch script

## For Server 1

Server 1 babysitters (A, B) don't need host override because:
- They register with local registry (`localhost:18000`)
- Other services on the same server can use `localhost` or `127.0.0.1`
- The config file `host = "0.0.0.0"` is fine for local registration

## For Server 2

Server 2 babysitters (C, D) **must** have host override because:
- They register with remote registry on Server 1
- Server 1's router needs the actual IP to connect to Server 2 services
- `BABYSITTER_HOST` is set to `SERVER2_IP` in `start-server2.sh`

## Verification

Check registered services:
```bash
curl http://<SERVER1_IP>:18000/services | jq '.services[] | {name, host, port}'
```

Expected output:
- Server 1 services: `host: "0.0.0.0"` or `host: "localhost"` (OK for local)
- Server 2 services: `host: "<SERVER2_IP>"` (actual IP address)
