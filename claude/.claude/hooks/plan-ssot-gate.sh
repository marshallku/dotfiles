#!/usr/bin/env bash
# PreToolUse ExitPlanMode hook — blocks presenting a plan until this session
# has consulted the ~/docs SSoT at least once (a `dn search`/`tag`/`related`
# query, recorded as ssot-checked-<session> by ssot-check-mark.sh).
#
# Rationale: free-form planning otherwise skips ~/docs entirely — only the
# /codex-plan skill wired it in. Gating on ExitPlanMode catches every plan
# the model presents, keyword-free, the same way pre-commit-gate.sh catches
# every commit. The marker is per-session: once you've searched, the relevant
# SSoT is in context for the rest of the session, so later plans pass freely.
#
# Allows when:
#   - ~/.claude/state/ssot-gate-disabled exists (session-wide opt-out)
#   - the `dn` SSoT tool is not installed / ~/docs is absent (no SSoT here)
#   - ssot-checked-<session> marker exists (already consulted this session)

set -euo pipefail

INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')

STATE_DIR="$HOME/.claude/state"
DISABLED="$STATE_DIR/ssot-gate-disabled"
MARKER="$STATE_DIR/ssot-checked-${SESSION}"
LOG_FILE="$HOME/.claude/hooks-debug.log"

log() {
    echo "[$(date +%H:%M:%S)] plan-ssot-gate: $*" >> "$LOG_FILE"
}

# Session-wide opt-out
[ -f "$DISABLED" ] && { log "allow: globally disabled"; echo '{}'; exit 0; }

# No SSoT on this machine → nothing to consult, don't block
if [ ! -x "$HOME/docs/scripts/dn" ] || [ ! -d "$HOME/docs" ]; then
    log "allow: dn/~/docs not present"
    echo '{}'
    exit 0
fi

# Already consulted SSoT this session
[ -f "$MARKER" ] && { log "allow: ssot-checked marker present"; echo '{}'; exit 0; }

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

jq -n --arg msg "$REASON" '{permissionDecision: "deny", message: $msg}'
