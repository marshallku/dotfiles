#!/usr/bin/env bash
# codex-plan.sh — Iterate on a plan with Codex as a pressure-tester.
# Round 1 starts a fresh thread; subsequent rounds resume the same thread
# so codex retains memory of the plan and prior critiques. Read-only.
#
# Usage:
#   codex-plan.sh "Plan: refactor X by Y so that Z. Risks I see: A, B."
#   codex-plan.sh --plan-file plan.md
#   codex-plan.sh --continue "what about backwards compat?"
#   codex-plan.sh --reset "Plan: ..."     # force fresh thread
#
# Default behavior is fresh (--reset). Pass --continue explicitly to
# resume the previous round.
#
# Caveat: --continue resumes the latest *companion task thread* in this
# workspace. All four wrappers in this directory (codex-ask.sh,
# codex-plan.sh, codex-review.sh, codex-delegate.sh) route through
# `companion task`, which means every one of them creates a resumable
# task job (jobClass: "task"). The companion's --resume-last picks the
# newest one regardless of which wrapper produced it, so calling any
# other wrapper between plan rounds will hijack --continue. The
# companion CLI does not expose per-thread-id resume, so we cannot
# isolate plan threads at this layer. Either avoid interleaving codex
# calls between plan rounds, or use --reset and paraphrase the prior
# round into the new prompt.
#
# Exit codes:
#   0 = round completed
#   2 = usage / missing input / companion error

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

COMPANION="$(dirname "$0")/codex-companion.sh"
if [[ ! -x "$COMPANION" ]]; then
    echo "[codex-plan] companion wrapper missing: $COMPANION" >&2
    exit 2
fi

MODE="reset"
PLAN_FILE=""
TIMEOUT="${CODEX_PLAN_TIMEOUT:-420}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --continue)
            MODE="continue"
            shift
            ;;
        --reset)
            MODE="reset"
            shift
            ;;
        --plan-file)
            PLAN_FILE="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

INPUT_TEXT="$*"
if [[ -n "$PLAN_FILE" ]]; then
    if [[ ! -f "$PLAN_FILE" ]]; then
        echo "[codex-plan] plan file not found: $PLAN_FILE" >&2
        exit 2
    fi
    INPUT_TEXT=$(cat "$PLAN_FILE")
fi

if [[ -z "$INPUT_TEXT" ]]; then
    echo "Usage: $0 [--continue|--reset] [--plan-file <path>] <plan or follow-up>" >&2
    exit 2
fi

MODEL_ARGS=()
if [[ -n "${CODEX_PLAN_MODEL:-}" ]]; then
    MODEL_ARGS=(--model "$CODEX_PLAN_MODEL")
fi

RESUME_FLAG="--fresh"
[[ "$MODE" == "continue" ]] && RESUME_FLAG="--resume-last"

# Frame codex as an adversarial planner — challenge, don't rubber-stamp.
# Read-only sandbox is enforced by the companion `task` (no --write flag).
# AGENTS.md "Code Review Principles" + "What NOT to do" already cover the
# attitude; we just point codex at the plan and the angles to check.
if [[ "$RESUME_FLAG" == "--fresh" ]]; then
    PROMPT=$(cat <<EOF
Pressure-test this plan before implementation per AGENTS.md. Find what would break it: hidden assumptions, missed edge cases / failure modes, simpler alternatives skipped, scope gaps vs the ask, concrete risks (data loss, race, rollback, perf, security). If genuinely sound, say so briefly and stop. Read the codebase as needed; do not edit files or propose to implement.

--- PLAN UNDER REVIEW ---
${INPUT_TEXT}
--- END PLAN ---
EOF
)
else
    # Continuation turn — keep it short, codex already has the thread context.
    PROMPT=$(cat <<EOF
Follow-up on the plan we are pressure-testing in this thread.

${INPUT_TEXT}

Stay in pressure-tester mode. Read files as needed. No file edits.
EOF
)
fi

portable_timeout "$TIMEOUT" "$COMPANION" task $RESUME_FLAG ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$PROMPT" </dev/null
