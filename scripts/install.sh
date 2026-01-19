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
APP_ROOT="${APP_ROOT:-/app}"
SETUP_APP_ROOT="${SETUP_APP_ROOT:-auto}" # auto|true|false
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-auto}" # auto|true|false (installs python3 + pip + aiohttp for mock service)

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
        --app-root)
            APP_ROOT="$2"
            shift 2
            ;;
        --setup-app-root)
            # auto|true|false
            SETUP_APP_ROOT="$2"
            shift 2
            ;;
        --install-python-deps)
            # auto|true|false
            INSTALL_PYTHON_DEPS="$2"
            shift 2
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
            echo "  --app-root PATH        App root to stage runtime files (default: /app; env: APP_ROOT)"
            echo "  --setup-app-root MODE  auto|true|false (default: auto; env: SETUP_APP_ROOT)"
            echo "  --install-python-deps MODE  auto|true|false (default: auto; env: INSTALL_PYTHON_DEPS)"
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

        # Handle Kylin Linux and other Debian/Ubuntu-based distributions
        if [ "$OS" = "kylin" ] || [ "$ID_LIKE" = "debian" ] || [ "$ID_LIKE" = "ubuntu" ]; then
            # Check if apt-get is available (Debian/Ubuntu-based)
            if command_exists apt-get; then
                OS="debian"
                echo -e "${BLUE}Detected Debian/Ubuntu-based OS (${ID})${NC}"
            fi
        fi
    elif command_exists uname; then
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    else
        OS="unknown"
    fi

    # Fallback: detect by package manager
    if [ "$OS" = "unknown" ] || [ -z "$OS" ]; then
        if command_exists apt-get; then
            OS="debian"
            echo -e "${BLUE}Detected Debian/Ubuntu-based OS via package manager${NC}"
        elif command_exists yum; then
            OS="centos"
            echo -e "${BLUE}Detected CentOS/RHEL-based OS via package manager${NC}"
        elif command_exists apk; then
            OS="alpine"
            echo -e "${BLUE}Detected Alpine Linux via package manager${NC}"
        fi
    fi
}

# Function to check if OpenSSL is available
check_openssl() {
    if command_exists pkg-config; then
        if pkg-config --exists openssl 2>/dev/null; then
            return 0
        fi
    fi

    # Check for OpenSSL headers
    if [ -f /usr/include/openssl/ssl.h ] || [ -f /usr/local/include/openssl/ssl.h ]; then
        return 0
    fi

    return 1
}

# Function to install system dependencies
install_system_deps() {
    echo -e "${BLUE}[1/5] Installing system dependencies...${NC}"

    detect_os

    INSTALLED=false

    case $OS in
        ubuntu|debian)
            if ! command_exists apt-get; then
                echo -e "${YELLOW}Warning: apt-get not found, trying alternative methods...${NC}"
            else
                echo "Installing dependencies via apt-get..."
                apt-get update
                if apt-get install -y \
                    build-essential \
                    pkg-config \
                    libssl-dev \
                    ca-certificates \
                    curl \
                    bash; then
                    INSTALLED=true
                else
                    echo -e "${YELLOW}Warning: Some packages may have failed to install${NC}"
                fi
            fi
            ;;
        alpine)
            if ! command_exists apk; then
                echo -e "${YELLOW}Warning: apk not found, skipping system dependencies${NC}"
            else
                echo "Installing dependencies via apk..."
                if apk add --no-cache \
                    build-base \
                    pkgconfig \
                    openssl-dev \
                    ca-certificates \
                    curl \
                    bash; then
                    INSTALLED=true
                fi
            fi
            ;;
        centos|rhel|fedora)
            if command_exists yum; then
                echo "Installing dependencies via yum..."
                if yum install -y \
                    gcc \
                    pkgconfig \
                    openssl-devel \
                    ca-certificates \
                    curl \
                    bash; then
                    INSTALLED=true
                fi
            elif command_exists dnf; then
                echo "Installing dependencies via dnf..."
                if dnf install -y \
                    gcc \
                    pkgconfig \
                    openssl-devel \
                    ca-certificates \
                    curl \
                    bash; then
                    INSTALLED=true
                fi
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown OS ($OS), trying to detect package manager...${NC}"
            # Try common package managers as fallback
            if command_exists apt-get; then
                echo "Detected apt-get, attempting installation..."
                apt-get update && \
                apt-get install -y build-essential pkg-config libssl-dev ca-certificates curl bash && \
                INSTALLED=true
            elif command_exists yum; then
                echo "Detected yum, attempting installation..."
                yum install -y gcc pkgconfig openssl-devel ca-certificates curl bash && \
                INSTALLED=true
            elif command_exists apk; then
                echo "Detected apk, attempting installation..."
                apk add --no-cache build-base pkgconfig openssl-dev ca-certificates curl bash && \
                INSTALLED=true
            fi
            ;;
    esac

    # Verify OpenSSL is available
    if ! check_openssl; then
        echo -e "${RED}Error: OpenSSL development libraries not found${NC}"
        echo ""
        echo "Please install OpenSSL development packages:"
        case $OS in
            ubuntu|debian)
                echo "  sudo apt-get install libssl-dev pkg-config"
                ;;
            alpine)
                echo "  apk add openssl-dev pkgconfig"
                ;;
            centos|rhel|fedora)
                echo "  sudo yum install openssl-devel pkgconfig"
                ;;
            *)
                echo "  Install libssl-dev (Debian/Ubuntu) or openssl-devel (CentOS/RHEL/Fedora)"
                ;;
        esac
        echo ""
        echo "If OpenSSL is installed in a non-standard location, set:"
        echo "  export OPENSSL_DIR=/path/to/openssl"
        echo "  export PKG_CONFIG_PATH=/path/to/openssl/lib/pkgconfig"
        exit 1
    fi

    if [ "$INSTALLED" = "true" ]; then
        echo -e "${GREEN}✓ System dependencies installed${NC}"
    else
        echo -e "${YELLOW}⚠ Could not install system dependencies automatically${NC}"
        echo "Please install manually: build-essential/gcc, pkg-config, libssl-dev/openssl-devel, curl, bash"
    fi
    echo ""
}

# Install Python deps for the integration demo mock service
# This is needed when babysitter backend runs demo/integration-validation/mock_service.py
install_python_deps() {
    # Decide whether to run
    local should_install=false
    if [ "${INSTALL_PYTHON_DEPS}" = "true" ]; then
        should_install=true
    elif [ "${INSTALL_PYTHON_DEPS}" = "false" ]; then
        should_install=false
    else
        # auto: install if we're root and inside a container OR python3 already exists
        if [ "$(id -u)" = "0" ] && [ -f "/.dockerenv" ]; then
            should_install=true
        elif command_exists python3; then
            should_install=true
        fi
    fi

    if [ "${should_install}" != "true" ]; then
        return 0
    fi

    if [ "$(id -u)" != "0" ]; then
        echo -e "${YELLOW}⚠ Skipping Python deps install (needs root). Set INSTALL_PYTHON_DEPS=false to silence.${NC}"
        return 0
    fi

    echo -e "${BLUE}Installing Python deps for mock service (python3 + pip + requirements.txt)...${NC}"
    detect_os

    # Ensure python3 + pip
    if ! command_exists python3 || ! command_exists pip3; then
        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y python3 python3-pip
                ;;
            alpine)
                apk add --no-cache python3 py3-pip
                ;;
            centos|rhel|fedora)
                if command_exists yum; then
                    yum install -y python3 python3-pip
                elif command_exists dnf; then
                    dnf install -y python3 python3-pip
                fi
                ;;
            *)
                # Package-manager fallback
                if command_exists apt-get; then
                    apt-get update && apt-get install -y python3 python3-pip
                elif command_exists apk; then
                    apk add --no-cache python3 py3-pip
                elif command_exists yum; then
                    yum install -y python3 python3-pip
                elif command_exists dnf; then
                    dnf install -y python3 python3-pip
                else
                    echo -e "${YELLOW}⚠ Could not install python3/pip automatically. Please install python3 + pip manually.${NC}"
                    return 0
                fi
                ;;
        esac
    fi

    # Install Python dependencies from requirements.txt
    # Look for requirements files in common locations (priority order)
    local requirements_file=""
    if [ -f "${PROJECT_ROOT}/requirements.txt" ]; then
        # Root-level requirements (for demo/integration testing)
        requirements_file="${PROJECT_ROOT}/requirements.txt"
    elif [ -f "${PROJECT_ROOT}/python/requirements.txt" ]; then
        # Full Python implementation requirements
        requirements_file="${PROJECT_ROOT}/python/requirements.txt"
    fi

    if [ -z "${requirements_file}" ] || [ ! -f "${requirements_file}" ]; then
        echo -e "${YELLOW}⚠ No requirements file found; skipping python deps install${NC}"
        echo ""
        return 0
    fi

    # Install deps into system python3 (if present)
    if command_exists python3; then
        echo "Installing Python dependencies into system python3 from ${requirements_file}..."
        python3 -m pip install --no-cache-dir -r "${requirements_file}" >/dev/null 2>&1 || \
            python3 -m pip install --no-cache-dir -r "${requirements_file}"
        echo -e "${GREEN}✓ Python deps installed into system python3${NC}"
    fi

    # Also install into conda base if present (some images have python3 pointing to conda)
    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
        echo "Installing Python dependencies into conda base from ${requirements_file}..."
        # shellcheck disable=SC1091
        source /opt/conda/etc/profile.d/conda.sh
        conda activate base
        python -m pip install --no-cache-dir -r "${requirements_file}" >/dev/null 2>&1 || \
            python -m pip install --no-cache-dir -r "${requirements_file}"
        echo -e "${GREEN}✓ Python deps installed into conda base${NC}"
    fi

    if ! command_exists python3 && [ ! -f "/opt/conda/etc/profile.d/conda.sh" ]; then
        echo -e "${YELLOW}⚠ python3 not found; cannot install Python dependencies${NC}"
    fi
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

    # Verify OpenSSL before building
    if ! check_openssl; then
        echo -e "${RED}Error: OpenSSL development libraries not found${NC}"
        echo ""
        echo "The build requires OpenSSL development libraries."
        echo "Please install them and run the script again:"
        echo "  - Debian/Ubuntu/Kylin: sudo apt-get install libssl-dev pkg-config"
        echo "  - CentOS/RHEL: sudo yum install openssl-devel pkgconfig"
        echo "  - Alpine: apk add openssl-dev pkgconfig"
        echo ""
        echo "Or set OPENSSL_DIR if installed in non-standard location:"
        echo "  export OPENSSL_DIR=/path/to/openssl"
        exit 1
    fi

    cd "${PROJECT_ROOT}/rust" || exit 1

    # Ensure Cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # Build release binaries
    echo "Building infini-registry, infini-router, and infini-babysitter..."

    # Set OpenSSL environment variables if needed
    if [ -n "${OPENSSL_DIR:-}" ]; then
        export OPENSSL_DIR
        echo "Using OPENSSL_DIR: ${OPENSSL_DIR}"
    fi

    if cargo build --release --bin infini-registry --bin infini-router --bin infini-babysitter; then
        echo -e "${GREEN}✓ Build completed successfully${NC}"

        # Show binary sizes
        echo ""
        echo "Built binaries:"
        ls -lh target/release/infini-* 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || true
    else
        echo -e "${RED}Error: Build failed${NC}"
        echo ""
        echo "Common issues:"
        echo "  1. Missing OpenSSL development libraries"
        echo "     Fix: Install libssl-dev (Debian/Ubuntu) or openssl-devel (CentOS/RHEL)"
        echo ""
        echo "  2. OpenSSL not found by pkg-config"
        echo "     Fix: Set PKG_CONFIG_PATH or OPENSSL_DIR environment variables"
        echo ""
        echo "  3. Insufficient memory"
        echo "     Fix: Set CARGO_BUILD_JOBS=2 to reduce parallelism"
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

    # Copy docker entrypoint to /app if /app exists (Docker container setup)
    if [ -d "/app" ] && [ -f "${PROJECT_ROOT}/docker/docker_entrypoint_rust.sh" ]; then
        cp "${PROJECT_ROOT}/docker/docker_entrypoint_rust.sh" "/app/docker_entrypoint.sh"
        chmod +x "/app/docker_entrypoint.sh"
        echo -e "  ${GREEN}✓${NC} Copied docker entrypoint to /app/docker_entrypoint.sh"
    fi

    # Create necessary directories
    mkdir -p "${PROJECT_ROOT}/logs"
    mkdir -p "${PROJECT_ROOT}/config"
    echo -e "  ${GREEN}✓${NC} Created directories (logs, config)"

    # Stage a runnable layout into APP_ROOT (useful for base-image installs)
    # We only do this when running as root (or explicitly requested),
    # because creating /app on a host machine can be undesirable.
    should_setup_app_root=false
    if [ "${SETUP_APP_ROOT}" = "true" ]; then
        should_setup_app_root=true
    elif [ "${SETUP_APP_ROOT}" = "false" ]; then
        should_setup_app_root=false
    else
        # auto: do it if we're root or inside a container
        if [ "$(id -u)" = "0" ]; then
            should_setup_app_root=true
        elif [ -f "/.dockerenv" ]; then
            should_setup_app_root=true
        fi
    fi

    if [ "${should_setup_app_root}" = "true" ]; then
        if [ "$(id -u)" != "0" ]; then
            echo -e "  ${YELLOW}⚠${NC} Skipping APP_ROOT staging (needs root). Set --setup-app-root false to silence."
        else
            mkdir -p "${APP_ROOT}"
            mkdir -p "${APP_ROOT}/script"
            mkdir -p "${APP_ROOT}/config"
            mkdir -p "${APP_ROOT}/logs"

            # Copy entrypoint
            if [ -f "${PROJECT_ROOT}/docker/docker_entrypoint_rust.sh" ]; then
                cp "${PROJECT_ROOT}/docker/docker_entrypoint_rust.sh" "${APP_ROOT}/docker_entrypoint.sh"
                chmod +x "${APP_ROOT}/docker_entrypoint.sh"
                echo -e "  ${GREEN}✓${NC} Staged entrypoint: ${APP_ROOT}/docker_entrypoint.sh"
            else
                echo -e "  ${YELLOW}⚠${NC} docker/docker_entrypoint_rust.sh not found; entrypoint not staged"
            fi

            # Copy launch scripts (runtime needs these)
            if [ -d "${PROJECT_ROOT}/script" ]; then
                cp -a "${PROJECT_ROOT}/script/." "${APP_ROOT}/script/"
                chmod +x "${APP_ROOT}"/script/*.sh 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged scripts: ${APP_ROOT}/script/"
            else
                echo -e "  ${YELLOW}⚠${NC} script/ directory not found; scripts not staged"
            fi

            # Copy configs as examples/defaults
            if [ -d "${PROJECT_ROOT}/config" ]; then
                cp -a "${PROJECT_ROOT}/config/." "${APP_ROOT}/config/" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged configs: ${APP_ROOT}/config/"
            fi

            # Copy env-set.sh if available (used by conda-based entrypoints / hardware env)
            if [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
                cp "${PROJECT_ROOT}/env-set.sh" "${APP_ROOT}/env-set.sh"
                chmod +x "${APP_ROOT}/env-set.sh" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged env-set.sh: ${APP_ROOT}/env-set.sh"
            elif [ -f "${PROJECT_ROOT}/demo/integration-validation/env-set.sh" ]; then
                cp "${PROJECT_ROOT}/demo/integration-validation/env-set.sh" "${APP_ROOT}/env-set.sh"
                chmod +x "${APP_ROOT}/env-set.sh" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged env-set.sh (demo): ${APP_ROOT}/env-set.sh"
            fi
        fi
    fi

    echo -e "${GREEN}✓ Setup complete${NC}"
    echo ""
}

# Main installation flow
main() {
    install_system_deps
    install_rust
    build_binaries
    install_binaries
    install_python_deps
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
