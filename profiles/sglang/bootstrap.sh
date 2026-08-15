#!/usr/bin/env bash
# Experimental CUDA SGLang profile. Requires an explicit model ID or local path.
set -euo pipefail

: "${MODEL:?Set MODEL to a Hugging Face model ID or local model directory}"
WORKSPACE="${WORKSPACE:-/workspace}"
STACK_DIR="${STACK_DIR:-$WORKSPACE/sglang-stack}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
PORT="${PORT:-30000}"
POD_PYTHON="${POD_PYTHON:-$(command -v python3)}"

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
exec "$POD_PYTHON" -m sglang.launch_server \\
  --model-path "$MODEL" --host 127.0.0.1 --port "$PORT"
EOF
chmod 700 "$STACK_DIR/start.sh"
nohup "$STACK_DIR/start.sh" >"$STACK_DIR/sglang.log" 2>&1 &
echo "SGLang is starting on http://127.0.0.1:$PORT (log: $STACK_DIR/sglang.log)"
