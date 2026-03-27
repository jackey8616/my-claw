#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
  echo "Error: Please run with bash: bash ./setup-new-vps.sh"
  exit 1
fi
set -e

# ============================================================
# setup-new-vps.sh
# Deploy OpenClaw in a whole new VPS(run with root)
# Usage: bash ./setup-new-vps.sh or ./setup-new-vps.sh
# ============================================================

REMOTE_DEVICE_ID=""
VAULT_ID=""
REVERSE_PROXY_DOMAIN=""

read -p "REMOTE_DEVICE_ID: " REMOTE_DEVICE_ID
read -p "VAULT_ID: " VAULT_ID
read -p "REVERSE_PROXY_DOMAIN: " REVERSE_PROXY_DOMAIN

# ============================================================
# 1. Create dedicate user openclaw (UID=1000, same as node user inside the openclaw container)
# ============================================================
echo "==> Create openclaw user"

if id "openclaw" &>/dev/null; then
  echo "    User openclaw exists, skip."
elif id -u 1000 &>/dev/null; then
  echo "    Warning: UID 1000 has been occupied by $(id -nu 1000), unable to create openclaw user."
  exit 1
else
  useradd -m -u 1000 -s /bin/bash openclaw
  mkdir -p /home/openclaw
  chown openclaw:openclaw /home/openclaw
  echo "    openclaw create success（UID=1000）"
fi

# ============================================================
# 2. Install Docker
# ============================================================
echo "==> Update packages & install Docker"
apt update && apt upgrade -y
curl -fsSL https://get.docker.com | sh

# Add openclaw into docker group in order to run docker without privilege. 
usermod -aG docker openclaw
echo "    openclaw added docker group"

# ============================================================
# 3. Change working directory to user openclaw's home
# ============================================================
echo "    Changing pwd to user openclaw's home directory"
WORKDIR=$(pwd)
OPENCLAW_WORKDIR="/home/openclaw/$(basename $WORKDIR)"
mv "$WORKDIR" "$OPENCLAW_WORKDIR"
chown -R openclaw:openclaw "$OPENCLAW_WORKDIR"
cd "$OPENCLAW_WORKDIR"
export WORKDIR="$OPENCLAW_WORKDIR"


# ============================================================
# Rest of the execution will run as user openclaw
# ============================================================

run_as_openclaw() {
  set -e
  cd "$WORKDIR"
  mkdir -p "$HOME/.docker"

  # ============================================================
  # 4. Syncthing Setup（Obsidian Vault）
  # ============================================================
  echo "==> Setting Syncthing（Obsidian Vault）"
  mkdir -p openclaw/obsidian-data

  docker compose up -d obsidian-vault
  sleep 8

  SYNCTHING_CONFIG_FILE="./syncthing/config/config.xml"
  if [ ! -f "$SYNCTHING_CONFIG_FILE" ]; then
    echo "Error: Unable to find $SYNCTHING_CONFIG_FILE"
    exit 1
  fi

  cp "$SYNCTHING_CONFIG_FILE" "$SYNCTHING_CONFIG_FILE.bak"
  sed -i 's|<listenAddress>tcp://default</listenAddress>|<listenAddress>tcp://0.0.0.0</listenAddress>|g' "$SYNCTHING_CONFIG_FILE"

  API_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$SYNCTHING_CONFIG_FILE" | head -1)

  # Getting DeviceID for latter pairing
  DEVICE_ID=$(docker exec openclaw-obsidian curl -s \
    -H "X-Api-Key: $API_KEY" http://127.0.0.1:8384/rest/system/status | jq -r '.myID')
  echo "    This machine's Syncthing Device ID: $DEVICE_ID"

  # Add remote device
  echo "    Setting remote device"
  docker exec openclaw-obsidian curl -s -X POST \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"deviceID\": \"$REMOTE_DEVICE_ID\",
      \"name\": \"MacBookAir\",
      \"autoAcceptFolder\": true
    }" \
    http://127.0.0.1:8384/rest/config/devices

  # Add Obsidian Vault folder
  echo "    Setting vault folder"
  docker exec openclaw-obsidian curl -s -X POST \
    -H "X-API-Key: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"id\": \"$VAULT_ID\",
      \"label\": \"Obsidian Vault\",
      \"path\": \"/data/obsidian-data\",
      \"type\": \"sendreceive\",
      \"devices\": [
        {\"deviceID\": \"$REMOTE_DEVICE_ID\"}
      ]
    }" \
    http://127.0.0.1:8384/rest/config/folders

  sleep 8
  docker compose down

  # ============================================================
  # 5. Init OpenClaw
  # ============================================================
  echo "==> Init OpenClaw"
  mkdir -p openclaw/data
  mkdir -p openclaw/skills

  docker run -it --rm \
    --env-file "$(pwd)/.env" \
    -v "$(pwd)/openclaw/data:/home/node/.openclaw" \
    ghcr.io/openclaw/openclaw:latest \
    npx openclaw onboard

  # ============================================================
  # 6. Caddy Reverse Proxy
  # ============================================================
  echo "==> Setup Caddy"
  mkdir -p caddy/data
  mkdir -p caddy/config

  sed -i "s|\[domain\]|$REVERSE_PROXY_DOMAIN|g" "./Caddyfile"

  # ============================================================
  # 7. Run all services
  # ============================================================
  echo "==> Run all services"
  docker compose up -d

  # ============================================================
  # 8. Setup OpenClaw LAN mode
  # ============================================================
  echo "==> Setup LAN mode"
  docker exec -ti openclaw-app openclaw config set gateway.bind lan

  # ============================================================
  # 9. Setup OpenClaw allowed Origin for WebUI
  # ============================================================
  echo "==> Setup allowedOrigins"
  # Wait all containers ready
  echo "Sleep 5"
  sleep 5

  jq ".gateway.controlUi.allowedOrigins += [\"https://$REVERSE_PROXY_DOMAIN\"]" \
    ./openclaw/data/openclaw.json > temp.json \
    && mv temp.json ./openclaw/data/openclaw.json

  docker exec -ti openclaw-app openclaw gateway restart

  echo "    allowedOrigins added https://$REVERSE_PROXY_DOMAIN"

  # ============================================================
  # 10. Pair new device for login OpenClaw UI
  # ============================================================
  echo "==> Gateway UI Pairing"
  echo "    Open OpenClaw UI in another device in order to send pairing request..."
  read -p "Press Enter after you opened ui and login ..."
  docker exec -ti openclaw-app openclaw devices list

  PAIRING_REQUEST_ID=""
  echo "    Enter PAIRING_REQUEST_ID from above command to continue with auto-approve."
  read -p "PAIRING_REQUEST_ID: " PAIRING_REQUEST_ID
  docker exec -ti openclaw-app openclaw devices approve "$PAIRING_REQUEST_ID"

  echo "==> Deploy completed!"
  echo "    OpenClaw is running in https://$REVERSE_PROXY_DOMAIN"
}

export WORKDIR REMOTE_DEVICE_ID VAULT_ID REVERSE_PROXY_DOMAIN
export HOME="/home/openclaw"
TEMP_SCRIPT=$(mktemp)
declare -f run_as_openclaw > "$TEMP_SCRIPT"
echo "run_as_openclaw" >> "$TEMP_SCRIPT"
chown openclaw:openclaw "$TEMP_SCRIPT"
sudo -u openclaw -E sg docker -c "bash $TEMP_SCRIPT"
rm -f "$TEMP_SCRIPT"

# ============================================================
# 11. Optional: disable root SSH
# ============================================================
echo ""
echo "========================================================"
echo "Optional:"
echo "  After user openclaw can login via SSH,"
echo "  You can run following command to disable root SSH login:"
echo ""
echo "    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
echo "    systemctl restart sshd"
echo "========================================================"
