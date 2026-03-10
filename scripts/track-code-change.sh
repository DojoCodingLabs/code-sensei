#!/bin/bash
# CodeSensei — Track Code Change Hook (PostToolUse: Write|Edit|MultiEdit)
# Records what files Claude creates or modifies for contextual teaching
# This data is used by /explain and /recap to know what happened

# Resolve lib path relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

CHANGES_LOG="${PROFILE_DIR}/session-changes.jsonl"

# Read hook input from stdin
INPUT=$(cat)

ensure_profile_dir

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

  # Track technology in session and lifetime concepts — single atomic jq pass
  IS_FIRST_EVER="false"
  if [ -f "$PROFILE_FILE" ] && [ "$TECH" != "other" ]; then
    # Read current state once to determine what flags to set
    ALREADY_IN_SESSION=$(jq --arg tech "$TECH" '.session_concepts | index($tech)' "$PROFILE_FILE")
    ALREADY_IN_LIFETIME=$(jq --arg tech "$TECH" '.concepts_seen | index($tech)' "$PROFILE_FILE")

    if [ "$ALREADY_IN_LIFETIME" = "null" ]; then
      IS_FIRST_EVER="true"
      # Add to both session_concepts and concepts_seen in one pass
      update_profile --arg tech "$TECH" '
        .session_concepts += (if (.session_concepts | index($tech)) == null then [$tech] else [] end) |
        .concepts_seen   += (if (.concepts_seen   | index($tech)) == null then [$tech] else [] end)
      '
    elif [ "$ALREADY_IN_SESSION" = "null" ]; then
      # New to session only — single pass
      update_profile --arg tech "$TECH" '
        .session_concepts += [$tech]
      '
    fi
  fi

  # Always inject teaching context after code changes
  BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>/dev/null || echo "white")

  # --- Pending lessons queue (durable, per-lesson file to avoid append races) ---
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
  cat > "$LESSON_FILE" <<LESSON_EOF
{"timestamp":"$TIMESTAMP","type":"$LESSON_TYPE","tech":"$TECH","file":"$FILE_PATH","tool":"$TOOL_NAME","belt":"$BELT","firstEncounter":$IS_FIRST_EVER}
LESSON_EOF

  # --- Minimal delegation hint (not full teaching content) ---
  CONTEXT="CodeSensei: New teaching moment detected ($TECH, $FILE_PATH). If the user is not in the middle of a complex task, use the Task tool to invoke the 'sensei' agent. Pass it the latest pending lesson from ~/.code-sensei/pending-lessons/."

  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":\"$CONTEXT\"}}"
fi

exit 0
