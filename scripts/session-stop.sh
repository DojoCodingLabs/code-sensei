#!/bin/bash
# CodeSensei -- Session Stop Hook
# Saves session data and shows a mini-recap prompt

SCRIPT_NAME="session-stop"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"
# shellcheck source=lib/log-helpers.sh
source "${SCRIPT_DIR}/lib/log-helpers.sh"

LIB_DIR="${SCRIPT_DIR}/lib"
if [ -f "${LIB_DIR}/error-handling.sh" ]; then
  # shellcheck source=lib/error-handling.sh
  source "${LIB_DIR}/error-handling.sh"
else
  LOG_FILE="${PROFILE_DIR}/error.log"
  log_error() { printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')" "${1:-unknown}" "$2" >> "$LOG_FILE" 2>/dev/null; }
  check_jq() { command -v jq &>/dev/null; }
fi

SESSION_LOG="${PROFILE_DIR}/sessions.log"
SESSION_LOG_MAX_LINES=500
SESSION_STATE="${PROFILE_DIR}/session-state.json"
TODAY=$(date -u +%Y-%m-%d)

if [ ! -f "$PROFILE_FILE" ]; then
  exit 0
fi

if ! check_jq "$SCRIPT_NAME"; then
  exit 0
fi

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

if ! printf '%s %s session_stop concepts=%s xp=%s belt=%s\n' \
  "$TODAY" "$(date -u +%H:%M:%S)" "$SESSION_CONCEPTS" "$XP" "$BELT" >> "$SESSION_LOG" 2>&1
then
  log_error "$SCRIPT_NAME" "Failed to write to session log: $SESSION_LOG"
fi
trim_log_file "$SESSION_LOG" "$SESSION_LOG_MAX_LINES"

if ! update_profile '.session_concepts = []'; then
  log_error "$SCRIPT_NAME" "Failed clearing session_concepts during session stop"
  exit 0
fi

if [ "$SESSION_CONCEPTS" -gt 0 ]; then
  echo "You encountered $SESSION_CONCEPTS new concepts this session! Use /code-sensei:recap next time for a full summary."
fi

# Archive pending lessons from this session (DOJ-2436)
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

  # Cap archive size: keep only the latest 30 daily archives
  ARCHIVE_COUNT=$(find "$ARCHIVE_DIR" -name "*.jsonl" -type f | wc -l | tr -d ' ')
  if [ "$ARCHIVE_COUNT" -gt 30 ]; then
    REMOVE_COUNT=$((ARCHIVE_COUNT - 30))
    find "$ARCHIVE_DIR" -name "*.jsonl" -type f | sort | head -n "$REMOVE_COUNT" | while IFS= read -r archive_file; do
      [ -n "$archive_file" ] && rm -f "$archive_file"
    done
  fi
fi

rm -f "$SESSION_STATE"
rm -f "$PROFILE_DIR/.jq-warned"

exit 0
