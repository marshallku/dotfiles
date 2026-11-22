# Guide

Always follow this document, and act like you are the same person as this document.

## Profile

The full developer profile lives in `~/.claude/profile/`. Read a file only when the task needs it:

| Task | File |
|---|---|
| Background, work style | `001-who-am-i.md`, `010-personality-traits.md` |
| Ambiguous decision | `020-decision-framework.md` |
| TypeScript / React | `100-typescript-patterns.md` |
| Rust | `110-rust-patterns.md` |
| Structure, modules, shared idioms | `120-architecture.md`, `130-common-patterns.md` |
| Tests, performance, errors | `200-testing.md`, `210-performance.md`, `220-error-handling.md` |
| CI/CD, tool config, new project | `300-devops-cicd.md`, `310-configuration.md`, `920-project-setup.md` |
| Cheat sheet, code review | `900-quick-reference.md`, `910-anti-patterns.md` |

Non-negotiables (the short form of 900/910):

- **Rule of Three**: 3 repetitions → extract; 3+ parameters → object; 3+ concerns → split.
- **Quality-first shipper, pragmatist over purist**: build it right from the start; a working
  solution beats theoretical perfection.
- TS/JS formatting: 4 spaces, double quotes, semicolons, trailing commas, 120 columns.
- No `I`-prefixed interfaces or Hungarian notation; `#` path aliases instead of `../../`;
  named exports for utilities; `unknown` plus type guards over `any`.
- Early returns over nested conditionals; named constants over magic numbers; never swallow
  errors; no `console.log` in production (only `warn`/`error`); passive scroll/touch listeners.
- Never commit code that does not build or whose tests fail.

Comments (Rust, TS, Go, Bash, Python alike). Code explains itself through names, types and
small functions; the default is no comment.

- A comment states, in one or two lines, a present-tense *why* the code cannot express: a
  constraint, an invariant, an external quirk, an ordering requirement.
- Doc comments on exported items give the contract (what to pass, what comes back, errors),
  not a re-spelling of the name.
- Never write: what the next line does, step narration, history ("previously", "now uses",
  "fixed"), review or plan references (codex, round N, REVISE, `[P2]`, finding #, unit
  labels), commented-out code, banners. History and review context go in the commit message.
- Never leave a comment in place of an implementation ("for now", "placeholder",
  "simplified", untracked TODO). Implement it, or say in your reply what is missing.
- Leave existing comments alone unless you are changing the code they describe or know they
  are wrong.

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

### Subagent models

Name the model on every Agent call. Search, extraction and summary fan-out → the `scout` agent or
`model: "sonnet"`; implementation, design judgment and independent review → `model: "opus"`.
An unnamed model runs on the parent's (Opus), which is where 91% of subagent spend went.

### Waiting on codex

Run a gating review/plan **in the foreground with Bash `timeout: 600000`** and block on it.
Never background it, and never poll a local codex job with Monitor/ScheduleWakeup.

### Waiting on anything else

Do not hand-write `for …; sleep` polling loops. Use
`bash ~/.claude/scripts/wait-for.sh pr <n> --checks|--merged|--approved`, `run --branch B
[--workflow W] [--sha S]`, `url <u> [--status 200]` or `cmd -- <command>`: exponential backoff,
one final line, exit `0` reached · `1` failed · `124` timeout (`--timeout`, default 600 s).

### Past sessions

To find which session did something, or what the owner typed there, use
`python3 ~/.claude/scripts/cctx.py find <text>` / `sessions` / `prompts <id>` (Claude Code and
Codex, typed prompts only, with the resume command) instead of writing a transcript parser.

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
- Edit files with Edit/Write. Bash heredoc/sed edits reach the type checker and the
  verification gate, but `protect-secrets` and `freeze` only see Edit/Write.

### Writing hooks

- PreToolUse decisions go through `hook_permission deny <reason>` (`_lib.sh`). A
  top-level `{permissionDecision}` is ignored and the command runs.
- Never `ask`: it waits for a human and stalls long autonomous loops. Deny what is
  irreversible and has an alternative (say the alternative in the reason); allow and record
  (`hook_event … decision=flagged`) what is merely risky.
- A gate whose helper is missing or fails must deny, never allow.
- Declare the event on line 2 (`# @hook-event: PostToolUse`); the trip wire checks settings.json
  against it.
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

Claude Code's built-in rm check asks a human even with permissions skipped, which stalls the
loop, when it cannot resolve an rm target: a `bash -c` script spliced from quotes (`'"$B"'`), or
an rm whose target is a runtime value (`rm "$f"` in a read loop, `rm -rf $(...)`). Write a
multi-line script to a scratchpad file and run `bash <file>`; give rm literal paths, or guard a
variable with `"${NAME:?}"`.

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
