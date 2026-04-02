#!/bin/bash
# daily-summary.sh — Walk all session logs for a given day, generate a
# consolidated daily summary, and append it to the Daily Note.
#
# Usage: bash daily-summary.sh [YYYY-MM-DD]
# Default date: today in local TZ ($TZ env var or UTC).
  
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="$HOME/vault"
SESSION_LOGS_DIR="$VAULT/01-Session-Logs"
DAILY_DIR="$VAULT/04-Daily-Notes"
HOOK_SETTINGS="$SCRIPT_DIR/hooks/99-session-archive/claude-hook-settings.json"
ENV_FILE="$SCRIPT_DIR/.env"
LOGFILE="/tmp/daily-summary-debug.log"

# Load .env (DISCORD_BOT_TOKEN, TZ, CLAUDE_CODE_OAUTH_TOKEN, etc.)
if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1090
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
  
DISCORD_CHANNEL_ID="1486128557444042883"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

discord_send() {
  local msg="$1"
  [ -z "${DISCORD_BOT_TOKEN:-}" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# ---------------------------------------------------------------------------
# Date & paths
# ---------------------------------------------------------------------------
DATE="${1:-$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')}"
DAILY_NOTE="$DAILY_DIR/$DATE.md"
TIMESTAMP=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d %H:%M %Z')

log "=== Daily summary start: $DATE ==="

# ---------------------------------------------------------------------------
# Collect session logs
# ---------------------------------------------------------------------------
mapfile -t SESSION_FILES < <(ls "$SESSION_LOGS_DIR/${DATE}_"*.md 2>/dev/null || true)
COUNT=${#SESSION_FILES[@]}

if [ "$COUNT" -eq 0 ]; then
  log "No session logs found for $DATE — exiting."
  exit 0
fi

log "Found $COUNT session log(s)."

# Build combined input — include filename as a separator so Claude has context
COMBINED=""
for f in "${SESSION_FILES[@]}"; do
  COMBINED+="### $(basename "$f" .md)"$'\n\n'
  COMBINED+="$(cat "$f")"$'\n\n---\n\n'
done

# Truncate to ~60 000 chars to stay within haiku context safely
COMBINED="${COMBINED:0:60000}"

# ---------------------------------------------------------------------------
# Generate summary via Claude
# ---------------------------------------------------------------------------
log "Calling Claude (haiku) to generate summary..."

SUMMARY=$(cd /tmp && printf '%s' "$COMBINED" | claude -p \
"以下是 ${DATE} 當天所有 session logs（共 ${COUNT} 個）。
請用繁體中文產生一份日摘要。只輸出以下格式的內容，不要任何額外說明或開場白：

## 今日總覽

[2-3 句整體摘要，說明今天完成了什麼]

## 技術決策

[條列今天做出的重要技術決策，格式：「**決策**：原因」]

## 學到的教訓

[條列今天踩過的坑或發現的問題，以及從中學到什麼]

## 明日展望

[條列尚未完成的事項或明天的優先行動]" \
  --settings "$HOOK_SETTINGS" --dangerously-skip-permissions --model haiku 2>/dev/null)

if [ -z "$SUMMARY" ]; then
  log "ERROR: Claude returned empty output."
  exit 1
fi

log "Summary generated (${#SUMMARY} chars)."

# ---------------------------------------------------------------------------
# Ensure daily note exists
# ---------------------------------------------------------------------------
if [ ! -f "$DAILY_NOTE" ]; then
  mkdir -p "$DAILY_DIR"
  cat > "$DAILY_NOTE" <<EOF
---
date: $DATE
timezone: ${TZ:-UTC}
status: in-progress
tags:
  - daily-log
type: daily-notes
---

# Daily Log - $DATE

## Timeline

EOF
  log "Created new daily note: $DAILY_NOTE"
fi

# ---------------------------------------------------------------------------
# Append Daily Summary section (idempotent guard)
# ---------------------------------------------------------------------------
if grep -q "^## Daily Summary" "$DAILY_NOTE"; then
  log "Daily Summary section already exists in $DAILY_NOTE — skipping append."
else
  cat >> "$DAILY_NOTE" <<EOF

---

## Daily Summary

_Generated: $TIMESTAMP — ${COUNT} session(s)_

$SUMMARY
EOF
  log "Appended Daily Summary to $DAILY_NOTE"
fi

# ---------------------------------------------------------------------------
# Discord notification
# ---------------------------------------------------------------------------
OVERVIEW=$(echo "$SUMMARY" | awk '/^## 今日總覽/{found=1; next} found && /^## /{exit} found{print}' | sed '/^$/d' | head -3)
discord_send "📅 **Daily Summary — ${DATE}**（${COUNT} sessions）

${OVERVIEW}

詳細內容已寫入 Daily Note。"

log "=== Done ==="
