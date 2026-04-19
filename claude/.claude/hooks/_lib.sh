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
