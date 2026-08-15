#!/usr/bin/env bash
# Repeatedly reload the Qwen preset at each MTP cap and emit server timings.
set -euo pipefail

STACK_DIR="${STACK_DIR:-/workspace/llama-router}"
PORT="${ROUTER_PORT:-8080}"
MODEL="${MODEL:-qwen3.8-27b-mtp}"
DEPTHS="${DEPTHS:-1 2 3 4 5}"
PROMPT='Write a concise Python function that validates an email address, then explain its edge cases.'

for depth in $DEPTHS; do
  sed -i "s/^spec-draft-n-max = .*/spec-draft-n-max = $depth/" "$STACK_DIR/models.ini"
  pkill -f "$STACK_DIR/models.ini" 2>/dev/null || true
  nohup "$STACK_DIR/start-router.sh" >"$STACK_DIR/logs/router.log" 2>&1 &

  for _ in $(seq 1 30); do
    status="$(curl -s "http://127.0.0.1:$PORT/v1/models" || true)"
    if grep -qE '"value":"(ready|loaded)"' <<<"$status"; then
      break
    fi
    sleep 3
  done

  curl -s "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}],\"temperature\":0,\"max_tokens\":128,\"stream\":false}" \
    | python3 -c 'import json,sys; t=json.load(sys.stdin)["timings"]; print({"tok_s":t["predicted_per_second"],"draft":t["draft_n"],"accepted":t["draft_n_accepted"]})'
done
