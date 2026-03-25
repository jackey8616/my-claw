#!/bin/bash
REMOTE_DEVICE_ID=""
VAULT_ID=""
REVERSE_PROXY_DOMAIN=""
read -p "REMOTE_DEVICE_ID: " REMOTE_DEVICE_ID
read -p "VAULT_ID: " VAULT_ID
read -p "REVERSE_PROXY_DOMAIN: " REVERSE_PROXY_DOMAIN

echo "Updating apt"
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

echo "Managing Syncthing for Obsidian"
mkdir -p openclaw/obsidian-vault
docker compose up -d openclaw-obsidian
sleep 8

SYNCTHING_CONFIG_FILE="./syncthing/config/config.xml"
if [ -f "$SYNCTHING_CONFIG_FILE" ]; then
  cp "$SYNCTHING_CONFIG_FILE" "$SYNCTHING_CONFIG_FILE.bak"
  sed -i 's|<listenAddress>tcp://default</listenAddress>|<listenAddress>tcp://0.0.0.0</listenAddress>|g' "$SYNCTHING_CONFIG_FILE"
  API_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$SYNCTHING_CONFIG_FILE" | head -1)
else
  echo "Error: missing $SYNCTHING_CONFIG_FILE"
  exit 1
fi

DEVICE_ID=$(docker exec openclaw-obsidian curl -s \
  -H "X-Api-Key: $API_KEY" http://127.0.0.1:8384/rest/system/status | jq -r '.myID')

docker exec openclaw-obsidian curl -s -X POST \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceID\": \"$REMOTE_DEVICE_ID\",
    \"name\": \"MacBookAir\",
    \"autoAcceptFolder\":true
  }" \
  http://127.0.0.1:8384/rest/config/devices


docker exec openclaw-obsidian curl -s -X POST \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\":\"$VAULT_ID\",
    \"label\":\"Obsidian Vault\",
    \"path\":\"/data/obsidian_vault\",
    \"type\":\"sendreceive\",
    \"devices\":[
      {\"deviceID\":\"$REMOTE_DEVICE_ID\"}
    ]
  }" \
  http://127.0.0.1:8384/rest/config/folders
sleep 8
docker compose down

echo "Managing OpenClaw"
mkdir -p openclaw/data
mkdir -p openclaw/skills
sudo chmod -R 775 openclaw && sudo chown -R 1000:1000 openclaw
docker run -it --rm \
  --env-file $(pwd)/.env \
  -v $(pwd)/openclaw/data:/home/node/.openclaw \
  ghcr.io/openclaw/openclaw:latest \
  npx openclaw onboard

echo "Managing Caddy for Reverse-Proxy"
mkdir -p caddy/data
mkdir -p caddy/config
sudo chmod -R 775 caddy && sudo chown -R 1000:1000 caddy
sed -i "s|[domain]|$REVERSE_DOMAIN_PROXY|g" "./Caddyfile"
