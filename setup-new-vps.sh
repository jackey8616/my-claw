#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
  echo "Error: Please run with bash: bash ./setup-vps.sh"
  exit 1
fi
set -e

# ============================================================
# setup-vps.sh
# Deploy personal Claude Code assistant on a fresh VPS
# Run as root on a fresh Ubuntu 22.04/24.04
#
# What this script does:
#   1.  Create a dedicated user
#   2.  Install Docker
#   3.  Move workdir to agent home
#   4.  Write docker-compose.yml for Syncthing
#   5.  Syncthing setup & Obsidian Vault sync
#   6.  Install Node.js + Claude Code (native)
#   7.  Install Bun (required for Channels plugins)
#   8.  Configure Claude Code auth (OAuth Token)
#   8.5 Configure Claude Code Hooks
#   9.  Install Discord Channels plugin
#   10. Write CLAUDE.md pointing to Persona in vault
#   11. Write tmux startup script
#   12. Firewall
# ============================================================

# ============================================================
# Helpers
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $1"; }
warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }
pause()   { read -p "$1 [Press Enter to continue]"; }

update_env() {
  local var_name=$1
  local var_value=$2
  if grep -q "^${var_name}=" .env 2>/dev/null; then
    sed -i "s|^${var_name}=.*|${var_name}=\"${var_value}\"|" .env
  else
    echo "${var_name}=\"${var_value}\"" >> .env
  fi
}

load_env() {
  local env_var_name=$1
  local prompt_text=${2:-$1}
  local current_val
  current_val=$(grep "^${env_var_name}=" .env 2>/dev/null | cut -d '=' -f2- | tr -d '"')

  if [[ -n "$current_val" ]]; then
    read -p "${env_var_name} already exists (${current_val:0:20}...), overwrite? (y/N): " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
      read -p "New ${prompt_text}: " new_val
      update_env "$env_var_name" "$new_val"
      echo "$new_val"
    else
      echo "$current_val"
    fi
  else
    read -p "Enter ${prompt_text}: " new_val
    update_env "$env_var_name" "$new_val"
    echo "$new_val"
  fi
}

# ============================================================
# Load config from .env
# ============================================================
touch .env

info "Loading configuration..."
AGENT_USER=$(load_env "AGENT_USER" "dedicated user name (e.g. myagent)")
REMOTE_DEVICE_ID=$(load_env "REMOTE_DEVICE_ID" "Syncthing Device ID of your Mac/PC")
VAULT_ID=$(load_env "VAULT_ID" "Syncthing Folder ID of your Obsidian Vault")
DISCORD_BOT_TOKEN=$(load_env "DISCORD_BOT_TOKEN" "Discord Bot Token")
CLAUDE_CODE_OAUTH_TOKEN=$(load_env "CLAUDE_CODE_OAUTH_TOKEN" "Claude OAuth Token (run: claude setup-token on local machine)")
TIMEZONE=$(load_env "TIMEZONE" "Timezone (e.g. Asia/Taipei)")

# Derived paths
AGENT_HOME="/home/${AGENT_USER}"
VAULT_LOCAL="${AGENT_HOME}/vault"
PERSONA_LOCAL="${AGENT_HOME}/vault/00-Laura-Persona"
WORKDIR=$(pwd)
AGENT_WORKDIR="${AGENT_HOME}/$(basename $WORKDIR)"

# ============================================================
# 1. Create dedicated agent user
# ============================================================
info "Creating agent user: ${AGENT_USER}"

if id "$AGENT_USER" &>/dev/null; then
  warning "User ${AGENT_USER} already exists, skipping."
else
  useradd -m -s /bin/bash "$AGENT_USER"
  mkdir -p "$AGENT_HOME"
  chown "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"
  info "User ${AGENT_USER} created."
fi

# ============================================================
# 2. Install Docker
# ============================================================
info "Checking Docker..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq unzip jq

if command -v docker &>/dev/null; then
  warning "Docker already installed, skipping."
else
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

usermod -aG docker "$AGENT_USER"
info "Added ${AGENT_USER} to docker group."

# ============================================================
# 3. Move workdir to agent home
# ============================================================
info "Moving workdir to ${AGENT_WORKDIR}..."
if [ "$WORKDIR" != "$AGENT_WORKDIR" ]; then
  mv "$WORKDIR" "$AGENT_WORKDIR"
  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_WORKDIR"
fi
export WORKDIR="$AGENT_WORKDIR"

# ============================================================
# 4. Write docker-compose.yml for Syncthing
# ============================================================
info "Writing docker-compose.yml..."

cat > "${WORKDIR}/docker-compose.yml" <<COMPOSE
services:
  syncthing:
    image: syncthing/syncthing:latest
    container_name: agent-syncthing
    hostname: agent-syncthing
    restart: unless-stopped
    environment:
      - PUID=1000
      - PGID=1000
    ports:
      - "8384:8384"     # Web UI (close after setup)
      - "22000:22000"   # Sync protocol
    volumes:
      - ${VAULT_LOCAL}:/data/vault
      - syncthing-config:/var/syncthing

volumes:
  syncthing-config:
COMPOSE

chown "${AGENT_USER}:${AGENT_USER}" "${WORKDIR}/docker-compose.yml"

# ============================================================
# 5. Syncthing setup & Obsidian Vault sync
# ============================================================
info "Starting Syncthing..."
mkdir -p "$VAULT_LOCAL"
chown -R "${AGENT_USER}:${AGENT_USER}" "$VAULT_LOCAL"

cd "$WORKDIR"
sudo -u "$AGENT_USER" docker compose up -d syncthing
sleep 10

# Extract API key — call from host (Syncthing v2.0 image has no curl)
info "Waiting for Syncthing API to be ready..."
SYNCTHING_CONFIG_DIR=$(docker volume inspect \
  "$(basename $WORKDIR)_syncthing-config" \
  --format '{{.Mountpoint}}')
SYNCTHING_CONFIG_FILE="${SYNCTHING_CONFIG_DIR}/config/config.xml"
API_KEY=$(sed -n 's:.*<apikey>\(.*\)</apikey>.*:\1:p' "$SYNCTHING_CONFIG_FILE" | head -1)

# Setup listen address
sed -i 's|<listenAddress>tcp://default</listenAddress>|<listenAddress>tcp://0.0.0.0</listenAddress>|g' "$SYNCTHING_CONFIG_FILE"

# Get this machine's Device ID
DEVICE_ID=$(curl -sf \
  -H "X-Api-Key: $API_KEY" \
  http://127.0.0.1:8384/rest/system/status | jq -r '.myID')

info "This VPS Syncthing Device ID:"
echo ""
echo "  >>>  ${DEVICE_ID}  <<<"
echo ""

# Add remote device (your Mac/PC)
info "Adding remote device..."
curl -s -X POST \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"deviceID\": \"${REMOTE_DEVICE_ID}\",
    \"name\": \"LocalMachine\",
    \"autoAcceptFolders\": true
  }" \
  http://127.0.0.1:8384/rest/config/devices > /dev/null

# Add Obsidian Vault folder
info "Adding Obsidian Vault folder..."
curl -s -X POST \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"${VAULT_ID}\",
    \"label\": \"Obsidian Vault\",
    \"path\": \"/data/vault\",
    \"type\": \"sendreceive\",
    \"devices\": [
      {\"deviceID\": \"${REMOTE_DEVICE_ID}\"}
    ]
  }" \
  http://127.0.0.1:8384/rest/config/folders > /dev/null

info "Syncthing configured. Now share the Vault folder to this device from your local Syncthing."
pause "Press Enter after Vault is fully synced..."

# Verify vault has AGENTS.md
if [ ! -f "${PERSONA_LOCAL}/AGENTS.md" ]; then
  warning "AGENTS.md not found in vault root (${PERSONA_LOCAL}/AGENTS.md)."
  warning "Make sure you have AGENTS.md in your Obsidian Vault root before proceeding."
  pause "Press Enter to continue anyway..."
fi

# ============================================================
# 6. Install Node.js + Claude Code (native, not Docker)
# ============================================================
CLAUDE_CODE_VERSION="2.1.86"

info "Installing Node.js (via nvm)..."
sudo -u "$AGENT_USER" bash -c '
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "    nvm already installed, skipping."
  else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi
  source "$NVM_DIR/nvm.sh"
  if nvm ls --no-colors 2>/dev/null | grep -q "lts/"; then
    echo "    Node.js LTS already installed, skipping."
  else
    nvm install --lts
  fi
  nvm use --lts
'

info "Installing Claude Code@${CLAUDE_CODE_VERSION}..."
sudo -u "$AGENT_USER" bash -c "
  export NVM_DIR=\"\$HOME/.nvm\"
  source \"\$NVM_DIR/nvm.sh\"
  INSTALLED=\$(npm list -g --depth=0 2>/dev/null | grep '@anthropic-ai/claude-code' | grep -o '[0-9]*\.[0-9]*\.[0-9]*' || true)
  if [ \"\$INSTALLED\" = \"${CLAUDE_CODE_VERSION}\" ]; then
    echo '    Claude Code ${CLAUDE_CODE_VERSION} already installed, skipping.'
  else
    echo \"    Installing Claude Code ${CLAUDE_CODE_VERSION} (was: \${INSTALLED:-none})...\"
    npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
  fi
"

# Verify Claude Code version meets minimum requirement
info "Verifying Claude Code version..."
sudo -u "$AGENT_USER" bash -c '
  export NVM_DIR="$HOME/.nvm"
  source "$NVM_DIR/nvm.sh"
  CLAUDE_VER=$(claude --version 2>/dev/null | grep -oP "\d+\.\d+\.\d+" | head -1)
  echo "    Claude Code version: ${CLAUDE_VER}"
  IFS="." read -r major minor patch <<< "$CLAUDE_VER"
  if [ "$major" -lt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -lt 1 ]; } || \
     { [ "$major" -eq 2 ] && [ "$minor" -eq 1 ] && [ "$patch" -lt 80 ]; }; then
    echo "    Warning: Claude Code >= 2.1.80 is required for Discord plugin support."
  else
    echo "    Version OK (>= 2.1.80)."
  fi
'

# ============================================================
# 7. Install Bun (required for Claude Code Channels plugins)
# ============================================================
info "Installing Bun..."
sudo -u "$AGENT_USER" bash -c '
  if command -v bun &>/dev/null || [ -f "$HOME/.bun/bin/bun" ]; then
    echo "    Bun already installed ($(~/.bun/bin/bun --version 2>/dev/null || bun --version)), skipping."
  else
    curl -fsSL https://bun.sh/install | bash
    echo "    Bun installed."
  fi

  # Ensure bun is in PATH for future sessions
  if ! grep -q "\.bun/bin" $HOME/.bashrc 2>/dev/null; then
    echo "export BUN_INSTALL=\"\$HOME/.bun\"" >> $HOME/.bashrc
    echo "export PATH=\"\$BUN_INSTALL/bin:\$PATH\"" >> $HOME/.bashrc
  fi
'

# ============================================================
# 8. Configure Claude Code auth (OAuth Token)
# ============================================================
info "Setting up Claude Code authentication..."
sudo -u "$AGENT_USER" bash -c "
  mkdir -p \$HOME/.claude

  # Skip onboarding prompt
  cat > \$HOME/.claude.json <<'CLAUDEJSON'
{
  \"hasCompletedOnboarding\": true
}
CLAUDEJSON
  chmod 600 \$HOME/.claude.json

  if ! grep -q 'CLAUDE_CODE_OAUTH_TOKEN' \$HOME/.bashrc 2>/dev/null; then
    echo 'export CLAUDE_CODE_OAUTH_TOKEN=\"${CLAUDE_CODE_OAUTH_TOKEN}\"' >> \$HOME/.bashrc
  else
    sed -i 's|^export CLAUDE_CODE_OAUTH_TOKEN=.*|export CLAUDE_CODE_OAUTH_TOKEN=\"${CLAUDE_CODE_OAUTH_TOKEN}\"|' \$HOME/.bashrc
  fi

  if ! grep -q '^export TZ=' \$HOME/.bashrc 2>/dev/null; then
    echo 'export TZ=\"${TIMEZONE}\"' >> \$HOME/.bashrc
  else
    sed -i 's|^export TZ=.*|export TZ=\"${TIMEZONE}\"|' \$HOME/.bashrc
  fi
"

# ============================================================
# 8.5 Configure Claude Code Hooks
# ============================================================
info "Configuring Claude Code hooks..."

HOOKS_DIR="${AGENT_WORKDIR}/hooks"

find "$HOOKS_DIR" -name "*.sh" -exec chmod +x {} \;
chown -R "${AGENT_USER}:${AGENT_USER}" "$HOOKS_DIR"

sudo -u "$AGENT_USER" bash -c "
  GLOBAL_SETTINGS=\"\$HOME/.claude/settings.json\"
  mkdir -p \$HOME/.claude

  if [ ! -f \"\$GLOBAL_SETTINGS\" ]; then
    echo '{}' > \"\$GLOBAL_SETTINGS\"
  fi

  # 清除舊的 hooks 區塊，避免重複執行時重複註冊
  jq 'del(.hooks)' \"\$GLOBAL_SETTINGS\" > /tmp/claude-settings-merged.json
  mv /tmp/claude-settings-merged.json \"\$GLOBAL_SETTINGS\"

  # 依資料夾名稱排序，逐一讀取 claude_event_name 並註冊所有 .sh
  find '${HOOKS_DIR}' -mindepth 1 -maxdepth 1 -type d | sort | while read -r hook_dir; do
    EVENT_FILE=\"\${hook_dir}/claude_event_name\"

    if [ ! -f \"\$EVENT_FILE\" ]; then
      echo \"    Skipping \$(basename \$hook_dir): no claude_event_name found\"
      continue
    fi

    EVENT=\$(cat \"\$EVENT_FILE\" | tr -d '[:space:]')

    find \"\$hook_dir\" -name '*.sh' | sort | while read -r script; do
      jq \".hooks.\${EVENT} += [{\\\"hooks\\\": [{\\\"type\\\": \\\"command\\\", \\\"command\\\": \\\"\$script\\\"}]}]\" \
        \"\$GLOBAL_SETTINGS\" > /tmp/claude-settings-merged.json
      mv /tmp/claude-settings-merged.json \"\$GLOBAL_SETTINGS\"
      echo \"    Registered [\${EVENT}]: \$script\"
    done
  done

  chmod 600 \"\$GLOBAL_SETTINGS\"
"

# ============================================================
# 9. Install Discord Channels plugin
# ============================================================
info "Installing Discord Channels plugin..."

# Write Discord bot token to Claude channels config
sudo -u "$AGENT_USER" bash -c "
  mkdir -p \$HOME/.claude/channels/discord
  cat > \$HOME/.claude/channels/discord/.env <<EOF
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
EOF
  chmod 600 \$HOME/.claude/channels/discord/.env
"

# Install via marketplace (handles clone + bun install + config registration)
sudo -u "$AGENT_USER" bash -c "
  export NVM_DIR=\"\$HOME/.nvm\"
  source \"\$NVM_DIR/nvm.sh\"
  export BUN_INSTALL=\"\$HOME/.bun\"
  export PATH=\"\$BUN_INSTALL/bin:\$PATH\"
  export CLAUDE_CODE_OAUTH_TOKEN=\"${CLAUDE_CODE_OAUTH_TOKEN}\"
 
  claude plugin marketplace add anthropics/claude-plugins-official
  claude plugin install discord@claude-plugins-official
"

info "Discord plugin installed."

# ============================================================
# 10. Write CLAUDE.md (repo root, points to vault AGENTS.md)
# ============================================================
info "Writing CLAUDE.md..."

cat > "${AGENT_WORKDIR}/CLAUDE.md" <<'CLAUDEMD'
# Bootstrap

Before doing anything else, read the full contents of
${PERSONA_LOCAL}/AGENTS.md and follow all
instructions within it.

Do not proceed until you have read that file.
CLAUDEMD
sed -i "s|\${PERSONA_LOCAL}|${PERSONA_LOCAL}|g" "${AGENT_WORKDIR}/CLAUDE.md"

chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKDIR}/CLAUDE.md"

# ============================================================
# 11. tmux startup script
# ============================================================
info "Writing tmux startup script..."

cat > "${AGENT_WORKDIR}/start-agent.sh" <<'STARTSCRIPT'
#!/bin/bash
# Start Claude Code assistant in a persistent tmux session
# Usage: bash start-agent.sh

# Resolve script's own directory so it works regardless of cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load config from .env in the same directory
if [ -f "${SCRIPT_DIR}/.env" ]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
else
  echo "Error: .env not found at ${SCRIPT_DIR}/.env"
  exit 1
fi

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export TZ="$TIMEZONE"

# Resolve absolute path to claude so tmux shell doesn't need nvm in PATH
CLAUDE_BIN="$(which claude)"
if [ -z "$CLAUDE_BIN" ]; then
  echo "Error: claude binary not found. Is nvm/node installed?"
  exit 1
fi

SESSION="assistant"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already running. Attaching..."
  tmux attach -t "$SESSION"
else
  echo "Starting new Claude Code session..."
  tmux new-session -d -s "$SESSION" -x 220 -y 50 \
    -e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN" \
    -e "TZ=$TZ"
  tmux send-keys -t "$SESSION" "cd ${SCRIPT_DIR} && ${CLAUDE_BIN} --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions" Enter
  echo "Session started. Attaching..."
  tmux attach -t "$SESSION"
fi
STARTSCRIPT

chmod +x "${AGENT_WORKDIR}/start-agent.sh"
chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKDIR}/start-agent.sh"

# Install tmux if not present
if ! command -v tmux &>/dev/null; then
  info "Installing tmux..."
  apt-get install -y tmux -qq
fi

# ============================================================
# 12. Firewall
# ============================================================
info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH
  ufw --force enable
  ufw deny 8384
  ufw allow 22000
  info "UFW configured. Port 8384 (Syncthing UI) is blocked externally."
else
  warning "ufw not found, skipping firewall setup."
fi

# ============================================================
# Done!
# ============================================================
echo ""
echo "========================================================"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "  1. SSH into the VPS as ${AGENT_USER}:"
echo "     ssh ${AGENT_USER}@<your-vps-ip>"
echo ""
echo "  2. Start the assistant:"
echo "     bash ~/${AGENT_WORKDIR##*/}/start-agent.sh"
echo ""
echo "  3. Pair your Discord account:"
echo "     DM your bot → get a pairing code → type it in Claude Code"
echo "     tmux attach -t assistant"
echo "     /discord:access pair <code>"
echo "     /discord:access policy allowlist"
echo ""
echo "  4. Verify vault is synced:"
echo "     ls ~/vault/"
echo ""
echo "  5. (Optional) Disable root SSH after confirming ${AGENT_USER} can login:"
echo "     sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
echo "     systemctl restart sshd"
echo ""
echo "========================================================"
