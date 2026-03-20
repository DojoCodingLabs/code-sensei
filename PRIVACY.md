# CodeSensei Privacy & Local Storage

CodeSensei is designed to be local-first.

This document explains what the plugin stores on disk, what it does not do, and how retention works.

Platform note:
- CodeSensei currently targets macOS and Linux shells.
- On Windows, use WSL for the most reliable behavior.

## What CodeSensei stores locally

By default, CodeSensei writes data under:

```text
~/.code-sensei/
```

### `profile.json`
Your persistent learning profile, including:
- belt
- XP
- streak data
- quiz counters
- quiz history
- concepts seen
- concepts mastered
- preferences
- achievement metadata

### `profile.json.backup`
A backup of the previous profile created before import overwrites it.

### `session-commands.jsonl`
A recent local history of shell commands used for contextual teaching.

Stored fields:
- timestamp
- redacted/truncated command string
- concept classification

Important:
- CodeSensei redacts common secret patterns before logging
- Commands are truncated before storage
- This file is capped to the most recent 1000 lines

### `session-changes.jsonl`
A recent local history of file-change events.

Stored fields:
- timestamp
- tool name
- file path
- extension
- detected tech label
- tracked concept identifier

This file is capped to the most recent 1000 lines.

### `sessions.log`
A compact session start/stop log used for streaks and session summaries.

This file is capped to the most recent 500 lines.

### `pending-lessons/`
Structured teaching moments queued during the active session.

This queue is cleared at session end after archival.

### `lessons-archive/`
Archived teaching moments from past sessions.

Retention:
- keeps the last 30 daily archive files

### `error.log`
Local plugin script errors for troubleshooting.

## What CodeSensei does not do

The shell scripts in this repository do not:
- upload your code
- send telemetry
- send your profile to Dojo Coding
- call external tracking APIs

## Redaction behavior

CodeSensei attempts to redact common sensitive patterns before writing commands to local logs, including values that look like:
- `*_TOKEN`
- `*_SECRET`
- `*_PASSWORD`
- `*_API_KEY`
- `Authorization: Bearer ...`
- credential-bearing URLs like `https://user:pass@example.com`

This redaction is heuristic, not a cryptographic guarantee.

If you run especially sensitive commands and want zero retention, you should clear `~/.code-sensei/` afterwards.

## How to inspect your local footprint

Run:

```bash
/code-sensei:doctor
```

That command reports:
- setup health
- profile status
- storage paths
- pending lesson count
- next-step suggestions

## How to reset everything

Delete the local directory:

```bash
rm -rf ~/.code-sensei
```

That removes your local profile, logs, backups, pending lessons, and archives.
