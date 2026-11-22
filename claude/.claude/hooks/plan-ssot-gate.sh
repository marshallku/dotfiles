#!/usr/bin/env bash
# @hook-event: PreToolUse
# PreToolUse ExitPlanMode hook — blocks presenting a plan until this session
# has consulted the ~/docs SSoT at least once (a `dn search`/`tag`/`related`
# Bash command in this session's transcript; Codex passes its command ledger).
#
# Free-form planning otherwise skips ~/docs; gating on ExitPlanMode catches every plan
# keyword-free. Once consulted, the SSoT stays in context, so later plans in the session pass.
#
# Allows when:
#   - ~/.claude/state/ssot-gate-disabled exists (session-wide opt-out)
#   - the `dn` SSoT tool is not installed / ~/docs is absent (no SSoT here)
#   - the transcript holds a `dn search|tag|related` command (already consulted)
#   - ssot-checked-<session> marker exists (manual clear for this session)

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
DN_RE='(^|[^[:alnum:]_/])(dn|[^[:space:]]*/dn)[[:space:]]+(search|tag|related)([[:space:]]|$)'

STATE_DIR="$HOME/.claude/state"
DISABLED="$STATE_DIR/ssot-gate-disabled"
MARKER="$STATE_DIR/ssot-checked-${SESSION}"
LOG_FILE="$HOME/.claude/hooks-debug.log"

log() {
    hook_log plan-ssot-gate "$@"
}

[ -f "$DISABLED" ] && { log "allow: globally disabled"; echo '{}'; exit 0; }

if [ ! -x "$HOME/docs/scripts/dn" ] || [ ! -d "$HOME/docs" ]; then
    log "allow: dn/~/docs not present"
    echo '{}'
    exit 0
fi

# Already consulted SSoT this session
[ -f "$MARKER" ] && { log "allow: ssot-checked marker present"; echo '{}'; exit 0; }
if [ -f "$TRANSCRIPT" ] && jq -r '.. | objects | select(.type? == "tool_use" and .name? == "Bash")
        | .input.command? // empty' "$TRANSCRIPT" 2>/dev/null | grep -E "$DN_RE" >/dev/null; then
    # Not grep -q: an early exit breaks jq's pipe, and pipefail turns a found consult into a deny.
    log "allow: dn consult found in transcript"
    echo '{}'
    exit 0
fi

log "BLOCK: ExitPlanMode without an SSoT consult this session"

# shellcheck disable=SC2016
REASON='[plan-ssot-gate] Before presenting this plan, consult the ~/docs SSoT — 30s now can save an hour, and surfacing a prior decision sharpens the plan.

Pull the 2-3 core nouns of this plan and run, e.g.:

    dn search "<keyword1> <keyword2>"        # weighted full-text across all layers
    dn related <repo-note>                    # adjacent material (e.g. dn related kagi)
    ls ~/docs/topics/repos/                   # similar projects to borrow from

Priority hits: sources/sessions/<repo-slug>/ (this repo'\''s recent work),
topics/repos/<repo>.md (accumulated repo knowledge), topics/repos/<other>.md
(same-domain projects — borrowing is wanted), topics/decisions/, sources/debug/.

If a hit is relevant, fold it into the plan (cite it in a "Prior context" line).
If nothing relevant turns up, that'\''s fine — the search itself clears this gate.
Then re-run ExitPlanMode to present the plan.

Bypass for this session: touch ~/.claude/state/ssot-gate-disabled'

hook_permission deny "$REASON"
