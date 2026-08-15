#!/usr/bin/env bash
# Select a serving profile. Pass the profile as $1 or set PROFILE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:-${PROFILE:-llama-router}}"

case "$PROFILE" in
  llama-router) exec "$ROOT/profiles/llama-router/bootstrap.sh" ;;
  open-webui) exec "$ROOT/profiles/open-webui/bootstrap.sh" ;;
  vllm) exec "$ROOT/profiles/vllm/bootstrap.sh" ;;
  sglang) exec "$ROOT/profiles/sglang/bootstrap.sh" ;;
  *)
    echo "Unknown profile: $PROFILE" >&2
    echo "Available profiles: llama-router, open-webui, vllm, sglang" >&2
    exit 2
    ;;
esac
