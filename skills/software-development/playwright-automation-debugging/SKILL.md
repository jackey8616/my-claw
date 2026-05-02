---
name: playwright-automation-debugging
description: Skills for orchestrating, debugging, and deploying Playwright/browser-based automation, specifically within constrained environments like Docker.
---

# Playwright Browser Automation & Debugging

Skills for orchestrating, debugging, and deploying Playwright/browser-based automation, specifically within constrained environments like Docker.

## Trigger Conditions
- Tasks involving `playwright`, `puppeteer`, or `agent-browser`.
- Debugging "Chrome not found" or "Auto-launch failed" errors.
- Configuring browser automation inside Docker containers.
- Implementing custom browser discovery or launcher logic.

## Core Workflow

### 1. Environment Verification
Before assuming a binary is missing, verify the actual filesystem state:
- **Check for Headless Shell**: Search for `chrome-headless-shell` or `headless_shell` in the Playwright cache.
- **Check Permissions**: Ensure the user running the agent has execute permissions on the binary.
- **Test Manual Launch**: Use `--executable-path` to bypass automatic discovery and verify the binary actually works.

### 2. Debugging Discovery Failures
If `agent-browser` fails to find a present browser, analyze the "Discovery Fingerprint":
- **Fingerprint Matching**: Be aware that some launchers (like `agent-browser`) use rigid path matching (e.g., expecting `/chromium-XXXX/chrome-linux64/chrome`) and will ignore `chromium_headless_shell-XXXX/chrome-linux/headless_shell`.
- **Path Mimicking**: If the launcher is immutable, use symbolic links to satisfy the expected fingerprint.

### 3. Docker Deployment Strategy (Robust Pattern)
To avoid "Path Fragility" where version updates break hardcoded paths:
- **Avoid Hardcoding**: Never hardcode version numbers (e.g., `1217`) in config files.
- **Dynamic Discovery**: Use a shell script in the `entrypoint.sh` to locate the binary at runtime.
- **Environment Variable Injection**: Export the discovered path to a recognized variable (e.g., `AGENT_BROWSER_EXECUTABLE_PATH`) before dropping root.

## Pitfalls & Lessons Learned
- **Full Chrome vs. Headless Shell**: An installation of `chrome-headless-shell` (via `--only-shell`) is NOT the same as a full Chromium install. Some launchers require the full binary.
- **Directory vs. File**: `Permission denied (os error 13)` often occurs when a tool is pointed at a directory instead of the actual binary executable.
- **Sudo/Root Blocks**: `npx playwright install --with-deps` often fails in non-privileged containers because it attempts to install system libraries via `apt`. Install dependencies in the Dockerfile build stage instead.

## Verification Steps
- [ ] Run `docker exec <id> sh -c 'echo $BROWSER_VAR'` to verify environment injection.
- [ ] Run `agent-browser open <url>` without flags to verify automatic discovery.
- [ ] Confirm the binary is executable (`chmod +x`).
