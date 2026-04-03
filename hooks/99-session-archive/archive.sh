#!/bin/bash
# Session archiver — generates session log and updates daily note.

VAULT_DIR="$HOME/vault"
SESSION_LOGS_DIR="$VAULT_DIR/01-Session-Logs"
DAILY_DIR="$VAULT_DIR/02-Daily-Notes"
SESSION_TEMPLATE_PATH="$VAULT_DIR/templates/SESSION-LOG.md"
DAILY_TEMPLATE_PATH="$VAULT_DIR/templates/DAILY-NOTE.md"

TRANSCRIPT_PATH="${1:-}"

MONTH=$(TZ="${TZ:-UTC}" date '+%Y-%m')
DATE=$(TZ="${TZ:-UTC}" date '+%Y-%m-%d')
TIME_START=$(TZ="${TZ:-UTC}" date '+%H:%M')
DAILY_NOTE="$DAILY_DIR/$MONTH/$DATE.md"

HOOK_SETTINGS="{\"disableAllHooks\": true}"
LOGFILE="/tmp/session-archiver-debug.log"

# Load .env for Discord credentials
ENV_FILE="$(dirname "$0")/../../.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
DISCORD_CHANNEL_ID="1486128557444042883"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOGFILE"; }
err() { log "ERROR: $*"; echo "ERROR: $*" >&2; }

die() {
  err "$*"
  discord_notify "❌ Session archive failed: $*"
  exit 1
}

discord_notify() {
  local msg="$1"
  [ -z "$DISCORD_BOT_TOKEN" ] && return
  local payload
  payload=$(jq -n --arg content "$msg" '{"content": $content}')
  curl -s -X POST "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOGFILE" 2>&1
}

# ---------------------------------------------------------------------------
# Validate templates
# ---------------------------------------------------------------------------
[ -f "$SESSION_TEMPLATE_PATH" ] || die "Session template not found at '$SESSION_TEMPLATE_PATH'"
[ -f "$DAILY_TEMPLATE_PATH"   ] || die "Daily template not found at '$DAILY_TEMPLATE_PATH'"

SESSION_TEMPLATE_CONTENT=$(cat "$SESSION_TEMPLATE_PATH")

# ---------------------------------------------------------------------------
# Validate transcript — hard errors, no silent fallback
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
# Generate session log via Claude
# ---------------------------------------------------------------------------
log "Generating session log from template..."
TIME_END=$(TZ="${TZ:-UTC}" date '+%H:%M')

SESSION_LOG_CONTENT=$(claude -p \
"你是個人知識助理，負責在對話結束後產生 SessionLog。

## 任務
根據以下對話內容，填寫 SessionLog Template 中的所有 {{placeholder}}，輸出完整的 SessionLog markdown 檔案。

## 規則
- 完整保留 template 的所有結構、章節標題、frontmatter 欄位
- 將所有 {{placeholder}} 替換為實際內容，不留任何 {{}} 符號
- frontmatter 欄位：
  - title: 動詞開頭，10字以內的中文主題
  - date: $DATE
  - time: $DATE $TIME_START - $TIME_END UTC
  - tags: 2-5個，小寫英文加連字號
  - summary: 嚴格 5-8 行，每行對應一個面向
  - todos: 若無待辦則填 []
  - knowledge_graph_updates: 填入識別到的知識關聯，若無則填 []
- Markdown Body：
  - 若本次對話無新知識，## 新知識 段落寫「本次對話無新增知識。」
  - 若無靈感，## 靈感 段落寫「本次對話無捕捉到靈感。」
  - 若無待辦，## 待辦或成果 段落寫「本次對話無新增待辦。」
  - [[wiki-link]] 使用繁體中文或英文原文節點名稱
- 只輸出 markdown 內容，不加任何說明或前後文

## SessionLog Template
$SESSION_TEMPLATE_CONTENT

## 對話內容
$TRANSCRIPT_TEXT
" \
  --settings "$HOOK_SETTINGS" --dangerously-skip-permissions --model claude-haiku-4-5 2>/dev/null)

[ -n "$SESSION_LOG_CONTENT" ] || die "Claude failed to generate session log (empty response)"

# ---------------------------------------------------------------------------
# Parse title and summary from generated frontmatter
# ---------------------------------------------------------------------------
LOG_TITLE=$(echo "$SESSION_LOG_CONTENT" | awk '
  /^---/{ fm++; next }
  fm==1 && /^title:/{ sub(/^title: */,""); print; exit }
')
LOG_SUMMARY=$(echo "$SESSION_LOG_CONTENT" | awk '
  /^---/{ fm++; next }
  fm==1 && /^summary:/{ in_sum=1; next }
  fm==1 && in_sum && /^  /{ gsub(/^ +/,""); print; next }
  fm==1 && in_sum && !/^  /{ in_sum=0 }
  fm==2{ exit }
' | head -1)

LOG_TITLE="${LOG_TITLE:-Session}"
LOG_TITLE_SLUG=$(echo "$LOG_TITLE" | tr ' ' '-' | tr -cd '[:alnum:]-_')
LOG_TITLE_SLUG="${LOG_TITLE_SLUG:-Session}"
LOG_FILENAME="${DATE}_${LOG_TITLE_SLUG}.md"
LOG_PATH="$SESSION_LOGS_DIR/$DATE/$LOG_FILENAME"
LOG_REL_PATH="01-Session-Logs/$DATE/$LOG_FILENAME"   # vault-root relative, for frontmatter & wiki-links

# ---------------------------------------------------------------------------
# Write session log file
# ---------------------------------------------------------------------------
mkdir -p "$SESSION_LOGS_DIR"
echo "$SESSION_LOG_CONTENT" > "$LOG_PATH"
log "Session log written to $LOG_PATH"

# ---------------------------------------------------------------------------
# Create daily note from template if it doesn't exist
# ---------------------------------------------------------------------------
if [ ! -f "$DAILY_NOTE" ]; then
  log "Daily note not found, creating from template..."
  mkdir -p "$DAILY_DIR"
  sed "s/{{YYYY-MM-DD}}/$DATE/g" "$DAILY_TEMPLATE_PATH" > "$DAILY_NOTE"
  log "Daily note created: $DAILY_NOTE"
fi

# ---------------------------------------------------------------------------
# Update frontmatter: append new path to sessions list
#
# Uses awk to rewrite the file in-place.
# Handles three cases:
#   1. sessions list has real entries already  → append after last real entry
#   2. sessions list only has {{placeholders}} → replace placeholders, add entry
#   3. sessions key exists but list is empty   → add entry on next line
# ---------------------------------------------------------------------------
NEW_SESSION_ENTRY="  - $LOG_REL_PATH"

awk -v new_entry="$NEW_SESSION_ENTRY" '
  BEGIN { fm=0; in_sessions=0; injected=0 }

  /^---/ { fm++; print; next }

  fm==1 {
    if (/^sessions:/) {
      in_sessions=1
      print
      next
    }

    if (in_sessions) {
      if (/^  - /) {
        if (/{{/) {
          # Placeholder line — skip it, inject real entry once
          if (!injected) {
            print new_entry
            injected=1
          }
          next
        }
        # Real entry — keep it
        print
        next
      } else {
        # Exiting the sessions block — inject if not yet done
        if (!injected) {
          print new_entry
          injected=1
        }
        in_sessions=0
        print
        next
      }
    }

    print
    next
  }

  # Frontmatter closed while still in sessions block
  fm==2 && in_sessions && !injected {
    print new_entry
    injected=1
    in_sessions=0
  }

  { print }
' "$DAILY_NOTE" > "${DAILY_NOTE}.tmp" && mv "${DAILY_NOTE}.tmp" "$DAILY_NOTE"

log "Frontmatter sessions list updated"

# ---------------------------------------------------------------------------
# Update body: append entry to ## 今日會話 section
# ---------------------------------------------------------------------------
TIME_ONLY=$(TZ="${TZ:-UTC}" date '+%H:%M')
WIKI_LINK="[[${LOG_REL_PATH}|${LOG_TITLE}]]"
LIST_ITEM="- ${WIKI_LINK} \`${TIME_ONLY}\`"
LIST_SUB="  - ${LOG_SUMMARY:-（無摘要）}"

if grep -q "^## 今日會話" "$DAILY_NOTE"; then
  printf '\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
else
  printf '\n## 今日會話\n\n%s\n%s\n' "$LIST_ITEM" "$LIST_SUB" >> "$DAILY_NOTE"
fi

log "今日會話 section updated"
log "Session archived: ${LOG_TITLE} — ${LOG_SUMMARY:-（無摘要）}"

discord_notify "📝 Session archived: **${LOG_TITLE}** — ${LOG_SUMMARY:-（無摘要）}"

exit 0
