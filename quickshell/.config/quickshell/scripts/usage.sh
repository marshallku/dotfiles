#!/usr/bin/env bash
# Desktop widget collector: Claude/Codex rate-limit windows + today's spend.
# Both come from `coctl usage` (local transcript scan + /api/oauth/usage), so
# this runs on a slow timer, never alongside the 3s agent poll.
#
# Output: {generated_at, limits:{ok,...}, today:{ok,...}} — independent sections.

set -u

coctl="$HOME/.local/bin/coctl"
now_ms=$(( $(date +%s%N) / 1000000 ))

limits=""
today=""
if [[ -x "$coctl" ]]; then
    limits=$(timeout 15 "$coctl" usage --limits --json 2>/dev/null) || limits=""
    today=$(timeout 15 "$coctl" usage --json 2>/dev/null) || today=""
fi

jq -n -c \
    --argjson now "$now_ms" \
    --arg limits "$limits" \
    --arg today "$today" '
    def parse: if . == "" then null else (try fromjson catch null) end;
    ($limits | parse) as $l
    | ($today | parse) as $t
    | {
        generated_at: $now,
        limits: (
            if $l == null then {ok: false, error: "coctl usage --limits failed"}
            else {
                ok: true,
                claude_5h: $l.claude.five_hour,
                claude_5h_reset: $l.claude.five_hour_reset,
                claude_week: $l.claude.seven_day,
                claude_week_reset: $l.claude.seven_day_reset,
                codex_week: $l.codex.weekly,
                codex_week_reset: $l.codex.weekly_reset
            }
            end
        ),
        today: (
            if $t == null then {ok: false, error: "coctl usage failed"}
            else {
                ok: true,
                claude_cost: $t.claude.cost,
                claude_tokens: $t.claude.subtotal_tokens,
                codex_tokens: $t.codex.subtotal_tokens
            }
            end
        )
      }
'
