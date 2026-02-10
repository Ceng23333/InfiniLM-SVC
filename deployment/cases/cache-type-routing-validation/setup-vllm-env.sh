#!/usr/bin/env bash
# Setup conda environment for vLLM benchmarks (no vLLM build required)
# Just installs dependencies and sets up PYTHONPATH to run benchmarks directly

set -euo pipefail

VLLM_DIR="${VLLM_DIR:-/home/zenghua/repos/vllm}"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-vllm-bench-local}"

echo "=========================================="
echo "Setting up vLLM benchmark environment"
echo "=========================================="
echo "vLLM directory: ${VLLM_DIR}"
echo "Conda environment: ${CONDA_ENV_NAME}"
echo ""
echo "Note: This will NOT build vLLM. We'll run the benchmark script directly."
echo ""

if [ ! -d "${VLLM_DIR}" ]; then
  echo "Error: VLLM_DIR does not exist: ${VLLM_DIR}"
  echo "  Set VLLM_DIR to point to your vLLM repository"
  exit 1
fi

# Check if conda is available
if ! command -v conda &> /dev/null; then
  echo "Error: conda command not found. Please install conda first."
  exit 1
fi

# Create conda environment if it doesn't exist
if conda env list | grep -q "^${CONDA_ENV_NAME} "; then
  echo "Conda environment '${CONDA_ENV_NAME}' already exists"
  echo "Activating environment..."
  eval "$(conda shell.bash hook)"
  conda activate "${CONDA_ENV_NAME}"
else
  echo "Creating conda environment '${CONDA_ENV_NAME}'..."
  eval "$(conda shell.bash hook)"
  conda create -n "${CONDA_ENV_NAME}" python=3.10 -y
  conda activate "${CONDA_ENV_NAME}"
fi

echo ""
echo "Installing minimal dependencies for vLLM benchmarks..."
echo "Note: We'll install dependencies but skip vLLM build. Warnings about missing"
echo "      compiled extensions (vllm._C, Triton) are expected and can be ignored."
echo ""

cd "${VLLM_DIR}"

# Install PyTorch first (CPU version is fine for benchmarks)
echo "Installing PyTorch (CPU version)..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu || \
  pip install torch torchvision torchaudio || echo "Warning: PyTorch installation may have failed"

# Install only the dependencies needed for benchmarks (no vLLM build)
if [ -f "requirements/common.txt" ]; then
  echo "Installing common dependencies..."
  pip install -r requirements/common.txt || echo "Warning: Some dependencies may have failed"
fi

# Install benchmark-specific dependencies
echo "Installing benchmark dependencies (pandas, matplotlib, seaborn, datasets)..."
pip install pandas matplotlib seaborn datasets || echo "Warning: Some benchmark dependencies may have failed"

echo ""
echo "✅ vLLM benchmark environment setup complete!"
echo ""
echo "To use this environment:"
echo "  conda activate ${CONDA_ENV_NAME}"
echo "  export PYTHONPATH=${VLLM_DIR}:\$PYTHONPATH"
echo "  cd ${VLLM_DIR}"
echo "  python -m vllm.benchmarks.serve --help"
echo ""
echo "Note: vLLM is NOT installed. The benchmark scripts will run directly"
echo "      from the vLLM source directory using PYTHONPATH."
