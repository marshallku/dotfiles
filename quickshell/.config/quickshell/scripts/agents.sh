#!/usr/bin/env bash
# Desktop widget collector: live Claude/Codex agents + recent attention events.
#
# Read-only consumer — no classification of its own. Three sources, each the
# owner of the agents it can see:
#   - comux panes: `comux list-agents --json` (status: working / ready /
#                  blocked / idle, plus what the agent is doing right now).
#   - tmux panes:  `tmx agents --json` (status from Claude's session file,
#                  pane capture as the codex fallback; also background codex
#                  jobs and the attention queue).
#   - everything else: ~/.claude/sessions/<pid>.json — Claude in a copad tab or
#                  a plain terminal. Status mapped exactly like tmx's
#                  resolve_status (busy/idle/waiting).
# A Claude session is attributed to a comux pane by its COPAD_MUX_PANE env
# (comux rows carry no pid), to a tmux pane by pid, and to a copad tab by
# COPAD_PANEL_ID — so each agent is listed once, where it actually runs.
#
# The attention queue is shown as an event list only; it is NOT used to
# derive state (notifications include idle reminders and are truncated).
#
# Output: one JSON object with independent sections, each {ok, error?, items}.
# A source that is simply not running (no comux server, no tmx) contributes
# nothing; a source that is running but fails marks the section ok:false, and
# the QML side keeps the last good items and renders them as stale.

set -u

now_ms=$(( $(date +%s%N) / 1000000 ))
sessions_dir="$HOME/.claude/sessions"
errors=()

# ── tmx (tmux) ─────────────────────────────────────────────────────────────
tmx_json="null"
if command -v tmx >/dev/null 2>&1; then
    out=$(timeout 5 tmx agents --json 2>/dev/null)
    if jq -e '.agents' >/dev/null 2>&1 <<<"$out"; then
        tmx_json=$out
    else
        errors+=("tmx agents failed")
    fi
fi

# ── comux ──────────────────────────────────────────────────────────────────
comux_json="null"
comux_sock="${COPAD_MUX_SOCK:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/copad-mux-$(id -un)/sock}"
if command -v comux >/dev/null 2>&1 && [[ -S "$comux_sock" ]]; then
    out=$(timeout 5 comux list-agents --json 2>/dev/null)
    if jq -e '.ok == true' >/dev/null 2>&1 <<<"$out"; then
        comux_json=$out
    else
        errors+=("comux list-agents failed")
    fi
fi

# ── Claude sessions: process identity ──────────────────────────────────────
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

# Where a live session runs, from its own environment (readable: same user).
session_env() {
    local environ mux="" panel=""
    environ=$(tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null)
    mux=$(sed -n 's/^COPAD_MUX_PANE=//p' <<<"$environ" | head -n1)
    panel=$(sed -n 's/^COPAD_PANEL_ID=//p' <<<"$environ" | head -n1)
    jq -n -c --arg mux "$mux" --arg panel "$panel" '{mux_token: $mux, copad_panel: $panel}'
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
        lines+=("$(jq -c --argjson env "$(session_env "$pid")" '. + $env' <<<"$row")")
    done
    (( ${#lines[@]} > 0 )) && sessions=$(printf '%s\n' "${lines[@]}" | jq -s -c '.')
fi

error=""
(( ${#errors[@]} > 0 )) && error=$(IFS='; '; echo "${errors[*]}")

jq -n -c \
    --argjson now "$now_ms" \
    --argjson sessions "$sessions" \
    --argjson tmx "$tmx_json" \
    --argjson comux "$comux_json" \
    --arg error "$error" '
    # Same mapping as tmx collector.rs resolve_status. Unknown → null → dropped.
    def session_status: {busy: "working", idle: "ready", waiting: "awaiting-decision"}[.status];
    # comux says "blocked" for what tmx calls "awaiting-decision".
    def comux_status: if . == "blocked" then "awaiting-decision" else . end;
    def basename: split("/") | last;

    ($sessions | map({key: (.pid | tostring), value: .}) | from_entries) as $by_pid
    | ($sessions | map(select(.mux_token != "")) | map({key: .mux_token, value: .}) | from_entries) as $by_token

    | ([($comux.agents // [])[]
        | (if .token != "" then $by_token[.token] else null end) as $s
        | {
            id: "comux:\(if .token != "" then .token else .terminal end)",
            kind: (if .tool == "claude" or .tool == "codex" then .tool else "custom" end),
            status: (.status | comux_status),
            name: ($s.name // .tool),
            repo: (if $s then ($s.cwd | basename) else .space end),
            location: "comux \(.space) · \(.title)",
            detail: .detail,
            pid: ($s.pid // null | if . then tostring else null end),
            since_ms: ($now - .for_secs * 1000)
          }
    ]) as $comux_agents

    | ([($tmx.agents // [])[]
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
            location: (if .pane then "tmux \(.pane.session):\(.pane.window).\(.pane.pane)" else "background" end),
            detail: null,
            pid: $pid,
            since_ms: ($s.statusUpdatedAt // null)
          }
    ]) as $tmux_agents

    | ([$comux_agents[], $tmux_agents[] | .pid | select(. != null)]) as $seen

    | ([$sessions[]
        | select((.pid | tostring) as $p | $seen | index($p) | not)
        # A comux pane whose server did not list it (sweep lag) is still a
        # comux agent — skip it rather than re-list it as a copad tab.
        | select(.mux_token == "" or $comux == null)
        | (session_status) as $st
        | select($st != null)
        | {
            id: "session:\(.pid)",
            kind: "claude",
            status: $st,
            name,
            repo: (.cwd | basename),
            location: (if .copad_panel != "" then "copad tab" elif .mux_token != "" then "comux" else "terminal" end),
            detail: null,
            pid: (.pid | tostring),
            since_ms: (.statusUpdatedAt // null)
          }
    ]) as $others

    | {
        generated_at: $now,
        agents: (
            if $error == "" then {ok: true, items: ($comux_agents + $tmux_agents + $others)}
            else {ok: false, error: $error, items: []}
            end
        ),
        attention: (
            if $tmx == null then {ok: true, items: []}
            else {ok: true, items: [($tmx.attention // [])[:5][] | {ts, kind, source, title, body}]}
            end
        )
      }
'
