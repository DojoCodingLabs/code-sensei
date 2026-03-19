#!/bin/bash
# CodeSensei — Doctor Script
# Checks local prerequisites and profile state for a healthier first-run experience.

set -euo pipefail

SCRIPT_NAME="doctor"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"
# shellcheck source=lib/error-handling.sh
source "${SCRIPT_DIR}/lib/error-handling.sh"

HOOKS_FILE="${PLUGIN_ROOT}/hooks/hooks.json"
COMMANDS_DIR="${PLUGIN_ROOT}/commands"
PENDING_DIR="${PROFILE_DIR}/pending-lessons"
LESSON_ARCHIVE_DIR="${PROFILE_DIR}/lessons-archive"

file_exists() {
  if [ -f "$1" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

dir_exists() {
  if [ -d "$1" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

emit_json() {
  printf '%s\n' "$1"
}

jq_ok="false"
hooks_ok="false"
status="ok"
issues=()
suggestions=()

if command -v jq >/dev/null 2>&1; then
  jq_ok="true"
else
  jq_ok="false"
  emit_json '{"status":"fail","profile":{"dir":"'"${PROFILE_DIR}"'","file":"'"${PROFILE_FILE}"'","dir_exists":false,"exists":false,"belt":"unknown","xp":0,"quizzes_total":0,"concepts_mastered":0,"streak_current":0},"checks":{"jq_installed":false,"hooks_valid":false,"commands_detected":0,"pending_lessons":0,"pending_dir_exists":false,"archive_dir_exists":false},"storage_paths":{"profile":"'"${PROFILE_FILE}"'","backup":"'"${PROFILE_FILE}.backup"'","commands_log":"'"${PROFILE_DIR}/session-commands.jsonl"'","changes_log":"'"${PROFILE_DIR}/session-changes.jsonl"'","sessions_log":"'"${PROFILE_DIR}/sessions.log"'","pending_lessons":"'"${PROFILE_DIR}/pending-lessons/"'","lessons_archive":"'"${PROFILE_DIR}/lessons-archive/"'","error_log":"'"${PROFILE_DIR}/error.log"'"},"issues":["jq is not installed"],"suggestions":["Install jq: brew install jq (macOS) or apt install jq (Linux)"]}'
  exit 0
fi

if [ -f "$HOOKS_FILE" ]; then
  if [ "$jq_ok" = "true" ] && jq . "$HOOKS_FILE" >/dev/null 2>&1; then
    hooks_ok="true"
  else
    hooks_ok="false"
    if [ "$status" = "ok" ]; then
      status="warn"
    fi
    issues+=("hooks/hooks.json is missing or invalid")
  fi
else
  if [ "$status" = "ok" ]; then
    status="warn"
  fi
  issues+=("hooks/hooks.json not found")
fi

profile_exists="$(file_exists "$PROFILE_FILE")"
profile_dir_exists="$(dir_exists "$PROFILE_DIR")"
pending_dir_exists="$(dir_exists "$PENDING_DIR")"
archive_dir_exists="$(dir_exists "$LESSON_ARCHIVE_DIR")"

if [ "$profile_exists" = "false" ]; then
  if [ "$status" = "ok" ]; then
    status="warn"
  fi
  suggestions+=("Run /code-sensei:progress once to create your local profile")
fi

commands_count=0
if [ -d "$COMMANDS_DIR" ]; then
  commands_count=$(find "$COMMANDS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
fi

pending_count=0
if [ -d "$PENDING_DIR" ]; then
  pending_count=$(find "$PENDING_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')
fi

profile_belt="unknown"
profile_xp=0
profile_quizzes=0
profile_mastered=0
profile_streak=0
if [ "$profile_exists" = "true" ] && [ "$jq_ok" = "true" ]; then
  profile_belt=$(jq -r '.belt // "white"' "$PROFILE_FILE" 2>/dev/null || printf 'unknown')
  profile_xp=$(jq -r '.xp // 0' "$PROFILE_FILE" 2>/dev/null || printf '0')
  profile_quizzes=$(jq -r '.quizzes.total // 0' "$PROFILE_FILE" 2>/dev/null || printf '0')
  profile_mastered=$(jq -r '(.concepts_mastered // []) | length' "$PROFILE_FILE" 2>/dev/null || printf '0')
  profile_streak=$(jq -r '.streak.current // 0' "$PROFILE_FILE" 2>/dev/null || printf '0')
fi

issues_json='[]'
for issue in "${issues[@]:-}"; do
  if [ -n "$issue" ]; then
    issues_json=$(printf '%s' "$issues_json" | jq --arg issue "$issue" '. + [$issue]')
  fi
done

suggestions_json='[]'
for suggestion in "${suggestions[@]:-}"; do
  if [ -n "$suggestion" ]; then
    suggestions_json=$(printf '%s' "$suggestions_json" | jq --arg suggestion "$suggestion" '. + [$suggestion]')
  fi
done

jq -n \
  --arg status "$status" \
  --arg plugin_root "$PLUGIN_ROOT" \
  --arg profile_dir "$PROFILE_DIR" \
  --arg profile_file "$PROFILE_FILE" \
  --argjson jq_installed "$jq_ok" \
  --argjson hooks_valid "$hooks_ok" \
  --argjson profile_dir_exists "$profile_dir_exists" \
  --argjson profile_exists "$profile_exists" \
  --argjson pending_dir_exists "$pending_dir_exists" \
  --argjson archive_dir_exists "$archive_dir_exists" \
  --argjson commands_count "$commands_count" \
  --argjson pending_count "$pending_count" \
  --arg profile_belt "$profile_belt" \
  --argjson profile_xp "$profile_xp" \
  --argjson profile_quizzes "$profile_quizzes" \
  --argjson profile_mastered "$profile_mastered" \
  --argjson profile_streak "$profile_streak" \
  --argjson issues "$issues_json" \
  --argjson suggestions "$suggestions_json" \
  '{
    status: $status,
    plugin_root: $plugin_root,
    profile: {
      dir: $profile_dir,
      file: $profile_file,
      dir_exists: $profile_dir_exists,
      exists: $profile_exists,
      belt: $profile_belt,
      xp: $profile_xp,
      quizzes_total: $profile_quizzes,
      concepts_mastered: $profile_mastered,
      streak_current: $profile_streak
    },
    checks: {
      jq_installed: $jq_installed,
      hooks_valid: $hooks_valid,
      commands_detected: $commands_count,
      pending_lessons: $pending_count,
      pending_dir_exists: $pending_dir_exists,
      archive_dir_exists: $archive_dir_exists
    },
    storage_paths: {
      profile: $profile_file,
      backup: ($profile_file + ".backup"),
      commands_log: ($profile_dir + "/session-commands.jsonl"),
      changes_log: ($profile_dir + "/session-changes.jsonl"),
      sessions_log: ($profile_dir + "/sessions.log"),
      pending_lessons: ($profile_dir + "/pending-lessons/"),
      lessons_archive: ($profile_dir + "/lessons-archive/"),
      error_log: ($profile_dir + "/error.log")
    },
    issues: $issues,
    suggestions: $suggestions
  }'
