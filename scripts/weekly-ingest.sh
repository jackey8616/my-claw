#!/bin/bash
# weekly-ingest.sh — 每週日 03:00 UTC 分析近期 SessionLog，更新 AGENTS.md
#
# Usage: bash weekly-ingest.sh
#
# Crontab example (UTC 03:00 every Sunday):
#   0 3 * * 0 /bin/bash /home/laura/my-claw/scripts/weekly-ingest.sh >> /tmp/weekly-ingest-cron.log 2>&1
#
# TODO: 設計 weekly-ingest Skill（參考 todos.md 的「Agent 自我迭代」項目）

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

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] weekly-ingest started"

cd "$REPO_DIR"
claude -p "/ingest" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] weekly-ingest done (exit $?)"
