FROM node:22

# Install basic tools
RUN apt-get update && apt-get install -y \
    curl \
    git \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Optional extra apt packages (set via docker-compose build args)
ARG EXTRA_APT_PACKAGES=""
RUN if [ -n "$EXTRA_APT_PACKAGES" ]; then \
      apt-get update && apt-get install -y $EXTRA_APT_PACKAGES && rm -rf /var/lib/apt/lists/*; \
    fi

# Install pnpm globally
RUN npm install -g pnpm

# Install clawdbot (CLI package — upstream hasn't renamed to openclaw yet)
# Pin to specific version for reproducible builds
RUN npm install -g clawdbot@2026.1.24-3 \
    && clawdbot --version

# Run user-setup.sh hook for custom toolchains (Rust, Go, Python, etc.)
COPY user-setup.sh /tmp/user-setup.sh
RUN chmod +x /tmp/user-setup.sh && /tmp/user-setup.sh

# Create directories
# Templates are stored separately so we can detect first-run vs existing config
RUN mkdir -p /root/.clawdbot \
    && mkdir -p /root/.clawdbot-templates \
    && mkdir -p /root/clawd \
    && mkdir -p /root/clawd/skills

# Copy startup script
COPY start-openclaw.sh /usr/local/bin/start-openclaw.sh
RUN chmod +x /usr/local/bin/start-openclaw.sh

# Copy default configuration template
COPY openclaw.json.template /root/.clawdbot-templates/openclaw.json.template

# Set working directory
WORKDIR /root/clawd

# Expose the gateway port
EXPOSE 18789

CMD ["/usr/local/bin/start-openclaw.sh"]
