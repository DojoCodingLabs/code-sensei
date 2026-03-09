#!/bin/bash
# CodeSensei — Track Command Hook (PostToolUse: Bash)
# Records what shell commands Claude runs for contextual teaching
# Helps /explain and /recap know what tools/packages were used

SCRIPT_NAME="track-command"
PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
COMMANDS_LOG="$PROFILE_DIR/session-commands.jsonl"

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

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // "unknown"' 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading tool_input.command: $COMMAND"
  COMMAND="unknown"
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Detect what kind of command this is for concept tracking
CONCEPT=""
case "$COMMAND" in
  *"npm install"*|*"npm i "*|*"yarn add"*|*"pnpm add"*)
    CONCEPT="package-management"
    # Extract package name for tracking
    PACKAGE=$(printf '%s' "$COMMAND" | sed -E 's/.*(npm install|npm i|yarn add|pnpm add)[[:space:]]+([^[:space:]]+).*/\2/' | head -1)
    ;;
  *"pip install"*|*"pip3 install"*)
    CONCEPT="package-management"
    ;;
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

# Log the command (truncate to 200 chars, escape for JSON)
CMD_TRUNCATED=$(printf '%s' "$COMMAND" | head -c 200)
SAFE_CMD=$(printf '%s' "$CMD_TRUNCATED" | sed 's/\\/\\\\/g; s/"/\\"/g')
SAFE_CONCEPT=$(printf '%s' "$CONCEPT" | sed 's/\\/\\\\/g; s/"/\\"/g')
if ! printf '{"timestamp":"%s","command":"%s","concept":"%s"}\n' \
    "$TIMESTAMP" "$SAFE_CMD" "$SAFE_CONCEPT" >> "$COMMANDS_LOG" 2>&1; then
  log_error "$SCRIPT_NAME" "Failed to write to commands log: $COMMANDS_LOG"
fi

# Track concept in session and lifetime if new and meaningful
IS_FIRST_EVER="false"
if [ -n "$CONCEPT" ] && [ -f "$PROFILE_FILE" ]; then
  ALREADY_SEEN=$(jq --arg c "$CONCEPT" '.session_concepts | index($c)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking session_concepts for $CONCEPT: $ALREADY_SEEN"
    ALREADY_SEEN="0"
  fi

  if [ "$ALREADY_SEEN" = "null" ]; then
    UPDATED=$(jq --arg c "$CONCEPT" '.session_concepts += [$c]' "$PROFILE_FILE" 2>&1)
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

  LIFETIME_SEEN=$(jq --arg c "$CONCEPT" '.concepts_seen | index($c)' "$PROFILE_FILE" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed checking concepts_seen for $CONCEPT: $LIFETIME_SEEN"
    LIFETIME_SEEN="0"
  fi

  if [ "$LIFETIME_SEEN" = "null" ]; then
    UPDATED=$(jq --arg c "$CONCEPT" '.concepts_seen += [$c]' "$PROFILE_FILE" 2>&1)
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

# Always inject teaching context after commands
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

# Escape the full context once before embedding it in the hook payload
ESCAPED_CONTEXT=$(json_escape "$CONTEXT")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":%s}}\n' "$ESCAPED_CONTEXT"

exit 0
