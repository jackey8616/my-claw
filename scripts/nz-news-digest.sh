#!/bin/bash
# nz-news-digest.sh — daily NZ news cross-reference digest posted to Discord
#
# Usage: bash nz-news-digest.sh
# Crontab (UTC 20:00 daily = ~8am NZST):
#   0 20 * * * /bin/bash /home/laura/my-claw/scripts/nz-news-digest.sh >> /tmp/nz-news-digest.log 2>&1

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="$REPO_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] nz-news-digest started"

cd "$REPO_DIR"
claude -p "/nz-news-digest" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] nz-news-digest done (exit $?)"
