---
name: playwright-automation
description: End-to-end web automation and testing using Playwright (npm/npx or Python).
tags: [automation, playwright, testing, web-scraping]
---

# Playwright Automation

This skill governs the process of automating web browsers for testing, data extraction, or interaction using Playwright.

## Trigger Conditions
- User asks to "test a website", "automate a browser", or "use Playwright".
- Tasks requiring interaction with dynamic JS-heavy websites (SPAs).
- End-to-end (E2E) testing of web flows.

## Workflow

### 1. Environment Setup
Depending on the environment, choose the appropriate installation path:
- **Node.js (Prefered for rapid prototyping):**
    - Use `npx playwright install chromium` to download browser binaries.
    - **Pitfall:** In constrained environments (like containers/VMs), `npx playwright install --with-deps` may fail if `sudo` is unavailable. Try installing only the binaries first.
- **Python:**
    - `pip install playwright` followed by `playwright install chromium`.
    - Ensure a virtual environment is used if system pip is unavailable.

### 2. Browser Interaction
When using built-in `browser_*` tools:
- **Navigation:** Use `browser_navigate(url=...)` to reach the target page.
- **Inspection:** Use `browser_snapshot()` to get the current DOM state/accessibility tree.
- **Action:** Use `browser_click(element_ref=...)` or `browser_type(element_ref=..., text=...)`.

### 3. Scripting (for durable tests)
When writing standalone scripts:
- Use `chromium.launch(headless=True)` for CI/CD or `headless=False` for debugging.
- Use `page.wait_for_selector()` to handle asynchronous loading.
- Use `page.screenshot()` to document failures.

## Pitfalls & Lessons Learned
- **Dependency Hell:** If `npx playwright install` fails with permission errors, the environment likely lacks the necessary system libraries (glibc, libgbm, etc.) and requires root access for `--with-deps`.
- **Tool Availability:** If `pip` is missing in a Python environment, try `python3 -m pip` or check for `python3-venv`.
- **Bot Detection:** Some sites block headless browsers. Use stealth plugins or residential proxies if `browser_navigate` returns 403/Cloudflare challenges.
- **Timeouts:** Large browser binary downloads can timeout in limited-bandwidth environments. Be prepared to retry or use pre-installed agents (e.g., `agent-browser`).

## Verification
- [ ] Browser launches without "Missing Dependency" errors.
- [ ] Target URL is reachable and content is rendered.
- [ ] Interactive elements (buttons, inputs) respond to events.
