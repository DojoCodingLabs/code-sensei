# 🥋 CodeSensei

### Learn to code while you vibecode — by [Dojo Coding](https://dojocoding.io)

**CodeSensei** is a free, open-source Claude Code plugin that teaches you programming while you build. Like Duolingo, but for coding — and instead of fake exercises, you learn from **your own projects** in real-time.

No prior coding experience needed. Seriously.

<!-- TODO: Add demo GIF here → real vibecoding session → CodeSensei explains → quiz → XP → belt promotion -->

---

## The Problem

10 million people are vibecoding — prompting AI to build apps without understanding a single line of code. They ship incredible things, but they learn **nothing**. The moment something breaks, they're stuck.

Traditional education says "learn first, then build." But vibecoders are already building. They're not going backwards.

## The Insight

The most powerful classroom is the one you're already sitting in.

Vibecoders don't lack curiosity — they lack **context**. When Claude creates a React component, they want to know what just happened. When it sets up a database, they want to know why.

The questions are already there. Nobody's answering them. **Until now.**

## The Solution

CodeSensei is an AI mentor that lives inside Claude Code. As you build, it explains what's happening, why decisions were made, and quizzes you along the way — all adapted to your skill level through a martial arts belt progression system.

You build your project. CodeSensei builds your understanding.

- 🧠 **Contextual learning** — explanations from *your actual code*, not generic examples
- 🥋 **Belt progression** — White Belt to Black Belt, earned through real understanding
- 🧩 **Micro-quizzes** — comprehension checks that earn XP, not memorization drills
- 🔥 **Streaks & XP** — daily streaks and experience points that persist across projects
- 🎯 **Adaptive difficulty** — set your background (marketing, design, finance) and get analogies from *your field*

---

## 🥋 Belt Progression System

```
⬜ White Belt    →     0 XP    "You wrote your first prompt"
🟡 Yellow Belt   →   500 XP    "You understand files & folders"
🟠 Orange Belt   → 1,500 XP    "You get frontend vs backend"
🟢 Green Belt    → 3,500 XP    "You can read and modify code"
🔵 Blue Belt     → 7,000 XP    "You understand APIs & databases"
🟤 Brown Belt    → 12,000 XP   "You can architect a full app"
⚫ Black Belt    → 20,000 XP   "You think like an engineer"
```

Every explanation, every quiz, every session earns XP. Every belt promotion is a milestone worth celebrating.

---

## 📦 Installation

```bash
# In Claude Code:
/plugin marketplace add DojoCodingLabs/code-sensei
/plugin install code-sensei@code-sensei
```

That's it. Start building — CodeSensei activates automatically.

> **Requires:** [Claude Code](https://code.claude.com) with plugin support. Hook scripts use `jq` for profile tracking — install with `brew install jq` (macOS) or `apt install jq` (Linux).

### Local Development

```bash
git clone https://github.com/DojoCodingLabs/code-sensei.git
cd code-sensei

# In Claude Code:
/plugin marketplace add .
/plugin install code-sensei
```

---

## 🎮 Commands

| Command | What it does |
|---------|-------------|
| `/code-sensei:explain` | Explain what Claude just did, in terms you understand |
| `/code-sensei:quiz` | Test your understanding with a contextual quiz |
| `/code-sensei:why` | Understand *why* Claude made a specific decision |
| `/code-sensei:progress` | View your full learning dashboard |
| `/code-sensei:recap` | End-of-session summary of everything you learned |
| `/code-sensei:level` | Adjust difficulty or set your background field |
| `/code-sensei:belt` | View your current belt rank and progress |

---

## 🧠 How It Works

1. **You vibecode normally** — prompt Claude to build whatever you want
2. **Hooks track what happens** — file changes, commands run, technologies used
3. **You ask when curious** — `/code-sensei:explain`, `/code-sensei:quiz`, `/code-sensei:why` whenever you want to learn
4. **CodeSensei adapts** — explanations match your belt level and background
5. **You level up** — XP accumulates, belts are earned, skills unlock
6. **Progress persists** — your profile lives at `~/.code-sensei/` and works across all projects

### Adaptive Teaching

CodeSensei's AI mentor adapts its entire communication style to your level:

**⬜ White Belt hears:**
> "Claude added a 'translator' to your server. When someone fills out your form, the data arrives as raw text. This translator converts it into something your code can read — like translating a letter from another language."

**🔵 Blue Belt hears:**
> "Express middleware was added to parse incoming JSON. This sits in the request pipeline before your route handlers, so `req.body` is already a JavaScript object by the time your code runs."

Same concept. Different depth. Always from **your project**, not a generic example.

### Background-Specific Analogies

Set your field with `/code-sensei:level background marketing` and CodeSensei speaks your language:

- **Marketing:** "An API is like a campaign brief — you send specific requirements, and the server delivers exactly what you asked for."
- **Design:** "Components are like design system elements — reusable, consistent, and composable."
- **Finance:** "A variable is like an account balance — it holds a value that changes over time."
- **Medicine:** "Error handling is like triage — you check for the most critical problems first."

### What Gets Tracked

- ✅ File types and technologies Claude uses (for contextual teaching)
- ✅ Your XP, belt level, quiz history, and streak
- ❌ No personal data, no code content, no telemetry, no external calls

Everything stays on your machine in `~/.code-sensei/`.

---

## 🔧 What's Included

```
code-sensei/
├── .claude-plugin/
│   ├── plugin.json          # Plugin metadata
│   └── marketplace.json     # Marketplace catalog
├── commands/                 # 7 slash commands
│   ├── explain.md            #   /code-sensei:explain
│   ├── quiz.md               #   /code-sensei:quiz
│   ├── why.md                #   /code-sensei:why
│   ├── progress.md           #   /code-sensei:progress
│   ├── recap.md              #   /code-sensei:recap
│   ├── level.md              #   /code-sensei:level
│   └── belt.md               #   /code-sensei:belt
├── agents/
│   └── sensei.md             # AI mentor subagent (Haiku)
├── skills/                   # 10 auto-invoked teaching modules
├── hooks/
│   └── hooks.json            # Session & code change tracking
├── scripts/                  # Hook scripts (bash + jq)
└── data/                     # Concept tree & quiz bank
```

---

## 📚 Learning Modules

CodeSensei covers **42 concepts** across **9 categories**:

- **🧱 Fundamentals** — Variables, functions, loops, conditionals
- **🌐 Web Basics** — HTML, CSS, how browsers work
- **⚡ JavaScript** — Core JS, async/await, imports, JSON
- **💻 Terminal & Tools** — Command line, npm, git, env variables
- **🎨 Frontend** — React, components, props, state, routing
- **⚙️ Backend** — Servers, routes, middleware, REST APIs, auth
- **🗄️ Databases** — SQL, schemas, ORMs, relationships
- **🚀 Deployment** — Hosting, Docker, CI/CD
- **🏗️ Architecture** — Design patterns, scalability, client-server

---

## 🤝 Contributing

CodeSensei is open source and built to be contributed to:

- **📝 Better analogies** — A nurse writes a medical analogy for error handling. Now every nurse learning to code gets it.
- **🧩 More quizzes** — Add questions to `data/quiz-bank.json`
- **🌍 Translations** — Help us teach in Spanish, Portuguese, and beyond
- **💡 New skill modules** — Want to add Python, Rust, or mobile dev? Go for it.
- **🐛 Bug fixes** — Found an issue? Open a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 🏢 Built by Dojo Coding

[Dojo Coding](https://dojocoding.io) is a LATAM-first tech education ecosystem with 1,800+ developers across 8 countries. We believe anyone can learn to code — especially when they're already building.

CodeSensei is free forever. Open source. No paywall. The full product.

### Go deeper with Dojo Coding

- **[VibeCoding Bootcamp](https://dojocoding.io/bootcamp)** — Structured curriculum with live mentors
- **[DojoOS](https://dojocoding.io/dojoos)** — Full developer environment and community
- **[Discord](https://dojocoding.io/discord)** — Join the community

---

## 📄 License

MIT License — free to use, modify, and distribute.

---

<p align="center">
  <strong>🥋 From vibecoder to engineer — one session at a time.</strong><br>
  <em>Free. Open source. By <a href="https://dojocoding.io">Dojo Coding</a>.</em>
</p>
