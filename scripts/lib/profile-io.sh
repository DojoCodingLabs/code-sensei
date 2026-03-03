#!/usr/bin/env bash
# Shared profile I/O library for CodeSensei
# Source this file in hook scripts to get atomic read/write helpers.
# Usage: source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/profile-io.sh"

PROFILE_DIR="${HOME}/.code-sensei"
PROFILE_FILE="${PROFILE_DIR}/profile.json"

# Ensure profile directory exists
ensure_profile_dir() {
  mkdir -p "$PROFILE_DIR"
}

# Read profile, output to stdout. Returns empty object if missing.
read_profile() {
  if [ -f "$PROFILE_FILE" ]; then
    cat "$PROFILE_FILE"
  else
    echo '{}'
  fi
}

# Atomic write: takes JSON from stdin, writes to profile via temp+mv.
# Returns 1 if the temp file is empty (guards against writing a blank profile).
write_profile() {
  ensure_profile_dir
  local tmp_file
  tmp_file=$(mktemp "${PROFILE_FILE}.tmp.XXXXXX")
  if cat > "$tmp_file" && [ -s "$tmp_file" ]; then
    mv "$tmp_file" "$PROFILE_FILE"
  else
    rm -f "$tmp_file"
    return 1
  fi
}

# Update profile atomically: takes a jq filter, applies it in one pass.
# Usage: update_profile '.xp += 10'
# Requires jq to be installed; callers should guard with `command -v jq`.
update_profile() {
  local filter="$1"
  local current
  current=$(read_profile)
  echo "$current" | jq "$filter" | write_profile
}
