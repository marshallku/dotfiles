#!/usr/bin/env bash
# PostToolUse (Edit|Write) — the harness's computational sensor.
#
# Runs the edited project's type checker and feeds any errors back to Claude as
# additionalContext, so a type error is caught at edit time instead of at commit
# time by an expensive LLM reviewer.
#
# ---------------------------------------------------------------------------
# HISTORY — this hook was silently dead from 2026-04-21 to 2026-08-31.
#
# The old version ran under `set -euo pipefail` and built its error detail with:
#     DETAIL=$(cd "$ROOT" && npx tsc --noEmit --pretty false 2>&1 | grep "error TS" | head -5)
# With pipefail that pipeline inherits tsc's non-zero exit, and unlike the line
# above it there was no `|| true`, so `set -e` killed the script one line before
# the printf. It aborted on exactly the path where errors exist and only ever
# emitted `{}` on the clean path — i.e. it reported "no errors" and nothing else,
# for four months. It also never wrote to hooks-debug.log, so nothing about the
# failure was observable.
#
# Three rules follow from that and must not be undone:
#   1. NO `set -e`. A sensor that aborts is worse than no sensor: it reports
#      clean. Every fallible command is handled explicitly instead.
#   2. Every exit path logs, except the unsupported-file-extension one (see the
#      comment at that branch). If this hook ever dies again, the gap in
#      hook-events.jsonl is the evidence.
#   3. The checker runs ONCE and its output is reused for both the count and the
#      detail. The old version invoked tsc twice per edit.
# ---------------------------------------------------------------------------
#
# Opt-out: touch ~/.claude/state/post-typecheck-disabled
# Tuning:  POST_TYPECHECK_TIMEOUT_SECS (default 25; the hook's own budget in
#          settings.json is 30s, so stay under it)

set -uo pipefail

. "$(dirname "$0")/_lib.sh" 2>/dev/null || true

TIMEOUT_SECS="${POST_TYPECHECK_TIMEOUT_SECS:-25}"
case "$TIMEOUT_SECS" in ''|*[!0-9]*) TIMEOUT_SECS=25 ;; esac

# Fallbacks so the hook still runs if _lib.sh ever fails to source.
command -v hook_log   >/dev/null 2>&1 || hook_log()   { :; }
command -v hook_event >/dev/null 2>&1 || hook_event() { :; }

clean() { echo '{}'; exit 0; }

# PostToolUse surfaces hookSpecificOutput.additionalContext back to the model.
# (The old version emitted a bare `{"hookSpecificOutput":{"message":...}}`, which
# has no hookEventName and is not part of the schema.)
report() {
    jq -nc --arg ctx "$1" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
      }
    }' 2>/dev/null || echo '{}'
    exit 0
}

if [ -f "$HOME/.claude/state/post-typecheck-disabled" ]; then
    hook_event post-typecheck skip reason=disabled_marker
    clean
fi

INPUT=$(cat 2>/dev/null || echo '{}')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
if [ -z "$FILE_PATH" ]; then
    hook_event post-typecheck skip reason=no_file_path
    clean
fi

# The one deliberately unlogged exit. Every .md/.json/.sh/.txt edit lands here,
# so logging it would make "file this hook does not check" the highest-volume
# record in the ledger while saying nothing about the sensor's health. Every
# other exit path — including disabled and malformed input above — is recorded.
EXT="${FILE_PATH##*.}"
case "$EXT" in ts|tsx|rs|go) ;; *) clean ;; esac

# Nearest ancestor directory holding a project manifest.
find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/tsconfig.json" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/go.mod" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# Nearest ancestor holding node_modules/.bin/<name>. Walking up matters for
# pnpm/npm workspaces, where the binary is hoisted to the monorepo root.
find_local_bin() {
    local dir="$1" name="$2"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -x "$dir/node_modules/.bin/$name" ]; then
            printf '%s\n' "$dir/node_modules/.bin/$name"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

PROJECT_ROOT=$(find_project_root "$(dirname "$FILE_PATH")") || {
    hook_event post-typecheck skip lang="$EXT" reason=no_project_root file="$FILE_PATH"
    clean
}

# Run a checker once, setting OUTPUT and RUN_STATUS in the CURRENT shell
# (124 = timed out, 127 = no timeout binary available).
#
# Deliberately not `OUTPUT=$(run_checker ...)`: a command substitution runs the
# function in a subshell, so the RUN_STATUS assignment is discarded and the
# parent keeps its initial 0 — which reads as "checker succeeded" for both the
# timeout and the crashed-checker paths. That is the same shape of silent
# false-clean this hook was rewritten to eliminate. Route the output through a
# temp file and call run_checker as a plain command instead.
RUN_STATUS=0
OUTPUT=""
CHECK_OUT=$(mktemp 2>/dev/null || true)
cleanup() { [ -n "${CHECK_OUT:-}" ] && rm -f "$CHECK_OUT" 2>/dev/null; return 0; }
trap cleanup EXIT

run_checker() {
    RUN_STATUS=0
    OUTPUT=""
    if [ -z "${CHECK_OUT:-}" ]; then
        RUN_STATUS=127   # no temp file → treat as "could not run"
        return 0
    fi
    ( cd "$PROJECT_ROOT" && portable_timeout "$TIMEOUT_SECS" "$@" ) >"$CHECK_OUT" 2>&1
    RUN_STATUS=$?
    OUTPUT=$(cat "$CHECK_OUT" 2>/dev/null || true)
    return 0
}

LANG_LABEL=""
ERROR_RE=""

case "$EXT" in
    ts|tsx)
        [ -f "$PROJECT_ROOT/tsconfig.json" ] || { hook_event post-typecheck skip lang=ts reason=no_tsconfig root="$PROJECT_ROOT"; clean; }
        # Require a real local tsc. `npx tsc` in a project without a typescript
        # dependency resolves to an unrelated binary that prints "This is not the
        # tsc command you are looking for" and exits 0 — the grep then finds no
        # "error TS" and the sensor reports clean. That is a silent false
        # negative, so refuse to guess.
        TSC_BIN=$(find_local_bin "$PROJECT_ROOT" tsc) || {
            hook_event post-typecheck skip lang=ts reason=no_local_tsc root="$PROJECT_ROOT"
            clean
        }
        LANG_LABEL="TypeScript"
        ERROR_RE='error TS'
        run_checker "$TSC_BIN" --noEmit --pretty false
        ;;
    rs)
        [ -f "$PROJECT_ROOT/Cargo.toml" ] || { hook_event post-typecheck skip lang=rs reason=no_cargo_toml root="$PROJECT_ROOT"; clean; }
        command -v cargo >/dev/null 2>&1 || { hook_event post-typecheck skip lang=rs reason=no_cargo root="$PROJECT_ROOT"; clean; }
        LANG_LABEL="Rust"
        # `cargo check --message-format short` emits two shapes:
        #   src/main.rs:1:27: error[E0308]: mismatched types...   <- the diagnostic
        #   error: could not compile `x` due to 1 previous error  <- cargo's summary
        # The inherited '^error' matched ONLY the summary, so the sensor reported
        # "1 Rust error" and showed the useless rollup line no matter how many
        # real errors there were. Match the file-prefixed diagnostics instead.
        ERROR_RE=':[0-9]+:[0-9]+: error'
        run_checker cargo check --message-format short
        ;;
    go)
        [ -f "$PROJECT_ROOT/go.mod" ] || { hook_event post-typecheck skip lang=go reason=no_go_mod root="$PROJECT_ROOT"; clean; }
        command -v go >/dev/null 2>&1 || { hook_event post-typecheck skip lang=go reason=no_go root="$PROJECT_ROOT"; clean; }
        LANG_LABEL="Go"
        ERROR_RE='^[^[:space:]]+\.go:[0-9]+'
        run_checker go vet ./...
        ;;
esac

# A timeout is not "clean" — it is a sensor that failed to sense. Report nothing
# to Claude (a timeout says nothing about the code) but leave the evidence, so
# "this sensor always times out" shows up as a trend instead of as silence.
if [ "$RUN_STATUS" -eq 124 ]; then
    hook_log post-typecheck "TIMEOUT after ${TIMEOUT_SECS}s: $LANG_LABEL in $PROJECT_ROOT"
    hook_event post-typecheck timeout lang="$EXT" secs="$TIMEOUT_SECS" root="$PROJECT_ROOT"
    clean
fi
if [ "$RUN_STATUS" -eq 127 ]; then
    hook_log post-typecheck "no timeout binary; skipped $LANG_LABEL check in $PROJECT_ROOT"
    hook_event post-typecheck skip lang="$EXT" reason=no_timeout_binary root="$PROJECT_ROOT"
    clean
fi

MATCHES=$(printf '%s\n' "$OUTPUT" | grep -E "$ERROR_RE" 2>/dev/null || true)

if [ -z "$MATCHES" ]; then
    # Exit 0 with no matched lines is a genuine pass. A non-zero exit with no
    # matched lines means the checker itself failed (bad config, missing dep) —
    # that is a broken sensor, not clean code, so record it.
    if [ "$RUN_STATUS" -ne 0 ]; then
        hook_log post-typecheck "checker exited $RUN_STATUS with no parsable errors: $LANG_LABEL in $PROJECT_ROOT"
        hook_event post-typecheck checker_error lang="$EXT" status="$RUN_STATUS" root="$PROJECT_ROOT" \
            head="$(printf '%s' "$OUTPUT" | head -c 300)"
    else
        hook_event post-typecheck pass lang="$EXT" root="$PROJECT_ROOT"
    fi
    clean
fi

COUNT=$(printf '%s\n' "$MATCHES" | grep -c '' 2>/dev/null || echo 0)
DETAIL=$(printf '%s\n' "$MATCHES" | head -5)

hook_log post-typecheck "$COUNT $LANG_LABEL error(s) in $PROJECT_ROOT"
hook_event post-typecheck fail lang="$EXT" errors="$COUNT" root="$PROJECT_ROOT"

MSG="[post-typecheck] $COUNT $LANG_LABEL error(s) in $PROJECT_ROOT after editing $FILE_PATH:

$DETAIL"
[ "$COUNT" -gt 5 ] && MSG="$MSG

(showing first 5 of $COUNT)"

report "$MSG"
