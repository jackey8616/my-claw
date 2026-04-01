#!/bin/bash

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


if [ "$CHANNEL_TEXT" = "!usage" ]; then
  log "usage matched! Transcript: $TRANSCRIPT_PATH"

  read -r INPUT_TOKENS OUTPUT_TOKENS TOTAL <<< "$(jq -rs '
    [.[] | select(.type == "assistant") | {
      i: (.message.usage.input_tokens // 0),
      o: (.message.usage.output_tokens // 0)
    }] |
    (map(.i) | add // 0) as $i |
    (map(.o) | add // 0) as $o |
    "\($i) \($o) \($i + $o)"
  ' "$TRANSCRIPT_PATH" 2>/dev/null)"

  INPUT_TOKENS=${INPUT_TOKENS:-0}
  OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}
  TOTAL=${TOTAL:-0}

  commify() { printf "%d" "$1" | sed ':a;s/\B[0-9]\{3\}\b/,&/;ta'; }
  MSG=$(printf '📊 **Current Usage**\n```\nInput:  %s\nOutput: %s\nTotal:  %s\n```' \
    "$(commify "$INPUT_TOKENS")" "$(commify "$OUTPUT_TOKENS")" "$(commify "$TOTAL")")
  discord_send "$MSG"
  log "Usage sent: input=$INPUT_TOKENS output=$OUTPUT_TOKENS total=$TOTAL"

  echo '{"decision": "block", "reason": "Usage reported."}'
  exit 2
fi

exit 0
