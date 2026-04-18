---
name: cover-letter
description: 根據 JD 連結與 vault 中的 CV 及舊 Cover Letter 範本，產出格式一致的 Cover Letter。
allowed-tools: Read Write
---

## 輸入

`$ARGUMENTS` 為以下其中一種：
- JD 的 URL
- 直接貼上的 JD 文字（當 URL 無法擷取時）

## 執行步驟

### 步驟 1：取得 JD 內容

若輸入為 URL，呼叫 `/fetch-external $ARGUMENTS` 取得 JD 的結構化內容。

若回傳 `status: "error"`，或 `status: "ok"` 但 `summary` 與 `key_facts` 皆為空，**停止執行**，回覆 Clode：

> 「無法從 URL 取得 JD 內容（原因：`{message}`）。請直接貼上 JD 文字，我再繼續產出。」

否則，從內容中提取：公司名稱、職位名稱、職責描述、技能要求。

### 步驟 2：讀取 CV

讀取 `/home/laura/vault/05-Knowledge-Base/career/CV 2026.md`。

若不存在，告知 Clode 需先補充資料，停止執行。

### 步驟 3：建立 Markdown 檔案並寫入 JD 與匹配度

**3a. 建立檔案**

路徑：`/home/laura/vault/05-Knowledge-Base/career/cover-letters/YYYY-MM_公司名.md`（日期取當前時間，公司名從 JD 提取）

**3b. 寫入 JD 摘要**

```markdown
| Company  | {公司名稱}   |
| -------- | ------------ |
| Position | {職位名稱}   |
| JD Url   | {URL 或 N/A} |

# JD

{JD 原文或摘要}
```

**3c. 計算匹配度（0–10 分）並寫入**

對照 JD 的技能要求與職責，評估 CV 的吻合程度，給出 0–10 整數分，並列出評分理由（強項、缺口各最多 3 點）。

格式：
```markdown
# Match Score

**Score: {N}/10**

**優勢（JD 要求 → CV 對應）**
- {優勢 1}
- {優勢 2}
- {優勢 3}

**缺口（JD 要求但 CV 不足）**
- {缺口 1}
- {缺口 2}
```

**3d. 若分數 < 5，停止並回報**

將以上內容寫入 markdown 後，回覆 Clode：

> 「匹配度 {N}/10，低於門檻。主要缺口：{缺口摘要}。檔案已存入 `{路徑}`。是否仍要繼續產出 Cover Letter？」

**等待 Clode 明確要求繼續後，才執行步驟 4–5。**

若分數 ≥ 5，直接繼續執行步驟 4。

### 步驟 4：讀取舊 Cover Letter 並產出

讀取 `/home/laura/vault/05-Knowledge-Base/career/cover-letters/` 下所有 `.md` 檔案（排除當前正在寫入的檔案），用於校準語氣與風格。

產出 Cover Letter，遵守以下固定規則：

**問候語（依公司文化判斷）：**
- 新創 / 小型公司 / 非正式文化 → `Hi [Company] hiring team,`
- 大型企業 / 諮詢公司 / 正式文化 → `Dear Hiring Manager,`

**開頭句（依公司文化判斷）：**
- 新創 / 非正式 → `I'm reaching out regarding the [Position] role.`
- 正式 → `I am writing to apply for the [Position] role at [Company].`

**段落結構（3–4 段，純 prose，不使用 bullet points）：**
1. **第 1 段（引入）**：說明身份（Tech Lead / Full-Stack Engineer），立即連結 JD 核心需求，附上一個數字化成就作為開場佐證
2. **第 2–3 段（技術證明）**：每段聚焦 JD 中的一個核心需求，用具體過往成就呼應；必須點名 JD 的關鍵詞，再用自己的話連結
3. **最後段（收尾）**：表達想進一步交流（`I would love to chat more about...` / `I'd love to chat more about...`），或說明地點/身份（如 NZ citizen）

**結尾（固定格式）：**
```
Best regards,

KO-LI, MO
GitHub: https://github.com/jackey8616
```

**寫作規則（必須遵守）：**
- 所有成就必須量化：使用 60x、70%、4x、20k+、30k+、175+ 等具體數字（從 CV 取得）
- 每次提到技術名稱，必須附上使用脈絡（不列清單）
- 明確將 JD 的職責語言對應到自身經驗（explicit mapping）
- 全篇 200–350 字，不超過 4 段
- 不使用以下類型的語句：「I am passionate about...」、「I am a hardworking...」、未有佐證的形容詞

### 步驟 5：附加至 Markdown 並輸出

將 Cover Letter **附加**至步驟 3 建立的同一份 markdown 檔案末尾：

```markdown
# CoverLetter

{Cover Letter 全文}
```

更新檔案後，將 Cover Letter 全文輸出給 Clode 審閱。
