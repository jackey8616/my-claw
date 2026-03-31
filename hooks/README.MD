# hooks/

此資料夾存放所有 Claude Code 的 global hook 腳本。
`setup-new-vps.sh` 執行時會自動將這裡的所有 hook 註冊到 `~/.claude/settings.json`。

---

## 資料夾結構

```
hooks/
  01-session-memory/        ← 數字前綴決定執行順序
    claude_event_name       ← 內容為 Claude Code event name（純文字）
    session-end.sh          ← hook 腳本本體
    claude-hook-settings.json
    README.md
  02-another-hook/
    claude_event_name
    some-hook.sh
    ...
```

---

## 命名規則

| 項目 | 規則 |
|---|---|
| 子資料夾 | `{數字前綴}-{描述}`，例如 `01-session-memory` |
| 執行順序 | 依資料夾名稱字母排序（`sort`），數字前綴越小越早執行 |
| 同資料夾內多個 `.sh` | 依檔名排序後依序執行 |
| `claude_event_name` | 純文字檔，內容為對應的 Claude Code event name |

---

## claude_event_name 可用值

Claude Code 支援以下 hook event：

| Event | 觸發時機 |
|---|---|
| `PreToolUse` | 工具執行前 |
| `PostToolUse` | 工具執行後 |
| `Notification` | Claude 發出通知時 |
| `Stop` | Claude 完成回應時 |
| `SessionEnd` | Session 結束時 |

`claude_event_name` 檔案內容範例：
```
SessionEnd
```

---

## 新增 Hook 的方法

1. 在 `hooks/` 底下建立新子資料夾，加上數字前綴控制順序：
   ```bash
   mkdir hooks/02-my-hook
   ```

2. 建立 `claude_event_name` 檔，寫入對應的 event name：
   ```bash
   echo "PostToolUse" > hooks/02-my-hook/claude_event_name
   ```

3. 撰寫 hook 腳本：
   ```bash
   touch hooks/02-my-hook/my-hook.sh
   chmod +x hooks/02-my-hook/my-hook.sh
   ```

4. 重新執行 `setup-new-vps.sh`，hook 會自動被註冊到 `~/.claude/settings.json`。

> **注意**：`setup-new-vps.sh` 使用 `jq` append 的方式寫入，重複執行會導致重複註冊。
> 若需重新註冊，請先手動清除 `~/.claude/settings.json` 的 `hooks` 區塊。

---

## setup-new-vps.sh 的註冊邏輯

腳本會：

1. 依資料夾名稱排序掃描 `hooks/` 底下所有子資料夾
2. 讀取每個子資料夾的 `claude_event_name`
3. 將該資料夾內所有 `.sh`（依檔名排序）append 到 `~/.claude/settings.json` 對應的 event 陣列
4. 沒有 `claude_event_name` 的資料夾會被跳過並顯示警告

最終產生的 `~/.claude/settings.json` 結構範例：

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/laura/my-claw/hooks/01-session-memory/session-end.sh"
          }
        ]
      }
    ]
  }
}
```