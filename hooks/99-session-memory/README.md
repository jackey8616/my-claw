---
name: session-memory
description: Claude Code SessionEnd hook — generates structured session logs and links them in daily notes
type: hook
event: SessionEnd
script: session-end.sh
settings: claude-hook-settings.json
vault_dirs:
  - ~/vault/01-Session-Logs
  - ~/vault/04-Daily-Notes
---

# session-memory

SessionEnd hook，在每次 Claude Code session 結束時自動執行。

## 功能

1. 讀取本次 session 的 transcript（JSONL）
2. 呼叫 Claude（haiku）產生結構化 session log（繁體中文）
3. 將 log 寫入 `~/vault/01-Session-Logs/YYYY-MM-DD_<title>.md`
4. 在當天的 daily note（`~/vault/04-Daily-Notes/YYYY-MM-DD.md`）加入連結

## 檔案說明

| 檔案 | 說明 |
|------|------|
| `session-end.sh` | 主要 hook 腳本 |
| `claude-hook-settings.json` | 空 hooks 設定，防止子呼叫觸發遞迴 hook |

## Hook 註冊

在 `~/.claude/settings.json` 的 `hooks.SessionEnd` 中指定絕對路徑：

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/laura/my-claw/hooks/session-memory/session-end.sh"
          }
        ]
      }
    ]
  }
}
```

## VPS 重建注意事項

重建後需手動執行：
```bash
chmod +x ~/my-claw/hooks/session-memory/session-end.sh
```
並確認 `~/.claude/settings.json` 的路徑正確。
