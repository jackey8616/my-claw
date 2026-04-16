---
name: midnight-archive
description: 強制封存當前 Claude session（由午夜 cron 觸發）。通知 Discord、暫停接收訊息、對 tmux session 送出 !archive，並在背景自動恢復 Discord 存取。
disable-model-invocation: false
context: fork
allowed-tools: Bash mcp__plugin_discord_discord__reply
---

## 參數

- `$ARGUMENTS`：tmux target（預設 `assistant:0.0`）

## 執行步驟

依序完成以下步驟，不要省略。

### 步驟 1：通知 Discord

使用 `mcp__plugin_discord_discord__reply` 發送至頻道 `1486128557444042883`：

```
⏰ UTC 23:50 — 即將自動封存當前會話，Discord 暫時停止接收訊息。
```

### 步驟 2：暫停 Discord 接收

使用 Bash 將 `~/.claude/channels/discord/access.json` 的 `allowFrom` 清空：

```bash
ACCESS_FILE="$HOME/.claude/channels/discord/access.json"
if [ -f "$ACCESS_FILE" ]; then
  cp "$ACCESS_FILE" "${ACCESS_FILE}.bak"
  python3 -c "
import json, sys
path = sys.argv[1]
d = json.load(open(path))
d['allowFrom'] = []
json.dump(d, open(path, 'w'), indent=2)
" "$ACCESS_FILE"
  echo "Discord incoming blocked"
fi
```

### 步驟 3：取得 PID、送出 !archive、立即還原 Discord 存取

取得 main session 的 Claude PID，送出 !archive，**立即還原** access.json（不等 PID 消失），再啟動背景安全網。

```bash
TMUX_TARGET="${ARGUMENTS:-assistant:0.0}"
ACCESS_FILE="$HOME/.claude/channels/discord/access.json"

# 取 main session 的 claude PID（透過 tmux pane pid 找子程序）
PANE_PID=$(tmux list-panes -t "$TMUX_TARGET" -F "#{pane_pid}" 2>/dev/null | head -1)
CLAUDE_PID=$(pgrep -P "$PANE_PID" -x claude 2>/dev/null | head -1)
echo "Main session PID: ${CLAUDE_PID:-unknown}"

# 送出 !archive
tmux send-keys -t "$TMUX_TARGET" "!archive" Enter
echo "Sent !archive to $TMUX_TARGET"

# 立即還原 access.json（archive skill 的步驟 5 需要能通知 Discord）
cp "${ACCESS_FILE}.bak" "$ACCESS_FILE"
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Discord access restored immediately after sending !archive" >> /tmp/midnight-archive.log

# 背景安全網：若上方還原失敗，等 PID 消失後再還原一次
(
  if [ -n "$CLAUDE_PID" ]; then
    while kill -0 "$CLAUDE_PID" 2>/dev/null; do sleep 1; done
  fi
  cp "${ACCESS_FILE}.bak" "$ACCESS_FILE"
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Discord access safety-restore (PID ${CLAUDE_PID:-unknown} exited)" >> /tmp/midnight-archive.log
) &
disown
echo "Safety watcher started for PID ${CLAUDE_PID:-unknown}"
```
