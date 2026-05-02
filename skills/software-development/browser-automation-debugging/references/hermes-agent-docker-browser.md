# Case Study: agent-browser vs. chrome-headless-shell in Docker

## Problem
In `nousresearch/hermes-agent` Docker images, browser tools report `Auto-launch failed: Chrome not found` despite Playwright being installed.

## Root Cause
The Dockerfile uses `npx playwright install --with-deps chromium --only-shell`, which installs `chrome-headless-shell`. 
`agent-browser` is designed to find and launch a **full Chrome binary**. It explicitly does not recognize the `chrome-headless-shell` binary, even when it is located in the standard Playwright browser cache.

## Evidence/Reproduction
- `agent-browser open <url>` $\rightarrow$ Fails with `Chrome not found`.
- `agent-browser open <url> --executable-path <path_to_headless_shell>` $\rightarrow$ Tests if the shell is functionally compatible with the tool's requirements.

## Resolution
To resolve this in a Docker image:
1. Remove `--only-shell` from the Playwright installation command.
2. Or, explicitly run `agent-browser install` during the build process.
3. Or, manually run `agent-browser install` as the `hermes` user after container startup (requires write access to `/opt/data/.agent-browser`).
