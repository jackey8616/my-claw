#!/bin/bash
# UserPromptSubmit hook — intercepts !archive, summarizes, then exit session

LOGFILE="/tmp/session-archiver-debug.log"
HOOK_DIR="$(dirname "$0")"
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
    bash "$HOOK_DIR/archive.sh" "$TRANSCRIPT_PATH"
    log "Archive done. Sending /exit to tmux..."
    tmux send-keys -t "assistant:0.0" "/exit" Enter
    sleep 3
    log "Restarting claude..."
    tmux send-keys -t "assistant:0.0" "source /home/laura/.nvm/nvm.sh && cd /home/laura/my-claw && claude --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions" Enter
    sleep 15
    log "Sending initial prompt..."
    tmux send-keys -t "assistant:0.0" "Hey, are there anything I should know now? Reply via Discord channel 1486128557444042883." Enter
  ) >> "$LOGFILE" 2>&1 &
  disown
  echo '{"decision": "block", "reason": "Archiving session and resetting..."}'
  exit 2
fi

log "No match, passing through."
exit 0
