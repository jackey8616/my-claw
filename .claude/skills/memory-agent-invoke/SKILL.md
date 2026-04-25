---
name: memory-agent-invoke
description: 呼叫 memory-agent subprocess 寫入 memory graph。封裝 --allowedTools 清單，供所有無 memory write 權限的 session 使用。
allowed-tools: Bash
---

## 用途

透過 Bash 啟動獨立的 `memory-agent` process 寫入 memory graph。

呼叫方（Archive Skill 或其他 session）不需要 memory write 權限，也不需要知道 `--allowedTools` 細節。

## 輸入格式

`$ARGUMENTS` 為 JSON 字串，包含以下 key（可部分省略）：

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

## 執行

```bash
ollama launch claude --model gemma4:31b-cloud --agent memory-agent \
  --allowedTools "mcp__memory__create_entities,mcp__memory__create_relations,mcp__memory__add_observations,mcp__memory__delete_entities,mcp__memory__delete_observations,mcp__memory__compact_graph" \
  -p '$ARGUMENTS'
```

## 注意

- 不加 `--dangerously-skip-permissions`，非 memory 工具在非互動模式下會被 permission prompt 阻斷
- `--allowedTools` 清單是唯一維護點，memory tools 有增減時只改此處
- 回傳 memory-agent 的寫入摘要
