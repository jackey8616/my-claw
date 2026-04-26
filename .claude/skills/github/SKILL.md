---
name: github
description: GitHub 工作流程助手：整理 jj commits、開自己 repo 的 PR、合併 PR、開 upstream PR。
disable-model-invocation: false
argument-hint: prepare|pr|merge <PR#>|upstream-pr <owner/repo>
allowed-tools: Bash Read
---

## 提交機制說明

本 skill 使用 **jj（Jujutsu）** 管理本地提交。工作流程分兩層：

- **jj 層**：commit 整理（split / squash / describe / bookmark）
- **git 層**：網路操作（push 到 remote、GitHub API）

不使用 `git add` 或 `git commit`。

---

## 環境準備

執行前先載入 token：

```bash
source /home/laura/my-claw/.env
# GH_TOKEN 現在可用
```

取得當前 repo 資訊：

```bash
git remote get-url origin
jj log -r '@'
jj bookmark list
```

從 remote URL 解析出 owner 和 repo name（格式：`https://github.com/<owner>/<repo>.git`）。

---

## 操作選單

根據 `$ARGUMENTS` 判斷要執行哪個操作。若 `$ARGUMENTS` 為空，列出以下選項請使用者選擇：

1. `prepare` — 整理 jj commits，確認推送就緒
2. `pr` — 在自己的 repo 開 Pull Request
3. `merge <PR#>` — 合併指定 PR
4. `upstream-pr <owner/repo>` — fork 並對 upstream 開 PR

---

## 操作 1：prepare

**觸發**：`$ARGUMENTS` 包含 `prepare`，或由 `pr` 前置步驟呼叫

### 步驟

1. 顯示相對於 main 的待推送 commits：

   ```bash
   jj log -r 'ancestors(@, 20) ~ ancestors(main@origin, 1)' \
     --no-graph \
     -T 'change_id.short() ++ "\t" ++ description.first_line() ++ "\n"'
   ```

2. 找出 description 為空的 commits（代表尚未命名）：

   ```bash
   jj log -r 'ancestors(@, 20) ~ ancestors(main@origin, 1)' \
     --no-graph \
     -T 'if(description == "", change_id.short() ++ " [NO MESSAGE]\n")'
   ```

3. 對每個 NO MESSAGE 的 commit，查看其內容後自行判斷：

   ```bash
   jj diff -r <change-id>
   ```

   - 若變更邏輯上屬於前一個 commit $\rightarrow$ `jj squash -r <id>`
   - 若是獨立功能 $\rightarrow$ `jj describe -r <id> -m "<conventional-commit-message>"`

4. 所有 commits 都有 meaningful description 後，回報清單給使用者確認。

---

## 操作 2：pr（開自己 repo 的 PR）

**觸發**：`$ARGUMENTS` 包含 `pr`（且不含 `upstream`）

### 步驟

1. 執行 prepare（確認 commits 就緒）

2. 確認或建立 bookmark（jj 的 branch 對應物）：

   ```bash
   jj bookmark list
   ```

   若 `@` 尚未綁定 bookmark，依 commit messages 推斷語意建立：

   ```bash
   # 命名規則：feat/<topic> 或 fix/<topic>，全小寫 kebab-case
   jj bookmark create <name> -r @
   ```

3. 將 bookmark 同步至 git，再推送 remote：

   ```bash
   # colocated repo 中 jj bookmark 已對應 git branch，直接 git push
   source /home/laura/my-claw/.env
   git push "https://x-access-token:${GH_TOKEN}@github.com/<owner>/<repo>.git" <bookmark>
   ```

4. 收集 PR 資訊：
   - `title`：最頂層 commit 的 description first line，或從所有 commits 推斷整體語意
   - `body`：所有 commits 的 description，格式為 markdown checklist
   - `head`：bookmark 名稱
   - `base`：`main`

5. 建立 PR：

   ```bash
   # 使用 GitHub CLI (gh) 建立 PR
   gh pr create \
     --title "<title>" \
     --body "<body>" \
     --head <bookmark> \
     --base main
   ```

6. 從回應取出 PR URL 並回報

---

## 操作 3：merge（合併 PR）

**觸發**：`$ARGUMENTS` 包含 `merge`，後面接 PR 編號（例如 `merge 42`）

### 步驟

1. 從 `$ARGUMENTS` 取出 PR 編號

2. 查詢 PR 狀態確認可合併：

   ```bash
   gh pr view <PR#>
   ```

3. 顯示 PR 標題、分支、狀態，請使用者確認

4. 執行合併（預設 squash merge）：

   ```bash
   gh pr merge <PR#> --squash --delete-branch
   ```

5. 合併成功後，拉取最新 main 並刪除本地 bookmark：

   ```bash
   jj git fetch
   jj bookmark delete <bookmark>
   ```

6. 回報合併結果（commit SHA）

---

## 操作 4：upstream-pr（對 upstream 開 PR）

**觸發**：`$ARGUMENTS` 包含 `upstream-pr`，後面接 `<owner>/<repo>`

### 步驟

1. 從 `$ARGUMENTS` 取出 upstream repo

2. 取得 Laura 的 GitHub username：

   ```bash
   source /home/laura/my-claw/.env
   gh api user --jq '.login'
   ```

3. Fork upstream repo（若尚未 fork）：

   ```bash
   gh repo fork <upstream-owner>/<upstream-repo> --clone
   ```

4. Clone fork 至暫存目錄（使用 git，upstream-pr 不需要 jj）：

   ```bash
   git clone "https://x-access-token:${GH_TOKEN}@github.com/<my-username>/<upstream-repo>.git" /tmp/<upstream-repo>
   ```

5. 建立 feature branch、套用修改、commit、推送：

   ```bash
   cd /tmp/<upstream-repo>
   git checkout -b <feature-branch>
   # 套用修改
   git add -A
   git commit -m "<message>"
   git push "https://x-access-token:${GH_TOKEN}@github.com/<my-username>/<upstream-repo>.git" <feature-branch>
   ```

6. 對 upstream 開 PR：

   ```bash
   gh pr create \
     --repo <upstream-owner>/<upstream-repo> \
     --title "<title>" \
     --body "<body>" \
     --head <my-username>:<feature-branch> \
     --base main
   ```

7. 回報 PR URL

---

## 注意事項

- Token 載入後不要輸出完整值，僅顯示前 10 碼確認
- API 回應若含 `"message"` 欄位通常代表錯誤，顯示給使用者
- 合併操作前務必讓使用者確認
- bookmark 命名全小寫 kebab-case，不使用 `main` 或 `master`

---

## Quick Reference Table

| Action | Recommended Command (gh) | Fallback/Advanced |
|--------|--------------------------|------------------|
| Clone | `gh repo clone o/r` | `git clone https://github.com/o/r.git` |
| Create repo | `gh repo create name --public` | `curl POST /user/repos` |
| Fork | `gh repo fork o/r --clone` | `curl POST /repos/o/r/forks` |
| Repo info | `gh repo view o/r` | `curl GET /repos/o/r` |
| Edit settings | `gh repo edit --...` | `curl PATCH /repos/o/r` |
| Create release | `gh release create v1.0` | `curl POST /repos/o/r/releases` |
| List workflows | `gh workflow list` | `curl GET /repos/o/r/actions/workflows` |
| Rerun CI | `gh run rerun ID` | `curl POST /repos/o/r/actions/runs/ID/rerun` |
| Set secret | `gh secret set KEY` | `curl PUT /repos/o/r/actions/secrets/KEY` |
