#!/usr/bin/env bash
# copad statusbar module: in-flight pilot (agent queue) jobs.
#
# pilot.status returns { counts: {<status>: n}, gate, active, goals[] }.
# Non-terminal statuses (queued/spawning/sending/running/awaiting_gate)
# are "in flight"; awaiting_gate additionally means a job is paused
# waiting for the user (answer/approve), surfaced with ⏸.
#
# coctl by absolute path (daemon PATH gotcha). Blank when nothing is in
# flight so the slot stays clean between agent runs.
set -u

coctl="$HOME/.local/bin/coctl"
[[ -x "$coctl" ]] || exit 0

json=$("$coctl" --json call pilot.status 2>/dev/null) || exit 0

active=$(printf '%s' "$json" | jq '
    (.counts // {}) as $c
    | [$c.queued, $c.spawning, $c.sending, $c.running, $c.awaiting_gate]
    | map(. // 0) | add' 2>/dev/null)
gate=$(printf '%s' "$json" | jq -r '.counts.awaiting_gate // 0' 2>/dev/null)

[[ -z "$active" || "$active" == "0" ]] && exit 0

# U+F135 rocket glyph + trailing space.
if [[ -n "$gate" && "$gate" != "0" ]]; then
    printf '{"text":" %s ⏸%s ","tooltip":"%s pilot jobs in flight · %s awaiting gate"}\n' \
        "$active" "$gate" "$active" "$gate"
else
    printf '{"text":" %s ","tooltip":"%s pilot jobs in flight"}\n' "$active" "$active"
fi
