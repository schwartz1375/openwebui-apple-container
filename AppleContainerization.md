<h1 style="text-align: center;">macOS 26 + Apple Container: A New Way to Host Open-WebUI</h1>  
<p style="text-align: center;">Matthew Schwartz</p>  
<p style="text-align: center;">September 15, 2025</p>  

Apple introduced **Container** with macOS 26 — a first-party way to run Linux containers directly on Apple Silicon. It brings secure isolation and Apple-optimized performance without relying on Docker or OrbStack.

📌 **Note:** Container is supported starting with macOS 26, but it does **not** come preinstalled. You’ll need to download and install the signed binary from Apple’s GitHub: [https://github.com/apple/container](https://github.com/apple/container).

---

### What Apple Says

Apple describes Container as:

> *“a tool for creating and running Linux containers using lightweight virtual machines on a Mac.”* ([Apple GitHub](https://github.com/apple/container))

In its developer announcement, Apple also noted:

> *“The Containerization framework enables developers to create, download, or run Linux container images directly on Mac. It’s built on an open source framework optimized for Apple silicon and provides secure isolation between container images.”* ([Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-supercharges-its-tools-and-technologies-for-developers/))

The key point is secure isolation and Apple Silicon optimization delivered through a first-party tool.

---

### Run Open-WebUI with Apple Container

```bash
# Create a persistent host dir (since named volumes aren't fully supported yet)
mkdir -p "$HOME/.open-webui"

# Replace <YOUR_IP> with: ipconfig getifaddr en0   # or relevant interface
IP="$(ipconfig getifaddr en0)"

container run \
  --detach \
  --name open-webui \
  --publish 3000:8080 \
  --volume "$HOME/.open-webui:/app/backend/data" \
  --env OLLAMA_BASE_URL="http://$IP:11434" \
  --memory 2G \
  --cpus 2 \
  ghcr.io/open-webui/open-webui:main
```

📌 **Container 0.6.0 Note:** Apple Container 0.6.0 changed from `--port` to `--publish` for port mapping. The example above uses the newer syntax. For older versions (0.5.0), replace `--publish` with `--port`.

📌 **Important:** In the Ollama app settings, enable *“Expose Ollama to the network”*.

By default Ollama only listens on `127.0.0.1`. Apple’s `container` runtime isolates containers in their own lightweight VM, so they cannot reach the host’s loopback interface. Exposing Ollama makes it available on your Mac’s LAN IP (for example, `http://192.168.x.x:11434`), allowing Open-WebUI inside the container to connect and list your models.

🔒 **Security note:** Once Ollama is exposed, other devices on your local network could also reach it. macOS will normally prompt you to allow or deny incoming connections. For extra control, you can use the macOS firewall (or a third-party firewall) to restrict access so only your own machine or subnet can connect.

This launches Open-WebUI on [http://localhost:3000](http://localhost:3000), with data persisted to your Mac.

---

### Why It Matters

By leveraging Apple’s own tooling, developers gain clear workload separation through secure isolation, fast performance optimized for Apple Silicon, native integration without third-party hypervisors, and the ability to keep AI workloads private and local.

---

### What’s Missing
Ecosystem support is still early. Tools like Watchtower or Compose aren’t available, restart policies are limited, and shortcuts like `host.docker.internal` don’t work. Updates and orchestration currently require manual steps.
📌 **Container 0.6.0 Updates:** Recent improvements include better resource management with `--memory` and `--cpus` flags, enhanced port publishing with `--publish`, and improved image pruning (though `container image prune` no longer accepts `-f` and may require timeouts).

---

### Looking Ahead

Apple’s entry into containers is significant. For developers and AI practitioners, this means Open-WebUI and Ollama can now run natively with Apple’s own tooling — combining open-source flexibility with first-party security.

📌 In a prior post I showed how to deploy Open-WebUI with Ollama and Docker:
👉 [Unlocking the Power of Open-Source Generative AI: Ollama + OpenWebUI v0.4.0](https://www.linkedin.com/posts/schwartz1375_local-hosting-of-llm-models-has-become-increasingly-activity-7264804264357552128-JdxD)

