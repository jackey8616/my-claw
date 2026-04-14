# SPEC: Memory Agent & Invoke Skill

**Version:** 1.0
**Status:** Implemented
**Date:** 2026-04-08

---

## 問題背景

主代理（Laura Agent）及所有正常 session 不得直接寫入 memory graph（記憶圖譜寫入隔離，見 `memory-graph-write-isolation.md`）。但 Archive 流程必須在 session 結束時寫入。

先前的 Archive Skill 直接在主 session 呼叫 `mcp__memory__*` 工具，違反寫入隔離原則。

---

## 設計目標

1. 主 session 硬封鎖 memory write（技術強制，非行為約束）
2. Archive Skill 仍能寫入 memory graph
3. 寫入工具隔離：MemoryAgent 只能使用 memory 工具（技術強制）

---

## 架構

```
Archive Skill（主 session，無 memory write 權限）
  步驟 1-3: SessionLog + DailyNote（Read/Write）
  步驟 4:   精煉 memory data → JSON
            → /memory-agent-invoke <json>
  步驟 5:   Discord 通知
  步驟 6:   重啟 session

memory-agent-invoke Skill
  allowed-tools: Bash
  執行：Bash subprocess → claude --agent memory-agent --allowedTools <memory tools only> -p <json>

memory-agent（獨立 process）
  tools 白名單：只有 mcp__memory__* 六個工具
  輸入：結構化 JSON（entities / relations / observations）
  輸出：寫入摘要
```

---

## 工具隔離機制

**關鍵發現：** agent frontmatter 的 `tools` 白名單只對透過 Agent 工具生成的 subagent 有效，`--agent` CLI 直接啟動時不套用。

**解法：** `--allowedTools` + 不加 `--dangerously-skip-permissions` + `-p`（非互動）

- `--allowedTools "<memory tools>"` → 只有這些工具自動批准
- 無 `--dangerously-skip-permissions` → 其他工具觸發 permission prompt
- `-p`（非互動）→ permission prompt 無法回答 → 非 memory 工具實際上被阻斷

技術強制，不依賴模型行為約束。

---

## 檔案

| 檔案 | 說明 |
|---|---|
| `.claude/agents/memory-agent.md` | MemoryAgent 定義（tools 白名單、system prompt） |
| `.claude/skills/memory-agent-invoke/SKILL.md` | Invoke Skill（封裝 Bash 呼叫與 --allowedTools 清單） |

---

## memory-agent-invoke 呼叫格式

```bash
claude --agent memory-agent \
  --allowedTools "mcp__memory__create_entities,mcp__memory__create_relations,\
mcp__memory__add_observations,mcp__memory__delete_entities,\
mcp__memory__delete_observations,mcp__memory__compact_graph" \
  -p '<json>'
```

**`--allowedTools` 是唯一維護點。** memory tools 有增減時只改 `memory-agent-invoke/SKILL.md`。

---

## JSON 輸入格式

```json
{
  "entities": [
    { "name": "NodeName", "entityType": "concept", "observations": ["說明"] }
  ],
  "relations": [
    { "from": "NodeA", "to": "NodeB", "relationType": "relates_to" }
  ],
  "observations": [
    { "entityName": "NodeName", "contents": ["補充觀察"] }
  ]
}
```

三個 key 均可省略，依實際需要傳入。

---

## Eval 測試案例

| ID | 操作 | 預期結果 | 狀態 |
|---|---|---|---|
| TC-MA-001 | memory-agent 接收 entities JSON | create_entities 成功 | ✅ 2026-04-08 |
| TC-MA-002 | memory-agent 接收 relations JSON | create_relations 成功 | 待跑 |
| TC-MA-003 | memory-agent 接收 observations JSON | add_observations 成功 | 待跑 |
| TC-MA-004 | memory-agent 嘗試呼叫 Read 工具 | 被阻斷（permission prompt） | ✅ 2026-04-08 |
| TC-MA-005 | memory-agent 嘗試呼叫 Discord reply | 被阻斷 | ✅ 2026-04-08 |
| TC-AS-002 | Archive Skill 步驟 4 直接呼叫 mcp__memory__* | 被拒絕（allowed-tools 已移除） | 待實作 |
| TC-AS-003 | 完整 archive 流程（Skill → memory-agent-invoke → MemoryAgent） | memory graph 更新 ✅ | 待實作 |

---

## 待完成

- [ ] Archive Skill 步驟 4 改用 `/memory-agent-invoke`，移除 `mcp__memory__*` allowed-tools
- [ ] 跑 TC-MA-002/003、TC-AS-002/003
- [ ] Laura Agent 加入 `disallowedTools: [mcp__memory__*]`（依賴 Archive Skill 改動完成）

---

## 相關文件

- `docs/security/memory-graph-write-isolation.md`
- `docs/security/external-content-filtering.md`
