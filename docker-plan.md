# Local Container Project Plan

## Objective

Build a standalone local Docker-based runtime for OpenClaw (formerly Moltbot/Clawdbot) that provides container isolation without any Cloudflare dependencies. Users should be able to `docker run` (or `docker-compose up`) and immediately have a working AI assistant with persistent storage and optional browser automation.

## Background: What is OpenClaw

[OpenClaw](https://github.com/openclaw/openclaw) (CLI package is still named `clawdbot`) is a personal AI assistant with a gateway architecture. The gateway process runs on port 18789 and exposes:
- A WebSocket-based chat interface (the "Control UI")
- Multi-channel support (Telegram, Discord, Slack)
- Device pairing for authentication
- Persistent conversations and config in `~/.clawdbot/`
- An extensible skills system in a workspace directory (default `~/clawd/skills/`)

## Key OpenClaw Details Learned from moltworker

These are things not obvious from docs that were discovered during the Cloudflare deployment:

1. **Package name**: `npm install -g clawdbot@2026.1.24-3` (upstream hasn't renamed to openclaw yet)
2. **Config file**: Lives at `/root/.clawdbot/clawdbot.json` — this is the main config. The gateway won't start without it.
3. **Config template**: See `moltbot.json.template` in this repo for the structure. Key fields:
   - `gateway.port` (default 18789)
   - `gateway.auth.allowInsecureAuth` (set true for local dev to skip device pairing)
   - `gateway.channels[]` — array of channel configs (telegram, discord, slack)
   - `ai.providers[]` — API provider configs (anthropic, openai, etc.)
   - `ai.defaultProvider` / `ai.defaultModel`
4. **Config injection**: The startup script uses a node script to merge environment variables into `clawdbot.json`:
   - `ANTHROPIC_API_KEY` → `ai.providers[name=anthropic].apiKey`
   - `ANTHROPIC_BASE_URL` → `ai.providers[name=anthropic].baseUrl`
   - `OPENAI_API_KEY` → adds an openai provider
   - `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`/`SLACK_APP_TOKEN` → channel configs
   - `MOLTBOT_GATEWAY_TOKEN` → `gateway.auth.sharedToken`
5. **Skills directory**: `/root/clawd/skills/` — each skill has a `SKILL.md` describing it
6. **Gateway startup**: `clawdbot gateway --config /root/.clawdbot/clawdbot.json`
7. **Process management**: The gateway is a long-running Node.js process. It needs to be monitored and restarted if it crashes.
8. **Node.js version**: Requires Node.js 22+ (the clawdbot package depends on it)

## Architecture for Local Container

### What's simple locally (vs. Cloudflare complexity)

| Concern | Cloudflare moltworker | Local container |
|---------|----------------------|-----------------|
| Persistence | tar → base64 → R2 bucket binding (complex) | Bind mount: `-v ~/.moltbot:/root/.clawdbot` |
| Networking | Worker proxy, WebSocket forwarding | Direct port expose: `-p 18789:18789` |
| Auth | Cloudflare Access + gateway token + device pairing | Optional password or just localhost trust |
| Container lifecycle | `@cloudflare/sandbox` SDK, Durable Objects | `docker run` / `docker-compose` |
| Browser automation | CDP shim through Worker → Browser Rendering API | Sidecar Chrome container or mounted Docker socket |
| Config injection | Worker passes env vars through sandbox SDK | Standard Docker `-e` env vars |

### Proposed Structure

```
local-openclaw/
├── Dockerfile                  # Based on moltworker's, with user-setup.sh hook
├── docker-compose.yml          # Main entry point for users
├── start-openclaw.sh           # Startup script (adapted from start-moltbot.sh)
├── openclaw.json.template      # Default config template
├── user-setup.sh               # No-op by default, users customize for extra packages
├── skills/                     # Built-in skills (copy from moltworker)
│   └── ...
└── README.md
```

### Dockerfile

Start from `ubuntu:24.04` or `node:22` (no need for `cloudflare/sandbox` base image). Install:
- Node.js 22
- clawdbot (npm global)
- pnpm
- Basic tools (curl, git, etc.)
- `user-setup.sh` hook for custom toolchains (see below)

Add build arg support:
```dockerfile
ARG EXTRA_APT_PACKAGES=""
RUN if [ -n "$EXTRA_APT_PACKAGES" ]; then \
      apt-get update && apt-get install -y $EXTRA_APT_PACKAGES; \
    fi

COPY user-setup.sh /tmp/user-setup.sh
RUN chmod +x /tmp/user-setup.sh && /tmp/user-setup.sh
```

### docker-compose.yml

```yaml
services:
  openclaw:
    build:
      context: .
      args:
        EXTRA_APT_PACKAGES: ""  # Add apt packages here
    ports:
      - "18789:18789"
    volumes:
      - ./data:/root/.clawdbot        # Persistent config + conversations
      - ./workspace:/root/clawd        # Workspace + skills
    environment:
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      # Optional:
      # - OPENAI_API_KEY=${OPENAI_API_KEY}
      # - TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
      # - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
    restart: unless-stopped
```

### Startup Script (start-openclaw.sh)

Adapted from `start-moltbot.sh`. Core logic:
1. Check if `clawdbot.json` exists; if not, copy from template
2. Merge environment variables into config (API keys, channel tokens)
3. Start `clawdbot gateway`
4. Optionally run healthcheck loop

Key difference from moltworker: no R2 backup/restore logic needed (bind mounts handle persistence).

### Extensibility (user-setup.sh)

Default `user-setup.sh` is a no-op:
```bash
#!/bin/bash
# Add custom setup commands here.
# This runs during docker build as root.
# Examples:
#   apt-get update && apt-get install -y rustc cargo
#   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
echo "No custom setup configured."
```

Users edit this file and rebuild to add Rust, Go, Python, etc.

## Files to Copy from moltworker

These files from this repo (`/Users/colkitt/sith/toys/moltbot/cloudflare/moltworker/`) are useful starting points:

1. **`Dockerfile`** — adapt (change base image from `cloudflare/sandbox` to `ubuntu:24.04`, add extensibility hooks)
2. **`start-moltbot.sh`** — adapt as `start-openclaw.sh` (remove R2 logic, keep config init + env var injection + gateway startup)
3. **`moltbot.json.template`** — copy as `openclaw.json.template`
4. **`skills/`** — copy the skills directory as-is

Everything in `src/` is Cloudflare-specific and should NOT be copied.

## Implementation Steps

1. Create the new repo and basic structure
2. Write the Dockerfile (based on moltworker's, with ubuntu base + extensibility)
3. Write `start-openclaw.sh` (adapted from `start-moltbot.sh`)
4. Copy `moltbot.json.template` and `skills/`
5. Write `docker-compose.yml`
6. Write `user-setup.sh` (default no-op)
7. Test: `docker-compose up` with an Anthropic API key
8. Verify: config persistence across container restarts via bind mount
9. Write README with setup instructions

## Optional Future Additions

- **Browser automation**: Add a Chrome sidecar container in docker-compose for CDP
- **CLI wrapper**: A shell script or small binary that wraps `docker run` with sane defaults
- **Pre-built images**: Publish to Docker Hub / GHCR so users don't need to build
- **Profile system**: Multiple `user-setup.sh` variants (e.g., `profiles/rust.sh`, `profiles/python.sh`) that users can select
