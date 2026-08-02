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
# --continue resumes by explicit thread id (stored per repo under
# ~/.claude/state/codex-threads/plan-<repo_hash>), so interleaving other
# codex calls between rounds is safe — they cannot hijack the plan thread.
# The remaining invariant is one active plan thread per repo: a second
# concurrent plan in the same repo overwrites the key. Set
# CODEX_PLAN_THREAD_KEY to run isolated plans side by side.
#
# If the stored thread is gone (never started, or codex GC'd the rollout),
# --continue degrades to a fresh round with a warning rather than failing.
#
# Exit codes:
#   0 = round completed
#   2 = usage / missing input / codex error

set -euo pipefail

. "$(dirname "$0")/../hooks/_lib.sh"

RUNNER="$(dirname "$0")/codex-exec.sh"
if [[ ! -x "$RUNNER" ]]; then
    echo "[codex-plan] runner missing: $RUNNER" >&2
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

# Plan threads are keyed per repo so /ask-codex or /cross-review between
# rounds cannot steal the resume (the old --resume-last failure mode).
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
THREAD_KEY="${CODEX_PLAN_THREAD_KEY:-plan-$(repo_hash "$REPO_ROOT")}"

# Frame codex as an adversarial planner — challenge, don't rubber-stamp.
# Read-only sandbox is the runner's default (no --write flag).
# AGENTS.md "Code Review Principles" + "What NOT to do" already cover the
# attitude; we just point codex at the plan and the angles to check.
build_fresh_prompt() {
    cat <<EOF
Pressure-test this plan before implementation per AGENTS.md. Find what would break it: hidden assumptions, missed edge cases / failure modes, simpler alternatives skipped, scope gaps vs the ask, concrete risks (data loss, race, rollback, perf, security). If genuinely sound, say so briefly and stop. Read the codebase as needed; do not edit files or propose to implement.

--- PLAN UNDER REVIEW ---
${INPUT_TEXT}
--- END PLAN ---
EOF
}

# Continuation turn — keep it short, codex already has the thread context.
build_continue_prompt() {
    cat <<EOF
Follow-up on the plan we are pressure-testing in this thread.

${INPUT_TEXT}

Stay in pressure-tester mode. Read files as needed. No file edits.
EOF
}

run_plan() {
    local mode="$1"
    local -a rargs=(--thread-key "$THREAD_KEY")
    local prompt
    if [[ "$mode" == "continue" ]]; then
        rargs+=(--resume)
        prompt=$(build_continue_prompt)
    else
        prompt=$(build_fresh_prompt)
    fi
    set +e
    "$RUNNER" --timeout "$TIMEOUT" ${rargs[@]+"${rargs[@]}"} \
        ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} --prompt "$prompt" </dev/null
    PLAN_STATUS=$?
    set -e
}

run_plan "$MODE"

# Exit 3 = the stored thread is gone (never started, or GC'd). Degrade to a
# fresh round instead of failing — the caller wants a critique either way.
if [[ "$MODE" == "continue" && $PLAN_STATUS -eq 3 ]]; then
    echo "[codex-plan] no resumable plan thread; starting a fresh round" >&2
    run_plan reset
fi
# A completed turn already pings the user: `codex exec` invokes the `notify`
# program from ~/.codex/config.toml (the app-server path did not, which is why
# this used to be manual). Only ping for outcomes codex never reports itself.
if [[ $PLAN_STATUS -ne 0 ]]; then
    notify_codex_done "codex-plan FAILED (exit $PLAN_STATUS)" "$REPO_ROOT"
fi
exit $PLAN_STATUS
