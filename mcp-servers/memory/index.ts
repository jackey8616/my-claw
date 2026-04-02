#!/usr/bin/env bun
/**
 * Laura's custom Memory MCP Server
 *
 * Drop-in replacement for @modelcontextprotocol/server-memory with:
 * - auto last_seen tracking on every entity write
 * - graph_health_check: list entities stale for N+ days
 * - compact_graph: dedup, prune orphans, rewrite file
 *
 * File format: NDJSON (compatible with @modelcontextprotocol/server-memory)
 * Each line is a JSON object with a "type" field ("entity" or "relation").
 * Migrates standard JSON format on first load if detected.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js"
import { readFileSync, writeFileSync, existsSync } from "fs"

// ── Types ──────────────────────────────────────────────────────────────────

interface Entity {
  name: string
  entityType: string
  observations: string[]
  last_seen: string
}

interface Relation {
  from: string
  to: string
  relationType: string
}

interface Graph {
  entities: Entity[]
  relations: Relation[]
}

// ── Storage ────────────────────────────────────────────────────────────────

const MEMORY_FILE = process.env.MEMORY_FILE_PATH ?? `${process.env.HOME}/.claude/memory.json`

function now(): string {
  return new Date().toISOString().split("T")[0] // YYYY-MM-DD
}

function loadGraph(): Graph {
  if (!existsSync(MEMORY_FILE)) return { entities: [], relations: [] }

  const raw = readFileSync(MEMORY_FILE, "utf-8").trim()
  if (!raw) return { entities: [], relations: [] }

  // Detect standard JSON format (migration from old server format)
  // Standard JSON starts with `{` and has "entities"/"relations" keys
  if (raw.startsWith("{") && !raw.includes("\n{")) {
    const parsed = JSON.parse(raw)
    if (parsed.entities || parsed.relations) {
      const graph: Graph = {
        entities: (parsed.entities ?? []).map((e: any) => ({ ...e, last_seen: e.last_seen ?? now() })),
        relations: parsed.relations ?? [],
      }
      saveGraph(graph) // migrate to NDJSON
      return graph
    }
  }

  // NDJSON: replace newlines with commas, wrap in array, parse
  const items: any[] = JSON.parse("[" + raw.replace(/\r?\n/g, ",") + "]")
  const entities: Entity[] = []
  const relations: Relation[] = []
  for (const obj of items) {
    if (obj.type === "entity") {
      entities.push({
        name: obj.name,
        entityType: obj.entityType,
        observations: obj.observations ?? [],
        last_seen: obj.last_seen ?? now(),
      })
    } else if (obj.type === "relation") {
      relations.push({ from: obj.from, to: obj.to, relationType: obj.relationType })
    }
  }
  return { entities, relations }
}

function saveGraph(graph: Graph): void {
  const lines = [
    ...graph.entities.map(e => JSON.stringify({ type: "entity", name: e.name, entityType: e.entityType, observations: e.observations, last_seen: e.last_seen })),
    ...graph.relations.map(r => JSON.stringify({ type: "relation", from: r.from, to: r.to, relationType: r.relationType })),
  ]
  writeFileSync(MEMORY_FILE, lines.join("\n") + "\n", "utf-8")
}

// ── Graph mutations ────────────────────────────────────────────────────────

function createEntities(input: Omit<Entity, "last_seen">[]): Entity[] {
  const graph = loadGraph()
  const created: Entity[] = []
  for (const e of input) {
    const existing = graph.entities.find(x => x.name === e.name)
    if (existing) {
      // Merge observations, update last_seen
      for (const obs of e.observations) {
        if (!existing.observations.includes(obs)) existing.observations.push(obs)
      }
      existing.last_seen = now()
    } else {
      const entity: Entity = { ...e, last_seen: now() }
      graph.entities.push(entity)
      created.push(entity)
    }
  }
  saveGraph(graph)
  return created
}

function createRelations(input: Relation[]): Relation[] {
  const graph = loadGraph()
  const created: Relation[] = []
  for (const r of input) {
    const exists = graph.relations.some(
      x => x.from === r.from && x.to === r.to && x.relationType === r.relationType
    )
    if (!exists) {
      graph.relations.push(r)
      created.push(r)
    }
    // Bump last_seen on the from-entity
    const entity = graph.entities.find(x => x.name === r.from)
    if (entity) entity.last_seen = now()
  }
  saveGraph(graph)
  return created
}

function addObservations(input: { entityName: string; contents: string[] }[]): { entityName: string; addedObservations: string[] }[] {
  const graph = loadGraph()
  const results = []
  for (const { entityName, contents } of input) {
    const entity = graph.entities.find(x => x.name === entityName)
    if (!entity) throw new Error(`Entity "${entityName}" not found`)
    const added = []
    for (const obs of contents) {
      if (!entity.observations.includes(obs)) {
        entity.observations.push(obs)
        added.push(obs)
      }
    }
    entity.last_seen = now()
    results.push({ entityName, addedObservations: added })
  }
  saveGraph(graph)
  return results
}

function deleteEntities(names: string[]): void {
  const graph = loadGraph()
  const nameSet = new Set(names)
  graph.entities = graph.entities.filter(e => !nameSet.has(e.name))
  graph.relations = graph.relations.filter(r => !nameSet.has(r.from) && !nameSet.has(r.to))
  saveGraph(graph)
}

function deleteObservations(input: { entityName: string; observations: string[] }[]): void {
  const graph = loadGraph()
  for (const { entityName, observations } of input) {
    const entity = graph.entities.find(x => x.name === entityName)
    if (entity) {
      const toRemove = new Set(observations)
      entity.observations = entity.observations.filter(o => !toRemove.has(o))
      entity.last_seen = now()
    }
  }
  saveGraph(graph)
}

function deleteRelations(input: Relation[]): void {
  const graph = loadGraph()
  graph.relations = graph.relations.filter(
    r => !input.some(x => x.from === r.from && x.to === r.to && x.relationType === r.relationType)
  )
  saveGraph(graph)
}

function openNodes(names: string[]): Graph {
  const graph = loadGraph()
  const nameSet = new Set(names)
  const entities = graph.entities.filter(e => nameSet.has(e.name))
  const entityNames = new Set(entities.map(e => e.name))
  const relations = graph.relations.filter(r => entityNames.has(r.from) && entityNames.has(r.to))
  return { entities, relations }
}

function searchNodes(query: string): Graph {
  const graph = loadGraph()
  const q = query.toLowerCase()
  const entities = graph.entities.filter(
    e =>
      e.name.toLowerCase().includes(q) ||
      e.entityType.toLowerCase().includes(q) ||
      e.observations.some(o => o.toLowerCase().includes(q))
  )
  const entityNames = new Set(entities.map(e => e.name))
  const relations = graph.relations.filter(r => entityNames.has(r.from) && entityNames.has(r.to))
  return { entities, relations }
}

function graphHealthCheck(staleDays: number): { stale: Entity[]; orphanRelations: Relation[] } {
  const graph = loadGraph()
  const cutoff = new Date()
  cutoff.setDate(cutoff.getDate() - staleDays)
  const stale = graph.entities.filter(e => new Date(e.last_seen) < cutoff)
  const entityNames = new Set(graph.entities.map(e => e.name))
  const orphanRelations = graph.relations.filter(r => !entityNames.has(r.from) || !entityNames.has(r.to))
  return { stale, orphanRelations }
}

function compactGraph(): { removedEntities: number; removedRelations: number } {
  const graph = loadGraph()
  const before = { e: graph.entities.length, r: graph.relations.length }

  // Dedup entities by name (keep last)
  const entityMap = new Map<string, Entity>()
  for (const e of graph.entities) entityMap.set(e.name, e)
  graph.entities = Array.from(entityMap.values())

  // Dedup relations
  const relSeen = new Set<string>()
  graph.relations = graph.relations.filter(r => {
    const key = `${r.from}|${r.to}|${r.relationType}`
    if (relSeen.has(key)) return false
    relSeen.add(key)
    return true
  })

  // Remove orphan relations (entity no longer exists)
  const entityNames = new Set(graph.entities.map(e => e.name))
  graph.relations = graph.relations.filter(r => entityNames.has(r.from) && entityNames.has(r.to))

  saveGraph(graph)
  return {
    removedEntities: before.e - graph.entities.length,
    removedRelations: before.r - graph.relations.length,
  }
}

// ── MCP Server ─────────────────────────────────────────────────────────────

const server = new Server(
  { name: "laura-memory", version: "1.0.0" },
  { capabilities: { tools: {} } }
)

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "create_entities",
      description: "Create new entities in the knowledge graph. Existing entities get observations merged and last_seen updated.",
      inputSchema: {
        type: "object",
        properties: {
          entities: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                entityType: { type: "string" },
                observations: { type: "array", items: { type: "string" } },
              },
              required: ["name", "entityType", "observations"],
            },
          },
        },
        required: ["entities"],
      },
    },
    {
      name: "create_relations",
      description: "Create relations between entities. Duplicates are ignored. Updates last_seen on the from-entity.",
      inputSchema: {
        type: "object",
        properties: {
          relations: {
            type: "array",
            items: {
              type: "object",
              properties: {
                from: { type: "string" },
                to: { type: "string" },
                relationType: { type: "string" },
              },
              required: ["from", "to", "relationType"],
            },
          },
        },
        required: ["relations"],
      },
    },
    {
      name: "add_observations",
      description: "Add observations to existing entities. Updates last_seen.",
      inputSchema: {
        type: "object",
        properties: {
          observations: {
            type: "array",
            items: {
              type: "object",
              properties: {
                entityName: { type: "string" },
                contents: { type: "array", items: { type: "string" } },
              },
              required: ["entityName", "contents"],
            },
          },
        },
        required: ["observations"],
      },
    },
    {
      name: "delete_entities",
      description: "Delete entities and their associated relations from the graph.",
      inputSchema: {
        type: "object",
        properties: {
          entityNames: { type: "array", items: { type: "string" } },
        },
        required: ["entityNames"],
      },
    },
    {
      name: "delete_observations",
      description: "Remove specific observations from entities.",
      inputSchema: {
        type: "object",
        properties: {
          deletions: {
            type: "array",
            items: {
              type: "object",
              properties: {
                entityName: { type: "string" },
                observations: { type: "array", items: { type: "string" } },
              },
              required: ["entityName", "observations"],
            },
          },
        },
        required: ["deletions"],
      },
    },
    {
      name: "delete_relations",
      description: "Delete specific relations from the graph.",
      inputSchema: {
        type: "object",
        properties: {
          relations: {
            type: "array",
            items: {
              type: "object",
              properties: {
                from: { type: "string" },
                to: { type: "string" },
                relationType: { type: "string" },
              },
              required: ["from", "to", "relationType"],
            },
          },
        },
        required: ["relations"],
      },
    },
    {
      name: "open_nodes",
      description: "Retrieve specific entities and the relations between them by name.",
      inputSchema: {
        type: "object",
        properties: {
          names: { type: "array", items: { type: "string" } },
        },
        required: ["names"],
      },
    },
    {
      name: "search_nodes",
      description: "Search entities by name, type, or observation content (case-insensitive substring match).",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string" },
        },
        required: ["query"],
      },
    },
    {
      name: "read_graph",
      description: "Return the entire knowledge graph. Use sparingly — prefer open_nodes or search_nodes.",
      inputSchema: { type: "object", properties: {} },
    },
    {
      name: "graph_health_check",
      description: "List entities not updated in N days, and orphan relations. Use before compact_graph to review what will be cleaned.",
      inputSchema: {
        type: "object",
        properties: {
          stale_days: {
            type: "number",
            description: "Entities with last_seen older than this many days are flagged as stale. Default: 30.",
          },
        },
      },
    },
    {
      name: "compact_graph",
      description: "Deduplicate entities and relations, remove orphan relations. Returns counts of removed items.",
      inputSchema: { type: "object", properties: {} },
    },
  ],
}))

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const { name, arguments: args } = req.params

  try {
    switch (name) {
      case "create_entities": {
        const created = createEntities(args!.entities as Omit<Entity, "last_seen">[])
        return { content: [{ type: "text", text: JSON.stringify(created, null, 2) }] }
      }
      case "create_relations": {
        const created = createRelations(args!.relations as Relation[])
        return { content: [{ type: "text", text: JSON.stringify(created, null, 2) }] }
      }
      case "add_observations": {
        const results = addObservations(args!.observations as { entityName: string; contents: string[] }[])
        return { content: [{ type: "text", text: JSON.stringify(results, null, 2) }] }
      }
      case "delete_entities": {
        deleteEntities(args!.entityNames as string[])
        return { content: [{ type: "text", text: "Entities deleted." }] }
      }
      case "delete_observations": {
        deleteObservations(args!.deletions as { entityName: string; observations: string[] }[])
        return { content: [{ type: "text", text: "Observations deleted." }] }
      }
      case "delete_relations": {
        deleteRelations(args!.relations as Relation[])
        return { content: [{ type: "text", text: "Relations deleted." }] }
      }
      case "open_nodes": {
        const result = openNodes(args!.names as string[])
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] }
      }
      case "search_nodes": {
        const result = searchNodes(args!.query as string)
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] }
      }
      case "read_graph": {
        const graph = loadGraph()
        return { content: [{ type: "text", text: JSON.stringify(graph, null, 2) }] }
      }
      case "graph_health_check": {
        const staleDays = (args?.stale_days as number) ?? 30
        const result = graphHealthCheck(staleDays)
        const summary = {
          stale_days_threshold: staleDays,
          stale_entity_count: result.stale.length,
          orphan_relation_count: result.orphanRelations.length,
          stale_entities: result.stale.map(e => ({ name: e.name, entityType: e.entityType, last_seen: e.last_seen })),
          orphan_relations: result.orphanRelations,
        }
        return { content: [{ type: "text", text: JSON.stringify(summary, null, 2) }] }
      }
      case "compact_graph": {
        const result = compactGraph()
        return { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] }
      }
      default:
        throw new Error(`Unknown tool: ${name}`)
    }
  } catch (err) {
    return {
      content: [{ type: "text", text: `Error: ${(err as Error).message}` }],
      isError: true,
    }
  }
})

const transport = new StdioServerTransport()
await server.connect(transport)
