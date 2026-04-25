---
name: archive
description: 收到 !archive 指令、主題自然結束、或對話輪數過多時，封存本次 session 至 vault、更新 DailyNote、同步 memory graph，並通知 Discord。
disable-model-invocation: false
allowed-tools: Read Write Bash mcp__plugin_discord_discord__reply
---

## 日期判定規則

查看對話歷史中**第一則**帶有 `ts="..."` 屬性的 `<channel>` 標籤，取出其 UTC 日期（YYYY-MM-DD），記為 SESSION_START_DATE。

- 若 SESSION_START_DATE == NOW_DATE（或找不到 ts）：使用 NOW_DATE 作為 DATE、NOW_MONTH 作為 MONTH。
- 若 SESSION_START_DATE < NOW_DATE（跨日 session）：使用 SESSION_START_DATE 作為 DATE，SESSION_START_DATE 前 7 碼作為 MONTH（例：`2026-04-12` → `2026-04`）。

後續所有步驟的 `{DATE}` 與 `{MONTH}` 均使用此判定結果。

## 執行步驟

依序完成以下所有步驟，不要省略任何一步。

### 步驟 0：取得當前時間

使用 Bash 工具執行以下指令，取得 NOW_DATE、NOW_MONTH、NOW_TIME：

```bash
TZ=UTC date '+NOW_DATE=%Y-%m-%d NOW_MONTH=%Y-%m NOW_TIME=%H:%M'
```

### 步驟 1：產出 SessionLog 內容

根據本次對話內容，整理出以下欄位：

- **title**：動詞開頭，10 字以內的繁體中文主題摘要
- **tags**：2–5 個小寫英文加連字號標籤
- **summary**：嚴格 8 行，每行對應一個面向：
  1. 本次對話的核心主題是什麼
  2. 討論了哪些具體概念或問題
  3. 產生了哪些新知識或學習進展
  4. 捕捉到哪些靈感或想法
  5. 記錄了哪些待辦事項
  6. 整合出哪些洞見或結論
  7. 與既有知識的關聯點
  8. 下次建議探索的方向
- **knowledge_body**：`## 新知識` 段落的完整 markdown，格式：
  ```
  ### 知識標題
  說明內容。
  **狀態**：未探索 | 學習中 | 已掌握
  **分類**：...
  **關聯**：[[節點A]]、[[節點B]]
  ```
- **insights_body**：`## 靈感` 段落，格式：
  ```
  ### 靈感標題
  完整內容。
  **背景**：...
  **關聯領域**：...
  ```
- **synthesis_body**：`## 整合洞見` 條列格式
- **todos_body**：`## 待辦或成果` 使用 `- [ ]` 格式
- **next_suggestions_body**：`## 下次建議` 1–3 個方向

### 步驟 2：寫入 SessionLog 檔案

從上方時間資訊取得 DATE 和 TIME，路徑格式：

```
/home/laura/vault/01-Session-Logs/{DATE}/{DATE}_{title-slug}.md
```

title-slug：將 title 中的空格換為連字號，只保留英數字與連字號。

檔案內容格式：

```markdown
---
title: {title}
date: {DATE}
time: {DATE} {TIME_START} - {TIME_END} UTC
tags:
  - {tag-1}
  - {tag-2}
todos:
  - [ ] ...
summary: |
  {summary 8 行，每行縮排 2 格}
---

## 摘要

{overview：一段自然語言的對話回顧}

---

## 新知識

{knowledge_body}

---

## 靈感

{insights_body}

---

## 整合洞見

{synthesis_body}

---

## 待辦或成果

{todos_body}

---

## 下次建議

{next_suggestions_body}
```

使用 Write 工具建立資料夾（若不存在）並寫入檔案。

### 步驟 3：更新 DailyNote

DailyNote 路徑：`/home/laura/vault/02-Daily-Notes/{MONTH}/{DATE}.md`

- 若檔案不存在：從 `/home/laura/vault/templates/DAILY-NOTE.md` 複製建立（用 Read 讀取後 Write 寫入）
- 在 frontmatter 的 `sessions:` 清單末尾加入本次 SessionLog 的相對路徑：
  `01-Session-Logs/{DATE}/{LOG_FILENAME}`
- 在 `## 今日會話` 段落末尾追加（若段落不存在則建立）：
  ```
  - [[01-Session-Logs/{DATE}/{LOG_FILENAME}|{title}]] `{TIME}`
    - {summary 第 1 行}
  ```

使用 Read + Write 完成更新。

### 步驟 4：同步 memory graph

從本次對話中識別新的知識節點與關聯，整理成以下 JSON 格式：

```json
{
  "entities": [
    { "name": "NodeName", "entityType": "concept", "observations": ["說明"] }
  ],
  "relations": [
    { "from": "NodeA", "to": "NodeB", "relationType": "relates_to" }
  ],
  "observations": [
    { "entityName": "NodeName", "contents": ["補充觀察"] }
  ]
}
```

整理完成後，透過 Bash 呼叫 memory-agent 寫入：

```bash
claude --agent memory-agent \
  --allowedTools "mcp__memory__create_entities,mcp__memory__create_relations,mcp__memory__add_observations,mcp__memory__delete_entities,mcp__memory__delete_observations,mcp__memory__compact_graph" \
  --dangerously-skip-permissions \
  -p '<上面的 JSON>'
```

不直接呼叫 `mcp__memory__*` 工具。

### 步驟 5：通知 Discord

若 `$ARGUMENTS` 為 `silent`，跳過此步驟。

否則使用 `mcp__plugin_discord_discord__reply` 發送至頻道 `1486128557444042883`：

```
📝 Session archived: **{title}**
{summary 第 1 行}
```

### 步驟 6：重啟 session

所有步驟完成後執行以下指令。先在背景等待 Claude process 退出後再送啟動命令，然後用 `kill -TERM` 終止當前 process（Discord 連線模式下 `/exit` 無法正確退出）：

若 `$ARGUMENTS` 非空且非 `silent`，以 `$ARGUMENTS` 作為下一個 session 的 startup prompt；否則使用預設問候。

```bash
LOG_DIR="${TMPDIR:-/tmp}/claude-archiver"
mkdir -p "$LOG_DIR"
if [ -n "$ARGUMENTS" ] && [ "$ARGUMENTS" != "silent" ]; then
  NEXT_PROMPT="$ARGUMENTS. Reply via Discord channel 1486128557444042883."
else
  NEXT_PROMPT="Hey, are there anything I should know now? Reply via Discord channel 1486128557444042883."
fi
(while kill -0 "$PPID" 2>/dev/null; do sleep 1; done && tmux send-keys -t "assistant:0.0" "bash /home/laura/my-claw/start-agent.sh" Enter) >> "$LOG_DIR/session-archiver-debug.log" 2>&1 &
disown
kill -TERM "$PPID"
```

`$PPID` 在 Bash tool 的 subprocess 中 = 當前 claude process。背景 loop 等 claude 真正退出後才送啟動命令。
