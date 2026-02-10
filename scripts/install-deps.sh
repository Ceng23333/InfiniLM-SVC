#!/usr/bin/env bash
# InfiniLM-SVC Phase 1: Dependency Installation Script
# Installs all dependencies requiring network/proxy, downloads Rust crates
# This script is designed for Phase 1 of a two-phase build process
#
# Usage:
#   ./scripts/install-deps.sh [OPTIONS]
#
# Options:
#   --skip-rust-install    Skip Rust installation (assumes Rust is already installed)
#   --deployment-case NAME  Deployment case preset name (loads deployment/cases/NAME; env: DEPLOYMENT_CASE)
#   --help                 Show this help message
#
# This script:
#   - Installs system dependencies
#   - Installs Rust toolchain
#   - Installs xmake
#   - Installs Python dependencies
#   - Clones and installs InfiniCore/InfiniLM (if enabled via deployment case)
#   - Downloads Rust crate dependencies (cargo fetch)
#   - Does NOT build InfiniLM-SVC binaries (that's Phase 2)
#
# Note: InfiniCore/InfiniLM are installed in Phase 1 to ensure Phase 2 can build offline

set -e

# Source the main install.sh script to reuse its functions
# We'll call only the Phase 1 functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"

# Check if install.sh exists
if [ ! -f "${INSTALL_SCRIPT}" ]; then
    echo "Error: install.sh not found at ${INSTALL_SCRIPT}"
    exit 1
fi

# Source install.sh to get all functions and setup
# Set a flag to prevent install.sh's main() from executing
SKIP_INSTALL_MAIN=true
source "${INSTALL_SCRIPT}"
unset SKIP_INSTALL_MAIN

# Override main() to run only Phase 1
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}InfiniLM-SVC Phase 1: Dependency Installation${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Load deployment-case defaults early so it can influence installation behavior.
    load_deployment_case_preset

    # Verify proxy accessibility early (before any network operations)
    verify_proxy

    # Ensure git is available early (needed for potential future operations)
    ensure_git || {
        echo -e "${YELLOW}⚠ git not available, some features may be limited${NC}"
    }

    # Phase 1: Install dependencies
    install_system_deps
    install_rust
    install_xmake
    install_python_deps

    # Clone and install InfiniCore and InfiniLM in Phase 1
    # This ensures Phase 2 can build offline without needing network access
    echo -e "${BLUE}Cloning and installing InfiniCore/InfiniLM (for offline Phase 2 build)...${NC}"

    # Temporarily clear INSTALL_PHASE to allow installation
    # install_infinicore_and_infinilm_optional skips if INSTALL_PHASE="deps"
    # We want to install in Phase 1, so we clear it to allow the function to proceed
    local saved_install_phase="${INSTALL_PHASE:-}"
    unset INSTALL_PHASE  # Clear it so the function doesn't skip

    # Install InfiniCore and InfiniLM (will clone if needed)
    install_infinicore_and_infinilm_optional

    # Restore original phase (if it was set)
    if [ -n "${saved_install_phase}" ]; then
        INSTALL_PHASE="${saved_install_phase}"
    else
        unset INSTALL_PHASE
    fi

    # Verify installations
    verify_infinicore_and_infinilm

    # Download Rust crate dependencies without building
    echo -e "${BLUE}Downloading Rust crate dependencies (cargo fetch)...${NC}"
    if [ ! -d "${PROJECT_ROOT}/rust" ]; then
        echo -e "${RED}Error: rust/ directory not found at ${PROJECT_ROOT}/rust${NC}"
        exit 1
    fi

    # Ensure Cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # Verify Rust is installed
    if ! command_exists cargo; then
        echo -e "${RED}Error: cargo not found. Rust installation may have failed.${NC}"
        exit 1
    fi

    # Change to rust directory and fetch dependencies
    cd "${PROJECT_ROOT}/rust" || exit 1

    if [ ! -f "Cargo.toml" ]; then
        echo -e "${RED}Error: Cargo.toml not found in ${PROJECT_ROOT}/rust${NC}"
        exit 1
    fi

    echo "Running cargo fetch to download all dependencies..."
    if cargo fetch --manifest-path Cargo.toml; then
        echo -e "${GREEN}✓ Rust dependencies downloaded and cached${NC}"
        echo "  Dependencies are cached in ~/.cargo/registry and ~/.cargo/git"
    else
        echo -e "${RED}Error: cargo fetch failed${NC}"
        exit 1
    fi

    cd "${PROJECT_ROOT}" || exit 1

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Phase 1 Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Dependencies installed:"
    echo "  ✓ System dependencies"
    echo "  ✓ Rust toolchain"
    echo "  ✓ xmake"
    echo "  ✓ Python dependencies"
    echo "  ✓ InfiniCore/InfiniLM (cloned and installed)"
    echo "  ✓ Rust crate dependencies (cached)"
    echo ""
    echo "Next steps:"
    echo "  1. Commit this intermediate image for reuse"
    echo "  2. Run Phase 2 (install-build.sh) to build from local sources"
    echo ""
}

# Run main function
main
