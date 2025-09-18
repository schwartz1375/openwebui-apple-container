# Apple Containerization

This repo provides a concise guide and helper script for running Open-WebUI using Apple’s first‑party `container` tool on Apple silicon Macs.

- Reference article: `AppleContainerization.md`
- Example script: `openwebui-apple-container.sh`

## Why use this?

- First‑party runtime: Uses Apple’s `container` for lightweight, secure isolation.
- Apple silicon optimized: Great performance without third‑party hypervisors.
- Local + private: Pair Open‑WebUI with a local Ollama for private inference.
- Simple persistence: Stores UI data on the host for easy upgrades.

## Requirements

- macOS 26 or later.
- Apple `container` installed from Apple’s [GitHub](https://github.com/schwartz1375/openwebui-apple-container).
- Ollama installed on the host (and configured to accept LAN connections).

See `AppleContainerization.md` for background, trade‑offs, and networking context.

## Quick start (script)

The script wraps common tasks for running Open‑WebUI with Apple `container` while pointing it at an Ollama instance on your Mac.

```
./openwebui-apple-container.sh run    # create/start container
./openwebui-apple-container.sh update # pull image and recreate if changed
./openwebui-apple-container.sh logs   # follow logs
./openwebui-apple-container.sh test   # quick connectivity test to Ollama
```

Optional environment overrides:

```
OLLAMA_URL="http://<IP>:11434" 
OWUI_NAME="open-webui"
OWUI_PORTS="3000:8080"                       # host:container
OWUI_DATA="$HOME/.open-webui"               # persistent data dir
OWUI_IMAGE="ghcr.io/open-webui/open-webui:main"
```

After `run`, open `http://localhost:3000`.

## Networking and security

- Apple `container` isolates containers in a lightweight VM; they cannot reach the host loopback (`127.0.0.1`). Configure Ollama to listen on your Mac’s LAN address.
- In the Ollama app, enable “Expose Ollama to the network” (or run `OLLAMA_HOST=0.0.0.0 ollama serve`).
- Exposing Ollama means other devices on your LAN may reach it. Use the macOS firewall to restrict access if needed.

## Related doc

Read `AppleContainerization.md` for a short overview of Apple `container`, a sample manual `container run` command, and notes on current limitations and future outlook.
