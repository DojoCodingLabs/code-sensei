#!/bin/bash
# CodeSensei — Session Start Hook
# Loads user profile and updates streak on each Claude Code session start

SCRIPT_NAME="session-start"
PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
SESSION_LOG="$PROFILE_DIR/sessions.log"
TODAY=$(date -u +%Y-%m-%d)

# Load shared error handling
# shellcheck source=lib/error-handling.sh
LIB_DIR="$(dirname "$0")/lib"
if [ -f "$LIB_DIR/error-handling.sh" ]; then
  source "$LIB_DIR/error-handling.sh"
else
  # Minimal inline fallback if lib is missing
  LOG_FILE="${PROFILE_DIR}/error.log"
  log_error() { printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')" "${1:-unknown}" "$2" >> "$LOG_FILE" 2>/dev/null; }
  json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  check_jq() { command -v jq &>/dev/null; }
fi

# Create profile directory if it doesn't exist
if ! mkdir -p "$PROFILE_DIR" 2>&1 | grep -q .; then
  : # directory created or already exists
fi
if [ ! -d "$PROFILE_DIR" ]; then
  log_error "$SCRIPT_NAME" "Failed to create profile directory: $PROFILE_DIR"
  exit 0
fi

# Create default profile if none exists
if [ ! -f "$PROFILE_FILE" ]; then
  CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if ! cat > "$PROFILE_FILE" << PROFILE
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

# Profile exists — update streak and session count
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
TOTAL_SESSIONS=$(jq -r '.sessions.total // 0' "$PROFILE_FILE" 2>&1)

# Calculate streak
if [ "$LAST_SESSION" = "$TODAY" ]; then
  # Already logged today, no streak change
  NEW_STREAK=$CURRENT_STREAK
elif [ -n "$LAST_SESSION" ]; then
  # Check if last session was yesterday (handles both GNU and BSD date)
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

# Update longest streak
if [ "$NEW_STREAK" -gt "$LONGEST_STREAK" ]; then
  NEW_LONGEST=$NEW_STREAK
else
  NEW_LONGEST=$LONGEST_STREAK
fi

# Update profile atomically (temp file + mv)
UPDATED=$(jq \
  --arg today "$TODAY" \
  --argjson streak "$NEW_STREAK" \
  --argjson longest "$NEW_LONGEST" \
  --argjson sessions "$((TOTAL_SESSIONS + 1))" \
  '.streak.current = $streak |
   .streak.longest = $longest |
   .streak.last_session_date = $today |
   .sessions.total = $sessions |
   .sessions.last_session = $today |
   .session_concepts = []' \
  "$PROFILE_FILE" 2>&1)

if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed updating profile: $UPDATED"
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

# Log session
if ! printf '%s %s session_start\n' "$TODAY" "$(date -u +%H:%M:%S)" >> "$SESSION_LOG" 2>&1; then
  log_error "$SCRIPT_NAME" "Failed to write to session log: $SESSION_LOG"
fi

# Show streak info if notable
BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt after profile update: $BELT"
  BELT="white"
fi

if [ "$NEW_STREAK" -ge 7 ] && [ "$NEW_STREAK" != "$CURRENT_STREAK" ]; then
  echo "${NEW_STREAK}-day streak! Consistency is the Dojo Way."
fi

exit 0
