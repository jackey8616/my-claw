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
#   2.  Install Docker (general purpose, no longer used for vault sync)
#   3.  Move workdir to agent home
#   4.  Install rclone + configure Cloudflare R2 + systemd vault mount
#   5.  Install Node.js + Claude Code (native)
#   6.  Install Bun (required for Channels plugins)
#   7.  Configure Claude Code auth (OAuth Token)
#   7.2 Install MCP server dependencies (.mcp.json is in repo)
#   7.5 Configure Claude Code Hooks
#   8.  Install Discord Channels plugin
#   9.  Write CLAUDE.md pointing to Persona in vault
#   10. Write tmux startup script
#   11. Firewall
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
R2_ACCOUNT_ID=$(load_env "R2_ACCOUNT_ID" "Cloudflare Account ID (from R2 dashboard)")
R2_ACCESS_KEY_ID=$(load_env "R2_ACCESS_KEY_ID" "R2 API Token Access Key ID (vps-rclone token)")
R2_SECRET_ACCESS_KEY=$(load_env "R2_SECRET_ACCESS_KEY" "R2 API Token Secret Access Key (vps-rclone token)")
R2_BUCKET_NAME=$(load_env "R2_BUCKET_NAME" "R2 bucket name (e.g. laura-vault)")
R2_E2E_PASSWORD=$(load_env "R2_E2E_PASSWORD" "Remotely Save E2E encryption password (shared with Mac/iPhone)")
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
apt-get install -y -qq unzip jq bubblewrap socat uidmap gnupg

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
# 4. Install rclone + configure Cloudflare R2 + systemd vault mount
# ============================================================
info "Installing rclone..."
if command -v rclone &>/dev/null; then
  warning "rclone already installed ($(rclone --version | head -1)), skipping."
else
  curl -fsSL https://rclone.org/install.sh | bash
fi

info "Configuring rclone R2 remote for ${AGENT_USER}..."
sudo -u "$AGENT_USER" bash -c "
  mkdir -p \$HOME/.config/rclone
  cat > \$HOME/.config/rclone/rclone.conf <<RCLONECONF
[r2]
type = s3
provider = Cloudflare
access_key_id = ${R2_ACCESS_KEY_ID}
secret_access_key = ${R2_SECRET_ACCESS_KEY}
endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
acl = private
RCLONECONF
  chmod 600 \$HOME/.config/rclone/rclone.conf
  echo '    rclone config written.'
"

info "Verifying R2 connection..."
sudo -u "$AGENT_USER" bash -c "
  rclone lsd r2:${R2_BUCKET_NAME} --max-depth 1 2>&1 | head -5 || true
"

info "Creating vault directory and setting up systemd mount service..."
mkdir -p "$VAULT_LOCAL"
apt-get install -y -qq fuse3
chown -R "${AGENT_USER}:${AGENT_USER}" "$VAULT_LOCAL"

RCLONE_BIN=$(which rclone)
cat > /etc/systemd/system/vault-mount.service <<SYSTEMD
[Unit]
Description=rclone R2 vault FUSE mount
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
User=${AGENT_USER}
ExecStartPre=/bin/mkdir -p ${VAULT_LOCAL}
ExecStart=${RCLONE_BIN} mount r2:${R2_BUCKET_NAME} ${VAULT_LOCAL} \\
  --vfs-cache-mode full \\
  --vfs-cache-max-age 24h \\
  --vfs-cache-max-size 500M \\
  --daemon \\
  --log-file /var/log/rclone-vault.log \\
  --log-level INFO
ExecStop=/bin/fusermount -uz ${VAULT_LOCAL}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable vault-mount.service
systemctl start vault-mount.service

info "Waiting for vault mount to settle..."
sleep 5

if mountpoint -q "$VAULT_LOCAL"; then
  info "Vault mounted successfully at ${VAULT_LOCAL}."
else
  warning "Vault mount may not be ready yet. Check: systemctl status vault-mount.service"
fi

# Verify vault has AGENTS.md
if [ ! -f "${PERSONA_LOCAL}/AGENTS.md" ]; then
  warning "AGENTS.md not found (${PERSONA_LOCAL}/AGENTS.md)."
  warning "Make sure Mac has synced vault to R2 before this step."
  pause "Press Enter to continue anyway..."
fi

# ============================================================
# 5. Install Node.js + Claude Code (native, not Docker)
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

  # Fix missing execute bit on seccomp helper (required for sandbox to work)
  SECCOMP_BIN=\"\$(npm root -g)/@anthropic-ai/claude-code/vendor/seccomp/x64/apply-seccomp\"
  if [ -f \"\$SECCOMP_BIN\" ]; then
    chmod +x \"\$SECCOMP_BIN\"
    echo '    Fixed apply-seccomp execute bit.'
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
# 6. Install Bun (required for Claude Code Channels plugins)
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
# 7. Configure Claude Code auth (OAuth Token)
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
# 7.2 Install MCP server dependencies
# ============================================================
info "Installing MCP server dependencies..."

sudo -u "$AGENT_USER" bash -c "
  export BUN_INSTALL=\"\$HOME/.bun\"
  export PATH=\"\$BUN_INSTALL/bin:\$PATH\"

  cd ${AGENT_WORKDIR}/mcp-servers/memory && bun install --frozen-lockfile
  echo '    Memory server deps installed.'
"

info "MCP deps installed. Config is in .mcp.json (checked into repo)."

# ============================================================
# 7.3 Install Playwright + Chromium (for fetch-external MCP)
# ============================================================
info "Installing Playwright MCP + Chromium..."

# Install @playwright/mcp locally so .mcp.json can reference node_modules/.bin/playwright-mcp
sudo -u "$AGENT_USER" bash -c "
  export NVM_DIR=\"\$HOME/.nvm\"
  source \"\$NVM_DIR/nvm.sh\"
  cd ${AGENT_WORKDIR}
  if [ -d 'node_modules/@playwright/mcp' ]; then
    echo '    @playwright/mcp already installed, skipping.'
  else
    npm install @playwright/mcp
    echo '    @playwright/mcp installed.'
  fi
"

# Install Chromium system dependencies (requires root)
AGENT_NODE=$(sudo -u "$AGENT_USER" bash -c 'export NVM_DIR="$HOME/.nvm"; source "$NVM_DIR/nvm.sh"; which node')
PLAYWRIGHT_BIN="${AGENT_WORKDIR}/node_modules/.bin/playwright"
if [ -f "$PLAYWRIGHT_BIN" ]; then
  "$AGENT_NODE" "$PLAYWRIGHT_BIN" install-deps chromium
  info "Chromium system deps installed."
else
  warning "playwright binary not found at ${PLAYWRIGHT_BIN}, skipping install-deps."
fi

# Download Chromium browser binary (as agent user, stored in ~/.cache/ms-playwright/)
sudo -u "$AGENT_USER" bash -c "
  export NVM_DIR=\"\$HOME/.nvm\"
  source \"\$NVM_DIR/nvm.sh\"
  cd ${AGENT_WORKDIR}
  node node_modules/.bin/playwright install chromium
  echo '    Chromium browser binary downloaded.'
"

info "Playwright + Chromium ready."

# ============================================================
# 7.4 GitHub integration (optional: GH_TOKEN + GPG signing)
# ============================================================
info "GitHub integration (optional)..."

GPG_KEY_PATH="${PERSONA_LOCAL}/laura-bot.gpg.asc"

read -p "Set up GitHub integration (GH_TOKEN + GPG signing)? (y/N): " setup_github
if [[ "$setup_github" =~ ^[Yy]$ ]]; then
  GH_TOKEN=$(load_env "GH_TOKEN" "GitHub Personal Access Token (repo + write:gpg_key scope)")

  # Resolve GitHub account primary email
  GPG_EMAIL=$(curl -s -H "Authorization: Bearer ${GH_TOKEN}" \
    https://api.github.com/user/emails | \
    jq -r '[.[] | select(.primary == true and .verified == true)] | .[0].email')
  if [[ -z "$GPG_EMAIL" || "$GPG_EMAIL" == "null" ]]; then
    error "Could not resolve a verified primary email from GitHub. Check GH_TOKEN scope (needs user:email or read:user)."
  fi
  info "Using GitHub email for GPG key: ${GPG_EMAIL}"

  sudo -u "$AGENT_USER" bash -c "
    GPG_KEY_PATH='${GPG_KEY_PATH}'
    GPG_EMAIL='${GPG_EMAIL}'

    if [ -f \"\$GPG_KEY_PATH\" ]; then
      echo '    Importing existing Laura bot GPG key from vault...'
      gpg --batch --import \"\$GPG_KEY_PATH\"
    else
      echo '    Generating new Laura bot GPG key...'
      gpg --batch --gen-key <<GPGBATCH
%no-protection
Key-Type: EdDSA
Key-Curve: ed25519
Name-Real: Laura
Name-Email: ${GPG_EMAIL}
Expire-Date: 0
GPGBATCH
      KEY_ID=\$(gpg --list-secret-keys --keyid-format LONG \"\$GPG_EMAIL\" 2>/dev/null | grep '^sec' | awk '{print \$2}' | cut -d'/' -f2 | head -1)
      gpg --armor --export-secret-keys \"\$KEY_ID\" > \"\$GPG_KEY_PATH\"
      echo \"    Key exported to vault: \$GPG_KEY_PATH\"
    fi

    KEY_ID=\$(gpg --list-secret-keys --keyid-format LONG \"\$GPG_EMAIL\" 2>/dev/null | grep '^sec' | awk '{print \$2}' | cut -d'/' -f2 | head -1)
    git config --global user.signingkey \"\$KEY_ID\"
    git config --global commit.gpgsign true
    git config --global gpg.program gpg
    echo \"    Git signing configured with key: \$KEY_ID\"
  "

  info "GitHub integration enabled."
else
  warning "Skipping GitHub integration. GitHub skill will be disabled."
fi

# ============================================================
# 7.5 Configure Claude Code Hooks
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

  # 依資料夾名稱排序，逐一讀取 claude_event_name 並註冊 on-event.sh
  find '${HOOKS_DIR}' -mindepth 1 -maxdepth 1 -type d | sort | while read -r hook_dir; do
    EVENT_FILE=\"\${hook_dir}/claude_event_name\"

    if [ ! -f \"\$EVENT_FILE\" ]; then
      echo \"    Skipping \$(basename \$hook_dir): no claude_event_name found\"
      continue
    fi

    EVENT=\$(cat \"\$EVENT_FILE\" | tr -d '[:space:]')
    SCRIPT=\"\${hook_dir}/on-event.sh\"

    if [ ! -f \"\$SCRIPT\" ]; then
      echo \"    Skipping [\${EVENT}]: on-event.sh not found in \$(basename \$hook_dir)\"
      continue
    fi

    jq \".hooks.\${EVENT} += [{\\\"hooks\\\": [{\\\"type\\\": \\\"command\\\", \\\"command\\\": \\\"\$SCRIPT\\\"}]}]\" \
      \"\$GLOBAL_SETTINGS\" > /tmp/claude-settings-merged.json
    mv /tmp/claude-settings-merged.json \"\$GLOBAL_SETTINGS\"
    echo \"    Registered [\${EVENT}]: \$SCRIPT\"
  done

  chmod 600 \"\$GLOBAL_SETTINGS\"
"

info "hooks installed."

# ============================================================
# 8. Install Discord Channels plugin
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
# 9. Write CLAUDE.md (repo root, points to vault AGENTS.md)
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
# 10. tmux startup script
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
# 11. AppArmor profile for bubblewrap (Ubuntu 24.04+)
# ============================================================
info "Configuring AppArmor profile for bubblewrap..."
# Ubuntu 24.04 restricts unprivileged user namespaces by default.
# bwrap requires a profile granting 'userns' permission to function.
if sysctl -n kernel.apparmor_restrict_unprivileged_userns 2>/dev/null | grep -q "1"; then
  cat > /etc/apparmor.d/bwrap <<'AAPROFILE'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/bwrap flags=(unconfined) {
  userns,
}
AAPROFILE
  apparmor_parser -r /etc/apparmor.d/bwrap
  info "AppArmor profile for bwrap loaded."
else
  info "AppArmor userns restriction not active, skipping."
fi

# ============================================================
# 12. Firewall
# ============================================================
info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH
  ufw --force enable
  info "UFW configured. rclone R2 uses outbound HTTPS only — no inbound ports needed."
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
echo "  4. Verify vault is mounted:"
echo "     mountpoint ~/vault && ls ~/vault/"
echo ""
echo "  5. (Optional) Disable root SSH after confirming ${AGENT_USER} can login:"
echo "     sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config"
echo "     systemctl restart sshd"
echo ""
echo "========================================================"
