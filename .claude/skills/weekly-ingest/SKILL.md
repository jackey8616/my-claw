---
name: weekly-ingest
description: 每週分析近 7 天 SessionLog 與 DailyNote，對照 AGENTS.md 產出行為規則修改提案，存檔並寫入待辦。背景靜默執行，不需要即時互動。
disable-model-invocation: false
context: fork
allowed-tools: Read Write Glob Bash
---

## 當前時間資訊

!`TZ=UTC date '+TODAY=%Y-%m-%d'`
!`TZ=UTC date -d '7 days ago' '+WEEK_START=%Y-%m-%d'`
!`TZ=UTC date '+WEEK_NUM=W%V' 2>/dev/null || TZ=UTC date '+WEEK_NUM=W%U'`

## 參數

- `$ARGUMENTS`：可覆蓋起始日期（格式 YYYY-MM-DD），預設為 7 天前

## 執行步驟

依序完成以下步驟，不要省略。

### 步驟 1：確定資料範圍

- DATE_END = TODAY
- DATE_START = WEEK_START（或 $ARGUMENTS 若有提供）
- WEEK_ID = `{YYYY}-{WEEK_NUM}`（例：`2026-W16`）

### 步驟 2：讀取 AGENTS.md

讀取現有規則：
```
/home/laura/vault/00-Laura-Persona/AGENTS.md
```

### 步驟 3：讀取近 7 天 SessionLog

使用 Bash 列出 DATE_START 到 DATE_END 之間所有 SessionLog：

```bash
find /home/laura/vault/01-Session-Logs -name "*.md" \
  -newermt "{DATE_START}" ! -newermt "{DATE_END} 23:59:59" \
  | sort
```

對每個檔案使用 Read 讀取，重點提取：
- `## 待辦或成果` 段落（有無新增或遺漏的行為）
- `## 整合洞見` 段落
- `## 下次建議` 段落
- frontmatter 的 `tags`

### 步驟 4：讀取近 7 天 DailyNote

```bash
find /home/laura/vault/02-Daily-Notes -name "*.md" \
  -newermt "{DATE_START}" ! -newermt "{DATE_END} 23:59:59" \
  | sort
```

對每個檔案讀取 `## 反思` 段落。

### 步驟 5：分析

根據步驟 2–4 的資料，針對 AGENTS.md 進行分析：

**A. 規則違反 / 被忽略**
- AGENTS.md 中哪些規則在本週的 session 中被違反或沒有被遵守？
- 引用具體 session 日期作為依據。

**B. 新行為模式（尚未有規則涵蓋）**
- 本週反覆出現但 AGENTS.md 沒有明確規定的行為模式？

**C. 過時規則**
- AGENTS.md 中哪些規則已不再適用或需要更新？

**D. 版本更新**
- 根據分析，AGENTS.md 的 `Last Updated` 與版本號應如何更新？

### 步驟 6：產出提案檔

路徑：`/home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}.md`

格式：

```markdown
---
week: {WEEK_ID}
date_range: {DATE_START} to {DATE_END}
generated: {TODAY}
sessions_analyzed: {N}
---

## 分析摘要

{2-3 句話說明本週的主要發現}

## A. 規則違反 / 被忽略

{條列，每項附 session 日期依據}

## B. 新行為模式（建議新增規則）

{條列提案，包含建議的規則文字}

## C. 過時規則（建議修改或刪除）

{條列，包含原文與建議修改後的文字}

## 建議的 AGENTS.md 變更

```diff
{完整的 unified diff 格式，可直接套用}
```
```

若本週無足夠資料（SessionLog 少於 3 個），寫明原因並跳過 diff 產出。

使用 Write 工具寫入檔案。

### 步驟 7：寫入待辦

讀取 `/home/laura/vault/04-Todos/todos.md`，在 `## Open` 區塊的最頂端新增：

```markdown
- [ ] **審核 AGENTS.md 週更新提案 ({WEEK_ID})** `high`
  - 提案檔：`vault/00-Laura-Persona/proposals/{WEEK_ID}.md`
  - 分析範圍：{DATE_START} → {DATE_END}，共 {N} 個 session
  - _Added: {TODAY}_
```

使用 Read + Write 更新 todos.md。
