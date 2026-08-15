#!/usr/bin/env bash
# Private Open WebUI gateway for the llama.cpp router, vLLM, and SGLang profiles.
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
STACK_DIR="${STACK_DIR:-$WORKSPACE/open-webui}"
DATA_DIR="${DATA_DIR:-$STACK_DIR/data}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
PORT="${PORT:-3000}"

command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
POD_PYTHON="${POD_PYTHON:-$(command -v python3)}"
mkdir -p "$DATA_DIR" "$UV_CACHE_DIR"
if ! "$POD_PYTHON" -c 'import open_webui' >/dev/null 2>&1; then
  UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install --python "$POD_PYTHON" --system \
    --break-system-packages open-webui
fi

SECRET_FILE="$DATA_DIR/.webui_secret_key"
if [[ ! -s "$SECRET_FILE" ]]; then
  python3 -c 'import secrets; print(secrets.token_urlsafe(48))' >"$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi

cat >"$STACK_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export DATA_DIR="$DATA_DIR"
export WEBUI_SECRET_KEY="\$(cat "$SECRET_FILE")"
export WEBUI_NAME="LLM Pod Stack"
export ENABLE_OPENAI_API=True
export ENABLE_OPENAI_API_PASSTHROUGH=False
export ENABLE_BASE_MODELS_CACHE=True
export OPENAI_API_BASE_URLS="http://127.0.0.1:8080/v1;http://127.0.0.1:8000/v1;http://127.0.0.1:30000/v1"
export OPENAI_API_KEYS="none;none;none"
export OPENAI_API_CONFIGS='{"0":{"enable":true,"prefix_id":"llama"},"1":{"enable":true,"prefix_id":"vllm"},"2":{"enable":true,"prefix_id":"sglang"}}'
exec "$POD_PYTHON" -m open_webui serve --host 127.0.0.1 --port "$PORT"
EOF
chmod 700 "$STACK_DIR/start.sh"
pkill -f "$STACK_DIR/start.sh" 2>/dev/null || true
nohup "$STACK_DIR/start.sh" >"$STACK_DIR/open-webui.log" 2>&1 &
echo "Open WebUI is starting on http://127.0.0.1:$PORT (log: $STACK_DIR/open-webui.log)"
