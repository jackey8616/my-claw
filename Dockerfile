# Use the official Hermes Agent image as the base
FROM nousresearch/hermes-agent:v2026.5.29.2

# Switch to root to install only the essential "Privilege & Identity" core
USER root

# Avoid prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install only the absolute minimum required for a "Self-Healing" orchestrator
# - sudo: To allow the agent to fix permissions (like docker.sock) and manage services
# - gh: GitHub CLI for PR/Issue management
# - gnupg / dbus-x11: Required for secure identity and signed commits
# - curl/wget/git: Core networking and version control
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    gnupg \
    dbus-x11 \
    curl \
    wget \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (minimal footprint)
RUN echo "deb [signed-by=/usr/share/keyrings/github-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list \
    && wget -qO- https://cli.github.com/packages/github-archive-keyring.gpg | gpg --dearmor > /usr/share/keyrings/github-archive-keyring.gpg \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Configure passwordless sudo for the hermes user (UID 1000)
# This is the "Master Key" that allows the agent to spawn sandboxes and fix system issues
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup GPG home directory
RUN mkdir -p /home/hermes/.gnupg && chown -R hermes:hermes /home/hermes/.gnupg && chmod 700 /home/hermes/.gnupg

# Switch back to the hermes user
USER hermes
WORKDIR /opt/data
