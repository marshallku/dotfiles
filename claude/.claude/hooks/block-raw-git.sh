#!/usr/bin/env bash
# @hook-event: PreToolUse
# PreToolUse Bash hook — unconditionally deny a raw `git commit` issued through the Bash tool,
# including `-C <path>`/flag variants and composed commands. Commits go through ~/save.sh, which
# runs git internally, so its own commit never reaches this hook. Every other git subcommand,
# including `git push`, is allowed. Unlike pre-commit-gate.sh, no review marker lets it through.
#
# Opt-out (only if the user explicitly asks):
#   one-time:  touch ~/.claude/state/raw-git-block-disabled  (commit, then rm)

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$HOME/.claude/state/raw-git-block-disabled"

log() {
    # Delegates to _lib.sh so every hook shares one date-stamped format.
    hook_log block-raw-git "$@"
}

[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# Shared parser first (_commit_targets.py, also pre-commit-gate's): it knows whether a raw
# `git commit` actually runs, so `grep "git commit" x` is not blocked. Anything it cannot parse,
# or a failing helper, falls through to the regex below.
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
# Skip python when the command cannot commit by the helper's own first test (no save.sh, no
# git … commit): the regex below could not match either.
case "$CMD" in
    *save.sh*|*git*commit*)
        KINDS=$(printf '%s' "$CMD" | python3 "$(dirname "$0")/_commit_targets.py" --kinds "${CWD:-$PWD}" 2>/dev/null) \
            || KINDS="error" ;;
    *) KINDS="none" ;;
esac
if [ "$KINDS" = "none" ] || { [ -n "$KINDS" ] && ! printf '%s\n' "$KINDS" | grep -qvE '^save '; }; then
    log "allow: parser found no raw git commit"
    echo '{}'
    exit 0
fi

# This gate is a HABIT GUARD: it reliably stops the routine `git commit` that
# should have gone through ~/save.sh, plus the common composed and
# shell-runner forms. It is NOT an adversarial sandbox — a caller with shell
# access can always evade a string matcher (write a script, base64-pipe-sh, or
# just `touch` the opt-out marker documented in the deny message). We optimise
# for catching every *habitual* form without false-positiving real work.

# What to scan depends on the leading program word:
#   - save.sh (optionally via a bash/sh/zsh wrapper or path prefix): its quoted
#     commit message is DATA and may legitimately say "git commit"/"git push"
#     (e.g. committing this very hook). Strip quoted substrings so the message
#     can't self-trigger — what survives is any chained command outside the
#     quotes (`~/save.sh "msg" && git commit …` still blocks).
#   - anything else (`git …`, `bash -c "git commit"`, `eval …`): scan as-is, so
#     git invocations embedded in a shell-runner's quoted code are still caught.
SAVE_RE='^[[:space:]]*((bash|sh|zsh)[[:space:]]+)?([^[:space:]]*/)?save\.sh([[:space:]]|$)'
if printf '%s' "$CMD" | grep -qE "$SAVE_RE"; then
    SCAN=$(printf '%s' "$CMD" | sed -E 's/"[^"]*"//g; s/'\''[^'\'']*'\''//g')
else
    SCAN=$CMD
fi

# Detect a raw `git commit` invocation anywhere in SCAN. `git` must
# appear as a word (`\bgit\b`, so `/usr/bin/git` and `cd x && git …` both count,
# but `legit`/`digit` do not), followed by any run of option tokens — a flag
# `-x` / `--opt=val` plus its optional argument, where the argument may be a
# double/single-quoted string (so `git -C "/my repo" commit` is caught) or a
# bareword (`-C /repo`) — then `commit` as a standalone subcommand. The
# trailing class (whitespace, shell separator `;&|`, a closing quote, or end —
# deliberately not a bare `\b`) means the subcommand must end at one of those,
# so plumbing like `git commit-tree` is NOT matched while `sh -c 'git commit'`
# (commit closed by a quote) still is, and non-option words (`log`, `show`) and
# filenames (`-- commit.txt`) end the option run before the subcommand slot so
# `git log commit` and `git diff -- commit.txt` stay allowed.
git_arg='("[^"]*"|'\''[^'\'']*'\''|[^-][^[:space:]]*)'
git_re="\\bgit\\b([[:space:]]+-[^[:space:]]+([[:space:]]+${git_arg})?)*[[:space:]]+commit([[:space:]]|[;&|\"']|\$)"
PARSED_GIT=0
printf '%s\n' "$KINDS" | grep -q '^git ' && PARSED_GIT=1
if [ "$PARSED_GIT" = 1 ] || printf '%s' "$SCAN" | grep -qE "$git_re"; then
    log "BLOCK: raw git commit -> $CMD"
    REASON='[block-raw-git] Raw `git commit` is blocked by user policy.

All commits MUST go through `~/save.sh`, which commits the STAGED
index + pushes atomically with the project guards (and passes the
commit-message / review gates). It does NOT stage for you — `git add` is
allowed and is your job. Other git commands (push, tag, …) are allowed.

Do this instead:
  git add <paths>            # stage exactly what belongs in this commit
  ~/save.sh "<commit message>"

If you genuinely need a raw git commit (rare — ask the user first):
  touch ~/.claude/state/raw-git-block-disabled   # then run it, then rm the marker'
    # Claude Code ignores a top-level {permissionDecision}; only hookSpecificOutput decides.
    jq -n --arg msg "$REASON" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$msg}}'
    exit 0
fi

echo '{}'
exit 0
