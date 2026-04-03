#!/bin/bash
# daily-summary.sh — Walk all session logs for a given day, generate a
# consolidated daily summary, and write it to the Daily Note via JSON + placeholder replace.
#
# Usage: bash daily-summary.sh [YYYY-MM-DD]
# Default date: today in local TZ ($TZ env var or UTC).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
DATE="${1:-$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')}"
MONTH="$(echo "$DATE" | cut -c1-7)"
TIMESTAMP=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d %H:%M %Z')

VAULT_DIR="$HOME/vault"
RELATIVE_SESSION_LOGS_DIR="01-Session-Logs/$DATE"
SESSION_LOGS_DIR="$VAULT_DIR/$RELATIVE_SESSION_LOGS_DIR"
DAILY_DIR="$VAULT_DIR/02-Daily-Notes/$MONTH"
DAILY_TEMPLATE_PATH="$VAULT_DIR/templates/DAILY-NOTE.md"

HOOK_SETTINGS='{"disableAllHooks": true}'
LOGFILE="/tmp/daily-summary-debug.log"

# Load .env
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi

# Ensure claude is in PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

DISCORD_CHANNEL_ID="1486128557444042883"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
err()  { log "ERROR: $*"; echo "ERROR: $*" >&2; }
die()  { err "$*"; discord_send "❌ Daily summary failed: $*"; exit 1; }

discord_send() {
  local msg="$1"
  [ -z "${DISCORD_BOT_TOKEN:-}" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# Safely read a string field from JSON; fallback to $2 if missing/null
jq_str() { echo "$RAW_JSON" | jq -r "$1 // empty" 2>/dev/null || echo "${2:-（無資料）}"; }

# Replace a single-line placeholder in $RENDERED (in-place via temp var)
# Usage: replace_line "{{placeholder}}" "replacement"
replace_line() {
  local ph="$1" val="$2"
  # Escape & for sed replacement string
  local escaped_val
  escaped_val=$(printf '%s' "$val" | sed 's/[&/\]/\\&/g; s/$/\\/')
  escaped_val="${escaped_val%?}"  # strip trailing backslash added by last line
  RENDERED=$(printf '%s' "$RENDERED" | sed "s|${ph}|${escaped_val}|g")
}

# Replace a placeholder line with a potentially multi-line block using awk
replace_block() {
  local ph="$1" val="$2"
  RENDERED=$(awk -v ph="$ph" -v rep="$val" '
    index($0, ph) { print rep; next }
    { print }
  ' <<< "$RENDERED")
}

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
DAILY_NOTE="$DAILY_DIR/$DATE.md"
log "=== Daily summary start: $DATE ==="
[ -f "$DAILY_TEMPLATE_PATH" ] || die "Daily template not found at '$DAILY_TEMPLATE_PATH'"

# ---------------------------------------------------------------------------
# Collect session logs
# ---------------------------------------------------------------------------
mapfile -t SESSION_FILES < <(ls "$SESSION_LOGS_DIR/${DATE}_"*.md 2>/dev/null || true)
COUNT=${#SESSION_FILES[@]}

if [ "$COUNT" -eq 0 ]; then
  log "No session logs found for $DATE — exiting."
  exit 0
fi

log "Found $COUNT session log(s)."

# ---------------------------------------------------------------------------
# Build inputs for Claude
# ---------------------------------------------------------------------------
SESSION_PATHS_YAML=""   # for frontmatter sessions: list
COMBINED=""             # raw session log content fed to Claude

for f in "${SESSION_FILES[@]}"; do
  rel_path="${f#$VAULT_DIR/}"
  slug="$(basename "$f" .md)"
  SESSION_PATHS_YAML+="  - ${rel_path}"$'\n'
  COMBINED+="### ${slug}  (path: ${rel_path})"$'\n\n'
  COMBINED+="$(cat "$f")"$'\n\n---\n\n'
done

COMBINED="${COMBINED:0:60000}"

# ---------------------------------------------------------------------------
# Ask Claude to produce ONLY a JSON data object — no markdown, no prose
# ---------------------------------------------------------------------------
log "Calling Claude to generate JSON data..."

RAW_JSON=$(printf '%s' "$COMBINED" | cd /tmp && claude -p \
"你是個人知識助理。根據以下 ${COUNT} 個 session logs（日期：${DATE}），萃取摘要資料。

只輸出一個合法的 JSON 物件，不要任何說明、開場白或 markdown 代碼區塊。

JSON schema（所有值皆為字串，除非特別標示）：
{
  \"tags\": [\"tag1\", \"tag2\"],          // 2-5 個小寫英文加連字號
  \"summary\": \"...\",                    // 一句話摘要，20 字以內
  \"overview\": \"...\",                   // 2-4 句整體回顧，說明學了什麼、做了什麼、有哪些未竟之事
  \"knowledge_gained\": \"...\",           // 條列已學習知識，每條「- **主題**：說明」，多條以換行分隔
  \"knowledge_shallow\": \"...\",          // 條列今日出現但未深入的主題；若無寫「今日無此類主題。」
  \"todos_incomplete\": \"...\",           // 條列未完成待辦；若全部完成寫「今日無未完成待辦。」
  \"best_insights\": \"...\",             // 最值得保留的靈感前3條，條列；若無寫「今日無靈感記錄。」
  \"reflection\": \"...\",                // 思維突破或連結 + 明日最重要一件事；若無寫「今日無特別反思。」
  \"sessions\": [                         // 每個 session 一個物件
    {
      \"slug\": \"...\",                  // session 檔名去掉 .md
      \"rel_path\": \"...\",              // vault-root 相對路徑
      \"title\": \"...\",                 // session frontmatter title
      \"summary_line\": \"...\"           // 一句話摘要
    }
  ]
}

Session Logs:
${COMBINED}" \
  --settings "$HOOK_SETTINGS" --dangerously-skip-permissions --model claude-haiku-4-5 2>/dev/null)

[ -n "$RAW_JSON" ] || die "Claude returned empty output"

# Strip accidental markdown fences if model misbehaves
RAW_JSON=$(echo "$RAW_JSON" | sed 's/^```json//; s/^```//' | sed '/^```/d')

# Validate JSON
echo "$RAW_JSON" | jq empty 2>/dev/null || die "Claude returned invalid JSON: ${RAW_JSON:0:200}"

log "JSON received (${#RAW_JSON} chars)."

# ---------------------------------------------------------------------------
# Extract fields from JSON
# ---------------------------------------------------------------------------
F_SUMMARY=$(jq_str '.summary')
F_OVERVIEW=$(jq_str '.overview')
F_KNOWLEDGE_GAINED=$(jq_str '.knowledge_gained')
F_KNOWLEDGE_SHALLOW=$(jq_str '.knowledge_shallow')
F_TODOS=$(jq_str '.todos_incomplete')
F_INSIGHTS=$(jq_str '.best_insights')
F_REFLECTION=$(jq_str '.reflection')

# Build tags YAML lines
F_TAGS_YAML=$(echo "$RAW_JSON" | jq -r '.tags[]? | "  - " + .' 2>/dev/null || echo "  - daily")

# Build sessions frontmatter YAML (use known paths, not Claude's output)
F_SESSIONS_YAML="$SESSION_PATHS_YAML"

# ---------------------------------------------------------------------------
# Render template — replace each placeholder
# ---------------------------------------------------------------------------
RENDERED=$(cat "$DAILY_TEMPLATE_PATH")

# --- frontmatter single-line fields ---
replace_line "{{YYYY-MM-DD}}"  "$DATE"
replace_line "{{ 摘要 }}"      "$F_SUMMARY"

# --- frontmatter multi-line blocks (tags / sessions) ---
# Replace the entire tags block ({{tag-1}} line and any following {{tag-N}} lines)
replace_block "{{tag-1}}" "$F_TAGS_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{tag-')

# Replace sessions block
replace_block "{{session-log-1-path}}" "$F_SESSIONS_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{session-log-')

# --- body section placeholders ---
replace_block "{{今日整體回顧：學了什麼、做了什麼、有哪些未竟之事}}" "$F_OVERVIEW"
replace_block "{{已學習知識條目列表（從 SessionLog 彙整）}}"         "$F_KNOWLEDGE_GAINED"
replace_block "{{今日出現但尚未深入的主題}}"                         "$F_KNOWLEDGE_SHALLOW"
replace_block "{{未完成的待辦（跨 session 彙整）}}"                  "$F_TODOS"
replace_block "{{今日最值得保留的靈感（前3條）}}"                    "$F_INSIGHTS"
replace_block "{{今日有哪些思維上的突破或連結？}}"                   "$F_REFLECTION"
replace_block "{{明日最重要的一件事是什麼？}}"                       ""

# session list block
replace_block "{{session-log-1 summary}}" ""
replace_block "{{session-log-2 summary}}" ""

# Append generation footer
RENDERED+=$'\n\n---\n'
RENDERED+="_Generated: ${TIMESTAMP} — ${COUNT} session(s)_"

# ---------------------------------------------------------------------------
# Write daily note (idempotent)
# ---------------------------------------------------------------------------
if [ -f "$DAILY_NOTE" ] && grep -q "^date: $DATE" "$DAILY_NOTE"; then
  log "Daily note for $DATE already exists — skipping write."
else
  mkdir -p "$DAILY_DIR"
  printf '%s\n' "$RENDERED" > "$DAILY_NOTE"
  log "Written daily note: $DAILY_NOTE"
fi

# ---------------------------------------------------------------------------
# Discord notification
# ---------------------------------------------------------------------------
OVERVIEW_SHORT=$(echo "$F_OVERVIEW" | head -2)
discord_send "📅 **Daily Summary — ${DATE}**（${COUNT} sessions）

${OVERVIEW_SHORT}

詳細內容已寫入 Daily Note。"

log "=== Done ==="
