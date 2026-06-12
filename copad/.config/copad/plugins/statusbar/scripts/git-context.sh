#!/usr/bin/env bash
# copad statusbar module: git branch + dirty for registered workspaces.
#
# SCOPE NOTE — this tracks the repos in workspaces.toml, NOT whatever repo
# the focused terminal sits in. A module's exec is routed through the
# DAEMON socket (statusbar.rs deliberately uses daemon_socket_path,
# skipping the per-GUI socket), and the focused-panel cwd
# (context.snapshot.active_cwd) is per-GUI state the daemon does not
# track — so "follow the focused terminal" is unreachable until copad
# grows daemon-side context tracking (roadmap item 5b.2). The git plugin
# already watches workspaces.toml repos daemon-side, so those render and
# update live (branch/checkout/worktree events re-drive the poll).
#
# Output: " main"  (single ws) or  " copad:main  api:feat*"  (multi),
# with a tooltip carrying branch + worktree count per workspace. Blank
# when no workspace is registered. coctl by absolute path (daemon PATH
# gotcha).
set -u

coctl="$HOME/.local/bin/coctl"
[[ -x "$coctl" ]] || exit 0

ws=$("$coctl" --json call git.list_workspaces 2>/dev/null) || exit 0
names=$(printf '%s' "$ws" | jq -r '(.workspaces // [])[].name' 2>/dev/null)
[[ -n "$names" ]] || exit 0

multi=0
(( $(printf '%s\n' "$names" | grep -c .) > 1 )) && multi=1

text=""
tip=""
while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    params=$(jq -cn --arg n "$name" '{workspace: $n}') || continue
    st=$("$coctl" --json call git.status --params "$params" 2>/dev/null) || continue
    branch=$(printf '%s' "$st" | jq -r '.branch // empty' 2>/dev/null)
    [[ -n "$branch" ]] || continue
    dirty=$(printf '%s' "$st" | jq -r 'if .dirty then "*" else "" end' 2>/dev/null)
    wt=$(printf '%s' "$ws" | jq -r --arg n "$name" \
        '(.workspaces // [])[] | select(.name==$n) | .worktree_count // 0' 2>/dev/null)

    if (( multi )); then
        seg="${name}:${branch}${dirty}"
    else
        seg="${branch}${dirty}"
    fi
    text="${text:+$text  }${seg}"
    tip="${tip:+$tip · }${name} ${branch}${dirty} (${wt} worktrees)"
done <<< "$names"

[[ -n "$text" ]] || exit 0

# Build output JSON with jq so config-/branch-derived names containing
# quotes or backslashes can't break the envelope. U+E0A0 powerline branch
# glyph + trailing space (overdraw guard) baked into the text field.
jq -cn --arg t " $text " --arg tip "$tip" '{text: $t, tooltip: $tip}'
