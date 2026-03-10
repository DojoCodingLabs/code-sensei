#!/bin/bash
# CodeSensei — Track Command Hook (PostToolUse: Bash)
# Records what shell commands Claude runs for contextual teaching
# Helps /explain and /recap know what tools/packages were used

# Resolve lib path relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

COMMANDS_LOG="${PROFILE_DIR}/session-commands.jsonl"

# Read hook input from stdin
INPUT=$(cat)

ensure_profile_dir

if command -v jq &> /dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Detect what kind of command this is for concept tracking
  CONCEPT=""
  case "$COMMAND" in
    *"npm install"*|*"npm i "*|*"yarn add"*|*"pnpm add"*)
      CONCEPT="package-management"
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

  # Log the command
  echo "{\"timestamp\":\"$TIMESTAMP\",\"command\":\"$(echo "$COMMAND" | head -c 200)\",\"concept\":\"$CONCEPT\"}" >> "$COMMANDS_LOG"

  # Track concept in session and lifetime — single atomic jq pass
  IS_FIRST_EVER="false"
  if [ -n "$CONCEPT" ] && [ -f "$PROFILE_FILE" ]; then
    # Read current state once to determine what flags to set
    ALREADY_IN_SESSION=$(jq --arg c "$CONCEPT" '.session_concepts | index($c)' "$PROFILE_FILE")
    ALREADY_IN_LIFETIME=$(jq --arg c "$CONCEPT" '.concepts_seen | index($c)' "$PROFILE_FILE")

    if [ "$ALREADY_IN_LIFETIME" = "null" ]; then
      IS_FIRST_EVER="true"
      # Add to both session_concepts and concepts_seen in one atomic pass
      update_profile --arg c "$CONCEPT" '
        .session_concepts += (if (.session_concepts | index($c)) == null then [$c] else [] end) |
        .concepts_seen   += (if (.concepts_seen   | index($c)) == null then [$c] else [] end)
      '
    elif [ "$ALREADY_IN_SESSION" = "null" ]; then
      # New to session only — single atomic pass
      update_profile --arg c "$CONCEPT" '
        .session_concepts += [$c]
      '
    fi
  fi

  # Always inject teaching context after commands
  BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>/dev/null || echo "white")
  # Sanitize command for JSON (remove quotes and special chars)
  SAFE_CMD=$(echo "$COMMAND" | head -c 80 | tr '"' "'" | tr '\\' '/')

  # --- Pending lessons queue (durable, per-lesson file to avoid append races) ---
  PENDING_DIR="${PROFILE_DIR}/pending-lessons"
  mkdir -p "$PENDING_DIR"

  if [ "$IS_FIRST_EVER" = "true" ] && [ -n "$CONCEPT" ]; then
    LESSON_TYPE="micro-lesson"
  elif [ -n "$CONCEPT" ]; then
    LESSON_TYPE="inline-insight"
  else
    LESSON_TYPE="command-hint"
  fi

  # Write one JSON file per lesson (atomic, no race conditions)
  LESSON_ID="${TIMESTAMP}-$(printf '%05d' $$)"
  LESSON_FILE="${PENDING_DIR}/${LESSON_ID}.json"
  cat > "$LESSON_FILE" <<LESSON_EOF
{"timestamp":"$TIMESTAMP","type":"$LESSON_TYPE","concept":"$CONCEPT","command":"$SAFE_CMD","belt":"$BELT","firstEncounter":$IS_FIRST_EVER}
LESSON_EOF

  # --- Minimal delegation hint (not full teaching content) ---
  DISPLAY_TOPIC="${CONCEPT:-shell command}"
  CONTEXT="CodeSensei: New teaching moment detected ($DISPLAY_TOPIC, $SAFE_CMD). If the user is not in the middle of a complex task, use the Task tool to invoke the 'sensei' agent. Pass it the latest pending lesson from ~/.code-sensei/pending-lessons/."

  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$CONTEXT\"}}"
fi

exit 0
