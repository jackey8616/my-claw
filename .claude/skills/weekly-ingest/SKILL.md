---
name: weekly-ingest
description: 每週分析近 7 天 SessionLog 與 DailyNote，對照 AGENTS.md 產出分析草稿，並在 todos.md 新增高優先待辦等待 Clode 回饋。支援三種模式：初始分析、整合回饋產出 diff、套用批准。不直接依賴 Claude Code harness 語法，可在其他 AI 助理環境執行。
disable-model-invocation: false
context: fork
allowed-tools: Read Write Glob Bash
---

## 模式

根據 `$ARGUMENTS` 決定執行模式：

| 模式 | `$ARGUMENTS` 格式 | 說明 |
|------|------------------|------|
| A：初始分析（預設） | 空，或 `YYYY-MM-DD` | 分析近 7 天，產出草稿 + 待辦 |
| B：整合回饋 | `feedback {WEEK_ID}` | 讀草稿，補回饋，產出 diff |
| C：套用批准 | `apply {WEEK_ID}` | 套用 diff，草稿升正式檔，更新待辦 |

---

## 模式 A：初始分析

### 步驟 1：確定資料範圍

使用 Bash 取得當前日期資訊：

```bash
TZ=UTC date '+%Y-%m-%d'              # TODAY
TZ=UTC date -d '7 days ago' '+%Y-%m-%d'  # WEEK_START
TZ=UTC date '+W%V'                   # WEEK_NUM (ISO week number)
TZ=UTC date '+%-V'                   # WEEK_NUM_INT (integer, for quarter check)
```

- DATE_END = TODAY
- DATE_START = WEEK_START（若 `$ARGUMENTS` 為 `YYYY-MM-DD` 格式則以此覆蓋）
- WEEK_ID = `{YYYY}-{WEEK_NUM}`（例：`2026-W16`）

**季度分類 review 檢查：**

讀取 `/home/laura/vault/00-Laura-Persona/eval-config.md`，取得 `categories_last_reviewed` 欄位（格式：`YYYY-WNN`）。

計算距今週數差：`CURRENT_WEEK_INT - LAST_REVIEW_WEEK_INT`（跨年時加 52）。

若週數差 ≥ 13（約一季），在草稿末尾附加：

```markdown
## ⚠️ 季度分類 Review 提醒

距上次 Wall of Failures 大類審查已超過 13 週（上次：{LAST_REVIEWED}）。
建議本週回饋時一併確認五大分類是否仍足夠，或需新增類別。
確認後請更新 `vault/00-Laura-Persona/eval-config.md` 的 `categories_last_reviewed` 欄位。
```

若 `eval-config.md` 不存在，建立初始檔（`categories_last_reviewed: {WEEK_ID}`）並略過提醒。

### 步驟 2：讀取 AGENTS.md

```
/home/laura/vault/00-Laura-Persona/AGENTS.md
```

### 步驟 3：讀取近 7 天 SessionLog

```bash
find /home/laura/vault/01-Session-Logs -name "*.md" \
  -newermt "{DATE_START}" ! -newermt "{DATE_END} 23:59:59" \
  | sort
```

對每個檔案讀取：
- `## 待辦或成果` 段落
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

**0. 讀取上週指標（供趨勢比較）**

```bash
# 找最近一份已完成提案（非 draft、非本週）
ls /home/laura/vault/00-Laura-Persona/proposals/*.md 2>/dev/null \
  | grep -v '\-draft\.md' | sort | tail -1
```

讀取該檔案的 frontmatter，取得：
- `PREV_RULE_COUNT`：上週規則總數
- `PREV_VIOLATIONS`：上週違規次數
- `PREV_DENSITY`：上週違規密度（%）

若無上週資料，趨勢欄位填 `-`。

**A. 規則違反 / 被忽略**

對照 AGENTS.md **兩類規則**逐項檢查：
1. 禁止規則（❌ 標記項）：本週 session 有無直接違反？
2. 要求規則（四節 4.1 session 開始必做清單、4.2 情境行為表、五節核心功能步驟）：逐項確認每個 session 是否遵守。

每條違規引用具體 session 日期。

**B. 新行為模式（尚未有規則涵蓋）**
- 本週反覆出現但 AGENTS.md 沒有明確規定的行為模式？

**C. 過時規則**
- AGENTS.md 中哪些規則已不再適用或需要更新？

**每條 C 項必須包含：**
- 原文引用
- 建議修改後的文字（或明確說明「不修改原因：...」）
- 不得留空或僅提「建議確認」

**E. 量化指標計算**

1. **規則總數 (Rule Count)**

   分兩類計算後相加：
   ```bash
   AGENTS=/home/laura/vault/00-Laura-Persona/AGENTS.md
   # 禁止規則：❌ 標記項目
   PROHIBITION=$(grep -c '❌' "$AGENTS")
   # 要求規則：數字步驟（如 4.1 必做清單）+ 行為表格資料列（如 4.2）+ 其他清單列點
   REQUIRED_STEPS=$(grep -cE '^\s+[0-9]+\.\s+\*\*' "$AGENTS")
   TABLE_RULES=$(grep -cE '^\|\s+[^-:|].*\|' "$AGENTS")
   RULE_COUNT=$((PROHIBITION + REQUIRED_STEPS + TABLE_RULES))
   ```
   標記為 `RULE_COUNT`（禁止 `PROHIBITION` + 要求步驟 `REQUIRED_STEPS` + 要求表格列 `TABLE_RULES`），趨勢 = `RULE_COUNT - PREV_RULE_COUNT`（+/- 或 `-`）。

2. **總對話輪數 (Total Turns)**
   `TOTAL_TURNS`：加總本週所有 SessionLog 中的對話輪數（frontmatter `turns` 欄位為準；無此欄位則計 `## ` 段落數估算）。

3. **總違規次數 (Total Violations)**
   `TOTAL_VIOLATIONS`：A 節違規總次數（各 session 不重複計）。

4. **違規密度 (Violation Density)**
   `VIOLATION_DENSITY = (TOTAL_VIOLATIONS / TOTAL_TURNS) × 100%`（保留兩位小數）
   趨勢 = 與 `PREV_DENSITY` 比較，輸出「↑X%」「↓X%」或「→（持平）」。

5. **錯誤分類牆 (Wall of Failures)**
   將 A 節所有違規各歸入以下五類之一：
   - **遺忘 (Omission)**：應做未做——要求規則未執行
   - **逾越 (Commission)**：不該做卻做——禁止規則被違反
   - **偏離 (Deviation)**：語氣/格式/邏輯漂移，未達品質標準
   - **幻覺 (Hallucination)**：自創事實或規則
   - **衝突 (Conflict)**：規則互相矛盾導致執行失敗

   以表格形式輸出。優先級：Omission / Commission → Deviation → Hallucination / Conflict。

> **D. 使用者體感** 由模式 B 補入，此處略過。
> 草稿節次順序：**📊 規則執行指標（含 Wall of Failures）→ A → B → C → D**

### 步驟 6：產出分析草稿

路徑：`/home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}-draft.md`

此階段不含 diff，等模式 B 整合回饋後產出。

```markdown
---
week: {WEEK_ID}
date_range: {DATE_START} to {DATE_END}
generated: {TODAY}
sessions_analyzed: {N}
status: awaiting-feedback
metrics:
  rule_count: {RULE_COUNT}
  total_turns: {TOTAL_TURNS}
  total_violations: {TOTAL_VIOLATIONS}
  violation_density: {VIOLATION_DENSITY}
---

## 分析摘要

{2-3 句話說明本週主要發現}

## 📊 規則執行指標

| 指標項目 | 數值 | 趨勢 (vs 上週) |
| :--- | :--- | :--- |
| 規則總數 (Rule Count) | {RULE_COUNT} 條 | {+Δ / -Δ / -} |
| 總對話輪數 (Total Turns) | {TOTAL_TURNS} | - |
| 總違規次數 (Total Violations) | {TOTAL_VIOLATIONS} | {+Δ / -Δ / -} |
| **違規密度 (Violation Density)** | **{VIOLATION_DENSITY}%** | **{↑X% / ↓X% / →}** |

**錯誤分類牆 (Wall of Failures)**

| 違規描述 | 分類 |
|---|---|
{每條違規一行：\| 描述 \| 遺忘 / 逾越 / 偏離 / 幻覺 / 衝突 \|}

## A. 規則違反 / 被忽略

{條列，每項附 session 日期依據}

## B. 新行為模式（建議新增規則）

{條列提案，包含建議的規則文字}

## C. 過時規則（建議修改或刪除）

{條列，含原文與建議修改後文字}

## D. 使用者體感

（待回饋填入）
```

若本週 SessionLog 少於 3 個，寫明原因並結束（跳過後續步驟）。

使用 Write 工具寫入檔案。

### 步驟 7：寫入待辦

讀取 `/home/laura/vault/04-Todos/todos.md`，在 `## Open` 區塊最頂端新增：

```markdown
- [ ] **[週報] 提供 {WEEK_ID} 體感回饋並批准** `high`
  - 草稿：`vault/00-Laura-Persona/proposals/{WEEK_ID}-draft.md`
  - 分析範圍：{DATE_START} → {DATE_END}，共 {N} 個 session
  - 流程：提供回饋 → `/weekly-ingest feedback {WEEK_ID}` → 確認 diff → `/weekly-ingest apply {WEEK_ID}`
  - _Added: {TODAY}_
```

使用 Read + Write 更新 todos.md。

---

## 模式 B：整合回饋

**觸發**：`$ARGUMENTS` 格式為 `feedback {WEEK_ID}`

回饋內容由呼叫此模式的主 session 在對話上下文中提供。

### 步驟 B1：讀取草稿

路徑：`/home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}-draft.md`

確認 `status: awaiting-feedback`，否則報錯。

### 步驟 B2：補入使用者體感

將回饋內容填入 `## D. 使用者體感` 段落（逐字保留，不摘要）。

### 步驟 B3：產出 AGENTS.md diff

根據 A、B、C 節分析與 D 節回饋，對照現有 AGENTS.md，產出完整 unified diff：

```diff
--- a/AGENTS.md
+++ b/AGENTS.md
@@ ... @@
```

每條修改必須有對應的分析依據（標明來自 A/B/C 哪一節）。

### 步驟 B4：將 diff 寫回草稿

在草稿末尾新增：

```markdown
## E. 建議的 AGENTS.md 變更

\`\`\`diff
{unified diff}
\`\`\`
```

更新 frontmatter `status: diff-ready`，使用 Write 覆寫草稿。

---

## 模式 C：套用批准

**觸發**：`$ARGUMENTS` 格式為 `apply {WEEK_ID}`

### 步驟 C1：讀取並驗證草稿

路徑：`/home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}-draft.md`

確認 `status: diff-ready`，否則報錯停止。

### 步驟 C2：套用 diff

讀取 `## E. 建議的 AGENTS.md 變更` 中的 diff，使用 Edit tool 將每條變更套用至：
```
/home/laura/vault/00-Laura-Persona/AGENTS.md
```

### 步驟 C3：升格為正式檔

更新草稿 frontmatter：
- `status: applied`
- `applied: {TODAY}`

覆寫後用 Bash 重新命名：

```bash
mv /home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}-draft.md \
   /home/laura/vault/00-Laura-Persona/proposals/{WEEK_ID}.md
```

### 步驟 C4：更新待辦

在 todos.md 中找到對應的 `[ ] **[週報] 提供 {WEEK_ID}...`，改為 `[x]` 並補上 `_Done: {TODAY}_`。
