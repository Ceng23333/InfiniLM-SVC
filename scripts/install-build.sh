#!/usr/bin/env bash
# InfiniLM-SVC Phase 2: Build from Local Sources Script
# Builds InfiniLM-SVC, InfiniCore, and InfiniLM from mounted/copied sources
# This script is designed for Phase 2 of a two-phase build process
#
# Usage:
#   ./scripts/install-build.sh [OPTIONS]
#
# Options:
#   --skip-build           Skip building binaries (assumes binaries already exist)
#   --install-path PATH    Installation path for binaries (default: /usr/local/bin)
#   --build-only           Only build, don't install binaries
#   --install-infinicore MODE   auto|true|false (default: auto; env: INSTALL_INFINICORE)
#   --install-infinilm MODE     auto|true|false (default: auto; env: INSTALL_INFINILM)
#   --infinicore-src PATH       Path to InfiniCore repo (required for Phase 2; env: INFINICORE_SRC)
#   --infinilm-src PATH         Path to InfiniLM repo (required for Phase 2; env: INFINILM_SRC)
#   --infinilm-svc-src PATH     Path to InfiniLM-SVC repo (for Phase 2; env: INFINILM_SVC_SRC)
#   --infinicore-branch BRANCH  Git branch/tag/commit to checkout in InfiniCore repo (env: INFINICORE_BRANCH)
#   --infinilm-branch BRANCH    Git branch/tag/commit to checkout in InfiniLM repo (env: INFINILM_BRANCH)
#   --deployment-case NAME      Deployment case preset name (loads deployment/cases/NAME; env: DEPLOYMENT_CASE)
#   --help                 Show this help message
#
# This script:
#   - Validates that required tools (Rust, xmake) are available
#   - Validates that InfiniCore/InfiniLM source directories exist
#   - Builds Rust binaries (uses cached cargo deps from Phase 1)
#   - Installs InfiniCore from mounted/copied source
#   - Installs InfiniLM from mounted/copied source
#   - Installs binaries
#   - Sets up scripts
#   - Works offline (no network operations)

set -e

# Source the main install.sh script to reuse its functions
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

# Override main() to run only Phase 2
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}InfiniLM-SVC Phase 2: Build from Local Sources${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    # Load deployment-case defaults early so it can influence installation behavior.
    load_deployment_case_preset

    # Phase 2: Validate prerequisites (no network operations)
    echo -e "${BLUE}Validating prerequisites...${NC}"

    # Validate Rust is installed
    if ! command_exists cargo || ! command_exists rustc; then
        echo -e "${RED}Error: Rust is not installed. Please run Phase 1 (install-deps.sh) first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Rust toolchain found${NC}"
    rustc --version
    cargo --version

    # Validate xmake is installed
    if ! command_exists xmake; then
        echo -e "${RED}Error: xmake is not installed. Please run Phase 1 (install-deps.sh) first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ xmake found${NC}"
    xmake --version

    # Validate InfiniCore/InfiniLM are installed (from Phase 1)
    # In Phase 2, we expect them to already be installed from Phase 1
    # But we still check if source paths are provided for potential rebuilds
    resolve_optional_repo_paths
    local default_in_container="false"
    if [ -f "/.dockerenv" ]; then
        default_in_container="true"
    fi
    local do_infinicore
    local do_infinilm
    do_infinicore="$(should_do "${INSTALL_INFINICORE}" "${default_in_container}")"
    do_infinilm="$(should_do "${INSTALL_INFINILM}" "${default_in_container}")"

    if [ "${do_infinicore}" = "true" ]; then
        # Check if InfiniCore is already installed (from Phase 1)
        local infinicore_installed=false
        if python3 -c "import infinicore" 2>/dev/null || python -c "import infinicore" 2>/dev/null; then
            infinicore_installed=true
            echo -e "${GREEN}✓ InfiniCore is already installed (from Phase 1)${NC}"
        fi

        # If source path is provided, validate it exists (for potential rebuilds)
        if [ -n "${INFINICORE_SRC}" ]; then
            if [ ! -d "${INFINICORE_SRC}" ]; then
                if [ "${infinicore_installed}" = "false" ]; then
                    echo -e "${RED}Error: InfiniCore not installed and source directory not found: ${INFINICORE_SRC}${NC}"
                    echo -e "${RED}  InfiniCore should have been installed in Phase 1. Please run Phase 1 first.${NC}"
                    exit 1
                else
                    echo -e "${YELLOW}⚠ InfiniCore source directory not found: ${INFINICORE_SRC}${NC}"
                    echo -e "${YELLOW}  But InfiniCore is already installed, continuing...${NC}"
                fi
            else
                echo -e "${GREEN}✓ InfiniCore source found: ${INFINICORE_SRC}${NC}"
            fi
        elif [ "${infinicore_installed}" = "false" ]; then
            echo -e "${YELLOW}⚠ InfiniCore not found installed and no source path provided${NC}"
            echo -e "${YELLOW}  Expected to be installed in Phase 1. Continuing anyway...${NC}"
        fi
    fi

    if [ "${do_infinilm}" = "true" ]; then
        # Check if InfiniLM is already installed (from Phase 1)
        local infinilm_installed=false
        if python3 -c "import infinilm" 2>/dev/null || python -c "import infinilm" 2>/dev/null; then
            infinilm_installed=true
            echo -e "${GREEN}✓ InfiniLM is already installed (from Phase 1)${NC}"
        fi

        # If source path is provided, validate it exists (for potential rebuilds)
        if [ -n "${INFINILM_SRC}" ]; then
            if [ ! -d "${INFINILM_SRC}" ]; then
                if [ "${infinilm_installed}" = "false" ]; then
                    echo -e "${RED}Error: InfiniLM not installed and source directory not found: ${INFINILM_SRC}${NC}"
                    echo -e "${RED}  InfiniLM should have been installed in Phase 1. Please run Phase 1 first.${NC}"
                    exit 1
                else
                    echo -e "${YELLOW}⚠ InfiniLM source directory not found: ${INFINILM_SRC}${NC}"
                    echo -e "${YELLOW}  But InfiniLM is already installed, continuing...${NC}"
                fi
            else
                echo -e "${GREEN}✓ InfiniLM source found: ${INFINILM_SRC}${NC}"
            fi
        elif [ "${infinilm_installed}" = "false" ]; then
            echo -e "${YELLOW}⚠ InfiniLM not found installed and no source path provided${NC}"
            echo -e "${YELLOW}  Expected to be installed in Phase 1. Continuing anyway...${NC}"
        fi
    fi

    echo ""

    # Phase 2: Build and install
    # Ensure INSTALL_PHASE is not set to "deps" so build_binaries will run
    # build_binaries skips if INSTALL_PHASE="deps", so we explicitly unset it or set to "build"
    unset INSTALL_PHASE

    # If INFINILM_SVC_SRC is provided, use it as the project root for building
    # This allows building from a mounted/copied source instead of the current directory
    local original_project_root="${PROJECT_ROOT}"
    local using_external_source=false
    if [ -n "${INFINILM_SVC_SRC:-}" ] && [ -d "${INFINILM_SVC_SRC}" ]; then
        echo -e "${BLUE}Using InfiniLM-SVC source from: ${INFINILM_SVC_SRC}${NC}"
        echo -e "${BLUE}  Original PROJECT_ROOT: ${original_project_root}${NC}"
        echo -e "${BLUE}  New PROJECT_ROOT: ${INFINILM_SVC_SRC}${NC}"

        # Verify the source has required files
        if [ ! -f "${INFINILM_SVC_SRC}/rust/Cargo.toml" ]; then
            echo -e "${YELLOW}⚠ Warning: ${INFINILM_SVC_SRC}/rust/Cargo.toml not found${NC}"
            echo -e "${YELLOW}  Falling back to original PROJECT_ROOT: ${original_project_root}${NC}"
        else
            PROJECT_ROOT="${INFINILM_SVC_SRC}"
            using_external_source=true
            echo -e "${GREEN}✓ InfiniLM-SVC source validated: ${PROJECT_ROOT}/rust/Cargo.toml exists${NC}"
            echo -e "${GREEN}✓ Will build from external source: ${PROJECT_ROOT}${NC}"
            # Update SCRIPT_DIR to point to scripts in the new project root
            if [ -f "${PROJECT_ROOT}/scripts/install.sh" ]; then
                SCRIPT_DIR="${PROJECT_ROOT}/scripts"
            fi
        fi
    fi

    # Build Rust binaries (uses cached cargo deps from Phase 1)
    # This builds InfiniLM-SVC (infini-registry, infini-router, infini-babysitter)
    # build_binaries() will use the updated PROJECT_ROOT if INFINILM_SVC_SRC was provided
    echo -e "${BLUE}Building from PROJECT_ROOT: ${PROJECT_ROOT}${NC}"
    build_binaries

    # Verify binaries were built from the correct location
    if [ "${using_external_source}" = "true" ]; then
        echo -e "${BLUE}Verifying binaries were built from external source...${NC}"
        if [ -f "${PROJECT_ROOT}/rust/target/release/infini-registry" ]; then
            echo -e "${GREEN}✓ Binary found at: ${PROJECT_ROOT}/rust/target/release/infini-registry${NC}"
            echo -e "${GREEN}✓ External source override confirmed - binaries built from: ${PROJECT_ROOT}${NC}"
        else
            echo -e "${YELLOW}⚠ Binary not found at expected location: ${PROJECT_ROOT}/rust/target/release/infini-registry${NC}"
        fi
    fi

    # Keep PROJECT_ROOT set to external source for install_binaries() if using external source
    # install_binaries() needs to copy from the correct location
    if [ "${using_external_source}" = "true" ]; then
        # Don't restore yet - install_binaries() needs the external PROJECT_ROOT
        echo -e "${BLUE}Keeping PROJECT_ROOT=${PROJECT_ROOT} for binary installation${NC}"
    else
        # Restore original PROJECT_ROOT if not using external source
        PROJECT_ROOT="${original_project_root}"
    fi

    # InfiniCore and InfiniLM should already be installed from Phase 1
    # If external source paths are provided, copy/mount them to override the Phase 1 repos
    # This allows using external repos instead of the ones cloned in Phase 1
    if [ -n "${INFINICORE_SRC:-}" ] || [ -n "${INFINILM_SRC:-}" ]; then
        echo -e "${BLUE}InfiniCore/InfiniLM external source paths provided - overriding Phase 1 repos...${NC}"

        # Resolve default paths to find where Phase 1 cloned the repos
        resolve_optional_repo_paths

        # Override InfiniCore if external source is provided
        if [ -n "${INFINICORE_SRC:-}" ] && [ -d "${INFINICORE_SRC}" ]; then
            local default_infinicore_path="${PROJECT_ROOT}/../InfiniCore"
            if [ "${INFINICORE_SRC}" != "${default_infinicore_path}" ] && [ -d "${default_infinicore_path}" ]; then
                echo -e "${BLUE}  Overriding InfiniCore from Phase 1: ${default_infinicore_path}${NC}"
                echo -e "${BLUE}  With external source: ${INFINICORE_SRC}${NC}"

                # Backup the original Phase 1 repo (optional, for safety)
                if [ -d "${default_infinicore_path}/.git" ]; then
                    echo -e "${BLUE}  Backing up Phase 1 InfiniCore to ${default_infinicore_path}.phase1-backup${NC}"
                    rm -rf "${default_infinicore_path}.phase1-backup" 2>/dev/null || true
                    mv "${default_infinicore_path}" "${default_infinicore_path}.phase1-backup" 2>/dev/null || true
                fi

                # Copy external repo to override Phase 1 location
                echo -e "${BLUE}  Copying external InfiniCore to ${default_infinicore_path}...${NC}"
                rm -rf "${default_infinicore_path}" 2>/dev/null || true
                cp -a "${INFINICORE_SRC}" "${default_infinicore_path}" || {
                    echo -e "${RED}Error: Failed to copy InfiniCore from ${INFINICORE_SRC}${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ InfiniCore overridden with external source${NC}"

                # Update INFINICORE_SRC to point to the overridden location
                INFINICORE_SRC="${default_infinicore_path}"
            else
                echo -e "${BLUE}  Using external InfiniCore directly: ${INFINICORE_SRC}${NC}"
            fi
        fi

        # Override InfiniLM if external source is provided
        if [ -n "${INFINILM_SRC:-}" ] && [ -d "${INFINILM_SRC}" ]; then
            local default_infinilm_path="${PROJECT_ROOT}/../InfiniLM"
            if [ "${INFINILM_SRC}" != "${default_infinilm_path}" ] && [ -d "${default_infinilm_path}" ]; then
                echo -e "${BLUE}  Overriding InfiniLM from Phase 1: ${default_infinilm_path}${NC}"
                echo -e "${BLUE}  With external source: ${INFINILM_SRC}${NC}"

                # Backup the original Phase 1 repo (optional, for safety)
                if [ -d "${default_infinilm_path}/.git" ]; then
                    echo -e "${BLUE}  Backing up Phase 1 InfiniLM to ${default_infinilm_path}.phase1-backup${NC}"
                    rm -rf "${default_infinilm_path}.phase1-backup" 2>/dev/null || true
                    mv "${default_infinilm_path}" "${default_infinilm_path}.phase1-backup" 2>/dev/null || true
                fi

                # Copy external repo to override Phase 1 location
                echo -e "${BLUE}  Copying external InfiniLM to ${default_infinilm_path}...${NC}"
                rm -rf "${default_infinilm_path}" 2>/dev/null || true
                cp -a "${INFINILM_SRC}" "${default_infinilm_path}" || {
                    echo -e "${RED}Error: Failed to copy InfiniLM from ${INFINILM_SRC}${NC}"
                    exit 1
                }
                echo -e "${GREEN}✓ InfiniLM overridden with external source${NC}"

                # Update INFINILM_SRC to point to the overridden location
                INFINILM_SRC="${default_infinilm_path}"
            else
                echo -e "${BLUE}  Using external InfiniLM directly: ${INFINILM_SRC}${NC}"
            fi
        fi

        # Now install/rebuild using the overridden repos
        echo -e "${BLUE}Installing/rebuilding InfiniCore/InfiniLM with overridden repos...${NC}"
        # Set INSTALL_PHASE to "build" to skip cloning (repos should exist from Phase 1 or override)
        INSTALL_PHASE=build
        install_infinicore_and_infinilm_optional
        unset INSTALL_PHASE
    else
        echo -e "${BLUE}InfiniCore/InfiniLM should be installed from Phase 1 - verifying...${NC}"
    fi
    verify_infinicore_and_infinilm

    # Install binaries (PROJECT_ROOT should still point to external source if used)
    install_binaries

    # Restore original PROJECT_ROOT after all operations that need it
    if [ "${using_external_source}" = "true" ]; then
        echo -e "${BLUE}Restoring original PROJECT_ROOT: ${original_project_root}${NC}"
        PROJECT_ROOT="${original_project_root}"
    fi

    # Setup scripts
    setup_scripts

    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Phase 2 Complete!${NC}"
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
