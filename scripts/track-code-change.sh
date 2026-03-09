#!/bin/bash
# CodeSensei — Track Code Change Hook (PostToolUse: Write|Edit|MultiEdit)
# Records what files Claude creates or modifies for contextual teaching
# This data is used by /explain and /recap to know what happened

PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
CHANGES_LOG="$PROFILE_DIR/session-changes.jsonl"
SESSION_STATE="$PROFILE_DIR/session-state.json"

# Rate limiting constants
RATE_LIMIT_INTERVAL=30   # minimum seconds between teaching triggers
SESSION_CAP=12           # maximum teaching triggers per session

# Read hook input from stdin
INPUT=$(cat)

if [ ! -d "$PROFILE_DIR" ]; then
  mkdir -p "$PROFILE_DIR"
fi

if command -v jq &> /dev/null; then
  # Extract file path and tool info from hook input
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // "unknown"')
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

  # Log the change
  echo "{\"timestamp\":\"$TIMESTAMP\",\"tool\":\"$TOOL_NAME\",\"file\":\"$FILE_PATH\",\"extension\":\"$EXTENSION\",\"tech\":\"$TECH\"}" >> "$CHANGES_LOG"

  # Track technology in session concepts if it's new
  IS_FIRST_EVER="false"
  if [ -f "$PROFILE_FILE" ] && [ "$TECH" != "other" ]; then
    ALREADY_SEEN=$(jq --arg tech "$TECH" '.session_concepts | index($tech)' "$PROFILE_FILE")
    if [ "$ALREADY_SEEN" = "null" ]; then
      UPDATED=$(jq --arg tech "$TECH" '.session_concepts += [$tech]' "$PROFILE_FILE")
      echo "$UPDATED" > "$PROFILE_FILE"
    fi

    # Also add to lifetime concepts_seen if new — and flag for micro-lesson
    LIFETIME_SEEN=$(jq --arg tech "$TECH" '.concepts_seen | index($tech)' "$PROFILE_FILE")
    if [ "$LIFETIME_SEEN" = "null" ]; then
      UPDATED=$(jq --arg tech "$TECH" '.concepts_seen += [$tech]' "$PROFILE_FILE")
      echo "$UPDATED" > "$PROFILE_FILE"
      IS_FIRST_EVER="true"
    fi
  fi

  # Skip non-educational file changes without consuming the session budget
  if [ "$TECH" = "other" ]; then
    echo "{}"
    exit 0
  fi

  # --- Rate limiting ---
  NOW=$(date +%s)

  # Read current session state (graceful default if missing)
  if [ -f "$SESSION_STATE" ]; then
    LAST_TRIGGER=$(jq -r '.last_trigger_time // 0' "$SESSION_STATE" 2>/dev/null || echo "0")
    TRIGGER_COUNT=$(jq -r '.trigger_count // 0' "$SESSION_STATE" 2>/dev/null || echo "0")
  else
    LAST_TRIGGER=0
    TRIGGER_COUNT=0
  fi

  # Enforce session cap (applies to everyone, including first-ever concepts)
  if [ "$TRIGGER_COUNT" -ge "$SESSION_CAP" ]; then
    echo "{}"
    exit 0
  fi

  # Enforce minimum interval — first-ever concepts bypass this check only
  ELAPSED=$(( NOW - LAST_TRIGGER ))
  if [ "$ELAPSED" -lt "$RATE_LIMIT_INTERVAL" ] && [ "$IS_FIRST_EVER" != "true" ]; then
    echo "{}"
    exit 0
  fi

  # Update session state
  NEW_COUNT=$(( TRIGGER_COUNT + 1 ))
  SESSION_START_VAL=""
  if [ -f "$SESSION_STATE" ]; then
    SESSION_START_VAL=$(jq -r '.session_start // ""' "$SESSION_STATE" 2>/dev/null || echo "")
  fi
  if [ -z "$SESSION_START_VAL" ]; then
    SESSION_START_VAL="$TIMESTAMP"
  fi

  jq -n \
    --argjson last "$NOW" \
    --argjson count "$NEW_COUNT" \
    --arg start "$SESSION_START_VAL" \
    '{"last_trigger_time": $last, "trigger_count": $count, "session_start": $start}' \
    > "$SESSION_STATE"

  # Build teaching context
  BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>/dev/null || echo "white")

  if [ "$IS_FIRST_EVER" = "true" ]; then
    # First-time encounter: micro-lesson about the technology
    CONTEXT="🥋 CodeSensei micro-lesson trigger: The user just encountered '$TECH' for the FIRST TIME (file: $FILE_PATH). Their belt level is '$BELT'. Provide a brief 2-sentence explanation of what $TECH is and why it matters for their project. Adapt language to their belt level. Keep it concise and non-intrusive — weave it naturally into your response, don't stop everything for a lecture."
  else
    # Already-seen technology: inline insight about the specific change
    CONTEXT="🥋 CodeSensei inline insight: Claude just used '$TOOL_NAME' on '$FILE_PATH' ($TECH). The user's belt level is '$BELT'. Provide a brief 1-2 sentence explanation of what this change does and why, adapted to their belt level. Keep it natural and non-intrusive — weave it into your response as a quick teaching moment."
  fi

  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$CONTEXT\"}}"
fi

exit 0
