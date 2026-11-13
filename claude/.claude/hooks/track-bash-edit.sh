#!/usr/bin/env bash
# Bash edits get the same sensors as Edit/Write.
#
#   PreToolUse  Bash: track-bash-edit.sh pre   — stamp the time the command starts
#   PostToolUse Bash: track-bash-edit.sh post  — repository files changed since the stamp
#                     go to dirty-<session>.log (review reminders) and post-typecheck.sh
#
# Why: agents often edit through `python3 - <<'PY' … write_text(…)`, `sed -i` or `cat >`.
# On the work machine that was 6,188 edits in four months (27% of Bash input); on the
# mac-mini, Bash file writes outnumbered Edit/Write calls. None of them reached
# track-edit.sh or post-typecheck.sh, which only match Edit|Write, so a type error made
# that way was never reported and the review reminder never fired.
#
# Detection is by result, not by parsing the command: after the command, every tracked
# modified or untracked (non-ignored) file in the cwd's repository whose mtime is at or
# after the stamp counts. Git-only commands (pull, checkout, rebase …) are skipped — they
# move other people's code, not this session's edits. Subagent and scratchpad edits are
# skipped exactly like track-edit.sh.
#
# Every exit path logs except "not a repository" and "nothing changed", which happen on
# most Bash calls; the daily `heartbeat` event covers those.
# Opt-out: touch ~/.claude/state/track-bash-edit-disabled

set -uo pipefail

. "$(dirname "$0")/_lib.sh" 2>/dev/null || true
command -v hook_event >/dev/null 2>&1 || hook_event() { :; }

MODE="${1:-post}"
STATE_DIR="$HOME/.claude/state"
INPUT=$(cat 2>/dev/null || echo '{}')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
case "$SESSION" in ''|*[!A-Za-z0-9_-]*) SESSION=default ;; esac
MARK="$STATE_DIR/bash-mark-$SESSION"
MAX_CANDIDATES="${TRACK_BASH_EDIT_MAX_FILES:-2000}"

done_ok() { echo '{}'; exit 0; }

[ -f "$STATE_DIR/track-bash-edit-disabled" ] && done_ok

if [ "$MODE" = pre ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null
    date +%s > "$MARK" 2>/dev/null
    done_ok
fi

STAMP=$(cat "$MARK" 2>/dev/null | tr -dc '0-9')
[ -n "$STAMP" ] || done_ok

BEAT="$STATE_DIR/track-bash-edit-heartbeat-$(date '+%Y-%m-%d')"
if [ ! -e "$BEAT" ]; then
    rm -f "$STATE_DIR"/track-bash-edit-heartbeat-* 2>/dev/null
    : > "$BEAT" 2>/dev/null && hook_event track-bash-edit heartbeat
fi

AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
if [ -n "$AGENT_ID" ]; then
    hook_event track-bash-edit skip reason=subagent
    done_ok
fi

CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
# A git command that moves files (pull, checkout, rebase …) changes code this session did not
# write. Missing an edit chained after it is the cheaper mistake than attributing a pull.
if printf '%s' "$CMD" | grep -qE '(^|[^[:alnum:]_-])git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+(pull|checkout|switch|restore|reset|rebase|merge|cherry-pick|stash|am|revert|clone|worktree|submodule)([^[:alnum:]_-]|$)'; then
    hook_event track-bash-edit skip reason=git_moves_files
    done_ok
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -d "$CWD" ] || done_ok
REPO=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || done_ok

# Candidate paths: tracked-and-modified plus untracked-not-ignored, capped for huge trees.
# NUL-delimited: by default git C-quotes non-ASCII or quoted names, which stat cannot find.
CANDIDATES=()
while IFS= read -r -d '' path; do
    CANDIDATES+=("$path")
    [ ${#CANDIDATES[@]} -ge "$MAX_CANDIDATES" ] && break
done < <(git -C "$REPO" ls-files -z -m -o --exclude-standard 2>/dev/null)
[ ${#CANDIDATES[@]} -gt 0 ] || done_ok

# One stat call for all candidates: "<mtime> <path>". Pick the flavour first; a stat that
# fails on one vanished file must not be read as "this is BSD stat".
if stat -c '%Y' / >/dev/null 2>&1; then STAT_FMT=(-c '%Y %n'); else STAT_FMT=(-f '%m %N'); fi
STATS=$(cd "$REPO" && printf '%s\0' "${CANDIDATES[@]}" | xargs -0 stat "${STAT_FMT[@]}" 2>/dev/null)

CHANGED=()
seen=""
while IFS= read -r line; do
    mtime="${line%% *}"
    rel="${line#* }"
    case "$seen" in *"|$rel|"*) continue ;; esac  # -m and -o can both list a path
    seen="$seen|$rel|"
    case "$mtime" in ''|*[!0-9]*) continue ;; esac
    [ "$mtime" -ge "$STAMP" ] || continue
    abs="$REPO/$rel"
    case "$abs" in */claude-[0-9]*/*/scratchpad/*) continue ;; esac
    [ -f "$abs" ] || continue
    CHANGED+=("$abs")
done <<< "$STATS"

[ ${#CHANGED[@]} -gt 0 ] || done_ok

printf '%s\n' "${CHANGED[@]}" >> "$STATE_DIR/dirty-${SESSION}.log"
hook_log track-bash-edit "${#CHANGED[@]} file(s) changed by Bash in $REPO"
hook_event track-bash-edit tracked files="${#CHANGED[@]}" repo="$REPO"

# Type-check through the same sensor Edit/Write uses: ONE run, for the first checkable file.
# It checks that file's whole project, and its 25s budget is what fits this hook's 30s
# timeout — a second run could be killed mid-way and lose the first run's diagnostics.
CONTEXT=""
for f in "${CHANGED[@]}"; do
    case "${f##*.}" in ts|tsx|rs|go) ;; *) continue ;; esac
    OUT=$(jq -nc --arg f "$f" --arg s "$SESSION" '{session_id:$s, tool_input:{file_path:$f}}' \
        | bash "$(dirname "$0")/post-typecheck.sh" 2>/dev/null)
    CONTEXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    break
done

if [ -n "$CONTEXT" ]; then
    jq -nc --arg ctx "[track-bash-edit] A Bash command changed files; type check:
$CONTEXT" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}'
    exit 0
fi
done_ok
