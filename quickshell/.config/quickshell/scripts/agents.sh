#!/usr/bin/env bash
# Desktop widget collector: live Claude/Codex agents + recent attention events.
#
# Read-only consumer — no classification of its own:
#   - tmux panes:   `tmx agents --json` (the ecosystem's source of truth; its
#                   status comes from Claude's own session file, with pane
#                   capture as the codex fallback).
#   - outside tmux: ~/.claude/sessions/<pid>.json for Claude processes tmx
#                   cannot see (copad tabs, plain terminals). Status is mapped
#                   exactly like tmx's resolve_status (busy/idle/waiting).
#   - attention:    tmx's `attention[]`, shown as an event list only. It is
#                   NOT used to derive state — notifications include idle
#                   reminders and the queue is truncated.
#
# Output: one JSON object with independent sections, each {ok, error?, items}.
# A failing source marks its own section ok:false; the QML side keeps the
# last good items and renders them as stale.

set -u

now_ms=$(( $(date +%s%N) / 1000000 ))
sessions_dir="$HOME/.claude/sessions"

tmx_json=""
tmx_error=""
if command -v tmx >/dev/null 2>&1; then
    tmx_json=$(timeout 5 tmx agents --json 2>/dev/null) || tmx_error="tmx agents failed"
    if [[ -z "$tmx_error" ]] && ! jq -e '.agents' >/dev/null 2>&1 <<<"$tmx_json"; then
        tmx_error="tmx agents: malformed json"
        tmx_json=""
    fi
else
    tmx_error="tmx not installed"
fi

# ── Process identity ───────────────────────────────────────────────────────
# A session file outlives its process on crash, and the pid can be reused.
# Live iff: same machine + pid namespace (pidDomain), same start tick
# (procStart == /proc/<pid>/stat field 22), started after this boot (a stale
# file from a previous boot can collide on pid + tick), and not a zombie.
machine_id=$(cat /etc/machine-id 2>/dev/null)
pid_ns=$(readlink /proc/self/ns/pid 2>/dev/null)
pid_domain="linux:${machine_id}:${pid_ns}"
boot_ms=$(( $(awk '/^btime/ {print $2}' /proc/stat) * 1000 ))

session_live() {
    local pid=$1 domain=$2 proc_start=$3 started_at=$4 stat rest state tick

    [[ -n "$proc_start" && "$domain" == "$pid_domain" ]] || return 1
    (( started_at >= boot_ms )) || return 1
    stat=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
    # comm (field 2) may contain spaces/parens — split after the last ')'.
    rest=${stat##*) }
    read -r state _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ tick _ <<<"$rest"
    [[ "$state" != "Z" && "$state" != "X" ]] || return 1
    [[ "$tick" == "$proc_start" ]]
}

sessions="[]"
if [[ -d "$sessions_dir" ]]; then
    lines=()
    for f in "$sessions_dir"/*.json; do
        [[ -e "$f" ]] || break
        row=$(jq -c '{pid, pidDomain, procStart, startedAt, sessionId, name, cwd, status, statusUpdatedAt}' "$f" 2>/dev/null) || continue
        IFS=$'\t' read -r pid domain proc_start started_at < <(
            jq -r '[.pid, .pidDomain // "", .procStart // "", .startedAt // 0] | @tsv' <<<"$row")
        session_live "$pid" "$domain" "$proc_start" "$started_at" || continue
        lines+=("$row")
    done
    (( ${#lines[@]} > 0 )) && sessions=$(printf '%s\n' "${lines[@]}" | jq -s -c '.')
fi

jq -n -c \
    --argjson now "$now_ms" \
    --argjson sessions "$sessions" \
    --arg tmx "$tmx_json" \
    --arg tmx_error "$tmx_error" '
    ($tmx | if . == "" then null else fromjson end) as $t
    | ($sessions | map({key: (.pid | tostring), value: .}) | from_entries) as $by_pid

    # Same mapping as tmx collector.rs resolve_status. Unknown → null → dropped.
    | def session_status: {busy: "working", idle: "ready", waiting: "awaiting-decision"}[.status];

    ([($t.agents // [])[]
        | select(.kind == "claude" or .kind == "codex" or .kind == "custom")
        # Background codex jobs carry "running • 10s ago", not "pid N" —
        # default to null rather than letting an empty capture drop the agent.
        | (first(.extra | capture("^pid (?<p>[0-9]+)$") | .p) // null) as $pid
        | (if $pid then $by_pid[$pid] else null end) as $s
        | {
            id,
            kind,
            status,
            name: ($s.name // .repo_name),
            repo: .repo_name,
            cwd,
            pid: ($pid // null),
            location: (if .pane then "tmux \(.pane.session):\(.pane.window).\(.pane.pane)" else "background" end),
            tmux_target: (if .pane then "\(.pane.session):\(.pane.window).\(.pane.pane)" else null end),
            since_ms: ($s.statusUpdatedAt // null)
          }
    ]) as $tmux_agents
    | ($tmux_agents | map(.pid) | map(select(. != null))) as $seen

    | ([$sessions[]
        | select((.pid | tostring) as $p | $seen | index($p) | not)
        | (session_status) as $st
        | select($st != null)
        | {
            id: "session:\(.pid)",
            kind: "claude",
            status: $st,
            name,
            repo: (.cwd | split("/") | last),
            cwd,
            pid: (.pid | tostring),
            location: "outside tmux",
            tmux_target: null,
            since_ms: (.statusUpdatedAt // null)
          }
    ]) as $outside

    | {
        generated_at: $now,
        agents: (
            if $t == null and ($sessions | length) == 0 then
                {ok: false, error: $tmx_error, items: []}
            else
                {ok: ($tmx_error == ""), error: (if $tmx_error == "" then null else $tmx_error end),
                 items: ($tmux_agents + $outside)}
            end
        ),
        attention: (
            if $t == null then {ok: false, error: $tmx_error, items: []}
            else {ok: true, items: [($t.attention // [])[:5][] | {ts, kind, source, title, body}]}
            end
        )
      }
'
