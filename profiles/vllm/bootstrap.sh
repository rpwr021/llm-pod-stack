#!/usr/bin/env bash
# Experimental CUDA vLLM profile. Requires an explicit Hugging Face model ID or local path.
set -euo pipefail

MODEL="${MODEL:-unsloth/Qwen3.8-27B-NVFP4}"
WORKSPACE="${WORKSPACE:-/workspace}"
STACK_DIR="${STACK_DIR:-$WORKSPACE/vllm-stack}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
# Model checkpoints must live on the persistent pod volume: Xet reconstruction
# can temporarily need more space than a 40 GB root filesystem provides.
HF_HOME="${HF_HOME:-$WORKSPACE/hf-cache}"
HF_XET_CACHE="${HF_XET_CACHE:-$HF_HOME/xet}"
PORT="${PORT:-8000}"
SPEC_TOKENS="${SPEC_TOKENS:-1}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.75}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
POD_PYTHON="${POD_PYTHON:-$(command -v python3)}"
TORCH_BACKEND="${TORCH_BACKEND:-cu129}"
REINSTALL_TORCH="${REINSTALL_TORCH:-0}"

command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$STACK_DIR" "$UV_CACHE_DIR" "$HF_HOME" "$HF_XET_CACHE"
if ! "$POD_PYTHON" -c 'import vllm' >/dev/null 2>&1 || [[ "$REINSTALL_TORCH" == 1 ]]; then
  # GPU pod images normally provide CUDA Torch/Jupyter already. Reuse that
  # runtime rather than making a second, multi-GB Torch virtual environment.
  reinstall_args=()
  # vLLM imports TorchAudio during startup.  Reinstall the matching CUDA wheel
  # alongside Torch so a prior base-image CUDA wheel cannot prevent launch.
  [[ "$REINSTALL_TORCH" == 1 ]] && reinstall_args=(--reinstall-package torch --reinstall-package torchaudio --reinstall-package torchvision)
  UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install --python "$POD_PYTHON" --system \
    --break-system-packages "${reinstall_args[@]}" vllm --torch-backend "$TORCH_BACKEND"
fi
VLLM_BIN="${VLLM_BIN:-$(command -v vllm || true)}"
[[ -n "$VLLM_BIN" ]] || { echo "vLLM executable was not installed" >&2; exit 1; }

cat >"$STACK_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export HF_XET_HIGH_PERFORMANCE=1
export HF_HOME="$HF_HOME"
export HF_XET_CACHE="$HF_XET_CACHE"
# FlashInfer 0.6.x misdetects Blackwell SM120 during sampler JIT.  Native
# PyTorch sampling avoids that startup crash; NVFP4 model kernels remain used.
export VLLM_USE_FLASHINFER_SAMPLER=0
# uv distributes the CUDA runtime across package-specific directories. Pod
# images can otherwise resolve an older system NVRTC first (which lacks SM120
# support on RTX 50-series GPUs), so put every matching wheel directory first.
for cuda_runtime in /usr/local/lib/python*/dist-packages/nvidia/*/lib /usr/local/lib/python*/dist-packages/nvidia/cu13/lib; do
  [[ -d "\$cuda_runtime" ]] && export LD_LIBRARY_PATH="\$cuda_runtime:\${LD_LIBRARY_PATH:-}"
done
exec "$VLLM_BIN" serve "$MODEL" \\
  --host 127.0.0.1 --port "$PORT" \\
  --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" --max-model-len "$MAX_MODEL_LEN" \\
  --kv-cache-dtype fp8 --enable-prefix-caching \\
  --speculative-config '{"method":"mtp","num_speculative_tokens":$SPEC_TOKENS}'
EOF
chmod 700 "$STACK_DIR/start.sh"
nohup "$STACK_DIR/start.sh" >"$STACK_DIR/vllm.log" 2>&1 &
echo "vLLM is starting on http://127.0.0.1:$PORT (log: $STACK_DIR/vllm.log)"
