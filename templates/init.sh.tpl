#!/bin/bash
# init.sh.tpl — Terraform cloud-init template for openclaw VPS
# Rendered by Terraform templatestring() / templatefile(); do NOT run directly.
#
# Required Terraform variables:
#   agent_user, gh_token (optional), r2_account_id, r2_access_key_id,
#   r2_secret_access_key, r2_bucket_name, r2_e2e_password,
#   discord_bot_token, claude_oauth_token, timezone, repo_url,
#   gpg_key_path (optional; GitHub enabled only when BOTH gh_token AND gpg_key_path are set)
set -euo pipefail

# ── Inject secrets as env vars (never written to disk as plaintext) ──
export AGENT_USER="${agent_user}"
export GH_TOKEN="${gh_token}"
export R2_ACCOUNT_ID="${r2_account_id}"
export R2_ACCESS_KEY_ID="${r2_access_key_id}"
export R2_SECRET_ACCESS_KEY="${r2_secret_access_key}"
export R2_BUCKET_NAME="${r2_bucket_name}"
export R2_E2E_PASSWORD="${r2_e2e_password}"
export DISCORD_BOT_TOKEN="${discord_bot_token}"
export CLAUDE_CODE_OAUTH_TOKEN="${claude_oauth_token}"
export TIMEZONE="${timezone}"
# GitHub auto-detected: enabled only when BOTH GH_TOKEN and GPG_KEY_PATH are set
%{ if gh_token != "" ~}
export GH_TOKEN="${gh_token}"
%{ endif ~}
%{ if gpg_key_path != "" ~}
export GPG_KEY_PATH="${gpg_key_path}"
%{ endif ~}

# ── Clone repo ──
apt-get install -y -qq git
REPO_NAME=$(basename "${repo_url}" .git)
git clone "${repo_url}" /root/"$REPO_NAME"
cd /root/"$REPO_NAME"

# ── Run setup in non-interactive mode ──
bash setup-new-vps.sh --non-interactive
