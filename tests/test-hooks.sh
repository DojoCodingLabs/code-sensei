#!/bin/bash
# CodeSensei — Hook Regression Tests
# Validates that hook scripts produce valid JSON output and write
# structured pending lessons to the queue directory.
#
# Usage: bash tests/test-hooks.sh
# Requirements: jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"

PASS=0
FAIL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

pass() { PASS=$((PASS + 1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL + 1)); echo -e "  ${RED}✗${NC} $1: $2"; }

cleanup() {
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT

# --- Setup: create a minimal profile ---
setup_profile() {
  mkdir -p "$TEST_HOME/.code-sensei"
  cat > "$TEST_HOME/.code-sensei/profile.json" <<'PROFILE'
{
  "belt": "yellow",
  "xp": 100,
  "session_concepts": [],
  "concepts_seen": ["html"],
  "streak": {"current": 3}
}
PROFILE
}

echo ""
echo "━━━ CodeSensei Hook Regression Tests ━━━"
echo ""

# ============================================================
# TEST GROUP 1: track-code-change.sh
# ============================================================
echo "▸ track-code-change.sh"

# Test 1.1: Output is valid JSON
setup_profile
OUTPUT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"src/App.tsx"}}' \
  | bash "$SCRIPT_DIR/scripts/track-code-change.sh" 2>/dev/null)

if echo "$OUTPUT" | jq . > /dev/null 2>&1; then
  pass "stdout is valid JSON"
else
  fail "stdout is valid JSON" "got: $OUTPUT"
fi

# Test 1.2: Output contains hookSpecificOutput with PostToolUse event
EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName')
if [ "$EVENT" = "PostToolUse" ]; then
  pass "hookEventName is PostToolUse"
else
  fail "hookEventName is PostToolUse" "got: $EVENT"
fi

# Test 1.3: additionalContext is a delegation hint (not verbose teaching)
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')
if echo "$CONTEXT" | grep -q "Task tool" && echo "$CONTEXT" | grep -q "sensei"; then
  pass "additionalContext is a delegation hint (mentions Task tool + sensei)"
else
  fail "additionalContext is a delegation hint" "got: $CONTEXT"
fi

# Test 1.4: additionalContext does NOT contain old verbose teaching patterns
if echo "$CONTEXT" | grep -q "Provide a brief"; then
  fail "additionalContext has no verbose teaching" "still contains 'Provide a brief'"
else
  pass "additionalContext has no verbose teaching content"
fi

# Test 1.5: Pending lesson file was created
LESSON_COUNT=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" 2>/dev/null | wc -l)
if [ "$LESSON_COUNT" -ge 1 ]; then
  pass "pending lesson file created ($LESSON_COUNT file(s))"
else
  fail "pending lesson file created" "found $LESSON_COUNT files"
fi

# Test 1.6: Pending lesson file is valid JSON
LESSON_FILE=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" | head -1)
if jq . "$LESSON_FILE" > /dev/null 2>&1; then
  pass "pending lesson file is valid JSON"
else
  fail "pending lesson file is valid JSON" "file: $LESSON_FILE"
fi

# Test 1.7: Pending lesson has required fields
LESSON_TYPE=$(jq -r '.type' "$LESSON_FILE")
LESSON_TECH=$(jq -r '.tech' "$LESSON_FILE")
LESSON_BELT=$(jq -r '.belt' "$LESSON_FILE")
if [ "$LESSON_TYPE" != "null" ] && [ "$LESSON_TECH" != "null" ] && [ "$LESSON_BELT" != "null" ]; then
  pass "pending lesson has type=$LESSON_TYPE, tech=$LESSON_TECH, belt=$LESSON_BELT"
else
  fail "pending lesson has required fields" "type=$LESSON_TYPE tech=$LESSON_TECH belt=$LESSON_BELT"
fi

# Test 1.8: First encounter for new tech creates micro-lesson
setup_profile
rm -rf "$TEST_HOME/.code-sensei/pending-lessons"
echo '{"tool_name":"Write","tool_input":{"file_path":"main.py"}}' \
  | bash "$SCRIPT_DIR/scripts/track-code-change.sh" > /dev/null 2>&1
LESSON_FILE=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" | head -1)
LESSON_TYPE=$(jq -r '.type' "$LESSON_FILE")
FIRST=$(jq -r '.firstEncounter' "$LESSON_FILE")
if [ "$LESSON_TYPE" = "micro-lesson" ] && [ "$FIRST" = "true" ]; then
  pass "first encounter creates micro-lesson with firstEncounter=true"
else
  fail "first encounter creates micro-lesson" "type=$LESSON_TYPE firstEncounter=$FIRST"
fi

# Test 1.9: Already-seen tech creates inline-insight
setup_profile
rm -rf "$TEST_HOME/.code-sensei/pending-lessons"
echo '{"tool_name":"Edit","tool_input":{"file_path":"index.html"}}' \
  | bash "$SCRIPT_DIR/scripts/track-code-change.sh" > /dev/null 2>&1
LESSON_FILE=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" | head -1)
LESSON_TYPE=$(jq -r '.type' "$LESSON_FILE")
FIRST=$(jq -r '.firstEncounter' "$LESSON_FILE")
if [ "$LESSON_TYPE" = "inline-insight" ] && [ "$FIRST" = "false" ]; then
  pass "already-seen tech creates inline-insight with firstEncounter=false"
else
  fail "already-seen tech creates inline-insight" "type=$LESSON_TYPE firstEncounter=$FIRST"
fi

echo ""

# ============================================================
# TEST GROUP 2: track-command.sh
# ============================================================
echo "▸ track-command.sh"

setup_profile
rm -rf "$TEST_HOME/.code-sensei/pending-lessons"

# Test 2.1: Output is valid JSON
OUTPUT=$(echo '{"tool_input":{"command":"npm install express"}}' \
  | bash "$SCRIPT_DIR/scripts/track-command.sh" 2>/dev/null)

if echo "$OUTPUT" | jq . > /dev/null 2>&1; then
  pass "stdout is valid JSON"
else
  fail "stdout is valid JSON" "got: $OUTPUT"
fi

# Test 2.2: additionalContext is delegation hint
CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext')
if echo "$CONTEXT" | grep -q "Task tool" && echo "$CONTEXT" | grep -q "sensei"; then
  pass "additionalContext is a delegation hint"
else
  fail "additionalContext is a delegation hint" "got: $CONTEXT"
fi

# Test 2.3: Pending lesson file for command
LESSON_FILE=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" | head -1)
if jq . "$LESSON_FILE" > /dev/null 2>&1; then
  pass "pending lesson file is valid JSON"
else
  fail "pending lesson file is valid JSON" "file: $LESSON_FILE"
fi

# Test 2.4: Command lesson has concept field
CONCEPT=$(jq -r '.concept' "$LESSON_FILE")
if [ "$CONCEPT" = "package-management" ]; then
  pass "command lesson detected concept=package-management"
else
  fail "command lesson detected concept" "got: $CONCEPT"
fi

echo ""

# ============================================================
# TEST GROUP 3: session-stop.sh (cleanup)
# ============================================================
echo "▸ session-stop.sh (pending lessons cleanup)"

setup_profile
rm -rf "$TEST_HOME/.code-sensei/pending-lessons" "$TEST_HOME/.code-sensei/lessons-archive"

# Create some pending lessons
mkdir -p "$TEST_HOME/.code-sensei/pending-lessons"
echo '{"timestamp":"2026-03-09T12:00:00Z","type":"micro-lesson","tech":"react"}' \
  > "$TEST_HOME/.code-sensei/pending-lessons/test1.json"
echo '{"timestamp":"2026-03-09T12:01:00Z","type":"inline-insight","tech":"css"}' \
  > "$TEST_HOME/.code-sensei/pending-lessons/test2.json"

# Add a session concept so we can verify the full flow
jq '.session_concepts = ["react","css"]' "$TEST_HOME/.code-sensei/profile.json" \
  | tee "$TEST_HOME/.code-sensei/profile.json.tmp" > /dev/null \
  && mv "$TEST_HOME/.code-sensei/profile.json.tmp" "$TEST_HOME/.code-sensei/profile.json"

# Run session-stop
bash "$SCRIPT_DIR/scripts/session-stop.sh" > /dev/null 2>&1

# Test 3.1: Pending lessons directory was cleaned
REMAINING=$(find "$TEST_HOME/.code-sensei/pending-lessons" -name "*.json" 2>/dev/null | wc -l)
if [ "$REMAINING" -eq 0 ]; then
  pass "pending lessons cleaned after session stop"
else
  fail "pending lessons cleaned" "$REMAINING files remaining"
fi

# Test 3.2: Archive file was created
TODAY=$(date -u +%Y-%m-%d)
ARCHIVE_FILE="$TEST_HOME/.code-sensei/lessons-archive/${TODAY}.jsonl"
if [ -f "$ARCHIVE_FILE" ]; then
  pass "archive file created at lessons-archive/${TODAY}.jsonl"
else
  fail "archive file created" "file not found: $ARCHIVE_FILE"
fi

# Test 3.3: Archive contains the lessons (each line is valid JSON)
ARCHIVE_LINES=$(wc -l < "$ARCHIVE_FILE")
VALID_JSON=0
while IFS= read -r line; do
  if echo "$line" | jq . > /dev/null 2>&1; then
    VALID_JSON=$((VALID_JSON + 1))
  fi
done < "$ARCHIVE_FILE"
if [ "$VALID_JSON" -eq "$ARCHIVE_LINES" ] && [ "$ARCHIVE_LINES" -ge 2 ]; then
  pass "archive has $ARCHIVE_LINES valid JSON lines"
else
  fail "archive has valid JSON lines" "total=$ARCHIVE_LINES valid=$VALID_JSON"
fi

echo ""

# ============================================================
# SUMMARY
# ============================================================
TOTAL=$((PASS + FAIL))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}All $TOTAL tests passed!${NC}"
else
  echo -e "${RED}$FAIL/$TOTAL tests failed${NC}"
fi
echo ""

exit "$FAIL"
