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

  # Show gentle reminder if they learned things but didn't recap
  if [ "$SESSION_CONCEPTS" -gt 0 ]; then
    echo "You encountered $SESSION_CONCEPTS new concepts this session! Use /code-sensei:recap next time for a full summary."
  fi
fi

exit 0
