#!/bin/bash
# midnight-archive.sh — 每日 23:50 UTC 執行 /archive Skill
#
# Usage: bash midnight-archive.sh
#
# Crontab example (UTC 23:50 daily):
#   50 23 * * * /bin/bash /home/laura/my-claw/scripts/midnight-archive.sh >> /tmp/midnight-archive.log 2>&1

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load .env (for CLAUDE_CODE_OAUTH_TOKEN etc.)
ENV_FILE="$REPO_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] midnight-archive started"

cd "$REPO_DIR"
claude -p "/archive" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] midnight-archive done (exit $?)"
