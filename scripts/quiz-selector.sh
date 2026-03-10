#!/bin/bash
# CodeSensei — Quiz Selector (Spaced Repetition + Hybrid Static/Dynamic)
# Reads profile quiz_history, identifies concepts due for review,
# checks quiz-bank.json for matching static questions, and outputs
# a JSON recommendation for the quiz command.
#
# Output JSON format:
# {
#   "mode": "spaced_repetition" | "static" | "dynamic",
#   "concept": "concept-name",
#   "reason": "why this concept was selected",
#   "static_question": { ... } | null,
#   "belt": "current belt",
#   "quiz_format": "multiple_choice" | "free_response" | "code_prediction"
# }

SCRIPT_NAME="quiz-selector"
PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
QUIZ_BANK="$PLUGIN_ROOT/data/quiz-bank.json"

# Load shared error handling
LIB_DIR="$(dirname "$0")/lib"
if [ -f "$LIB_DIR/error-handling.sh" ]; then
  source "$LIB_DIR/error-handling.sh"
else
  LOG_FILE="${PROFILE_DIR}/error.log"
  log_error() { printf '[%s] [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')" "${1:-unknown}" "$2" >> "$LOG_FILE" 2>/dev/null; }
  json_escape() {
    local str="$1"
    if command -v jq &>/dev/null; then
      printf '%s' "$str" | jq -Rs '.'
    else
      printf '"%s"' "$(printf '%s' "$str" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    fi
  }
  check_jq() { command -v jq &>/dev/null; }
fi

# shellcheck source=scripts/lib/date-compat.sh
source "$PLUGIN_ROOT/scripts/lib/date-compat.sh"

# Default output if we can't determine anything
DEFAULT_OUTPUT='{"mode":"dynamic","concept":null,"reason":"No profile data available","static_question":null,"belt":"white","quiz_format":"multiple_choice"}'

if ! check_jq "$SCRIPT_NAME"; then
  echo "$DEFAULT_OUTPUT"
  exit 0
fi

if [ ! -f "$PROFILE_FILE" ]; then
  echo "$DEFAULT_OUTPUT"
  exit 0
fi

# Read profile data
BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading belt: $BELT"
  echo "$DEFAULT_OUTPUT"
  exit 0
fi

QUIZ_HISTORY=$(jq -c '.quiz_history // []' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading quiz_history: $QUIZ_HISTORY"
  QUIZ_HISTORY="[]"
fi

CONCEPTS_SEEN=$(jq -c '.concepts_seen // []' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading concepts_seen: $CONCEPTS_SEEN"
  CONCEPTS_SEEN="[]"
fi

SESSION_CONCEPTS=$(jq -c '.session_concepts // []' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading session_concepts: $SESSION_CONCEPTS"
  SESSION_CONCEPTS="[]"
fi

TOTAL_QUIZZES=$(jq -r '.quizzes.total // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading quizzes.total: $TOTAL_QUIZZES"
  TOTAL_QUIZZES=0
fi

CORRECT_QUIZZES=$(jq -r '.quizzes.correct // 0' "$PROFILE_FILE" 2>&1)
if [ $? -ne 0 ]; then
  log_error "$SCRIPT_NAME" "jq failed reading quizzes.correct: $CORRECT_QUIZZES"
  CORRECT_QUIZZES=0
fi

TODAY=$(date_today)
NOW_EPOCH=$(date_to_epoch "$TODAY")

# Determine quiz format based on belt level
# Orange Belt+ gets a mix of formats; lower belts get multiple choice
QUIZ_FORMAT="multiple_choice"
if [ "$BELT" = "orange" ] || [ "$BELT" = "green" ] || [ "$BELT" = "blue" ] || [ "$BELT" = "brown" ] || [ "$BELT" = "black" ]; then
  # Cycle through formats: every 3rd quiz is free-response, every 5th is code prediction
  QUIZ_NUM=$((TOTAL_QUIZZES + 1))
  if [ $((QUIZ_NUM % 5)) -eq 0 ]; then
    QUIZ_FORMAT="code_prediction"
  elif [ $((QUIZ_NUM % 3)) -eq 0 ]; then
    QUIZ_FORMAT="free_response"
  fi
fi

# ─── PRIORITY 1: Spaced Repetition (concepts the user got WRONG) ───
# Find concepts that were answered incorrectly and are due for review.
# Schedule: 1 day after first miss, 3 days after second, 7 days after third.

SPACED_REP_CONCEPT=""
SPACED_REP_REASON=""

if [ "$QUIZ_HISTORY" != "[]" ]; then
  # Get concepts that were answered incorrectly, with their last wrong date and wrong count
  WRONG_CONCEPTS=$(printf '%s' "$QUIZ_HISTORY" | jq -c '
    [.[] | select(.result == "incorrect")] |
    group_by(.concept) |
    map({
      concept: .[0].concept,
      wrong_count: length,
      last_wrong: (sort_by(.timestamp) | last | .timestamp),
      total_attempts: 0
    })
  ' 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed computing wrong concepts: $WRONG_CONCEPTS"
    WRONG_CONCEPTS="[]"
  fi

  # For each wrong concept, check if it's due for review
  for ROW in $(printf '%s' "$WRONG_CONCEPTS" | jq -c '.[]' 2>/dev/null); do
    CONCEPT=$(printf '%s' "$ROW" | jq -r '.concept' 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed reading concept from wrong row: $CONCEPT"
      continue
    fi

    WRONG_COUNT=$(printf '%s' "$ROW" | jq -r '.wrong_count' 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed reading wrong_count: $WRONG_COUNT"
      continue
    fi

    LAST_WRONG=$(printf '%s' "$ROW" | jq -r '.last_wrong' 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed reading last_wrong: $LAST_WRONG"
      continue
    fi

    # Calculate days since last wrong answer using cross-platform helpers
    LAST_WRONG_DATE=$(printf '%s' "$LAST_WRONG" | cut -d'T' -f1)
    LAST_EPOCH=$(date_to_epoch "$LAST_WRONG_DATE")
    if [ -n "$LAST_EPOCH" ] && [ "$LAST_EPOCH" != "0" ]; then
      DAYS_SINCE=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
    else
      log_error "$SCRIPT_NAME" "Could not parse date '$LAST_WRONG_DATE' for spaced repetition; defaulting days_since=999"
      DAYS_SINCE=999
    fi

    # Spaced repetition intervals: 1 day, 3 days, 7 days
    REVIEW_INTERVAL=1
    if [ "$WRONG_COUNT" -ge 3 ]; then
      REVIEW_INTERVAL=7
    elif [ "$WRONG_COUNT" -ge 2 ]; then
      REVIEW_INTERVAL=3
    fi

    # Check if enough time has passed and concept hasn't been mastered since
    CORRECT_SINCE=$(printf '%s' "$QUIZ_HISTORY" | jq --arg c "$CONCEPT" --arg lw "$LAST_WRONG" '
      [.[] | select(.concept == $c and .result == "correct" and .timestamp > $lw)] | length
    ' 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed computing correct_since for $CONCEPT: $CORRECT_SINCE"
      CORRECT_SINCE=0
    fi

    if [ "$DAYS_SINCE" -ge "$REVIEW_INTERVAL" ] && [ "$CORRECT_SINCE" -lt 3 ]; then
      SPACED_REP_CONCEPT="$CONCEPT"
      SPACED_REP_REASON="You missed '$CONCEPT' $WRONG_COUNT time(s). Revisiting after $DAYS_SINCE days for reinforcement."
      break
    fi
  done
fi

# If spaced repetition found a concept, check for a static question
if [ -n "$SPACED_REP_CONCEPT" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(jq -c --arg concept "$SPACED_REP_CONCEPT" --arg belt "$BELT" '
    .quizzes[$concept] // [] |
    map(select(.belt == $belt or .belt == "white")) |
    first // null
  ' "$QUIZ_BANK" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed reading static question for $SPACED_REP_CONCEPT: $STATIC_Q"
    STATIC_Q="null"
  fi

  ESCAPED_CONCEPT=$(json_escape "$SPACED_REP_CONCEPT")
  ESCAPED_REASON=$(json_escape "$SPACED_REP_REASON")
  ESCAPED_BELT=$(json_escape "$BELT")

  if [ "$STATIC_Q" != "null" ] && [ -n "$STATIC_Q" ]; then
    printf '{"mode":"spaced_repetition","concept":%s,"reason":%s,"static_question":%s,"belt":%s,"quiz_format":"%s"}\n' \
      "$ESCAPED_CONCEPT" "$ESCAPED_REASON" "$STATIC_Q" "$ESCAPED_BELT" "$QUIZ_FORMAT"
  else
    printf '{"mode":"spaced_repetition","concept":%s,"reason":%s,"static_question":null,"belt":%s,"quiz_format":"%s"}\n' \
      "$ESCAPED_CONCEPT" "$ESCAPED_REASON" "$ESCAPED_BELT" "$QUIZ_FORMAT"
  fi
  exit 0
fi

# ─── PRIORITY 2: Unquizzed session concepts ───
# Concepts from this session that haven't been quizzed yet
UNQUIZZED_CONCEPT=""
if [ "$SESSION_CONCEPTS" != "[]" ]; then
  for CONCEPT in $(printf '%s' "$SESSION_CONCEPTS" | jq -r '.[]' 2>/dev/null); do
    BEEN_QUIZZED=$(printf '%s' "$QUIZ_HISTORY" | jq --arg c "$CONCEPT" '[.[] | select(.concept == $c)] | length' 2>&1)
    if [ $? -ne 0 ]; then
      log_error "$SCRIPT_NAME" "jq failed checking quiz history for $CONCEPT: $BEEN_QUIZZED"
      continue
    fi
    if [ "$BEEN_QUIZZED" -eq 0 ]; then
      UNQUIZZED_CONCEPT="$CONCEPT"
      break
    fi
  done
fi

if [ -n "$UNQUIZZED_CONCEPT" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(jq -c --arg concept "$UNQUIZZED_CONCEPT" --arg belt "$BELT" '
    .quizzes[$concept] // [] |
    map(select(.belt == $belt or .belt == "white")) |
    first // null
  ' "$QUIZ_BANK" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed reading static question for $UNQUIZZED_CONCEPT: $STATIC_Q"
    STATIC_Q="null"
  fi

  ESCAPED_CONCEPT=$(json_escape "$UNQUIZZED_CONCEPT")
  ESCAPED_BELT=$(json_escape "$BELT")

  if [ "$STATIC_Q" != "null" ] && [ -n "$STATIC_Q" ]; then
    printf '{"mode":"static","concept":%s,"reason":"New concept from this session — not yet quizzed.","static_question":%s,"belt":%s,"quiz_format":"%s"}\n' \
      "$ESCAPED_CONCEPT" "$STATIC_Q" "$ESCAPED_BELT" "$QUIZ_FORMAT"
  else
    printf '{"mode":"dynamic","concept":%s,"reason":"New concept from this session — no static question available, generate dynamically.","static_question":null,"belt":%s,"quiz_format":"%s"}\n' \
      "$ESCAPED_CONCEPT" "$ESCAPED_BELT" "$QUIZ_FORMAT"
  fi
  exit 0
fi

# ─── PRIORITY 3: Least-quizzed lifetime concepts ───
# Concepts seen but quizzed the fewest times
LEAST_QUIZZED=""
if [ "$CONCEPTS_SEEN" != "[]" ]; then
  LEAST_QUIZZED=$(jq -r --argjson history "$QUIZ_HISTORY" '
    .[] as $concept |
    ($history | [.[] | select(.concept == $concept)] | length) as $count |
    {concept: $concept, count: $count}
  ' <<< "$CONCEPTS_SEEN" 2>&1 | jq -s 'sort_by(.count) | first | .concept // null' 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed computing least-quizzed concept: $LEAST_QUIZZED"
    LEAST_QUIZZED=""
  fi
fi

if [ -n "$LEAST_QUIZZED" ] && [ "$LEAST_QUIZZED" != "null" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(jq -c --arg concept "$LEAST_QUIZZED" --arg belt "$BELT" '
    .quizzes[$concept] // [] |
    map(select(.belt == $belt or .belt == "white")) |
    first // null
  ' "$QUIZ_BANK" 2>&1)
  if [ $? -ne 0 ]; then
    log_error "$SCRIPT_NAME" "jq failed reading static question for $LEAST_QUIZZED: $STATIC_Q"
    STATIC_Q="null"
  fi

  ESCAPED_CONCEPT=$(json_escape "$LEAST_QUIZZED")
  ESCAPED_BELT=$(json_escape "$BELT")

  printf '{"mode":"static","concept":%s,"reason":"Reinforcing least-practiced concept.","static_question":%s,"belt":%s,"quiz_format":"%s"}\n' \
    "$ESCAPED_CONCEPT" "$STATIC_Q" "$ESCAPED_BELT" "$QUIZ_FORMAT"
  exit 0
fi

# ─── FALLBACK: Dynamic generation ───
ESCAPED_BELT=$(json_escape "$BELT")
printf '{"mode":"dynamic","concept":null,"reason":"No specific concept to target — generate from current session context.","static_question":null,"belt":%s,"quiz_format":"%s"}\n' \
  "$ESCAPED_BELT" "$QUIZ_FORMAT"
exit 0
