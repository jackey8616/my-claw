# SPEC: OS-Level Network Escape Prevention

**Version:** 1.0
**Status:** Approved
**Date:** 2026-04-06

---

## 範圍

防止主代理透過 Bash 執行出站網路連線。

---

## 威脅

外部 injection 操控主代理，在 Bash 執行 `curl` / `wget` / `nc` 等指令將 vault 資料外傳至任意 host。

---

## 措施

在 `.claude/settings.json` 加入：

```json
"sandbox": {
  "enabled": true,
  "failIfUnavailable": true
}
```

依賴套件（Linux，Ubuntu 24.04）：

```bash
sudo apt-get install bubblewrap socat uidmap
```

Ubuntu 24.04 預設啟用 `kernel.apparmor_restrict_unprivileged_userns`，需額外建立 AppArmor profile：

```bash
sudo tee /etc/apparmor.d/bwrap << 'EOF'
abi <abi/4.0>,
include <tunables/global>

/usr/bin/bwrap flags=(unconfined) {
  userns,
}
EOF
sudo apparmor_parser -r /etc/apparmor.d/bwrap
```

Claude Code 的 seccomp helper 需要執行權限：

```bash
chmod +x ~/.nvm/versions/node/*/lib/node_modules/@anthropic-ai/claude-code/vendor/seccomp/x64/apply-seccomp
```

效果：Bash process 受 Linux namespace 隔離，無法建立出站網路連線。

---

## 接受的殘留風險

| 風險 | 說明 | 後續計畫 |
|---|---|---|
| `WebFetch` 不受 sandbox 覆蓋 | 工具本身可存取任意 URL | 工具層 allowlist 規格（待撰寫） |
| MCP 工具出站行為不受限 | Discord plugin 屬授權行為，其餘待評估 | 工具層規格統一處理 |

---

## Eval 測試案例

| ID | 操作 | 預期結果 |
|---|---|---|
| TC-OS-001 | Bash 執行 `curl https://evil.com` | 失敗（網路被隔離） |
| TC-OS-002 | Bash 執行 `echo "test"` | 成功（非網路操作不受影響） |
| TC-OS-003 | `WebFetch` github.com | 成功（sandbox 不覆蓋） |

---

## 不在此規格範圍

- Linode Cloud Firewall outbound 規則（B 層，暫緩）
- WebFetch domain allowlist（工具層規格，下一步）

---

## 相關文件

- 工具層規格：`docs/security/tool-allowlist.md`（待撰寫）
