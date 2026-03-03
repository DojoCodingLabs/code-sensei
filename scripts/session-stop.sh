#!/bin/bash
# CodeSensei — Session Stop Hook
# Saves session data and shows a mini-recap prompt

SCRIPT_NAME="session-stop"
PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
SESSION_LOG="$PROFILE_DIR/sessions.log"
TODAY=$(date -u +%Y-%m-%d)

# Load shared error handling
LIB_DIR="$(dirname "$0")/lib"
if [ -f "$LIB_DIR/error-handling.sh" ]; then
  source "$LIB_DIR/error-handling.sh"
else
  LOG_FILE="${PROFILE_DIR}/error.log"
  log_error() { printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')" "${1:-unknown}" "$2" >> "$LOG_FILE" 2>/dev/null; }
  json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  check_jq() { command -v jq &>/dev/null; }
fi

if [ ! -f "$PROFILE_FILE" ]; then
  exit 0
fi

if ! check_jq "$SCRIPT_NAME"; then
  exit 0
fi

# Count concepts learned this session
SESSION_CONCEPTS=$(jq -r '.session_concepts | length // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading session_concepts length: $SESSION_CONCEPTS"
  SESSION_CONCEPTS=0
fi

XP=$(jq -r '.xp // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading xp: $XP"
  XP=0
fi

BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt: $BELT"
  BELT="white"
fi

STREAK=$(jq -r '.streak.current // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading streak: $STREAK"
  STREAK=0
fi

# Log session end
if ! printf '%s %s session_stop concepts=%s xp=%s belt=%s\n' \
    "$TODAY" "$(date -u +%H:%M:%S)" "$SESSION_CONCEPTS" "$XP" "$BELT" >> "$SESSION_LOG" 2>&1; then
  log_error "$SCRIPT_NAME" "Failed to write to session log: $SESSION_LOG"
fi

# Clear session-specific data atomically
UPDATED=$(jq '.session_concepts = []' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed clearing session_concepts: $UPDATED"
  exit 0
fi

TMPFILE=$(mktemp "${PROFILE_FILE}.XXXXXX" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "mktemp failed: $TMPFILE"
  exit 0
fi

printf '%s\n' "$UPDATED" > "$TMPFILE" && mv "$TMPFILE" "$PROFILE_FILE"
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "Failed to write updated profile (atomic mv)"
  rm -f "$TMPFILE"
  exit 0
fi

# Show gentle reminder if they learned things but didn't recap
if [ "$SESSION_CONCEPTS" -gt 0 ]; then
  echo "You encountered $SESSION_CONCEPTS new concepts this session! Use /code-sensei:recap next time for a full summary."
fi

exit 0
