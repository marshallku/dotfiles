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

## 🤝 Codex Cross-Check & Harness Rules

OpenAI Codex CLI is a peer reviewer from a different model family. These are the rules;
the why, the hook registry, the ledgers and the history of what broke are in
`~/dotfiles/claude/.claude/hooks/README.md` — read it before changing the harness.

### Tools

| Stage | Tool | Notes |
|---|---|---|
| Quick design question | `/ask-codex "q"` | read-only, one turn. Not for things you are 80%+ sure of. |
| Plan pressure test | `/codex-plan` | read-only, multi-round; stop at ~3 rounds. Use for risky or wide plans, not every plan. |
| Delegate a sub-task | `/codex-delegate` | background, **writes files**; only when the user opts in. Review its diff yourself. |
| Review before commit | `/cross-review` | read-only VERDICT loop over the staged index. |

All of them run through `~/.claude/scripts/codex-exec.sh`: stdout is the final message (parse
`VERDICT:` there), stderr is progress; exit `0` ok · `1` REVISE · `2` error · `3` resume
unavailable · `124` timeout.

### Waiting on codex

Run a gating review/plan **in the foreground with Bash `timeout: 600000`** and block on it.
Never background it, and never poll a local codex job with Monitor/ScheduleWakeup.

### Work units, review and commits

- A work unit is the staged index. `git add <exact paths>`, then `/cross-review`; `save.sh`
  commits exactly that index. Approval is bound to the (HEAD tree, index tree) pair, not to a
  session; more `git add` or a moved HEAD needs a new review.
- Review is required for any implementation, configuration, dependency or agent-instruction
  change (`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/*`, `.codex/*` always). Docs-only
  changes may skip. Auth, permissions, secrets and shell/path handling are never skipped by size.
- On REVISE: verify each finding against the code and a reproduction, fix minimally with a
  regression test, re-stage, and resume with `--resume --response-file`. Keep going while
  findings are valid and in scope; stop and show both sides on a repeated finding or when only
  invalid / out-of-scope findings remain.
- Commit only through `~/save.sh` (subject: `Verb …` from its list, or `type: …`). Never a raw
  git commit. No co-author or "Generated with" lines anywhere — commit messages, PR text,
  and GitHub merges (`gh pr merge` needs an explicit `--body`).
- Edit files with Edit/Write. Bash heredoc/sed edits reach the type checker and review
  reminders, but `protect-secrets` and `freeze` only see Edit/Write.

### Writing hooks

- PreToolUse decisions go through `hook_permission deny <reason>` (`_lib.sh`). A
  top-level `{permissionDecision}` is ignored and the command runs.
- Never `ask`: it waits for a human and stalls long autonomous loops. Deny what is
  irreversible and has an alternative (say the alternative in the reason); allow and record
  (`hook_event … decision=flagged`) what is merely risky.
- A gate whose helper is missing or fails must deny, never allow.
- Log every exit path with `hook_log` / `hook_event`; never hand-roll `log()`.
- Sensors (`post-typecheck.sh`) do not use `set -e`.
- Hooks and wrappers must run on Linux and macOS (bash ≥ 4 on PATH, BSD/GNU `stat`, `date`,
  `sed`, `awk`; use the `portable_*` helpers). Add a test under `scripts/__tests__`.
- `bash ~/.claude/scripts/harness-report.sh` is the health scorecard; its `--tripwire` mode runs
  at SessionStart.

### Autonomous loops (`/goal`, `/loop`)

Per work unit: plan (if non-trivial) → codex plan review (if risky) → implement → unit test →
e2e (if applicable) → `/cross-review` → `~/save.sh`. Skip a step only with a stated reason.
Pause for the user only at planning checkpoints. `/iterate` encodes the same gate.

### Working with codex output

1. It is a second opinion, not ground truth. Verify before accepting.
2. Apply mechanical fixes; bring judgment calls to the user. Ignore style, lint/typecheck,
   naming, "future improvement", TODO and coverage-only findings.
3. When you and codex disagree, show the user both positions.
4. Codex is read-only except through `/codex-delegate`.
5. Prompts to codex are English; replies to the user are in the user's language, including
   right after a hook or codex exchange in English.

### Reporting

Mark each claim of a result as reproduced (command + exit code), read in code (`file:line`),
or inferred. Say what was not verified. If a real environment cannot be reached, stop and say
so — do not report a mock run as verification.


---

## ⚡ Emergency Quick Reference

**Can't decide?** → Read `020-decision-framework.md`

**Need code pattern?** → Read `100-typescript-patterns.md` or `110-rust-patterns.md`

**Check if something is wrong?** → Read `910-anti-patterns.md`

**Starting new project?** → Read `920-project-setup.md`

**Need to understand "why"?** → Read `010-personality-traits.md`

---

**Remember:** This is a living document. Patterns evolve. When in doubt, refer to the decision framework and core principles.

