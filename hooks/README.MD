# hooks/

此資料夾存放所有 Claude Code 的 global hook 腳本。
`setup-new-vps.sh` 執行時會自動將這裡的所有 hook 註冊到 `~/.claude/settings.json`。

---

## 資料夾結構
```
hooks/
  01-session-memory/        ← 數字前綴決定執行順序
    claude_event_name       ← 內容為 Claude Code event name（純文字）
    on-event.sh             ← hook 腳本本體（固定命名）
    README.md
  02-another-hook/
    claude_event_name
    on-event.sh
    ...
```

---

## 命名規則

| 項目 | 規則 |
|---|---|
| 子資料夾 | `{數字前綴}-{描述}`，例如 `01-session-memory` |
| 執行順序 | 依資料夾名稱字母排序（`sort`），數字前綴越小越早執行 |
| hook 腳本 | 固定命名為 `on-event.sh`，每個資料夾只有一個入口腳本 |
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

3. 建立固定命名的 hook 腳本 `on-event.sh`：
```bash
   touch hooks/02-my-hook/on-event.sh
   chmod +x hooks/02-my-hook/on-event.sh
```

4. 重新執行 `setup-new-vps.sh`，hook 會自動被註冊到 `~/.claude/settings.json`。

> **注意**：每個資料夾內必須有 `on-event.sh`，否則該 hook 會被跳過並顯示 skip 警告。

> **注意**：`setup-new-vps.sh` 每次執行前會自動清除舊的 hooks 區塊再重新寫入，重複執行不會造成重複註冊。
> 若需重新註冊，請先手動備份 `~/.claude/settings.json` 的 `hooks` 區塊中，沒有被本專案管理的hook資料。

---

## setup-new-vps.sh 的註冊邏輯

腳本會：

1. 依資料夾名稱排序掃描 `hooks/` 底下所有子資料夾
2. 讀取每個子資料夾的 `claude_event_name`
3. 檢查該資料夾內是否存在 `on-event.sh`，不存在則跳過並顯示 skip 警告
4. 將 `on-event.sh` append 到 `~/.claude/settings.json` 對應的 event 陣列
5. 沒有 `claude_event_name` 的資料夾會被跳過並顯示警告

最終產生的 `~/.claude/settings.json` 結構範例：
```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/laura/my-claw/hooks/01-session-memory/on-event.sh"
          }
        ]
      }
    ]
  }
}
```
