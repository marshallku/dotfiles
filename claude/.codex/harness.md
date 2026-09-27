# Shared harness in Codex

The source of truth stays in `~/dotfiles/claude/.claude/`. Skills under
`~/.agents/skills/` link to those sources; scripts, profile, SSoT (`~/docs`),
review snapshots, open loops, and handoffs use the same existing paths.
Do not copy skills to make Codex-specific versions.

At session start, read `~/.claude/profile/900-quick-reference.md` and
`~/.claude/profile/910-anti-patterns.md`. Read the remaining profile files
on demand. The current AGENTS.md review suppression rules and `~/save.sh`
commit policy override old profile examples (including AI co-author trailers).
Read a repository's CLAUDE.md when present for its existing local conventions,
in addition to its AGENTS.md. Do not import Claude's global orchestration index
as Codex's system instructions.

## Workflow

Use the shared `iterate` skill for its implementation → tests → e2e → checks →
cross-review → save.sh cycle. Before non-trivial planning, search `~/docs`
using `dn search` / `dn related`; cite relevant prior context. Use `codex-plan`
for plan pressure testing when appropriate. Explain any skipped verification.
Complete a full `cross-review` before declaring an implementation unit done.
Stage only the intended paths. Commits/pushes, when requested by the user or
the invoked workflow, go through `~/save.sh`; never raw git commit/push.

Review commands use the exact session ID injected by SessionStart, or
`CODEX_THREAD_ID` if available. Never infer it from another session's state.
If hooks were not active before edits, supply the known starting commit with
`--base`; don't invent a baseline. Review approval remains bound to session,
repository and full content. Keep the three-round limit and evidence-first triage.

The shared reviewer invokes **Codex**, including when Codex is implementing.
This provides a separate read-only review session, not a different model family.
Do not describe it as a Claude cross-check. Read-only wrapper children suppress
their own workflow hooks to avoid recursive review and overwriting parent handoffs;
the shared safety checks remain enabled. A reviewer/consultant must answer the
requested review or question directly, without invoking another review/plan cycle.

## Skill/tool compatibility

- `/name` in a shared skill means invoke `$name` (or read its SKILL.md) in Codex.
- `Bash`, `Read`, `Edit`, `Write`, `Glob`, `Grep` mean the equivalent available
  shell, file, patch and search tools. Claude `allowed-tools`, `effort`, `model`,
  `context`, `isolation` metadata do not configure Codex permissions or models.
- For long shell commands retain the returned execution session and wait on it
  to completion. Claude's `timeout: 600000` / `run_in_background` are not Codex
  tool arguments. Keep gating reviews attached to the active turn.
- `Agent(Explore)` or `@code-reviewer` refers to a procedure. Read the matching
  `~/.claude/agents/*.md` and use an available subagent only when the invoked skill
  or user requests delegation. Enforce read-only scope explicitly; Claude agent
  YAML does not create Codex agents or isolated worktrees automatically.
- `/loop` is Claude-specific. Do not claim a loop or scheduling mechanism exists
  unless the current Codex tools actually provide it. Create a Codex goal only
  when explicitly requested. The work-unit checks still apply to each cycle.
- External executables (`dn`, `tabd`, `gh`, `crew`, deployment CLIs) keep their
  existing paths and credentials. Check availability when the skill needs them.
  Claude plugins/LSPs and Figma auth are not transferred by skill symlinks.

## Hook adaptations and limits

`hooks.json` calls one adapter, which reads the live shared `settings.json` and
runs supported hooks in order. Disabled Claude hooks stay disabled. Policies
are implemented only in the original scripts, not duplicated in the adapter.

- SessionStart, prompt reminders, compaction preservation, review gates, handoff,
  edit tracking, type checks, secret protection and freeze reuse the original hooks.
- Codex patches expand into per-file events, including deletes and both move paths.
- Bash commands feed a small per-session command ledger for the shared verification
  heuristic; Codex's unstable transcript format is not parsed.
- `update_plan` uses the existing SSoT gate; Codex has no Claude ExitPlanMode event.
  Plans written directly in conversation rely on the instruction above.
- Legacy `deny` output is normalized. Codex does not support hook `ask`, so those
  operations are denied with an explanation for the user to run them manually.
- These are tool guardrails, not an OS sandbox: shell/MCP file writes do not become
  patch events. Full-tree review still detects their repository content changes.
- Claude `Notification`, statusline, copad status hooks and the harness tripwire
  are not ported. Codex keeps its existing `notify-codex.sh` configuration.
- Handoffs currently share `~/.claude/handoffs/latest.md`, including its existing
  last-writer-wins behavior across concurrent sessions/repos.

Install with `bash ~/dotfiles/install-codex.sh`, restart Codex, then inspect and
trust the six event hooks in `/hooks`. Until trust is granted, these automatic
gates do not run. Trust is never synthesized or bypassed by the installer.
New shared skills are picked up by rerunning the installer; edits to linked
skills/scripts are immediately shared. Existing independent skill directories
are preserved (including this machine's Codex `tabd`).

Official contracts: https://learn.chatgpt.com/docs/hooks and
https://learn.chatgpt.com/docs/build-skills.
