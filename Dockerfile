# Use the official Hermes Agent image as the base
FROM nousresearch/hermes-agent:v2026.5.29.2

# Switch to root to install only the essential "Privilege & Identity" core
USER root

# Avoid prompts during apt-get install
ENV DEBIAN_FRONTEND=noninteractive

# Install absolute minimum core utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    gnupg \
    dbus-x11 \
    curl \
    wget \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI via direct binary download (more robust than apt in containers)
RUN curl -fsSL https://api.github.com/repos/cli/cli/releases/latest \
    | grep "browser_download_url" \
    | grep "linux_amd64.tar.gz" \
    | cut -d '"' -f 4 \
    | xargs wget -qO- | tar -xZ -C /usr/local/bin gh \
    && chmod +x /usr/local/bin/gh

# Configure passwordless sudo for the hermes user (UID 1000)
RUN echo "hermes ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup GPG home directory
RUN mkdir -p /home/hermes/.gnupg && chown -R hermes:hermes /home/hermes/.gnupg && chmod 700 /home/hermes/.gnupg

# Switch back to the hermes user
USER hermes
WORKDIR /opt/data
