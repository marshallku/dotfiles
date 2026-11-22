#!/usr/bin/env bash
# @hook-event: UserPromptSubmit
# UserPromptSubmit hook — when a short prompt is the natural-language form of an existing skill
# ("PR 올려줘", "티켓 따고", "정리해"), name the skill in additionalContext so the agent runs it
# instead of improvising the steps.
#
# Why: on the work Mac ship-pr was invoked by slash 3 times and by natural language 55 times; after
# "PR 올려줘" the skill ran 17 of 40 times and a raw `gh pr create` ran 17 times, which skipped the
# skill's evidence step and produced 28 follow-up "스크린샷도 넣어줘" prompts. /ticket ran 21 of 29
# times from natural language, /cleanup 1 of 8.
#
# Routes are private and per machine (most of these skills are work-only):
#   ~/.claude/skill-routes — one route per line: <ERE, case-insensitive><TAB><skill name>
#   e.g.   (^|[[:space:]])PR[[:space:]]*(올려|만들어)	ship-pr
# Only prompts up to SKILL_ROUTE_MAX_CHARS (default 40) are routed: a long prompt is a task, not a
# lifecycle command. Slash commands are left alone. The first matching route wins. A route naming
# a skill that is not installed as a personal or project skill is skipped (plugin skills are not
# routed). Never blocks. Opt-out: ~/.claude/state/skill-route-disabled

set -uo pipefail

. "$(dirname "$0")/_lib.sh"

log() { hook_log skill-route "$@"; }

ROUTES="${SKILL_ROUTES_FILE:-$HOME/.claude/skill-routes}"
MAX_CHARS="${SKILL_ROUTE_MAX_CHARS:-40}"
case "$MAX_CHARS" in ''|*[!0-9]*) MAX_CHARS=40 ;; esac

INPUT=$(cat)
if [ -f "$HOME/.claude/state/skill-route-disabled" ]; then log "skip: disabled"; echo '{}'; exit 0; fi
if [ ! -f "$ROUTES" ]; then log "skip: no routes file"; echo '{}'; exit 0; fi

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
# The Codex bridge (scripts/codex-harness/bridge.py) runs shared hooks with this variable set.
RUNTIME=claude
[ "${HARNESS_REQUIRED_REVIEWER:-}" = claude ] && RUNTIME=codex
TRIMMED=$(printf '%s' "$PROMPT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if [ -z "$TRIMMED" ]; then log "skip: empty prompt"; echo '{}'; exit 0; fi
case "$TRIMMED" in /*) log "skip: slash command"; echo '{}'; exit 0 ;; esac
# Character count, not bytes: Korean is three bytes a character in UTF-8.
LENGTH=$(printf '%s' "$TRIMMED" | python3 -I -c 'import sys; print(len(sys.stdin.read()))' 2>/dev/null || echo 9999)
if [ "$LENGTH" -gt "$MAX_CHARS" ]; then log "skip: long prompt ($LENGTH chars)"; echo '{}'; exit 0; fi

skill_installed() {
    local name="$1" dir
    # Personal and project skills of the runtime receiving this prompt. Plugin skills are not
    # routed: a cached plugin directory says nothing about whether it is enabled.
    case "$name" in */*|*:*|.*) return 1 ;; esac
    local dirs
    if [ "$RUNTIME" = codex ]; then
        dirs=("$HOME/.agents/skills/$name" "$HOME/.codex/skills/$name" "${CWD:-$PWD}/.agents/skills/$name")
    else
        dirs=("$HOME/.claude/skills/$name" "${CWD:-$PWD}/.claude/skills/$name")
    fi
    for dir in "${dirs[@]}"; do
        [ -f "$dir/SKILL.md" ] && return 0
    done
    return 1
}

SKILL=""
# `|| [ -n "$pattern" ]` keeps a last line without a trailing newline.
while IFS=$'\t' read -r pattern name _ || [ -n "$pattern" ]; do
    case "$pattern" in ''|'#'*) continue ;; esac
    [ -n "$name" ] || continue
    if grep -qiE -- "$pattern" <<< "$TRIMMED" 2>/dev/null; then
        if skill_installed "$name"; then SKILL="$name"; break; fi
        log "skip route: $name is not installed"
    fi
done < "$ROUTES"

if [ -z "$SKILL" ]; then log "skip: no route matched"; echo '{}'; exit 0; fi

log "ROUTE: $SKILL"
hook_event skill-route route skill="$SKILL"
if [ "$RUNTIME" = codex ]; then HOW="invoke \`\$$SKILL\` (read its SKILL.md)"; else HOW="invoke it with the Skill tool (\`$SKILL\`)"; fi
CONTEXT="[skill-route] This short prompt is the natural-language form of the \`$SKILL\` skill: $HOW and follow its steps instead of doing them by hand — the hand-made version skipped steps the skill enforces. If the prompt clearly means something else, ignore this note."
jq -n --arg ctx "$CONTEXT" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'
