---
name: github
description: GitHub 工作流程助手：commit 到分支、開自己 repo 的 PR、合併 PR、開 upstream PR。
disable-model-invocation: false
argument-hint: commit|pr|merge <PR#>|upstream-pr <owner/repo>
allowed-tools: Bash Read
---

## 前置檢查

執行任何操作前，先確認 GitHub 整合已設定：

```bash
source /home/laura/my-claw/.env
if [ -z "$GH_TOKEN" ]; then
  echo "❌ GitHub 整合未啟用：GH_TOKEN 不存在於 .env"
  echo "請重新執行 setup-new-vps.sh 並選擇啟用 GitHub integration。"
  exit 1
fi
```

若 GH_TOKEN 不存在，立即停止，告知使用者 GitHub skill 未啟用，不繼續執行任何操作。

---

## 環境準備

執行前先載入 token：

```bash
source /home/laura/my-claw/.env
# GH_TOKEN 現在可用
# 用法：git push https://x-access-token:${GH_TOKEN}@github.com/<owner>/<repo>.git <branch>
# GitHub API：curl -H "Authorization: Bearer ${GH_TOKEN}" https://api.github.com/...
```

取得當前 repo 資訊：

```bash
git remote get-url origin        # 取得 remote URL
git rev-parse --abbrev-ref HEAD  # 取得目前分支
git status --short               # 查看變更
```

從 remote URL 解析出 owner 和 repo name（格式通常是 `https://github.com/<owner>/<repo>.git`）。

---

## 操作選單

根據 `$ARGUMENTS` 判斷要執行哪個操作。若 `$ARGUMENTS` 為空，列出以下選項請使用者選擇：

1. `commit` — 提交目前變更到分支
2. `pr` — 在自己的 repo 開 Pull Request
3. `merge <PR#>` — 合併指定 PR
4. `upstream-pr <owner/repo>` — fork 並對 upstream 開 PR

---

## 操作 1：commit

**觸發**：`$ARGUMENTS` 包含 `commit`

### 步驟

1. 確認目前分支名稱
2. 確認有未提交的變更（`git status`）
3. 若使用者有提供 commit message，直接使用；否則根據變更內容提議一個 conventional commit 格式的訊息並請使用者確認
4. 執行：
   ```bash
   git add -A
   git commit -m "<message>"
   ```
5. 詢問是否要推送到遠端：
   ```bash
   source /home/laura/my-claw/.env
   git push https://x-access-token:${GH_TOKEN}@github.com/<owner>/<repo>.git <branch>
   ```
6. 回報結果（commit hash + 是否已推送）

---

## 操作 2：pr（開自己 repo 的 PR）

**觸發**：`$ARGUMENTS` 包含 `pr`（且不含 `upstream`）

### 步驟

1. 取得目前分支名稱，確認不是 `main`（若是 `main` 則提醒先建立 feature branch）
2. 確認目前分支已推送到遠端（若無，先推送）
3. 收集資訊：
   - `head`：目前分支
   - `base`：預設 `main`
   - `title`：從 `$ARGUMENTS` 取，或根據最近 commit 訊息提議
   - `body`：根據 commit 列表自動生成（`git log main..HEAD --oneline`）
4. 用 GitHub API 建立 PR：
   ```bash
   source /home/laura/my-claw/.env
   curl -s -X POST \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"title\": \"<title>\", \"body\": \"<body>\", \"head\": \"<branch>\", \"base\": \"main\"}" \
     https://api.github.com/repos/<owner>/<repo>/pulls
   ```
5. 從回應取出 PR URL 並回報

---

## 操作 3：merge（合併 PR）

**觸發**：`$ARGUMENTS` 包含 `merge`，後面接 PR 編號（例如 `merge 42`）

### 步驟

1. 從 `$ARGUMENTS` 取出 PR 編號
2. 先查詢 PR 狀態確認可合併：
   ```bash
   source /home/laura/my-claw/.env
   curl -s \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     https://api.github.com/repos/<owner>/<repo>/pulls/<PR#>
   ```
3. 顯示 PR 標題、分支、狀態，請使用者確認
4. 執行合併（預設 squash merge）：
   ```bash
   curl -s -X PUT \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"merge_method\": \"squash\"}" \
     https://api.github.com/repos/<owner>/<repo>/pulls/<PR#>/merge
   ```
5. 回報合併結果（commit SHA）

---

## 操作 4：upstream-pr（對 upstream 開 PR）

**觸發**：`$ARGUMENTS` 包含 `upstream-pr`，後面接 `<owner>/<repo>`（例如 `upstream-pr anthropics/claude-plugins-official`）

### 步驟

1. 從 `$ARGUMENTS` 取出 upstream repo（`<upstream-owner>/<upstream-repo>`）
2. 取得 Laura 的 GitHub username（從 GH_TOKEN 查詢）：
   ```bash
   source /home/laura/my-claw/.env
   curl -s -H "Authorization: Bearer ${GH_TOKEN}" https://api.github.com/user | grep '"login"'
   ```
3. Fork upstream repo（若尚未 fork）：
   ```bash
   curl -s -X POST \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     https://api.github.com/repos/<upstream-owner>/<upstream-repo>/forks
   ```
4. Clone fork 到本地（臨時目錄）：
   ```bash
   git clone https://x-access-token:${GH_TOKEN}@github.com/<my-username>/<upstream-repo>.git /tmp/<upstream-repo>
   ```
5. 建立 feature branch、套用修改、commit、推送到 fork
6. 對 upstream 開 PR：
   ```bash
   curl -s -X POST \
     -H "Authorization: Bearer ${GH_TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"title\": \"<title>\", \"body\": \"<body>\", \"head\": \"<my-username>:<branch>\", \"base\": \"main\"}" \
     https://api.github.com/repos/<upstream-owner>/<upstream-repo>/pulls
   ```
7. 回報 PR URL

---

## 注意事項

- Token 載入後不要輸出完整值，僅顯示前 10 碼確認
- API 回應若含 `"message"` 欄位通常代表錯誤，顯示給使用者
- 合併操作前務必讓使用者確認
