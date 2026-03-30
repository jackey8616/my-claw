# Hooks Setup Guide

This guide covers enabling and testing hooks after deployment.

## Post-Deployment Setup

After running `setup-new-vps.sh` or pulling new hooks, follow these steps to activate them.

### 1. Enable Hooks

For each hook in this directory, enable it:

```bash
# Enable a specific hook
docker compose exec openclaw-app openclaw hooks enable <hook-name>

# Examples
docker compose exec openclaw-app openclaw hooks enable session-shutdown
```

### 2. Restart Gateway

Hooks are loaded at startup. Restart to activate:

```bash
docker compose restart openclaw
```

### 3. Verify Hooks Are Loaded

List all discovered hooks with their status:

```bash
docker compose exec openclaw-app openclaw hooks list --verbose
```

You should see output like:

```
Hooks (3/3 ready)

Ready:
  💾 session-memory ✓ - Save session context to memory when /new or /reset
  🎯 session-shutdown ✓ - Archive sessions and update memory on reset/stop
  📝 command-logger ✓ - Log all command events to a centralized audit file
```

### 4. Check Individual Hook Info

If a hook isn't showing as ready, inspect why:

```bash
docker compose exec openclaw-app openclaw hooks info session-shutdown
```

This will show requirements, eligibility, and any missing dependencies.

### 5. Monitor Hook Execution

Watch gateway logs to see hooks running:

```bash
docker compose logs -f openclaw | grep -i hook
```

Or check the full logs:

```bash
docker compose logs -f openclaw
```

## Known Hooks

### session-shutdown

**Status:** Under development

**Triggered:** `/reset` and `/stop` commands

**Purpose:** Archive sessions, generate summaries, update memory, sync Git

**Enable:**
```bash
docker compose exec openclaw-app openclaw hooks enable session-shutdown
docker compose restart openclaw
```

## Troubleshooting

### Hook not appearing in `hooks list`

1. Verify the hook directory exists:
   ```bash
   ls -la openclaw/hooks/
   ```

2. Check the `HOOK.md` file has correct metadata:
   ```bash
   cat openclaw/hooks/<hook-name>/HOOK.md
   ```

3. Restart gateway and try again:
   ```bash
   docker compose restart openclaw
   docker compose exec openclaw-app openclaw hooks list --verbose
   ```

### Hook shows as ready but not triggering

1. Check if it's actually enabled:
   ```bash
   docker compose exec openclaw-app openclaw hooks list --verbose
   ```
   Look for a checkmark (✓) next to the hook name.

2. If not enabled, enable it:
   ```bash
   docker compose exec openclaw-app openclaw hooks enable session-shutdown
   docker compose restart openclaw
   ```

3. Monitor logs while triggering the event:
   ```bash
   docker compose logs -f openclaw &
   # Then trigger the event (e.g., send /reset command)
   ```

### Handler.ts syntax errors

If the handler has TypeScript errors, the hook won't load. Check gateway logs:

```bash
docker compose logs openclaw | grep -A5 "session-shutdown"
```

Fix the error in `handler.ts` and restart.

## Development Workflow

When developing a new hook:

1. Create the hook in `openclaw/hooks/<hook-name>/`
2. Write `HOOK.md` and `handler.ts`
3. Enable it: `openclaw hooks enable <hook-name>`
4. Restart: `docker compose restart openclaw`
5. Test by triggering the event
6. Monitor logs: `docker compose logs -f openclaw`
7. Commit to Git when ready

See `README.md` for full development guide.
