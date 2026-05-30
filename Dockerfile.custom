# Use the official Hermes Agent image as the base
FROM nousresearch/hermes-agent:v2026.5.29.2

# Switch to root to install system dependencies
USER root

# Avoid prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install core utilities for the "Self-Healing Engineer" capability
# - sudo: To allow the agent to manage system services
# - python3-pip: For installing required Python libraries (like pymupdf)
# - gh: GitHub CLI for PR/Issue management
# - gnupg: For GPG key management and signing
# - dbus-x11: Required for gpg-agent to function in a container
# - curl/wget/git: Basic networking and version control
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    python3-pip \
    gnupg \
    dbus-x11 \
    curl \
    wget \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN echo "deb [signed-by=/usr/share/keyrings/github-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list \
    && wget -qO- https://cli.github.com/packages/github-archive-keyring.gpg | gpg --dearmor > /usr/share/keyrings/github-archive-keyring.gpg \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Configure sudo for the hermes user (UID 1000)
# The base image uses UID 1000. We grant passwordless sudo to this user.
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup a dedicated home directory for GPG if not already handled by base image
RUN mkdir -p /home/hermes/.gnupg && chown -R hermes:hermes /home/hermes/.gnupg && chmod 700 /home/hermes/.gnupg

# Switch back to the hermes user
USER hermes
WORKDIR /opt/data
