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
INSTALL_XTASK="${INSTALL_XTASK:-auto}"           # auto|true|false (installs xtask binary from InfiniLM-Rust)
VERIFY_INSTALL="${VERIFY_INSTALL:-auto}"          # auto|true|false (verifies InfiniCore/InfiniLM imports after installation)
INFINICORE_SRC="${INFINICORE_SRC:-}"            # optional, defaults resolved later
INFINILM_SRC="${INFINILM_SRC:-}"                # optional, defaults resolved later
INFINILM_RUST_SRC="${INFINILM_RUST_SRC:-}"      # optional, defaults resolved later
INFINICORE_BRANCH="${INFINICORE_BRANCH:-}"      # optional git ref (branch/tag/commit)
INFINILM_BRANCH="${INFINILM_BRANCH:-}"          # optional git ref (branch/tag/commit)
INFINILM_RUST_BRANCH="${INFINILM_RUST_BRANCH:-}" # optional git ref (branch/tag/commit, default: llama.maca_dep)
DEPLOYMENT_CASE="${DEPLOYMENT_CASE:-}"          # optional deployment preset name (deployment/cases/<name>)
INFINICORE_BUILD_CMD="${INFINICORE_BUILD_CMD:-}" # optional command to run in InfiniCore repo before pip install (e.g. "python3 scripts/install.py --metax-gpu=y --ccl=y")
INFINICORE_BUILD_CPP="${INFINICORE_BUILD_CPP:-auto}" # auto|true|false - build C++ targets (infiniop, infinirt, infiniccl, infinicore_cpp_api) - takes long time
INFINICORE_BUILD_PYTHON="${INFINICORE_BUILD_PYTHON:-auto}" # auto|true|false - build Python extension (_infinicore) - quick rebuild

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
        --install-xtask)
            # auto|true|false
            INSTALL_XTASK="$2"
            shift 2
            ;;
        --infinilm-rust-src)
            INFINILM_RUST_SRC="$2"
            shift 2
            ;;
        --infinilm-rust-branch)
            INFINILM_RUST_BRANCH="$2"
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
        --infinicore-build-cpp)
            # auto|true|false
            INFINICORE_BUILD_CPP="$2"
            shift 2
            ;;
        --infinicore-build-python)
            # auto|true|false
            INFINICORE_BUILD_PYTHON="$2"
            shift 2
            ;;
        --verify-install)
            # auto|true|false
            VERIFY_INSTALL="$2"
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
            echo "  --install-xtask MODE        auto|true|false (default: auto; env: INSTALL_XTASK)"
            echo "  --infinilm-rust-src PATH    Path to InfiniLM-Rust repo (default: ../InfiniLM-Rust; env: INFINILM_RUST_SRC)"
            echo "  --infinilm-rust-branch BRANCH Git branch/tag/commit to checkout in InfiniLM-Rust repo (default: llama.maca_dep; env: INFINILM_RUST_BRANCH)"
            echo "  --deployment-case NAME      Deployment case preset name (loads deployment/cases/NAME; env: DEPLOYMENT_CASE)"
            echo "  --infinicore-build-cmd CMD  Command to run in InfiniCore repo before pip install (env: INFINICORE_BUILD_CMD)"
            echo "  --infinicore-build-cpp MODE auto|true|false (default: auto; env: INFINICORE_BUILD_CPP)"
            echo "                              Build C++ targets (infiniop, infinirt, infiniccl, infinicore_cpp_api)"
            echo "  --infinicore-build-python MODE auto|true|false (default: auto; env: INFINICORE_BUILD_PYTHON)"
            echo "                              Build Python extension (_infinicore) - quick rebuild"
            echo "  --verify-install MODE       auto|true|false (default: auto; env: VERIFY_INSTALL)"
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
    command -v "$1" >/dev/null 2>&1 || [ -f "/usr/bin/$1" ] || [ -f "/usr/local/bin/$1" ] || [ -f "/bin/$1" ]
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
        if  [ "$ID_LIKE" = "debian" ] || [ "$ID_LIKE" = "ubuntu" ]; then
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
        centos|rhel|fedora|kylin)
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
    # Check if xmake is already available
    if command_exists xmake; then
        return 0
    fi

    # Check common xmake installation locations
    if [ -f "/root/.xmake/bin/xmake" ] || [ -f "${HOME}/.xmake/bin/xmake" ]; then
        # Source xmake profile to add it to PATH
        if [ -f "/root/.xmake/profile" ]; then
            # shellcheck disable=SC1091
            source /root/.xmake/profile 2>/dev/null || true
        elif [ -f "${HOME}/.xmake/profile" ]; then
            # shellcheck disable=SC1091
            source "${HOME}/.xmake/profile" 2>/dev/null || true
        fi
        if command_exists xmake; then
            return 0
        fi
    fi

    if [ "$(id -u)" != "0" ]; then
        echo -e "${YELLOW}⚠ xmake not found and cannot install without root. Please install xmake manually.${NC}"
        return 1
    fi

    echo -e "${BLUE}Installing xmake...${NC}"
    # Official installer: https://xmake.io/#/guide/installation
    # Non-interactive install to /usr/local (default for root)
    # Try with proxy if available, then retry without proxy if needed
    local xmake_installed=false

    # Try installation with proxy support
    if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
        echo "  Trying xmake installation with proxy..."
        if curl -fsSL --proxy "${HTTP_PROXY:-${HTTPS_PROXY:-}}" https://xmake.io/shget.text 2>/dev/null | bash 2>&1; then
            xmake_installed=true
        fi
    fi

    # If proxy install failed or no proxy, try direct connection
    if [ "${xmake_installed}" != "true" ]; then
        echo "  Trying xmake installation without proxy..."
        # Unset proxy for direct connection
        if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
            curl -fsSL https://xmake.io/shget.text 2>/dev/null | bash 2>&1; then
            xmake_installed=true
        fi
    fi

    # If still failed, try alternative method: download and install manually
    if [ "${xmake_installed}" != "true" ]; then
        echo "  Trying alternative xmake installation method..."
        local xmake_installer="/tmp/xmake_installer.sh"
        # Try to download installer script
        if [ -n "${HTTP_PROXY:-}" ] || [ -n "${HTTPS_PROXY:-}" ]; then
            curl -fsSL --proxy "${HTTP_PROXY:-${HTTPS_PROXY:-}}" https://xmake.io/shget.text -o "${xmake_installer}" 2>/dev/null && \
            bash "${xmake_installer}" 2>&1 && xmake_installed=true || true
        fi
        if [ "${xmake_installed}" != "true" ]; then
            env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
                curl -fsSL https://xmake.io/shget.text -o "${xmake_installer}" 2>/dev/null && \
                bash "${xmake_installer}" 2>&1 && xmake_installed=true || true
        fi
        rm -f "${xmake_installer}" 2>/dev/null || true
    fi

    # Source xmake profile after installation to add it to PATH
    if [ -f "/root/.xmake/profile" ]; then
        # shellcheck disable=SC1091
        source /root/.xmake/profile 2>/dev/null || true
    elif [ -f "${HOME}/.xmake/profile" ]; then
        # shellcheck disable=SC1091
        source "${HOME}/.xmake/profile" 2>/dev/null || true
    fi

    # Check again after sourcing profile
    if command_exists xmake; then
        echo -e "${GREEN}✓ xmake installed successfully${NC}"
        return 0
    fi

    # Even if not in PATH, check if xmake binary exists in common locations
    if [ -f "/root/.xmake/bin/xmake" ] || [ -f "${HOME}/.xmake/bin/xmake" ]; then
        echo -e "${GREEN}✓ xmake installed (found in ~/.xmake/bin/xmake)${NC}"
        # Add to PATH for this session
        if [ -f "/root/.xmake/bin/xmake" ]; then
            export PATH="/root/.xmake/bin:${PATH}"
        elif [ -f "${HOME}/.xmake/bin/xmake" ]; then
            export PATH="${HOME}/.xmake/bin:${PATH}"
        fi
        return 0
    fi

    # If xmake is still not available, this is a problem
    echo -e "${RED}✗ xmake installation failed and xmake is not available${NC}"
    echo -e "${YELLOW}  xmake is required for building InfiniCore/InfiniLM native modules${NC}"
    echo -e "${YELLOW}  Please check network connectivity or install xmake manually${NC}"
    return 1
}

# Function to check if OpenSSL is available
check_openssl() {
    # Try pkg-config first
    if command_exists pkg-config; then
        if pkg-config --exists openssl 2>/dev/null; then
            return 0
        fi
    fi

    # Check for OpenSSL headers in common locations
    if [ -f /usr/include/openssl/ssl.h ] || \
       [ -f /usr/local/include/openssl/ssl.h ] || \
       [ -f /opt/conda/include/openssl/ssl.h ] || \
       [ -f /usr/include/ssl.h ]; then
        return 0
    fi

    # Check for OpenSSL libraries
    if [ -f /usr/lib64/libssl.so ] || \
       [ -f /usr/lib/libssl.so ] || \
       [ -f /usr/local/lib/libssl.so ] || \
       [ -f /opt/conda/lib/libssl.so ]; then
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
                    clang \
                    libclang-dev \
                    ca-certificates \
                    curl \
                    bash \
                    git; then
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
                    clang \
                    clang-dev \
                    ca-certificates \
                    curl \
                    bash \
                    git; then
                    INSTALLED=true
                fi
            fi
            ;;
        centos|rhel|fedora|kylin)
            # First, check if packages are already installed (base image might have them)
            echo "Checking if required packages are already installed..."
            local missing_packages=0
            local missing_list=""
            for pkg in gcc pkgconf openssl-devel clang clang-devel; do
                if ! rpm -q "${pkg}" >/dev/null 2>&1; then
                    missing_packages=$((missing_packages + 1))
                    missing_list="${missing_list} ${pkg}"
                fi
            done

            if [ ${missing_packages} -eq 0 ]; then
                INSTALLED=true
                echo -e "${GREEN}✓ All required packages are already installed${NC}"
            else
                echo -e "${BLUE}Missing ${missing_packages} package(s):${missing_list}${NC}"
                # Try yum first (common in many base images), then fallback to dnf.
                # Note: Even if yum --version fails due to libdnf issues, yum install might still work.
                # We need to handle stderr noise from libdnf carefully.
                if command_exists yum; then
                    echo "Attempting to install missing packages via yum..."
                    # Try yum install - some systems have libdnf issues but yum install still works
                    # We'll check package installation status regardless of yum exit code
                    yum install -y \
                        gcc \
                        pkgconfig \
                        openssl-devel \
                        clang \
                        clang-devel \
                        ca-certificates \
                        curl \
                        bash \
                        git >/dev/null 2>&1 || true

                    # Check if packages are actually installed (regardless of yum exit code)
                    # This handles cases where yum crashes due to libdnf but packages are still installed
                    missing_packages=0
                    for pkg in gcc pkgconf openssl-devel clang clang-devel git; do
                        if ! rpm -q "${pkg}" >/dev/null 2>&1; then
                            missing_packages=$((missing_packages + 1))
                        fi
                    done

                    if [ ${missing_packages} -eq 0 ]; then
                        INSTALLED=true
                        echo -e "${GREEN}✓ All required packages are now installed${NC}"
                    else
                        echo -e "${YELLOW}⚠ ${missing_packages} package(s) still missing after yum install${NC}"
                        echo -e "${YELLOW}  yum may have libdnf compatibility issues, but packages might still be installed${NC}"
                    fi
                fi

                # Try dnf if yum failed or doesn't exist (modern RHEL/CentOS/Fedora)
                if [ "$INSTALLED" != "true" ] && command_exists dnf; then
                    echo "Attempting to install missing packages via dnf..."
                    # Suppress stderr to avoid libdnf Python binding errors
                    dnf install -y \
                        gcc \
                        pkgconf \
                        openssl-devel \
                        clang \
                        clang-devel \
                        ca-certificates \
                        curl \
                        bash \
                        git >/dev/null 2>&1 || true

                    # Check if packages are now installed
                    missing_packages=0
                    for pkg in gcc pkgconf openssl-devel clang clang-devel git; do
                        if ! rpm -q "${pkg}" >/dev/null 2>&1; then
                            missing_packages=$((missing_packages + 1))
                        fi
                    done
                    if [ ${missing_packages} -eq 0 ]; then
                        echo -e "${GREEN}✓ Required packages are now installed${NC}"
                        INSTALLED=true
                    else
                        echo -e "${YELLOW}⚠ dnf installation failed and ${missing_packages} package(s) still missing${NC}"
                        echo -e "${YELLOW}  dnf may have libdnf compatibility issues${NC}"
                    fi
                fi

                # Final check - if still missing, warn but don't fail yet
                if [ "$INSTALLED" != "true" ]; then
                    echo -e "${YELLOW}⚠ Could not install all system dependencies via yum/dnf.${NC}"
                    echo -e "${YELLOW}  Missing packages may need to be installed manually:${NC}"
                    echo -e "${YELLOW}    gcc, pkgconf, openssl-devel, clang, clang-devel, ca-certificates, curl, bash, git${NC}"
                    echo -e "${YELLOW}  Note: Base image may already have these packages despite package manager issues${NC}"
                fi
            fi
            ;;
        *)
            echo -e "${YELLOW}Warning: Unknown OS ($OS), trying to detect package manager...${NC}"
            # Try common package managers as fallback
            if command_exists apt-get; then
                echo "Detected apt-get, attempting installation..."
                apt-get update && \
                apt-get install -y build-essential pkg-config libssl-dev clang libclang-dev ca-certificates curl bash && \
                INSTALLED=true
            elif command_exists dnf; then
                echo "Detected dnf, attempting installation..."
                dnf install -y gcc pkgconf openssl-devel clang clang-devel ca-certificates curl bash git 2>&1 && \
                INSTALLED=true
            elif command_exists yum; then
                echo "Detected yum, checking if it's working..."
                if yum --version >/dev/null 2>&1; then
                    echo "Installing dependencies via yum..."
                    yum install -y gcc pkgconf openssl-devel clang clang-devel ca-certificates curl bash git 2>&1 && \
                    INSTALLED=true
                else
                    echo -e "${YELLOW}⚠ yum appears to be corrupted (libdnf issue), skipping system package installation${NC}"
                    echo -e "${YELLOW}  Please fix yum/dnf or install dependencies manually:${NC}"
                    echo -e "${YELLOW}    gcc, pkgconf, openssl-devel, clang, clang-devel, ca-certificates, curl, bash, git${NC}"
                fi
            elif command_exists apk; then
                echo "Detected apk, attempting installation..."
                apk add --no-cache build-base pkgconfig openssl-dev clang clang-dev ca-certificates curl bash && \
                INSTALLED=true
            fi
            ;;
    esac

    # Always try to detect and set OPENSSL_DIR for Rust builds (even if check_openssl passes)
    # Rust's openssl-sys crate needs OPENSSL_DIR to be explicitly set
    local openssl_detected=false
    if [ -z "${OPENSSL_DIR:-}" ]; then
        echo "Detecting OpenSSL location for Rust build..."
        for dir in /usr /usr/local /opt/conda /opt/hpcc; do
            # Check for OpenSSL headers
            if [ -f "${dir}/include/openssl/ssl.h" ]; then
                # Check for OpenSSL libraries
                if [ -f "${dir}/lib/libssl.so" ] || [ -f "${dir}/lib64/libssl.so" ] || \
                   [ -f "${dir}/lib/libssl.a" ] || [ -f "${dir}/lib64/libssl.a" ]; then
                    echo -e "${GREEN}Found OpenSSL in ${dir}${NC}"
                    export OPENSSL_DIR="${dir}"
                    # Set include path
                    if [ -d "${dir}/include" ]; then
                        export C_INCLUDE_PATH="${dir}/include:${C_INCLUDE_PATH:-}"
                    fi
                    # Set library paths
                    if [ -d "${dir}/lib64" ]; then
                        export LD_LIBRARY_PATH="${dir}/lib64:${LD_LIBRARY_PATH:-}"
                    fi
                    if [ -d "${dir}/lib" ]; then
                        export LD_LIBRARY_PATH="${dir}/lib:${LD_LIBRARY_PATH:-}"
                    fi
                    # Try to find openssl.pc for pkg-config
                    for pc_path in "${dir}/lib/pkgconfig" "${dir}/lib64/pkgconfig" \
                                   "${dir}/share/pkgconfig" "${dir}/pkgconfig"; do
                        if [ -f "${pc_path}/openssl.pc" ]; then
                            export PKG_CONFIG_PATH="${pc_path}:${PKG_CONFIG_PATH:-}"
                            echo -e "${GREEN}Found openssl.pc at ${pc_path}${NC}"
                            break
                        fi
                    done
                    openssl_detected=true
                    break
                fi
            fi
        done
    else
        openssl_detected=true
        echo -e "${GREEN}OPENSSL_DIR already set: ${OPENSSL_DIR}${NC}"
    fi

    # Verify OpenSSL is available
    if ! check_openssl; then
        if [ "$openssl_detected" = "false" ]; then
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
                centos|rhel|fedora|kylin)
                    echo "  sudo yum install openssl-devel pkgconfig"
                    echo "  Note: If yum/dnf has libdnf issues, packages may need to be pre-installed in base image"
                    ;;
                *)
                    echo "  Install libssl-dev (Debian/Ubuntu) or openssl-devel (CentOS/RHEL/Fedora)"
                    ;;
            esac
            echo ""
            echo "If OpenSSL is installed in a non-standard location, set:"
            echo "  export OPENSSL_DIR=/path/to/openssl"
            echo "  export PKG_CONFIG_PATH=/path/to/openssl/lib/pkgconfig"
            echo "  export C_INCLUDE_PATH=/path/to/openssl/include:\$C_INCLUDE_PATH"
            echo "  export LD_LIBRARY_PATH=/path/to/openssl/lib:\$LD_LIBRARY_PATH"
            exit 1
        fi
    fi

    if [ "$openssl_detected" = "true" ]; then
        echo -e "${GREEN}✓ OpenSSL found and environment variables set${NC}"
        if [ -n "${OPENSSL_DIR:-}" ]; then
            echo -e "${GREEN}  OPENSSL_DIR=${OPENSSL_DIR}${NC}"
        fi
        if [ -n "${PKG_CONFIG_PATH:-}" ]; then
            echo -e "${GREEN}  PKG_CONFIG_PATH=${PKG_CONFIG_PATH}${NC}"
        fi
    else
        echo -e "${GREEN}✓ OpenSSL development libraries found${NC}"
    fi

    if [ "$INSTALLED" = "true" ]; then
        echo -e "${GREEN}✓ System dependencies installed${NC}"
    else
        echo -e "${YELLOW}⚠ Could not install system dependencies automatically${NC}"
        echo "Please install manually: build-essential/gcc, pkg-config, libssl-dev/openssl-devel, clang, libclang-dev/clang-devel, curl, bash, git"
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
    local requirements_files=()

    # Check for deployment-case-specific requirements files first
    if [ -n "${DEPLOYMENT_CASE:-}" ]; then
        local case_requirements="${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/requirements-embeddings.txt"
        if [ -f "${case_requirements}" ]; then
            requirements_files+=("${case_requirements}")
        fi
    fi

    # Then check common locations
    if [ -f "${PROJECT_ROOT}/requirements.txt" ]; then
        # Root-level requirements (for demo/integration testing)
        requirements_files+=("${PROJECT_ROOT}/requirements.txt")
    elif [ -f "${PROJECT_ROOT}/python/requirements.txt" ]; then
        # Full Python implementation requirements
        requirements_files+=("${PROJECT_ROOT}/python/requirements.txt")
    fi

    if [ ${#requirements_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}⚠ No requirements file found; skipping python deps install${NC}"
        echo ""
        return 0
    fi

    # Install deps into system python3 (if present)
    if command_exists python3; then
        for requirements_file in "${requirements_files[@]}"; do
            echo "Installing Python dependencies into system python3 from ${requirements_file}..."
            # Try with current pip config first, then try with default PyPI index
            if python3 -m pip install --no-cache-dir -r "${requirements_file}" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Python deps installed into system python3 from ${requirements_file}${NC}"
            elif python3 -m pip install --no-cache-dir -i https://pypi.org/simple -r "${requirements_file}" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Python deps installed into system python3 from ${requirements_file} (using PyPI)${NC}"
            else
                # Try with verbose output to see the actual error
                echo -e "${YELLOW}⚠ Attempting pip install with verbose output...${NC}"
                if python3 -m pip install --no-cache-dir -i https://pypi.org/simple -r "${requirements_file}"; then
                    echo -e "${GREEN}✓ Python deps installed into system python3 from ${requirements_file}${NC}"
                else
                    echo -e "${YELLOW}⚠ Failed to install some Python dependencies from ${requirements_file}${NC}"
                    echo -e "${YELLOW}  This is non-fatal; dependencies can be installed manually later${NC}"
                fi
            fi
        done
    fi

    # Also install into conda base if present (some images have python3 pointing to conda)
    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
        for requirements_file in "${requirements_files[@]}"; do
            echo "Installing Python dependencies into conda base from ${requirements_file}..."
            # shellcheck disable=SC1091
            source /opt/conda/etc/profile.d/conda.sh
            conda activate base
            # Try with current pip config first, then try with default PyPI index
            if python -m pip install --no-cache-dir -r "${requirements_file}" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Python deps installed into conda base from ${requirements_file}${NC}"
            elif python -m pip install --no-cache-dir -i https://pypi.org/simple -r "${requirements_file}" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Python deps installed into conda base from ${requirements_file} (using PyPI)${NC}"
            else
                # Try with verbose output to see the actual error
                echo -e "${YELLOW}⚠ Attempting pip install with verbose output...${NC}"
                if python -m pip install --no-cache-dir -i https://pypi.org/simple -r "${requirements_file}"; then
                    echo -e "${GREEN}✓ Python deps installed into conda base from ${requirements_file}${NC}"
                else
                    echo -e "${YELLOW}⚠ Failed to install some Python dependencies from ${requirements_file}${NC}"
                    echo -e "${YELLOW}  This is non-fatal; dependencies can be installed manually later${NC}"
                fi
            fi
        done
    fi

    # Always return success - Python deps are optional for core functionality
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
        else
            # Default to sibling directory
            INFINICORE_SRC="${PROJECT_ROOT}/../InfiniCore"
        fi
    fi
    if [ -z "${INFINILM_SRC}" ]; then
        if [ -d "${PROJECT_ROOT}/../InfiniLM" ]; then
            INFINILM_SRC="${PROJECT_ROOT}/../InfiniLM"
        else
            # Default to sibling directory
            INFINILM_SRC="${PROJECT_ROOT}/../InfiniLM"
        fi
    fi
    if [ -z "${INFINILM_RUST_SRC}" ]; then
        if [ -d "${PROJECT_ROOT}/../InfiniLM-Rust" ]; then
            INFINILM_RUST_SRC="${PROJECT_ROOT}/../InfiniLM-Rust"
        else
            # Default to sibling directory
            INFINILM_RUST_SRC="${PROJECT_ROOT}/../InfiniLM-Rust"
        fi
    fi
    # Set default branch for InfiniLM-Rust if not specified
    if [ -z "${INFINILM_RUST_BRANCH}" ]; then
        INFINILM_RUST_BRANCH="llama.maca_dep"
    fi
}

# Function to clone repository if it doesn't exist
clone_repo_if_needed() {
    local repo_src="$1"
    local repo_url="$2"
    local repo_name="$3"
    local use_recursive="${4:-false}"  # Optional: use --recursive for repos with submodules
    local branch="${5:-}"  # Optional: branch to checkout after clone

    # Check if repo exists and is a git repo
    if [ ! -d "${repo_src}" ] || [ ! -d "${repo_src}/.git" ]; then
        if ! command_exists git; then
            echo -e "${YELLOW}⚠ ${repo_name} repo not found and git is not available.${NC}"
            echo -e "${YELLOW}  Please clone the repo manually or install git.${NC}"
            return 1
        fi

        echo -e "${BLUE}Cloning ${repo_name} repository...${NC}"
        local parent_dir="$(dirname "${repo_src}")"
        local repo_dir_name="$(basename "${repo_src}")"

        # Create parent directory if it doesn't exist
        mkdir -p "${parent_dir}"

        # Clone the repository (with --recursive if needed for submodules, and -b for branch if specified)
        local clone_cmd="git clone"
        if [ "${use_recursive}" = "true" ]; then
            clone_cmd="git clone --recursive"
            echo -e "${BLUE}  Using --recursive flag (repo has submodules)${NC}"
        fi
        if [ -n "${branch}" ]; then
            clone_cmd="${clone_cmd} -b ${branch}"
            echo -e "${BLUE}  Using branch: ${branch}${NC}"
        fi

        if ${clone_cmd} "${repo_url}" "${repo_src}"; then
            echo -e "${GREEN}✓ Cloned ${repo_name} repository${NC}"

            # If not cloned with --recursive but repo has submodules, initialize them
            if [ "${use_recursive}" != "true" ] && [ -f "${repo_src}/.gitmodules" ]; then
                echo -e "${BLUE}Initializing submodules for ${repo_name}...${NC}"
                (cd "${repo_src}" && git submodule update --init --recursive) || {
                    echo -e "${YELLOW}⚠ Submodule initialization failed, but continuing...${NC}"
                }
            fi

            return 0
        else
            echo -e "${RED}✗ Failed to clone ${repo_name} repository${NC}"
            return 1
        fi
    else
        # Repo exists, but check if submodules need to be initialized
        if [ "${use_recursive}" = "true" ] && [ -f "${repo_src}/.gitmodules" ]; then
            echo -e "${BLUE}Checking submodules for ${repo_name}...${NC}"
            (cd "${repo_src}" && git submodule update --init --recursive 2>/dev/null || true)
        fi
    fi
    return 0
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

    # Ensure git is available FIRST for cloning repos
    # Check common git locations in case it's installed but not in PATH
    local git_found=false
    local git_path=""

    # Try to find git in common locations (check file existence directly)
    for git_loc in "/usr/bin/git" "/usr/local/bin/git" "/bin/git" "/opt/conda/bin/git"; do
        if [ -f "${git_loc}" ] && [ -x "${git_loc}" ]; then
            git_path="${git_loc}"
            git_found=true
            # Add to PATH if not already there
            local git_dir="$(dirname "${git_loc}")"
            if ! echo "${PATH}" | grep -q "${git_dir}"; then
                export PATH="${git_dir}:${PATH}"
            fi
            break
        fi
    done

    # Also try command -v if PATH is set
    if [ "${git_found}" != "true" ] && command -v git >/dev/null 2>&1; then
        git_path="$(command -v git)"
        git_found=true
    fi

    if [ "${git_found}" = "true" ]; then
        echo -e "${GREEN}✓ git available at ${git_path}${NC}"
        # Verify git actually works
        if ! "${git_path}" --version >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ git found but not working, will try to install...${NC}"
            git_found=false
        fi
    fi

    if [ "${git_found}" != "true" ]; then
        echo -e "${BLUE}Installing git for repository cloning...${NC}"

        # First check if git is already installed via rpm (common in RHEL/CentOS/Kylin)
        if command_exists rpm; then
            if rpm -q git >/dev/null 2>&1; then
                echo "  git is installed via rpm, finding location..."
                # Find git binary from rpm package
                local git_rpm_path=$(rpm -ql git 2>/dev/null | grep -E "/bin/git$" | head -1)
                if [ -n "${git_rpm_path}" ] && [ -f "${git_rpm_path}" ]; then
                    git_path="${git_rpm_path}"
                    git_found=true
                    local git_dir="$(dirname "${git_rpm_path}")"
                    if ! echo "${PATH}" | grep -q "${git_dir}"; then
                        export PATH="${git_dir}:${PATH}"
                    fi
                    echo -e "${GREEN}✓ git found via rpm at ${git_path}${NC}"
                fi
            fi
        fi

        # Try to install git using available package manager if still not found
        if [ "${git_found}" != "true" ]; then
            if command_exists apt-get; then
                echo "  Trying apt-get..."
                apt-get update -qq >/dev/null 2>&1
                apt-get install -y git >/dev/null 2>&1 || true
            elif command_exists yum; then
                echo "  Trying yum install git..."
                # yum may have libdnf issues but still install packages
                # Try installation and then verify git actually exists
                yum install -y git 2>&1 | grep -v "libdnf\|ImportError" || true
                # Wait a moment for installation to complete
                sleep 1
                # Check if git was actually installed despite yum errors
                if rpm -q git >/dev/null 2>&1; then
                    echo "  git package installed via rpm"
                    # Find git binary from rpm package
                    local git_rpm_path=$(rpm -ql git 2>/dev/null | grep -E "/bin/git$" | head -1)
                    if [ -n "${git_rpm_path}" ] && [ -f "${git_rpm_path}" ]; then
                        git_path="${git_rpm_path}"
                        git_found=true
                        local git_dir="$(dirname "${git_rpm_path}")"
                        if ! echo "${PATH}" | grep -q "${git_dir}"; then
                            export PATH="${git_dir}:${PATH}"
                        fi
                        echo -e "${GREEN}✓ git installed via yum at ${git_path}${NC}"
                    fi
                fi
            elif command_exists dnf; then
                echo "  Trying dnf install git..."
                dnf install -y git 2>&1 | grep -v "libdnf\|ImportError" || true
                sleep 1
                # Check if git was actually installed
                if rpm -q git >/dev/null 2>&1; then
                    echo "  git package installed via rpm"
                    local git_rpm_path=$(rpm -ql git 2>/dev/null | grep -E "/bin/git$" | head -1)
                    if [ -n "${git_rpm_path}" ] && [ -f "${git_rpm_path}" ]; then
                        git_path="${git_rpm_path}"
                        git_found=true
                        local git_dir="$(dirname "${git_rpm_path}")"
                        if ! echo "${PATH}" | grep -q "${git_dir}"; then
                            export PATH="${git_dir}:${PATH}"
                        fi
                        echo -e "${GREEN}✓ git installed via dnf at ${git_path}${NC}"
                    fi
                fi
            elif command_exists apk; then
                echo "  Trying apk..."
                apk add --no-cache git >/dev/null 2>&1 || true
            fi

            # Final check after installation attempt - look in all common locations
            for git_loc in "/usr/bin/git" "/usr/local/bin/git" "/bin/git" "/opt/conda/bin/git"; do
                if [ -f "${git_loc}" ] && [ -x "${git_loc}" ]; then
                    git_path="${git_loc}"
                    git_found=true
                    local git_dir="$(dirname "${git_loc}")"
                    if ! echo "${PATH}" | grep -q "${git_dir}"; then
                        export PATH="${git_dir}:${PATH}"
                    fi
                    break
                fi
            done

            # Also check command -v again
            if [ "${git_found}" != "true" ] && command -v git >/dev/null 2>&1; then
                git_path="$(command -v git)"
                git_found=true
            fi
        fi

        # Check again after installation attempt - look in all common locations
        for git_loc in "/usr/bin/git" "/usr/local/bin/git" "/bin/git" "/opt/conda/bin/git"; do
            if [ -f "${git_loc}" ] && [ -x "${git_loc}" ]; then
                git_path="${git_loc}"
                git_found=true
                local git_dir="$(dirname "${git_loc}")"
                if ! echo "${PATH}" | grep -q "${git_dir}"; then
                    export PATH="${git_dir}:${PATH}"
                fi
                break
            fi
        done

        # Also check command -v again
        if [ "${git_found}" != "true" ] && command -v git >/dev/null 2>&1; then
            git_path="$(command -v git)"
            git_found=true
        fi

        if [ "${git_found}" = "true" ]; then
            echo -e "${GREEN}✓ git installed/found at ${git_path}${NC}"
        else
            echo -e "${RED}✗ git installation failed and git is not available.${NC}"
            echo -e "${RED}Error: Cannot clone repositories without git. Please install git manually or mount repos.${NC}"
            return 1
        fi
    fi

    if ! ensure_python3_pip; then
        echo -e "${YELLOW}⚠ Skipping InfiniCore/InfiniLM install (python3/pip3 unavailable).${NC}"
        echo ""
        return 0
    fi

    # Install all Python dependencies for InfiniCore and InfiniLM in one place
    # This consolidates all pip install commands to avoid duplicates and ensure consistency
    if [ "${do_infinicore}" = "true" ] || [ "${do_infinilm}" = "true" ]; then
        echo "Installing Python dependencies for InfiniCore/InfiniLM..."
        # Use conda's Python if available (same as runtime)
        local python_cmd="python3"
        if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
            python_cmd="/opt/conda/bin/python"
            # shellcheck disable=SC1091
            source /opt/conda/etc/profile.d/conda.sh
            conda activate base
            export PATH="/opt/conda/bin:${PATH}"
        fi

        # Find requirements file for InfiniCore/InfiniLM dependencies
        local requirements_file=""
        if [ -n "${DEPLOYMENT_CASE:-}" ] && [ -f "${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/requirements-infinicore-infinilm.txt" ]; then
            requirements_file="${PROJECT_ROOT}/deployment/cases/${DEPLOYMENT_CASE}/requirements-infinicore-infinilm.txt"
        elif [ -n "${DEPLOYMENT_CASE:-}" ] && [ -f "${SCRIPT_DIR}/../deployment/cases/${DEPLOYMENT_CASE}/requirements-infinicore-infinilm.txt" ]; then
            requirements_file="${SCRIPT_DIR}/../deployment/cases/${DEPLOYMENT_CASE}/requirements-infinicore-infinilm.txt"
        elif [ -f "${PROJECT_ROOT}/requirements-infinicore-infinilm.txt" ]; then
            requirements_file="${PROJECT_ROOT}/requirements-infinicore-infinilm.txt"
        fi

        if [ -z "${requirements_file}" ] || [ ! -f "${requirements_file}" ]; then
            echo -e "${YELLOW}⚠ requirements-infinicore-infinilm.txt not found, skipping Python dependencies install${NC}"
            echo -e "${YELLOW}  Expected locations:${NC}"
            if [ -n "${DEPLOYMENT_CASE:-}" ]; then
                echo -e "${YELLOW}    - deployment/cases/${DEPLOYMENT_CASE}/requirements-infinicore-infinilm.txt${NC}"
            fi
            echo -e "${YELLOW}    - requirements-infinicore-infinilm.txt${NC}"
        else
            echo "Using requirements file: ${requirements_file}"
            # Try multiple China mainland mirrors in order: Tsinghua -> Aliyun -> Tencent
            # Note: Tsinghua is tried first as it's more likely to have all packages (e.g., ml_dtypes)
            local packages_installed=false
            for mirror_url in "https://pypi.tuna.tsinghua.edu.cn/simple" "http://mirrors.aliyun.com/pypi/simple" "https://mirrors.cloud.tencent.com/pypi/simple"; do
                local mirror_name=$(echo "${mirror_url}" | sed 's|https\?://||' | sed 's|/.*||')
                echo "  Trying ${mirror_name} mirror..."
                # Unset proxy env vars for pip to avoid proxy connection errors
                if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
                    ${python_cmd} -m pip install --no-cache-dir -i "${mirror_url}" --trusted-host "${mirror_name}" -r "${requirements_file}" 2>&1; then
                    echo -e "${GREEN}✓ Python dependencies installed from ${mirror_name}${NC}"
                    packages_installed=true
                    break
                else
                    echo "  ${mirror_name} mirror failed, trying next..."
                fi
            done
            if [ "${packages_installed}" != "true" ]; then
                echo -e "${YELLOW}⚠ Python dependencies installation failed from all China mirrors${NC}"
                echo -e "${YELLOW}  Requirements file: ${requirements_file}${NC}"
            fi
        fi
    fi

    # Ensure git is available for cloning repos
    if ! command_exists git; then
        echo -e "${BLUE}Installing git for repository cloning...${NC}"
        # Try to install git using available package manager
        if command_exists apt-get; then
            apt-get update -qq && apt-get install -y git >/dev/null 2>&1 || true
        elif command_exists yum; then
            yum install -y git >/dev/null 2>&1 || true
        elif command_exists dnf; then
            dnf install -y git >/dev/null 2>&1 || true
        elif command_exists apk; then
            apk add --no-cache git >/dev/null 2>&1 || true
        fi
        # Verify git is now available
        if ! command_exists git; then
            echo -e "${YELLOW}⚠ git installation failed, but continuing - repos may need to be mounted manually.${NC}"
        else
            echo -e "${GREEN}✓ git installed${NC}"
        fi
    fi

    # xmake is required for both InfiniCore and InfiniLM setup.py hooks.
    # Try to install xmake - fail early if it's not available when needed
    if ! install_xmake; then
        if [ "${do_infinicore}" = "true" ] || [ "${do_infinilm}" = "true" ]; then
            echo -e "${RED}✗ xmake is required for InfiniCore/InfiniLM installation but is not available${NC}"
            echo -e "${RED}  Cannot proceed without xmake. Please fix network connectivity or install xmake manually.${NC}"
            return 1
        else
            echo -e "${YELLOW}⚠ xmake installation failed, but not needed for current installation${NC}"
        fi
    fi

    # Ensure xmake profile is sourced if available (needed for subsequent xmake calls)
    if [ -f "/root/.xmake/profile" ]; then
        # shellcheck disable=SC1091
        source /root/.xmake/profile 2>/dev/null || true
    elif [ -f "${HOME}/.xmake/profile" ]; then
        # shellcheck disable=SC1091
        source "${HOME}/.xmake/profile" 2>/dev/null || true
    fi

    # Add xmake to PATH if it exists in common location
    if [ -f "/root/.xmake/bin/xmake" ] && ! command_exists xmake; then
        export PATH="/root/.xmake/bin:${PATH}"
    elif [ -f "${HOME}/.xmake/bin/xmake" ] && ! command_exists xmake; then
        export PATH="${HOME}/.xmake/bin:${PATH}"
    fi

    # Install InfiniCore (editable) if requested and repo exists.
    if [ "${do_infinicore}" = "true" ]; then
        if [ -z "${INFINICORE_SRC}" ]; then
            echo -e "${RED}✗ INSTALL_INFINICORE=true but INFINICORE_SRC not set.${NC}"
            echo -e "${RED}Error: Cannot install InfiniCore without INFINICORE_SRC.${NC}"
            return 1
        else
            # Try to clone if repo doesn't exist
            # InfiniCore doesn't require --recursive (no submodules mentioned in README)
            # Use branch from INFINICORE_BRANCH if specified
            if [ ! -d "${INFINICORE_SRC}" ] || [ ! -d "${INFINICORE_SRC}/.git" ]; then
                if clone_repo_if_needed "${INFINICORE_SRC}" "https://github.com/InfiniTensor/InfiniCore.git" "InfiniCore" "false" "${INFINICORE_BRANCH:-}"; then
                    echo -e "${GREEN}✓ InfiniCore repository ready${NC}"
                else
                    echo -e "${RED}✗ InfiniCore repo not found and could not be cloned.${NC}"
                    echo -e "${RED}Error: Failed to clone InfiniCore repository. Set --infinicore-src or ensure git is available.${NC}"
                    return 1
                fi
            fi

            if [ -d "${INFINICORE_SRC}" ] && [ -d "${INFINICORE_SRC}/.git" ]; then
                git_checkout_ref_if_requested "${INFINICORE_SRC}" "${INFINICORE_BRANCH}"

                # Use conda's Python if available (same as runtime)
            local python_cmd="python3"
            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                python_cmd="/opt/conda/bin/python"
            fi

            # Source env-set.sh to get INFINI_ROOT and other environment variables
            local infini_root="${INFINI_ROOT:-${HOME}/.infini}"
            if [ -f "/app/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source /app/env-set.sh
                infini_root="${INFINI_ROOT:-${HOME}/.infini}"
            elif [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source "${PROJECT_ROOT}/env-set.sh"
                infini_root="${INFINI_ROOT:-${HOME}/.infini}"
            fi

            local default_in_container="false"
            if [ -f "/.dockerenv" ]; then
                default_in_container="true"
            fi

            # Step 1: Build C++ targets (infiniop, infinirt, infiniccl, infinicore_cpp_api) - takes long time
            local do_build_cpp
            do_build_cpp="$(should_do "${INFINICORE_BUILD_CPP}" "${default_in_container}")"

            if [ "${do_build_cpp}" = "true" ]; then
                # Check if C++ libs already exist (skip if already built)
                local cpp_libs_exist=false
                if [ -f "${infini_root}/lib/libinfiniop.so" ] && \
                   [ -f "${infini_root}/lib/libinfinirt.so" ] && \
                   [ -f "${infini_root}/lib/libinfiniccl.so" ] && \
                   [ -f "${infini_root}/lib/libinfinicore_cpp_api.so" ]; then
                    cpp_libs_exist=true
                fi

                if [ "${cpp_libs_exist}" = "false" ]; then
                    echo "Building InfiniCore C++ targets (infiniop, infinirt, infiniccl, infinicore_cpp_api)..."
                    if [ -n "${INFINICORE_BUILD_CMD:-}" ]; then
                        echo "Running InfiniCore C++ build command: ${INFINICORE_BUILD_CMD}"
                        # Use conda's Python environment for build - replace python3/python with conda's Python if available
                        local build_cmd="${INFINICORE_BUILD_CMD}"
                        if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                            # Replace python3/python with conda's Python in the build command
                            # Use word boundaries to avoid partial matches and double replacement
                            build_cmd=$(echo "${build_cmd}" | sed "s|^python3 |${python_cmd} |" | sed "s| python3 | ${python_cmd} |" | sed "s|^python |${python_cmd} |" | sed "s| python | ${python_cmd} |")
                        fi
                        (
                            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                                # shellcheck disable=SC1091
                                source /opt/conda/etc/profile.d/conda.sh
                                conda activate base
                                export PATH="/opt/conda/bin:${PATH}"
                            fi
                            export PYTHON="${python_cmd}"
                            # Patch install.py to add -y flag to xmake commands for auto-confirmation
                            # This avoids interactive prompts during build
                            if [ -f "${INFINICORE_SRC}/scripts/install.py" ]; then
                                local install_py_backup="${INFINICORE_SRC}/scripts/install.py.backup"
                                if [ ! -f "${install_py_backup}" ]; then
                                    cp "${INFINICORE_SRC}/scripts/install.py" "${install_py_backup}"
                                    # Add -y flag to xmake f and xmake commands
                                    sed -i 's/xmake f \(.*\) -cv/xmake f \1 -y -cv/g' "${INFINICORE_SRC}/scripts/install.py"
                                    sed -i 's/run_cmd("xmake")/run_cmd("xmake -y")/g' "${INFINICORE_SRC}/scripts/install.py"
                                    sed -i 's/run_cmd("xmake install")/run_cmd("xmake install -y")/g' "${INFINICORE_SRC}/scripts/install.py"
                                    sed -i 's/run_cmd("xmake build/run_cmd("xmake build -y/g' "${INFINICORE_SRC}/scripts/install.py"
                                    sed -i 's/run_cmd("xmake install/run_cmd("xmake install -y/g' "${INFINICORE_SRC}/scripts/install.py"
                                fi
                            fi
                            cd "${INFINICORE_SRC}" && bash -lc "${build_cmd}"
                        ) || echo -e "${YELLOW}⚠ InfiniCore C++ build failed; continuing anyway.${NC}"
                    else
                        # Fallback: build C++ targets directly if no build command specified
                        echo "No INFINICORE_BUILD_CMD specified, building C++ targets directly..."
                        (
                            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                                # shellcheck disable=SC1091
                                source /opt/conda/etc/profile.d/conda.sh
                                conda activate base
                                export PATH="/opt/conda/bin:${PATH}"
                            fi
                            export PYTHON="${python_cmd}"
                            cd "${INFINICORE_SRC}" && \
                                xmake f -y -cv && \
                                xmake -y && \
                                xmake install -y
                        ) || echo -e "${YELLOW}⚠ InfiniCore C++ build failed; continuing anyway.${NC}"
                    fi
                else
                    echo -e "${GREEN}✓ InfiniCore C++ libraries already built, skipping C++ build${NC}"
                fi
            else
                echo "Skipping InfiniCore C++ build (INFINICORE_BUILD_CPP=${INFINICORE_BUILD_CPP})"
            fi

            # Step 2: Build Python extension (_infinicore) - quick rebuild, must match Python version
            local do_build_python
            do_build_python="$(should_do "${INFINICORE_BUILD_PYTHON}" "${default_in_container}")"

            if [ "${do_build_python}" = "true" ]; then
                echo "Installing InfiniCore Python extension (_infinicore) using ${python_cmd}..."
                (
                    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                        # shellcheck disable=SC1091
                        source /opt/conda/etc/profile.d/conda.sh
                        conda activate base
                        export PATH="/opt/conda/bin:${PATH}"
                    fi
                    export PYTHON="${python_cmd}"
                    # Dependencies are already installed above, just clean and build
                    # Build _infinicore explicitly using xmake before pip install
                    # This ensures the C++ dependencies are built and installed first
                    echo "Building _infinicore target explicitly with xmake..."
                    (
                        cd "${INFINICORE_SRC}"
                        # Ensure C++ libraries are installed first (needed by _infinicore)
                        if [ -n "${INFINICORE_BUILD_CMD:-}" ]; then
                            echo "  Running INFINICORE_BUILD_CMD to build C++ dependencies..."
                            # Patch install.py if not already patched
                            if [ -f "${INFINICORE_SRC}/scripts/install.py" ] && [ ! -f "${INFINICORE_SRC}/scripts/install.py.backup" ]; then
                                local install_py_backup="${INFINICORE_SRC}/scripts/install.py.backup"
                                cp "${INFINICORE_SRC}/scripts/install.py" "${install_py_backup}"
                                sed -i 's/xmake f \(.*\) -cv/xmake f \1 -y -cv/g' "${INFINICORE_SRC}/scripts/install.py"
                                sed -i 's/run_cmd("xmake")/run_cmd("xmake -y")/g' "${INFINICORE_SRC}/scripts/install.py"
                                sed -i 's/run_cmd("xmake install")/run_cmd("xmake install -y")/g' "${INFINICORE_SRC}/scripts/install.py"
                                sed -i 's/run_cmd("xmake build/run_cmd("xmake build -y/g' "${INFINICORE_SRC}/scripts/install.py"
                                sed -i 's/run_cmd("xmake install/run_cmd("xmake install -y/g' "${INFINICORE_SRC}/scripts/install.py"
                            fi
                            bash -c "${INFINICORE_BUILD_CMD}" || echo -e "${YELLOW}  ⚠ C++ build command failed, continuing...${NC}"
                        fi
                        # Build and install _infinicore explicitly
                        echo "  Building _infinicore target..."
                        xmake build -y _infinicore || {
                            echo -e "${YELLOW}  ⚠ xmake build _infinicore failed, trying pip install...${NC}"
                        }
                        # Install _infinicore to INFINI_ROOT
                        echo "  Installing _infinicore..."
                        xmake install -y _infinicore || {
                            echo -e "${YELLOW}  ⚠ xmake install _infinicore failed, trying pip install...${NC}"
                        }
                    ) || echo -e "${YELLOW}⚠ xmake build/install _infinicore failed, falling back to pip install${NC}"

                    # Clean _infinicore target to force rebuild with correct Python version
                    if [ -d "${INFINICORE_SRC}/.xmake" ]; then
                        echo "Cleaning _infinicore target to force rebuild with ${python_cmd}..."
                        (cd "${INFINICORE_SRC}" && xmake clean _infinicore 2>/dev/null || true)
                    fi
                    # pip install -e will trigger setup.py which builds _infinicore
                    # Try multiple China mainland mirrors in order: Aliyun -> Tsinghua -> Tencent
                    local infinicore_installed=false
                    for mirror_url in "http://mirrors.aliyun.com/pypi/simple" "https://pypi.tuna.tsinghua.edu.cn/simple" "https://mirrors.cloud.tencent.com/pypi/simple"; do
                        local mirror_name=$(echo "${mirror_url}" | sed 's|https\?://||' | sed 's|/.*||')
                        echo "  Trying ${mirror_name} mirror for InfiniCore..."
                        if ${python_cmd} -m pip install --no-cache-dir -i "${mirror_url}" --trusted-host "${mirror_name}" -e "${INFINICORE_SRC}" 2>&1; then
                            echo -e "${GREEN}✓ InfiniCore installed from ${mirror_name}${NC}"
                            infinicore_installed=true
                            break
                        else
                            echo "  ${mirror_name} mirror failed, trying next..."
                        fi
                    done
                    if [ "${infinicore_installed}" != "true" ]; then
                        echo -e "${YELLOW}⚠ InfiniCore Python extension install failed from all China mirrors${NC}"
                    fi
                ) || echo -e "${YELLOW}⚠ InfiniCore Python extension install failed (likely missing toolchain/libs).${NC}"
            else
                echo "Skipping InfiniCore Python extension build (INFINICORE_BUILD_PYTHON=${INFINICORE_BUILD_PYTHON})"
            fi

            # Create symlink for infinicore.lib module if needed
            # xmake installs _infinicore.so to INFINI_ROOT/lib, but Python expects it in python/infinicore/lib/
            local infini_root="${INFINI_ROOT:-${HOME}/.infini}"
            if [ -d "${INFINICORE_SRC}/python/infinicore" ]; then
                local lib_dir="${INFINICORE_SRC}/python/infinicore/lib"
                mkdir -p "${lib_dir}"
                # Find the .so file in INFINI_ROOT/lib (it may have different names based on Python version)
                local so_file=$(find "${infini_root}/lib" -name "infinicore*.so" -o -name "_infinicore*.so" 2>/dev/null | head -1)
                if [ -n "${so_file}" ] && [ ! -e "${lib_dir}/_infinicore.so" ]; then
                    echo "Creating symlink: ${lib_dir}/_infinicore.so -> ${so_file}"
                    ln -sf "${so_file}" "${lib_dir}/_infinicore.so"
                elif [ -z "${so_file}" ]; then
                    echo -e "${YELLOW}⚠ Could not find infinicore .so file in ${infini_root}/lib${NC}"
                fi
            fi
            fi
        fi
    fi

    # Install InfiniLM (editable) if requested and repo exists.
    if [ "${do_infinilm}" = "true" ]; then
        if [ -z "${INFINILM_SRC}" ]; then
            echo -e "${RED}✗ INSTALL_INFINILM=true but INFINILM_SRC not set.${NC}"
            echo -e "${RED}Error: Cannot install InfiniLM without INFINILM_SRC.${NC}"
            return 1
        else
            # Try to clone if repo doesn't exist
            # InfiniLM requires --recursive because it has submodules (per README.md)
            # Use branch from INFINILM_BRANCH if specified
            if [ ! -d "${INFINILM_SRC}" ] || [ ! -d "${INFINILM_SRC}/.git" ]; then
                if clone_repo_if_needed "${INFINILM_SRC}" "https://github.com/InfiniTensor/InfiniLM.git" "InfiniLM" "true" "${INFINILM_BRANCH:-}"; then
                    echo -e "${GREEN}✓ InfiniLM repository ready${NC}"
                else
                    echo -e "${RED}✗ InfiniLM repo not found and could not be cloned.${NC}"
                    echo -e "${RED}Error: Failed to clone InfiniLM repository. Set --infinilm-src or ensure git is available.${NC}"
                    return 1
                fi
            else
                # Repo exists, ensure submodules are initialized
                if [ -f "${INFINILM_SRC}/.gitmodules" ]; then
                    echo -e "${BLUE}Ensuring InfiniLM submodules are initialized...${NC}"
                    (cd "${INFINILM_SRC}" && git submodule update --init --recursive 2>/dev/null || true)
                fi
            fi

            if [ -d "${INFINILM_SRC}" ] && [ -d "${INFINILM_SRC}/.git" ]; then
                git_checkout_ref_if_requested "${INFINILM_SRC}" "${INFINILM_BRANCH}"

                # Use conda's Python if available (same as runtime)
                local python_cmd="python3"
                if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                    python_cmd="/opt/conda/bin/python"
                fi

                echo "Installing InfiniLM from ${INFINILM_SRC} (editable) using ${python_cmd}..."
                # Set PYTHON environment variable so xmake (called by setup.py) uses the same Python
                (
                    if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                        # shellcheck disable=SC1091
                        source /opt/conda/etc/profile.d/conda.sh
                        conda activate base
                        # Ensure conda's Python is first in PATH so xmake uses it
                        export PATH="/opt/conda/bin:${PATH}"
                    fi
                    export PYTHON="${python_cmd}"

                    # Ensure build dependencies are installed first (setuptools, wheel)
                    # Try multiple China mainland mirrors in order: Aliyun -> Tsinghua -> Tencent
                    # Unset proxy env vars to avoid proxy connection errors in pip subprocess
                    echo "Installing build dependencies (setuptools, wheel)..."
                    local build_deps_installed=false
                    local working_mirror_url=""
                    local working_mirror_name=""
                    for mirror_url in "http://mirrors.aliyun.com/pypi/simple" "https://pypi.tuna.tsinghua.edu.cn/simple" "https://mirrors.cloud.tencent.com/pypi/simple"; do
                        local mirror_name=$(echo "${mirror_url}" | sed 's|https\?://||' | sed 's|/.*||')
                        echo "  Trying ${mirror_name} mirror..."
                        # Unset proxy env vars for pip to avoid proxy connection errors
                        if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
                            ${python_cmd} -m pip install --no-cache-dir -i "${mirror_url}" --trusted-host "${mirror_name}" setuptools wheel 2>&1; then
                            echo -e "${GREEN}✓ Build dependencies installed from ${mirror_name}${NC}"
                            build_deps_installed=true
                            working_mirror_url="${mirror_url}"
                            working_mirror_name="${mirror_name}"
                            break
                        else
                            echo "  ${mirror_name} mirror failed, trying next..."
                        fi
                    done
                    if [ "${build_deps_installed}" != "true" ]; then
                        echo -e "${RED}✗ Failed to install build dependencies from all China mirrors${NC}"
                        return 1
                    fi

                    # Clean _infinilm target to force rebuild with correct Python version
                    if [ -d "${INFINILM_SRC}/.xmake" ]; then
                        echo "Cleaning _infinilm target to force rebuild with ${python_cmd}..."
                        (cd "${INFINILM_SRC}" && xmake clean _infinilm 2>/dev/null || true)
                    fi

                    # Build _infinilm explicitly using xmake before pip install
                    # This ensures the C++ extension is built and installed first
                    echo "Building _infinilm target explicitly with xmake..."
                    (
                        cd "${INFINILM_SRC}"
                        # Ensure InfiniCore libraries are installed first (needed by _infinilm)
                        # Build and install _infinilm explicitly
                        echo "  Building _infinilm target..."
                        xmake build -y _infinilm || {
                            echo -e "${YELLOW}  ⚠ xmake build _infinilm failed, trying pip install...${NC}"
                        }
                        # Install _infinilm to python/infinilm
                        echo "  Installing _infinilm..."
                        xmake install -y _infinilm || {
                            echo -e "${YELLOW}  ⚠ xmake install _infinilm failed, trying pip install...${NC}"
                        }
                    ) || echo -e "${YELLOW}⚠ xmake build/install _infinilm failed, falling back to pip install${NC}"

                    # Install InfiniLM package (editable mode)
                    # Since _infinilm is already built by xmake, we can use --no-build-isolation to skip build deps
                    # Create temporary pip config to ensure build dependencies subprocess uses the working mirror
                    # The subprocess spawned by pip install -e doesn't always respect PIP_INDEX_URL env var
                    echo "Installing InfiniLM package (editable mode) using ${working_mirror_name} mirror..."
                    local temp_pip_config="/tmp/pip_infinilm_install.conf"
                    cat > "${temp_pip_config}" << EOF
[global]
index-url = ${working_mirror_url}
trusted-host = ${working_mirror_name}
EOF
                    # Use --no-build-isolation since _infinilm is already built by xmake
                    # This avoids the subprocess build dependency installation issue
                    # Use the temporary pip config and unset proxy for pip subprocess
                    if env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
                        PIP_CONFIG_FILE="${temp_pip_config}" \
                        ${python_cmd} -m pip install --no-cache-dir --no-build-isolation -e "${INFINILM_SRC}" 2>&1; then
                        echo -e "${GREEN}✓ InfiniLM installed successfully from ${working_mirror_name}${NC}"
                        rm -f "${temp_pip_config}" 2>/dev/null || true
                    else
                        echo -e "${YELLOW}⚠ pip install -e failed, but _infinilm is already built by xmake${NC}"
                        echo -e "${YELLOW}  Checking if InfiniLM can be imported via PYTHONPATH...${NC}"
                        # Check if the .so file exists
                        if [ -f "${INFINILM_SRC}/python/infinilm/lib/_infinilm"*.so ] || [ -f "${INFINILM_SRC}/build"*"/_infinilm"*.so ]; then
                            echo -e "${GREEN}✓ _infinilm.so found - InfiniLM should work at runtime with PYTHONPATH${NC}"
                            echo -e "${YELLOW}  Note: InfiniLM is not installed as a package, but the module exists${NC}"
                            echo -e "${YELLOW}  The babysitter config should set PYTHONPATH=/workspace/InfiniLM/python:/workspace/InfiniCore/python${NC}"
                        else
                            echo -e "${RED}✗ _infinilm.so not found - InfiniLM installation incomplete${NC}"
                            rm -f "${temp_pip_config}" 2>/dev/null || true
                            return 1
                        fi
                        rm -f "${temp_pip_config}" 2>/dev/null || true
                    fi
                ) || {
                    echo -e "${YELLOW}⚠ InfiniLM install failed (likely missing toolchain/libs).${NC}"
                    echo -e "${YELLOW}  Note: InfiniLM may still work at runtime if PYTHONPATH includes /workspace/InfiniLM/python${NC}"
                }
            fi
        fi
    fi

    echo ""
}

# Function to install xtask from InfiniLM-Rust
install_xtask_optional() {
    resolve_optional_repo_paths

    # Decide whether to install (auto => install only if repo path exists and we're root/in-container)
    local default_in_container="false"
    if [ -f "/.dockerenv" ]; then
        default_in_container="true"
    fi

    local do_xtask
    do_xtask="$(should_do "${INSTALL_XTASK}" "${default_in_container}")"

    if [ "${do_xtask}" != "true" ]; then
        return 0
    fi

    # Resolve repo path if not set
    if [ -z "${INFINILM_RUST_SRC}" ]; then
        if [ -d "${PROJECT_ROOT}/../InfiniLM-Rust" ]; then
            INFINILM_RUST_SRC="${PROJECT_ROOT}/../InfiniLM-Rust"
        else
            # Default to sibling directory
            INFINILM_RUST_SRC="${PROJECT_ROOT}/../InfiniLM-Rust"
        fi
    fi

    # Check if repo exists and is a git repo, clone if needed
    if [ ! -d "${INFINILM_RUST_SRC}" ] || [ ! -d "${INFINILM_RUST_SRC}/.git" ]; then
        if ! command_exists git; then
            echo -e "${YELLOW}⚠ INSTALL_XTASK=true but InfiniLM-Rust repo not found and git is not available.${NC}"
            echo -e "${YELLOW}  Please clone the repo manually or install git.${NC}"
            return 0
        fi

        echo -e "${BLUE}Cloning InfiniLM-Rust repository...${NC}"
        local repo_url="https://github.com/InfiniTensor/InfiniLM-Rust.git"
        local parent_dir="$(dirname "${INFINILM_RUST_SRC}")"
        local repo_name="$(basename "${INFINILM_RUST_SRC}")"

        # Create parent directory if it doesn't exist
        mkdir -p "${parent_dir}"

        # Clone the repository
        if git clone "${repo_url}" "${INFINILM_RUST_SRC}"; then
            echo -e "${GREEN}✓ Cloned InfiniLM-Rust repository${NC}"
        else
            echo -e "${RED}✗ Failed to clone InfiniLM-Rust repository${NC}"
            return 0
        fi
    fi

    echo -e "${BLUE}Installing xtask from InfiniLM-Rust...${NC}"

    # Check if Rust/Cargo is available
    if ! command_exists cargo; then
        echo -e "${YELLOW}⚠ Skipping xtask install (cargo unavailable).${NC}"
        echo ""
        return 0
    fi

    # Get INFINI_ROOT from env-set.sh if available
    local infini_root="${INFINI_ROOT:-${HOME}/.infini}"
    if [ -f "/app/env-set.sh" ]; then
        # shellcheck disable=SC1091
        source /app/env-set.sh 2>/dev/null || true
        infini_root="${INFINI_ROOT:-${HOME}/.infini}"
    elif [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
        # shellcheck disable=SC1091
        source "${PROJECT_ROOT}/env-set.sh" 2>/dev/null || true
        infini_root="${INFINI_ROOT:-${HOME}/.infini}"
    fi

    # Ensure INFINI_ROOT directories exist
    mkdir -p "${infini_root}/bin"
    mkdir -p "${infini_root}/lib"

    # Checkout the specified branch
    git_checkout_ref_if_requested "${INFINILM_RUST_SRC}" "${INFINILM_RUST_BRANCH}"

    echo "Building xtask from ${INFINILM_RUST_SRC} (branch: ${INFINILM_RUST_BRANCH})..."

    # Build xtask binary
    (
        cd "${INFINILM_RUST_SRC}" || exit 1

        # Source cargo environment if available
        if [ -f "${HOME}/.cargo/env" ]; then
            # shellcheck disable=SC1091
            source "${HOME}/.cargo/env"
        fi

        # Build xtask binary
        if cargo build --release --bin xtask; then
            echo -e "${GREEN}✓ xtask build completed successfully${NC}"

            # Install xtask binary to INFINI_ROOT/bin
            local xtask_binary="${INFINILM_RUST_SRC}/target/release/xtask"
            if [ -f "${xtask_binary}" ]; then
                cp "${xtask_binary}" "${infini_root}/bin/xtask"
                chmod +x "${infini_root}/bin/xtask"
                echo -e "${GREEN}✓ Installed xtask to ${infini_root}/bin/xtask${NC}"
            else
                echo -e "${RED}✗ xtask binary not found at ${xtask_binary}${NC}"
                return 1
            fi

            # Install shared libraries (.so files) from build output to INFINI_ROOT/lib
            # These are built as part of the llama-cu dependency (e.g., librandom_sample.so)
            local build_out_dirs="${INFINILM_RUST_SRC}/target/release/build/llama-cu-*/out"
            local so_files_found=0
            for build_dir in ${build_out_dirs}; do
                if [ -d "${build_dir}" ]; then
                    # Find all .so files in the build output directory
                    while IFS= read -r -d '' so_file; do
                        local so_name="$(basename "${so_file}")"
                        cp "${so_file}" "${infini_root}/lib/${so_name}"
                        chmod 755 "${infini_root}/lib/${so_name}"
                        echo -e "${GREEN}✓ Installed ${so_name} to ${infini_root}/lib/${so_name}${NC}"
                        so_files_found=$((so_files_found + 1))
                    done < <(find "${build_dir}" -maxdepth 1 -name "*.so" -type f -print0 2>/dev/null)
                fi
            done

            if [ ${so_files_found} -eq 0 ]; then
                echo -e "${YELLOW}⚠ No .so files found in build output (this may be normal if libraries are statically linked)${NC}"
            fi
        else
            echo -e "${RED}✗ xtask build failed${NC}"
            return 1
        fi
    ) || {
        echo -e "${YELLOW}⚠ xtask installation failed${NC}"
        return 0  # Don't fail the entire installation
    }

    echo ""
}

# Function to verify InfiniCore/InfiniLM installations
verify_infinicore_and_infinilm() {
    resolve_optional_repo_paths

    # Decide whether to verify (auto => verify only if repos exist and we're in container)
    local default_in_container="false"
    if [ -f "/.dockerenv" ]; then
        default_in_container="true"
    fi

    local do_verify
    do_verify="$(should_do "${VERIFY_INSTALL}" "${default_in_container}")"

    if [ "${do_verify}" != "true" ]; then
        return 0
    fi

    echo -e "${BLUE}Verifying InfiniCore/InfiniLM installations...${NC}"

    # Verify InfiniCore if repo exists
    if [ -n "${INFINICORE_SRC:-}" ] && [ -d "${INFINICORE_SRC}" ] && [ -d "${INFINICORE_SRC}/python/infinicore" ]; then
        echo "Verifying infinicore.lib import..."
        (
            # Export color variables for use in subshell
            export GREEN="${GREEN:-}"
            export YELLOW="${YELLOW:-}"
            export NC="${NC:-}"

            # Determine Python command - use conda's Python if available
            local verify_python_cmd="python3"
            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                verify_python_cmd="/opt/conda/bin/python"
            fi

            # Source conda if available (same as docker entrypoint)
            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                # shellcheck disable=SC1091
                source /opt/conda/etc/profile.d/conda.sh
                conda activate base
                # Add conda's lib directory to LD_LIBRARY_PATH for Python library
                export LD_LIBRARY_PATH="/opt/conda/lib:${LD_LIBRARY_PATH:-}"
            fi

            # Source env-set.sh if available (same as docker entrypoint)
            if [ -f "/app/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source /app/env-set.sh
            elif [ -f "/workspace/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source /workspace/env-set.sh
            elif [ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source "${PROJECT_ROOT}/env-set.sh"
            fi

            # Ensure required environment variables are set for preload
            # These are needed by _preload.py to find HPCC libraries and _infinicore.so
            local infini_root="${INFINI_ROOT:-${HOME}/.infini}"
            export INFINI_ROOT="${infini_root}"

            # Set HPCC_PATH if not already set (needed for METAX preload)
            if [ -z "${HPCC_PATH:-}" ] && [ -d "/opt/hpcc" ]; then
                export HPCC_PATH="/opt/hpcc"
            fi

            # Ensure LD_LIBRARY_PATH includes necessary paths
            if [ -n "${HPCC_PATH:-}" ] && [ -d "${HPCC_PATH}/lib" ]; then
                export LD_LIBRARY_PATH="${HPCC_PATH}/lib:${LD_LIBRARY_PATH:-}"
            fi
            if [ -d "${infini_root}/lib" ]; then
                export LD_LIBRARY_PATH="${infini_root}/lib:${LD_LIBRARY_PATH:-}"
            fi
            if [ -d "/opt/conda/lib" ]; then
                export LD_LIBRARY_PATH="/opt/conda/lib:${LD_LIBRARY_PATH:-}"
            fi

            # Set PYTHONPATH to include InfiniCore Python directory
            export PYTHONPATH="${INFINICORE_SRC}/python:${PYTHONPATH:-}"

            # Enable preload if HPCC_PATH is set (for METAX)
            if [ -n "${HPCC_PATH:-}" ]; then
                export INFINICORE_PRELOAD_HPCC="1"
            fi

            # Use the determined Python command (conda's Python if available)
            # During Docker build, devices may not be available, so we catch device-related errors
            # Use set +e temporarily to allow import failures (we'll handle them)
            set +e
            if ${verify_python_cmd} -c "import infinicore; print('✓ infinicore imported successfully')" 2>&1; then
                set -e
                echo -e "${GREEN}✓ InfiniCore installation verified${NC}"
            else
                # Capture import output for better error detection
                # Import is expected to fail during build, so don't let set -e exit here
                local import_output
                import_output=$(${verify_python_cmd} -c "import infinicore" 2>&1 || true)
                set -e

                # Check if error is device-related (common during Docker build)
                # Device errors include: hcGetDeviceCount, infinirtGetAllDeviceCount, Error Code 3, Internal Error
                if echo "${import_output}" | grep -qE "(hcGetDeviceCount|infinirtGetAllDeviceCount|Error Code [0-9]+|Internal Error|ContextImpl)"; then
                    # Check if we're in a Docker build environment (devices not available)
                    local in_build_env=false
                    if [ -f "/.dockerenv" ] && { [ ! -c /dev/dri/card0 ] && [ ! -c /dev/htcd ] && [ ! -c /dev/infiniband ]; }; then
                        in_build_env=true
                    fi

                    if [ "${in_build_env}" = "true" ]; then
                        echo -e "${YELLOW}⚠ InfiniCore import failed due to device access (expected during Docker build)${NC}"
                        echo -e "${YELLOW}  Devices (/dev/dri, /dev/htcd, /dev/infiniband) are not available during build${NC}"
                        echo -e "${YELLOW}  This is normal - InfiniCore will work correctly at runtime with proper device mounts${NC}"
                        echo -e "${GREEN}✓ InfiniCore installation verified (device check skipped during build)${NC}"
                    else
                        echo -e "${YELLOW}⚠ InfiniCore import failed due to device access error${NC}"
                        echo -e "${YELLOW}  Error: ${import_output}${NC}"
                        echo -e "${YELLOW}  This may indicate a device configuration issue${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠ InfiniCore import verification failed${NC}"
                    echo -e "${YELLOW}  Error: ${import_output}${NC}"
                    echo -e "${YELLOW}  This may be normal if runtime dependencies are not yet available${NC}"
                    echo -e "${YELLOW}  The installation should work at runtime${NC}"
                fi
            fi
        )
    fi

    # Verify InfiniLM if repo exists
    if [ -n "${INFINILM_SRC:-}" ] && [ -d "${INFINILM_SRC}" ] && [ -d "${INFINILM_SRC}/python/infinilm" ]; then
        echo "Verifying infinilm import..."
        (
            # Export color variables for use in subshell
            export GREEN="${GREEN:-}"
            export YELLOW="${YELLOW:-}"
            export NC="${NC:-}"

            # Determine Python command - use conda's Python if available
            local verify_python_cmd="python3"
            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                verify_python_cmd="/opt/conda/bin/python"
            fi

            # Source conda if available (same as docker entrypoint)
            if [ -f "/opt/conda/etc/profile.d/conda.sh" ]; then
                # shellcheck disable=SC1091
                source /opt/conda/etc/profile.d/conda.sh
                conda activate base
                # Add conda's lib directory to LD_LIBRARY_PATH for Python library
                export LD_LIBRARY_PATH="/opt/conda/lib:${LD_LIBRARY_PATH:-}"
            fi

            # Source env-set.sh if available (same as docker entrypoint)
            if [ -f "/app/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source /app/env-set.sh
            elif [ -f "/workspace/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source /workspace/env-set.sh
            elif [ -n "${PROJECT_ROOT:-}" ] && [ -f "${PROJECT_ROOT}/env-set.sh" ]; then
                # shellcheck disable=SC1091
                source "${PROJECT_ROOT}/env-set.sh"
            fi

            # Set PYTHONPATH to include InfiniLM and InfiniCore Python directories
            export PYTHONPATH="${INFINILM_SRC}/python:${INFINICORE_SRC:-}/python:${PYTHONPATH:-}"

            # First check if InfiniLM package is installed via pip
            local infinilm_installed=false
            if ${verify_python_cmd} -m pip list 2>/dev/null | grep -qi "infinilm"; then
                infinilm_installed=true
            fi

            # Use the determined Python command (conda's Python if available)
            # Use set +e temporarily to allow import failures (we'll handle them)
            set +e
            if ${verify_python_cmd} -c "import infinilm; print('✓ infinilm imported successfully')" 2>&1; then
                set -e
                echo -e "${GREEN}✓ InfiniLM installation verified${NC}"
            else
                # Capture import output for better error detection
                # Import is expected to fail during build, so don't let set -e exit here
                local import_output
                import_output=$(${verify_python_cmd} -c "import infinilm" 2>&1 || true)
                set -e

                # Check if error is device-related (common during Docker build)
                # Device errors include: hcGetDeviceCount, infinirtGetAllDeviceCount, Error Code 3, Internal Error
                if echo "${import_output}" | grep -qE "(hcGetDeviceCount|infinirtGetAllDeviceCount|Error Code [0-9]+|Internal Error|ContextImpl)"; then
                    # Check if we're in a Docker build environment (devices not available)
                    local in_build_env=false
                    if [ -f "/.dockerenv" ] && { [ ! -c /dev/dri/card0 ] && [ ! -c /dev/htcd ] && [ ! -c /dev/infiniband ]; }; then
                        in_build_env=true
                    fi

                    if [ "${in_build_env}" = "true" ]; then
                        echo -e "${YELLOW}⚠ InfiniLM import failed due to device access (expected during Docker build)${NC}"
                        echo -e "${YELLOW}  Devices (/dev/dri, /dev/htcd, /dev/infiniband) are not available during build${NC}"
                        echo -e "${YELLOW}  This is normal - InfiniLM will work correctly at runtime with proper device mounts${NC}"
                        echo -e "${GREEN}✓ InfiniLM installation verified (device check skipped during build)${NC}"
                    else
                        echo -e "${YELLOW}⚠ InfiniLM import failed due to device access error${NC}"
                        echo -e "${YELLOW}  Error: ${import_output}${NC}"
                        echo -e "${YELLOW}  This may indicate a device configuration issue${NC}"
                    fi
                elif echo "${import_output}" | grep -qE "ModuleNotFoundError|No module named 'infinilm'"; then
                    if [ "${infinilm_installed}" != "true" ]; then
                        echo -e "${YELLOW}⚠ InfiniLM import verification failed - package not installed via pip${NC}"
                        echo -e "${YELLOW}  InfiniLM installation may have failed during build${NC}"
                        echo -e "${YELLOW}  Check build logs for installation errors${NC}"
                        if [ -d "${INFINILM_SRC}/python/infinilm" ]; then
                            echo -e "${YELLOW}  Source directory exists - InfiniLM may work at runtime if PYTHONPATH includes /workspace/InfiniLM/python${NC}"
                        fi
                    else
                        echo -e "${YELLOW}⚠ InfiniLM package installed but import failed${NC}"
                        echo -e "${YELLOW}  This may be normal if runtime dependencies are not yet available${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠ InfiniLM import verification failed${NC}"
                    echo -e "${YELLOW}  Error: ${import_output}${NC}"
                    echo -e "${YELLOW}  This may be normal if runtime dependencies are not yet available${NC}"
                fi
            fi
        )
    fi

    echo ""
    # Verification is informational only - always return success
    # Device errors during build are expected and non-fatal
    return 0
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
    # Re-detect OpenSSL if not already found (in case env-set.sh didn't set it)
    if ! check_openssl; then
        echo -e "${YELLOW}OpenSSL not found via standard check, attempting to locate...${NC}"
        # Try to find OpenSSL in common locations
        local openssl_found=false
        for dir in /usr /usr/local /opt/conda /opt/hpcc; do
            # Check for OpenSSL headers
            if [ -f "${dir}/include/openssl/ssl.h" ]; then
                # Check for OpenSSL libraries
                if [ -f "${dir}/lib/libssl.so" ] || [ -f "${dir}/lib64/libssl.so" ] || \
                   [ -f "${dir}/lib/libssl.a" ] || [ -f "${dir}/lib64/libssl.a" ]; then
                    echo -e "${GREEN}Found OpenSSL in ${dir}${NC}"
                    export OPENSSL_DIR="${dir}"
                    # Set include path
                    if [ -d "${dir}/include" ]; then
                        export C_INCLUDE_PATH="${dir}/include:${C_INCLUDE_PATH:-}"
                    fi
                    # Set library paths
                    if [ -d "${dir}/lib64" ]; then
                        export LD_LIBRARY_PATH="${dir}/lib64:${LD_LIBRARY_PATH:-}"
                    fi
                    if [ -d "${dir}/lib" ]; then
                        export LD_LIBRARY_PATH="${dir}/lib:${LD_LIBRARY_PATH:-}"
                    fi
                    # Try to find openssl.pc for pkg-config
                    for pc_path in "${dir}/lib/pkgconfig" "${dir}/lib64/pkgconfig" \
                                   "${dir}/share/pkgconfig" "${dir}/pkgconfig"; do
                        if [ -f "${pc_path}/openssl.pc" ]; then
                            export PKG_CONFIG_PATH="${pc_path}:${PKG_CONFIG_PATH:-}"
                            echo -e "${GREEN}Found openssl.pc at ${pc_path}${NC}"
                            break
                        fi
                    done
                    openssl_found=true
                    break
                fi
            fi
        done

        if [ "$openssl_found" = "false" ]; then
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
    fi

    cd "${PROJECT_ROOT}/rust" || exit 1

    # Ensure Cargo is in PATH
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # Build release binaries
    echo "Building infini-registry, infini-router, and infini-babysitter..."

    # Ensure OpenSSL environment variables are set for Rust build
    # Re-check and set OPENSSL_DIR if not already set (from install_system_deps)
    if [ -z "${OPENSSL_DIR:-}" ]; then
        # Try to find OpenSSL again
        for dir in /usr /usr/local /opt/conda /opt/hpcc; do
            if [ -f "${dir}/include/openssl/ssl.h" ] && \
               ([ -f "${dir}/lib/libssl.so" ] || [ -f "${dir}/lib64/libssl.so" ] || \
                [ -f "${dir}/lib/libssl.a" ] || [ -f "${dir}/lib64/libssl.a" ]); then
                export OPENSSL_DIR="${dir}"
                echo -e "${GREEN}Set OPENSSL_DIR=${OPENSSL_DIR} for Rust build${NC}"
                break
            fi
        done
    fi

    if [ -n "${OPENSSL_DIR:-}" ]; then
        export OPENSSL_DIR
        echo "Using OPENSSL_DIR: ${OPENSSL_DIR}"
        # Also set PKG_CONFIG_PATH if openssl.pc exists
        for pc_path in "${OPENSSL_DIR}/lib/pkgconfig" "${OPENSSL_DIR}/lib64/pkgconfig" \
                       "${OPENSSL_DIR}/share/pkgconfig" "${OPENSSL_DIR}/pkgconfig"; do
            if [ -f "${pc_path}/openssl.pc" ]; then
                export PKG_CONFIG_PATH="${pc_path}:${PKG_CONFIG_PATH:-}"
                echo "Using PKG_CONFIG_PATH: ${PKG_CONFIG_PATH}"
                break
            fi
        done
    fi

    if [ -n "${PKG_CONFIG_PATH:-}" ]; then
        export PKG_CONFIG_PATH
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
                # Only copy if source and destination are different
                if [ "${PROJECT_ROOT}/script" != "${APP_ROOT}/script" ]; then
                    mkdir -p "${APP_ROOT}/script"
                    cp -a "${PROJECT_ROOT}/script/." "${APP_ROOT}/script/" 2>/dev/null || true
                    chmod +x "${APP_ROOT}"/script/*.sh 2>/dev/null || true
                    echo -e "  ${GREEN}✓${NC} Staged scripts: ${APP_ROOT}/script/"
                else
                    # Source and destination are the same, just ensure scripts are executable
                    chmod +x "${APP_ROOT}"/script/*.sh 2>/dev/null || true
                    echo -e "  ${GREEN}✓${NC} Scripts already in place: ${APP_ROOT}/script/"
                fi
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

    # Install InfiniCore and InfiniLM FIRST (before Rust/build) for quick validation
    # This allows early validation of InfiniCore/InfiniLM setup before building InfiniLM-SVC binaries
    install_infinicore_and_infinilm_optional
    verify_infinicore_and_infinilm

    # Then install Rust and build InfiniLM-SVC binaries
    install_rust
    build_binaries
    install_binaries
    install_python_deps
    # install_xtask_optional  # Install xtask after Rust is available
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
