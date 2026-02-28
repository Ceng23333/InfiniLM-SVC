# >>> xmake >>>
test -f "/root/.xmake/profile" && source "/root/.xmake/profile"
# <<< xmake <<<

export XMAKE_ROOT=y

export INFINI_ROOT="$HOME/.infini"
export LD_LIBRARY_PATH="$INFINI_ROOT/lib:$LD_LIBRARY_PATH"

export PYTHONPATH="$HOME/.infini/lib":$PYTHONPATH

export XMAKE_MAIN_REPO=https://gitee.com/crapromer/xmake-repo

# CUTLASS_HOME: optional, only set if exists
if [ -d "/home/wuwei/cutlass/include" ]; then
  export CUTLASS_HOME=/home/wuwei/cutlass/include/
  export PATH=$CUTLASS_HOME:$PATH
fi

# Python include path: try common locations
if [ -d "/usr/include/python3.12" ]; then
  export CPLUS_INCLUDE_PATH="/usr/include/python3.12:${CPLUS_INCLUDE_PATH:-}"
elif [ -d "/opt/conda/include/python3.12" ]; then
  export CPLUS_INCLUDE_PATH="/opt/conda/include/python3.12:${CPLUS_INCLUDE_PATH:-}"
fi

# Remove duplicates and empty paths from LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$(echo "$LD_LIBRARY_PATH" | tr ':' '\n' | grep -v '^$' | awk '!seen[$0]++' | paste -sd: -)
