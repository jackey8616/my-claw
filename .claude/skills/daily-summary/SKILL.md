---
name: daily-summary
description: 將指定日期（預設昨日）所有 SessionLog 整合為 DailyNote，包含跨 session 的知識彙整、靈感精選、未完成待辦與反思。可重複執行（冪等）。
disable-model-invocation: false
context: fork
argument-hint: [YYYY-MM-DD]
allowed-tools: Read Write Glob Bash mcp__plugin_discord_discord__reply mcp__memory__add_observations
---

## 當前時間資訊

!`TZ=UTC date '+TODAY=%Y-%m-%d'; TZ=UTC date -d yesterday '+YESTERDAY=%Y-%m-%d'`

## 目標日期

若使用者傳入了日期參數（`$ARGUMENTS`），以該值作為 DATE；否則以上方 YESTERDAY 的值作為 DATE。

DATE 確定後，MONTH 取其前 7 碼（`YYYY-MM`）。

範例：
- `/daily-summary` → DATE = YESTERDAY
- `/daily-summary 2026-04-03` → DATE = 2026-04-03

## 執行步驟

依序完成以下所有步驟，不要省略任何一步。

### 步驟 1：讀取指定日期所有 SessionLog

使用確定的 DATE 值。

使用 Glob 列出當日所有 SessionLog：
```
/home/laura/vault/01-Session-Logs/{DATE}/*.md
```

對每個檔案使用 Read 讀取，從中提取：
- `tags`（frontmatter）
- `## 新知識` 段落：區分「已掌握/學習中」與「未探索」
- `## 靈感` 段落：完整保留
- `## 待辦或成果` 段落：只取 `- [ ]` 未完成項目
- `## 整合洞見` 段落：完整保留

若當日無任何 SessionLog，回報「今日尚無封存的 session」並停止。

### 步驟 2：跨 session 合成

根據步驟 1 收集的所有內容，合成以下欄位：

- **tags**：所有 session 的 tags 合併去重
- **summary_one_line**：一句話概括今日主軸（用於 frontmatter `summary` 欄位）
- **daily_summary**：一段 3–5 句的整體回顧，說明今天學了什麼、做了什麼、有哪些未竟之事
- **knowledge_acquired**：合併所有「已掌握/學習中」知識，去除重複，保留原有的 `###` 標題與內容格式
- **knowledge_unexplored**：所有「未探索」狀態的主題，條列格式
- **open_todos**：跨 session 彙整所有未完成待辦，保留 `- [ ]` 格式
- **best_inspirations**：從所有靈感中選出最多 3 條，依新穎度與可發展性挑選，保留原有 `###` 標題與內容
- **reflection**：回答兩個問題：
  1. 今日有哪些思維上的突破或跨 session 的連結？
  2. 明日最重要的一件事是什麼？

### 步驟 3：寫入 DailyNote

DailyNote 路徑：`/home/laura/vault/02-Daily-Notes/{MONTH}/{DATE}.md`

先用 Read 讀取現有檔案。定位並**保留**以下內容不修改：
- frontmatter 的 `sessions:` 清單
- `## 今日會話` 段落及其所有內容

**覆寫**其餘所有內容，使用以下格式：

```markdown
---
date: {DATE}
tags:
  - {tag-1}
  - {tag-2}
sessions:
  {保留原有 sessions 清單，不修改}
summary: {summary_one_line}
---

## 摘要

{daily_summary}

## 獲取的知識

{knowledge_acquired}

## 尚未深入的知識

{knowledge_unexplored（若無則寫「今日無未探索主題」）}

## 未完成的待辦

{open_todos（若無則寫「今日所有待辦已完成」）}

## 今日的最佳靈感

{best_inspirations}

## 反思

{reflection}

## 今日會話

{保留原有 ## 今日會話 段落內容，不修改}
```

使用 Write 工具寫入。

### 步驟 4：同步 memory graph（若有跨 session 洞見）

若步驟 2 產生了新的跨 session 整合洞見（在單一 session 中未出現的新連結），使用 `mcp__memory__add_observations` 補充到相關節點。若無新洞見，跳過此步驟。

### 步驟 5：通知 Discord

使用 `mcp__plugin_discord_discord__reply` 發送至頻道 `1486128557444042883`：

```
📅 Daily summary updated: {DATE}
{summary_one_line}
Sessions: {N} 個 | Todos open: {open_todos 數量} 個
```
