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

# --- helper: check container CLI/apiserver version compatibility ---
check_container_version() {
  local cli_ver api_ver
  cli_ver="$(container --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)"
  api_ver="$(container system status 2>/dev/null | grep 'container-apiserver version' | grep -o '[0-9]\+\.[0-9]\+' | head -1)"
  
  if [[ -n "$cli_ver" && -n "$api_ver" && "$cli_ver" != "$api_ver" ]]; then
    echo "WARNING: Container CLI version ($cli_ver) doesn't match apiserver version ($api_ver)"
    echo "This may cause port publishing issues. Consider running:"
    echo "  container system stop && container system start"
    echo ""
  fi
}

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

# --- helper: quick HTTP reachability check (exit 0 on success) ---
http_ok() {
  # $1 = URL
  if command -v curl >/dev/null 2>&1; then
    curl -s -f --connect-timeout 2 --max-time 5 "$1" >/dev/null 2>&1
  else
    python - <<PY >/dev/null 2>&1
import urllib.request, sys
u="${1}"
try:
    with urllib.request.urlopen(u, timeout=2) as r:
        sys.exit(0)
except Exception:
    sys.exit(1)
PY
  fi
}

# --- helper: check page looks like Open WebUI ---
looks_like_openwebui() {
  # $1 = URL
  python - <<PY >/dev/null 2>&1
import urllib.request, sys, re
u="${1}"
try:
    with urllib.request.urlopen(u, timeout=2) as r:
        body = r.read(4096).decode('utf-8', 'ignore')
        if re.search(r"open[-_\s]?webui", body, re.I):
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PY
}

# --- helper: normalize publish mapping ---
# Input format: "host:container" (single mapping). Optional OWUI_PUBLISH_STYLE
#   OWUI_PUBLISH_STYLE=host:container     (default)
#   OWUI_PUBLISH_STYLE=container:host
publish_arg() {
  # Only support single mapping like "3000:8080" for now
  local spec="$1" h c
  spec="${spec%%,*}"
  [[ -z "$spec" ]] && spec="3000:8080"
  h="${spec%%:*}"; c="${spec##*:}"
  [[ "$h" =~ ^[0-9]+$ ]] || h=3000
  [[ "$c" =~ ^[0-9]+$ ]] || c=8080
  case "${OWUI_PUBLISH_STYLE:-host:container}" in
    host:container)    printf '%s:%s' "$h" "$c" ;;
    container:host)    printf '%s:%s' "$c" "$h" ;;
    *)                 printf '%s:%s' "$h" "$c" ;;
  esac
}

# --- helper: ensure Apple container system is running ---
ensure_container_system() {
  if container system status >/dev/null 2>&1; then
    return
  fi
  echo "Apple Container system is not running; starting..."
  container system start >/dev/null 2>&1 || container system start
  for i in {1..15}; do
    if container system status >/dev/null 2>&1; then
      echo "Apple Container system started."
      return
    fi
    sleep 1
  done
  echo "ERROR: Apple Container system did not reach running state."
  exit 1
}

run_container() {
  ensure_container_system
  check_container_version
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
  local publish
  publish="$(publish_arg "$OWUI_PORTS")"
  echo "Publishing ports: $publish (from '$OWUI_PORTS', style: ${OWUI_PUBLISH_STYLE:-host:container})"
  
  container run \
    --detach \
    --name "$OWUI_NAME" \
    --publish "$publish" \
    --volume "$OWUI_DATA:/app/backend/data" \
    --env OLLAMA_BASE_URL="$url" \
    --memory 2G \
    --cpus 2 \
    "$OWUI_IMAGE"

  # Try to detect which host port is actually serving, to handle
  # potential publish order changes between container versions.
  local host_p="${OWUI_PORTS%%:*}" cont_p="${OWUI_PORTS##*:}" chosen=""
  echo "Waiting for Open-WebUI to become reachable..."
  for i in {1..300}; do
    for p in "$host_p" "$cont_p"; do
      [[ -z "$p" || ! "$p" =~ ^[0-9]+$ ]] && continue
      if http_ok "http://127.0.0.1:${p}/" || http_ok "http://localhost:${p}/"; then
        chosen="$p"
        looks_like_openwebui "http://127.0.0.1:${p}/" >/dev/null 2>&1 || true
        break 2
      fi
    done
    if (( i % 30 == 0 )); then 
      echo "... still waiting on ports ${host_p}/${cont_p} (${i}s elapsed)"
      # Show last few log lines to indicate progress
      container logs open-webui | tail -3 | sed 's/^/    /'
    fi
    sleep 1
  done

  if [[ -n "$chosen" ]]; then
    echo "Started. Visit http://localhost:${chosen}"
  else
    echo "Unable to confirm readiness within timeout."
    echo "Container status:"
    container inspect "$OWUI_NAME" 2>/dev/null | python -m json.tool 2>/dev/null | head -20 || true
    echo "Try: http://localhost:${host_p} or http://localhost:${cont_p}"
    echo "For detailed status: $0 logs"
  fi
}

update_container() {
  ensure_container_system
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
  if isinstance(data, list) and data:
    img = data[0]
  else:
    img = data
  # try multiple digest locations
  if "digest" in img:
    print(img["digest"])
  elif "variants" in img and img["variants"]:
    v = img["variants"][0]
    if "digest" in v:
      print(v["digest"])
  elif "id" in img:
    print(img["id"])
except Exception: pass
PY
  )"

  # current container image digest (if running)
  current="$(container inspect "$OWUI_NAME" 2>/dev/null | \
    python - <<'PY' 2>/dev/null || true
import sys, json
try:
  data=json.load(sys.stdin)
  if isinstance(data, list) and data:
    container_info = data[0]
  else:
    container_info = data
  img = container_info.get("image") or {}
  if "digest" in img:
    print(img["digest"])
  elif "id" in img:
    print(img["id"])
except Exception: pass
PY
  )"

  if [[ -n "$current" && -n "$remote" && "$current" == "$remote" ]]; then
    echo "Open-WebUI is up to date ($remote)"
    exit 0
  fi

  if [[ -z "$remote" ]]; then
    echo "Warning: Could not determine image digest, forcing update"
    remote="unknown"
  fi
  
  echo "Updating container to $remote"
  run_container
  echo "Pruning old images..."
  # container 0.6.0 removed '-f' from 'image prune' and may hang
  timeout 30 container image prune >/dev/null 2>&1 || true
}

logs_container() {
  ensure_container_system
  container logs -f "$OWUI_NAME"
}

test_connectivity() {
  ensure_container_system
  local url="${OLLAMA_URL:-$(pick_host_url)}"
  echo "Testing Ollama at: $url"
  echo "First 200 bytes of /api/tags:"
  http_get_head "${url%/}/api/tags" | sed -e 's/^{.*/& .../;200q' || true
}

stop_container() {
  ensure_container_system
  echo "Stopping Open-WebUI container..."
  container stop "$OWUI_NAME" 2>/dev/null || echo "Container '$OWUI_NAME' not running"
  container rm "$OWUI_NAME" 2>/dev/null || echo "Container '$OWUI_NAME' not found"
  echo "Stopped and removed '$OWUI_NAME'"
}

case "${1:-run}" in
  run)    run_container ;;
  update) update_container ;;
  logs|log)   logs_container ;;
  test)   test_connectivity ;;
  stop|kill)  stop_container ;;
  *)
    echo "Usage: $0 {run|update|logs|test|stop}"
    exit 1
    ;;
esac
