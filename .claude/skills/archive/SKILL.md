---
name: archive
description: 收到 !archive 指令、主題自然結束、或對話輪數過多時，封存本次 session 至 vault、更新 DailyNote、同步 memory graph，並通知 Discord。
disable-model-invocation: false
allowed-tools: Read Write Bash mcp__plugin_discord_discord__reply mcp__memory__create_entities mcp__memory__create_relations mcp__memory__add_observations
---

## 當前時間資訊

!`TZ=UTC date '+DATE=%Y-%m-%d MONTH=%Y-%m TIME=%H:%M'`

## 執行步驟

依序完成以下所有步驟，不要省略任何一步。

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

從本次對話中識別新的知識節點與關聯：
- 對每個新概念，使用 `mcp__memory__create_entities` 建立節點
- 對每個關聯，使用 `mcp__memory__create_relations` 建立邊
- 若有重要觀察，使用 `mcp__memory__add_observations` 補充

### 步驟 5：通知 Discord

使用 `mcp__plugin_discord_discord__reply` 發送至頻道 `1486128557444042883`：

```
📝 Session archived: **{title}**
{summary 第 1 行}
```

### 步驟 6：重啟 session

所有步驟完成後，用 Bash 背景執行重啟，讓新主題從乾淨的 session（新 JSONL）開始：

```bash
(sleep 5 && tmux send-keys -t "assistant:0.0" "/exit" Enter && sleep 3 && tmux send-keys -t "assistant:0.0" "source /home/laura/.nvm/nvm.sh && cd /home/laura/my-claw && claude --channels plugin:discord@claude-plugins-official --dangerously-skip-permissions \"Hey, are there anything I should know now? Reply via Discord channel 1486128557444042883.\"" Enter) >> /tmp/session-archiver-debug.log 2>&1 &
disown
```

這個指令會在背景執行，不阻塞目前回應。
