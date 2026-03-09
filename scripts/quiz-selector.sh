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

PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
QUIZ_BANK="$PLUGIN_ROOT/data/quiz-bank.json"

# Default output if we can't determine anything
DEFAULT_OUTPUT='{"mode":"dynamic","concept":null,"reason":"No profile data available","static_question":null,"belt":"white","quiz_format":"multiple_choice"}'

select_static_question() {
  local concept="$1"

  jq -c \
    --arg concept "$concept" \
    --arg belt "$BELT" \
    --arg format "$QUIZ_FORMAT" '
      def rank($value):
        if $value == "white" then 0
        elif $value == "yellow" then 1
        elif $value == "orange" then 2
        elif $value == "green" then 3
        elif $value == "blue" then 4
        elif $value == "brown" then 5
        elif $value == "black" then 6
        else -1
        end;
      (.quizzes[$concept] // []) as $questions |
      (($questions | map(select(rank(.belt) >= 0 and rank(.belt) <= rank($belt) and ((.format // "multiple_choice") == $format))) | first) //
       ($questions | map(select(rank(.belt) >= 0 and rank(.belt) <= rank($belt))) | first) //
       null)
    ' "$QUIZ_BANK"
}

if ! command -v jq &> /dev/null; then
  echo "$DEFAULT_OUTPUT"
  exit 0
fi

if [ ! -f "$PROFILE_FILE" ]; then
  echo "$DEFAULT_OUTPUT"
  exit 0
fi

# Read profile data
BELT=$(jq -r '.belt // "white"' "$PROFILE_FILE")
QUIZ_HISTORY=$(jq -c '.quiz_history // []' "$PROFILE_FILE")
CONCEPTS_SEEN=$(jq -c '.concepts_seen // []' "$PROFILE_FILE")
SESSION_CONCEPTS=$(jq -c '.session_concepts // []' "$PROFILE_FILE")
TOTAL_QUIZZES=$(jq -r '.quizzes.total // 0' "$PROFILE_FILE")
CORRECT_QUIZZES=$(jq -r '.quizzes.correct // 0' "$PROFILE_FILE")

TODAY=$(date -u +%Y-%m-%d)
NOW_EPOCH=$(date +%s)

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
  WRONG_CONCEPTS=$(echo "$QUIZ_HISTORY" | jq -c '
    [.[] | select(.result == "incorrect")] |
    group_by(.concept) |
    map({
      concept: .[0].concept,
      wrong_count: length,
      last_wrong: (sort_by(.timestamp) | last | .timestamp),
      total_attempts: 0
    })
  ')

  # For each wrong concept, check if it's due for review
  for ROW in $(echo "$WRONG_CONCEPTS" | jq -c '.[]'); do
    CONCEPT=$(echo "$ROW" | jq -r '.concept')
    WRONG_COUNT=$(echo "$ROW" | jq -r '.wrong_count')
    LAST_WRONG=$(echo "$ROW" | jq -r '.last_wrong')

    # Calculate days since last wrong answer
    LAST_WRONG_DATE=$(echo "$LAST_WRONG" | cut -d'T' -f1)
    LAST_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_WRONG_DATE" +%s 2>/dev/null || date -d "$LAST_WRONG_DATE" +%s 2>/dev/null)
    if [ -n "$LAST_EPOCH" ]; then
      DAYS_SINCE=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
    else
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
    CORRECT_SINCE=$(echo "$QUIZ_HISTORY" | jq --arg c "$CONCEPT" --arg lw "$LAST_WRONG" '
      [.[] | select(.concept == $c and .result == "correct" and .timestamp > $lw)] | length
    ')

    if [ "$DAYS_SINCE" -ge "$REVIEW_INTERVAL" ] && [ "$CORRECT_SINCE" -lt 3 ]; then
      SPACED_REP_CONCEPT="$CONCEPT"
      SPACED_REP_REASON="You missed '$CONCEPT' $WRONG_COUNT time(s). Revisiting after $DAYS_SINCE days for reinforcement."
      break
    fi
  done
fi

# If spaced repetition found a concept, check for a static question
if [ -n "$SPACED_REP_CONCEPT" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(select_static_question "$SPACED_REP_CONCEPT")

  if [ "$STATIC_Q" != "null" ] && [ -n "$STATIC_Q" ]; then
    echo "{\"mode\":\"spaced_repetition\",\"concept\":\"$SPACED_REP_CONCEPT\",\"reason\":\"$SPACED_REP_REASON\",\"static_question\":$STATIC_Q,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
    exit 0
  else
    echo "{\"mode\":\"spaced_repetition\",\"concept\":\"$SPACED_REP_CONCEPT\",\"reason\":\"$SPACED_REP_REASON\",\"static_question\":null,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
    exit 0
  fi
fi

# ─── PRIORITY 2: Unquizzed session concepts ───
# Concepts from this session that haven't been quizzed yet
UNQUIZZED_CONCEPT=""
if [ "$SESSION_CONCEPTS" != "[]" ]; then
  for CONCEPT in $(echo "$SESSION_CONCEPTS" | jq -r '.[]'); do
    BEEN_QUIZZED=$(echo "$QUIZ_HISTORY" | jq --arg c "$CONCEPT" '[.[] | select(.concept == $c)] | length')
    if [ "$BEEN_QUIZZED" -eq 0 ]; then
      UNQUIZZED_CONCEPT="$CONCEPT"
      break
    fi
  done
fi

if [ -n "$UNQUIZZED_CONCEPT" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(select_static_question "$UNQUIZZED_CONCEPT")

  if [ "$STATIC_Q" != "null" ] && [ -n "$STATIC_Q" ]; then
    echo "{\"mode\":\"static\",\"concept\":\"$UNQUIZZED_CONCEPT\",\"reason\":\"New concept from this session — not yet quizzed.\",\"static_question\":$STATIC_Q,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
    exit 0
  else
    echo "{\"mode\":\"dynamic\",\"concept\":\"$UNQUIZZED_CONCEPT\",\"reason\":\"New concept from this session — no static question available, generate dynamically.\",\"static_question\":null,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
    exit 0
  fi
fi

# ─── PRIORITY 3: Least-quizzed lifetime concepts ───
# Concepts seen but quizzed the fewest times
LEAST_QUIZZED=""
if [ "$CONCEPTS_SEEN" != "[]" ]; then
  LEAST_QUIZZED=$(jq -r --argjson history "$QUIZ_HISTORY" '
    .[] as $concept |
    ($history | [.[] | select(.concept == $concept)] | length) as $count |
    {concept: $concept, count: $count}
  ' <<< "$CONCEPTS_SEEN" | jq -s 'sort_by(.count) | first | .concept // null' 2>/dev/null)
fi

if [ -n "$LEAST_QUIZZED" ] && [ "$LEAST_QUIZZED" != "null" ] && [ -f "$QUIZ_BANK" ]; then
  STATIC_Q=$(select_static_question "$LEAST_QUIZZED")

  echo "{\"mode\":\"static\",\"concept\":\"$LEAST_QUIZZED\",\"reason\":\"Reinforcing least-practiced concept.\",\"static_question\":$STATIC_Q,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
  exit 0
fi

# ─── FALLBACK: Dynamic generation ───
echo "{\"mode\":\"dynamic\",\"concept\":null,\"reason\":\"No specific concept to target — generate from current session context.\",\"static_question\":null,\"belt\":\"$BELT\",\"quiz_format\":\"$QUIZ_FORMAT\"}"
exit 0
