#!/bin/bash
# Start Hermes Assistant in a persistent tmux session
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TZ="$TIMEZONE"
SESSION="assistant"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' already running. Attaching..."
  tmux attach -t "$SESSION"
else
  echo "Starting new Hermes session..."
  tmux new-session -d -s "$SESSION" -x 220 -y 50
  tmux send-keys -t "$SESSION" "source ~/.bashrc && cd ${SCRIPT_DIR} && hermes launch" Enter
  tmux attach -t "$SESSION"
fi