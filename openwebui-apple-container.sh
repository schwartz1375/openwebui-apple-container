#!/usr/bin/env bash
set -euo pipefail

# OpenWebUI via Apple "container" CLI + Ollama on host
# Usage:
#   ./openwebui-apple-container.sh run         # create/start container
#   ./openwebui-apple-container.sh update      # pull image, recreate if changed
#   ./openwebui-apple-container.sh logs        # follow logs
#   ./openwebui-apple-container.sh test        # quick connectivity test to Ollama
#
# Optional env overrides:
#   OLLAMA_URL="http://<IP>:11434"       # ipconfig getifaddr en0
#   OWUI_NAME="open-webui"
#   OWUI_PORTS="3000:8080"
#   OWUI_DATA="$HOME/.open-webui"
#   OWUI_IMAGE="ghcr.io/open-webui/open-webui:main"

OWUI_NAME="${OWUI_NAME:-open-webui}"
OWUI_PORTS="${OWUI_PORTS:-3000:8080}"
OWUI_DATA="${OWUI_DATA:-$HOME/.open-webui}"
OWUI_IMAGE="${OWUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"

# --- helper: pick a stable host URL if none provided ---
pick_host_url() {
  # Prefer numeric LAN IP (works inside container). Fallback to mDNS, then loopback.
  local mdns host ip
  ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  [[ -z "$ip" ]] && ip="$(ipconfig getifaddr en7 2>/dev/null || true)"
  if [[ -n "$ip" ]]; then
    echo "http://${ip}:11434"
    return
  fi
  mdns="$(scutil --get LocalHostName 2>/dev/null || true)"
  if [[ -n "${mdns:-}" ]]; then
    host="${mdns}.local"
    if ping -c1 -t1 "$host" >/dev/null 2>&1; then
      echo "http://${host}:11434"
      return
    fi
  fi
  # Last resort: loopback (unlikely to work from inside container)
  echo "http://127.0.0.1:11434"
}

# --- helper: check Ollama binding ---
check_ollama_bound() {
  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:11434 -sTCP:LISTEN -nP 2>/dev/null | grep -q "127.0.0.1:11434"; then
      echo "WARN: Ollama is listening on 127.0.0.1 only."
      echo "Enable 'Expose Ollama to the network' in the Ollama app settings,"
      echo "or run:  OLLAMA_HOST=0.0.0.0 ollama serve"
      return 1
    fi
  fi
  return 0
}

# --- helper: quick HTTP GET without curl/wget (uses Python stdlib) ---
http_get_head() {
  # $1 = URL
  python - <<PY 2>/dev/null || true
import urllib.request, sys
u="${1}"
try:
    with urllib.request.urlopen(u, timeout=5) as r:
        b=r.read(200)
        sys.stdout.buffer.write(b)
except Exception as e:
    print("ERROR:", e)
PY
}

run_container() {
  local url="${OLLAMA_URL:-$(pick_host_url)}"
  mkdir -p "$OWUI_DATA"

  echo "Ollama URL: $url"
  check_ollama_bound || true
  if [[ "$url" == http://*.local:* || "$url" == http://*.local ]]; then
    echo "NOTE: Using mDNS hostname ($url). Some containers cannot resolve .local."
    echo "      If models do not appear in Open-WebUI, re-run with:"
    echo "      OLLAMA_URL=\"http://\$(ipconfig getifaddr en0):11434\" $0 run"
  fi
  if [[ "$url" == http://127.0.0.1:* || "$url" == http://127.0.0.1 ]]; then
    echo "WARN: Using 127.0.0.1 will not be reachable from the container."
    echo "      Set OLLAMA to listen on 0.0.0.0 and use your LAN IP."
  fi

  echo "Stopping and removing any existing '$OWUI_NAME'..."
  container stop "$OWUI_NAME" >/dev/null 2>&1 || true
  container rm "$OWUI_NAME" >/dev/null 2>&1 || true

  echo "Starting Open-WebUI..."
  container run \
    --detach \
    --name "$OWUI_NAME" \
    --publish "$OWUI_PORTS" \
    --volume "$OWUI_DATA:/app/backend/data" \
    --env OLLAMA_BASE_URL="$url" \
    "$OWUI_IMAGE"

  echo "Started. Visit http://localhost:${OWUI_PORTS%%:*}"
}

update_container() {
  # pull latest image and recreate if digest changed
  echo "Pulling: $OWUI_IMAGE"
  container image pull "$OWUI_IMAGE" >/dev/null

  # remote digest
  local remote current
  remote="$(container image inspect "$OWUI_IMAGE" 2>/dev/null | \
    python - <<'PY' 2>/dev/null || true
import sys, json
try:
  data=json.load(sys.stdin)
  # try variants[0].digest then top-level digest
  v=data[0].get("variants") or []
  if v and "digest" in v[0]:
    print(v[0]["digest"]); raise SystemExit
  if "digest" in data[0]:
    print(data[0]["digest"])
except Exception: pass
PY
  )"

  # current container image digest (if running)
  current="$(container inspect "$OWUI_NAME" 2>/dev/null | \
    python - <<'PY' 2>/dev/null || true
import sys, json
try:
  data=json.load(sys.stdin)
  print((data[0].get("image") or {}).get("digest",""))
except Exception: pass
PY
  )"

  if [[ -n "$current" && -n "$remote" && "$current" == "$remote" ]]; then
    echo "Open-WebUI is up to date ($remote)"
    exit 0
  fi

  echo "Updating container to $remote"
  run_container
  echo "Pruning old images..."
  container image prune -f >/dev/null || true
}

logs_container() {
  container logs -f "$OWUI_NAME"
}

test_connectivity() {
  local url="${OLLAMA_URL:-$(pick_host_url)}"
  echo "Testing Ollama at: $url"
  echo "First 200 bytes of /api/tags:"
  http_get_head "${url%/}/api/tags" | sed -e 's/^{.*/& .../;200q' || true
}

case "${1:-run}" in
  run)    run_container ;;
  update) update_container ;;
  logs)   logs_container ;;
  test)   test_connectivity ;;
  *)
    echo "Usage: $0 {run|update|logs|test}"
    exit 1
    ;;
esac
