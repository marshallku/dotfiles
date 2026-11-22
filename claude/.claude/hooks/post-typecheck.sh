#!/usr/bin/env bash
# @hook-event: PostToolUse
# PostToolUse (Edit|Write) — the harness's computational sensor: runs the edited project's
# type checker and feeds errors back to Claude as additionalContext, so a type error surfaces
# at edit time rather than at commit review.
#
# Rules that must not be undone:
#   1. No `set -e`: a sensor that aborts reports clean. Handle every fallible command explicitly.
#   2. Every exit path logs, except the unchecked-extension one, which records a daily
#      heartbeat; a gap in hook-events.jsonl means the hook died.
#   3. Run the checker once and reuse its output for both the count and the detail.
#
# Opt-out: touch ~/.claude/state/post-typecheck-disabled
# Tuning:  POST_TYPECHECK_TIMEOUT_SECS (default 25; stay under the hook's 30s budget in settings.json)

set -uo pipefail

. "$(dirname "$0")/_lib.sh" 2>/dev/null || true

TIMEOUT_SECS="${POST_TYPECHECK_TIMEOUT_SECS:-25}"
case "$TIMEOUT_SECS" in ''|*[!0-9]*) TIMEOUT_SECS=25 ;; esac

# Fallbacks so the hook still runs if _lib.sh ever fails to source.
command -v hook_log   >/dev/null 2>&1 || hook_log()   { :; }
command -v hook_event >/dev/null 2>&1 || hook_event() { :; }

clean() { echo '{}'; exit 0; }

# PostToolUse surfaces hookSpecificOutput.additionalContext back to the model.
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

# The one deliberately unlogged exit: every .md/.json/.sh edit lands here and would drown the
# ledger. One `heartbeat` a day keeps harness-report from reading the hook as gone silent.
EXT="${FILE_PATH##*.}"
case "$EXT" in
    ts|tsx|rs|go) ;;
    *)
        BEAT="$HOME/.claude/state/post-typecheck-heartbeat-$(date '+%Y-%m-%d')"
        if [ ! -e "$BEAT" ]; then
            rm -f "$HOME"/.claude/state/post-typecheck-heartbeat-* 2>/dev/null
            : > "$BEAT" 2>/dev/null && hook_event post-typecheck heartbeat
        fi
        clean
        ;;
esac

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

find_pnp_root() {
    local dir="$1"
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if [ -f "$dir/.pnp.cjs" ]; then
            printf '%s\n' "$dir"
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

# run_checker sets OUTPUT and RUN_STATUS (124 = timed out, 127 = could not run) in the current
# shell. Never call it as `OUTPUT=$(run_checker ...)`: the subshell drops RUN_STATUS, which
# then reads as a clean pass; output goes through a temp file instead.
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
        LANG_LABEL="TypeScript"
        ERROR_RE='error TS'
        if TSC_BIN=$(find_local_bin "$PROJECT_ROOT" tsc); then
            run_checker "$TSC_BIN" --noEmit --pretty false
        elif PNP_ROOT=$(find_pnp_root "$PROJECT_ROOT") && command -v yarn >/dev/null 2>&1 \
            && (cd "$PROJECT_ROOT" && yarn bin tsc >/dev/null 2>&1); then
            # Yarn PnP has no node_modules/.bin; `yarn bin tsc` proves the project's own
            # typescript resolves. --incremental keeps re-checks fast, with its build info in
            # a cache, never in the repository.
            BUILDINFO_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/post-typecheck"
            mkdir -p "$BUILDINFO_DIR" 2>/dev/null
            BUILDINFO="$BUILDINFO_DIR/$(printf '%s' "$PROJECT_ROOT" | portable_md5 2>/dev/null | head -c 16).tsbuildinfo"
            run_checker yarn tsc --noEmit --pretty false --incremental --tsBuildInfoFile "$BUILDINFO"
        else
            hook_event post-typecheck skip lang=ts reason=no_local_tsc root="$PROJECT_ROOT"
            clean
        fi
        ;;
    rs)
        [ -f "$PROJECT_ROOT/Cargo.toml" ] || { hook_event post-typecheck skip lang=rs reason=no_cargo_toml root="$PROJECT_ROOT"; clean; }
        command -v cargo >/dev/null 2>&1 || { hook_event post-typecheck skip lang=rs reason=no_cargo root="$PROJECT_ROOT"; clean; }
        LANG_LABEL="Rust"
        # A crate whose -sys dependencies need system libraries this host lacks
        # (the GTK client of a cross-platform repo, edited on macOS) can never be
        # checked here. Remember that per manifest so every later edit skips
        # instantly instead of re-running a doomed dependency build.
        UNBUILDABLE_DIR="$HOME/.claude/state/post-typecheck-unbuildable"
        # A workspace member's lockfile lives at the workspace root, not beside it.
        WS_MANIFEST=$(cd "$PROJECT_ROOT" && cargo locate-project --workspace --message-format plain 2>/dev/null)
        WS_ROOT=$(dirname "${WS_MANIFEST:-$PROJECT_ROOT/Cargo.toml}")
        UNBUILDABLE_KEY=$(cat "$PROJECT_ROOT/Cargo.toml" "$WS_ROOT/Cargo.toml" "$WS_ROOT/Cargo.lock" 2>/dev/null | shasum 2>/dev/null | cut -c1-16)
        UNBUILDABLE_MARK="$UNBUILDABLE_DIR/$(printf '%s' "$PROJECT_ROOT" | shasum 2>/dev/null | cut -c1-16)"
        if [ -n "$UNBUILDABLE_KEY" ] && [ "$(cat "$UNBUILDABLE_MARK" 2>/dev/null)" = "$UNBUILDABLE_KEY" ]; then
            hook_event post-typecheck skip lang=rs reason=host_unbuildable_cached root="$PROJECT_ROOT"
            clean
        fi
        # Count only file-prefixed diagnostics (`src/main.rs:1:27: error[E0308]: ...`), not
        # cargo's `error: could not compile ...` summary line.
        ERROR_RE=':[0-9]+:[0-9]+: error'
        run_checker cargo check --message-format short
        ;;
    go)
        [ -f "$PROJECT_ROOT/go.mod" ] || { hook_event post-typecheck skip lang=go reason=no_go_mod root="$PROJECT_ROOT"; clean; }
        command -v go >/dev/null 2>&1 || { hook_event post-typecheck skip lang=go reason=no_go root="$PROJECT_ROOT"; clean; }
        LANG_LABEL="Go"
        # `go vet` may prefix type errors with "vet: " (`vet: internal/x/y.go:45:15: undefined: Foo`).
        ERROR_RE='^(vet: )?[^[:space:]]+\.go:[0-9]+'
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
    if [ "$RUN_STATUS" -ne 0 ] && [ "$EXT" = rs ] \
        && grep -qE 'failed to run custom build command for `[^`]+-sys ' "$CHECK_OUT" 2>/dev/null \
        && grep -q 'pkg-config' "$CHECK_OUT" 2>/dev/null; then
        # grep reads the file, not a pipe: `printf | grep -q` under pipefail turns an
        # early match into SIGPIPE (141) and a false "no match" on large output.
        # Missing host libraries, not a code problem and not a broken sensor.
        mkdir -p "$UNBUILDABLE_DIR" 2>/dev/null && [ -n "$UNBUILDABLE_KEY" ] \
            && printf '%s' "$UNBUILDABLE_KEY" >"$UNBUILDABLE_MARK" 2>/dev/null
        hook_log post-typecheck "host lacks system libs for $PROJECT_ROOT; skipping until Cargo.toml/lock change"
        hook_event post-typecheck skip lang=rs reason=host_unbuildable root="$PROJECT_ROOT"
    elif [ "$RUN_STATUS" -ne 0 ]; then
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
