#!/usr/bin/env bash
# PreToolUse Bash hook — hard-block raw `git commit` issued directly through
# the Bash tool. All commits MUST go through ~/save.sh, which wraps commit+push
# atomically with the project's guards (and runs git internally, so its own
# commit is never seen as a Bash tool call here). Every other git subcommand —
# including `git push` (tags, branches, retrying a failed save.sh push) — is
# allowed; only commit creation is the policy boundary.
#
# This is an UNCONDITIONAL deny — unlike pre-commit-gate.sh (which allows the
# commit once a review marker + intent exist), this gate never lets a raw git
# commit through. Rationale: user policy is "always commit via ~/save.sh"
# (see ~/.claude memory: feedback_save_sh_for_commit).
#
# Matches: `git commit` and `-C <path>` / flag variants thereof,
# even inside composed commands (`cd x && git commit ...`). Allows anything
# that routes through save.sh.
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

# Global / one-time opt-out marker.
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }

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
if printf '%s' "$SCAN" | grep -qE "$git_re"; then
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
    jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
    exit 0
fi

echo '{}'
exit 0
