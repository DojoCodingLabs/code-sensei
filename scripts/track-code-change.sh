#!/bin/bash
# CodeSensei -- Track Code Change Hook (PostToolUse: Write|Edit|MultiEdit)
# Records what files Claude creates or modifies for contextual teaching
# This data is used by /explain and /recap to know what happened

SCRIPT_NAME="track-code-change"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

CHANGES_LOG="${PROFILE_DIR}/session-changes.jsonl"
SESSION_STATE="${PROFILE_DIR}/session-state.json"
RATE_LIMIT_INTERVAL=30
SESSION_CAP=12

LIB_DIR="${SCRIPT_DIR}/lib"
if [ -f "${LIB_DIR}/error-handling.sh" ]; then
  # shellcheck source=lib/error-handling.sh
  source "${LIB_DIR}/error-handling.sh"
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

INPUT=$(cat)

ensure_profile_dir
if [ ! -d "$PROFILE_DIR" ]; then
  log_error "$SCRIPT_NAME" "Failed to create profile directory: $PROFILE_DIR"
  exit 0
fi

if ! check_jq "$SCRIPT_NAME"; then
  exit 0
fi

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

SAFE_FILE_PATH=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
SAFE_TOOL_NAME=$(printf '%s' "$TOOL_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
if ! printf '{"timestamp":"%s","tool":"%s","file":"%s","extension":"%s","tech":"%s"}\n' \
  "$TIMESTAMP" "$SAFE_TOOL_NAME" "$SAFE_FILE_PATH" "$EXTENSION" "$TECH" >> "$CHANGES_LOG" 2>&1
then
  log_error "$SCRIPT_NAME" "Failed to write to changes log: $CHANGES_LOG"
fi

IS_FIRST_EVER="false"
if [ -f "$PROFILE_FILE" ] && [ "$TECH" != "other" ]; then
  ALREADY_IN_SESSION=$(jq --arg tech "$TECH" '.session_concepts | index($tech)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking session_concepts for $TECH: $ALREADY_IN_SESSION"
    ALREADY_IN_SESSION="0"
  fi

  ALREADY_IN_LIFETIME=$(jq --arg tech "$TECH" '.concepts_seen | index($tech)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking concepts_seen for $TECH: $ALREADY_IN_LIFETIME"
    ALREADY_IN_LIFETIME="0"
  fi

  if [ "$ALREADY_IN_LIFETIME" = "null" ]; then
    IS_FIRST_EVER="true"
    if ! update_profile --arg tech "$TECH" '
      .session_concepts += (if (.session_concepts | index($tech)) == null then [$tech] else [] end) |
      .concepts_seen += (if (.concepts_seen | index($tech)) == null then [$tech] else [] end)
    '; then
      log_error "$SCRIPT_NAME" "Failed updating profile for first-time technology: $TECH"
      IS_FIRST_EVER="false"
    fi
  elif [ "$ALREADY_IN_SESSION" = "null" ]; then
    if ! update_profile --arg tech "$TECH" '.session_concepts += [$tech]'; then
      log_error "$SCRIPT_NAME" "Failed updating session_concepts for technology: $TECH"
    fi
  fi
fi

if [ "$TECH" = "other" ]; then
  printf '{}\n'
  exit 0
fi

NOW=$(date +%s)
if [ -f "$SESSION_STATE" ]; then
  LAST_TRIGGER=$(jq -r '.last_trigger_time // 0' "$SESSION_STATE" 2>/dev/null || echo "0")
  TRIGGER_COUNT=$(jq -r '.trigger_count // 0' "$SESSION_STATE" 2>/dev/null || echo "0")
else
  LAST_TRIGGER=0
  TRIGGER_COUNT=0
fi

if [ "$TRIGGER_COUNT" -ge "$SESSION_CAP" ]; then
  printf '{}\n'
  exit 0
fi

ELAPSED=$((NOW - LAST_TRIGGER))
if [ "$ELAPSED" -lt "$RATE_LIMIT_INTERVAL" ] && [ "$IS_FIRST_EVER" != "true" ]; then
  printf '{}\n'
  exit 0
fi

NEW_COUNT=$((TRIGGER_COUNT + 1))
SESSION_START_VAL=""
if [ -f "$SESSION_STATE" ]; then
  SESSION_START_VAL=$(jq -r '.session_start // ""' "$SESSION_STATE" 2>/dev/null || echo "")
fi
if [ -z "$SESSION_START_VAL" ]; then
  SESSION_START_VAL="$TIMESTAMP"
fi

if ! jq -n \
  --argjson last "$NOW" \
  --argjson count "$NEW_COUNT" \
  --arg start "$SESSION_START_VAL" \
  '{"last_trigger_time": $last, "trigger_count": $count, "session_start": $start}' > "$SESSION_STATE"
then
  log_error "$SCRIPT_NAME" "Failed to update session state: $SESSION_STATE"
  printf '{}\n'
  exit 0
fi

BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt: $BELT"
  BELT="white"
fi

# --- Pending lessons queue (durable, per-lesson file to avoid append races) --- (DOJ-2436)
PENDING_DIR="${PROFILE_DIR}/pending-lessons"
mkdir -p "$PENDING_DIR"

if [ "$IS_FIRST_EVER" = "true" ]; then
  LESSON_TYPE="micro-lesson"
else
  LESSON_TYPE="inline-insight"
fi

# Write one JSON file per lesson (atomic, no race conditions)
LESSON_ID="${TIMESTAMP}-$(printf '%05d' $$)"
LESSON_FILE="${PENDING_DIR}/${LESSON_ID}.json"
SAFE_FILE_PATH_LESSON=$(printf '%s' "$FILE_PATH" | sed 's/\\/\\\\/g; s/"/\\"/g')
SAFE_TOOL_NAME_LESSON=$(printf '%s' "$TOOL_NAME" | sed 's/\\/\\\\/g; s/"/\\"/g')
if ! printf '{"timestamp":"%s","type":"%s","tech":"%s","file":"%s","tool":"%s","belt":"%s","firstEncounter":%s}\n' \
  "$TIMESTAMP" "$LESSON_TYPE" "$TECH" "$SAFE_FILE_PATH_LESSON" "$SAFE_TOOL_NAME_LESSON" "$BELT" "$IS_FIRST_EVER" > "$LESSON_FILE"
then
  log_error "$SCRIPT_NAME" "Failed to write pending lesson: $LESSON_FILE"
fi

# --- Delegation hint: delegate teaching to sensei subagent --- (DOJ-2436)
CONTEXT="CodeSensei: New teaching moment detected ($TECH, $FILE_PATH). If the user is not in the middle of a complex task, use the Task tool to invoke the 'sensei' agent. Pass it the latest pending lesson from ~/.code-sensei/pending-lessons/."

ESCAPED_CONTEXT=$(json_escape "$CONTEXT")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED_CONTEXT"

exit 0
