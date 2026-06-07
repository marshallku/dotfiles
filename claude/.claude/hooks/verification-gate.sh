#!/usr/bin/env bash
# Stop hook — if this session changed code but the transcript shows no evidence
# that tests / e2e / the app were actually run, block the stop once and tell
# Claude to verify before concluding (or to state why verification is N/A).
#
# Sibling to auto-cross-review.sh: that gate asks "did an *external* reviewer
# see this?"; this one asks "did *you* actually run it?" — one step earlier.
# Both are single-shot per session and independent; on a turn that trips both,
# Claude simply receives both instructions.
#
# Fires at most once per session (verify-blocked-<session> marker).
# Skips if:
#   - ~/.claude/state/auto-review-disabled exists (master opt-out)
#   - ~/.claude/state/verify-gate-disabled exists (granular opt-out)
#   - fewer than AUTO_REVIEW_MIN_FILES (default 2) distinct files touched
#   - the transcript shows a test/e2e/run/deploy command was actually executed
#   - last assistant message ends with "?" (clarification pause heuristic)
#
# Note: a change that legitimately needs no e2e is handled by the block itself —
# it is single-shot, so Claude just states "verification N/A: <reason>" once and
# concludes. (An earlier intent-file auto-skip was removed: parsing verification.e2e
# from YAML in bash was fragile and a recurring source of false-relaxation.)
#
# Env overrides:
#   AUTO_REVIEW_MIN_FILES  (default 2)  — reuse the review gate's threshold
#   VERIFY_EXTRA_RUNNERS   (default "") — extra program names to count as a
#                                          verification command (space-separated)

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

LOG_FILE="$HOME/.claude/hooks-debug.log"
INPUT=$(cat)

SESSION=$(echo "$INPUT" | jq -r '.session_id // "default"')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

STATE_DIR="$HOME/.claude/state"
DIRTY_LOG="$STATE_DIR/dirty-${SESSION}.log"
BLOCKED="$STATE_DIR/verify-blocked-${SESSION}"
DISABLED="$STATE_DIR/auto-review-disabled"
DISABLED_SELF="$STATE_DIR/verify-gate-disabled"

MIN_FILES="${AUTO_REVIEW_MIN_FILES:-2}"

# Evidence is decided by the INVOKED PROGRAM, not substring presence (see the
# is_verification awk below). We split each command on shell connectors, strip
# env-var prefixes, and inspect the first token (the program) plus its sub-
# command — so `echo cargo test`, `cat vitest.config.ts`, `rg cargo test`, and
# `ls cypress` do NOT count, while `cargo test`, `FOO=x pnpm run e2e`, and
# `a && make deploy-remote` do. Build/typecheck/lint are deliberately excluded
# (post-typecheck.sh covers those); only behavioural runners count.
#
# Projects with a bespoke runner can extend the first-token whitelist:
#   VERIFY_EXTRA_RUNNERS="just bats" (space-separated program names)
EXTRA_RUNNERS="${VERIFY_EXTRA_RUNNERS:-}"

log() {
    echo "[$(date +%H:%M:%S)] verification-gate: $*" >> "$LOG_FILE"
}

# Opt-outs
[ -f "$DISABLED" ] && { echo '{}'; exit 0; }
[ -f "$DISABLED_SELF" ] && { echo '{}'; exit 0; }

# No tracked edits this session → nothing to verify
[ -f "$DIRTY_LOG" ] || { echo '{}'; exit 0; }

# Already fired once this session → let this stop proceed
[ -f "$BLOCKED" ] && { echo '{}'; exit 0; }

# Trivial change (few files) → skip
FILE_COUNT=$(sort -u "$DIRTY_LOG" 2>/dev/null | wc -l | tr -d ' ')
if [ "${FILE_COUNT:-0}" -lt "$MIN_FILES" ]; then
    log "skip: only $FILE_COUNT file(s) touched (min $MIN_FILES)"
    echo '{}'; exit 0
fi

# Evidence check — did Claude actually *run* a test/e2e/run/deploy command this
# session? Scan ONLY the Bash commands that were executed (tool_use inputs in
# this session's jsonl). NOT tool_result output or file contents: those can
# contain runner words without anything having run. Each command is parsed by
# invoked program (first token of each connector-split segment), so an argument
# or filename that merely names a runner does not count.
if [ -f "$TRANSCRIPT" ]; then
    # @json keeps each command on ONE line (newlines escaped as \n), so awk gets
    # exactly one record per command and can decode + skip heredoc bodies itself.
    EVID=$(jq -rc '.. | objects | select(.type? == "tool_use" and (.name? == "Bash")) | .input.command? // empty | @json' \
        "$TRANSCRIPT" 2>/dev/null | awk -v extra="$EXTRA_RUNNERS" '
        function is_verification(seg,   n,a,i,t1,t2,t3,script,r) {
            # Normalize: repeatedly peel leading whitespace, FOO=bar env
            # assignments, wrapper programs, and wrapper option flags — in any
            # order, until the first token is the program actually invoked.
            # (Looping handles e.g. `env RUST_LOG=x cargo test` and `sudo -E …`.)
            # Known narrow gap: value-taking wrapper options like `env -u FOO`
            # leave the value as the apparent program → that rare form yields a
            # false negative (an extra nudge), which is the safe failure side.
            changed = 1
            while (changed) {
                changed = 0
                if (sub(/^[[:space:]]+/, "", seg)) changed = 1
                if (sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", seg)) changed = 1
                if (sub(/^(sudo|env|time|nice|stdbuf|xvfb-run|command|nohup|setsid)[[:space:]]+/, "", seg)) changed = 1
                if (sub(/^-{1,2}[A-Za-z][^[:space:]]*[[:space:]]+/, "", seg)) changed = 1
            }
            n = split(seg, a, /[[:space:]]+/)
            if (n == 0) return 0
            t1 = a[1]; t2 = a[2]; t3 = a[3]
            sub(/^.*\//, "", t1)           # ./bin/cargo -> cargo
            # extra user-supplied runners (exact first-token match)
            if (extra != "") { en = split(extra, ea, /[[:space:]]+/)
                for (i=1;i<=en;i++) if (t1 == ea[i]) return 1 }
            if (t1 ~ /^(pytest|vitest|jest|mocha|cypress|playwright|ava|tox|nextest)$/) return 1
            if (t1 == "deploy-remote") return 1
            if (t1 == "cargo" && t2 ~ /^(test|nextest|run)$/) return 1
            if (t1 == "go"    && t2 ~ /^(test|run)$/) return 1
            if (t1 == "npx"   && t2 ~ /^(playwright|vitest|jest|cypress|mocha|ava)$/) return 1
            if (t1 ~ /^(npm|pnpm|yarn|bun)$/) {
                script = t2
                if (t2 ~ /^(run|run-script|exec)$/) script = t3
                if (script ~ /^(test|test:.+|e2e|e2e:.+|dev|start|serve|preview)$/) return 1
            }
            if (t1 == "make") {
                # whole-target match (allow suffixes like deploy-remote, test:ci,
                # e2e_ci) — NOT substring, so `make protest` / `make attest` /
                # `make build-test-fixtures` do not count.
                for (i=2;i<=n;i++)
                    if (a[i] ~ /^(test|e2e|deploy|run|dev|start|serve)([:_-][A-Za-z0-9:._-]*)?$/) return 1
            }
            return 0
        }
        {
          cmd = $0
          sub(/^"/, "", cmd); sub(/"$/, "", cmd)        # unwrap @json quotes
          gsub(/\\"/, "\"", cmd); gsub(/\\t/, " ", cmd); gsub(/\\\\/, "\\", cmd)
          nl = split(cmd, lines, /\\n/)                 # physical lines of the command
          delim = ""
          for (li = 1; li <= nl; li++) {
            ln = lines[li]
            if (delim != "") {                          # inside a heredoc body → skip
              d = ln; gsub(/^[[:space:]]+/, "", d); gsub(/[[:space:]]+$/, "", d)
              if (d == delim) delim = ""
              continue
            }
            # A heredoc on this line: capture the delimiter word so its body
            # (following lines) is treated as data, not commands.
            if (match(ln, /<<-?[[:space:]]*["'\''`]?[A-Za-z_][A-Za-z0-9_]*/)) {
              hd = substr(ln, RSTART, RLENGTH)
              gsub(/^<<-?[[:space:]]*["'\''`]?/, "", hd)
              delim = hd
            }
            # Analyze this line: split on shell connectors, check invoked program.
            gsub(/&&|\|\||[;|&]/, "\n", ln)
            m = split(ln, segs, /\n/)
            for (k = 1; k <= m; k++) if (is_verification(segs[k])) found++
          }
        }
        END { print found+0 }' || true)
    if [ "${EVID:-0}" -gt 0 ]; then
        log "skip: found $EVID verification command(s) in transcript"
        echo '{}'; exit 0
    fi
fi

# Clarification-pause heuristic — Claude is asking the user, not finishing.
if [ -f "$TRANSCRIPT" ]; then
    LAST_TEXT=$(tail -c 16384 "$TRANSCRIPT" 2>/dev/null \
        | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
        | tail -n1 || true)
    if echo "$LAST_TEXT" | grep -qE '\?\s*$'; then
        log "skip: last message looks like a clarification question"
        echo '{}'; exit 0
    fi
fi

# Block once and inject the verification mandate
touch "$BLOCKED"
log "BLOCK: no verification evidence ($FILE_COUNT files touched)"

REASON="[verify-gate] You changed code across $FILE_COUNT files this session, but the transcript shows no sign that you actually ran anything to verify it (no test runner, e2e/browser driver, deploy, or app run). Before concluding this turn:

1. If the change is verifiable, RUN it — unit tests for the touched code, and an e2e / real-app check if behaviour changed (per the project's usual command: cargo test, vitest, playwright, make run, deploy-remote, etc.). Report the actual result, not an assumption.
2. If verification genuinely does not apply (docs/config/pure-rename, or a library-internal change unit tests already cover), say so in ONE line with the reason, then conclude.

Do NOT claim the work is done while silently skipping verification — that is the exact failure this gate exists to catch. This fires at most once per session. Opt-out: touch ~/.claude/state/verify-gate-disabled"

jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
