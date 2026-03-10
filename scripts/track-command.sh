#!/bin/bash
# CodeSensei -- Track Command Hook (PostToolUse: Bash)
# Records what shell commands Claude runs for contextual teaching
# Helps /explain and /recap know what tools/packages were used

SCRIPT_NAME="track-command"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

COMMANDS_LOG="${PROFILE_DIR}/session-commands.jsonl"
SESSION_STATE="${PROFILE_DIR}/session-state.json"
RATE_LIMIT_INTERVAL=30
SESSION_CAP=12
TRIVIAL_COMMANDS="cd ls pwd clear echo cat which man help exit history alias type file wc whoami hostname uname true false"

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

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // "unknown"' 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading tool_input.command: $COMMAND"
  COMMAND="unknown"
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BASE_CMD=$(printf '%s' "$COMMAND" | sed 's/^[[:space:]]*//' | awk '{print $1}' | sed 's|.*/||')

IS_TRIVIAL="false"
for trivial in $TRIVIAL_COMMANDS; do
  if [ "$BASE_CMD" = "$trivial" ]; then
    IS_TRIVIAL="true"
    break
  fi
done

if [ "$IS_TRIVIAL" = "true" ]; then
  SAFE_LOG_CMD=$(printf '%s' "$COMMAND" | head -c 200 | sed 's/\\/\\\\/g; s/"/\\"/g')
  if ! printf '{"timestamp":"%s","command":"%s","concept":"","skipped":"trivial"}\n' \
    "$TIMESTAMP" "$SAFE_LOG_CMD" >> "$COMMANDS_LOG" 2>&1
  then
    log_error "$SCRIPT_NAME" "Failed to write trivial command log: $COMMANDS_LOG"
  fi
  printf '{}\n'
  exit 0
fi

CONCEPT=""
case "$COMMAND" in
  *"npm install"*|*"npm i "*|*"yarn add"*|*"pnpm add"*)
    CONCEPT="package-management"
    PACKAGE=$(printf '%s' "$COMMAND" | sed -E 's/.*(npm install|npm i|yarn add|pnpm add)[[:space:]]+([^[:space:]]+).*/\2/' | head -1)
    ;;
  *"pip install"*|*"pip3 install"*) CONCEPT="package-management" ;;
  *"git "*) CONCEPT="git" ;;
  *"docker "*) CONCEPT="docker" ;;
  *"curl "*|*"wget "*) CONCEPT="http-requests" ;;
  *"mkdir "*|*"touch "*|*"cp "*|*"mv "*|*"rm "*) CONCEPT="file-system" ;;
  *"node "*|*"npx "*) CONCEPT="nodejs-runtime" ;;
  *"python "*|*"python3 "*) CONCEPT="python-runtime" ;;
  *"psql "*|*"mysql "*|*"sqlite3 "*) CONCEPT="database-cli" ;;
  *"cd "*|*"ls "*|*"pwd"*) CONCEPT="terminal-navigation" ;;
  *"chmod "*|*"chown "*) CONCEPT="permissions" ;;
  *"ssh "*|*"scp "*) CONCEPT="remote-access" ;;
  *"env "*|*"export "*) CONCEPT="environment-variables" ;;
  *"test "*|*"jest "*|*"vitest "*|*"pytest "*) CONCEPT="testing" ;;
  *) CONCEPT="" ;;
esac

CMD_TRUNCATED=$(printf '%s' "$COMMAND" | head -c 200)
SAFE_LOG_CMD=$(printf '%s' "$CMD_TRUNCATED" | sed 's/\\/\\\\/g; s/"/\\"/g')
SAFE_CONCEPT=$(printf '%s' "$CONCEPT" | sed 's/\\/\\\\/g; s/"/\\"/g')
if ! printf '{"timestamp":"%s","command":"%s","concept":"%s"}\n' \
  "$TIMESTAMP" "$SAFE_LOG_CMD" "$SAFE_CONCEPT" >> "$COMMANDS_LOG" 2>&1
then
  log_error "$SCRIPT_NAME" "Failed to write to commands log: $COMMANDS_LOG"
fi

if [ -z "$CONCEPT" ]; then
  printf '{}\n'
  exit 0
fi

IS_FIRST_EVER="false"
if [ -f "$PROFILE_FILE" ]; then
  ALREADY_IN_SESSION=$(jq --arg c "$CONCEPT" '.session_concepts | index($c)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking session_concepts for $CONCEPT: $ALREADY_IN_SESSION"
    ALREADY_IN_SESSION="0"
  fi

  ALREADY_IN_LIFETIME=$(jq --arg c "$CONCEPT" '.concepts_seen | index($c)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking concepts_seen for $CONCEPT: $ALREADY_IN_LIFETIME"
    ALREADY_IN_LIFETIME="0"
  fi

  if [ "$ALREADY_IN_LIFETIME" = "null" ]; then
    IS_FIRST_EVER="true"
    if ! update_profile --arg c "$CONCEPT" '
      .session_concepts += (if (.session_concepts | index($c)) == null then [$c] else [] end) |
      .concepts_seen += (if (.concepts_seen | index($c)) == null then [$c] else [] end)
    '; then
      log_error "$SCRIPT_NAME" "Failed updating profile for first-time concept: $CONCEPT"
      IS_FIRST_EVER="false"
    fi
  elif [ "$ALREADY_IN_SESSION" = "null" ]; then
    if ! update_profile --arg c "$CONCEPT" '.session_concepts += [$c]'; then
      log_error "$SCRIPT_NAME" "Failed updating session_concepts for concept: $CONCEPT"
    fi
  fi
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

SAFE_CMD=$(printf '%s' "$COMMAND" | head -c 80 | tr '"' "'" | tr '\\' '/')

if [ "$IS_FIRST_EVER" = "true" ]; then
  CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$CONCEPT' for the FIRST TIME (command: $SAFE_CMD). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of what $CONCEPT means and why it matters. Adapt language to their belt level. Keep it concise and non-intrusive."
else
  CONTEXT="🥋 CodeSensei inline insight: Claude just ran a '$CONCEPT' command ($SAFE_CMD). The user's belt level is '$BELT'. Provide a brief 1-sentence explanation of what this command does, adapted to their belt level. Keep it natural and non-intrusive."
fi

ESCAPED_CONTEXT=$(json_escape "$CONTEXT")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED_CONTEXT"

exit 0
