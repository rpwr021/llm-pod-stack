#!/usr/bin/env bash
# Bootstraps the tested Qwen 3.8 llama-router stack on a new Linux GPU pod.
#
# On a fresh pod it installs the official Llama.app unified router binary.
# Then, on the pod:
#   HF_TOKEN=... bash bootstrap_qwen38_llama_router.sh
#
# The services bind to 127.0.0.1 only.  From the local Mac, forward the UI:
#   ssh -N -L 9932:127.0.0.1:8080 -p POD_PORT root@POD_HOST -i ~/.ssh/YOUR_PRIVATE_KEY

set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
STACK_DIR="${STACK_DIR:-${WORKSPACE}/llama-router}"
MODEL_REPO="${MODEL_REPO:-unsloth/Qwen3.8-27B-GGUF}"
MODEL_FILE="${MODEL_FILE:-Qwen3.8-27B-UD-Q4_K_XL.gguf}"
MMPROJ_FILE="${MMPROJ_FILE:-mmproj-BF16.gguf}"
MODEL_DIR="${MODEL_DIR:-${WORKSPACE}/models/Qwen3.8-27B-GGUF}"
LLAMA_BIN="${LLAMA_BIN:-/root/.llama-app/llama}"
SEARX_DIR="${SEARX_DIR:-${WORKSPACE}/searxng}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/uv-cache}"
HF_XET_CACHE="${HF_XET_CACHE:-/tmp/hf-xet}"
ROUTER_PORT="${ROUTER_PORT:-8080}"
SEARX_PORT="${SEARX_PORT:-8889}"
MTP_DEPTH="${MTP_DEPTH:-3}"
POD_PYTHON="${POD_PYTHON:-$(command -v python3)}"
PROFILE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_MCP="$PROFILE_DIR/../../shared/mcp/web_search_mcp.py"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command git
require_command python3
require_command curl

if [[ ! -x "$LLAMA_BIN" ]]; then
  echo "Installing the official Llama.app router binary..."
  curl -LsSf https://llama.app/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
if [[ ! -x "$LLAMA_BIN" ]]; then
  cat >&2 <<EOF
Llama.app installation did not create $LLAMA_BIN.
Set LLAMA_BIN to a compatible unified llama binary and rerun.
EOF
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
require_command uv

mkdir -p "$STACK_DIR" "$MODEL_DIR" "$UV_CACHE_DIR" "$HF_XET_CACHE"

if [[ ! -d "$SEARX_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/searxng/searxng.git "$SEARX_DIR"
fi

UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install --python "$POD_PYTHON" --system \
  --break-system-packages 'huggingface_hub[hf_xet]' mcp lxml requests msgspec setuptools
# SearXNG imports msgspec while its editable build metadata is evaluated.
UV_CACHE_DIR="$UV_CACHE_DIR" uv pip install --python "$POD_PYTHON" --system \
  --break-system-packages --no-build-isolation -e "$SEARX_DIR"

export HF_XET_HIGH_PERFORMANCE=1
export HF_XET_CACHE
if [[ -n "${HF_TOKEN:-}" ]]; then
  export HF_TOKEN
fi

if [[ ! -s "$MODEL_DIR/$MODEL_FILE" ]]; then
  hf download "$MODEL_REPO" "$MODEL_FILE" \
    --local-dir "$MODEL_DIR" --max-workers 8
fi
if [[ ! -s "$MODEL_DIR/$MMPROJ_FILE" ]]; then
  hf download "$MODEL_REPO" "$MMPROJ_FILE" \
    --local-dir "$MODEL_DIR" --max-workers 8
fi

cat >"$STACK_DIR/models.ini" <<EOF
[qwen3.8-27b-mtp]
model = $MODEL_DIR/$MODEL_FILE
mmproj = $MODEL_DIR/$MMPROJ_FILE
n-gpu-layers = 99
ctx-size = 32768
flash-attn = on
batch-size = 2048
ubatch-size = 512
parallel = 1
jinja = true
reasoning = auto
spec-type = draft-mtp
spec-draft-n-max = $MTP_DEPTH
spec-draft-p-min = 0.0
spec-draft-backend-sampling = false
EOF

mkdir -p "$STACK_DIR/searxng"
SEARX_SECRET="$($POD_PYTHON -c 'import secrets; print(secrets.token_hex(32))')"
cat >"$STACK_DIR/searxng/settings.yml" <<EOF
use_default_settings: true
general:
  instance_name: pod-searxng
server:
  bind_address: 127.0.0.1
  port: $SEARX_PORT
  secret_key: $SEARX_SECRET
  limiter: false
search:
  formats:
    - html
    - json
EOF

[[ -f "$SHARED_MCP" ]] || { echo "Missing shared MCP server: $SHARED_MCP" >&2; exit 1; }

cat >"$STACK_DIR/mcp-servers.json" <<EOF
{"mcpServers":{"pod_web_search":{"command":"$POD_PYTHON","args":["$SHARED_MCP"]}}}
EOF

cat >"$STACK_DIR/start-searxng.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export SEARXNG_SETTINGS_PATH="$STACK_DIR/searxng/settings.yml"
exec "$POD_PYTHON" -m searx.webapp
EOF

cat >"$STACK_DIR/start-router.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$LLAMA_BIN" serve \\
  --models-preset "$STACK_DIR/models.ini" \\
  --models-max 1 \\
  --models-autoload \\
  --mcp-servers-config "$STACK_DIR/mcp-servers.json" \\
  --ui-mcp-proxy \\
  --tools get_datetime \\
  --perf --metrics \\
  --host 127.0.0.1 --port "$ROUTER_PORT"
EOF

cat >"$STACK_DIR/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$STACK_DIR/logs"
pkill -f "$STACK_DIR/start-searxng.sh" 2>/dev/null || true
pkill -f "$LLAMA_BIN serve --models-preset $STACK_DIR/models.ini" 2>/dev/null || true
nohup "$STACK_DIR/start-searxng.sh" >"$STACK_DIR/logs/searxng.log" 2>&1 &
nohup "$STACK_DIR/start-router.sh" >"$STACK_DIR/logs/router.log" 2>&1 &
echo "Router: http://127.0.0.1:$ROUTER_PORT"
echo "MTP depth: $MTP_DEPTH"
EOF
chmod 700 "$STACK_DIR"/*.sh

"$STACK_DIR/start.sh"
echo
echo "Setup complete. Wait for the model to load, then open the forwarded local URL."
echo "Status: curl -s http://127.0.0.1:$ROUTER_PORT/v1/models"
