#!/usr/bin/env bash
# InfiniLM-SVC Installation Script
# Builds and installs InfiniLM-SVC binaries in a base image or system
#
# Usage:
#   ./scripts/install.sh [OPTIONS]
#
# Options:
#   --skip-rust-install    Skip Rust installation (assumes Rust is already installed)
#   --skip-build           Skip building binaries (assumes binaries already exist)
#   --install-path PATH    Installation path for binaries (default: /usr/local/bin)
#   --build-only           Only build, don't install binaries
#   --help                 Show this help message

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SKIP_RUST_INSTALL=false
SKIP_BUILD=false
INSTALL_PATH="/usr/local/bin"
BUILD_ONLY=false
PROJECT_ROOT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-rust-install)
            SKIP_RUST_INSTALL=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --install-path)
            INSTALL_PATH="$2"
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=true
            shift
            ;;
        --help)
            echo "InfiniLM-SVC Installation Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-rust-install    Skip Rust installation"
            echo "  --skip-build           Skip building binaries"
            echo "  --install-path PATH    Installation path (default: /usr/local/bin)"
            echo "  --build-only           Only build, don't install"
            echo "  --help                 Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Determine project root
if [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    # Fallback if script is piped/curl'd
    PROJECT_ROOT="${PWD}"
    if [ ! -d "${PROJECT_ROOT}/rust" ]; then
        echo -e "${RED}Error: Cannot find project root. Please run from InfiniLM-SVC directory.${NC}"
        exit 1
    fi
fi

cd "${PROJECT_ROOT}" || exit 1

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}InfiniLM-SVC Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif command_exists uname; then
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    else
        OS="unknown"
    fi
}

# Function to install system dependencies
install_system_deps() {
    echo -e "${BLUE}[1/5] Installing system dependencies...${NC}"

    detect_os

    case $OS in
        ubuntu|debian)
            if ! command_exists apt-get; then
                echo -e "${YELLOW}Warning: apt-get not found, skipping system dependencies${NC}"
                return
            fi
            apt-get update
            apt-get install -y \
                build-essential \
                pkg-config \
                libssl-dev \
                ca-certificates \
                curl \
                bash \
                || echo -e "${YELLOW}Warning: Some packages may have failed to install${NC}"
            ;;
        alpine)
            if ! command_exists apk; then
                echo -e "${YELLOW}Warning: apk not found, skipping system dependencies${NC}"
                return
            fi
            apk add --no-cache \
                build-base \
                pkgconfig \
                openssl-dev \
                ca-certificates \
                curl \
                bash
            ;;
        centos|rhel|fedora)
            if command_exists yum; then
                yum install -y \
                    gcc \
                    pkgconfig \
                    openssl-devel \
                    ca-certificates \
                    curl \
                    bash
            elif command_exists dnf; then
                dnf install -y \
                    gcc \
                    pkgconfig \
                    openssl-devel \
                    ca-certificates \
                    curl \
                    bash
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown OS ($OS), skipping system dependencies${NC}"
            echo "Please install: build-essential/gcc, pkg-config, libssl-dev/openssl-devel, curl, bash"
            ;;
    esac

    echo -e "${GREEN}✓ System dependencies installed${NC}"
    echo ""
}

# Function to install Rust
install_rust() {
    if [ "${SKIP_RUST_INSTALL}" = "true" ]; then
        echo -e "${BLUE}[2/5] Skipping Rust installation${NC}"
        if ! command_exists cargo; then
            echo -e "${RED}Error: Rust not found but --skip-rust-install was specified${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Using existing Rust installation${NC}"
        echo ""
        return
    fi

    echo -e "${BLUE}[2/5] Installing Rust...${NC}"

    if command_exists cargo && command_exists rustc; then
        RUST_VERSION=$(rustc --version 2>/dev/null | cut -d' ' -f2 || echo "unknown")
        echo -e "${GREEN}✓ Rust already installed (version: ${RUST_VERSION})${NC}"
        echo ""
        return
    fi

    echo "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

    # Add Rust to PATH
    export PATH="$HOME/.cargo/bin:${PATH}"

    # Also add to current shell session
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # Verify installation
    if command_exists cargo && command_exists rustc; then
        echo -e "${GREEN}✓ Rust installed successfully${NC}"
        rustc --version
        cargo --version
    else
        echo -e "${RED}Error: Rust installation failed${NC}"
        exit 1
    fi
    echo ""
}

# Function to build binaries
build_binaries() {
    if [ "${SKIP_BUILD}" = "true" ]; then
        echo -e "${BLUE}[3/5] Skipping build${NC}"
        if [ ! -f "${PROJECT_ROOT}/rust/target/release/infini-registry" ] || \
           [ ! -f "${PROJECT_ROOT}/rust/target/release/infini-router" ] || \
           [ ! -f "${PROJECT_ROOT}/rust/target/release/infini-babysitter" ]; then
            echo -e "${RED}Error: Binaries not found but --skip-build was specified${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Using existing binaries${NC}"
        echo ""
        return
    fi

    echo -e "${BLUE}[3/5] Building Rust binaries...${NC}"

    cd "${PROJECT_ROOT}/rust" || exit 1

    # Ensure Cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # Build release binaries
    echo "Building infini-registry, infini-router, and infini-babysitter..."
    cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Build completed successfully${NC}"

        # Show binary sizes
        echo ""
        echo "Built binaries:"
        ls -lh target/release/infini-* | awk '{print "  " $9 " (" $5 ")"}'
    else
        echo -e "${RED}Error: Build failed${NC}"
        exit 1
    fi

    cd "${PROJECT_ROOT}" || exit 1
    echo ""
}

# Function to install binaries
install_binaries() {
    if [ "${BUILD_ONLY}" = "true" ]; then
        echo -e "${BLUE}[4/5] Skipping installation (--build-only specified)${NC}"
        echo ""
        return
    fi

    echo -e "${BLUE}[4/5] Installing binaries to ${INSTALL_PATH}...${NC}"

    # Create install directory if it doesn't exist
    mkdir -p "${INSTALL_PATH}"

    # Copy binaries
    BINARIES=(
        "rust/target/release/infini-registry"
        "rust/target/release/infini-router"
        "rust/target/release/infini-babysitter"
    )

    for binary in "${BINARIES[@]}"; do
        if [ -f "${PROJECT_ROOT}/${binary}" ]; then
            cp "${PROJECT_ROOT}/${binary}" "${INSTALL_PATH}/"
            chmod +x "${INSTALL_PATH}/$(basename ${binary})"
            echo -e "  ${GREEN}✓${NC} Installed $(basename ${binary})"
        else
            echo -e "  ${RED}✗${NC} Binary not found: ${binary}"
        fi
    done

    echo -e "${GREEN}✓ Binaries installed${NC}"
    echo ""
}

# Function to set up scripts and directories
setup_scripts() {
    echo -e "${BLUE}[5/5] Setting up scripts and directories...${NC}"

    # Make scripts executable
    if [ -d "${PROJECT_ROOT}/script" ]; then
        chmod +x "${PROJECT_ROOT}"/script/*.sh 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Made scripts executable"
    fi

    if [ -d "${PROJECT_ROOT}/docker" ]; then
        chmod +x "${PROJECT_ROOT}"/docker/*.sh 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Made Docker scripts executable"
    fi

    # Create necessary directories
    mkdir -p "${PROJECT_ROOT}/logs"
    mkdir -p "${PROJECT_ROOT}/config"
    echo -e "  ${GREEN}✓${NC} Created directories (logs, config)"

    echo -e "${GREEN}✓ Setup complete${NC}"
    echo ""
}

# Main installation flow
main() {
    install_system_deps
    install_rust
    build_binaries
    install_binaries
    setup_scripts

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    if [ "${BUILD_ONLY}" = "false" ]; then
        echo "Binaries installed to: ${INSTALL_PATH}"
        echo ""
        echo "Verify installation:"
        echo "  ${INSTALL_PATH}/infini-registry --help"
        echo "  ${INSTALL_PATH}/infini-router --help"
        echo "  ${INSTALL_PATH}/infini-babysitter --help"
    else
        echo "Binaries built in: ${PROJECT_ROOT}/rust/target/release/"
        echo ""
        echo "To install manually:"
        echo "  cp ${PROJECT_ROOT}/rust/target/release/infini-* ${INSTALL_PATH}/"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Configure babysitter configs in config/ directory"
    echo "  2. See docker/README.md for Docker deployment"
    echo "  3. See QUICKSTART.md for usage examples"
    echo ""
}

# Run main function
main
