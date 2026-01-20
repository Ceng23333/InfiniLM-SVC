#! /bin/bash
echo "------------------------ env-set.sh ----------------------"
# export https_proxy=http://127.0.0.1:7890;export http_proxy=http://127.0.0.1:7890;export all_proxy=socks5://127.0.0.1:7890

source /root/.xmake/profile
export XMAKE_ROOT=y

# INFINI_ROOT
export INFINI_ROOT=/root/.infini
export PATH=${PATH}:${INFINI_ROOT}/bin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$INFINI_ROOT/lib

# Conda Python library (needed for _infinicore.so)
if [ -d "/opt/conda/lib" ]; then
    export LD_LIBRARY_PATH=/opt/conda/lib:$LD_LIBRARY_PATH
fi

# MACA
export MACA_HOME=/opt/hpcc
export MACA_PATH=${MACA_HOME}
export HPCC_PATH=${MACA_PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${MACA_PATH}/lib:${MACA_PATH}/htgpu_llvm/lib
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/include/hcr

# cu-bridge
export C_INCLUDE_PATH=${C_INCLUDE_PATH}:${MACA_PATH}/tools/cu-bridge/include

echo "------------------------ env-set.sh success ----------------------"
