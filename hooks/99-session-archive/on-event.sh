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

# !archive is now handled by the /archive Skill inside Claude.
# Claude receives the message, auto-invokes the Skill, which writes vault files,
# updates memory graph, notifies Discord, and restarts the session via tmux.

log "No match, passing through."
exit 0
