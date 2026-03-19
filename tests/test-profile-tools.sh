#!/bin/bash
# CodeSensei — Profile Tools Regression Tests
# Covers doctor/import scripts and secret redaction in command logging.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"

PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1: $2"; }

cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

setup_profile() {
  rm -rf "$TEST_HOME/.code-sensei"
  mkdir -p "$TEST_HOME/.code-sensei"
  cat > "$TEST_HOME/.code-sensei/profile.json" <<'PROFILE'
{
  "version": "1.0.0",
  "belt": "yellow",
  "xp": 125,
  "session_concepts": [],
  "concepts_seen": ["html"],
  "concepts_mastered": ["html"],
  "streak": {"current": 3, "longest": 3, "last_session_date": "2026-03-18"},
  "quizzes": {"total": 4, "correct": 3, "current_streak": 2, "longest_streak": 2},
  "quiz_history": []
}
PROFILE
}

create_wrapped_export() {
  local export_file="$1"
  cat > "$export_file" <<'EXPORT'
{
  "schema_version": "1.0",
  "exported_at": "2026-03-19T12:00:00Z",
  "plugin_version": "1.1.0",
  "profile": {
    "version": "1.0.0",
    "belt": "green",
    "xp": 3800,
    "session_concepts": [],
    "concepts_seen": ["html", "css", "js-basics"],
    "concepts_mastered": ["html", "css"],
    "streak": {"current": 9, "longest": 9, "last_session_date": "2026-03-19"},
    "quizzes": {"total": 18, "correct": 14, "current_streak": 5, "longest_streak": 6},
    "quiz_history": []
  }
}
EXPORT
}

echo ""
echo "━━━ CodeSensei Profile Tools Tests ━━━"
echo ""

# ============================================================
# TEST GROUP 1: doctor.sh
# ============================================================
echo "▸ doctor.sh"

rm -rf "$TEST_HOME/.code-sensei"
OUTPUT=$(bash "$SCRIPT_DIR/scripts/doctor.sh")

if echo "$OUTPUT" | jq . >/dev/null 2>&1; then
  pass "doctor output is valid JSON"
else
  fail "doctor output is valid JSON" "got: $OUTPUT"
fi

STATUS=$(echo "$OUTPUT" | jq -r '.status')
PROFILE_EXISTS=$(echo "$OUTPUT" | jq -r '.profile.exists')
COMMANDS_DETECTED=$(echo "$OUTPUT" | jq -r '.checks.commands_detected')
if [ "$STATUS" = "warn" ] && [ "$PROFILE_EXISTS" = "false" ] && [ "$COMMANDS_DETECTED" -ge 10 ]; then
  pass "doctor reports missing profile but valid plugin setup"
else
  fail "doctor reports missing profile but valid plugin setup" "status=$STATUS profile_exists=$PROFILE_EXISTS commands=$COMMANDS_DETECTED"
fi

echo ""

# ============================================================
# TEST GROUP 2: import-profile.sh
# ============================================================
echo "▸ import-profile.sh"

setup_profile
EXPORT_FILE="$TEST_HOME/code-sensei-export.json"
create_wrapped_export "$EXPORT_FILE"

PREVIEW=$(bash "$SCRIPT_DIR/scripts/import-profile.sh" "$EXPORT_FILE")
PREVIEW_STATUS=$(echo "$PREVIEW" | jq -r '.status')
TARGET_BELT=$(echo "$PREVIEW" | jq -r '.target_summary.belt')
CURRENT_BELT=$(echo "$PREVIEW" | jq -r '.current_summary.belt')
if [ "$PREVIEW_STATUS" = "preview" ] && [ "$TARGET_BELT" = "green" ] && [ "$CURRENT_BELT" = "yellow" ]; then
  pass "import preview shows target and current profile summaries"
else
  fail "import preview shows target and current profile summaries" "status=$PREVIEW_STATUS target=$TARGET_BELT current=$CURRENT_BELT"
fi

APPLY=$(bash "$SCRIPT_DIR/scripts/import-profile.sh" --apply "$EXPORT_FILE")
APPLY_STATUS=$(echo "$APPLY" | jq -r '.status')
IMPORTED_BELT=$(jq -r '.belt' "$TEST_HOME/.code-sensei/profile.json")
if [ "$APPLY_STATUS" = "imported" ] && [ "$IMPORTED_BELT" = "green" ] && [ -f "$TEST_HOME/.code-sensei/profile.json.backup" ]; then
  pass "import apply writes profile and creates backup"
else
  fail "import apply writes profile and creates backup" "status=$APPLY_STATUS belt=$IMPORTED_BELT backup=$( [ -f "$TEST_HOME/.code-sensei/profile.json.backup" ] && echo yes || echo no )"
fi

echo ""

# ============================================================
# TEST GROUP 3: track-command.sh redaction
# ============================================================
echo "▸ track-command.sh redaction"

setup_profile
rm -f "$TEST_HOME/.code-sensei/session-commands.jsonl"
cat <<'JSON' | bash "$SCRIPT_DIR/scripts/track-command.sh" >/dev/null 2>&1
{"tool_input":{"command":"export OPENAI_API_KEY=sk-test-123 && curl -H \"Authorization: Bearer real-token\" https://user:secret@example.com --token cli-secret"}}
JSON

LOG_CONTENT=$(cat "$TEST_HOME/.code-sensei/session-commands.jsonl")
if echo "$LOG_CONTENT" | grep -q '\[REDACTED\]' && ! echo "$LOG_CONTENT" | grep -q 'sk-test-123' && ! echo "$LOG_CONTENT" | grep -q 'real-token' && ! echo "$LOG_CONTENT" | grep -q 'cli-secret' && ! echo "$LOG_CONTENT" | grep -q 'secret@example.com'; then
  pass "command log redacts sensitive values"
else
  fail "command log redacts sensitive values" "$LOG_CONTENT"
fi

echo ""
echo "━━━ Summary ━━━"
echo -e "Passed: ${GREEN}${PASS}${NC}"
echo -e "Failed: ${RED}${FAIL}${NC}"
echo ""

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
