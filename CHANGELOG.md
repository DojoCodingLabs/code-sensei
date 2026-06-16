# Changelog

All notable changes to CodeSensei will be documented in this file.

## 1.1.1

- Fixed the `sensei` subagent failing to launch (0 tool uses) because its configured `haiku` model is unavailable; switched to `sonnet`

## 1.1.0

- Added `/code-sensei:doctor` for setup verification and local storage inspection
- Added deterministic profile import script with preview/apply workflow
- Hardened command logging with secret redaction
- Added retention caps for local session logs
- Improved marketplace-facing README and privacy documentation
- Tightened concept tracking alignment and launch validation

## 1.0.0

- Initial public release of CodeSensei
- Hook-based contextual teaching for Claude Code
- Belt progression, quiz bank, and persistent local profile
