     1|#!/bin/bash
     2|if [ -z "$BASH_VERSION" ]; then
     3|  echo "Error: Please run with bash: bash ./setup-vps.sh"
     4|  exit 1
     5|fi
     6|set -e
     7|
     8|NON_INTERACTIVE=false
     9|for arg in "$@"; do
    10|  [[ "$arg" == "--non-interactive" ]] && NON_INTERACTIVE=true
    11|done
    12|
    13|export DEBIAN_FRONTEND=noninteractive
    14|export DEBCONF_NONINTERACTIVE_SEEN=true
    15|APT_OPTS=(
    16|  -o Dpkg::Options::="--force-confdef"
    17|  -o Dpkg::Options::="--force-confold"
    18|)
    19|
    20|GREEN='\033[0;32m'
    21|YELLOW='\033[1;33m'
    22|RED='\033[0;31m'
    23|NC='\033[0m'
    24|
    25|info()    { echo -e "${GREEN}==>${NC} $1"; }
    26|warning() { echo -e "${YELLOW}Warning:${NC} $1"; }
    27|error()   { echo -e "${RED}Error:${NC} $1"; exit 1; }
    28|pause()   { $NON_INTERACTIVE && return; read -p "$1 [Press Enter to continue]"; }
    29|
    30|update_env() {
    31|  local var_name=$1
    32|  local var_value=$2
    33|  if grep -q "^${var_name}=" .env 2>/dev/null; then
    34|    sed -i "s|^${var_name}=.*|${var_name}=\"${var_value}\"|" .env
    35|  else
    36|    echo "${var_name}=\"${var_value}\"" >> .env
    37|  fi
    38|}
    39|
    40|load_env() {
    41|  local env_var_name=$1
    42|  local prompt_text=${2:-$1}
    43|  local val
    44|  val=$(grep "^${env_var_name}=" .env 2>/dev/null | cut -d '=' -f2- | tr -d '"')
    45|  [[ -z "$val" ]] && val="${!env_var_name}"
    46|  if [[ -n "$val" ]]; then
    47|    echo "$val"
    48|    return
    49|  fi
    50|  if $NON_INTERACTIVE; then
    51|    error "Required variable missing: ${env_var_name}"
    52|  fi
    53|  read -p "Enter ${prompt_text}: " val
    54|  update_env "$env_var_name" "$val"
    55|  echo "$val"
    56|}
    57|
    58|info "Loading configuration..."
    59|AGENT_USER=$(load_env "AGENT_USER" "dedicated user name")
    60|R2_ACCOUNT_ID=$(load_env "R2_ACCOUNT_ID" "Cloudflare Account ID")
    61|R2_ACCESS_KEY_ID=$(load_env "R2_ACCESS_KEY_ID" "R2 API Token Access Key ID")
    62|R2_SECRET_ACCESS_KEY=*** "R2_SECRET_ACCESS_KEY" "R2 API Token Secret Access Key")
    63|R2_BUCKET_NAME=$(load_env "R2_BUCKET_NAME" "R2 bucket name")
    64|DISCORD_BOT_TOKEN=*** "DISCORD_BOT_TOKEN" "Discord Bot Token")
    65|OLLAMA_API_KEY=*** "OLLAMA_API_KEY" "Ollama API Key")
    66|TIMEZONE=$(load_env "TIMEZONE" "Timezone")
    67|
    68|AGENT_HOME="/home/${AGENT_USER}"
    69|VAULT_LOCAL="${AGENT_HOME}/vault"
    70|PERSONA_LOCAL="${AGENT_HOME}/vault/00-Laura-Persona"
    71|WORKDIR=$(pwd)
    72|AGENT_WORKDIR="${AGENT_HOME}/$(basename $WORKDIR)"
    73|
    74|info "Creating agent user: ${AGENT_USER}"
    75|if id "$AGENT_USER" &>/dev/null; then
    76|  warning "User ${AGENT_USER} already exists."
    77|else
    78|  useradd -m -s /bin/bash "$AGENT_USER"
    79|  mkdir -p "$AGENT_HOME"
    80|  chown "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"
    81|fi
    82|
    83|info "Installing Docker..."
    84|apt-get "${APT_OPTS[@]}" update -qq && apt-get "${APT_OPTS[@]}" upgrade -y -qq
    85|apt-get "${APT_OPTS[@]}" install -y -qq unzip jq bubblewrap socat uidmap gnupg
    86|if command -v docker &>/dev/null; then
    87|  warning "Docker already installed."
    88|else
    89|  curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh
    90|fi
    91|usermod -aG docker "$AGENT_USER"
    92|
    93|info "Installing gh CLI..."
    94|if ! command -v gh &>/dev/null; then
    95|  type -p curl >/dev/null && curl -fsSL https://github.com/cli/cli/install.sh | sh
    96|fi
    97|info "Installing Ollama..."
    98|if command -v ollama &>/dev/null; then
    99|  warning "Ollama already installed."
   100|else
   101|  curl -fsSL https://ollama.com/install.sh | sh
  systemctl enable --now ollama
   102|fi
   103|
   104|info "Moving workdir to ${AGENT_WORKDIR}..."
   105|if [ "$WORKDIR" != "$AGENT_WORKDIR" ]; then
   106|  mv "$WORKDIR" "$AGENT_WORKDIR"
   107|  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_WORKDIR"
   108|fi
   109|export WORKDIR="$AGENT_WORKDIR"
   110|
   111|info "Installing rclone..."
   112|if command -v rclone &>/dev/null; then
   113|  warning "rclone already installed."
   114|else
   115|  curl -fsSL https://rclone.org/install.sh | bash
   116|fi
   117|
   118|info "Configuring rclone R2 remote..."
   119|sudo -u "$AGENT_USER" bash -c "
   120|  mkdir -p \$HOME/.config/rclone
   121|  cat > \$HOME/.config/rclone/rclone.conf <<RCLONECONF
   122|[r2]
   123|type = s3
   124|provider = Cloudflare
   125|access_key_id = ${R2_ACCESS_KEY_ID}
   126|secret_access_key = ${R2_SECRET_ACCESS_KEY}
   127|endpoint = https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com
   128|acl = private
   129|RCLONECONF
   130|  chmod 600 \$HOME/.config/rclone/rclone.conf
   131|"
   132|
   133|info "Setting up vault mount..."
   134|mkdir -p "$VAULT_LOCAL"
   135|apt-get "${APT_OPTS[@]}" install -y -qq fuse3
   136|chown -R "${AGENT_USER}:${AGENT_USER}" "$VAULT_LOCAL"
   137|RCLONE_BIN=$(which rclone)
   138|cat > /etc/systemd/system/vault-mount.service <<SYSTEMD
   139|[Unit]
   140|Description=rclone R2 vault FUSE mount
   141|After=network-online.target
   142|Wants=network-online.target
   143|[Service]
   144|Type=notify
   145|User=${AGENT_USER}
   146|ExecStartPre=/bin/mkdir -p ${VAULT_LOCAL}
   147|ExecStart=${RCLONE_BIN} mount r2:${R2_BUCKET_NAME} ${VAULT_LOCAL} --vfs-cache-mode full --vfs-cache-max-age 24h --vfs-cache-max-size 500M --log-level INFO
   148|ExecStop=/bin/fusermount -uz ${VAULT_LOCAL}
   149|Restart=on-failure
   150|RestartSec=10
   151|[Install]
   152|WantedBy=multi-user.target
   153|SYSTEMD
   154|systemctl daemon-reload
   155|systemctl enable vault-mount.service
   156|systemctl start vault-mount.service || warning "vault-mount failed to start immediately."
   157|
   158|info "Installing Hermes Agent (Headless)..."
   159|sudo -u "$AGENT_USER" bash -c '
   160|  apt-get update -qq && apt-get install -y -qq python3-pip python3-venv git
   161|  python3 -m venv ~/.hermes-venv
   162|  ~/.hermes-venv/bin/pip install --upgrade pip
   163|  ~/.hermes-venv/bin/pip install hermes-agent
   164|  if ! grep -q ".hermes-venv/bin" \$HOME/.bashrc 2>/dev/null; then
   165|    echo "export PATH=\"\$HOME/.hermes-venv/bin:\$PATH\"" >> \$HOME/.bashrc
   166|  fi
   167|'
   168|
   169|info "Configuring Hermes static settings..."
   170|sudo -u "$AGENT_USER" bash -c "
   171|  mkdir -p \$HOME/.hermes
   172|  cat > \$HOME/.hermes/config.yaml <<CONFIGYAML
   173|platforms:
   174|  discord:
   175|    token: \"\${DISCORD_BOT_TOKEN}\"
   176|    home_channel: \"1486128557444042883\"
   177|providers:
   178|  ollama:
   179|    api_key: \"\${OLLAMA_API_KEY}\"
   180|    base_url: \"http://localhost:11434\"
   181|settings:
   182|  default_model: \"gemma4:31b-cloud\"
   183|  timezone: \"\${TIMEZONE}\"
   184|CONFIGYAML
   185|  chmod 600 \$HOME/.hermes/config.yaml
   186|"
   187|
   188|info "Migrating legacy skills..."
   189|sudo -u "$AGENT_USER" bash -c "
   190|  mkdir -p \$HOME/.hermes/skills
   191|  if [ -d '${AGENT_WORKDIR}/.claude/skills' ]; then
   192|    cp -r ${AGENT_WORKDIR}/.claude/skills/* \$HOME/.hermes/skills/
   193|  fi
   194|  chown -R \$USER:\$USER \$HOME/.hermes/skills
   195|"
   196|
   197|info "Writing BOOTSTRAP.md..."
   198|cat > "${AGENT_WORKDIR}/BOOTSTRAP.md" <<'CLAUDEMD'
   199|# Bootstrap
   200|Before doing anything else, read the full contents of
   201|${PERSONA_LOCAL}/AGENTS.md and follow all
   202|instructions within it.
   203|Do not proceed until you have read that file.
   204|CLAUDEMD
   205|sed -i "s|\\${PERSONA_LOCAL}|${PERSONA_LOCAL}|g" "${AGENT_WORKDIR}/BOOTSTRAP.md"
   206|chown "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKDIR}/BOOTSTRAP.md"
   207|
   208|info "Writing start-agent.sh..."
   209|cat > "${AGENT_WORKDIR}/start-agent.sh" <<'STARTSCRIPT'
#!/bin/bash
# Start Hermes Assistant in a persistent tmux session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TZ="$TIMEZONE"
SESSION="assistant"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already running. Attaching..."
  tmux attach -t "$SESSION"
else
  echo "Starting new Hermes session..."
  tmux new-session -d -s "$SESSION" -x 220 -y 50
  tmux send-keys -t "$SESSION" "source ~/.bashrc && cd ${SCRIPT_DIR} && hermes launch" Enter
  tmux attach -t "$SESSION"
fi

STARTSCRIPT
   222|chmod +x "${AGENT_WORKDIR}/start-agent.sh"
   223|chown "${AGENT_USER}:${AGENT_USER} "${AGENT_WORKDIR}/start-agent.sh"
   224|
   225|apt-get "${APT_OPTS[@]}" install -y tmux -qq
   226|
   227|info "Installing crontab..."
   228|sudo -u "$AGENT_USER" bash -c '
   229|  REPO="$HOME/my-claw"
   230|  (crontab -l 2>/dev/null | grep -v "daily-summary\|midnight-archive\|weekly-ingest\|nz-news-digest"; echo "TZ=UTC"; echo "3 1 * * * /bin/bash $REPO/scripts/daily-summary.sh >> /tmp/daily-summary-cron.log 2>&1"; echo "50 23 * * * /bin/bash $REPO/scripts/midnight-archive.sh >> /tmp/midnight-archive.log 2>&1"; echo "0 3 * * 0 /bin/bash $REPO/scripts/weekly-ingest.sh >> /tmp/weekly-ingest-cron.log 2>&1"; echo "0 20 * * * /bin/bash $REPO/scripts/nz-news-digest.sh >> /tmp/nz-news-digest.log 2>&1") | crontab -
   231|'
   232|
   233|info "Configuring firewall..."
   234|if command -v ufw &>/dev/null; then
   235|  ufw allow OpenSSH
   236|  ufw --force enable
   237|fi
   238|
   239|echo "========================================================"
   240|echo -e "${GREEN}✅ Setup complete!${NC}"
   241|echo "========================================================"
   242|