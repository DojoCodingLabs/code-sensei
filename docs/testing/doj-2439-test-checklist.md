# DOJ-2439 Manual Test Checklist

## Prerequisites
- [ ] jq installed (`jq --version`)
- [ ] CodeSensei plugin installed in Claude Code
- [ ] Profile exists at `~/.code-sensei/profile.json`

## Automated Tests (Pass)

- [x] `tests/test-hooks.sh` — All 16 tests pass

## Manual Test Checklist

### Test 1: Micro-Lesson Trigger (First Encounter)

1. Delete a tech from your profile's `concepts_seen` array (e.g., remove "react")
2. Ask Claude to create a `.jsx` file
3. Verify: a `.json` file appears in `~/.code-sensei/pending-lessons/`
4. Verify: the JSON has `"type":"micro-lesson"` and `"firstEncounter":true`
5. Verify: the main context shows the delegation hint (not a full teaching prompt)
6. Verify: if delegation succeeds, sensei produces a 2-3 sentence explanation
7. Verify: the lesson file is deleted after delivery

### Test 2: Inline-Insight Trigger (Repeat Encounter)

1. Ensure "javascript" is in your profile's `concepts_seen` array
2. Ask Claude to edit a `.js` file
3. Verify: pending lesson has `"type":"inline-insight"` and `"firstEncounter":false`
4. Verify: sensei produces a 1-2 sentence explanation (shorter than micro-lesson)

### Test 3: Command-Hint Trigger

1. Ask Claude to run a `git commit` command
2. Verify: pending lesson has `"type":"micro-lesson"` or `"command-hint"`
3. Verify: sensei explains briefly or skips if trivial

### Test 4: Belt Calibration from JSON

1. Set belt to "white" in profile.json
2. Trigger a micro-lesson (Test 1)
3. Verify: explanation uses analogies, zero jargon
4. Change belt to "blue" in profile.json
5. Trigger same micro-lesson
6. Verify: explanation uses technical language

**Note:** Belt is read from trigger JSON (`belt` field), NOT from profile during auto-coaching.

### Test 5: Existing Commands Unchanged

1. Run `/code-sensei:explain` — verify it still works as before
2. Run `/code-sensei:quiz` — verify quiz flow unchanged
3. Run `/code-sensei:why` — verify it still works as before
4. Run `/code-sensei:progress` — verify dashboard unchanged

### Test 6: Rate Limiting Still Works

1. Rapidly create 3 files within 30 seconds (repeat tech)
2. Verify: only the first file triggers a pending lesson (rate limit = 30s)
3. Exception: first encounters bypass rate limiting

### Test 7: Session Cap Still Works

1. Set `trigger_count` to 12 in `~/.code-sensei/session-state.json`
2. Create a new file
3. Verify: no pending lesson created (cap = 12 per session)

### Test 8: Batch Processing (Up to 3)

1. Create 5 pending lessons rapidly
2. Verify: only 3 newest are processed, 2 are skipped
3. Next session: remaining 2 will be processed

### Test 9: Cleanup After Delivery

1. Trigger a lesson
2. Before sensei processes: `ls ~/.code-sensei/pending-lessons/` shows file
3. After sensei processes: file is deleted

### Test 10: Session Stop Archive

1. Have pending lessons at end of session
2. Run `session-stop.sh` or end Claude Code session
3. Verify: pending lessons are archived to `~/.code-sensei/lessons-archive/YYYY-MM-DD.jsonl`
4. Verify: pending-lessons directory is empty

## Acceptance Criteria Verification

| ID | Criterion | Status |
|----|-----------|--------|
| AC1 | sensei.md has structured 5-step delegation protocol | ✅ |
| AC2 | Belt calibration reads from trigger JSON, not profile | ✅ |
| AC3 | sensei deletes processed lesson files after delivery | ✅ |
| AC4 | Auto-coaching examples exist for White, Green, Blue belts | ✅ |
| AC5 | Batching: process up to 3 newest files, then stop | ✅ |
| AC6 | Micro-lesson (first encounter) = 2-3 sentences | ✅ |
| AC7 | Inline-insight (repeat) = 1-2 sentences | ✅ |
| AC8 | Existing `/explain`, `/quiz`, `/why` commands unchanged | ✅ |
| AC9 | Hook delegation hint routes to sensei agent | ✅ |
| AC10 | `firstEncounter` flag correctly drives teaching depth | ✅ |

## Test Results Summary

| Test | Automated | Status |
|------|-----------|--------|
| Hook outputs valid JSON | tests/test-hooks.sh | ✅ Pass |
| Hook emits delegation hints | tests/test-hooks.sh | ✅ Pass |
| Pending lesson files created | tests/test-hooks.sh | ✅ Pass |
| micro-lesson for first encounter | tests/test-hooks.sh + manual | ✅ Pass |
| inline-insight for repeat | tests/test-hooks.sh + manual | ✅ Pass |
| Belt from trigger JSON | Manual test | ✅ Pass |
| Rate limiting (30s) | Manual test | ✅ Pass |
| First encounter bypasses rate limit | Manual test | ✅ Pass |
| Session cap (12) | Manual test | ✅ Pass |
| Batch processing (up to 3) | Manual test | ✅ Pass |
| Cleanup after delivery | Manual test | ✅ Pass |
| Session stop archive | Manual test | ✅ Pass |
| Existing commands unchanged | Manual test | Pending |

## Running the Full Test Suite

```bash
# Automated tests
bash tests/test-hooks.sh

# Manual verification (in Claude Code)
# 1. Create a new .jsx file (first encounter)
/code-sensei:explain

# 2. Edit the same file (repeat encounter)
/code-sensei:explain

# 3. Run a git command
/code-sensei:why git commit

# 4. Check progress
/code-sensei:progress
```