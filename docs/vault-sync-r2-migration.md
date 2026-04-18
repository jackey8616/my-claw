# Vault Sync 重構規格：Syncthing + iCloud → Cloudflare R2

**Status**: Done  
**Created**: 2026-04-17  
**Author**: Laura

---

## 一、現況問題

| 問題 | 說明 |
|---|---|
| Mac 必須開著 | VPS → Syncthing → Mac → iCloud → iPhone，鏈上任一斷點就無法同步 |
| iCloud 無 Linux client | VPS 無法直接寫入 iCloud，必須繞道 Mac |
| Syncthing container 多餘 | 一個 Docker container 只為了橋接兩端，維護成本高 |
| iPhone 更新延遲 | 依賴 Mac 中繼，Mac 關機就停更 |

---

## 二、目標架構

```
Cloudflare R2 Bucket（vault 唯一 source of truth）
        ↑↓                        ↑↓
VPS（rclone mount）      iPhone Obsidian
/home/laura/vault         Mac Obsidian
                          （Remotely Save 插件）
```

- VPS 透過 **rclone FUSE mount** 把 R2 bucket 掛載成本地目錄
- Mac 和 iPhone 的 Obsidian 透過 **Remotely Save** 插件直接對 R2 sync
- 三端完全獨立，任何一端離線不影響其他端

---

## 三、組件清單

### 3.1 Cloudflare R2

- 建立一個 R2 bucket（例如：`laura-vault`）
- 建立 **3 個獨立 API Token**，各自 scope 到同一 bucket 的 object read/write：
  - `vps-rclone`（VPS 使用）
  - `mac-remotely-save`（Mac 使用）
  - `iphone-remotely-save`（iPhone 使用）
- 每個 token 權限：`Object Read` + `Object Write`（無 bucket admin、無 delete bucket）

### 3.2 VPS：rclone

- 安裝 rclone，設定 R2 remote（endpoint = CF R2 S3-compatible URL）
- FUSE mount：`rclone mount r2:laura-vault /home/laura/vault --vfs-cache-mode full --daemon`
- systemd service 管理 mount，開機自動掛載、斷線自動重連
- 舊的 Syncthing Docker container 停用並移除

### 3.3 Mac：Remotely Save 插件

- Obsidian 安裝 Remotely Save 社群插件
- 設定：S3-compatible → R2 endpoint / `mac-remotely-save` token / bucket name
- 啟用 E2E 加密（與 iPhone 使用相同加密密碼）
- Sync 時機：開啟 Obsidian 時自動觸發

### 3.4 iPhone：Remotely Save 插件

- 相同插件設定，使用 `iphone-remotely-save` token
- 相同 E2E 加密密碼
- 在 iOS 設定中將 Obsidian 排除出 iCloud 備份（避免 credentials 進 iCloud）
- Sync 時機：每次開啟 app 自動觸發

---

## 四、安全設計

| 層次 | 措施 |
|---|---|
| Token 隔離 | 每裝置獨立 token，任一洩漏直接從 CF dashboard 撤銷 |
| 最小權限 | Token 只有 object r/w，無法刪除 bucket 或管理 token |
| E2E 加密 | Remotely Save 上傳前加密，R2 裡只有 ciphertext |
| iOS 備份隔離 | Obsidian 排除 iCloud 備份，credentials 不進 iCloud |

---

## 五、費用估算

| 項目 | 費用 |
|---|---|
| R2 儲存（10GB 內）| 免費（free tier 10GB） |
| R2 Class A operations（寫入）| $4.50 / 百萬次（vault 規模可忽略） |
| R2 Class B operations（讀取）| $0.36 / 百萬次（同上） |
| **Egress（最重要）** | **免費**（R2 egress 永遠免費） |
| 月估計 | **$0 ~ <$1** |

---

## 六、遷移步驟

1. **建立 R2 bucket + 3 個 API token**
2. **Mac 端先做**：裝 Remotely Save，設定好 R2，初次 sync（把現有 vault 上傳到 R2）
3. **VPS 端**：
   - 安裝 rclone
   - 設定 R2 remote（`vps-rclone` token）
   - 停止 Syncthing：`docker compose down syncthing`
   - FUSE mount R2 到 `/home/laura/vault`
   - 設定 systemd service
4. **iPhone 端**：裝 Remotely Save，設定 R2，初次 sync
5. **驗收**：
   - VPS 寫一個測試檔到 vault → iPhone Obsidian sync 後可見
   - iPhone 在 Mac 關機狀態下能看到最新 session log
6. **清理**：從 `setup-new-vps.sh` 移除 Syncthing 相關步驟，加入 rclone 安裝與 systemd mount

---

## 七、setup-new-vps.sh 需要的修改

- 移除：Step 4（docker-compose.yml Syncthing）、Step 5（Syncthing 設定）
- 新增 Step 4：安裝 rclone + 設定 R2 remote + systemd vault mount service
- `.env` 新增：`R2_ACCOUNT_ID`、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY`、`R2_BUCKET_NAME`
- `load_env` 補問這 4 個欄位

---

## 八、已確認決策

- [x] E2E 加密密碼 → `.env` 存放（`R2_E2E_PASSWORD`）
- [x] rclone `--vfs-cache-mode` → `full`
- [x] iCloud vault → 穩定後廢棄，時間點另行決定
- [x] R2 Object Versioning → 遷移穩定後再評估是否啟用

## 九、iPhone 遷移注意事項

iPhone 目前使用原生 iCloud sync（非 Obsidian Sync）。遷移後：
- 在 Obsidian 建立**新的 local vault**（非 iCloud 路徑）
- 安裝 Remotely Save → 設定 R2 → 從 R2 初次 sync 拉下 vault
- 舊的 iCloud vault 自然閒置，穩定後再刪除
