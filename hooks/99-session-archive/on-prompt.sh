#!/bin/bash
# UserPromptSubmit hook — intercepts !session-clear, summarizes, then clears session

LOGFILE="/tmp/session-archiver-debug.log"
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }

log "Hook triggered. PROMPT='$PROMPT'"

# Extract text content from inside XML channel tags
CHANNEL_TEXT=$(echo "$PROMPT" | grep -v '<channel' | grep -v '</channel>' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n')

log "CHANNEL_TEXT='$CHANNEL_TEXT'"

if [ "$CHANNEL_TEXT" = "!archive" ]; then
  log "!archive matched! Transcript: $TRANSCRIPT_PATH"
  (
    bash /home/laura/my-claw/hooks/session-archiver/archive.sh "$TRANSCRIPT_PATH"
    log "Archive done. Sending /clear to tmux..."
    tmux send-keys -t "assistant:0.0" "/clear" Enter
  ) >> "$LOGFILE" 2>&1 &
  disown
  echo '{"decision": "block", "reason": "Archiving session and resetting..."}'
  exit 2
fi

log "No match, passing through."
exit 0
