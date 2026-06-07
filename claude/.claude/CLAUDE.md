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
| Subagent wrapper | `@codex-reviewer` | — | For programmatic Agent() invocation inside other workflows like `/iterate`. |
| Direct script calls | `bash ~/.claude/scripts/codex-{ask,review,plan,delegate}.sh` | — | For scripting / CI / piping context via stdin. |

All four user-facing skills (`/ask-codex`, `/codex-plan`, `/codex-delegate`, `/cross-review`) route through `~/.claude/scripts/codex-companion.sh`, which wraps the @openai/codex-plugin-cc app-server runtime at `~/dev/codex-plugin-cc`. This gives:
- **Streaming progress** to stderr (`[codex] Running command: …`, `[codex] Assistant message captured: …`) so codex is not a black box
- **Broker reuse** — one app-server process is shared across calls in the same workspace, so subsequent calls start instantly and share thread state
- **Persistent jobs** at `~/.claude/state/codex-companion/state/<workspace-slug>-<hash>/` (background tasks survive Claude session restarts)

Codex also auto-loads `~/.codex/AGENTS.md`, which mirrors this user's coding profile — so any codex call already follows the same principles (Rule of Three, anti-patterns, review format with `VERDICT:` contract).

### Waiting on codex — block foreground, do NOT poll

Codex calls (`/codex-plan`, `/cross-review`, a heavy `/ask-codex`) are slow — a multi-round plan or review runs for minutes. The wrong pattern, observed repeatedly in past sessions, is to launch codex and then wait on it with the **Monitor** tool (poll-for-condition), which times out and forces a manual re-arm. Each re-arm burns a turn and the loop reads as "still waiting" when nothing is actually progressing. That polling — not foreground execution — was the actual friction. Don't do it.

**Default: run the codex wrapper script foreground and block on it — ALWAYS pass an explicit `timeout`.** In the work-unit gate a cross-review or plan is the step that decides whether you commit; you wait on its verdict regardless, so there is nothing to overlap.

The one thing that makes foreground "look broken": the Bash tool's **default timeout is 120 s (2 min)**, but a real review/plan runs 3–8 min (the wrappers' own internal caps are 1200 s for review, 420 s for plan). With the default, the Bash call is killed at 2 min and you see a half-finished review that "just exited" — so **set `timeout: 600000`** (the 10-min Bash maximum) on every foreground codex call. That, not backgrounding, is the fix. `notify_codex_done` still pings you on completion so you can step away during the wait.

**Do NOT background a gating review/plan.** A `run_in_background` Bash call returns instantly, so with nothing else to do you end the turn — the session goes idle and the verdict arrives detached from the flow. That is exactly the "nothing executes, it just exits" symptom. Background is only for the rare case where you have genuine independent work to do alongside codex (and never edit the same files codex is reviewing); there a backgrounded Bash command re-invokes you automatically when it exits.

- Codex call gating the next step (the usual case) → **foreground, `timeout: 600000`, block.**
- Codex call with real parallel work alongside (rare) → `run_in_background: true`, continue; you are re-invoked when it exits.
- **Never** → a `Monitor` poll-loop + re-arm, or a hand-rolled "poll for completion marker" background script, for a *local* codex job. Reserve `Monitor`/`ScheduleWakeup` for external state the harness cannot observe (a remote CI run, a deploy), never for a background job the harness already tracks.

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

### Intent capture (workflow gate — fires upstream of review)

**Why this exists.** Cross-review at commit time can't recover what intent-extraction missed at edit time. The mechanism: LLMs optimize for plausible next-token completion + RLHF rewards helpfulness over precise execution, so on a casual prompt they fill ambiguity with majority-pattern defaults and drift starts in the *first response*. The fix is to capture *user intent* before any non-trivial edit and persist it as a SourceItem so future review can compare *code-vs-intent* (a narrow comparison task) instead of *code-vs-prompt* (the same failure mode the writer had).

**Where intent lives.** `~/docs/sources/sessions/<repo-slug>/<YYYY-MM-DD>-session-<short-id>.md` following the SourceItem standard (see `~/docs/CLAUDE.md:41` for envelope). Immutable per `~/docs` rules — revisions create a new file with `supersedes:` pointing at the prior. The ack state lives separately in `~/.claude/state/intent-acks/<basename>.ack` so the SourceItem itself stays raw-immutable.

**Schema (v1) — fields the intent file is validated on:**
- `acceptance_criteria` ≥1 — observable success signals (theater wedge: forces verifiable claims, not introspection)
- `out_of_scope` ≥1 — explicit non-goals (counters "do more than asked" sycophancy bias)
- `assumptions` ≥1 — unstated assumptions surfaced (so codex review can flag if any get violated)
- `goal`, `summary`, `commit_summary` — non-empty, single line each
- `verification.e2e` ∈ {required, not_applicable, deferred} — declares e2e applicability; if `deferred`, `verification.reason` required
- Plus SourceItem fields: `source_type: sessions`, `canonical_url: claude://session/<id>`, `content_hash` (sha256 of immutable payload excluding `## Notes`), `dedupe_key`, `tags` (3-axis: stack/domain/activity), `repo: owner/repo`

**Hooks involved:**

1. **`intent-capture.sh` (PreToolUse Edit|Write)** — On first non-trivial edit (≥`AUTO_INTENT_MIN_FILES` files or ≥`AUTO_INTENT_MIN_LINES` weighted diff lines, defaults inherit from `AUTO_REVIEW_*`), blocks the edit and instructs Claude to write the intent file + ask user for ack + run `intent-finalize.sh`. Allows on:
   - `AUTO_INTENT_SOFT_GATE=1` (dogfood default — warn-only)
   - `intent-capture-disabled` global marker
   - intent file already exists, ack marker exists, and ack is newer than intent file
2. **`intent-finalize.sh`** (helper, Claude invokes) — Validates schema; computes `content_hash` over the immutable payload (frontmatter excluding hash fields + body before `## Notes`); computes `dedupe_key = sha256(canonical_url + content_hash)`; writes ack marker; registers `intent-active-<session>-<repo>.path` so the hook fast-paths subsequent edits.
3. **`pre-commit-gate.sh` extension** — In hard-gate mode, also blocks `save.sh`/`git commit`/`git push` when the active intent marker is missing, ack is stale (intent modified after ack), or `verification.e2e: required` but no test/e2e evidence in transcript.
4. **`codex-review.sh --intent-file <path>`** — Reframes review from "is this good code?" to "does this diff match this intent?" by injecting goal/acceptance_criteria/out_of_scope/assumptions as a `TASK INTENT` section. Codex returns CRITICAL findings classified `[INTENT-MISMATCH]` or `[CODE-DEFECT]`.
5. **`save.sh` extension** — On successful commit/push, appends `Intent-Summary:` + `Intent-Ref:` trailers to the commit body (commit_summary from the intent file) and runs `git -C ~/docs commit` with `ingest: session intent <slug>` to persist the SourceItem in the private SSoT.

**Bypass / tuning env vars:**
- `AUTO_INTENT_SOFT_GATE=1` (default during initial rollout) — warn-only, no block
- `AUTO_INTENT_SOFT_GATE=0` — hard block on missing intent
- `AUTO_INTENT_MIN_FILES` / `AUTO_INTENT_MIN_LINES` — gate thresholds (inherit from `AUTO_REVIEW_*` if unset)
- `touch ~/.claude/state/intent-capture-disabled` — session-wide opt-out (intent gate only; review gate still fires)
- `touch ~/.claude/state/auto-review-disabled` — disables both review and intent gates

**The flow (when not bypassed):**
```
user prompt → first Edit/Write
  ↓ intent-capture.sh blocks
Claude writes intent file (template provided in block message)
  ↓ Claude surfaces goal+AC+OOS to user, asks for ack
user replies "proceed" (or modifications)
  ↓ Claude runs intent-finalize.sh (validates schema, sets ack)
edits proceed normally, codex-review.sh --intent-file at end
  ↓ VERDICT classification routes [INTENT-MISMATCH] vs [CODE-DEFECT]
save.sh injects Intent-Summary trailer + ~/docs ingest commit
```

### Complete hook registry

| Hook | Event | Matcher | Purpose |
|---|---|---|---|
| `careful-with-judge.sh` | PreToolUse | Bash | Dangerous-command pattern match (rm -r, DROP TABLE, force push…) → LLM-judge only when matched |
| `freeze.sh` | PreToolUse | Edit/Write | Block edits outside `~/.claude/freeze-dir.txt` scope (night-agent sandbox) |
| `protect-secrets.sh` | PreToolUse | Edit/Write | Deny writes to `.env`, `.secrets`, `credentials`, `*.pem`, `*.key`, `id_rsa*` |
| `intent-capture.sh` | PreToolUse | Edit/Write | Capture user intent (SourceItem in `~/docs/sources/sessions/`) before non-trivial sessions accumulate drift |
| `pre-commit-gate.sh` | PreToolUse | Bash | Block `save.sh`/`git commit`/`git push` until session has a fresh codex-review marker AND (hard-gate mode) acked intent file |
| `track-edit.sh` | PostToolUse | Edit/Write | Append edited file path to `~/.claude/state/dirty-<session>.log`; invalidate reviewed markers |
| `post-typecheck.sh` | PostToolUse | Edit/Write | Run `npx tsc --noEmit`/`cargo check`/`go vet ./...` after edits; surface errors as tool result |
| `session-start.sh` | SessionStart | — | Load last handoff into systemPrompt; GC stale state files |
| `remind-cross-review.sh` | UserPromptSubmit | — | Inject additionalContext reminding Claude to run codex-review before concluding |
| `contract-inject.sh` | UserPromptSubmit | — | On `/goal`·`/loop` activation, inject the per-work-unit autonomous-loop contract as additionalContext so the user need not retype it (non-blocking). Opt-out: `contract-inject-disabled` |
| `verification-gate.sh` | Stop | — | Block stop once/session when code changed but no test/e2e/run/deploy command was actually executed this session (scans executed Bash commands, not output text; excludes build/typecheck). Single-shot, so a genuinely-N/A change is handled by stating the reason once. Sibling to auto-cross-review (did *you* run it? vs. did a reviewer see it?). Opt-out: `verify-gate-disabled` |
| `auto-cross-review.sh` | Stop | — | Block stop once/session, inject review mandate if dirty log ≥ N files and no reviewed marker |
| `auto-handoff.sh` | Stop | — | Capture git status + branch + recent log to `~/.claude/handoffs/latest.md` for next session |

### Installed skills (slash commands)

User-invocable skills live at `~/dotfiles/claude/.claude/skills/<name>/SKILL.md`:

- `/ask-codex` — one-shot design consultation with Codex
- `/codex-plan` — multi-round plan pressure-testing with Codex (pre-implementation)
- `/codex-delegate` — delegate a sub-task to Codex (write-capable, background by default)
- `/cross-review` — full cross-review loop with VERDICT gate (3 rounds max)
- `/debug` — 5-phase structured debugging (3-strike + scope lock)
- `/iterate` — one work-cycle gate (implement → unit test → e2e → build/lint/typecheck → cross-review → `~/save.sh`); pair with `/loop` to enforce the gate every cycle

(Other installed skills not in the codex set: `/debug`, `/catchup`, `/mentor`, `/tabd`, `/frontend-design`, `/dotfiles-drift`, `/probe-hooks`, `/find-skills`. See `~/dotfiles/claude/.claude/skills/`.)

> Removed 2026-06-01: `/ship`, `/review`, `/verify`, `/handoff` — each was fully subsumed by automation. `/ship` → `~/save.sh` + `pre-commit-gate` (review) + autonomous-loop contract. `/review` (self-review) → `/cross-review` + the suppression rules folded into the Codex principles below. `/verify` → `/iterate` Step 3 e2e (tabd browser). `/handoff` → `auto-handoff.sh` Stop hook.

### Autonomous loop contract (`/goal`, `/loop`)

`/goal <text>` and `/loop` drive the session autonomously — a native session-scoped Stop hook re-feeds the goal until it is done. When you are driving any such loop, treat the per-work-unit gate below as **standing policy**. The user should NOT have to restate it in the goal text every time (they have been retyping it into nearly every `/goal` — that is the failure this contract fixes):

> **plan (if non-trivial) → codex review of plan → implement → unit test → e2e test (if applicable) → codex cross-review → `~/save.sh`**

1. One work-unit = one coherent change. Run the full gate **per unit**, not once at the very end.
2. Skip a step only with a stated reason ("e2e skipped — library-internal change, unit tests suffice"). Never skip silently.
3. The final commit always goes through `~/save.sh` (never raw `git commit`/`git push`).
4. This gate is exactly what `/iterate` encodes. Prefer **`/loop /iterate <task>`** when you want it mechanically enforced each cycle rather than relying on memory inside a free-form `/goal`.
5. Only pause for the user at planning checkpoints; otherwise run to completion.
6. Long codex review/plan steps in the loop follow the async-codex rule above — background + auto-wake, never Monitor polling.

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
2. **Valid feedback only — Fix-First pattern**. Mechanical fixes get applied immediately; judgment calls go to the user as questions. Suppress this class of finding (do not report): style/formatting (prettier/eslint handles it), things CI already catches (lint, typecheck), subjective naming preference, "future improvement" suggestions, TODO/FIXME comments, missing test coverage (separate task), import ordering.
3. **When you and codex disagree, surface both opinions to the user**. Do not silently pick one side. The disagreement itself is valuable signal.
4. **Read-only by default; write-capable only via `/codex-delegate`**. `/ask-codex`, `/codex-plan`, and `/cross-review` all run codex in `read-only` sandbox so it can investigate but not edit. `/codex-delegate` is the one path that grants `workspace-write`, and the user must opt in to it explicitly. Code that codex writes via delegate should be reviewed by Claude (and ideally by `/cross-review`) before commit — same as any third-party patch.
5. **Limit the loop**. `/cross-review` caps at 3 rounds. `/codex-plan` should also stop at ~3 rounds — beyond that the plan itself probably needs a rewrite, not more critique. If the same CRITICAL finding appears twice in a row, stop and ask the user — either codex is wrong or Claude cannot fix it cleanly.
6. **Language split — codex always English, user reply always matches user's language**. Prompts and briefs sent to codex (via any wrapper or direct `codex exec`) are always in English; codex's `~/.codex/AGENTS.md` is English and the wrapper templates are English, so this stays consistent and is more token-efficient for technical content. Replies back to the user always match the user's most recent message language, even right after a long English exchange with codex. When quoting codex output to the user, keep technical identifiers (paths, function names, error strings) verbatim but translate the surrounding narrative — do not pass codex's English prose through unchanged when the user is speaking another language.

### Integration with existing workflows

- **`/iterate`** — the one-cycle gate (implement → unit test → e2e → build/lint/typecheck → `/cross-review` → `~/save.sh`). This is where commit-time cross-review lives now that `/ship` is gone; commit always goes through `~/save.sh`, never raw git. See the autonomous-loop contract above.
- **`/codex-plan` before non-trivial implementation** — pair it with the existing `ExitPlanMode` checkpoint. After Claude writes a plan and before going wide on edits, run `/codex-plan --plan-file <path>` to pressure-test it. Cheaper than discovering plan flaws via `/cross-review` after the code is written.
- **`/codex-delegate` for clean-cut sub-tasks** — when a piece of work is well-scoped (clear input, clear acceptance) and would burn Claude's context, delegate it. Always verify the diff afterwards; never trust codex's "I ran the tests" claim without checking.
- **`@code-reviewer`** — Claude-based worktree reviewer (existing). Use together with `@codex-reviewer` for two independent perspectives on the same diff when the stakes are high (CodeX-Verify research shows 2-3 independent agents with different concerns beat single-agent review by ~40 percentage points).
- **`/debug`** — 5-phase structured debugging. Invoke when `/ask-codex` alone is not enough and you want a scoped debugging session (3-strike rule + scope lock prevents flailing).
- **Session handoff** — handled automatically by the `auto-handoff.sh` Stop hook (captures branch, recent commits, working-tree state to `~/.claude/handoffs/latest.md`). For a richer narrative handoff between major phases, just ask Claude to write one to that path.
- **Frontend visual check** — fold into `/iterate` Step 3 e2e: drive the dev server with tabd, screenshot the changed UI, and inspect layout/console errors before declaring done.

---

## ⚡ Emergency Quick Reference

**Can't decide?** → Read `020-decision-framework.md`

**Need code pattern?** → Read `100-typescript-patterns.md` or `110-rust-patterns.md`

**Check if something is wrong?** → Read `910-anti-patterns.md`

**Starting new project?** → Read `920-project-setup.md`

**Need to understand "why"?** → Read `010-personality-traits.md`

---

**Remember:** This is a living document. Patterns evolve. When in doubt, refer to the decision framework and core principles.

