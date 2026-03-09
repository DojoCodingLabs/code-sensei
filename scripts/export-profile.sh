#!/bin/bash
# CodeSensei — Export Profile Script
# Exports ~/.code-sensei/profile.json to a timestamped file with metadata wrapper

PROFILE_DIR="$HOME/.code-sensei"
PROFILE_FILE="$PROFILE_DIR/profile.json"
EXPORT_STAMP=$(date -u +%Y-%m-%dT%H-%M-%SZ)
EXPORT_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EXPORT_FILE="$HOME/code-sensei-export-${EXPORT_STAMP}-$$.json"

# Resolve plugin version from plugin.json if CLAUDE_PLUGIN_ROOT is set
PLUGIN_VERSION="unknown"
if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; then
  if command -v jq &> /dev/null; then
    PLUGIN_VERSION=$(jq -r '.version // "unknown"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")
  fi
fi

# Check if profile exists
if [ ! -f "$PROFILE_FILE" ]; then
  echo "ERROR: No profile found at $PROFILE_FILE" >&2
  echo "Run a CodeSensei session first to create your profile." >&2
  exit 0
fi

# Export with jq if available (full metadata wrapper)
if command -v jq &> /dev/null; then
  jq \
    --arg schema_version "1.0" \
    --arg exported_at "$EXPORT_TIMESTAMP" \
    --arg plugin_version "$PLUGIN_VERSION" \
    '{
      schema_version: $schema_version,
      exported_at: $exported_at,
      plugin_version: $plugin_version,
      profile: .
    }' \
    "$PROFILE_FILE" > "$EXPORT_FILE"

  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create export file at $EXPORT_FILE" >&2
    exit 0
  fi

  echo "$EXPORT_FILE"
else
  # jq not available — still create an importable wrapper without validation/pretty-printing
  echo "WARNING: jq not found. Creating export without jq validation/pretty formatting." >&2
  echo "Install jq for full export functionality: brew install jq" >&2

  {
    printf '{\n'
    printf '  "schema_version": "1.0",\n'
    printf '  "exported_at": "%s",\n' "$EXPORT_TIMESTAMP"
    printf '  "plugin_version": "%s",\n' "$PLUGIN_VERSION"
    printf '  "profile": '
    cat "$PROFILE_FILE"
    printf '\n}\n'
  } > "$EXPORT_FILE"

  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to copy profile to $EXPORT_FILE" >&2
    exit 0
  fi

  echo "$EXPORT_FILE"
fi

exit 0
