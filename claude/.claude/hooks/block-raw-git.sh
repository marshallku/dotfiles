#!/usr/bin/env bash
# PreToolUse Bash hook — hard-block raw `git commit` / `git push` issued
# directly through the Bash tool. All commits MUST go through ~/save.sh, which
# wraps commit+push atomically with the project's guards (and runs git internally,
# so its own commit is never seen as a Bash tool call here).
#
# This is an UNCONDITIONAL deny — unlike pre-commit-gate.sh (which allows the
# commit once a review marker + intent exist), this gate never lets raw git
# commit/push through. Rationale: user policy is "always commit via ~/save.sh"
# (see ~/.claude memory: feedback_save_sh_for_commit).
#
# Matches: `git commit`, `git push`, and `-C <path>` / flag variants thereof,
# even inside composed commands (`cd x && git commit ...`). Allows anything
# that routes through save.sh.
#
# Opt-out (only if the user explicitly asks):
#   one-time:  touch ~/.claude/state/raw-git-block-disabled  (commit, then rm)

set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

[ -z "$CMD" ] && { echo '{}'; exit 0; }

LOG_FILE="$HOME/.claude/hooks-debug.log"
DISABLED="$HOME/.claude/state/raw-git-block-disabled"

log() {
    echo "[$(date +%H:%M:%S)] block-raw-git: $*" >> "$LOG_FILE"
}

# Global / one-time opt-out marker.
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

# This gate is a HABIT GUARD: it reliably stops the routine `git commit` / `git
# push` that should have gone through ~/save.sh, plus the common composed and
# shell-runner forms. It is NOT an adversarial sandbox — a caller with shell
# access can always evade a string matcher (write a script, base64-pipe-sh, or
# just `touch` the opt-out marker documented in the deny message). We optimise
# for catching every *habitual* form without false-positiving real work.

# What to scan depends on the leading program word:
#   - save.sh (optionally via a bash/sh/zsh wrapper or path prefix): its quoted
#     commit message is DATA and may legitimately say "git commit"/"git push"
#     (e.g. committing this very hook). Strip quoted substrings so the message
#     can't self-trigger — what survives is any chained command outside the
#     quotes (`~/save.sh "msg" && git push` still blocks).
#   - anything else (`git …`, `bash -c "git commit"`, `eval …`): scan as-is, so
#     git invocations embedded in a shell-runner's quoted code are still caught.
SAVE_RE='^[[:space:]]*((bash|sh|zsh)[[:space:]]+)?([^[:space:]]*/)?save\.sh([[:space:]]|$)'
if printf '%s' "$CMD" | grep -qE "$SAVE_RE"; then
    SCAN=$(printf '%s' "$CMD" | sed -E 's/"[^"]*"//g; s/'\''[^'\'']*'\''//g')
else
    SCAN=$CMD
fi

# Detect a raw `git commit` / `git push` invocation anywhere in SCAN. `git` must
# appear as a word (`\bgit\b`, so `/usr/bin/git` and `cd x && git …` both count,
# but `legit`/`digit` do not), followed by any run of option tokens — a flag
# `-x` / `--opt=val` plus its optional argument, where the argument may be a
# double/single-quoted string (so `git -C "/my repo" commit` is caught) or a
# bareword (`-C /repo`) — then `commit`/`push` as a standalone subcommand. The
# trailing class (whitespace, shell separator `;&|`, a closing quote, or end —
# deliberately not a bare `\b`) means the subcommand must end at one of those,
# so plumbing like `git commit-tree` is NOT matched while `sh -c 'git push'`
# (push closed by a quote) still is, and non-option words (`stash`, `log`) and
# filenames (`-- commit.txt`) end the option run before the subcommand slot so
# `git stash push` and `git diff -- commit.txt` stay allowed.
git_arg='("[^"]*"|'\''[^'\'']*'\''|[^-][^[:space:]]*)'
git_re="\\bgit\\b([[:space:]]+-[^[:space:]]+([[:space:]]+${git_arg})?)*[[:space:]]+(commit|push)([[:space:]]|[;&|\"']|\$)"
if printf '%s' "$SCAN" | grep -qE "$git_re"; then
    log "BLOCK: raw git commit/push -> $CMD"
    REASON='[block-raw-git] Raw `git commit` / `git push` is blocked by user policy.

All commits and pushes MUST go through `~/save.sh`, which commits + pushes
atomically with the project guards (and passes the commit-message / review gates).

Do this instead:
  ~/save.sh "<commit message>"

If you genuinely need a raw git commit/push (rare — ask the user first):
  touch ~/.claude/state/raw-git-block-disabled   # then run it, then rm the marker'
    jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
    exit 0
fi

echo '{}'
exit 0
