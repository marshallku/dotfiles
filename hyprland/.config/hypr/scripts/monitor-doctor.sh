#!/usr/bin/env bash
# Diagnose — and revive — a Hyprland output that is connected but dark.
#
# The failure this exists for: a DP connector that flaps during boot leaves
# aquamarine with no CRTC assigned to the output ("Cannot commit a disconnected
# output" -> "DP-1 is not connected, clearing stale crtc 392"), while
# Hyprland's own monitor object survives the flap. `hyprctl monitors` then
# reports the output as active at the right mode with nothing scanning it out,
# so the panel stays black and every config check comes back clean. Only
# re-committing the output (disable, then re-enable) clears it.
#
# Reading the log correctly is most of the work here:
#   - the DRM state transitions ("Disabling output", "enabledState changed")
#     are useless as a health check. aquamarine disables an output as a normal
#     step of every commit, and the log is written asynchronously, so its tail
#     regularly shows a teardown for an output that is perfectly alive.
#   - the CRTC assignment lines ("slot 1 crtc 392 taken by DP-1" vs "connector
#     DP-1, has crtc -1") describe STATE rather than transitions and are
#     re-emitted on every hotplug rescan. That is the signal worth trusting.
#
# Usage:
#   monitor-doctor.sh [OUTPUT]      diagnose, and re-commit when that is the fix
#   monitor-doctor.sh -n [OUTPUT]   diagnose only, change nothing
#   monitor-doctor.sh -v [OUTPUT]   also print the raw log evidence
#
# OUTPUT defaults to DP-1. Exits 0 when the output ends up live, 1 otherwise.
set -euo pipefail

OUTPUT="DP-1"
DRY_RUN=0
VERBOSE=0
ATTEMPTS=3
MONITORS_LUA="$HOME/.config/hypr/monitors_local.lua"

# Re-committing an output goes through the compat shim: `hyprctl keyword` is
# rejected outright under the Lua config manager ("keyword can't work with
# non-legacy parsers. Use eval.").
# shellcheck source=hyprctl-compat.sh
. "$(dirname "$(readlink -f "$0")")/hyprctl-compat.sh"

die() { echo "monitor-doctor: $*" >&2; exit 1; }
say() { echo "$*"; }
# The screen being dark is exactly when you are looking at the other monitor.
toast() { command -v notify-send >/dev/null && notify-send "$@" || true; }

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=1 ;;
        -v|--verbose) VERBOSE=1 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \?//'; exit 0 ;;
        -*) die "unknown flag: $1" ;;
        *) OUTPUT="$1" ;;
    esac
    shift
done

command -v hyprctl >/dev/null || die "hyprctl not found"
command -v jq >/dev/null || die "jq not found"
hyprctl monitors >/dev/null 2>&1 || die "no reachable Hyprland instance"

################
### EVIDENCE ###
################

# The kernel's view. A connector the kernel calls disconnected is a cable, port
# or panel problem, and no amount of compositor poking will light it up.
connector_dir() {
    local d
    for d in /sys/class/drm/card*-"$OUTPUT"; do
        [ -r "$d/status" ] && { printf '%s\n' "$d"; return 0; }
    done
    return 1
}

# Prefer the log of the instance we are actually talking to over the newest one
# on disk — a leftover log from a previous session would date the verdict.
log_file() {
    local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
    if [ -n "$sig" ] && [ -f "$runtime/hypr/$sig/hyprland.log" ]; then
        printf '%s\n' "$runtime/hypr/$sig/hyprland.log"
        return 0
    fi
    ls -t "$runtime"/hypr/*/hyprland.log 2>/dev/null | head -1 || true
}

# Every line in which aquamarine states whether this output holds a CRTC.
crtc_lines() {
    [ -n "$LOG" ] || return 0
    grep -E "slot [0-9]+ crtc [0-9]+ taken by $OUTPUT,|crtc [0-9]+ assigned to $OUTPUT\$|Skipping connector $OUTPUT, has crtc [0-9]+|connector $OUTPUT, has crtc -1|$OUTPUT is not connected, clearing stale crtc|$OUTPUT is disabled, releasing crtc" \
        "$LOG" 2>/dev/null | sed 's/^.*drm: //' || true
}

hypr_field() { hyprctl monitors all -j | jq -r --arg n "$OUTPUT" '.[] | select(.name == $n) | '"$1"; }

#################
### DIAGNOSIS ###
#################

collect() {
    CONN_DIR="$(connector_dir || true)"
    if [ -n "$CONN_DIR" ]; then
        SYSFS_STATUS="$(cat "$CONN_DIR/status")"
        SYSFS_ENABLED="$(cat "$CONN_DIR/enabled" 2>/dev/null || echo '?')"
        SYSFS_DPMS="$(cat "$CONN_DIR/dpms" 2>/dev/null || echo '?')"
    else
        SYSFS_STATUS="no-connector"; SYSFS_ENABLED="?"; SYSFS_DPMS="?"
    fi

    LOG="$(log_file)"
    CRTC_LINE="$(crtc_lines | tail -1 || true)"
    case "$CRTC_LINE" in
        *"has crtc -1"*|*"is not connected, clearing"*|*"is disabled, releasing"*) CRTC_HELD=no ;;
        "") CRTC_HELD=unknown ;;
        *) CRTC_HELD=yes ;;
    esac
    FLAPS="$(grep -c "Connector $OUTPUT disconnected" "$LOG" 2>/dev/null || true)"

    HYPR_PRESENT="$(hypr_field '.name')"
    HYPR_DESC="$(hypr_field '.description')"
    HYPR_MODE="$(hypr_field '"\(.width)x\(.height)@\(.refreshRate | .*100 | round / 100) at \(.x)x\(.y)"')"
    HYPR_DISABLED="$(hypr_field '.disabled')"
    HYPR_WIDTH="$(hypr_field '.width')"
    VERDICT="$(verdict)"
}

# NO_CONNECTOR | LINK_DOWN | ABSENT | DARK | PHANTOM | LIVE
#
# Ordered by how much each source can be trusted: the kernel and Hyprland's own
# state are read live, so they settle everything they can answer. The log only
# gets the one question they cannot — whether anything is actually scanning out
# an output that Hyprland already claims is on.
verdict() {
    [ "$SYSFS_STATUS" != "no-connector" ] || { echo NO_CONNECTOR; return; }
    [ "$SYSFS_STATUS" = "connected" ] || { echo LINK_DOWN; return; }
    [ -n "$HYPR_PRESENT" ] || { echo ABSENT; return; }
    [ "$HYPR_DISABLED" = "false" ] && [ "${HYPR_WIDTH:-0}" -gt 0 ] || { echo DARK; return; }
    [ "$CRTC_HELD" != "no" ] || { echo PHANTOM; return; }
    echo LIVE
}

report() {
    say "output   : $OUTPUT${HYPR_DESC:+  ($HYPR_DESC)}"
    say "kernel   : status=$SYSFS_STATUS enabled=$SYSFS_ENABLED dpms=$SYSFS_DPMS"
    if [ -n "$HYPR_PRESENT" ]; then
        say "hyprland : $HYPR_MODE  disabled=$HYPR_DISABLED"
    else
        say "hyprland : not in the monitor list"
    fi
    say "crtc     : ${CRTC_LINE:-(no crtc line in the log)}"
    say "verdict  : $VERDICT"
    if [ "$VERBOSE" -eq 1 ]; then
        say ""
        say "--- crtc assignment history ---"
        crtc_lines | tail -20
    fi
}

# An output that dropped more than once in one session is unstable at the link
# level. Re-committing lights it up now but does nothing about the next boot.
instability_note() {
    [ "${FLAPS:-0}" -ge 2 ] || return 0
    say ""
    say "note     : $OUTPUT dropped $FLAPS times this session — the link itself is unstable."
    say "           Re-committing revives it but does not stop it recurring. In order:"
    say "           1. monitor OSD: DisplayPort version 1.4 -> 1.2, and turn Deep Sleep off"
    say "           2. try another cable, or another port (the free DP-* connectors)"
    say "           3. drop the refresh rate in $MONITORS_LUA"
}

###########
### FIX ###
###########

# Pull one `field = value` out of a single-line hl.monitor({ ... }) call.
# Handles both quoted strings and bare numbers; prints nothing when absent.
lua_field() {
    local re="[{,][[:space:]]*$2[[:space:]]*=[[:space:]]*(\"([^\"]*)\"|[^,}[:space:]]+)"
    [[ $1 =~ $re ]] || return 1
    printf '%s\n' "${BASH_REMATCH[2]:-${BASH_REMATCH[1]}}"
}

# The rule this machine wrote for this output, matched the way Hyprland itself
# matches: by connector name, or by the EDID description that monitors_local.lua
# recommends using instead so rules survive a cable swap. Rules built from a Lua
# variable or a loop cannot be resolved from here and are skipped — the same
# limitation the hyprlang parser this replaced had with config variables.
# Prints "MODE,POSITION,SCALE" or nothing.
config_spec() {
    local line key mode position scale
    [ -r "$MONITORS_LUA" ] || return 0
    while IFS= read -r line; do
        key="$(lua_field "$line" output)" || continue
        [ -n "$key" ] || continue
        case "$key" in
            "$OUTPUT") ;;
            desc:*)
                [ -n "$HYPR_DESC" ] || continue
                case "$HYPR_DESC" in "${key#desc:}"*) ;; *) continue ;; esac ;;
            *) continue ;;
        esac
        mode="$(lua_field "$line" mode || true)"
        position="$(lua_field "$line" position || true)"
        scale="$(lua_field "$line" scale || true)"
        printf '%s,%s,%s\n' "${mode:-preferred}" "${position:-auto}" "${scale:-1}"
        return 0
    done < <(grep -E '^[[:space:]]*hl\.monitor\(' "$MONITORS_LUA" 2>/dev/null || true)
    return 0
}

# Falling back is legitimate — a machine need not have a rule for every output —
# but it must be loud, because the fallback changes mode, position and scale.
monitor_spec() {
    local spec
    spec="$(config_spec)"
    if [ -n "$spec" ]; then
        printf '%s\n' "$spec"
    else
        say "warn     : no rule for $OUTPUT in $MONITORS_LUA — reviving at 'preferred,auto,1'" >&2
        printf 'preferred,auto,1\n'
    fi
}

# grim renders through the compositor, so a capture at the output's full size
# says the compositor is producing frames for it. It cannot prove the panel lit
# up — that is the one thing only the person in front of it can confirm.
# Returns 2 when grim is missing, so "cannot check" stays distinct from "failed".
scanout_bytes() {
    local shot
    command -v grim >/dev/null || return 2
    shot="$(mktemp --suffix=.png)"
    if grim -o "$OUTPUT" "$shot" 2>/dev/null; then
        stat -c %s "$shot"
        rm -f "$shot"
        return 0
    fi
    rm -f "$shot"
    return 1
}

scanout_report() {
    local bytes
    bytes="$(scanout_bytes || echo 0)"
    if [ "$bytes" -gt 0 ]; then
        say "scanout  : ${bytes} bytes captured — the compositor is producing frames for it"
    fi
}

# Verified against live state only. The log is authoritative for diagnosis but
# lags by a cycle right after a commit, which is precisely when this runs.
output_live() {
    local rc=0
    [ "$(hypr_field '.disabled')" = "false" ] || return 1
    [ "$(hypr_field '.width')" -gt 0 ] || return 1
    scanout_bytes >/dev/null || rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]
}

# A disable/enable issued while the connector is still flapping gets swallowed
# by the next hotplug rescan, so this retries rather than firing once and
# declaring success.
recommit() {
    local spec attempt
    spec="$(monitor_spec)"
    say ""
    say "fixing   : re-committing as '$OUTPUT,$spec'"

    for attempt in $(seq 1 "$ATTEMPTS"); do
        hypr_monitor_apply "$OUTPUT" disable || say "         : warn — compositor rejected the disable"
        sleep 1.5
        hypr_monitor_apply "$OUTPUT" "$spec" || say "         : warn — compositor rejected '$spec'"
        sleep 2.5

        if output_live; then
            say "         : attempt $attempt/$ATTEMPTS ok — hyprland is driving $OUTPUT again"
            return 0
        fi
        say "         : attempt $attempt/$ATTEMPTS did not take, retrying"
    done
    return 1
}

############
### MAIN ###
############

collect
report

case "$VERDICT" in
    LIVE)
        scanout_report
        instability_note
        exit 0
        ;;
    NO_CONNECTOR)
        say ""
        say "This GPU has no connector named $OUTPUT. Available:"
        for d in /sys/class/drm/card*-*; do
            [ -r "$d/status" ] && say "  ${d##*/card?-}  $(cat "$d/status")"
        done
        exit 1
        ;;
    LINK_DOWN)
        say ""
        say "The kernel does not see a sink on $OUTPUT, so this is not a compositor problem."
        say "Check the cable, the port, and that the monitor is powered on, then re-run."
        exit 1
        ;;
    ABSENT)
        say ""
        say "$OUTPUT is connected at the kernel but absent from Hyprland's monitor list."
        say "Nothing to re-commit — restart Hyprland, or look for a 'monitor=$OUTPUT,disable' rule."
        exit 1
        ;;
esac

# DARK / PHANTOM: the sink is there and the kernel sees it, but the compositor
# either has the output down or is not scanning it out. Re-commit.
if [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "dry run — would re-commit as '$OUTPUT,$(monitor_spec)'"
    instability_note
    exit 1
fi

if recommit; then
    scanout_report
    instability_note
    toast "$OUTPUT is back" "Re-committed by monitor-doctor"
    exit 0
fi

say ""
say "Could not revive $OUTPUT in $ATTEMPTS attempts."
say "Re-run once the hotplug storm settles, or restart Hyprland."
toast -u critical "$OUTPUT still dark" "monitor-doctor could not re-commit it"
exit 1
