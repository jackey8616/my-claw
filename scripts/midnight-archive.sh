#!/bin/bash
# midnight-archive.sh — thin wrapper that runs the /midnight-archive Skill via claude -p
#
# Usage: bash midnight-archive.sh [TMUX_TARGET]
# Default target: assistant:0.0
#
# Crontab example (UTC 23:50 daily):
#   50 23 * * * /bin/bash /home/laura/my-claw/scripts/midnight-archive.sh >> /tmp/midnight-archive.log 2>&1

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGUMENTS="${1:-}"

# Load .env (for CLAUDE_CODE_OAUTH_TOKEN etc.)
ENV_FILE="$REPO_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

cd "$REPO_DIR"
claude -p "/midnight-archive${ARGUMENTS:+ $ARGUMENTS}" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'
