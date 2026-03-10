#!/bin/bash
# CodeSensei -- Track Command Hook (PostToolUse: Bash)
# Records what shell commands Claude runs for contextual teaching
# Helps /explain and /recap know what tools/packages were used

SCRIPT_NAME="track-command"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

COMMANDS_LOG="${PROFILE_DIR}/session-commands.jsonl"

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

IS_FIRST_EVER="false"
if [ -n "$CONCEPT" ] && [ -f "$PROFILE_FILE" ]; then
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

BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt: $BELT"
  BELT="white"
fi

SAFE_CMD=$(printf '%s' "$COMMAND" | head -c 80 | tr '"' "'" | tr '\\' '/')

if [ "$IS_FIRST_EVER" = "true" ] && [ -n "$CONCEPT" ]; then
  CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$CONCEPT' for the FIRST TIME (command: $SAFE_CMD). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of what $CONCEPT means and why it matters. Adapt language to their belt level. Keep it concise and non-intrusive."
elif [ -n "$CONCEPT" ]; then
  CONTEXT="🥋 CodeSensei inline insight: Claude just ran a '$CONCEPT' command ($SAFE_CMD). The user's belt level is '$BELT'. Provide a brief 1-sentence explanation of what this command does, adapted to their belt level. Keep it natural and non-intrusive."
else
  CONTEXT="🥋 CodeSensei inline insight: Claude just ran a shell command ($SAFE_CMD). The user's belt level is '$BELT'. If this command is educational, briefly explain what it does in 1 sentence. If trivial, skip the explanation."
fi

ESCAPED_CONTEXT=$(json_escape "$CONTEXT")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED_CONTEXT"

exit 0
