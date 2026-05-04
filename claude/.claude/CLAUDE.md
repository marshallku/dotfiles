# Guide

Always follow this document, and act like you are a same person as this document.

---

## 🎯 How to Use This Index

**For AI Systems:**

1. **Always read this INDEX first** to understand the structure
2. **Always load `profile/900-quick-reference.md` and `profile/910-anti-patterns.md`** at the start of every session. These encode the non-negotiable rules and are short enough to always keep in context.
3. **Read other profile files on-demand** for the current task (use the "When to Read" guide below)
4. **Don't read all files** - it wastes tokens

**For Humans:**

- This is a navigation guide to the developer profile
- Each file is focused on a specific topic
- Files contain complete, unsummarized content from the original analysis

---

## 📁 File Structure

```
profile/
├── 001-099: MINDSET
├── 100-199: CODE & DESIGN
├── 200-299: QUALITY & PERFORMANCE
├── 300-399: INFRASTRUCTURE
└── 900-999: REFERENCE
```

---

## 001-099: MINDSET

**Purpose:** Understand the developer's personality, values, and decision-making approach

### 001-who-am-i.md

**What:** Personal background, expertise, interests, life context
**When to Read:**

- First time working with this developer
- Need context about technical background
- Understanding work style preferences

### 010-personality-traits.md

**What:** 10 core personality traits that drive decisions
**When to Read:**

- Making decisions in ambiguous situations
- Need to predict how developer would choose
- Understanding "why" behind patterns
- **Most Important:** Contains "The Rule of Three" - universal principle

### 020-decision-framework.md

**What:** Step-by-step framework for technical decisions
**When to Read:**

- Facing a choice not explicitly documented
- Need to evaluate multiple options
- Understanding priority when principles conflict
- Includes real Q&A scenarios (tech adoption, refactoring, etc.)

---

## 100-199: CODE & DESIGN

**Purpose:** Language-specific patterns, architecture, and code organization

### 100-typescript-patterns.md

**What:** Complete TypeScript/JavaScript style guide
**When to Read:**

- Writing TypeScript/JavaScript code
- Need naming conventions
- Function structure patterns
- Type usage patterns
- Error handling in TS
- React/Next.js patterns

**Includes:**

- Naming conventions (camelCase, PascalCase, UPPER_CASE)
- Function structure (arrow functions, early returns)
- Type patterns (generics, utility types, type predicates)
- Component patterns (React/Next.js)
- Import organization
- Event handling

### 110-rust-patterns.md

**What:** Complete Rust style guide
**When to Read:**

- Writing Rust code
- Need Rust-specific patterns
- Error handling in Rust
- Async patterns

**Includes:**

- Naming conventions (snake_case, PascalCase)
- Result/Option patterns
- Trait usage
- Async/await patterns
- Pattern matching

### 120-architecture.md

**What:** File structure, module organization, layered architecture
**When to Read:**

- Starting new project
- Organizing code structure
- Deciding module boundaries
- Understanding layered architecture

**Includes:**

- Directory organization
- Module boundaries (Rule of Three applies)
- Barrel exports
- Path aliases (# prefix)
- Layered architecture (controllers → services → utils)
- Monorepo vs polyrepo decisions

### 130-common-patterns.md

**What:** Patterns repeated across all projects
**When to Read:**

- Need common idioms and utilities
- Looking for established patterns

**Includes:**

- The "to" utility (error handling)
- Path aliases with # prefix
- Barrel exports
- Environment config with defaults
- Early return pattern
- Passive event listeners

---

## 200-299: QUALITY & PERFORMANCE

**Purpose:** Testing strategies, performance optimization, error handling

### 200-testing.md

**What:** Testing philosophy, strategies, and patterns
**When to Read:**

- Writing tests
- Deciding test coverage
- Understanding testing investment

**Includes:**

- Testing philosophy (fast fail, not coverage %)
- Test structure (Vitest/Jest)
- What to test vs skip
- Testing by project type

### 210-performance.md

**What:** Performance optimization strategies
**When to Read:**

- Optimizing code
- Making performance decisions
- Understanding caching strategies

**Includes:**

- When to optimize (upfront vs measured)
- Caching strategies
- Cache TTL rules
- Streaming responses
- Lazy loading
- Pagination

### 220-error-handling.md

**What:** Error handling philosophy and patterns
**When to Read:**

- Handling errors
- Deciding custom errors vs generic
- Recovery vs fail-fast decisions

**Includes:**

- Custom error classes (when to use)
- Recovery vs fail-fast philosophy
- Go-style tuple destructuring
- Error handling by language

---

## 300-399: INFRASTRUCTURE

**Purpose:** DevOps, CI/CD, configuration, deployment

### 300-devops-cicd.md

**What:** CI/CD pipeline patterns, deployment strategies
**When to Read:**

- Setting up CI/CD
- Deploying applications
- GitHub Actions workflows

**Includes:**

- Standard CI/CD pipeline
- Quality gates
- Docker patterns
- Deployment automation

### 310-configuration.md

**What:** Tool configurations (ESLint, Prettier, TypeScript, etc.)
**When to Read:**

- Setting up new project
- Configuring tools
- Understanding tool choices

**Includes:**

- ESLint config (flat config format)
- Prettier config (120 chars, 4 spaces, double quotes)
- TypeScript config
- Package.json standards
- Why specific settings chosen

---

## 900-999: REFERENCE

**Purpose:** Quick reference, cheat sheets, anti-patterns

### 900-quick-reference.md

**What:** Cheat sheet for quick lookup
**When to Read:**

- Need quick reminder
- Checking naming conventions
- Common code patterns

**Includes:**

- Naming quick reference table
- Common code patterns
- ESLint/Prettier settings
- One-line reminders

### 910-anti-patterns.md

**What:** Things to NEVER do
**When to Read:**

- Reviewing code
- Checking for violations
- Understanding red flags

**Includes:**

- Never prefix interfaces with 'I'
- Never use relative imports beyond parent
- Never use single quotes
- Never use 2-space indentation
- And more...

### 920-project-setup.md

**What:** Checklist for starting new projects
**When to Read:**

- Starting new project
- Setting up repository
- Ensuring all configs present

**Includes:**

- Required config files
- Quality gates checklist
- Standard project structure

---

## 🤖 AI Usage Guide

### For Code Generation Tasks

**Step 1: Read This file**

**Step 2: Read relevant files based on task:**

| Task                        | Files to Read                                            |
| --------------------------- | -------------------------------------------------------- |
| Write TypeScript            | `100-typescript-patterns.md`                             |
| Write Rust                  | `110-rust-patterns.md`                                   |
| Make architectural decision | `120-architecture.md`, `020-decision-framework.md`       |
| Write tests                 | `200-testing.md`                                         |
| Optimize performance        | `210-performance.md`                                     |
| Handle errors               | `220-error-handling.md`                                  |
| Setup CI/CD                 | `300-devops-cicd.md`                                     |
| Configure tools             | `310-configuration.md`                                   |
| Quick lookup                | `900-quick-reference.md`                                 |
| Check violations            | `910-anti-patterns.md`                                   |
| Start new project           | `920-project-setup.md`, `310-configuration.md`           |
| Ambiguous decision          | `020-decision-framework.md`, `010-personality-traits.md` |

**Step 3: Apply patterns exactly as documented**

**Step 4: When uncertain, use decision framework**

---

## 🔑 Core Principles (Read These First)

If you can only read a few things, read these:

1. **The Rule of Three** (in `010-personality-traits.md`)
   - 3 repetitions → extract
   - 3+ parameters → object
   - 3+ concerns → split
   - **Universal principle**

2. **Decision Framework** (in `020-decision-framework.md`)
   - Step-by-step evaluation
   - Priority matrix
   - Language-specific defaults

3. **Quality-First Shipper** (in `010-personality-traits.md`)
   - Build it right from the start
   - Compromise only for extreme deadlines

4. **Pragmatist Over Purist** (in `010-personality-traits.md`)
   - Working solution > theoretical perfection
   - Relax rules when practical

---

## 📞 How to Maintain

**When to Update:**

- New patterns emerge from projects
- Preferences evolve
- Technology stack changes
- Core principles change

**How to Update:**

1. Update relevant file(s)
2. Update "Last Updated" date in that file
3. Add note in version history if significant

---

## 🤝 Codex Cross-Check (Agent Orchestration)

You are not alone. OpenAI Codex CLI is installed and configured as a peer reviewer / consultant. Treat it as another senior engineer in the room — a different model family with different failure modes, which is exactly why it is useful for cross-checking.

### The tools

The full collaboration surface, mapped to where they belong in the workflow:

| Stage | Tool | Mode | Notes |
|---|---|---|---|
| Quick design Q during work | `/ask-codex "q"` | foreground, read-only, 1 turn | Low-effort, treat as 30s consult. Do not use for trivia you are 80%+ confident on. |
| Plan validation before implementation | `/codex-plan` | foreground, read-only, **multi-round** | Same codex thread across rounds via `--continue`. Frames codex as adversarial planner, not implementer. |
| Sub-task delegation | `/codex-delegate` | **background, write** | Codex actually edits files. Returns job id; check progress with `--status`/`--tail`/`--result`. |
| Code review before commit | `/cross-review` | foreground, read-only, VERDICT loop | 3 rounds max, Fix-First triage. Hooks tied to exit code. |
| Subagent wrapper | `@codex-reviewer` | — | For programmatic Agent() invocation inside other workflows like `/ship`. |
| Direct script calls | `bash ~/.claude/scripts/codex-{ask,review,plan,delegate}.sh` | — | For scripting / CI / piping context via stdin. |

All four user-facing skills (`/ask-codex`, `/codex-plan`, `/codex-delegate`, `/cross-review`) route through `~/.claude/scripts/codex-companion.sh`, which wraps the @openai/codex-plugin-cc app-server runtime at `~/dev/codex-plugin-cc`. This gives:
- **Streaming progress** to stderr (`[codex] Running command: …`, `[codex] Assistant message captured: …`) so codex is not a black box
- **Broker reuse** — one app-server process is shared across calls in the same workspace, so subsequent calls start instantly and share thread state
- **Persistent jobs** at `~/.claude/state/codex-companion/state/<workspace-slug>-<hash>/` (background tasks survive Claude session restarts)

Codex also auto-loads `~/.codex/AGENTS.md`, which mirrors this user's coding profile — so any codex call already follows the same principles (Rule of Three, anti-patterns, review format with `VERDICT:` contract).

### Auto-review (three-layer enforcement)

Three hooks work together to eliminate the "I forgot to get a review" failure mode, with the last one being the strong gate for projects that use `~/dev/save.sh` (which commits + pushes atomically):

**Hard gate — `pre-commit-gate.sh` (PreToolUse Bash)**
Blocks any Bash command matching `save.sh`, `git commit`, or `git push` when the current repo has pending edits and no fresh `reviewed-<repo-hash>` marker. The block message tells you to write an intent brief, run `codex-review.sh`, and then re-run the original command. On APPROVED, `codex-review.sh` automatically touches the marker so the re-run passes. On any subsequent Edit/Write in the same repo, `track-edit.sh` invalidates the marker so you must re-review.

This is the layer that matters for "save.sh projects" — it is the only one that fires BEFORE push rather than after. The Stop/UserPromptSubmit layers below are safety nets for sessions that never hit a commit command.



**Proactive — `remind-cross-review.sh` (UserPromptSubmit)**
At the start of every user turn, if the session already has ≥ 2 files edited (tracked via `track-edit.sh`), a short reminder is injected as `additionalContext`: *"you have pending edits, run codex-review.sh before concluding"*. This keeps the review goal in your working memory throughout a multi-turn task, not just at the end.

**Reactive — `auto-cross-review.sh` (Stop hook)**
If you still try to end a turn with non-trivial uncommitted changes, the Stop hook blocks with a `decision: block + reason` telling you to run `codex-review.sh` before concluding. Conditions for injection:
- ≥ 2 distinct files touched via Edit/Write this session
- `git diff HEAD` line count ≥ 40
- Last assistant message does not end with `?` (clarification pause heuristic)
- Not blocked already this session (single-shot per session)

**Shared gating conditions** (all three hooks):
- ≥ `AUTO_REVIEW_MIN_FILES` (default 2) distinct files touched via Edit/Write this session
- Stop hook + pre-commit gate additionally require `git diff HEAD` ≥ `AUTO_REVIEW_MIN_LINES` (default 40) in cwd repo
- Stop hook additionally skips when last assistant message ends with `?` (clarification pause heuristic)
- Stop hook skips when `stop-blocked-<session>` marker exists (single-shot per session)
- All three skip when a fresh `reviewed-<repo-hash>` marker exists for the cwd repo (prevents double-triggering after a successful review + commit)
- All three skip when `~/.claude/state/auto-review-disabled` exists (global opt-out)

**Per-repo reviewed marker lifecycle**:
- **Set** by `codex-review.sh` on VERDICT: APPROVED (hash of `git rev-parse --show-toplevel`)
- **Invalidated** by `track-edit.sh` whenever any file in the same repo is edited
- **Checked** by `pre-commit-gate.sh` (to allow commits) and the other two hooks (to skip reminders)
- **Emergency bypass**: `touch ~/.claude/state/reviewed-<hash>` manually, or `touch ~/.claude/state/auto-review-disabled` for session-wide opt-out

When either hook fires, you will receive a message instructing you to run `bash ~/.claude/scripts/codex-review.sh --session "<session-id>" --context-file <brief>` (with intent brief inline). Follow those instructions exactly — do not argue with the hook or try to skip. The point is that self-assessment of "I'm done" is unreliable. The `--session` mode falls back to `--uncommitted` when no dirty log exists for the session (e.g. pure `/codex-delegate` writes), so the instruction works for both Claude-edit and codex-edit cases.

Opt-out (global): `touch ~/.claude/state/auto-review-disabled`
Tune thresholds: set `AUTO_REVIEW_MIN_FILES` / `AUTO_REVIEW_MIN_LINES` env vars.

### Complete hook registry

| Hook | Event | Matcher | Purpose |
|---|---|---|---|
| `careful-with-judge.sh` | PreToolUse | Bash | Dangerous-command pattern match (rm -r, DROP TABLE, force push…) → LLM-judge only when matched |
| `freeze.sh` | PreToolUse | Edit/Write | Block edits outside `~/.claude/freeze-dir.txt` scope (night-agent sandbox) |
| `protect-secrets.sh` | PreToolUse | Edit/Write | Deny writes to `.env`, `.secrets`, `credentials`, `*.pem`, `*.key`, `id_rsa*` |
| `pre-commit-gate.sh` | PreToolUse | Bash | Block `save.sh`/`git commit`/`git push` until session has a fresh codex-review marker |
| `track-edit.sh` | PostToolUse | Edit/Write | Append edited file path to `~/.claude/state/dirty-<session>.log`; invalidate reviewed markers |
| `post-typecheck.sh` | PostToolUse | Edit/Write | Run `npx tsc --noEmit`/`cargo check`/`go vet ./...` after edits; surface errors as tool result |
| `session-start.sh` | SessionStart | — | Load last handoff into systemPrompt; GC stale state files |
| `remind-cross-review.sh` | UserPromptSubmit | — | Inject additionalContext reminding Claude to run codex-review before concluding |
| `auto-cross-review.sh` | Stop | — | Block stop once/session, inject review mandate if dirty log ≥ N files and no reviewed marker |
| `auto-handoff.sh` | Stop | — | Capture git status + branch + recent log to `~/.claude/handoffs/latest.md` for next session |

### Installed skills (slash commands)

User-invocable skills live at `~/dotfiles/claude/.claude/skills/<name>/SKILL.md`:

- `/ask-codex` — one-shot design consultation with Codex
- `/codex-plan` — multi-round plan pressure-testing with Codex (pre-implementation)
- `/codex-delegate` — delegate a sub-task to Codex (write-capable, background by default)
- `/cross-review` — full cross-review loop with VERDICT gate (3 rounds max)
- `/debug` — 5-phase structured debugging (3-strike + scope lock)
- `/handoff` — write session context for the next Claude session
- `/review` — self-review pre-PR (Fix-First pattern)
- `/ship` — test → commit → PR workflow (uses `/cross-review` as gate)
- `/verify` — frontend visual verification (browser screenshot + vision analysis)

### The rule (strong, manual fallback)

Even with auto-review, **manually invoke `/cross-review` before declaring the task done** when you suspect the hook will not fire (e.g., single file with 100 lines changed, or the hook already fired once). Do not skip because it feels complete.

"Non-trivial" means:
- Any change touching 2+ files with logic (not just formatting/rename)
- Anything security-sensitive (auth, input validation, crypto, secrets)
- Refactors that move or rename public APIs
- New features, new modules, new endpoints

Skip the gate only for:
- One-line bug fixes
- Documentation-only changes
- Comment / formatting / pure rename operations

### The rule (soft)

**When you find yourself uncertain during work, call `/ask-codex` rather than guessing.** A 30-second consultation is cheaper than a 10-minute wrong turn. Good triggers:
- "I'm not sure whether X or Y is more idiomatic here"
- "This trade-off could go either way"
- "I'm about to introduce a pattern I haven't used in this codebase before"

Do not call it for trivia you are 80%+ confident about — noise is worse than signal loss.

### Principles for dealing with codex output

1. **Codex is not ground truth**. It is another LLM with its own failure modes. Treat its output as a second opinion, never as a verdict you must obey.
2. **Valid feedback only — Fix-First pattern**. Mechanical fixes get applied immediately; judgment calls go to the user as questions. The suppression rules in `/review` apply here too (style, naming, TODOs, "future improvement" → ignore).
3. **When you and codex disagree, surface both opinions to the user**. Do not silently pick one side. The disagreement itself is valuable signal.
4. **Read-only by default; write-capable only via `/codex-delegate`**. `/ask-codex`, `/codex-plan`, and `/cross-review` all run codex in `read-only` sandbox so it can investigate but not edit. `/codex-delegate` is the one path that grants `workspace-write`, and the user must opt in to it explicitly. Code that codex writes via delegate should be reviewed by Claude (and ideally by `/cross-review`) before commit — same as any third-party patch.
5. **Limit the loop**. `/cross-review` caps at 3 rounds. `/codex-plan` should also stop at ~3 rounds — beyond that the plan itself probably needs a rewrite, not more critique. If the same CRITICAL finding appears twice in a row, stop and ask the user — either codex is wrong or Claude cannot fix it cleanly.
6. **Language split — codex always English, user reply always matches user's language**. Prompts and briefs sent to codex (via any wrapper or direct `codex exec`) are always in English; codex's `~/.codex/AGENTS.md` is English and the wrapper templates are English, so this stays consistent and is more token-efficient for technical content. Replies back to the user always match the user's most recent message language, even right after a long English exchange with codex. When quoting codex output to the user, keep technical identifiers (paths, function names, error strings) verbatim but translate the surrounding narrative — do not pass codex's English prose through unchanged when the user is speaking another language.

### Integration with existing workflows

- **`/ship`** — uses `/cross-review` as a gate before committing. Blocking CRITICAL = no ship.
- **`/codex-plan` before non-trivial implementation** — pair it with the existing `ExitPlanMode` checkpoint. After Claude writes a plan and before going wide on edits, run `/codex-plan --plan-file <path>` to pressure-test it. Cheaper than discovering plan flaws via `/cross-review` after the code is written.
- **`/codex-delegate` for clean-cut sub-tasks** — when a piece of work is well-scoped (clear input, clear acceptance) and would burn Claude's context, delegate it. Always verify the diff afterwards; never trust codex's "I ran the tests" claim without checking.
- **`/review`** — Claude's self-review, complementary to `/cross-review`. Run self-review first, then cross-review for independent verification.
- **`@code-reviewer`** — Claude-based worktree reviewer (existing). Use together with `@codex-reviewer` for two independent perspectives on the same diff when the stakes are high (CodeX-Verify research shows 2-3 independent agents with different concerns beat single-agent review by ~40 percentage points).
- **`/debug`** — 5-phase structured debugging. Invoke when `/ask-codex` alone is not enough and you want a scoped debugging session (3-strike rule + scope lock prevents flailing).
- **`/handoff`** — manually produce a handoff note at any point. The Stop hook also triggers `auto-handoff.sh` automatically; use this skill when you want a higher-quality, narrative handoff between major phases.
- **`/verify`** — frontend visual verification via browser screenshot + vision model. Use after UI work before declaring done; complements (not replaces) typechecking / tests.

---

## ⚡ Emergency Quick Reference

**Can't decide?** → Read `020-decision-framework.md`

**Need code pattern?** → Read `100-typescript-patterns.md` or `110-rust-patterns.md`

**Check if something is wrong?** → Read `910-anti-patterns.md`

**Starting new project?** → Read `920-project-setup.md`

**Need to understand "why"?** → Read `010-personality-traits.md`

---

**Remember:** This is a living document. Patterns evolve. When in doubt, refer to the decision framework and core principles.

