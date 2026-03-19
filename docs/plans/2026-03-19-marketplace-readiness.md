# CodeSensei Marketplace Readiness Implementation Plan

> For Hermes: execute this plan with frequent verification and atomic commits directly on `main`.

**Goal:** Make `DojoCodingLabs/code-sensei` ready for marketplace publication by fixing public-facing inconsistencies, hardening trust/privacy behavior, improving onboarding, and enforcing critical behavior in tests/CI.

**Architecture:** Keep the current lightweight plugin architecture (hooks + shell scripts + prompt commands + local JSON profile), but move launch-critical behavior toward clearer deterministic scripts and stronger guardrails. Prioritize user trust, clear onboarding, and reliable validation over adding net-new product scope.

**Tech Stack:** Claude Code plugin manifests, Bash hook scripts, jq-based JSON mutation, Markdown command prompts, GitHub Actions.

---

## Launch blockers to address

1. Public docs and metadata are inconsistent with the repo (command/concept/category counts, onboarding, privacy detail).
2. Command logging can capture secrets or tokens; privacy copy is less precise than actual behavior.
3. Import flow is prompt-only while export is scripted; setup verification is weak.
4. Hook regression test fails and CI does not run it.
5. Marketplace assets/copy need tightening to feel polished and reviewer-friendly.

---

## Planned workstreams

### Workstream 1 — Planning and launch checklist
- Add this plan to the repo so launch work is documented and reviewable.
- Keep commits atomic and grouped by theme.

### Workstream 2 — Marketplace-facing docs and metadata
- Update `README.md` to match reality:
  - correct command count
  - correct concept/category counts
  - clearer first-run steps
  - explicit jq requirement
  - precise privacy/storage section
  - setup/doctor guidance
- Update `CONTRIBUTING.md` to reflect current command set and validation expectations.
- Tighten `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` copy for clearer marketplace positioning.
- Add any missing support/launch docs that materially improve marketplace trust.

### Workstream 3 — Runtime trust and onboarding hardening
- Add deterministic setup verification via a new doctor/setup command and supporting script.
- Implement a real import script so import/export are symmetrical and less prompt-dependent.
- Add secret-safe command logging/redaction to `scripts/track-command.sh`.
- Review local storage/retention behavior and document it precisely.

### Workstream 4 — Behavior reliability and tests
- Reproduce and root-cause the failing `tests/test-hooks.sh` case.
- Fix the behavior or the test expectation based on intended rate-limit semantics.
- Expand tests to cover new doctor/import/redaction behavior where practical.
- Update `.github/workflows/validate.yml` to run hook regression tests in CI.

### Workstream 5 — Final verification and publish
- Run full local validation for shell scripts, JSON, and hook tests.
- Review `git diff` for launch quality.
- Push all atomic commits to `main`.

---

## Atomic commit plan

1. `docs: add marketplace readiness plan`
2. `docs: polish marketplace copy and onboarding`
3. `feat: add doctor and import scripts`
4. `fix: redact sensitive command logging`
5. `test: fix hook regression coverage and enforce in ci`
6. `chore: final marketplace readiness touchups` (only if genuinely needed)

---

## Verification checklist

- [ ] README/metadata match actual repo contents
- [ ] Import is backed by a script, not only prompt instructions
- [ ] Setup/doctor experience exists and is documented
- [ ] Sensitive command patterns are redacted before logging
- [ ] Hook regression tests pass locally
- [ ] CI runs critical hook tests
- [ ] Repo is clean and pushed to `main`
