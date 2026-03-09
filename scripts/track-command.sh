#!/bin/bash
# CodeSensei — Track Command Hook (PostToolUse: Bash)
# Records what shell commands Claude runs for contextual teaching
# Helps /explain and /recap know what tools/packages were used

PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
COMMANDS_LOG="$PROFILE_DIR/session-commands.jsonl"

# Read hook input from stdin
INPUT=$(cat)

if [ ! -d "$PROFILE_DIR" ]; then
  mkdir -p "$PROFILE_DIR"
fi

if command -v jq &> /dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "unknown"')
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Detect what kind of command this is for concept tracking
  CONCEPT=""
  case "$COMMAND" in
    *"npm install"*|*"npm i "*|*"yarn add"*|*"pnpm add"*)
      CONCEPT="package-management"
      # Extract package name for tracking
      PACKAGE=$(echo "$COMMAND" | sed -E 's/.*(npm install|npm i|yarn add|pnpm add)[[:space:]]+([^[:space:]]+).*/\2/' | head -1)
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

  record_profile_concept() {
    local concept="$1"
    local first_flag_var="$2"

    if [ -z "$concept" ] || [ ! -f "$PROFILE_FILE" ]; then
      return
    fi

    local already_in_session
    local already_in_lifetime
    local updated

    already_in_session=$(jq --arg c "$concept" '.session_concepts | index($c)' "$PROFILE_FILE")
    if [ "$already_in_session" = "null" ]; then
      updated=$(jq --arg c "$concept" '.session_concepts += [$c]' "$PROFILE_FILE")
      echo "$updated" > "$PROFILE_FILE"
    fi

    already_in_lifetime=$(jq --arg c "$concept" '.concepts_seen | index($c)' "$PROFILE_FILE")
    if [ "$already_in_lifetime" = "null" ]; then
      updated=$(jq --arg c "$concept" '.concepts_seen += [$c]' "$PROFILE_FILE")
      echo "$updated" > "$PROFILE_FILE"
      printf -v "$first_flag_var" '%s' "true"
    fi
  }

  # Track concept in session and lifetime if new and meaningful
  IS_FIRST_EVER="false"
  record_profile_concept "$CONCEPT" IS_FIRST_EVER

  # Always inject teaching context after commands
  BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>/dev/null || echo "white")
  # Sanitize command for JSON (remove quotes and special chars)
  SAFE_CMD=$(echo "$COMMAND" | head -c 80 | tr '"' "'" | tr '\\' '/')

  # Check if this is a test runner command — skip error detection for those
  IS_TEST_RUNNER="false"
  case "$COMMAND" in
    jest\ *|"jest"|\
    pytest\ *|"pytest"|\
    vitest\ *|"vitest"|\
    bats\ *|"bats"|\
    mocha\ *|"mocha"|\
    "npm test"*|"npm run test"*|\
    "yarn test"*|"yarn run test"*|\
    "pnpm test"*|"pnpm run test"*|"pnpm vitest"*|\
    "npx jest"*|"npx vitest"*|"pnpm exec jest"*|"pnpm exec vitest"*)
      IS_TEST_RUNNER="true"
      ;;
  esac

  # Detect error patterns in command output (only for non-test-runner commands)
  ERROR_CONCEPT=""
  if [ "$IS_TEST_RUNNER" = "false" ]; then
    TOOL_RESPONSE=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null || echo "")
    STDOUT=$(echo "$INPUT" | jq -r '.tool_response.stdout // ""' 2>/dev/null || echo "")
    STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // ""' 2>/dev/null || echo "")
    OUTPUT="${STDOUT}${STDERR}${TOOL_RESPONSE}"

    case "$OUTPUT" in
      *"Traceback (most recent call last):"*)
        ERROR_CONCEPT="error-reading"
        ;;
      *"TypeError"*|*"ReferenceError"*|*"SyntaxError"*)
        ERROR_CONCEPT="common-errors"
        ;;
      *"Error:"*|*"ERROR:"*|*"error:"*)
        ERROR_CONCEPT="error-reading"
        ;;
      *"ENOENT"*|*"EACCES"*|*"EPERM"*)
        ERROR_CONCEPT="error-reading"
        ;;
      *"command not found"*)
        ERROR_CONCEPT="error-reading"
        ;;
      *"ModuleNotFoundError"*|*"ImportError"*)
        ERROR_CONCEPT="error-reading"
        ;;
      *"fatal:"*)
        ERROR_CONCEPT="error-reading"
        ;;
    esac
  fi

  ERROR_IS_FIRST_EVER="false"
  record_profile_concept "$ERROR_CONCEPT" ERROR_IS_FIRST_EVER

  if [ "$ERROR_IS_FIRST_EVER" = "true" ] && [ -n "$ERROR_CONCEPT" ]; then
    CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$ERROR_CONCEPT' for the FIRST TIME while reading command output ($SAFE_CMD). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of how to read this kind of error and why it matters. Adapt language to their belt level. Keep it supportive and practical."
  elif [ -n "$ERROR_CONCEPT" ]; then
    # Error detected in command output: teach debugging first
    CONTEXT="🥋 CodeSensei inline insight: An error appeared in the command output ($SAFE_CMD). The user's belt level is '$BELT'. This is a great moment to teach '$ERROR_CONCEPT' — briefly explain how to read and interpret this type of error in 1-2 sentences, adapted to their belt level. Keep it supportive and practical."
  elif [ "$IS_FIRST_EVER" = "true" ] && [ -n "$CONCEPT" ]; then
    # First-time encounter: micro-lesson about the concept
    CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$CONCEPT' for the FIRST TIME (command: $SAFE_CMD). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of what $CONCEPT means and why it matters. Adapt language to their belt level. Keep it concise and non-intrusive."
  elif [ -n "$CONCEPT" ]; then
    # Already-seen concept: brief inline insight about this specific command
    CONTEXT="🥋 CodeSensei inline insight: Claude just ran a '$CONCEPT' command ($SAFE_CMD). The user's belt level is '$BELT'. Provide a brief 1-sentence explanation of what this command does, adapted to their belt level. Keep it natural and non-intrusive."
  else
    # Unknown command type: still provide a brief hint
    CONTEXT="🥋 CodeSensei inline insight: Claude just ran a shell command ($SAFE_CMD). The user's belt level is '$BELT'. If this command is educational, briefly explain what it does in 1 sentence. If trivial, skip the explanation."
  fi

  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$CONTEXT\"}}"
fi

exit 0
