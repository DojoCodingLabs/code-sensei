#!/bin/bash
# CodeSensei -- Session Start Hook
# Loads user profile and updates streak on each Claude Code session start

SCRIPT_NAME="session-start"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"

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
TODAY=$(date -u +%Y-%m-%d)

ensure_profile_dir
if [ ! -d "$PROFILE_DIR" ]; then
  log_error "$SCRIPT_NAME" "Failed to create profile directory: $PROFILE_DIR"
  exit 0
fi

if [ ! -f "$PROFILE_FILE" ]; then
  CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if ! cat <<PROFILE | write_profile
{
  "version": "1.0.0",
  "plugin": "code-sensei",
  "brand": "Dojo Coding",
  "created_at": "$CREATED_AT",
  "belt": "white",
  "xp": 0,
  "streak": {
    "current": 1,
    "longest": 1,
    "last_session_date": "$TODAY"
  },
  "quizzes": {
    "total": 0,
    "correct": 0,
    "current_streak": 0,
    "longest_streak": 0
  },
  "concepts_seen": [],
  "concepts_mastered": [],
  "skills_progress": {},
  "quiz_history": [],
  "sessions": {
    "total": 1,
    "first_session": "$TODAY",
    "last_session": "$TODAY"
  },
  "achievements": [
    {
      "id": "first-session",
      "name": "First Steps",
      "description": "Started your first CodeSensei session",
      "earned_at": "$CREATED_AT"
    }
  ],
  "preferences": {
    "difficulty": "auto",
    "analogy_domain": null,
    "show_hints": true
  },
  "session_concepts": []
}
PROFILE
  then
    log_error "$SCRIPT_NAME" "Failed to write default profile to $PROFILE_FILE"
    exit 0
  fi

  echo "Welcome to CodeSensei by Dojo Coding! Use /code-sensei:progress to get started."
  exit 0
fi

if ! check_jq "$SCRIPT_NAME"; then
  exit 0
fi

LAST_SESSION=$(jq -r '.streak.last_session_date // ""' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading last_session_date: $LAST_SESSION"
  exit 0
fi

CURRENT_STREAK=$(jq -r '.streak.current // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading streak.current: $CURRENT_STREAK"
  exit 0
fi

LONGEST_STREAK=$(jq -r '.streak.longest // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading streak.longest: $LONGEST_STREAK"
  exit 0
fi

TOTAL_SESSIONS=$(jq -r '.sessions.total // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading sessions.total: $TOTAL_SESSIONS"
  exit 0
fi

if [ "$LAST_SESSION" = "$TODAY" ]; then
  NEW_STREAK=$CURRENT_STREAK
elif [ -n "$LAST_SESSION" ]; then
  YESTERDAY=$(date -u -d "yesterday" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d 2>/dev/null)
  if [ -z "$YESTERDAY" ]; then
    log_error "$SCRIPT_NAME" "Failed to compute yesterday's date; resetting streak to 1"
    YESTERDAY=""
  fi

  if [ "$LAST_SESSION" = "$YESTERDAY" ]; then
    NEW_STREAK=$((CURRENT_STREAK + 1))
  else
    NEW_STREAK=1
  fi
else
  NEW_STREAK=1
fi

if [ "$NEW_STREAK" -gt "$LONGEST_STREAK" ]; then
  NEW_LONGEST=$NEW_STREAK
else
  NEW_LONGEST=$LONGEST_STREAK
fi

if ! update_profile \
  --arg today "$TODAY" \
  --argjson streak "$NEW_STREAK" \
  --argjson longest "$NEW_LONGEST" \
  --argjson sessions "$((TOTAL_SESSIONS + 1))" \
  '.streak.current = $streak |
   .streak.longest = $longest |
   .streak.last_session_date = $today |
   .sessions.total = $sessions |
   .sessions.last_session = $today |
   .session_concepts = []'
then
  log_error "$SCRIPT_NAME" "Failed updating profile during session start"
  exit 0
fi

if ! printf '%s %s session_start\n' "$TODAY" "$(date -u +%H:%M:%S)" >> "$SESSION_LOG" 2>&1; then
  log_error "$SCRIPT_NAME" "Failed to write to session log: $SESSION_LOG"
fi

if [ "$NEW_STREAK" -ge 7 ] && [ "$NEW_STREAK" != "$CURRENT_STREAK" ]; then
  echo "$NEW_STREAK-day streak! Consistency is the Dojo Way."
fi

exit 0
