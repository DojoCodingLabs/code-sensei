#!/bin/bash
# CodeSensei — Session Stop Hook
# Saves session data and shows a mini-recap prompt

PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
SESSION_LOG="$PROFILE_DIR/sessions.log"
SESSION_STATE="$PROFILE_DIR/session-state.json"
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

  # Clear session-specific data
  UPDATED=$(jq '.session_concepts = []' "$PROFILE_FILE")
  echo "$UPDATED" > "$PROFILE_FILE"

  # Show gentle reminder if they learned things but didn't recap
  if [ "$SESSION_CONCEPTS" -gt 0 ]; then
    echo "You encountered $SESSION_CONCEPTS new concepts this session! Use /code-sensei:recap next time for a full summary."
  fi
fi

# Clean up session state files
rm -f "$SESSION_STATE"
rm -f "$PROFILE_DIR/.jq-warned"

exit 0
