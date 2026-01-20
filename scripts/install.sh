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
#   --install-infinicore MODE   auto|true|false (default: auto; env: INSTALL_INFINICORE)
#   --install-infinilm MODE     auto|true|false (default: auto; env: INSTALL_INFINILM)
#   --infinicore-src PATH       Path to InfiniCore repo (default: ../InfiniCore; env: INFINICORE_SRC)
#   --infinilm-src PATH         Path to InfiniLM repo (default: ../InfiniLM; env: INFINILM_SRC)
#   --infinicore-branch BRANCH  Git branch/tag/commit to checkout in InfiniCore repo before install (env: INFINICORE_BRANCH)
#   --infinilm-branch BRANCH    Git branch/tag/commit to checkout in InfiniLM repo before install (env: INFINILM_BRANCH)
#   --deployment-case NAME      Deployment case preset name (loads deployment/cases/NAME; env: DEPLOYMENT_CASE)
#   --help                 Show this help message

set -e

# Environment setup (optional, but should be identical across deployment cases).
# Canonical location in images is `/app/env-set.sh` (staged from repo root `env-set.sh`).
# Source early so it affects all subsequent steps (deps install, build, etc.).
EARLY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "/app/env-set.sh" ]; then
    # shellcheck disable=SC1091
    source "/app/env-set.sh"
elif [ -n "${DEPLOYMENT_CASE:-}" ] && [ -f "${EARLY_SCRIPT_DIR}/../deployment/cases/${DEPLOYMENT_CASE}/env-set.sh" ]; then
    # If caller sets DEPLOYMENT_CASE in env, source the case env-set early so it affects
    # subsequent installs (notably xmake, which may require XMAKE_ROOT=y when running as root).
    # shellcheck disable=SC1091
    source "${EARLY_SCRIPT_DIR}/../deployment/cases/${DEPLOYMENT_CASE}/env-set.sh"
elif [ -f "${EARLY_SCRIPT_DIR}/../env-set.sh" ]; then
    # shellcheck disable=SC1091
    source "${EARLY_SCRIPT_DIR}/../env-set.sh"
elif [ -f "/workspace/env-set.sh" ]; then
    # shellcheck disable=SC1091
    source "/workspace/env-set.sh"
fi

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
INSTALL_INFINICORE="${INSTALL_INFINICORE:-auto}" # auto|true|false (installs InfiniCore python package + native build)
INSTALL_INFINILM="${INSTALL_INFINILM:-auto}"     # auto|true|false (installs InfiniLM python package + native build)
INFINICORE_SRC="${INFINICORE_SRC:-}"            # optional, defaults resolved later
INFINILM_SRC="${INFINILM_SRC:-}"                # optional, defaults resolved later
INFINICORE_BRANCH="${INFINICORE_BRANCH:-}"      # optional git ref (branch/tag/commit)
INFINILM_BRANCH="${INFINILM_BRANCH:-}"          # optional git ref (branch/tag/commit)
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-}"          # optional deployment preset name (deployment/cases/<name>)
INFINICORE_BUILD_CMD="${INFINICORE_BUILD_CMD:-}" # optional command to run in InfiniCore repo before pip install (e.g. "python3 scripts/install.py --metax-gpu=y --ccl=y")

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
        --install-infinicore)
            # auto|true|false
            INSTALL_INFINICORE="$2"
            shift 2
            ;;
        --install-infinilm)
            # auto|true|false
            INSTALL_INFINILM="$2"
            shift 2
            ;;
        --infinicore-src)
            INFINICORE_SRC="$2"
            shift 2
            ;;
        --infinilm-src)
            INFINILM_SRC="$2"
            shift 2
            ;;
        --infinicore-branch)
            INFINICORE_BRANCH="$2"
            shift 2
            ;;
        --infinilm-branch)
            INFINILM_BRANCH="$2"
            shift 2
            ;;
        --deployment-case)
            DEPLOYMENT_CASE="$2"
            shift 2
            ;;
        --infinicore-build-cmd)
            INFINICORE_BUILD_CMD="$2"
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
            echo "  --install-infinicore MODE   auto|true|false (default: auto; env: INSTALL_INFINICORE)"
            echo "  --install-infinilm MODE     auto|true|false (default: auto; env: INSTALL_INFINILM)"
            echo "  --infinicore-src PATH       Path to InfiniCore repo (default: ../InfiniCore; env: INFINICORE_SRC)"
            echo "  --infinilm-src PATH         Path to InfiniLM repo (default: ../InfiniLM; env: INFINILM_SRC)"
            echo "  --infinicore-branch BRANCH  Git branch/tag/commit to checkout in InfiniCore repo (env: INFINICORE_BRANCH)"
            echo "  --infinilm-branch BRANCH    Git branch/tag/commit to checkout in InfiniLM repo (env: INFINILM_BRANCH)"
            echo "  --deployment-case NAME      Deployment case preset name (loads deployment/cases/NAME; env: DEPLOYMENT_CASE)"
            echo "  --infinicore-build-cmd CMD  Command to run in InfiniCore repo before pip install (env: INFINICORE_BUILD_CMD)"
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

load_deployment_case_preset() {
    # Loads deployment/cases/<DEPLOYMENT_CASE>/install.defaults.sh if present.
    # This is used to set install-time defaults and to pick a canonical env-set/config bundle.
    if [ -z "${DEPLOYMENT_CASE:-}" ]; then
        return 0
    fi

    local case_dir="${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}"
    if [ ! -d "${case_dir}" ]; then
        echo -e "${RED}Error: deployment case not found: ${DEPLOYMENT_CASE}${NC}"
        echo "  Expected directory: ${case_dir}"
        echo "  Available cases:"
        ls -1 "${PROJECT_ROOT}/deployment/cases" 2>/dev/null | sed 's/^/    - /' || true
        exit 1
    fi

    local defaults="${case_dir}/install.defaults.sh"
    if [ -f "${defaults}" ]; then
        echo -e "${BLUE}Loading deployment case preset: ${DEPLOYMENT_CASE}${NC}"
        # shellcheck disable=SC1091
        source "${defaults}"
    else
        echo -e "${BLUE}Using deployment case '${DEPLOYMENT_CASE}' (no install.defaults.sh)${NC}"
    fi

    # Optional: also source case env-set for install-time environment if provided.
    if [ -f "${case_dir}/env-set.sh" ]; then
        echo -e "${BLUE}Sourcing deployment case env-set.sh for install-time environment${NC}"
        # shellcheck disable=SC1091
        source "${case_dir}/env-set.sh"
    fi
}

die() {
    echo -e "${RED}Error: $*${NC}"
    exit 1
}

is_true() {
    [ "${1:-}" = "true" ]
}

is_false() {
    [ "${1:-}" = "false" ]
}

should_do() {
    # Interpret auto|true|false into a boolean decision.
    # Usage: should_do "$MODE" "$DEFAULT_BOOL"
    local mode="${1:-auto}"
    local default_bool="${2:-false}"
    if is_true "${mode}"; then
        echo "true"
    elif is_false "${mode}"; then
        echo "false"
    else
        echo "${default_bool}"
    fi
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

# Ensure python3 + pip3 exist (installs if running as root and package manager available)
ensure_python3_pip() {
    if command_exists python3 && command_exists pip3; then
        return 0
    fi

    if [ "$(id -u)" != "0" ]; then
        echo -e "${YELLOW}⚠ Python3/pip3 missing and cannot install without root. Install python3 + pip3 manually.${NC}"
        return 1
    fi

    detect_os
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
            else
                return 1
            fi
            ;;
        *)
            if command_exists apt-get; then
                apt-get update && apt-get install -y python3 python3-pip
            elif command_exists apk; then
                apk add --no-cache python3 py3-pip
            elif command_exists yum; then
                yum install -y python3 python3-pip
            elif command_exists dnf; then
                dnf install -y python3 python3-pip
            else
                return 1
            fi
            ;;
    esac

    command_exists python3 && command_exists pip3
}

pip_install() {
    # Usage: pip_install pkg1 pkg2 ...
    ensure_python3_pip >/dev/null 2>&1 || return 1
    python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel >/dev/null 2>&1 || true
    python3 -m pip install --no-cache-dir "$@"
}

git_checkout_ref_if_requested() {
    # Usage: git_checkout_ref_if_requested /path/to/repo "ref"
    local repo="${1:-}"
    local ref="${2:-}"
    if [ -z "${ref}" ]; then
        return 0
    fi
    if [ -z "${repo}" ] || [ ! -d "${repo}" ]; then
        echo -e "${YELLOW}⚠ Requested git ref '${ref}' but repo path not found: ${repo}${NC}"
        return 0
    fi
    if [ ! -d "${repo}/.git" ]; then
        echo -e "${YELLOW}⚠ Requested git ref '${ref}' but ${repo} is not a git repo (no .git). Skipping checkout.${NC}"
        return 0
    fi
    if ! command_exists git; then
        echo -e "${YELLOW}⚠ Requested git ref '${ref}' but git is not installed. Skipping checkout.${NC}"
        return 0
    fi

    echo "Checking out ${repo} to '${ref}'..."
    (
        cd "${repo}" || exit 1
        # Warn if dirty; still proceed (useful in dev images)
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            echo -e "${YELLOW}⚠ Repo has uncommitted changes; checkout may fail or leave mixed state.${NC}"
        fi
        git fetch --all --tags >/dev/null 2>&1 || true
        git checkout -f "${ref}"
    ) || echo -e "${YELLOW}⚠ Failed to checkout '${ref}' in ${repo}. Continuing with current state.${NC}"
    return 0
}

# Install xmake (needed to build InfiniCore / InfiniLM native modules)
install_xmake() {
    if command_exists xmake; then
        return 0
    fi

    if [ "$(id -u)" != "0" ]; then
        echo -e "${YELLOW}⚠ xmake not found and cannot install without root. Please install xmake manually.${NC}"
        return 1
    fi

    echo -e "${BLUE}Installing xmake...${NC}"
    # Official installer: https://xmake.io/#/guide/installation
    # Non-interactive install to /usr/local (default for root)
    curl -fsSL https://xmake.io/shget.text | bash

    if ! command_exists xmake; then
        echo -e "${YELLOW}⚠ xmake install script ran but xmake is still not in PATH. You may need to restart the shell or adjust PATH.${NC}"
        return 1
    fi
    return 0
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

    ensure_python3_pip || return 0

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

resolve_optional_repo_paths() {
    # Resolve defaults for sibling repos if not provided.
    if [ -z "${INFINICORE_SRC}" ]; then
        if [ -d "${PROJECT_ROOT}/../InfiniCore" ]; then
            INFINICORE_SRC="${PROJECT_ROOT}/../InfiniCore"
        fi
    fi
    if [ -z "${INFINILM_SRC}" ]; then
        if [ -d "${PROJECT_ROOT}/../InfiniLM" ]; then
            INFINILM_SRC="${PROJECT_ROOT}/../InfiniLM"
        fi
    fi
}

install_infinicore_and_infinilm_optional() {
    resolve_optional_repo_paths

    # Decide whether to install (auto => install only if repo path exists and we're root/in-container)
    local default_in_container="false"
    if [ -f "/.dockerenv" ]; then
        default_in_container="true"
    fi

    local do_infinicore
    local do_infinilm
    do_infinicore="$(should_do "${INSTALL_INFINICORE}" "${default_in_container}")"
    do_infinilm="$(should_do "${INSTALL_INFINILM}" "${default_in_container}")"

    if [ "${do_infinicore}" != "true" ] && [ "${do_infinilm}" != "true" ]; then
        return 0
    fi

    # These installs require python + pip, and typically require xmake for native modules.
    echo -e "${BLUE}Installing optional Python backends (InfiniCore/InfiniLM)...${NC}"

    if ! ensure_python3_pip; then
        echo -e "${YELLOW}⚠ Skipping InfiniCore/InfiniLM install (python3/pip3 unavailable).${NC}"
        echo ""
        return 0
    fi

    # Runtime deps for InfiniLM server (FastAPI + uvicorn).
    # Keep this lightweight; users can layer heavier deps (torch, etc.) in their own images.
    if [ "${do_infinilm}" = "true" ]; then
        echo "Installing minimal Python runtime deps for InfiniLM server (fastapi, uvicorn)..."
        pip_install fastapi uvicorn || true
    fi

    # xmake is required for both InfiniCore and InfiniLM setup.py hooks.
    if ! install_xmake; then
        echo -e "${YELLOW}⚠ Skipping InfiniCore/InfiniLM install (xmake unavailable).${NC}"
        echo ""
        return 0
    fi

    # Install InfiniCore (editable) if requested and repo exists.
    if [ "${do_infinicore}" = "true" ]; then
        if [ -z "${INFINICORE_SRC}" ] || [ ! -d "${INFINICORE_SRC}" ]; then
            echo -e "${YELLOW}⚠ INSTALL_INFINICORE=true but InfiniCore repo not found. Set --infinicore-src or place it at ../InfiniCore.${NC}"
        else
            git_checkout_ref_if_requested "${INFINICORE_SRC}" "${INFINICORE_BRANCH}"
            if [ -n "${INFINICORE_BUILD_CMD:-}" ]; then
                echo "Running InfiniCore pre-build command: ${INFINICORE_BUILD_CMD}"
                # Pipe 'yes y' to handle xmake interactive prompts (e.g., package installation confirmations)
                (cd "${INFINICORE_SRC}" && yes y | bash -lc "${INFINICORE_BUILD_CMD}") || \
                    echo -e "${YELLOW}⚠ InfiniCore pre-build command failed; continuing to pip install anyway.${NC}"
            fi
            echo "Installing InfiniCore from ${INFINICORE_SRC} (editable)..."
            python3 -m pip install --no-cache-dir -e "${INFINICORE_SRC}" || \
                echo -e "${YELLOW}⚠ InfiniCore install failed (likely missing toolchain/libs).${NC}"
        fi
    fi

    # Install InfiniLM (editable) if requested and repo exists.
    if [ "${do_infinilm}" = "true" ]; then
        if [ -z "${INFINILM_SRC}" ] || [ ! -d "${INFINILM_SRC}" ]; then
            echo -e "${YELLOW}⚠ INSTALL_INFINILM=true but InfiniLM repo not found. Set --infinilm-src or place it at ../InfiniLM.${NC}"
        else
            git_checkout_ref_if_requested "${INFINILM_SRC}" "${INFINILM_BRANCH}"
            echo "Installing InfiniLM from ${INFINILM_SRC} (editable)..."
            python3 -m pip install --no-cache-dir -e "${INFINILM_SRC}" || \
                echo -e "${YELLOW}⚠ InfiniLM install failed (likely missing toolchain/libs).${NC}"
        fi
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

            # Stage deployment-case preset files (env + config) for runtime.
            # Canonical runtime env location: /app/env-set.sh
            if [ -n "${DEPLOYMENT_CASE:-}" ] && [ -f "${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/env-set.sh" ]; then
                cp "${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/env-set.sh" "${APP_ROOT}/env-set.sh"
                chmod +x "${APP_ROOT}/env-set.sh" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged env-set.sh (case ${DEPLOYMENT_CASE}): ${APP_ROOT}/env-set.sh"
            elif [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
                cp "${PROJECT_ROOT}/env-set.sh" "${APP_ROOT}/env-set.sh"
                chmod +x "${APP_ROOT}/env-set.sh" 2>/dev/null || true
                echo -e "  ${GREEN}✓${NC} Staged env-set.sh: ${APP_ROOT}/env-set.sh"
            fi

            if [ -n "${DEPLOYMENT_CASE:-}" ] && [ -d "${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/config" ]; then
                mkdir -p "${APP_ROOT}/config/cases/${DEPLOYMENT_CASE}"
                cp -a "${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/config/." "${APP_ROOT}/config/cases/${DEPLOYMENT_CASE}/"
                echo -e "  ${GREEN}✓${NC} Staged deployment case configs: ${APP_ROOT}/config/cases/${DEPLOYMENT_CASE}/"
            fi
        fi
    fi

    echo -e "${GREEN}✓ Setup complete${NC}"
    echo ""
}

# Main installation flow
main() {
    # Load deployment-case defaults early so it can influence installation behavior.
    load_deployment_case_preset
    install_system_deps
    install_rust
    build_binaries
    install_binaries
    install_python_deps
    install_infinicore_and_infinilm_optional
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
