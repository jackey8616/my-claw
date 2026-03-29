# OpenClaw Hooks

This directory contains custom hooks for OpenClaw automation.

Hooks are event-driven scripts that run when specific events occur (e.g., `/new`, `/reset`, `/stop` commands).

## Available Hooks

### session-shutdown

Triggered on `/reset` and `/stop` commands to:
- Archive session context
- Generate session summaries
- Update daily notes and memory
- Sync changes to Git

**Status:** Under development

## Hook Structure

Each hook is a directory containing:

```
<hook-name>/
├── HOOK.md        # Hook metadata and documentation
└── handler.ts     # Handler implementation (TypeScript)
```

### HOOK.md Format

```markdown
---
name: my-hook
description: "Short description"
metadata:
  { "openclaw": { "emoji": "🎯", "events": ["command:new"] } }
---

# My Hook

Description and documentation...
```

- **name**: Hook identifier (used with `openclaw hooks enable <name>`)
- **description**: One-line summary
- **events**: Array of events to listen for (e.g., `command:new`, `command:reset`, `command:stop`)

Common events:
- `command:new` — When `/new` is issued
- `command:reset` — When `/reset` is issued
- `command:stop` — When `/stop` is issued
- `gateway:startup` — When gateway starts
- `message:received` — When a message is received

See [OpenClaw Hooks Documentation](https://docs.openclaw.ai/automation/hooks) for full event reference.

### handler.ts Format

```typescript
const handler = async (event) => {
  // Only trigger on specific events
  if (event.type !== "command" || event.action !== "reset") {
    return;
  }

  // Your logic here
  console.log("[my-hook] Triggered");

  // Send messages to user (optional)
  event.messages.push("✨ Hook executed!");
};

export default handler;
```

**Event Context:**
- `event.type`: Event type ("command", "session", "message", "gateway", etc.)
- `event.action`: Event action ("new", "reset", "stop", "received", etc.)
- `event.sessionKey`: Current session identifier
- `event.timestamp`: When event occurred
- `event.messages`: Array to push messages back to user
- `event.context`: Additional context (varies by event type)

## Setup

### 1. Enable a Hook

After deploying a new hook to this directory:

```bash
openclaw hooks enable <hook-name>
```

### 2. Restart Gateway

Hooks are loaded at startup. Restart to activate:

```bash
docker compose restart openclaw
```

Or from inside the container:

```bash
docker compose exec openclaw-app openclaw hooks enable <hook-name>
docker compose restart openclaw
```

### 3. Verify

List all hooks:

```bash
docker compose exec openclaw-app openclaw hooks list --verbose
```

You should see your hook with a checkmark (✓):

```
Hooks (2/2 ready)

Ready:
  🎯 my-hook ✓ - Short description
  💾 session-memory ✓ - Save session context to memory
```

## Development Guide

### Create a New Hook

1. Create a directory:
   ```bash
   mkdir -p openclaw/hooks/my-hook
   ```

2. Write `HOOK.md`:
   ```markdown
   ---
   name: my-hook
   description: "What this hook does"
   metadata: { "openclaw": { "emoji": "🎯", "events": ["command:new"] } }
   ---

   # My Hook

   Detailed documentation...
   ```

3. Write `handler.ts`:
   ```typescript
   const handler = async (event) => {
     if (event.type !== "command" || event.action !== "new") {
       return;
     }

     console.log("[my-hook] Hook triggered");
     event.messages.push("✨ Done!");
   };

   export default handler;
   ```

4. Enable and test:
   ```bash
   openclaw hooks enable my-hook
   docker compose restart openclaw
   ```

5. Commit to Git:
   ```bash
   git add openclaw/hooks/my-hook/
   git commit -m "feat: add my-hook"
   git push origin feat/my-hook-name
   # Open PR for review
   ```

### Best Practices

- **Keep handlers fast** — Hook execution blocks command processing. Don't do slow work synchronously.
- **Handle errors gracefully** — Always wrap risky operations in try-catch.
- **Filter events early** — Return immediately if event isn't relevant.
- **Be specific with events** — Use `command:reset` instead of `command` for better performance.
- **Log clearly** — Use `console.log("[hook-name] message")` for debugging.

### Debugging

Monitor gateway logs:

```bash
docker compose logs -f openclaw
```

Or check hook eligibility:

```bash
docker compose exec openclaw-app openclaw hooks info my-hook
```

## Related Documentation

- [OpenClaw Hooks Docs](https://docs.openclaw.ai/automation/hooks) — Full reference
- [OpenClaw Events](https://docs.openclaw.ai/automation/hooks#event-types) — All available events
- [Session Memory Hook](https://docs.openclaw.ai/automation/hooks#session-memory) — Example bundled hook
