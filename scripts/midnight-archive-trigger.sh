#!/bin/bash
# midnight-archive-trigger.sh — force-archives the current Claude session.
#
# Flow:
#   1. Send Discord notification (heads-up to user)
#   2. Block incoming Discord messages (clear allowFrom in access.json)
#   3. Send !archive to the running Claude tmux session
#   4. Restore access.json after RESTORE_DELAY seconds (background)
#
# Usage: bash midnight-archive-trigger.sh [TMUX_TARGET]
# Default target: assistant:0.0
#
# Crontab example (UTC 23:50 daily):
#   50 23 * * * /bin/bash /home/laura/my-claw/scripts/midnight-archive-trigger.sh >> /tmp/midnight-archive.log 2>&1

set -euo pipefail

TMUX_TARGET="${1:-assistant:0.0}"
CHANNEL_ID="1486128557444042883"
ACCESS_FILE="$HOME/.claude/channels/discord/access.json"
ENV_FILE="$HOME/.claude/channels/discord/.env"
RESTORE_DELAY=120  # seconds — enough for archive + Claude restart

log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*"; }

# Load bot token
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

# 1. Notify Discord that auto-archive is about to start
if [ -n "${DISCORD_BOT_TOKEN:-}" ]; then
  curl -s -X POST "https://discord.com/api/v10/channels/${CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"content": "⏰ UTC 23:50 — 即將自動封存當前會話，Discord 暫時停止接收訊息。"}' \
    > /dev/null
  log "Discord notification sent"
  sleep 3  # brief pause so user sees the message
fi

# 2. Block incoming Discord messages by clearing allowFrom
if [ -f "$ACCESS_FILE" ]; then
  cp "$ACCESS_FILE" "${ACCESS_FILE}.bak"
  python3 - "$ACCESS_FILE" <<'PYEOF'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['allowFrom'] = []
json.dump(d, open(path, 'w'), indent=2)
PYEOF
  log "Discord incoming blocked (allowFrom cleared)"

  # Restore access.json in background after archive + restart completes
  (
    sleep $RESTORE_DELAY
    cp "${ACCESS_FILE}.bak" "$ACCESS_FILE"
    log "Discord access restored" >> /tmp/midnight-archive.log
  ) &
  disown
fi

# 3. Send !archive to the running Claude session via tmux
tmux send-keys -t "$TMUX_TARGET" "!archive" Enter
log "Sent !archive to tmux session $TMUX_TARGET"
