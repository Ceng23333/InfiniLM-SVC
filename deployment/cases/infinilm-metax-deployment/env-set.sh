#! /bin/bash
echo "------------------------ env-set.sh ----------------------"

# Proxy settings (use environment variables if set, otherwise use defaults)
# These can be set via Docker build args or environment variables
if [ -n "${HTTP_PROXY:-}" ]; then
    export http_proxy="${HTTP_PROXY}"
    export HTTP_PROXY="${HTTP_PROXY}"
fi
if [ -n "${HTTPS_PROXY:-}" ]; then
    export https_proxy="${HTTPS_PROXY}"
    export HTTPS_PROXY="${HTTPS_PROXY}"
fi
if [ -n "${ALL_PROXY:-}" ]; then
    export all_proxy="${ALL_PROXY}"
    export ALL_PROXY="${ALL_PROXY}"
fi
if [ -n "${NO_PROXY:-}" ]; then
    export no_proxy="${NO_PROXY}"
    export NO_PROXY="${NO_PROXY}"
fi

# Uncomment and modify the line below if you want to hardcode proxy settings
# export https_proxy=http://127.0.0.1:7890;export http_proxy=http://127.0.0.1:7890;export all_proxy=socks5://127.0.0.1:7890

if [ -f /root/.xmake/profile ]; then
  # shellcheck disable=SC1091
source /root/.xmake/profile
fi
export XMAKE_ROOT=y

# INFINI_ROOT
export INFINI_ROOT=/root/.infini
export PATH=${PATH}:${INFINI_ROOT}/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$INFINI_ROOT/lib

# Rust/Cargo (from Phase 1 installation)
# Ensure cargo bin is in PATH for Phase 2 builds
if [ -d "${HOME}/.cargo/bin" ]; then
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi

# Conda Python library (needed for _infinicore.so)
if [ -d "/opt/conda/lib" ]; then
    export LD_LIBRARY_PATH=/opt/conda/lib:$LD_LIBRARY_PATH
fi

# PyPI mirror configuration (use tsinghua mirror)
export PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

# MACA/HPCC (must come before system MPI to ensure HPCC MPI is used)
export MACA_HOME=/opt/hpcc
export MACA_PATH=${MACA_HOME}
export HPCC_PATH=${MACA_PATH}
# HPCC provides its own MPI libraries with HPCC-specific extensions (MPIX_Query_hpcc_support)
# These must come before system MPI libraries to avoid symbol conflicts
# Prioritize HPCC's OpenMPI if available, otherwise use system OpenMPI
if [ -d "${MACA_PATH}/ompi/lib" ]; then
    export LD_LIBRARY_PATH="${MACA_PATH}/ompi/lib:${LD_LIBRARY_PATH:-}"
elif [ -d "/usr/lib64/openmpi/lib" ]; then
    export LD_LIBRARY_PATH="/usr/lib64/openmpi/lib:${LD_LIBRARY_PATH:-}"
fi
# Add other HPCC library paths
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:${MACA_PATH}/lib:${MACA_PATH}/htgpu_llvm/lib:${MACA_PATH}/ucx/lib"
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/include/hcr

# cu-bridge
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/tools/cu-bridge/include

echo "------------------------ env-set.sh success ----------------------"
