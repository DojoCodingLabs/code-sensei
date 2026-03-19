#!/bin/bash
# CodeSensei — Shared Log Helpers
# Utilities for trimming local logs and redacting sensitive command content.

trim_log_file() {
  local file_path="$1"
  local max_lines="$2"

  if [ ! -f "$file_path" ]; then
    return 0
  fi

  local line_count
  line_count=$(wc -l < "$file_path" 2>/dev/null || echo 0)
  if [ "$line_count" -gt "$max_lines" ]; then
    tail -n "$max_lines" "$file_path" > "${file_path}.tmp" && mv "${file_path}.tmp" "$file_path"
  fi
}

redact_sensitive_command() {
  local raw_command="$1"

  printf '%s' "$raw_command" | \
    sed -E \
      -e 's/([A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|PWD|API_KEY|APIKEY|ACCESS_KEY|ACCESSKEY|PRIVATE_KEY|COOKIE|SESSION)[A-Za-z0-9_]*=)"[^"]*"/\1"[REDACTED]"/Ig' \
      -e "s/([A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|PWD|API_KEY|APIKEY|ACCESS_KEY|ACCESSKEY|PRIVATE_KEY|COOKIE|SESSION)[A-Za-z0-9_]*=)'[^']*'/\\1'[REDACTED]'/Ig" \
      -e 's/([A-Za-z_][A-Za-z0-9_]*(TOKEN|SECRET|PASSWORD|PASSWD|PWD|API_KEY|APIKEY|ACCESS_KEY|ACCESSKEY|PRIVATE_KEY|COOKIE|SESSION)[A-Za-z0-9_]*=)[^[:space:]]+/\1[REDACTED]/Ig' \
      -e 's/(--?(token|secret|password|pass|api-key|apikey|access-key|accesskey|private-key|authorization|cookie|session)(=|[[:space:]]+))[^[:space:]]+/\1[REDACTED]/Ig' \
      -e "s/(Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+)[^\"'[:space:]]+/\\1[REDACTED]/Ig" \
      -e 's#(https?://[^/@[:space:]]+:)[^/@[:space:]]+@#\1[REDACTED]@#g'
}
