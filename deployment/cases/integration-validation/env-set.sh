#! /bin/bash
echo "------------------------ env-set.sh ----------------------"
# Canonical env-set for the integration-validation deployment case.
# Keep this file identical across install/runtime for reproducibility.

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

# MACA
export MACA_HOME=/opt/hpcc
export MACA_PATH=${MACA_HOME}
export HPCC_PATH=${MACA_PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MACA_PATH}/lib:${MACA_PATH}/htgpu_llvm/lib
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/include/hcr

# cu-bridge
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/tools/cu-bridge/include

echo "------------------------ env-set.sh success ----------------------"
