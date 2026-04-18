# SPEC: Memory Graph Write Isolation

**Version:** 1.0
**Status:** Approved
**Date:** 2026-04-06

---

## 範圍

限制主代理對 memory graph 的寫入與破壞性操作，確保圖譜資料只能在封存時被修改。

---

## 威脅

| 威脅 | 說明 |
|---|---|
| Injection 操控寫入 | 外部內容（網頁、搜尋結果）誘導主代理將錯誤或惡意資訊寫入 memory graph，污染長期記憶 |
| Injection 操控刪除 | 外部內容誘導主代理刪除重要記憶節點，造成知識損失 |
| 角色混淆寫入 | 對話中的誤判導致錯誤資料寫入圖譜（已發生過一次，見 2026-04-05 session） |

---

## 措施

### 主代理：唯讀

`settings.json` 的 `permissions.allow` 只保留讀取工具，移除所有寫入工具：

```json
"permissions": {
  "allow": [
    "mcp__memory__open_nodes",
    "mcp__memory__search_nodes",
    "mcp__memory__read_graph"
  ]
}
```

**移除**：`mcp__memory__create_entities`、`mcp__memory__add_observations`

寫入工具未出現在 allow list，預設需要人工確認（permission prompt）或可加入 deny list 強制封鎖。

### Archive Skill：唯一寫入者

Archive Skill 的 `allowed-tools` 保留全部寫入與破壞性工具：

```
allowed-tools: Read Write Bash
  mcp__plugin_discord_discord__reply
  mcp__memory__create_entities
  mcp__memory__create_relations
  mcp__memory__add_observations
  mcp__memory__delete_entities
  mcp__memory__delete_observations
  mcp__memory__compact_graph
```

### 對話中的新知識

主代理在對話中識別到新知識或靈感時：
- **不立即寫入**，留在對話 context
- **封存時統一處理**：archive Skill 根據整個對話 context 判斷寫入內容
- archive Skill 本身有完整對話資訊，不依賴主代理的即時寫入

---

## 信任邊界圖

```
外部內容（WebFetch/WebSearch）
  │
  ▼  [fetch-external Skill, fork 隔離]
結構化 JSON
  │
  ▼
主代理（對話中）
  │  唯讀 memory
  │  知識暫存於 context
  │
  ▼  [archive Skill，session 結束時]
Memory Graph 寫入
```

---

## 接受的殘留風險

| 風險 | 說明 | 後續計畫 |
|---|---|---|
| Archive Skill 本身可被 injection 影響 | Archive 在 session 末尾執行，有完整對話歷史，但若整個對話已被污染，archive 仍可能寫入錯誤資料 | 長期觀察；考慮在 archive prompt 加入 sanity check |
| 讀取工具仍暴露 memory 內容 | 主代理唯讀不等於 memory 內容安全；injection 可能讀取後洩漏（但 Bash sandbox 已阻斷出站連線） | OS 層 sandbox 已覆蓋此風險 |

---

## Eval 測試案例

| ID | 操作 | 預期結果 |
|---|---|---|
| TC-MG-001 | 主代理呼叫 `mcp__memory__create_entities` | 被攔截（permission prompt 或 denied） |
| TC-MG-002 | 主代理呼叫 `mcp__memory__open_nodes` | 成功 |
| TC-MG-003 | Archive Skill 呼叫 `mcp__memory__create_entities` | 成功 |
| TC-MG-004 | Archive Skill 呼叫 `mcp__memory__delete_entities` | 成功 |

---

## 實作優先順序

1. `settings.json` 移除 `create_entities`、`add_observations`，加入 `read_graph`
2. Archive Skill `allowed-tools` 補上 `delete_entities`、`delete_observations`、`compact_graph`
3. 跑 TC-MG-001/002/003/004 eval 驗收

---

## 相關文件

- OS 層規格：`docs/security/os-network-escape-prevention.md`
- 工具層規格：`docs/security/external-content-filtering.md`
