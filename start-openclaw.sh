#!/bin/bash
# Startup script for OpenClaw in Docker
# This script:
# 1. Initializes config from template on first run
# 2. Merges environment variables into clawdbot.json
# 3. Starts the gateway

set -e

# Check if clawdbot gateway is already running
if pgrep -f "clawdbot gateway" > /dev/null 2>&1; then
    echo "OpenClaw gateway is already running, exiting."
    exit 0
fi

# Paths
CONFIG_DIR="/root/.clawdbot"
CONFIG_FILE="$CONFIG_DIR/clawdbot.json"
TEMPLATE_DIR="/root/.clawdbot-templates"
TEMPLATE_FILE="$TEMPLATE_DIR/openclaw.json.template"

echo "Config directory: $CONFIG_DIR"

# Create config directory
mkdir -p "$CONFIG_DIR"

# If config file doesn't exist, create from template
if [ ! -f "$CONFIG_FILE" ]; then
    echo "No existing config found, initializing from template..."
    if [ -f "$TEMPLATE_FILE" ]; then
        cp "$TEMPLATE_FILE" "$CONFIG_FILE"
    else
        # Create minimal config if template doesn't exist
        cat > "$CONFIG_FILE" << 'EOFCONFIG'
{
  "agents": {
    "defaults": {
      "workspace": "/root/clawd"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local"
  }
}
EOFCONFIG
    fi
else
    echo "Using existing config"
fi

# ============================================================
# UPDATE CONFIG FROM ENVIRONMENT VARIABLES
# ============================================================
node << 'EOFNODE'
const fs = require('fs');

const configPath = '/root/.clawdbot/clawdbot.json';
console.log('Updating config at:', configPath);
let config = {};

try {
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (e) {
    console.log('Starting with empty config');
}

// Ensure nested objects exist
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.gateway = config.gateway || {};
config.channels = config.channels || {};

// Always clear stale model primary to ensure startup script sets it fresh
delete config.agents.defaults.model.primary;

// Clean up any broken anthropic provider config from previous runs
if (config.models?.providers?.anthropic?.models) {
    const hasInvalidModels = config.models.providers.anthropic.models.some(m => !m.name);
    if (hasInvalidModels) {
        console.log('Removing broken anthropic provider config (missing model names)');
        delete config.models.providers.anthropic;
    }
}

// Gateway configuration
config.gateway.port = 18789;
config.gateway.mode = 'local';

// Allow insecure auth by default for local convenience
// Users who expose the port externally can set this to false in their config
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.allowInsecureAuth = true;

// Browser configuration (Chromium in Docker)
config.browser = config.browser || {};
config.browser.enabled = true;
config.browser.executablePath = '/usr/bin/chromium';
config.browser.headless = true;
config.browser.noSandbox = true;
config.browser.defaultProfile = 'clawd';

// Set gateway token if provided
if (process.env.CLAWDBOT_GATEWAY_TOKEN) {
    config.gateway.auth = config.gateway.auth || {};
    config.gateway.auth.token = process.env.CLAWDBOT_GATEWAY_TOKEN;
}

// Telegram configuration
if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
    config.channels.telegram.enabled = true;
    config.channels.telegram.dm = config.channels.telegram.dm || {};
    config.channels.telegram.dmPolicy = process.env.TELEGRAM_DM_POLICY || 'pairing';
}

// Discord configuration
if (process.env.DISCORD_BOT_TOKEN) {
    config.channels.discord = config.channels.discord || {};
    config.channels.discord.token = process.env.DISCORD_BOT_TOKEN;
    config.channels.discord.enabled = true;
    config.channels.discord.dm = config.channels.discord.dm || {};
    config.channels.discord.dm.policy = process.env.DISCORD_DM_POLICY || 'pairing';
}

// Slack configuration
if (process.env.SLACK_BOT_TOKEN && process.env.SLACK_APP_TOKEN) {
    config.channels.slack = config.channels.slack || {};
    config.channels.slack.botToken = process.env.SLACK_BOT_TOKEN;
    config.channels.slack.appToken = process.env.SLACK_APP_TOKEN;
    config.channels.slack.enabled = true;
}

// Anthropic provider configuration
const baseUrl = (process.env.ANTHROPIC_BASE_URL || '').replace(/\/+$/, '');

if (baseUrl) {
    console.log('Configuring Anthropic provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    const providerConfig = {
        baseUrl: baseUrl,
        api: 'anthropic-messages',
        models: [
            { id: 'claude-opus-4-5-20251101', name: 'Claude Opus 4.5', contextWindow: 200000 },
            { id: 'claude-sonnet-4-5-20250929', name: 'Claude Sonnet 4.5', contextWindow: 200000 },
            { id: 'claude-haiku-4-5-20251001', name: 'Claude Haiku 4.5', contextWindow: 200000 },
        ]
    };
    if (process.env.ANTHROPIC_API_KEY) {
        providerConfig.apiKey = process.env.ANTHROPIC_API_KEY;
    }
    config.models.providers.anthropic = providerConfig;
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['anthropic/claude-opus-4-5-20251101'] = { alias: 'Opus 4.5' };
    config.agents.defaults.models['anthropic/claude-sonnet-4-5-20250929'] = { alias: 'Sonnet 4.5' };
    config.agents.defaults.models['anthropic/claude-haiku-4-5-20251001'] = { alias: 'Haiku 4.5' };
    config.agents.defaults.model.primary = 'anthropic/claude-sonnet-4-5-20250929';
} else {
    // No custom base URL — default to Anthropic direct API
    config.agents.defaults.model.primary = 'anthropic/claude-sonnet-4-5-20250929';
}

// OpenAI provider (if OPENAI_API_KEY is set, register models)
if (process.env.OPENAI_API_KEY) {
    console.log('Configuring OpenAI provider');
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    config.models.providers.openai = config.models.providers.openai || {
        api: 'openai-responses',
        models: [
            { id: 'gpt-5.2', name: 'GPT-5.2', contextWindow: 200000 },
            { id: 'gpt-5', name: 'GPT-5', contextWindow: 200000 },
            { id: 'gpt-4.5-preview', name: 'GPT-4.5 Preview', contextWindow: 128000 },
        ]
    };
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/gpt-5.2'] = { alias: 'GPT-5.2' };
    config.agents.defaults.models['openai/gpt-5'] = { alias: 'GPT-5' };
    config.agents.defaults.models['openai/gpt-4.5-preview'] = { alias: 'GPT-4.5' };
}

// Write updated config
fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('Configuration updated successfully');
console.log('Config:', JSON.stringify(config, null, 2));
EOFNODE

# ============================================================
# START GATEWAY
# ============================================================
echo "Starting OpenClaw Gateway..."
echo "Gateway will be available on port 18789"

# Clean up stale lock files (from previous crashes)
rm -f /tmp/clawdbot-gateway.lock 2>/dev/null || true
rm -f "$CONFIG_DIR/gateway.lock" 2>/dev/null || true
find "$CONFIG_DIR" -name "*.lock" -delete 2>/dev/null || true

BIND_MODE="lan"

# Token logic:
# - If CLAWDBOT_GATEWAY_TOKEN is set, the user intends remote/LAN access.
# - If no token is set, use a stable default. The host-side port is bound
#   to 127.0.0.1 by default (in docker-compose.yml), so a well-known token
#   is not a security concern for local use.
if [ -z "$CLAWDBOT_GATEWAY_TOKEN" ]; then
    CLAWDBOT_GATEWAY_TOKEN="local"
    echo "No CLAWDBOT_GATEWAY_TOKEN set — using default token for local access"
else
    echo "Starting gateway with explicit token (remote access mode)..."
fi

echo ""
echo "============================================================"
echo "  Open the Control UI at:"
echo "  http://localhost:18789/?token=${CLAWDBOT_GATEWAY_TOKEN}"
echo "============================================================"
echo ""

exec clawdbot gateway --port 18789 --verbose --allow-unconfigured --bind "$BIND_MODE" --token "$CLAWDBOT_GATEWAY_TOKEN"
