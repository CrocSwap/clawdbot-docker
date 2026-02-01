# clawdbot-docker

Local Docker runtime for [OpenClaw](https://github.com/openclaw/openclaw) (package name: `clawdbot`). Provides container isolation with persistent storage, configurable via environment variables.

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

3. **Open the Control UI** at [http://localhost:18789](http://localhost:18789).

That's it. Config and conversations persist in `./data/`, workspace files in `./workspace/`.

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

### Auth

| Variable | Description |
|----------|-------------|
| `CLAWDBOT_GATEWAY_TOKEN` | Shared token for programmatic API access |

By default, the Control UI allows unauthenticated access (suitable for localhost). If you expose port 18789 externally, set a gateway token or edit the config to disable `allowInsecureAuth`.

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
