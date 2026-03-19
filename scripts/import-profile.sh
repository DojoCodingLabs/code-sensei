#!/bin/bash
# CodeSensei — Import Profile Script
# Validates and imports an exported profile with a preview/apply workflow.

set -euo pipefail

SCRIPT_NAME="import-profile"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/profile-io.sh
source "${SCRIPT_DIR}/lib/profile-io.sh"
# shellcheck source=lib/error-handling.sh
source "${SCRIPT_DIR}/lib/error-handling.sh"

APPLY_MODE="false"
IMPORT_PATH=""

if [ "${1:-}" = "--apply" ]; then
  APPLY_MODE="true"
  shift
fi

if [ $# -gt 0 ]; then
  IMPORT_PATH="$1"
  IMPORT_PATH="${IMPORT_PATH/#\~/$HOME}"
fi

emit_json() {
  printf '%s\n' "$1"
}

summary_json() {
  local json_file="$1"
  jq -c '{
    belt: (.belt // "white"),
    xp: (.xp // 0),
    concepts_mastered: ((.concepts_mastered // []) | length),
    quizzes_total: (.quizzes.total // 0),
    streak_current: (.streak.current // 0)
  }' "$json_file"
}

summary_from_stream() {
  jq -c '{
    belt: (.belt // "white"),
    xp: (.xp // 0),
    concepts_mastered: ((.concepts_mastered // []) | length),
    quizzes_total: (.quizzes.total // 0),
    streak_current: (.streak.current // 0)
  }'
}

if [ -z "$IMPORT_PATH" ]; then
  emit_json '{"status":"missing_arg","message":"Usage: bash ${CLAUDE_PLUGIN_ROOT}/scripts/import-profile.sh [--apply] /path/to/export.json"}'
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  emit_json '{"status":"jq_missing","message":"jq is required to validate and import CodeSensei profiles."}'
  exit 0
fi

if [ ! -f "$IMPORT_PATH" ]; then
  escaped_path=$(json_escape "$IMPORT_PATH")
  emit_json "{\"status\":\"file_not_found\",\"path\":${escaped_path}}"
  exit 0
fi

WRAPPED_EXPORT="false"
RAW_EXPORT="false"
PROFILE_PAYLOAD=''
SCHEMA_VERSION='unknown'
EXPORTED_AT='unknown'
PLUGIN_VERSION='unknown'

if jq -e '.profile and (.profile | type == "object")' "$IMPORT_PATH" >/dev/null 2>&1; then
  WRAPPED_EXPORT="true"
  PROFILE_PAYLOAD=$(jq -c '.profile' "$IMPORT_PATH")
  SCHEMA_VERSION=$(jq -r '.schema_version // "unknown"' "$IMPORT_PATH")
  EXPORTED_AT=$(jq -r '.exported_at // "unknown"' "$IMPORT_PATH")
  PLUGIN_VERSION=$(jq -r '.plugin_version // "unknown"' "$IMPORT_PATH")
elif jq -e '.belt' "$IMPORT_PATH" >/dev/null 2>&1; then
  RAW_EXPORT="true"
  PROFILE_PAYLOAD=$(jq -c '.' "$IMPORT_PATH")
else
  escaped_path=$(json_escape "$IMPORT_PATH")
  emit_json "{\"status\":\"invalid\",\"path\":${escaped_path},\"message\":\"The file does not look like a valid CodeSensei export.\"}"
  exit 0
fi

TARGET_SUMMARY=$(printf '%s\n' "$PROFILE_PAYLOAD" | summary_from_stream)
CURRENT_SUMMARY='null'
CURRENT_EXISTS='false'
if [ -f "$PROFILE_FILE" ]; then
  CURRENT_EXISTS='true'
  CURRENT_SUMMARY=$(summary_json "$PROFILE_FILE")
fi

ESCAPED_PATH=$(json_escape "$IMPORT_PATH")
ESCAPED_SCHEMA=$(json_escape "$SCHEMA_VERSION")
ESCAPED_EXPORTED=$(json_escape "$EXPORTED_AT")
ESCAPED_PLUGIN_VERSION=$(json_escape "$PLUGIN_VERSION")
ESCAPED_BACKUP=$(json_escape "${PROFILE_FILE}.backup")

if [ "$APPLY_MODE" != "true" ]; then
  emit_json "{\"status\":\"preview\",\"path\":${ESCAPED_PATH},\"format\":\"$([ \"$WRAPPED_EXPORT\" = \"true\" ] && printf wrapped || printf raw)\",\"schema_version\":${ESCAPED_SCHEMA},\"exported_at\":${ESCAPED_EXPORTED},\"plugin_version\":${ESCAPED_PLUGIN_VERSION},\"profile_exists\":${CURRENT_EXISTS},\"backup_path\":${ESCAPED_BACKUP},\"target_summary\":${TARGET_SUMMARY},\"current_summary\":${CURRENT_SUMMARY}}"
  exit 0
fi

ensure_profile_dir
if [ -f "$PROFILE_FILE" ]; then
  if ! cp "$PROFILE_FILE" "${PROFILE_FILE}.backup"; then
    log_error "$SCRIPT_NAME" "Failed to back up profile before import"
    emit_json "{\"status\":\"backup_failed\",\"path\":${ESCAPED_PATH}}"
    exit 0
  fi
fi

if ! printf '%s\n' "$PROFILE_PAYLOAD" | jq '.' | write_profile; then
  log_error "$SCRIPT_NAME" "Failed writing imported profile to $PROFILE_FILE"
  emit_json "{\"status\":\"write_failed\",\"path\":${ESCAPED_PATH}}"
  exit 0
fi

IMPORTED_SUMMARY=$(summary_json "$PROFILE_FILE")
emit_json "{\"status\":\"imported\",\"path\":${ESCAPED_PATH},\"backup_path\":${ESCAPED_BACKUP},\"schema_version\":${ESCAPED_SCHEMA},\"exported_at\":${ESCAPED_EXPORTED},\"plugin_version\":${ESCAPED_PLUGIN_VERSION},\"summary\":${IMPORTED_SUMMARY}}"
