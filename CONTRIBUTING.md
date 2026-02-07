# Contributing to CodeSensei 🥋

Thank you for wanting to make coding education better! Here's how to help.

## Quick Contributions (No Code Required)

### 📝 Add Better Analogies
The best contributions are often better ways to explain things. If you have a great analogy for a programming concept, open a PR editing the relevant skill file in `skills/`.

A nurse writes a medical analogy for error handling — now every nurse learning to code gets it. A marketer explains APIs using campaign brief terminology — now every marketer has that "aha" moment. **Your domain knowledge makes CodeSensei better for everyone.**

### 🧩 Add Quiz Questions
Add questions to `data/quiz-bank.json`. Follow this format:
```json
{
  "belt": "white",
  "question": "Your question in plain language",
  "options": ["Wrong but plausible", "Correct answer", "Another plausible wrong answer"],
  "correct": 1,
  "explanation": "Why the answer is correct, teaching something even if they got it right",
  "hint": "One-line hint connecting to something they already know"
}
```

**Quiz quality rules:**
- NEVER test syntax memorization — vibecoders don't need to memorize syntax
- ALWAYS test concepts, understanding, and reasoning
- Wrong answers should be plausible, not obviously wrong
- Explanations should teach something new even if the user knew the answer

### 🌍 Translations
We want CodeSensei to teach in every language. To add a translation:
1. Create a directory: `skills/[language-code]/`
2. Translate the SKILL.md files
3. Add translated quizzes to the quiz bank

Priority languages: Spanish (es), Portuguese (pt), French (fr), Japanese (ja), Korean (ko)

## Code Contributions

### Setup
```bash
git clone https://github.com/DojoCodingLabs/code-sensei.git
cd code-sensei
```

### Testing Locally
```bash
# Open Claude Code
claude

# Add as local marketplace
/plugin marketplace add .

# Install
/plugin install code-sensei

# Test your changes
/code-sensei:explain
/code-sensei:quiz
/code-sensei:progress
```

### What We Need Help With
- **New skill modules** — Python, Rust, mobile dev, Web3
- **Smarter concept detection** in hook scripts
- **Profile sync** — optional cloud sync for cross-device progress
- **Leaderboard** — community leaderboard (opt-in)
- **GitHub badge** — show your belt on your README

### PR Guidelines
1. Keep it focused — one feature or fix per PR
2. Test with Claude Code locally before submitting
3. Update quiz-bank.json if adding new concepts
4. Follow the existing tone: encouraging, simple, analogy-first

## Code of Conduct

Be kind. We're building a tool that helps people learn. Everyone is welcome regardless of skill level, background, or experience.

## Questions?

Open an issue or join us on [Discord](https://dojocoding.io/discord).

---

*CodeSensei by [Dojo Coding](https://dojocoding.io) — learn to code while you vibecode. Free. Open source.*
