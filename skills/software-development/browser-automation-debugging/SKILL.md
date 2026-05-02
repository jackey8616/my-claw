---
name: browser-automation-debugging
description: Debugging and resolving issues with browser-based automation tools (Playwright, Puppeteer, agent-browser) particularly in constrained environments like Docker.
---

# Browser Automation Debugging

This skill provides a systematic approach to diagnosing why browser automation tools fail to launch or interact with pages, with a focus on environment-specific failures (Docker, CI, Headless).

## Diagnostic Workflow

When a browser tool fails to launch (e.g., "Chrome not found"), follow this sequence:

1. **Detect Path Failure**: Check if the tool is looking in the wrong place.
   - List the directories the tool is searching.
   - Verify if the binary exists but is being ignored.
2. **Isolate Binary Compatibility**: Determine if the binary present is compatible with the launcher.
   - Many launchers require "Full Chrome" and will explicitly ignore `chrome-headless-shell`.
3. **Force Execution**: Use a direct path override (e.g., `--executable-path`) to bypass auto-detection.
   - If the binary fails even with a direct path, the issue is **Binary Compatibility/Dependencies**.
   - If it works, the issue is **Auto-detection/Path Configuration**.
4. **Dependency Verification**: Check for missing `.so` libraries (e.g., `libnss3`, `libatk`) using `ldd` on the binary.

## Common Pitfalls & Solutions

### Docker Environment Mismatches
- **Problem**: Dockerfiles installing `chrome-headless-shell` via `--only-shell` to save space.
- **Symptom**: Launcher reports "Chrome not found" despite Playwright being installed.
- **Solution**: Install a full Chrome binary or modify the launcher to accept the headless shell.

### Permission Errors in Volumes
- **Problem**: Browser caches located in volumes (e.g., `/opt/data/.agent-browser`) created as root.
- **Solution**: Ensure `chown -R` is performed for the agent user before the tool attempts installation.

## References
- See `references/hermes-agent-docker-browser.md` for the specific `agent-browser` and `chrome-headless-shell` mismatch case.
