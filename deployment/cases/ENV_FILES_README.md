# Environment Files for Deployment Cases

This directory contains `.env.example` files for each deployment case to simplify launching start scripts.

## Quick Start

1. **Copy the example file to `.env`:**
   ```bash
   cd <deployment-case>
   cp .env.example .env
   ```

2. **Edit `.env` with your values:**
   ```bash
   # Uncomment and set required paths
   MODEL1_DIR=/path/to/your/model
   ```

3. **Source the file and run the start script:**
   ```bash
   source .env
   ./start-master.sh localhost
   ```

## Available Environment Files

### infinilm-metax-deployment
- **`.env.example`** - Master node configuration
- **`.env.slave.example`** - Slave node configuration

### cache-type-routing-validation
- **`.env.example`** - Configuration for cache type routing validation

### cache-routing-validation
- **`.env.example`** - Configuration for cache routing validation

### integration-validation
- **`.env.server1.example`** - Server 1 (Registry + Router + Babysitters A, B)
- **`.env.server2.example`** - Server 2 (Babysitters C, D)

## How It Works

All start scripts automatically load `.env` files if they exist:

1. Scripts check for case-specific `.env` files (e.g., `.env.slave`, `.env.server1`)
2. If not found, they fall back to `.env`
3. Environment variables are loaded before defaults are applied
4. You can still override variables via command line or environment

## Example: infinilm-metax-deployment

```bash
# 1. Copy and customize
cd infinilm-metax-deployment
cp .env.example .env
# Edit .env: set MODEL1_DIR and MODEL2_DIR

# 2. Start master
source .env
./start-master.sh localhost

# 3. Start slave (on another host)
cp .env.slave.example .env.slave
# Edit .env.slave: set MODEL2_GGUF
source .env.slave
./start-slave.sh <MASTER_IP> <SLAVE_IP>
```

## Benefits

- **No manual export**: No need to `export` variables one by one
- **Easy configuration**: All settings in one place
- **Version control friendly**: `.env` files are gitignored, `.env.example` is tracked
- **Flexible**: Can still override via command line or environment

## Notes

- `.env` files are automatically ignored by git (via `.gitignore`)
- `.env.example` files are tracked in git as templates
- Start scripts load `.env` files before applying defaults
- Environment variables set in `.env` can still be overridden
