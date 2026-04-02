#!/bin/bash
# Session archiver — generates session log and appends summary block to daily note.

SESSION_LOGS_DIR="$HOME/vault/01-Session-Logs"
DAILY_DIR="$HOME/vault/04-Daily-Notes"
TRANSCRIPT_PATH="${1:-}"
TIMESTAMP=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d %H:%M %Z')
DATE=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')
DAILY_NOTE="$DAILY_DIR/$DATE.md"
HOOK_SETTINGS="$(dirname "$0")/claude-hook-settings.json"
LOGFILE="/tmp/session-archiver-debug.log"

# Load .env for Discord credentials
ENV_FILE="$(dirname "$0")/../../.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
DISCORD_CHANNEL_ID="1486128557444042883"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

discord_notify() {
  local msg="$1"
  [ -z "$DISCORD_BOT_TOKEN" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# Ensure daily note exists
if [ ! -f "$DAILY_NOTE" ]; then
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

EOF
fi

# Validate transcript
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "No transcript found at '$TRANSCRIPT_PATH'"
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session 結束（無 transcript）

EOF
  exit 0
fi

# Extract conversation text
TRANSCRIPT_TEXT=$(jq -r '
  select(.type == "user" or .type == "assistant") |
  select(.isMeta != true) |
  if .type == "user" then
    if (.message.content | type) == "string" then "【用戶】: \(.message.content)"
    elif (.message.content | type) == "array" then "【用戶】: \([.message.content[] | select(.type == "text") | .text] | join(""))"
    else empty end
  else "【AI】: \([.message.content[]? | select(.type == "text") | .text] | join(""))"
  end
' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 40000)

if [ -z "$TRANSCRIPT_TEXT" ]; then
  log "Transcript empty or unreadable"
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session 結束（空 transcript）

EOF
  exit 0
fi

# Generate session log via Claude (single call, output reused for both session log and daily note)
log "Generating session log..."
SESSION_LOG_CONTENT=$(echo "$TRANSCRIPT_TEXT" | claude -p \
  "請用繁體中文產生一份 session log。只輸出以下格式的內容，不要任何額外說明：

title: [一句話描述本次 session 的主題，英文，適合作為檔名]
summary: [2-3 句話的整體摘要]

## 目標與成果

[條列完成的事項，用 ✅ 標記]

## 關鍵決策

[條列重要決策，每條說明原因]

## 待辦 / 下一步

[條列未完成或後續行動]" \
  --settings "$HOOK_SETTINGS" --dangerously-skip-permissions --model haiku 2>/dev/null)

if [ -z "$SESSION_LOG_CONTENT" ]; then
  log "Claude failed to generate session log"
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session 結束（摘要生成失
EOF
  exit 0
fi

# Parse output — LOG_SUMMARY reused in both session log and daily note
LOG_TITLE=$(echo "$SESSION_LOG_CONTENT" | grep '^title:' | sed 's/^title: *//' | tr ' ' '-' | tr -cd '[:alnum:]-_')
LOG_SUMMARY=$(echo "$SESSION_LOG_CONTENT" | grep '^summary:' | sed 's/^summary: *//')
LOG_BODY=$(echo "$SESSION_LOG_CONTENT" | grep -v '^title:' | grep -v '^summary:')
LOG_TITLE="${LOG_TITLE:-Session}"
LOG_FILENAME="${DATE}_${LOG_TITLE}.md"
LOG_PATH="$SESSION_LOGS_DIR/$LOG_FILENAME"

# Write session log
cat > "$LOG_PATH" <<EOF
---
title: ${LOG_TITLE//-/ }
date: $DATE
time: $TIMESTAMP
status: completed
tags:
  - session-log
type: session-log
---

# ${LOG_TITLE//-/ }

## Session 摘要

${LOG_SUMMARY:-（無摘要）}

${LOG_BODY}
EOF

# Append session entry to ## Sessions section in daily note
TIME_ONLY=$(TZ="${TZ:-UTC}" date '+%H:%M')
LIST_ITEM="- [[01-Session-Logs/$LOG_FILENAME|${LOG_TITLE//-/ }]] \`$TIME_ONLY\`"
LIST_SUB="  - ${LOG_SUMMARY:-（無摘要）}"

if grep -q "^## Sessions" "$DAILY_NOTE"; then
  printf '\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
else
  printf '\n## Sessions\n\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
fi

log "Session log written to $LOG_PATH"
log "Daily note updated: $DAILY_NOTE"

log "Session archived: ${LOG_TITLE//-/ } — ${LOG_SUMMARY:-（無摘要）}"

exit 0
