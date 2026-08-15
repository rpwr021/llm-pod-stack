#!/usr/bin/env bash
# Experimental CUDA SGLang profile. Requires an explicit model ID or local path.
set -euo pipefail

: "${MODEL:?Set MODEL to a Hugging Face model ID or local model directory}"
WORKSPACE="${WORKSPACE:-/workspace}"
STACK_DIR="${STACK_DIR:-$WORKSPACE/sglang-stack}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
PORT="${PORT:-30000}"
POD_PYTHON="${POD_PYTHON:-$(command -v python3)}"
MEM_FRACTION_STATIC="${MEM_FRACTION_STATIC:-0.85}"
CHUNKED_PREFILL_SIZE="${CHUNKED_PREFILL_SIZE:-2048}"
ENABLE_MTP="${ENABLE_MTP:-1}"

command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
mkdir -p "$STACK_DIR" "$UV_CACHE_DIR"
if ! "$POD_PYTHON" -c 'import sglang' >/dev/null 2>&1; then
  UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install --python "$POD_PYTHON" --system \
    --break-system-packages sglang
fi

cat >"$STACK_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SPEC_ARGS=()
if [[ "$ENABLE_MTP" == 1 ]]; then
  SPEC_ARGS=(
    --speculative-algorithm EAGLE
    --speculative-num-steps 3
    --speculative-eagle-topk 1
    --speculative-num-draft-tokens 4
  )
fi
exec "$POD_PYTHON" -m sglang.launch_server \\
  --model-path "$MODEL" --host 127.0.0.1 --port "$PORT" \\
  --trust-remote-code \\
  --mem-fraction-static "$MEM_FRACTION_STATIC" \\
  --attention-backend flashinfer \\
  --chunked-prefill-size "$CHUNKED_PREFILL_SIZE" \\
  --reasoning-parser qwen3 --tool-call-parser qwen3_coder \\
  --mamba-radix-cache-strategy extra_buffer_lazy \\
  "\${SPEC_ARGS[@]}"
EOF
chmod 700 "$STACK_DIR/start.sh"
nohup "$STACK_DIR/start.sh" >"$STACK_DIR/sglang.log" 2>&1 &
echo "SGLang is starting on http://127.0.0.1:$PORT (log: $STACK_DIR/sglang.log)"
