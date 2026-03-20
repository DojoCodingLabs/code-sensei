# 🥋 CodeSensei — Learn to Code While You Build

[![Claude Code Plugin](https://img.shields.io/badge/Claude_Code-Plugin-blue?logo=anthropic&logoColor=white)](https://github.com/DojoCodingLabs/code-sensei)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](https://opensource.org/licenses/MIT)
[![Category: Education](https://img.shields.io/badge/Category-Education-orange)](https://github.com/topics/claude-code-plugin)
[![Free & Open Source](https://img.shields.io/badge/Free-Open_Source-brightgreen)](https://github.com/DojoCodingLabs/code-sensei)

### In-context coding tutor for Claude Code — explanations, quizzes, and belt-based progress from your real project

**CodeSensei** is a free, open-source Claude Code plugin by [Dojo Coding](https://dojocoding.io) that turns every coding session into a learning session.

It watches what you build locally, explains what just happened in plain language, quizzes you on concepts from your own project, and tracks your growth with a martial arts belt progression system.

<p align="center">
  <img src="codesenseicover.png" alt="CodeSensei — Learn to code while you build" />
</p>

---

## Why it exists

Millions of people are building with AI before they fully understand the code.

That is not a failure — it is a new starting point.

The problem is what happens next:
- something breaks
- a new feature needs a custom change
- the AI explanation feels too abstract
- the user realizes they shipped something they cannot yet reason about

CodeSensei closes that gap.

Instead of forcing people to stop building and go study in a separate environment, it teaches inside the workflow they already use.

---

## What you get

- 🧠 **Contextual explanations** — learn from your actual project, not fake toy examples
- 🧩 **Micro-quizzes** — quick checks that reinforce understanding instead of syntax memorization
- 🥋 **Belt progression** — White Belt to Black Belt, earned through XP + mastery gates
- 🔁 **Persistent local profile** — progress follows you across projects on the same machine
- 🎯 **Adaptive teaching** — explanations adjust to your belt level and professional background
- 🔒 **Local-first design** — no telemetry, no external calls, no code uploads from the plugin scripts

---

## Quick start

### Requirements

- [Claude Code](https://code.claude.com) with plugin support
- `jq` installed locally
  - macOS: `brew install jq`
  - Ubuntu/Debian: `sudo apt install jq`

`jq` is required for profile tracking, imports, quizzes, and diagnostics.

### Supported platforms

- ✅ macOS
- ✅ Linux
- ⚠️ Windows via WSL recommended

CodeSensei is a Unix-shell plugin today. Its runtime depends on `bash`, `jq`, and standard Unix tools, so WSL is the safest path on Windows.

### Install from marketplace

Inside Claude Code:

```bash
/plugin marketplace add DojoCodingLabs/code-sensei
/plugin install code-sensei@code-sensei
```

### First-run flow

After install:

1. Run `/code-sensei:progress` to initialize your local profile
2. Optional: run `/code-sensei:level background marketing` (or design, finance, medicine, etc.)
3. Build normally with Claude Code
4. Use `/code-sensei:explain` after a code change you want to understand
5. Run `/code-sensei:doctor` if you want to verify setup or inspect local storage paths

### Update

Inside Claude Code:

```bash
/plugin marketplace update DojoCodingLabs/code-sensei
/plugin update code-sensei@code-sensei
```

Restart your Claude Code session after updating so hooks reload cleanly.

### Local development install

```bash
git clone https://github.com/DojoCodingLabs/code-sensei.git
cd code-sensei

/plugin marketplace add .
/plugin install code-sensei
```

---

## Commands

CodeSensei currently ships with **10 commands**:

| Command | What it does |
|---------|--------------|
| `/code-sensei:explain` | Explain what Claude just changed in terms you understand |
| `/code-sensei:quiz` | Test your understanding with a contextual quiz |
| `/code-sensei:why` | Explain why a specific decision or pattern was used |
| `/code-sensei:progress` | Show your learning dashboard, streak, mastery, and next belt requirements |
| `/code-sensei:recap` | Summarize what you learned in the session |
| `/code-sensei:level` | Adjust difficulty or set your professional background |
| `/code-sensei:belt` | Show current belt rank and progress |
| `/code-sensei:export` | Export your local profile for backup or migration |
| `/code-sensei:import` | Restore a profile from a previous export |
| `/code-sensei:doctor` | Verify setup health and inspect exactly what CodeSensei stores locally |

---

## How it works

1. **You build normally**
   Prompt Claude to create files, edit code, install dependencies, and run commands.

2. **Hooks watch local activity**
   CodeSensei listens for file changes and shell commands, then queues lightweight teaching moments locally.

3. **You ask when curious**
   Use `/code-sensei:explain`, `/code-sensei:why`, or `/code-sensei:quiz` whenever you want to understand something better.

4. **Teaching adapts to you**
   White Belt gets analogy-first explanations. Advanced belts get more technical language, tradeoffs, and architecture discussion.

5. **Progress persists locally**
   Your profile lives in `~/.code-sensei/` and carries across projects on that machine.

---

## Belt progression

```text
⬜ White Belt    →     0 XP    “You wrote your first prompt”
🟡 Yellow Belt   →   500 XP    “You understand files & folders”
🟠 Orange Belt   → 1,500 XP    “You get frontend vs backend”
🟢 Green Belt    → 3,500 XP    “You can read and modify code”
🔵 Blue Belt     → 7,000 XP    “You understand APIs & databases”
🟤 Brown Belt    → 12,000 XP   “You can architect a full app”
⚫ Black Belt    → 20,000 XP   “You think like an engineer”
```

Promotion is not XP-only.

Each new belt also requires:
- concept mastery gates
- quiz accuracy of at least 60%

That keeps progress tied to understanding, not just activity.

---

## Adaptive teaching examples

### White Belt / beginner
> “Claude just added a translator to your server. Raw form data arrives as text, and this translator turns it into something your code can actually read.”

### Blue Belt / advanced learner
> “Claude added middleware to parse JSON before requests hit your route handlers, so `req.body` is already normalized when your business logic runs.”

Same project. Same concept. Different depth.

### Background-specific analogies
Set a background with `/code-sensei:level background marketing` and CodeSensei will adapt examples to your field.

Examples:
- **Marketing** — “An API is like a campaign brief: you send structured requirements and receive a structured result.”
- **Design** — “Components are like design system elements: reusable, composable, and consistent.”
- **Finance** — “A variable is like an account balance: a named value that changes over time.”
- **Medicine** — “Error handling is like triage: you check critical problems first.”

---

## Learning coverage

CodeSensei currently includes:

- **10 learning categories**
- **45 concepts**
- **124 quiz questions**

Categories:
- 🧱 Fundamentals
- 🌐 Web Basics
- ⚡ JavaScript
- 💻 Terminal & Tools
- 🎨 Frontend
- ⚙️ Backend
- 🗄️ Databases
- 🚀 Deployment
- 🏗️ Architecture
- 🐞 Debugging

---

## What is stored locally

Everything lives under `~/.code-sensei/`.

Primary files:
- `profile.json` — belt, XP, streaks, quiz stats, preferences, mastered concepts
- `profile.json.backup` — last backup created during import
- `session-commands.jsonl` — recent command log, truncated and redacted
- `session-changes.jsonl` — recent file-change log
- `sessions.log` — compact session start/stop history
- `pending-lessons/` — queued teaching moments for the current session
- `lessons-archive/` — archived teaching moments
- `error.log` — local script errors only

Retention:
- `session-commands.jsonl` keeps the most recent 1000 lines
- `session-changes.jsonl` keeps the most recent 1000 lines
- `sessions.log` keeps the most recent 500 lines
- `lessons-archive/` keeps the last 30 daily archive files
- `pending-lessons/` is cleared at session end

Sensitive data handling:
- command logs are truncated
- common token/secret/password patterns are redacted before logging
- the plugin scripts do not upload your code or local profile anywhere

For a more detailed breakdown, see [PRIVACY.md](PRIVACY.md).

---

## Privacy and trust

CodeSensei is designed to be local-first.

The shell scripts in this repo:
- do not send telemetry
- do not upload code
- do not call external APIs for tracking
- store learning data locally on your machine

Important precision:
- CodeSensei does record local metadata about your coding sessions so it can teach effectively
- That includes file paths, concept history, quiz history, and redacted command history
- If you want to inspect exactly what exists on disk, run `/code-sensei:doctor`

If you ever want a clean reset, delete `~/.code-sensei/`.

---

## Repository structure

```text
code-sensei/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
├── commands/                 # 10 slash commands
├── agents/
│   └── sensei.md             # teaching agent prompt
├── hooks/
│   └── hooks.json            # SessionStart, SessionEnd, PostToolUse hooks
├── scripts/                  # local runtime behavior (bash + jq)
├── skills/                   # teaching modules
├── data/
│   ├── concept-tree.json     # 45 concepts across 10 categories
│   └── quiz-bank.json        # 124 quiz items
└── tests/
```

---

## Contributing

Contributions are welcome.

High-value areas:
- better analogies
- more quiz questions
- new learning modules
- better concept detection
- translations
- bug fixes and tests

See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Built by Dojo Coding

[Dojo Coding](https://dojocoding.io) is a LATAM-first tech education ecosystem helping more people become builders.

CodeSensei is free forever, open source, and designed to help users go from “I shipped something with AI” to “I understand what I’m building.”

Learn more:
- [Dojo Coding](https://dojocoding.io)
- [VibeCoding Bootcamp](https://dojocoding.io/bootcamp)
- [DojoOS](https://dojocoding.io/dojoos)
- [Discord](https://dojocoding.io/discord)

---

## License

MIT License.

---

<p align="center">
  <strong>From vibecoder to engineer — one session at a time.</strong><br>
  <em>Free. Open source. By <a href="https://dojocoding.io">Dojo Coding</a>.</em>
</p>
