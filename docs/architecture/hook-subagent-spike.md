# ADR: Hook-to-Subagent Communication Pipeline

## Status

Proposed

## Context

CodeSensei is a Claude Code plugin that teaches programming concepts during vibecoding sessions. The core loop is:

1. User vibes (Claude writes/edits code, runs commands)
2. PostToolUse hooks fire, detecting what changed (file types, technologies, concepts)
3. Teaching content is delivered to the user alongside their coding session

The current implementation uses `hookSpecificOutput.additionalContext` to inject teaching triggers into the **main conversation context**. This means every code change appends an instruction like `"CodeSensei micro-lesson trigger: ..."` or `"CodeSensei inline insight: ..."` directly into Claude's context window. Claude in the main conversation thread is then expected to follow these instructions and produce teaching content inline.

This creates several problems:

- **Main context pollution**: Teaching instructions consume tokens in the user's primary coding conversation, competing with the actual work being done.
- **Unreliable execution**: The main Claude instance may ignore, abbreviate, or deprioritize the teaching instruction when focused on a complex coding task.
- **No separation of concerns**: The coding assistant and the teaching mentor are the same Claude instance, with conflicting priorities (ship code vs. teach concepts).
- **Scaling issues**: As the plugin adds more triggers (debugging insights, architecture explanations, security warnings), the additionalContext payloads grow and further pollute the main context.

The SRD explicitly identifies this as the top priority:

> "Shadow coaching is the product -- the subagent IS CodeSensei; everything else is secondary."
> "No main context injection -- trigger subagent via hooks, never use additionalContext for teaching."

The sensei subagent (`agents/sensei.md`) already exists with a full system prompt, belt-aware teaching behavior, and is configured to use the Haiku model. The missing piece is the **communication pipeline** between hooks and this subagent.

## Current Architecture

### Hook Flow (PostToolUse)

```
User codes --> Claude uses Write/Edit/Bash tool
                |
                v
        PostToolUse hook fires
                |
                v
        scripts/track-code-change.sh (or track-command.sh)
                |
                v
        1. Read stdin (JSON with tool_name, tool_input)
        2. Detect technology / concept from file extension or command pattern
        3. Update ~/.code-sensei/profile.json (session_concepts, concepts_seen)
        4. Output JSON to stdout:
           {
             "hookSpecificOutput": {
               "hookEventName": "PostToolUse",
               "additionalContext": "CodeSensei micro-lesson trigger: ..."
             }
           }
                |
                v
        Claude's main context receives the additionalContext string
                |
                v
        Main Claude is expected to follow the instruction and produce teaching
```

### What Exists

| Component | File | Purpose |
|-----------|------|---------|
| Hook config | `hooks/hooks.json` | Registers PostToolUse hooks for Write/Edit/MultiEdit and Bash |
| Code change tracker | `scripts/track-code-change.sh` | Detects file types, injects micro-lesson/inline insight triggers |
| Command tracker | `scripts/track-command.sh` | Detects CLI concepts (git, npm, docker, etc.), injects triggers |
| Session lifecycle | `scripts/session-start.sh`, `scripts/session-stop.sh` | Profile init, streak tracking, cleanup |
| Sensei agent | `agents/sensei.md` | Full teaching system prompt, belt-aware, Haiku model |
| Slash commands | `commands/*.md` | 7 user-invoked commands (explain, quiz, why, progress, etc.) |
| Skills | `skills/*/SKILL.md` | 10 auto-invoked teaching modules with concept analogies |

### Pros of Current Approach

- **Works today**: No protocol changes needed. The `additionalContext` mechanism is a documented hook output field.
- **Simple implementation**: Bash scripts output JSON, Claude receives a string. No orchestration layer.
- **Synchronous**: The teaching trigger arrives in the same turn as the code change, so context is fresh.
- **Low latency**: No extra API calls or subprocesses -- just a string appended to context.

### Cons of Current Approach

- **Main context pollution**: Every code change injects 50-150 tokens of teaching instructions into the main context window.
- **Unreliable**: Claude may ignore the instruction, especially during complex multi-step coding tasks.
- **Wrong model**: Teaching runs on the main model (likely Sonnet/Opus) instead of the cheaper Haiku model configured for the sensei agent.
- **No isolation**: If teaching output is poor, there is no way to iterate on it without affecting the coding experience.
- **Token budget conflict**: The more teaching content is injected, the less room the main model has for its primary coding task.
- **No teaching quality control**: The main model was not primed with the sensei system prompt, belt-awareness, or teaching philosophy. It receives a one-line instruction and improvises.

## Options Considered

### Option 1: Enhanced additionalContext with Subagent Delegation Instruction

**How it works**: Keep the current `additionalContext` mechanism but change the injected instruction from "produce teaching content" to "delegate to the sensei subagent." The hook output would say something like: `"Use the Task tool to invoke the 'sensei' agent with the following context: [concept, belt, file, etc.]"`

This relies on the main Claude instance using the Task tool (which spawns a subagent) when it reads the additionalContext instruction.

**Feasibility**: Medium

**Pros**:
- Requires zero changes to the hook scripts' output mechanism -- still uses `additionalContext`.
- The sensei agent already exists and is fully configured with teaching behavior.
- Teaching runs on Haiku (cheaper, faster) as specified in `agents/sensei.md`.
- Teaching content is produced by a purpose-built agent with the full system prompt, not improvised by the main model.
- The main model's context only receives the subagent's final output, not the raw trigger.

**Cons**:
- Still pollutes main context with the delegation instruction (though much shorter than full teaching content).
- Still relies on the main model actually following the instruction and invoking the Task tool -- this is unreliable under heavy workload.
- Adds one round-trip (main model reads instruction -> main model invokes Task -> subagent runs -> output returns).
- The main model may choose not to delegate if it deems the task low priority relative to the user's coding request.
- No guarantee of execution -- the instruction is advisory, not imperative.

**Implementation effort**: Low (1-2 hours). Change the `CONTEXT` strings in `track-code-change.sh` and `track-command.sh` to delegation instructions instead of direct teaching instructions.

### Option 2: Hook Writes to File, Command Reads from File (Decoupled Channel)

**How it works**: The PostToolUse hook writes teaching triggers to a local file (e.g., `~/.code-sensei/pending-lessons.jsonl`) instead of outputting them via `additionalContext`. A separate mechanism -- either a new slash command (`/code-sensei:teach`) or a modification to existing commands -- reads from this file and invokes the sensei agent.

Variants:
- **2a: User-triggered**: The user (or a CLAUDE.md instruction) periodically runs `/code-sensei:teach` which drains the pending lessons queue.
- **2b: SessionEnd-triggered**: The session-stop hook reads pending lessons and produces a batch summary.
- **2c: Periodic check**: A CLAUDE.md instruction tells Claude to check the pending file after every N tool uses.

**Feasibility**: Medium

**Pros**:
- Zero main context pollution -- hooks write to a file, not to additionalContext.
- Teaching is fully decoupled from the coding flow -- lessons accumulate and are delivered at appropriate moments.
- The sensei agent processes lessons in batch, which may produce higher-quality teaching (seeing patterns across multiple changes).
- File-based communication is simple and debuggable (just read the JSONL file).
- Works within the existing plugin protocol -- no new capabilities needed.

**Cons**:
- Teaching is no longer synchronous with code changes -- the "just-in-time" teaching moment is lost.
- Requires the user to take an action (run a command) or relies on CLAUDE.md instructions that may not be followed.
- Variant 2b (SessionEnd) means teaching only happens at the end, which defeats the "learn while you build" philosophy.
- File coordination between hooks and commands is fragile -- race conditions on `pending-lessons.jsonl` are possible.
- Adds complexity to the hook scripts (write to file) and command scripts (read from file, invoke agent).

**Implementation effort**: Medium (4-8 hours). Modify hook scripts to write to file, create a new command or modify existing ones to drain the queue, handle file locking and cleanup.

### Option 3: additionalContext Triggers Subagent via Structured Protocol

**How it works**: Instead of injecting a natural-language instruction via `additionalContext`, the hook outputs a structured JSON payload that the Claude Code runtime interprets as a directive to invoke a specific agent. This would require the hook output schema to support an `invokeAgent` field (or similar) alongside `additionalContext`.

Example hook output:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "invokeAgent": {
      "agent": "sensei",
      "context": {
        "trigger": "micro-lesson",
        "tech": "react",
        "file": "src/App.jsx",
        "belt": "white"
      }
    }
  }
}
```

**Feasibility**: Low (not currently supported by the Claude Code plugin protocol)

**Pros**:
- The cleanest architecture -- hooks declaratively trigger agents without polluting any context.
- Zero ambiguity -- the runtime knows exactly what to do, no reliance on Claude following instructions.
- The subagent receives structured context, not a natural-language instruction that could be misinterpreted.
- Fully decoupled: main model never sees teaching triggers, teaching model never sees coding context.
- Could be extended to support priority, debouncing, batching, etc.

**Cons**:
- **Does not exist in the current Claude Code plugin protocol.** The hook output schema only supports `additionalContext` (a string) and `hookEventName` within `hookSpecificOutput`. There is no `invokeAgent` or equivalent field.
- Would require a feature request to Anthropic or a protocol extension.
- Timeline is unknown and dependent on Anthropic's roadmap.
- Even if added, the behavior (subagent runs in a side channel? in the main conversation?) would need specification.

**Implementation effort**: N/A for the plugin side (trivial JSON change in hook scripts). Requires protocol-level changes from Anthropic.

### Option 4: Hook Spawns claude CLI Subprocess

**How it works**: The PostToolUse hook script, instead of outputting `additionalContext`, spawns a separate `claude` CLI process (or uses the Claude API directly via `curl`) to run the sensei agent's prompt with the teaching context. The result is written to a file that the user can optionally view.

```bash
# In track-code-change.sh, instead of echo additionalContext:
claude --agent sensei --context "$CONTEXT" --output ~/.code-sensei/last-lesson.md &
```

**Feasibility**: Low

**Pros**:
- Fully independent of the main conversation -- zero context pollution.
- The sensei agent runs with its own system prompt, on its own model.
- Could produce high-quality, standalone teaching content.

**Cons**:
- **Hooks run in a constrained environment.** There is no guarantee that the `claude` CLI is available or executable from within a hook script. Hooks are designed to be fast, lightweight processes that read stdin and write stdout -- spawning a full CLI session is outside their intended use.
- **API key / authentication**: A subprocess would need its own API credentials. Plugin hooks do not have access to the user's API key.
- **Cost**: Every code change would trigger an API call, potentially costing the user money without their awareness.
- **Latency**: Hook scripts are expected to complete quickly. Spawning a CLI process adds seconds of latency to every tool use, blocking the main Claude session.
- **Background execution**: If run as a background process (`&`), there is no way to deliver the output back to the user's conversation.
- **Security**: Executing arbitrary subprocesses from hooks raises trust concerns for the plugin protocol.

**Implementation effort**: High (significant engineering, authentication handling, cost management). Also potentially violates plugin protocol expectations.

### Option 5: Hybrid -- additionalContext Delegation + Pending Lessons File

**How it works**: Combine Options 1 and 2. The hook script does two things:

1. Writes the full teaching context to `~/.code-sensei/pending-lessons.jsonl` (for batch processing later).
2. Outputs a minimal `additionalContext` string that says: "A CodeSensei teaching moment was detected. If appropriate, use the Task tool to invoke the 'sensei' agent with the pending lesson from `~/.code-sensei/pending-lessons.jsonl`."

The main Claude model can choose to delegate to the sensei immediately (if the coding task is simple and there is bandwidth) or skip it (if busy with complex work). Either way, the lesson is persisted and can be delivered later via `/code-sensei:recap` or `/code-sensei:explain`.

Additionally, the `/code-sensei:recap` command is enhanced to always drain the pending lessons file, ensuring no teaching moment is lost even if the main model skipped delegation during the session.

**Feasibility**: High

**Pros**:
- **Best of both worlds**: Just-in-time teaching when possible, batch delivery when not.
- **Minimal context pollution**: The delegation instruction is a single short sentence, not a full teaching prompt.
- **No lost teaching moments**: Lessons persist in the file even if the main model ignores the additionalContext.
- **Graceful degradation**: If delegation fails, the `/code-sensei:recap` command catches everything.
- **Uses existing protocol**: No new fields needed. `additionalContext` carries the delegation hint, files carry the data.
- **Sensei agent runs on Haiku**: When delegation happens, teaching is produced by the purpose-built agent on the correct model.
- **Debuggable**: The JSONL file provides a complete audit trail of all teaching moments in a session.

**Cons**:
- More complex than Option 1 -- hooks now write to both stdout and a file.
- Still relies on the main model following the delegation instruction (not guaranteed).
- File management adds operational complexity (cleanup, rotation, race conditions on write).
- The "pending lessons" concept may confuse contributors who expect hooks to be self-contained.

**Implementation effort**: Medium (4-6 hours). Modify hook scripts to write to JSONL file + emit shorter additionalContext. Modify `/code-sensei:recap` to drain the pending file. Add file cleanup to `session-stop.sh`.

## Recommendation

**Option 5: Hybrid (additionalContext Delegation + Pending Lessons File)**, with a clear migration path toward Option 3 when the protocol supports it.

### Rationale

1. **It works today.** No protocol changes, no feature requests, no waiting on Anthropic. We can ship this in the current plugin version.

2. **It respects the North Star.** The sensei subagent becomes the primary teaching engine. The main context receives only a minimal delegation hint, not full teaching content. Teaching quality improves because the sensei agent has the full system prompt, belt-awareness, and teaching philosophy.

3. **No lost teaching moments.** The JSONL file acts as a durable queue. Even when the main model is too busy to delegate, every teaching opportunity is captured and available for batch delivery via `/code-sensei:recap`.

4. **Progressive enhancement.** The architecture naturally evolves:
   - **Phase 1 (now)**: Hybrid with additionalContext delegation hints
   - **Phase 2 (when available)**: If Anthropic adds `invokeAgent` to the hook output schema, remove the additionalContext delegation and switch to direct agent invocation (Option 3). The JSONL file remains as a fallback/audit trail.

5. **Low risk.** If the delegation hint is ignored by the main model, the user experience is the same as today (no teaching). But the pending lessons file ensures the content is available on demand. There is no regression path.

6. **Aligned with SRD priorities.** This directly addresses J1/J2 (hook-to-subagent pipeline redesign) and eliminates the anti-pattern of main context injection for teaching.

### Why Not the Others

- **Option 1 alone**: Better than today but still unreliable -- no fallback when delegation is skipped.
- **Option 2 alone**: Loses the just-in-time teaching that makes CodeSensei feel like a "shadow coach." Batch-only delivery defeats the core product promise.
- **Option 3**: The ideal architecture but does not exist yet. We should file a feature request with Anthropic and design for it, but we cannot block on it.
- **Option 4**: Fundamentally incompatible with the plugin protocol. Hooks are not meant to spawn long-running subprocesses or make API calls.

## Implementation Plan

### Phase 1: Hybrid Pipeline (estimated 4-6 hours)

**Step 1: Add JSONL writer to hook scripts**

Modify `scripts/track-code-change.sh` and `scripts/track-command.sh` to write structured teaching triggers to `~/.code-sensei/pending-lessons.jsonl`:

```jsonl
{"timestamp":"2026-03-03T12:00:00Z","type":"micro-lesson","tech":"react","file":"src/App.jsx","belt":"white","concept":"react-components"}
{"timestamp":"2026-03-03T12:01:00Z","type":"inline-insight","tech":"css","file":"src/styles.css","belt":"white","tool":"Edit"}
```

Use atomic writes (write to temp file, then `mv`) per the SRD requirement for data integrity.

**Step 2: Shorten additionalContext to delegation hint**

Replace the current verbose teaching instructions with a minimal delegation hint:

```
Before: "CodeSensei micro-lesson trigger: The user just encountered 'react' for the FIRST TIME (file: src/App.jsx). Their belt level is 'white'. Provide a brief 2-sentence explanation..."

After: "CodeSensei: New teaching moment detected (react, src/App.jsx). If the user is not in the middle of a complex task, use the Task tool to invoke the 'sensei' agent. Pass it the latest entry from ~/.code-sensei/pending-lessons.jsonl."
```

**Step 3: Update sensei agent to read pending lessons**

Add instructions to `agents/sensei.md` for reading from the pending lessons file when invoked via Task delegation:

```markdown
## When Invoked via Delegation
If you receive context about pending lessons, read `~/.code-sensei/pending-lessons.jsonl` to get the full teaching context. Process the most recent entry (or batch if multiple are pending). After processing, mark entries as delivered.
```

**Step 4: Enhance /code-sensei:recap to drain pending lessons**

Modify `commands/recap.md` to instruct the sensei agent to read all undelivered lessons from the JSONL file and produce a session summary.

**Step 5: Add cleanup to session-stop.sh**

Archive or clear `pending-lessons.jsonl` at session end. The session-stop hook already clears `session_concepts` from the profile; extend it to handle the lessons file.

**Step 6: Add file rotation and size limits**

Ensure the JSONL file does not grow unbounded:
- Rotate at session end (archive to `~/.code-sensei/lessons-archive/YYYY-MM-DD.jsonl`)
- Cap at 100 entries per session (oldest entries dropped)
- Total archive size capped at 1MB

### Phase 2: Protocol Enhancement (future, depends on Anthropic)

- File a feature request with Anthropic for `invokeAgent` support in hook output schema.
- Design the structured invocation format.
- When available, replace the additionalContext delegation hint with direct agent invocation.
- Keep the JSONL file as an audit trail and fallback.

## Open Questions

1. **Hook execution timeout**: How long do PostToolUse hooks have before they are killed? If the timeout is very short (< 1s), writing to a JSONL file might be unreliable. Need to verify that file I/O completes within the hook timeout.

2. **Task tool availability**: Can the main Claude instance always use the Task tool? Are there contexts (e.g., during a multi-step tool use chain) where Task is unavailable or would break the flow?

3. **Subagent output destination**: When the main model uses Task to invoke the sensei agent, where does the sensei's output appear? Is it visible to the user, or only to the main model? If only visible to the main model, it would need to relay the teaching content -- which partially defeats the isolation goal.

4. **Race conditions on profile.json**: Both hook scripts (`track-code-change.sh`, `track-command.sh`) and the sensei subagent read/write `~/.code-sensei/profile.json`. If they run concurrently, writes can be lost. The SRD already flags this (priority 3), but the hybrid approach makes it more acute since the subagent might be writing XP while a hook is updating concepts_seen. Atomic writes (temp file + `mv`) mitigate but do not fully solve this.

5. **Debouncing**: During rapid coding (e.g., Claude writes 10 files in a row), should every file change trigger a pending lesson? Or should the hook debounce and batch changes that happen within a short window (e.g., 5 seconds)? The current approach fires on every PostToolUse, which can be noisy.

6. **User consent / preferences**: Should users be able to control the teaching frequency? A `preferences.coaching_frequency` field (e.g., "every_change", "meaningful_only", "on_demand") in the profile would let users tune the experience. This is a product question but affects the pipeline design.

7. **Anthropic plugin protocol roadmap**: Has Anthropic signaled any plans for richer hook output schemas (e.g., agent invocation, tool chaining)? A conversation with DevRel or a review of the plugin protocol changelog would clarify whether Option 3 is months away or years away.

8. **JSONL file locking**: If multiple hooks fire simultaneously (e.g., a Write and a Bash in quick succession), both scripts might append to `pending-lessons.jsonl` at the same time. On POSIX systems, `echo >> file` appends are atomic for small writes, but `jq ... > file` is not. Need to ensure writes use append mode (`>>`) rather than overwrite.

9. **Delivered status tracking**: How should we mark lessons as "delivered" vs. "pending"? Options include: (a) separate files for pending vs. delivered, (b) a `delivered: true` field in each JSONL entry, (c) truncate the file after the recap command processes it. Option (c) is simplest; option (b) is most flexible.

10. **Skills auto-invocation**: The `skills/` directory contains auto-invoked teaching modules. How do these interact with the hook-to-subagent pipeline? Currently, skills are injected based on concept triggers -- should they be folded into the sensei agent's context when it processes a pending lesson?
