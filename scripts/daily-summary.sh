#!/bin/bash
# daily-summary.sh — thin wrapper that runs the /daily-summary Skill via claude -p
#
# Usage: bash daily-summary.sh [YYYY-MM-DD]
# Default date: today (TZ from environment, fallback UTC)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGUMENTS="${1:-}"

# Load .env (for DISCORD_BOT_TOKEN, CLAUDE_CODE_OAUTH_TOKEN etc.)
ENV_FILE="$REPO_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Invoke the skill by name; let Claude handle skill loading and tool permissions
PROMPT="/daily-summary${ARGUMENTS:+ $ARGUMENTS}"

cd "$REPO_DIR"
claude -p "$PROMPT" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'
