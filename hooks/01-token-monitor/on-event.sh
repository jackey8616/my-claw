#!/bin/bash

HOOK_DIR="$(dirname "$0")"
LOGFILE="/tmp/token-monitor-debug.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

# Load .env for Discord credentials
ENV_FILE="$HOOK_DIR/../../.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
DISCORD_CHANNEL_ID="1486128557444042883"

discord_send() {
  local msg="$1"
  [ -z "$DISCORD_BOT_TOKEN" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# Parse hook input from stdin
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# Extract text content (strip XML channel tags)
CHANNEL_TEXT=$(echo "$PROMPT" | grep -v '<channel' | grep -v '</channel>' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')

log "Hook triggered. CHANNEL_TEXT='$CHANNEL_TEXT' TRANSCRIPT='$TRANSCRIPT_PATH'"

THRESHOLD=50000

if [ -n "$TRANSCRIPT_PATH" ] && [ "$CHANNEL_TEXT" != "!usage" ]; then
  read -r CURR_TOTAL PREV_TOTAL <<< "$(jq -rs '
    [.[] | select(.type == "assistant") | .message.usage] as $turns |
    ($turns | map(
      (.input_tokens // 0) + (.output_tokens // 0) +
      (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
    ) | add // 0) as $curr |
    ($turns[:-1] | map(
      (.input_tokens // 0) + (.output_tokens // 0) +
      (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
    ) | add // 0) as $prev |
    "\($curr) \($prev)"
  ' "$TRANSCRIPT_PATH" 2>/dev/null)"

  CURR_TOTAL=${CURR_TOTAL:-0}
  PREV_TOTAL=${PREV_TOTAL:-0}
  CURR_BUCKET=$(( CURR_TOTAL / THRESHOLD ))
  PREV_BUCKET=$(( PREV_TOTAL / THRESHOLD ))

  if [ "$CURR_BUCKET" -gt "$PREV_BUCKET" ]; then
    commify() { printf "%d" "$1" | sed ':a;s/\B[0-9]\{3\}\b/,&/;ta'; }
    MILESTONE=$(( CURR_BUCKET * THRESHOLD ))
    discord_send "$(printf '⚠️ **Token milestone: %s**\nTotal (cached + non-cached): %s' \
      "$(commify "$MILESTONE")" "$(commify "$CURR_TOTAL")")"
    log "Token milestone: $MILESTONE (total=$CURR_TOTAL)"
  fi
fi

if [ "$CHANNEL_TEXT" = "!usage" ]; then
  log "!usage matched. Transcript: $TRANSCRIPT_PATH"

  read -r INPUT_TOKENS OUTPUT_TOKENS CACHE_READ CACHE_WRITE <<< "$(jq -rs '
    [.[] | select(.type == "assistant") | .message.usage] |
    (map(.input_tokens // 0) | add // 0) as $i |
    (map(.output_tokens // 0) | add // 0) as $o |
    (map(.cache_read_input_tokens // 0) | add // 0) as $cr |
    (map(.cache_creation_input_tokens // 0) | add // 0) as $cw |
    "\($i) \($o) \($cr) \($cw)"
  ' "$TRANSCRIPT_PATH" 2>/dev/null)"

  INPUT_TOKENS=${INPUT_TOKENS:-0}
  OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}
  CACHE_READ=${CACHE_READ:-0}
  CACHE_WRITE=${CACHE_WRITE:-0}
  CACHE_TOTAL=$((CACHE_READ + CACHE_WRITE))
  NON_CACHE_TOTAL=$((INPUT_TOKENS + OUTPUT_TOKENS))
  TOTAL=$((NON_CACHE_TOTAL + CACHE_TOTAL))

  commify() { printf "%d" "$1" | sed ':a;s/\B[0-9]\{3\}\b/,&/;ta'; }
  MSG=$(printf '📊 **Current Usage**\n```\nInput:          %s\nOutput:         %s\nCache read:     %s\nCache write:    %s\n─────────────────────\nCache Total:    %s\nNon-cache Total:%s\nTotal:          %s\n```' \
    "$(commify "$INPUT_TOKENS")" "$(commify "$OUTPUT_TOKENS")" \
    "$(commify "$CACHE_READ")" "$(commify "$CACHE_WRITE")" \
    "$(commify "$CACHE_TOTAL")" "$(commify "$NON_CACHE_TOTAL")" "$(commify "$TOTAL")")
  discord_send "$MSG"
  log "Usage sent: input=$INPUT_TOKENS output=$OUTPUT_TOKENS cache_read=$CACHE_READ cache_write=$CACHE_WRITE total=$TOTAL"

  echo '{"decision": "block", "reason": "Usage reported."}'
  exit 2
fi

exit 0
