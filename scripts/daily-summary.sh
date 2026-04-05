#!/bin/bash
# daily-summary.sh — thin wrapper that runs the /daily-summary Skill via claude -p
#
# Usage: bash daily-summary.sh [YYYY-MM-DD]
# Default date: today (TZ from environment, fallback UTC)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_FILE="$REPO_DIR/.claude/skills/daily-summary/SKILL.md"
ARGUMENTS="${1:-}"

# Load .env (for DISCORD_BOT_TOKEN etc.)
ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Read skill content
PROMPT=$(cat "$SKILL_FILE")

# Substitute !`command` shell injections
while [[ "$PROMPT" =~ \!\`([^\`]+)\` ]]; do
  cmd="${BASH_REMATCH[1]}"
  output=$(eval "$cmd")
  PROMPT="${PROMPT//"!\`${cmd}\`"/$output}"
done

# Substitute $ARGUMENTS
PROMPT="${PROMPT//\$ARGUMENTS/$ARGUMENTS}"

cd "$REPO_DIR"
claude -p "$PROMPT" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'
