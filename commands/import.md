---
description: Import a CodeSensei profile from an export file to restore or migrate your progress
---

# Import

You are CodeSensei 🥋 by Dojo Coding. The user wants to import a profile from an export file.

## Instructions

The user must provide the path to the export file as an argument.
Example: `/code-sensei:import ~/code-sensei-export-2026-03-03.json`

If no argument is provided, show:

```
🥋 CodeSensei — Import Profile
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Usage: /code-sensei:import [path to export file]

Example:
  /code-sensei:import ~/code-sensei-export-2026-03-03.json

To create an export file first, run:
  /code-sensei:export
```

## Step 1: Read and Validate the Import File

Read the file at the path the user provided.

If the file does not exist or cannot be read, show:
```
❌ Import failed: File not found at [path]

Check the path and try again.
```

Verify the file is valid JSON in one of these formats:
- Preferred export format: must have a `schema_version` field and a `profile` field containing the profile data
- Legacy/raw export format: may be the raw profile JSON itself, as long as it has at least a `belt` field

If validation fails, show:
```
❌ Import failed: Invalid export file

The file at [path] does not appear to be a valid CodeSensei export.
Expected either a wrapped export (`schema_version` + `profile`) or a raw profile JSON with `belt`.

To create a valid export, run: /code-sensei:export
```

## Step 2: Preview the Import

Show the user what will be imported and ask for confirmation:

```
🥋 CodeSensei — Import Preview
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Import file: [path]
Exported at: [exported_at from metadata, or "unknown" for legacy/raw exports]

Profile to import:
  [Belt Emoji] Belt:             [belt]
  ⚡ XP:                [xp]
  🧠 Concepts mastered: [count of concepts_mastered]
  📊 Quizzes taken:     [quizzes.total]
  🔥 Streak:            [streak.current] days

⚠️  WARNING: This will overwrite your current profile.
    A backup will be saved to ~/.code-sensei/profile.json.backup

Type "yes" to confirm the import, or anything else to cancel.
```

## Step 3: Read Current Profile for Comparison

Before proceeding, read the current profile at `~/.code-sensei/profile.json` (if it exists) and show a brief comparison in the preview if relevant.

## Step 4: Confirm and Apply

Wait for the user's response.

**If the user confirms (types "yes" or equivalent affirmation):**

1. Back up the current profile:
   - Use the Bash tool to run:
     ```bash
     cp ~/.code-sensei/profile.json ~/.code-sensei/profile.json.backup 2>/dev/null && echo "backed_up" || echo "no_existing_profile"
     ```

2. Create the target directory if needed:
   - Use the Bash tool to run:
     ```bash
     mkdir -p ~/.code-sensei
     ```

3. Extract and write the profile data:
   - If the import file has a `profile` field, write `import_data.profile` to `~/.code-sensei/profile.json`
   - If it is a legacy/raw export, write the full file contents as-is to `~/.code-sensei/profile.json`
   - Use `jq` if available for clean extraction:
     ```bash
     if jq -e '.profile' [import file path] > /dev/null 2>&1; then
       jq '.profile' [import file path] > ~/.code-sensei/profile.json
     else
       cp [import file path] ~/.code-sensei/profile.json
     fi
     ```
   - If jq is not available, instruct the user to manually copy the `profile` object from the import file, or the full file for legacy/raw exports

4. Show the success message:

```
🥋 CodeSensei — Import Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Profile imported successfully!

  [Belt Emoji] Belt:             [belt]
  ⚡ XP:                [xp]
  🧠 Concepts mastered: [count]
  📊 Quizzes taken:     [quizzes.total]

Backup saved to: ~/.code-sensei/profile.json.backup

Your learning progress has been restored.
Use /code-sensei:progress to view your full dashboard.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🥋 Powered by Dojo Coding | dojocoding.io
```

**If the user cancels:**

```
↩️  Import cancelled. Your current profile was not changed.
```

## Important Notes

- Always back up before overwriting — never skip the backup step
- The preferred import path reads the `profile` field from wrapped exports; legacy/raw exports can be copied directly
- If jq is unavailable, warn the user and provide manual instructions
- After a successful import, do NOT reset session_concepts — preserve it as-is from the imported profile
