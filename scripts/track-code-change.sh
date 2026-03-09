#!/bin/bash
# CodeSensei — Track Code Change Hook (PostToolUse: Write|Edit|MultiEdit)
# Records what files Claude creates or modifies for contextual teaching
# This data is used by /explain and /recap to know what happened

SCRIPT_NAME="track-code-change"
PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
CHANGES_LOG="$PROFILE_DIR/session-changes.jsonl"

# Load shared error handling
LIB_DIR="$(dirname "$0")/lib"
if [ -f "$LIB_DIR/error-handling.sh" ]; then
  source "$LIB_DIR/error-handling.sh"
else
  LOG_FILE="${PROFILE_DIR}/error.log"
  log_error() { printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')" "${1:-unknown}" "$2" >> "$LOG_FILE" 2>/dev/null; }
  json_escape() {
    local str="$1"
    if command -v jq &>/dev/null; then
      printf '%s' "$str" | jq -Rs '.'
    else
      printf '"%s"' "$(printf '%s' "$str" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fi
  }
  check_jq() { command -v jq &>/dev/null; }
fi

# Read hook input from stdin
INPUT=$(cat)

if [ ! -d "$PROFILE_DIR" ]; then
  if ! mkdir -p "$PROFILE_DIR" 2>&1; then
    log_error "$SCRIPT_NAME" "Failed to create profile directory: $PROFILE_DIR"
    exit 0
  fi
fi

if ! check_jq "$SCRIPT_NAME"; then
  exit 0
fi

# Extract file path and tool info from hook input
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading tool_name: $TOOL_NAME"
  TOOL_NAME="unknown"
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // "unknown"' 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading file_path: $FILE_PATH"
  FILE_PATH="unknown"
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Detect file type/technology for concept mapping
EXTENSION="${FILE_PATH##*.}"
TECH=""
case "$EXTENSION" in
  html|htm) TECH="html" ;;
  css|scss|sass|less) TECH="css" ;;
  js|mjs) TECH="javascript" ;;
  jsx) TECH="react" ;;
  ts|tsx) TECH="typescript" ;;
  py) TECH="python" ;;
  sql) TECH="sql" ;;
  json) TECH="json" ;;
  md|mdx) TECH="markdown" ;;
  sh|bash) TECH="shell" ;;
  yaml|yml) TECH="yaml" ;;
  toml) TECH="toml" ;;
  env) TECH="environment-variables" ;;
  dockerfile|Dockerfile) TECH="docker" ;;
  *) TECH="other" ;;
esac

# Log the change (escape dynamic values for JSON safety)
SAFE_FILE_PATH=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
SAFE_TOOL_NAME=$(printf '%s' "$TOOL_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
if ! printf '{"timestamp":"%s","tool":"%s","file":"%s","extension":"%s","tech":"%s"}\n' \
    "$TIMESTAMP" "$SAFE_TOOL_NAME" "$SAFE_FILE_PATH" "$EXTENSION" "$TECH" >> "$CHANGES_LOG" 2>&1; then
  log_error "$SCRIPT_NAME" "Failed to write to changes log: $CHANGES_LOG"
fi

# Track technology in session concepts if it's new
IS_FIRST_EVER="false"
if [ -f "$PROFILE_FILE" ] && [ "$TECH" != "other" ]; then
  ALREADY_SEEN=$(jq --arg tech "$TECH" '.session_concepts | index($tech)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking session_concepts for $TECH: $ALREADY_SEEN"
    ALREADY_SEEN="0"
  fi

  if [ "$ALREADY_SEEN" = "null" ]; then
    UPDATED=$(jq --arg tech "$TECH" '.session_concepts += [$tech]' "$PROFILE_FILE" 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed appending to session_concepts: $UPDATED"
    else
      TMPFILE=$(mktemp "${PROFILE_FILE}.XXXXXX" 2>&1)
      if [ $? -ne 0 ]; then
        log_error "$SCRIPT_NAME" "mktemp failed: $TMPFILE"
      else
        printf '%s\n' "$UPDATED" > "$TMPFILE" && mv "$TMPFILE" "$PROFILE_FILE"
        if [ $? -ne 0 ]; then
          log_error "$SCRIPT_NAME" "Failed atomic profile write (session_concepts)"
          rm -f "$TMPFILE"
        fi
      fi
    fi
  fi

  # Also add to lifetime concepts_seen if new — and flag for micro-lesson
  LIFETIME_SEEN=$(jq --arg tech "$TECH" '.concepts_seen | index($tech)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking concepts_seen for $TECH: $LIFETIME_SEEN"
    LIFETIME_SEEN="0"
  fi

  if [ "$LIFETIME_SEEN" = "null" ]; then
    UPDATED=$(jq --arg tech "$TECH" '.concepts_seen += [$tech]' "$PROFILE_FILE" 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed appending to concepts_seen: $UPDATED"
    else
      TMPFILE=$(mktemp "${PROFILE_FILE}.XXXXXX" 2>&1)
      if [ $? -ne 0 ]; then
        log_error "$SCRIPT_NAME" "mktemp failed: $TMPFILE"
      else
        printf '%s\n' "$UPDATED" > "$TMPFILE" && mv "$TMPFILE" "$PROFILE_FILE"
        if [ $? -ne 0 ]; then
          log_error "$SCRIPT_NAME" "Failed atomic profile write (concepts_seen)"
          rm -f "$TMPFILE"
        else
          IS_FIRST_EVER="true"
        fi
      fi
    fi
  fi
fi

# Always inject teaching context after code changes
BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt: $BELT"
  BELT="white"
fi

if [ "$IS_FIRST_EVER" = "true" ]; then
  CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$TECH' for the FIRST TIME (file: $FILE_PATH). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of what $TECH is and why it matters for their project. Adapt language to their belt level. Keep it concise and non-intrusive — weave it naturally into your response, don't stop everything for a lecture."
else
  CONTEXT="🥋 CodeSensei inline insight: Claude just used '$TOOL_NAME' on '$FILE_PATH' ($TECH). The user's belt level is '$BELT'. Provide a brief 1-2 sentence explanation of what this change does and why, adapted to their belt level. Keep it natural and non-intrusive — weave it into your response as a quick teaching moment."
fi

# Escape the full context once before embedding it in the hook payload
ESCAPED_CONTEXT=$(json_escape "$CONTEXT")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED_CONTEXT"

exit 0
