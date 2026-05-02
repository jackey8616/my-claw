# Case Study: `agent-browser` Discovery Failure in Docker

## Problem
`agent-browser` reported `Auto-launch failed: Chrome not found` in Docker despite `chrome-headless-shell` being installed via Playwright.

## Root Cause
The tool utilized a rigid "fingerprint matching" strategy. It looked for folders named `chromium-XXXX` and binaries named `chrome`. The official Docker image provided `chromium_headless_shell-XXXX` and `headless_shell`, causing a total mismatch.

## Solution
Instead of mimicking the fingerprint via symlinks (which is fragile), the fix implemented dynamic discovery in `entrypoint.sh`:
1. Scanning `$PLAYWRIGHT_BROWSERS_PATH` for any executable file matching `chrome|chromium`.
2. Exporting the result to `AGENT_BROWSER_EXECUTABLE_PATH`.

This bypasses the internal discovery logic and ensures compatibility across Playwright versions.

## Verification Command
```bash
# Manually verify by forcing the path
node_modules/.bin/agent-browser open <url> --executable-path /opt/hermes/.playwright/chromium_headless_shell-XXXX/chrome-linux/headless_shell
```
