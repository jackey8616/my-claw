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

# Helper to apply templates by replacing {{VAR}} with current shell variables
apply_template() {
  local template_path=$1
  local output_path=$2
  info "Applying template ${template_path} -> ${output_path}"
  
  local content
  content=$(cat "$template_path")
  
  # Replace common placeholders. We use a loop to handle all defined variables.
  # This regex finds all {{VAR_NAME}} patterns and replaces them with the value of the shell variable VAR_NAME.
  while [[ $content =~ \{\{([A-Z0-9_]+)\}\} ]]; do
    local var_name="${BASH_REMATCH[1]}"
    local var_value="${!var_name}"
    content="${content//\{\{$var_name\}\}/$var_value}"
  done
  
  echo "$content" > "$output_path"
}

update_env() {
  local var_name=$1
  local var_value=$2
  if grep -q "^${var_name}=" .env 2>/dev/null; then
    sed -i "s|^${var_name}=.*|${var_name}=\"\${var_value}\"|" .env
  else
    echo "${var_name}=\"\${var_value}\"" >> .env
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

# ── Configuration ────────────────────────────────────────────────────────────
info "Loading configuration..."
AGENT_USER=$(load_env "AGENT_USER" "dedicated user name")
R2_ACCOUNT_ID=$(load_env "R2_ACCOUNT_ID" "Cloudflare Account ID")
R2_ACCESS_KEY_ID=$(load_env "R2_ACCESS_KEY_ID" "R2 API Token Access Key ID")
R2_SECRET_ACCESS_KEY=$(load_env "R2_SECRET_ACCESS_KEY" "R2 API Token Secret Access Key")
R2_BUCKET_NAME=$(load_env "R2_BUCKET_NAME" "R2 bucket name")
DISCORD_BOT_TOKEN=$(load_env "DISCORD_BOT_TOKEN" "Discord Bot Token")
OLLAMA_API_KEY=$(load_env "OLLAMA_API_KEY" "Ollama API Key")
TIMEZONE=$(load_env "TIMEZONE" "Timezone")

# Docker image for Hermes Agent
HERMES_IMAGE="${HERMES_IMAGE:-nousresearch/hermes-agent:latest}"

HOST_AGENT_HOME="/home/${AGENT_USER}"
HOST_VAULT="${HOST_AGENT_HOME}/vault"
WORKDIR=$(pwd)
REPO_NAME=$(basename "$WORKDIR")
REPO_WORKDIR="${HOST_AGENT_HOME}/${REPO_NAME}"
HERMES_STATEFUL_DATA_DIR="${HOST_VAULT}/00-Laura-Persona"

# Template Variables
AGENT_UID=$(id -u "$AGENT_USER" 2>/dev/null || echo 1000)
AGENT_GID=$(id -g "$AGENT_USER" 2>/dev/null || echo 1000)

# ── User ─────────────────────────────────────────────────────────────────────
info "Creating agent user: ${AGENT_USER}"
if id "$AGENT_USER" &>/dev/null; then
  warning "User ${AGENT_USER} already exists."
else
  useradd -m -s /bin/bash "$AGENT_USER"
  chown "${AGENT_USER}:${AGENT_USER}" "$HOST_AGENT_HOME"
fi

# ── System packages ───────────────────────────────────────────────────────────
info "Updating system..."
apt-get "${APT_OPTS[@]}" update -qq
apt-get "${APT_OPTS[@]}" upgrade -y -qq

info "Installing base packages..."
apt-get "${APT_OPTS[@]}" install -y -qq \
  unzip jq curl fuse3

info "Configuring FUSE..."
sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

# ── Docker ────────────────────────────────────────────────────────────────────
info "Installing Docker..."
if command -v docker &>/dev/null; then
  warning "Docker already installed."
else
  curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh
fi
usermod -aG docker "$AGENT_USER"

# ── Ollama ────────────────────────────────────────────────────────────────────
info "Installing Ollama..."
if command -v ollama &>/dev/null; then
  warning "Ollama already installed."
else
  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable --now ollama
fi

# ── Move workdir ──────────────────────────────────────────────────────────────
info "Moving workdir to ${REPO_WORKDIR}..."
if [ "$WORKDIR" != "$REPO_WORKDIR" ]; then
  mv "$WORKDIR" "$REPO_WORKDIR"
  chown -R "${AGENT_USER}:${AGENT_USER}" "$REPO_WORKDIR"
fi
export WORKDIR="$REPO_WORKDIR"

# ── rclone ────────────────────────────────────────────────────────────────────
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

# ── Vault FUSE mount ──────────────────────────────────────────────────────────
info "Setting up vault mount..."
mkdir -p "$HOST_VAULT"
chown -R "${AGENT_USER}:${AGENT_USER}" "$HOST_VAULT"

RCLONE_BIN=$(which rclone)
apply_template "templates/vault-mount.service.tpl" "/etc/systemd/system/vault-mount.service"

systemctl daemon-reload
systemctl enable vault-mount.service
fusermount -uz "$HOST_VAULT" 2>/dev/null || true
systemctl restart vault-mount.service || warning "vault-mount failed to start immediately."

WAIT=1
for i in $(seq 1 5); do
  mountpoint -q "$HOST_VAULT" && break
  warning "Vault not mounted yet, retrying in ${WAIT}s... (attempt $i/5)"
  sleep $WAIT
  WAIT=$((2 ** i))
done
mountpoint -q "$HOST_VAULT" || error "vault-mount failed to start after 5 attempts"

# ── Hermes – Docker setup ─────────────────────────────────────────────────────
info "Setting up Hermes Agent via Docker..."

DOTENV_PATH="${REPO_WORKDIR}/.env"
cat > "$DOTENV_PATH" <<EOF
OLLAMA_API_KEY=${OLLAMA_API_KEY}
DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
DISCORD_ALLOWED_USERS=201941454946304001
DISCORD_HOME_CHANNEL=1486128557444042883
TZ=${TIMEZONE}
EOF
chown "${AGENT_USER}:${AGENT_USER}" "$DOTENV_PATH"
chmod 644 "$DOTENV_PATH"

# Apply docker-compose template
apply_template "templates/docker-compose.yml.tpl" "${REPO_WORKDIR}/docker-compose.yml"
chown "${AGENT_USER}:${AGENT_USER}" "${REPO_WORKDIR}/docker-compose.yml"

# Install systemd service
info "Installing Hermes systemd service..."
loginctl enable-linger "$AGENT_USER"
apply_template "templates/hermes-agent.service.tpl" "/etc/systemd/system/hermes-agent.service"

systemctl daemon-reload
systemctl enable hermes-agent.service
systemctl restart hermes-agent.service || warning "hermes-agent failed to start – check: journalctl -u hermes-agent"

# ── Sudoers ───────────────────────────────────────────────────────────────────
info "Configuring sudoers for ${AGENT_USER}..."
cat > "/etc/sudoers.d/${AGENT_USER}-services" <<SUDOERS
${AGENT_USER} ALL=(ALL) NOPASSWD: \
  /bin/systemctl start hermes-agent.service, \
  /bin/systemctl stop hermes-agent.service, \
  /bin/systemctl restart hermes-agent.service, \
  /bin/systemctl status hermes-agent.service, \
  /bin/systemctl start vault-mount.service, \
  /bin/systemctl stop vault-mount.service, \
  /bin/systemctl restart vault-mount.service, \
  /bin/systemctl status vault-mount.service
SUDOERS
chmod 440 "/etc/sudoers.d/${AGENT_USER}-services"

# ── Firewall ──────────────────────────────────────────────────────────────────
info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow OpenSSH
  ufw --force enable
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo "========================================================"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "  Hermes container:  sudo systemctl status hermes-agent"
echo "  Live logs:         journalctl -u hermes-agent -f"
echo "  Compose dir:       ${REPO_WORKDIR}"
echo "  Vault mount:       ${HOST_VAULT}"
echo "========================================================"
