#!/bin/bash
# Start Claude Code assistant in a persistent tmux session
# Usage: bash start-agent.sh [prompt]

# Resolve script's own directory so it works regardless of cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default prompt if none provided
DEFAULT_PROMPT="${1:-and are there anything I should know now?}"
LAUNCH_PROMPT="Hey Laura, read and follow CLAUDE.md ${DEFAULT_PROMPT} Reply via Discord channel 1486128557444042883."

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export TZ="$TIMEZONE"

# Resolve absolute path to claude so tmux shell doesn't need nvm in PATH
CLAUDE_BIN="$(which claude)"
if [ -z "$CLAUDE_BIN" ]; then
  echo "Error: claude binary not found. Is nvm/node installed?"
  exit 1
fi

SESSION="assistant"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  if [ -n "$TMUX" ]; then
    echo "Already inside tmux session. Sending launch command..."
    tmux send-keys -t "$SESSION" "cd ${SCRIPT_DIR} && ollama launch claude --model gemma4:31b-cloud -- --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions \"$LAUNCH_PROMPT\"" Enter
  else
    echo "Session '$SESSION' already running. Attaching..."
    tmux attach -t "$SESSION"
  fi
else
  echo "Starting new Claude Code session..."
  tmux new-session -d -s "$SESSION" -x 220 -y 50 \
    -e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN" \
    -e "TZ=$TZ"
  tmux send-keys -t "$SESSION" "cd ${SCRIPT_DIR} && ollama launch claude --model gemma4:31b-cloud -- --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions \"$LAUNCH_PROMPT\"" Enter
  echo "Session started. Attaching..."
  tmux attach -t "$SESSION"
fi
