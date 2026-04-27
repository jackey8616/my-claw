#!/bin/bash
# check-email.sh — poll laura.b.clode@gmail.com for new messages, hand off to Claude
#
# Crontab (every 10 minutes):
#   */10 * * * * /bin/bash /home/laura/my-claw/scripts/check-email.sh >> /tmp/check-email.log 2>&1

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ENV_FILE="$REPO_DIR/.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] check-email started"

RESULT=$(python3 "$REPO_DIR/scripts/check-email.py")
COUNT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['count'])")

if [ "$COUNT" -eq 0 ]; then
  echo "No new messages."
  exit 0
fi

echo "Found $COUNT new message(s), handing to Claude..."

PROMPT="laura.b.clode@gmail.com 收到了 $COUNT 封新信件，內容如下：

$RESULT

請逐封閱讀，用繁體中文在 Discord channel 1486128557444042883 摘要每封信的寄件人、主旨與重點，並告知 Clode 是否需要採取任何行動。"

claude -p "$PROMPT" --dangerously-skip-permissions \
  --settings '{"disableAllHooks": true}'

echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] check-email done"
