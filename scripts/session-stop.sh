#!/bin/bash
# CodeSensei — Session Stop Hook
# Saves session data and shows a mini-recap prompt

# Resolve lib path relative to this script's location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

SESSION_LOG="${PROFILE_DIR}/sessions.log"
TODAY=$(date -u +%Y-%m-%d)

if [ ! -f "$PROFILE_FILE" ]; then
  exit 0
fi

if command -v jq &> /dev/null; then
  # Count concepts learned this session
  SESSION_CONCEPTS=$(jq -r '.session_concepts | length // 0' "$PROFILE_FILE")
  XP=$(jq -r '.xp // 0' "$PROFILE_FILE")
  BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE")
  STREAK=$(jq -r '.streak.current // 0' "$PROFILE_FILE")

  # Log session end
  echo "$TODAY $(date -u +%H:%M:%S) session_stop concepts=$SESSION_CONCEPTS xp=$XP belt=$BELT" >> "$SESSION_LOG"

  # Clear session-specific data atomically
  update_profile '.session_concepts = []'

  # Archive pending lessons from this session
  PENDING_DIR="${PROFILE_DIR}/pending-lessons"
  ARCHIVE_DIR="${PROFILE_DIR}/lessons-archive"
  if [ -d "$PENDING_DIR" ] && [ "$(ls -A "$PENDING_DIR" 2>/dev/null)" ]; then
    mkdir -p "$ARCHIVE_DIR"
    ARCHIVE_FILE="${ARCHIVE_DIR}/${TODAY}.jsonl"
    # Concatenate all pending lesson files into the daily archive
    for f in "$PENDING_DIR"/*.json; do
      [ -f "$f" ] && cat "$f" >> "$ARCHIVE_FILE"
    done
    # Clear the pending queue
    rm -f "$PENDING_DIR"/*.json

    # Cap archive size: keep only last 30 days of archives (~1MB)
    find "$ARCHIVE_DIR" -name "*.jsonl" -type f | sort | head -n -30 | xargs -r rm -f
  fi

  # Show gentle reminder if they learned things but didn't recap
  if [ "$SESSION_CONCEPTS" -gt 0 ]; then
    echo "You encountered $SESSION_CONCEPTS new concepts this session! Use /code-sensei:recap next time for a full summary."
  fi
fi

exit 0
