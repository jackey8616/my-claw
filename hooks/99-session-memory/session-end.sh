#!/bin/bash
# Claude Code SessionEnd hook
# Generates a session log in 01-Session-Logs and links it from today's daily note.

SESSION_LOGS_DIR="$HOME/vault/01-Session-Logs"
DAILY_DIR="$HOME/vault/04-Daily-Notes"
INPUT=$(cat)
REASON=$(echo "$INPUT" | jq -r '.reason // "unknown"')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')
TIMESTAMP=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d %H:%M %Z')
DATE=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')
DAILY_NOTE="$DAILY_DIR/$DATE.md"
HOOK_SETTINGS="$(dirname "$0")/claude-hook-settings.json"

# Create daily note if missing
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

## Timeline

EOF
fi

# Exit early if no transcript
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session Ended (reason: $REASON)

EOF
  exit 0
fi

# Extract conversation text from JSONL transcript (skip meta/tool messages)
TRANSCRIPT_TEXT=$(jq -r '
  select(.type == "user" or .type == "assistant") |
  select(.isMeta != true) |
  if .type == "user" then
    if (.message.content | type) == "string" then
      "【用戶】: \(.message.content)"
    elif (.message.content | type) == "array" then
      "【用戶】: \([.message.content[] | select(.type == "text") | .text] | join(""))"
    else empty end
  else
    "【AI】: \([.message.content[]? | select(.type == "text") | .text] | join(""))"
  end
' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 40000)

if [ -z "$TRANSCRIPT_TEXT" ]; then
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session Ended (reason: $REASON)

EOF
  exit 0
fi

# Generate structured session log via Claude
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
  cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session Ended (reason: $REASON, 摘要生成失敗)

EOF
  exit 0
fi

# Parse title from output
LOG_TITLE=$(echo "$SESSION_LOG_CONTENT" | grep '^title:' | sed 's/^title: *//' | tr ' ' '-' | tr -cd '[:alnum:]-_')
LOG_SUMMARY=$(echo "$SESSION_LOG_CONTENT" | grep '^summary:' | sed 's/^summary: *//')
LOG_BODY=$(echo "$SESSION_LOG_CONTENT" | grep -v '^title:' | grep -v '^summary:')

if [ -z "$LOG_TITLE" ]; then
  LOG_TITLE="Session"
fi

# Write session log file
LOG_FILENAME="${DATE}_${LOG_TITLE}.md"
LOG_PATH="$SESSION_LOGS_DIR/$LOG_FILENAME"

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

# Add link entry in daily note
cat >> "$DAILY_NOTE" <<EOF

### $TIMESTAMP - Session 結束 (reason: $REASON)

📋 Session Log: [[01-Session-Logs/$LOG_FILENAME|${LOG_TITLE//-/ }]]

EOF

exit 0
