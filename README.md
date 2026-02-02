# clawdbot-docker

Local Docker runtime for [OpenClaw](https://github.com/openclaw/openclaw) (package name: `clawdbot`). Provides container isolation with persistent storage, configurable via environment variables.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/) (included with Docker Desktop)
- An API key from [Anthropic](https://console.anthropic.com/) (or OpenAI)

Everything else (Node.js, clawdbot, Chromium) is installed inside the container during the build.

## Quick Start

1. **Clone and configure:**

   ```bash
   git clone https://github.com/openclaw/clawdbot-docker.git
   cd clawdbot-docker
   ```

   Create a `.env` file with your API key:

   ```
   ANTHROPIC_API_KEY=sk-ant-...
   ```

2. **Start:**

   ```bash
   docker-compose up --build
   ```

3. **Open the Control UI** at [http://localhost:18789/?token=local](http://localhost:18789?token=local).

That's it. Config and conversations persist in `./data/`, workspace files in `./workspace/`.

Browser automation (Chromium) is included and configured out of the box — no extra setup needed.

## Configuration

All configuration is done through environment variables, either in `.env` or passed directly. The startup script merges these into the `clawdbot.json` config on each boot.

### AI Providers

| Variable | Description |
|----------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic API key (required for default setup) |
| `ANTHROPIC_BASE_URL` | Custom Anthropic endpoint (e.g. for a proxy) |
| `OPENAI_API_KEY` | Enables OpenAI as an additional provider |

The default model is Claude Sonnet 4.5. Setting `OPENAI_API_KEY` adds GPT models as options without changing the default.

### Chat Channels

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token |
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `SLACK_BOT_TOKEN` | Slack bot token (requires `SLACK_APP_TOKEN` too) |
| `SLACK_APP_TOKEN` | Slack app-level token |

### Networking and Auth

By default, the gateway port is bound to **`127.0.0.1`** (localhost only). This means only the host machine can access the Control UI — no token configuration needed for local use.

**For remote/VM deployments**, set `CLAWDBOT_GATEWAY_TOKEN` in your `.env`:

```
CLAWDBOT_GATEWAY_TOKEN=some-strong-secret
OPENCLAW_BIND_HOST=0.0.0.0
```

| Variable | Description |
|----------|-------------|
| `CLAWDBOT_GATEWAY_TOKEN` | Gateway auth token. When set, enables remote access mode. |
| `OPENCLAW_BIND_HOST` | Host-side bind address. Defaults to `127.0.0.1`. Set to `0.0.0.0` for remote access. |

The logic:
- **No token set** (default): port bound to `127.0.0.1`, a default token (`local`) is used. Access the Control UI at `http://localhost:18789/?token=local`. Safe for local use since the port is only reachable from your machine.
- **Token set**: you're signaling remote access intent. Set `OPENCLAW_BIND_HOST=0.0.0.0` to make the port reachable from other machines. Consider disabling `allowInsecureAuth` in the config for production use.

Chat channels (Telegram, Discord, Slack) connect outbound and are unaffected by the bind address.

## Browser Automation

Chromium is installed in the image and pre-configured for headless operation in Docker. The startup script sets:

- `browser.enabled: true`
- `browser.executablePath: /usr/bin/chromium`
- `browser.headless: true`
- `browser.noSandbox: true` (Docker provides isolation)
- `browser.defaultProfile: "clawd"`

This works out of the box — no extra configuration needed. If you run into shared memory issues with complex pages, add `shm_size: '2gb'` to the service in `docker-compose.yml`.

## Volumes

| Host Path | Container Path | Purpose |
|-----------|---------------|---------|
| `./data/` | `/root/.clawdbot/` | Config file, conversations, state |
| `./workspace/` | `/root/clawd/` | Workspace directory, skills |

These are created automatically on first run. Data persists across container restarts and rebuilds.

## Customizing the Image

### Extra apt packages

Add packages at build time via the `EXTRA_APT_PACKAGES` build arg in `docker-compose.yml`:

```yaml
build:
  args:
    EXTRA_APT_PACKAGES: "python3 python3-pip golang"
```

### Custom toolchains

Edit `user-setup.sh` for more complex setup (runs as root during build):

```bash
#!/bin/bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
```

Then rebuild: `docker-compose up --build`

## Security

Running in a container significantly reduces blast radius compared to running clawdbot directly on your host machine.

**What the container isolates:**
- **Filesystem** — AI-generated code can only access the two bind-mounted directories (`./data/` and `./workspace/`). It cannot read your home directory, SSH keys, other projects, etc.
- **Processes** — cannot see or signal processes on the host.
- **Syscalls** — Docker's default seccomp profile blocks dangerous operations (kernel modules, reboot, etc.).

**What it does NOT isolate:**
- **Outbound network** — the container has full internet access (required for API calls and chat channels). AI-generated code could exfiltrate data from the workspace.
- **Bind-mounted data** — anything in `./data/` and `./workspace/` is fully accessible. Don't put sensitive files in the workspace.
- **Resource exhaustion** — no CPU/memory limits by default. Add `mem_limit` and `cpus` to the service in `docker-compose.yml` if needed.

**Things to avoid:**
- Never mount the Docker socket (`/var/run/docker.sock`) into the container — this is effectively root on the host.
- For remote deployments, always set `CLAWDBOT_GATEWAY_TOKEN` and consider disabling `allowInsecureAuth`.

## Project Structure

```
clawdbot-docker/
├── Dockerfile                  # Container image (node:22 base)
├── docker-compose.yml          # Main entry point
├── start-openclaw.sh           # Startup script (config merge + gateway launch)
├── openclaw.json.template      # Default config template
├── user-setup.sh               # Custom build hook (edit and rebuild)
├── data/                       # Persistent config (auto-created, gitignored)
└── workspace/                  # Persistent workspace (auto-created, gitignored)
```
