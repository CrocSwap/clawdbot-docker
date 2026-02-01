# CLAUDE.md

## Project Overview

This repo provides a local Docker runtime for [OpenClaw](https://github.com/openclaw/openclaw). The upstream CLI package is still named `clawdbot` (not yet renamed). The goal is a simple `docker-compose up` experience that gives users a working AI assistant with persistent storage and optional chat channel integrations.

## Origin

This was extracted from the Cloudflare moltworker deployment at `/Users/colkitt/sith/toys/moltbot/cloudflare/moltworker/`. The Cloudflare version uses `@cloudflare/sandbox`, R2 bucket persistence, Worker proxying, and Browser Rendering API — none of which apply here. This repo replaces all of that with standard Docker primitives (bind mounts, port mapping, env vars).

## Architecture

- **Dockerfile**: Based on `node:22`. Installs clawdbot globally via npm, Chromium for browser automation, and runs `user-setup.sh` hook for custom toolchains.
- **start-openclaw.sh**: Entrypoint script. Copies config template on first run, then runs an inline Node.js heredoc that merges environment variables into `clawdbot.json`. Finally execs `clawdbot gateway`.
- **docker-compose.yml**: Bind-mounts `./data/` → `/root/.clawdbot/` (config/state) and `./workspace/` → `/root/clawd/` (workspace/skills). Passes env vars from `.env` file.
- **openclaw.json.template**: Minimal seed config (workspace path + gateway port). Only used on first run.
- **user-setup.sh**: No-op by default. Users edit this to install extra toolchains (Rust, Python, etc.) and rebuild.

## Key Details

- The clawdbot package version is pinned in the Dockerfile (`clawdbot@2026.1.24-3`). Update this when upgrading.
- Config lives at `/root/.clawdbot/clawdbot.json` inside the container. The startup script merges env vars into it on every boot, so env var changes take effect on restart without losing manually-edited config fields.
- `allowInsecureAuth` is set to `true` by default in the startup script (not the template). This is intentional for localhost use.
- The config merge script always clears and re-sets `agents.defaults.model.primary` to prevent stale model references.
- Gateway binds in `lan` mode (listens on all interfaces inside the container). This requires a token — one is auto-generated if `CLAWDBOT_GATEWAY_TOKEN` is not set.
- Chromium is installed in the image. The startup script configures `browser.enabled`, `browser.headless`, `browser.noSandbox`, `browser.executablePath`, and `browser.defaultProfile` on every boot. These are set in the config merge script, not the template, so they apply even for existing configs.
- Stale `.lock` files under the config directory are cleaned up on boot to prevent crashes after unclean shutdowns.

## Environment Variables

Handled by the inline Node.js script in `start-openclaw.sh`:
- `ANTHROPIC_API_KEY` — required for default setup
- `ANTHROPIC_BASE_URL` — optional, for proxies
- `OPENAI_API_KEY` — adds OpenAI as a secondary provider
- `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`/`SLACK_APP_TOKEN` — chat channels
- `CLAWDBOT_GATEWAY_TOKEN` — shared auth token for API access

## Build and Run

```bash
# Create .env with at minimum ANTHROPIC_API_KEY=...
docker-compose up --build
# Gateway available at http://localhost:18789
```

## Common Tasks

- **Upgrade clawdbot**: Change the version in the `Dockerfile` `npm install -g clawdbot@<version>` line and rebuild.
- **Add a skill**: Place it in `./workspace/skills/<skill-name>/` with a `SKILL.md`. It persists via the bind mount.
- **Add system packages**: Either set `EXTRA_APT_PACKAGES` build arg or edit `user-setup.sh`, then rebuild.
- **Reset config**: Delete `./data/clawdbot.json` and restart. The template will be re-copied.

## What NOT to Do

- Don't add Cloudflare-specific logic (R2, Workers, AI Gateway routing, CDP browser profiles). That belongs in the moltworker repo.
- Don't remove the `allowInsecureAuth = true` default without providing an alternative local auth flow.
- Don't change the bind mount paths without updating both `docker-compose.yml` and `start-openclaw.sh`.
