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

// Helper: parse comma-separated model list from env var, filtering blanks
function parseExtraModels(envVar) {
    return (process.env[envVar] || '').split(',').map(s => s.trim()).filter(Boolean);
}

// Anthropic provider configuration
const baseUrl = (process.env.ANTHROPIC_BASE_URL || '').replace(/\/+$/, '');
const anthropicModel = process.env.ANTHROPIC_MODEL || 'claude-sonnet-4-5-20250929';

if (baseUrl) {
    console.log('Configuring Anthropic provider with base URL:', baseUrl);
    config.models = config.models || {};
    config.models.providers = config.models.providers || {};
    const knownModels = [
        { id: 'claude-opus-4-5-20251101', name: 'Claude Opus 4.5', contextWindow: 200000 },
        { id: 'claude-sonnet-4-5-20250929', name: 'Claude Sonnet 4.5', contextWindow: 200000 },
        { id: 'claude-haiku-4-5-20251001', name: 'Claude Haiku 4.5', contextWindow: 200000 },
    ];
    // If the user specified a primary model not in the known list, add it
    if (!knownModels.some(m => m.id === anthropicModel)) {
        knownModels.push({ id: anthropicModel, name: anthropicModel, contextWindow: 200000 });
    }
    // Add any extra models from ANTHROPIC_EXTRA_MODELS
    for (const extraId of parseExtraModels('ANTHROPIC_EXTRA_MODELS')) {
        if (!knownModels.some(m => m.id === extraId)) {
            knownModels.push({ id: extraId, name: extraId, contextWindow: 200000 });
        }
    }
    const providerConfig = {
        baseUrl: baseUrl,
        api: 'anthropic-messages',
        models: knownModels
    };
    if (process.env.ANTHROPIC_API_KEY) {
        providerConfig.apiKey = process.env.ANTHROPIC_API_KEY;
    }
    config.models.providers.anthropic = providerConfig;
    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['anthropic/claude-opus-4-5-20251101'] = { alias: 'Opus 4.5' };
    config.agents.defaults.models['anthropic/claude-sonnet-4-5-20250929'] = { alias: 'Sonnet 4.5' };
    config.agents.defaults.models['anthropic/claude-haiku-4-5-20251001'] = { alias: 'Haiku 4.5' };
    if (!knownModels.slice(0, 3).some(m => m.id === anthropicModel)) {
        config.agents.defaults.models['anthropic/' + anthropicModel] = { alias: anthropicModel };
    }
    for (const extraId of parseExtraModels('ANTHROPIC_EXTRA_MODELS')) {
        config.agents.defaults.models['anthropic/' + extraId] = { alias: extraId };
    }
    config.agents.defaults.model.primary = 'anthropic/' + anthropicModel;
} else if (process.env.ANTHROPIC_API_KEY) {
    // No custom base URL — default to Anthropic direct API
    config.agents.defaults.model.primary = 'anthropic/' + anthropicModel;
}

// OpenAI-compatible provider (works with OpenAI, OpenRouter, Kimi, etc.)
if (process.env.OPENAI_API_KEY) {
    const openaiBaseUrl = (process.env.OPENAI_BASE_URL || '').replace(/\/+$/, '');
    const openaiModel = process.env.OPENAI_MODEL || 'gpt-5.2';
    console.log('Configuring OpenAI provider' + (openaiBaseUrl ? ' with base URL: ' + openaiBaseUrl : ''));

    config.models = config.models || {};
    config.models.providers = config.models.providers || {};

    const openaiModels = [
        { id: openaiModel, name: openaiModel, contextWindow: 200000 },
    ];
    for (const extraId of parseExtraModels('OPENAI_EXTRA_MODELS')) {
        if (!openaiModels.some(m => m.id === extraId)) {
            openaiModels.push({ id: extraId, name: extraId, contextWindow: 200000 });
        }
    }
    const openaiProvider = {
        api: 'openai-responses',
        models: openaiModels
    };
    if (openaiBaseUrl) {
        openaiProvider.baseUrl = openaiBaseUrl;
    }
    config.models.providers.openai = openaiProvider;

    config.agents.defaults.models = config.agents.defaults.models || {};
    config.agents.defaults.models['openai/' + openaiModel] = { alias: openaiModel };
    for (const extraId of parseExtraModels('OPENAI_EXTRA_MODELS')) {
        config.agents.defaults.models['openai/' + extraId] = { alias: extraId };
    }

    // If no Anthropic key, use OpenAI model as primary
    if (!process.env.ANTHROPIC_API_KEY) {
        config.agents.defaults.model.primary = 'openai/' + openaiModel;
    }
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

# Clean up stale lock files (from previous crashes / container restarts)
rm -f /tmp/clawdbot-gateway.lock 2>/dev/null || true
rm -f "$CONFIG_DIR/gateway.lock" 2>/dev/null || true
find "$CONFIG_DIR" -name "*.lock" -delete 2>/dev/null || true
# Chromium profile singleton locks (these don't have a .lock extension)
find "$CONFIG_DIR" -name "SingletonLock" -delete 2>/dev/null || true
find "$CONFIG_DIR" -name "SingletonSocket" -delete 2>/dev/null || true
find "$CONFIG_DIR" -name "SingletonCookie" -delete 2>/dev/null || true

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

# Pre-launch Chromium with CDP so the browser control server finds it running.
# Clawdbot's built-in /start endpoint fails to launch chromium in Docker,
# but if we start it ourselves on the expected CDP port, clawdbot detects it.
# Chromium runs as a background process; the shell stays as PID 1 so it can
# reap child processes (exec would orphan chromium, causing it to be killed).
echo "Starting Chromium (headless, CDP on port 18800)..."
chromium \
    --headless \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --remote-debugging-port=18800 \
    --remote-debugging-address=127.0.0.1 \
    --user-data-dir=/root/.clawdbot/browser/clawd/user-data \
    about:blank 2>/dev/null &
CHROMIUM_PID=$!

# Wait for CDP to be ready
sleep 2
if kill -0 $CHROMIUM_PID 2>/dev/null; then
    echo "Chromium started (PID $CHROMIUM_PID)"
else
    echo "WARNING: Chromium failed to start. Browser automation will not be available."
fi

# Start gateway in the background (not exec) so this shell stays as PID 1
# to manage chromium as a child process.
clawdbot gateway --port 18789 --verbose --allow-unconfigured --bind "$BIND_MODE" --token "$CLAWDBOT_GATEWAY_TOKEN" &
GATEWAY_PID=$!

# Forward signals to the gateway
trap "kill $GATEWAY_PID $CHROMIUM_PID 2>/dev/null; wait" SIGTERM SIGINT

# Wait for the gateway to exit; if it does, clean up chromium too
wait $GATEWAY_PID
EXIT_CODE=$?
kill $CHROMIUM_PID 2>/dev/null
exit $EXIT_CODE
