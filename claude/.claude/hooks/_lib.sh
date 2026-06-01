#!/usr/bin/env bash
# Shared portability helpers for hooks and scripts.
# Source with: . "$(dirname "$0")/_lib.sh" (hooks)
#           or: . "$(dirname "$0")/../hooks/_lib.sh" (scripts)

# Portable md5 — prints the hex digest of stdin.
# Linux: md5sum; macOS: md5 -q
portable_md5() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | awk '{print $1}'
    elif command -v md5 >/dev/null 2>&1; then
        md5 -q
    else
        echo "[_lib] no md5 implementation found" >&2
        return 1
    fi
}

# 12-char repo hash used by the cross-review marker system.
repo_hash() {
    printf '%s' "$1" | portable_md5 | head -c 12
}

# Portable timeout — runs a command with a wall-clock limit.
# Linux: timeout; macOS: gtimeout (coreutils). Returns 127 if neither exists
# so callers can distinguish "missing binary" from "command failed".
portable_timeout() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$secs" "$@"
    else
        echo "[_lib] no timeout binary found (install coreutils: 'brew install coreutils')" >&2
        return 127
    fi
}

# Portable mtime — prints file modification time as unix epoch.
portable_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Portable "format epoch as human date".
portable_fmtdate() {
    local epoch="$1"
    local fmt="${2:-%Y-%m-%d %H:%M}"
    date -d "@$epoch" +"$fmt" 2>/dev/null || date -r "$epoch" +"$fmt" 2>/dev/null || echo ""
}

# Predicate: would auto-cross-review.sh block this Stop event right now?
# Returns 0 if it would block, 1 otherwise. Pure read-only — writes nothing.
# Mirrors auto-cross-review.sh's gating; keep in sync.
#
# Race-aware: auto-cross-review.sh creates stop-blocked-<session> AS it blocks
# the current Stop. A naive presence check misclassifies that event as
# "already blocked, will skip" when it's actually "blocking right now".
# Resolved with a freshness window: a marker newer than ~2s is treated as
# evidence of an in-flight block by the parallel hook (suppress the
# notification); only an older marker is trusted as "previous-session block,
# this Stop will pass through".
#
# Args: session_id, cwd, transcript_path
auto_review_would_block() {
    local session="${1:-default}" cwd="${2:-}" transcript="${3:-}"
    local state="$HOME/.claude/state"
    local dirty="$state/dirty-${session}.log"
    local blocked="$state/stop-blocked-${session}"
    local disabled="$state/auto-review-disabled"
    local min_files="${AUTO_REVIEW_MIN_FILES:-2}"
    local min_lines="${AUTO_REVIEW_MIN_LINES:-40}"
    local freshness="${AUTO_REVIEW_BLOCK_FRESH_SECS:-2}"

    [[ -f "$disabled" ]] && return 1
    [[ ! -f "$dirty" ]] && return 1
    if [[ -f "$blocked" ]]; then
        local age=$(( $(date +%s) - $(portable_mtime "$blocked") ))
        if [[ "$age" -gt "$freshness" ]]; then
            return 1  # old marker → previous-session block; this Stop passes
        else
            return 0  # fresh marker → parallel auto-cross-review just blocked this Stop
        fi
    fi

    local file_count
    file_count=$(sort -u "$dirty" 2>/dev/null | wc -l | tr -d ' ')
    [[ "${file_count:-0}" -lt "$min_files" ]] && return 1

    if [[ -n "$cwd" ]]; then
        local repo
        if repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
            local rh
            rh=$(repo_hash "$repo")
            [[ -f "$state/reviewed-$rh" ]] && return 1
            local tracked untracked weighted
            tracked=$(git -C "$repo" diff HEAD 2>/dev/null | wc -l | tr -d ' ')
            untracked=$(git -C "$repo" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
            weighted=$(( ${tracked:-0} + ${untracked:-0} * 10 ))
            [[ "$weighted" -lt "$min_lines" ]] && return 1
        fi
    fi

    if [[ -f "$transcript" ]]; then
        local last_text
        last_text=$(tail -c 16384 "$transcript" 2>/dev/null \
            | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' 2>/dev/null \
            | tail -n1 || true)
        echo "$last_text" | grep -qE '\?\s*$' && return 1
    fi

    return 0
}

# Path to notify-codex.sh. Anchored to the deployed ~/.claude/hooks location
# (same convention as ~/.codex/config.toml's absolute notify path); BASH_SOURCE
# is unreliable when this lib is sourced, so don't derive from it.
_NOTIFY_CODEX_SH="$HOME/.claude/hooks/notify-codex.sh"

# notify_codex_done <summary> [cwd]
# Fire a user-facing completion notification for a codex turn.
#
# Why this exists: the codex skills route through codex-companion.sh →
# codex-plugin-cc *app-server*, which consumes turn-complete as an internal
# JSON-RPC event and never invokes the `notify` program in ~/.codex/config.toml.
# So notify-codex.sh never fires for skill-driven calls. Wrappers call this to
# ping explicitly. Reuses notify-codex.sh formatting via a synthesized
# agent-turn-complete payload, so the notify-codex-disabled marker still works.
#
# Best-effort and non-blocking: never fails the caller, backgrounds the notify.
notify_codex_done() {
    local summary="$1"
    local cwd="${2:-$PWD}"
    [[ -f "$_NOTIFY_CODEX_SH" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local payload
    payload=$(jq -n --arg cwd "$cwd" --arg tid "codex-companion" --arg msg "$summary" \
        '{type:"agent-turn-complete", cwd:$cwd, "turn-id":$tid, "last-assistant-message":$msg}' 2>/dev/null) || return 0
    bash "$_NOTIFY_CODEX_SH" "$payload" >/dev/null 2>&1 &
    return 0
}
