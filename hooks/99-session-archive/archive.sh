#!/bin/bash
# Session archiver — generates session log and updates daily note.
# Strategy: Claude produces JSON data only; script does all placeholder replacement.

set -euo pipefail

MONTH=$(TZ="${TZ:-UTC}" date '+%Y-%m')
DATE=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')

VAULT_DIR="$HOME/vault"
RELATIVE_SESSION_LOGS_DIR="01-Session-Logs/$DATE"
SESSION_LOGS_DIR="$VAULT_DIR/$RELATIVE_SESSION_LOGS_DIR"
DAILY_DIR="$VAULT_DIR/02-Daily-Notes/$MONTH"
SESSION_TEMPLATE_PATH="$VAULT_DIR/templates/SESSION-LOG.md"
DAILY_TEMPLATE_PATH="$VAULT_DIR/templates/DAILY-NOTE.md"

TRANSCRIPT_PATH="${1:-}"
TIME_START=$(TZ="${TZ:-UTC}" date '+%H:%M')
DAILY_NOTE="$DAILY_DIR/$DATE.md"

HOOK_SETTINGS='{"disableAllHooks": true}'
LOGFILE="/tmp/session-archiver-debug.log"

ENV_FILE="$(dirname "$0")/../../.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }
DISCORD_CHANNEL_ID="1486128557444042883"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
err()  { log "ERROR: $*"; echo "ERROR: $*" >&2; }
die()  { err "$*"; discord_notify "❌ Session archive failed: $*"; exit 1; }

discord_notify() {
  local msg="$1"
  [ -z "${DISCORD_BOT_TOKEN:-}" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# Read a string field from $RAW_JSON; fallback to $2
jq_str() { echo "$RAW_JSON" | jq -r "$1 // empty" 2>/dev/null || echo "${2:-（無資料）}"; }

# Replace a single-line placeholder in $RENDERED
replace_line() {
  local ph="$1" val="$2"
  local escaped
  escaped=$(printf '%s' "$val" | sed 's/[&/\]/\\&/g; s/$/\\/')
  escaped="${escaped%?}"
  RENDERED=$(printf '%s' "$RENDERED" | sed "s|${ph}|${escaped}|g")
}

# Replace a placeholder line with a potentially multi-line block
replace_block() {
  local ph="$1" val="$2"
  RENDERED=$(awk -v ph="$ph" -v rep="$val" '
    index($0, ph) { print rep; next }
    { print }
  ' <<< "$RENDERED")
}

# ---------------------------------------------------------------------------
# Validate templates
# ---------------------------------------------------------------------------
[ -f "$SESSION_TEMPLATE_PATH" ] || die "Session template not found at '$SESSION_TEMPLATE_PATH'"
[ -f "$DAILY_TEMPLATE_PATH"   ] || die "Daily template not found at '$DAILY_TEMPLATE_PATH'"

# ---------------------------------------------------------------------------
# Validate & parse transcript
# ---------------------------------------------------------------------------
[ -n "$TRANSCRIPT_PATH" ] || die "No transcript path provided. Usage: $0 <transcript_path>"
[ -f "$TRANSCRIPT_PATH" ] || die "Transcript file not found: '$TRANSCRIPT_PATH'"

TRANSCRIPT_TEXT=$(jq -r '
  select(.type == "user" or .type == "assistant") |
  select(.isMeta != true) |
  if .type == "user" then
    if (.message.content | type) == "string" then "【用戶】: \(.message.content)"
    elif (.message.content | type) == "array" then "【用戶】: \([.message.content[] | select(.type == "text") | .text] | join(""))"
    else empty end
  else "【AI】: \([.message.content[]? | select(.type == "text") | .text] | join(""))"
  end
' "$TRANSCRIPT_PATH" 2>/dev/null | head -c 40000)

[ -n "$TRANSCRIPT_TEXT" ] || die "Transcript is empty or unreadable: '$TRANSCRIPT_PATH'"

# ---------------------------------------------------------------------------
# Ask Claude to produce ONLY a JSON data object
# ---------------------------------------------------------------------------
log "Calling Claude to generate JSON data from transcript..."
TIME_END=$(TZ="${TZ:-UTC}" date '+%H:%M')

RAW_JSON=$(printf '%s' "$TRANSCRIPT_TEXT" | cd /tmp && claude -p \
"你是個人知識助理，負責在對話結束後產生 SessionLog 所需的結構化資料。

根據以下對話內容，萃取所有必要欄位。
只輸出一個合法的 JSON 物件，不要任何說明、開場白或 markdown 代碼區塊。

JSON schema（所有值皆為字串，除非特別標示）：
{
  \"title\": \"...\",
  // 動詞開頭，10 字以內的繁體中文主題

  \"tags\": [\"tag1\", \"tag2\"],
  // 2-5 個小寫英文加連字號

  \"summary\": [
    \"第一行：本次對話的核心主題是什麼。\",
    \"第二行：討論了哪些具體概念或問題。\",
    \"第三行：產生了哪些新知識或學習進展。\",
    \"第四行：捕捉到哪些靈感或想法。\",
    \"第五行：記錄了哪些待辦事項。\",
    \"第六行：整合出哪些洞見或結論。\",
    \"第七行：與既有知識的關聯點。\",
    \"第八行：下次建議探索的方向。\"
  ],
  // 嚴格 8 個元素的陣列，每行對應上述面向，不可多也不可少

  \"todos\": [\"- [ ] 待辦一\", \"- [ ] 待辦二\"],
  // 待辦事項陣列；若無則為空陣列 []

  \"knowledge_graph_updates\": [\"- [[節點A]] → [[節點B]]：關係說明\"],
  // 知識關聯陣列；若無則為空陣列 []

  \"overview\": \"...\",
  // 一段自然語言的對話回顧，說明本次對話的脈絡與價值，供快速瀏覽與向量索引

  \"knowledge_body\": \"...\",
  // ## 新知識 段落的完整 markdown 內容
  // 格式：
  // ### 知識標題
  //
  // 說明內容，可多段落。
  //
  // **狀態**：未探索 | 學習中 | 已掌握
  // **分類**：哲學 / 程式 / 心理學 / ...
  // **關聯**：[[節點A]]、[[節點B]]
  //
  // 若本次無新知識，填「本次對話無新增知識。」

  \"insights_body\": \"...\",
  // ## 靈感 段落的完整 markdown 內容
  // 格式：
  // ### 靈感標題或關鍵句
  //
  // 靈感的完整內容，保留原始語感，不過度整理。
  //
  // **背景**：何時產生、當時的討論脈絡
  // **關聯領域**：...
  //
  // 若無靈感，填「本次對話無捕捉到靈感。」

  \"synthesis_body\": \"...\",
  // ## 整合洞見 段落的完整 markdown 內容
  // 格式：
  // - 洞見一：具體說明，有資訊量。
  // - 洞見二：...
  //
  // 若無洞見，填「本次對話無整合洞見。」

  \"todos_body\": \"...\",
  // ## 待辦或成果 段落的完整 markdown 內容
  // 格式：
  // - [ ] 任務 A  \`#high\` \`due: YYYY-MM-DD\`
  // - [ ] 任務 B  \`#medium\`
  //
  // 若無待辦，填「本次對話無新增待辦。」

  \"next_suggestions_body\": \"...\"
  // ## 下次建議 段落的完整 markdown 內容
  // 基於本次內容，建議下次可以探索的 1-3 個方向，條列格式
  // 若無建議，填「本次對話無下次建議。」
}

對話內容：
${TRANSCRIPT_TEXT}" \
  --settings "$HOOK_SETTINGS" --dangerously-skip-permissions --model claude-haiku-4-5 2>/dev/null)

[ -n "$RAW_JSON" ] || die "Claude returned empty output"

# Strip accidental markdown fences
RAW_JSON=$(echo "$RAW_JSON" | sed 's/^```json[[:space:]]*//' | sed 's/^```[[:space:]]*//' | sed '/^```/d')

echo "$RAW_JSON" | jq empty 2>/dev/null || die "Claude returned invalid JSON: ${RAW_JSON:0:300}"

log "JSON received (${#RAW_JSON} chars)."

# ---------------------------------------------------------------------------
# Extract fields
# ---------------------------------------------------------------------------
F_TITLE=$(jq_str '.title' 'Session')
F_OVERVIEW=$(jq_str '.overview')
F_KNOWLEDGE_BODY=$(jq_str '.knowledge_body')
F_INSIGHTS_BODY=$(jq_str '.insights_body')
F_SYNTHESIS_BODY=$(jq_str '.synthesis_body')
F_TODOS_BODY=$(jq_str '.todos_body')
F_NEXT_SUGGESTIONS_BODY=$(jq_str '.next_suggestions_body')

# summary: 8-line array → YAML block scalar lines (indented with 2 spaces for the | block)
F_SUMMARY_YAML=$(echo "$RAW_JSON" | jq -r '.summary[]?' 2>/dev/null \
  | awk '{print "  " $0}' \
  || echo "  （無摘要）")
F_SUMMARY_FIRST=$(echo "$RAW_JSON" | jq -r '.summary[0] // "（無摘要）"' 2>/dev/null)

# tags → YAML list lines
F_TAGS_YAML=$(echo "$RAW_JSON" | jq -r '.tags[]? | "  - " + .' 2>/dev/null || echo "  - session")

# todos frontmatter → YAML list lines
F_TODOS_YAML=$(echo "$RAW_JSON" | jq -r \
  'if (.todos | length) == 0 then "  []"
   else .todos[] | "  " + . end' 2>/dev/null || echo "  []")

# knowledge_graph_updates → YAML list lines
F_KGU_YAML=$(echo "$RAW_JSON" | jq -r \
  'if (.knowledge_graph_updates | length) == 0 then "  []"
   else .knowledge_graph_updates[] | "  " + . end' 2>/dev/null || echo "  []")

# Derive filename from title
F_TITLE_SLUG=$(echo "$F_TITLE" | tr ' ' '-' | tr -cd '[:alnum:]-_')
F_TITLE_SLUG="${F_TITLE_SLUG:-Session}"
LOG_FILENAME="${DATE}_${F_TITLE_SLUG}.md"
LOG_PATH="$SESSION_LOGS_DIR/$LOG_FILENAME"
LOG_REL_PATH="$RELATIVE_SESSION_LOGS_DIR/$LOG_FILENAME"

# ---------------------------------------------------------------------------
# Render session log from template — placeholder replacement
# ---------------------------------------------------------------------------
RENDERED=$(cat "$SESSION_TEMPLATE_PATH")

# --- frontmatter: single-line ---
replace_line "{{title}}" "$F_TITLE"
replace_line "{{date}}"  "$DATE"
replace_line "{{time}}"  "$DATE $TIME_START - $TIME_END UTC"

# --- frontmatter: tags block ---
# Replace first tag placeholder line, then delete any remaining {{tag-N}} lines
replace_block "{{tag-1}}" "$F_TAGS_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{tag-')

# --- frontmatter: todos block ---
replace_block "{{todo-1}}" "$F_TODOS_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{todo-')

# --- frontmatter: summary block scalar (each line already indented) ---
replace_block "{{summary-line-1}}" "$F_SUMMARY_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{summary-line-')

# --- frontmatter: knowledge_graph_updates block ---
replace_block "{{knowledge_graph_update-1}}" "$F_KGU_YAML"
RENDERED=$(printf '%s' "$RENDERED" | grep -v '{{knowledge_graph_update-')

# --- body sections ---
replace_block "{{overview}}"               "$F_OVERVIEW"
replace_block "{{knowledge_body}}"         "$F_KNOWLEDGE_BODY"
replace_block "{{insights_body}}"          "$F_INSIGHTS_BODY"
replace_block "{{synthesis_body}}"         "$F_SYNTHESIS_BODY"
replace_block "{{todos_body}}"             "$F_TODOS_BODY"
replace_block "{{next_suggestions_body}}"  "$F_NEXT_SUGGESTIONS_BODY"

# ---------------------------------------------------------------------------
# Write session log
# ---------------------------------------------------------------------------
mkdir -p "$SESSION_LOGS_DIR"
printf '%s\n' "$RENDERED" > "$LOG_PATH"
log "Session log written: $LOG_PATH"

# ---------------------------------------------------------------------------
# Create daily note from template if it doesn't exist
# ---------------------------------------------------------------------------
if [ ! -f "$DAILY_NOTE" ]; then
  log "Daily note not found, creating from template..."
  mkdir -p "$DAILY_DIR"
  cp "$DAILY_TEMPLATE_PATH" "$DAILY_NOTE"
  log "Daily note created: $DAILY_NOTE"
fi

# ---------------------------------------------------------------------------
# Update frontmatter: append session path to sessions list
# ---------------------------------------------------------------------------
NEW_SESSION_ENTRY="  - $LOG_REL_PATH"

awk -v new_entry="$NEW_SESSION_ENTRY" '
  BEGIN { fm=0; in_sessions=0; injected=0 }
  /^---/ { fm++; print; next }
  fm==1 {
    if (/^sessions:/) { in_sessions=1; print; next }
    if (in_sessions) {
      if (/^  - /) {
        if (/{{/) {
          if (!injected) { print new_entry; injected=1 }
          next
        }
        print; next
      } else {
        if (!injected) { print new_entry; injected=1 }
        in_sessions=0; print; next
      }
    }
    print; next
  }
  fm==2 && in_sessions && !injected { print new_entry; injected=1; in_sessions=0 }
  { print }
' "$DAILY_NOTE" > "${DAILY_NOTE}.tmp" && mv "${DAILY_NOTE}.tmp" "$DAILY_NOTE"

log "Frontmatter sessions list updated"

# ---------------------------------------------------------------------------
# Update body: append to ## 今日會話
# ---------------------------------------------------------------------------
TIME_ONLY=$(TZ="${TZ:-UTC}" date '+%H:%M')
WIKI_LINK="[[${LOG_REL_PATH}|${F_TITLE}]]"
LIST_ITEM="- ${WIKI_LINK} \`${TIME_ONLY}\`"
LIST_SUB="  - ${F_SUMMARY_FIRST}"

if grep -q "^## 今日會話" "$DAILY_NOTE"; then
  printf '\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
else
  printf '\n## 今日會話\n\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
fi

log "今日會話 section updated"
log "Session archived: ${F_TITLE} — ${F_SUMMARY_FIRST}"
discord_notify "📝 Session archived: **${F_TITLE}** — ${F_SUMMARY_FIRST}"

exit 0
