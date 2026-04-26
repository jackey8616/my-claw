#!/bin/bash
if [ -z "$BASH_VERSION" ]; then
  echo "Error: Please run with bash: bash ./setup-vps.sh"
  exit 1
fi
set -e

NON_INTERACTIVE=false
for arg in "$@"; do
  [[ "$arg" == "--non-interactive" ]] && NON_INTERACTIVE=true
done

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
APT_OPTS=(
  -o Dpkg::Options::="--force-confdef"
  -o Dpkg::Options::="--force-confold"
)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} $1"; }
warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }
pause()   { $NON_INTERACTIVE && return; read -p "$1 [Press Enter to continue]"; }

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
  local val
  val=$(grep "^${env_var_name}=" .env 2>/dev/null | cut -d '=' -f2- | tr -d '"')
  [[ -z "$val" ]] && val="${!env_var_name}"
  if [[ -n "$val" ]]; then
    echo "$val"
    return
  fi
  if $NON_INTERACTIVE; then
    error "Required variable missing: ${env_var_name}"
  fi
  read -p "Enter ${prompt_text}: " val
  update_env "$env_var_name" "$val"
  echo "$val"
}

info "Loading configuration..."
AGENT_USER=$(load_env "AGENT_USER" "dedicated user name")
R2_ACCOUNT_ID=$(load_env "R2_ACCOUNT_ID" "Cloudflare Account ID")
R2_ACCESS_KEY_ID=$(load_env "R2_ACCESS_KEY_ID" "R2 API Token Access Key ID")
R2_SECRET_ACCESS_KEY=$(load_env "R2_SECRET_ACCESS_KEY" "R2 API Token Secret Access Key")
R2_BUCKET_NAME=$(load_env "R2_BUCKET_NAME" "R2 bucket name")
DISCORD_BOT_TOKEN=$(load_env "DISCORD_BOT_TOKEN" "Discord Bot Token")
OLLAMA_API_KEY=$(load_env "OLLAMA_API_KEY" "Ollama API Key")
TIMEZONE=$(load_env "TIMEZONE" "Timezone")

AGENT_HOME="/home/${AGENT_USER}"
VAULT_LOCAL="${AGENT_HOME}/vault"
PERSONA_LOCAL="${AGENT_HOME}/vault/00-Laura-Persona"
WORKDIR=$(pwd)
AGENT_WORKDIR="${AGENT_HOME}/$(basename $WORKDIR)"

info "Creating agent user: ${AGENT_USER}"
if id "$AGENT_USER" &>/dev/null; then
  warning "User ${AGENT_USER} already exists."
else
  useradd -m -s /bin/bash "$AGENT_USER"
  mkdir -p "$AGENT_HOME"
  chown "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"
fi

info "Updating System..."
apt-get "${APT_OPTS[@]}" update -qq && apt-get "${APT_OPTS[@]}" upgrade -y -qq

info "Installing Docker..."
apt-get "${APT_OPTS[@]}" install -y -qq unzip jq bubblewrap socat uidmap gnupg
if command -v docker &>/dev/null; then
  warning "Docker already installed."
else
  curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh
fi
usermod -aG docker "$AGENT_USER"

info "Installing gh CLI..."
if ! command -v gh &>/dev/null; then
  type -p curl >/dev/null && curl -fsSL https://github.com/cli/cli/install.sh | sh
fi
info "Installing Ollama..."
if command -v ollama &>/dev/null; then
  warning "Ollama already installed."
else
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable --now ollama
fi

info "Moving workdir to ${AGENT_WORKDIR}..."
if [ "$WORKDIR" != "$AGENT_WORKDIR" ]; then
  mv "$WORKDIR" "$AGENT_WORKDIR"
  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_WORKDIR"
fi
export WORKDIR="$AGENT_WORKDIR"

info "Installing rclone..."
if command -v rclone &>/dev/null; then
  warning "rclone already installed."
else
  curl -fsSL https://rclone.org/install.sh | bash
fi

info "Configuring rclone R2 remote..."
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
"

info "Setting up vault mount..."
mkdir -p "$VAULT_LOCAL"
apt-get "${APT_OPTS[@]}" install -y -qq fuse3
chown -R "${AGENT_USER}:${AGENT_USER}" "$VAULT_LOCAL"
RCLONE_BIN=$(which rclone)
cat > /etc/systemd/system/vault-mount.service <<SYSTEMD
[Unit]
Description=rclone R2 vault FUSE mount
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
User=${AGENT_USER}
ExecStartPre=/bin/mkdir -p ${VAULT_LOCAL}
ExecStart=${RCLONE_BIN} mount r2:${R2_BUCKET_NAME} ${VAULT_LOCAL} --vfs-cache-mode full --vfs-cache-max-age 24h --vfs-cache-max-size 500M --log-level INFO
ExecStop=/bin/fusermount -uz ${VAULT_LOCAL}
Restart=on-failure
RestartSec=10
[Install]
WantedBy=multi-user.target
SYSTEMD
systemctl daemon-reload
systemctl enable vault-mount.service
systemctl start vault-mount.service || warning "vault-mount failed to start immediately."

info "Installing Hermes Agent dependencies..."
apt-get "${APT_OPTS[@]}" install -y -qq python3-pip python3-venv git ripgrep

info "Configuring Hermes static settings..."
mkdir -p "/home/${AGENT_USER}/.hermes"
cat > "/home/${AGENT_USER}/.hermes/config.yaml" <<CONFIGYAML
platforms:
  discord:
    token: "${DISCORD_BOT_TOKEN}"
    home_channel: "1486128557444042883"
providers:
  ollama:
    api_key: "${OLLAMA_API_KEY}"
    base_url: "http://localhost:11434"
settings:
  default_model: "gemma4:31b-cloud"
  timezone: "${TIMEZONE}"
CONFIGYAML

chown -R "${AGENT_USER}:${AGENT_USER}" "/home/${AGENT_USER}/.hermes"
chmod 600 "/home/${AGENT_USER}/.hermes/config.yaml"

info "Setting up Hermes Agent (Headless)..."
sudo -u "$AGENT_USER" bash -c '
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- --skip-setup
  source ~/.bashrc
'

info "Migrating legacy skills..."
sudo -u "$AGENT_USER" bash -c "
  mkdir -p \$HOME/.hermes/skills
  if [ -d '${AGENT_WORKDIR}/.claude/skills' ]; then
    cp -r ${AGENT_WORKDIR}/.claude/skills/* \$HOME/.hermes/skills/
  fi
  chown -R \$USER:\$USER \$HOME/.hermes/skills
"

info "Writing BOOTSTRAP.md..."
cat > "${AGENT_WORKDIR}/BOOTSTRAP.md" <<'CLAUDEMD'
# Bootstrap
Before doing anything else, read the full contents of
${PERSONA_LOCAL}/AGENTS.md and follow all
instructions within it.
Do not proceed until you have read that file.
CLAUDEMD
sed -i "s|\\${PERSONA_LOCAL}|${PERSONA_LOCAL}|g" "${AGENT_WORKDIR}/BOOTSTRAP.md"
chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKDIR}/BOOTSTRAP.md"

info "Installing and configuring Hermes Gateway service..."
loginctl enable-linger "$AGENT_USER"
AGENT_VENV_BIN="/home/${AGENT_USER}/.hermes/hermes-agent/venv/bin"
sudo -u "$AGENT_USER" bash -c "
  ${AGENT_VENV_BIN}/hermes gateway install
  ${AGENT_VENV_BIN}/hermes gateway start
"

info "Installing crontab..."
sudo -u "$AGENT_USER" bash -c '
  REPO="$HOME/my-claw"
  (crontab -l 2>/dev/null | grep -v "daily-summary\|midnight-archive\|weekly-ingest\|nz-news-digest"; echo "TZ=UTC"; echo "3 1 * * * /bin/bash $REPO/scripts/daily-summary.sh >> /tmp/daily-summary-cron.log 2>&1"; echo "50 23 * * * /bin/bash $REPO/scripts/midnight-archive.sh >> /tmp/midnight-archive.log 2>&1"; echo "0 3 * * 0 /bin/bash $REPO/scripts/weekly-ingest.sh >> /tmp/weekly-ingest-cron.log 2>&1"; echo "0 20 * * * /bin/bash $REPO/scripts/nz-news-digest.sh >> /tmp/nz-news-digest.log 2>&1") | crontab -
'

info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH
  ufw --force enable
fi

echo "========================================================"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo "========================================================="