#!/bin/bash
# CodeSensei — Shared Error Handling Library
# Source this file in hook scripts for consistent error logging and JSON safety.
#
# Usage:
#   source "$(dirname "$0")/lib/error-handling.sh"

LOG_FILE="${HOME}/.code-sensei/error.log"
MAX_LOG_LINES=1000

# Log an error with timestamp and script name.
# Usage: log_error "script-name" "message"
log_error() {
  local script_name="${1:-unknown}"
  local message="$2"
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%d')
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '[%s] [%s] %s\n' "$timestamp" "$script_name" "$message" >> "$LOG_FILE"
  # Cap log file to MAX_LOG_LINES
  if [ -f "$LOG_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
      tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
  fi
}

# Safely escape a string for JSON interpolation.
# Returns a JSON-encoded string including surrounding double quotes.
# Usage: escaped=$(json_escape "$var")
json_escape() {
  local str="$1"
  if command -v jq &>/dev/null; then
    printf '%s' "$str" | jq -Rs '.'
  else
    # Basic fallback: escape backslashes, double quotes, and common control chars
    printf '"%s"' "$(printf '%s' "$str" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

# Check that jq is installed. Logs a one-time warning per session if missing.
# Usage: check_jq "script-name" || exit 0
check_jq() {
  if ! command -v jq &>/dev/null; then
    local warn_file="${HOME}/.code-sensei/.jq-warned"
    if [ ! -f "$warn_file" ]; then
      log_error "${1:-unknown}" "jq not installed — CodeSensei features limited. Install with: brew install jq"
      touch "$warn_file"
    fi
    return 1
  fi
  return 0
}
