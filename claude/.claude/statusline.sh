#!/usr/bin/env bash
. "$(dirname "$0")/hooks/_lib.sh"
input=$(cat)

# --- Extract fields ---
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
FIVE_H=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
SEVEN_D=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
LINES_ADD=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_DEL=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# --- Colors ---
C_RESET='\033[0m'
C_DIM='\033[2m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_MAGENTA='\033[35m'
C_BLUE='\033[34m'

# --- Context bar (15-wide, color by threshold) ---
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$C_RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$C_YELLOW"
else BAR_COLOR="$C_GREEN"; fi

BAR_W=15
FILLED=$((PCT * BAR_W / 100))
EMPTY=$((BAR_W - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v F "%${FILLED}s" && BAR="${F// /━}"
[ "$EMPTY" -gt 0 ] && printf -v E "%${EMPTY}s" && BAR="${BAR}${E// /╌}"

# --- Duration ---
SECS=$((DURATION_MS / 1000))
if [ "$SECS" -ge 3600 ]; then
    DUR="$((SECS / 3600))h$((SECS % 3600 / 60))m"
elif [ "$SECS" -ge 60 ]; then
    DUR="$((SECS / 60))m$((SECS % 60))s"
else
    DUR="${SECS}s"
fi

# --- Cost formatting ---
COST_FMT=$(printf '$%.2f' "$COST")

# --- Git (cached) ---
CACHE_FILE="/tmp/claude-statusline-git-$$"
# Use a stable cache key based on project dir
CACHE_KEY="/tmp/claude-statusline-git-$(printf '%s' "$DIR" | portable_md5)"
CACHE_MAX=5

cache_stale() {
    [ ! -f "$CACHE_KEY" ] || \
    [ $(($(date +%s) - $(portable_mtime "$CACHE_KEY"))) -gt $CACHE_MAX ]
}

GIT_INFO=""
if cache_stale; then
    if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
        BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
        STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
        MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
        UNTRACKED=$(git -C "$DIR" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        echo "$BRANCH|$STAGED|$MODIFIED|$UNTRACKED" > "$CACHE_KEY"
    else
        echo "|||" > "$CACHE_KEY"
    fi
fi

IFS='|' read -r BRANCH STAGED MODIFIED UNTRACKED < "$CACHE_KEY"

if [ -n "$BRANCH" ]; then
    GIT_INFO=" ${C_MAGENTA}${BRANCH}${C_RESET}"
    [ "$STAGED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${C_GREEN}+${STAGED}${C_RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${C_YELLOW}~${MODIFIED}${C_RESET}"
    [ "$UNTRACKED" -gt 0 ] && GIT_INFO="${GIT_INFO} ${C_RED}?${UNTRACKED}${C_RESET}"
fi

# --- Rate limits ---
RATE_INFO=""
if [ -n "$FIVE_H" ]; then
    FIVE_H_INT=$(printf '%.0f' "$FIVE_H")
    if [ "$FIVE_H_INT" -ge 80 ]; then RATE_C="$C_RED"
    elif [ "$FIVE_H_INT" -ge 50 ]; then RATE_C="$C_YELLOW"
    else RATE_C="$C_GREEN"; fi
    RATE_INFO="${C_DIM}5h${C_RESET}${RATE_C}${FIVE_H_INT}%${C_RESET}"
fi
if [ -n "$SEVEN_D" ]; then
    SEVEN_D_INT=$(printf '%.0f' "$SEVEN_D")
    if [ "$SEVEN_D_INT" -ge 80 ]; then RATE_C="$C_RED"
    elif [ "$SEVEN_D_INT" -ge 50 ]; then RATE_C="$C_YELLOW"
    else RATE_C="$C_GREEN"; fi
    RATE_INFO="${RATE_INFO} ${C_DIM}7d${C_RESET}${RATE_C}${SEVEN_D_INT}%${C_RESET}"
fi

# --- Lines changed ---
DIFF_INFO=""
if [ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]; then
    DIFF_INFO=" ${C_DIM}|${C_RESET} ${C_GREEN}+${LINES_ADD}${C_RESET}${C_RED}-${LINES_DEL}${C_RESET}"
fi

# --- Line 1: model + dir + git ---
printf '%b' "${C_CYAN}${MODEL}${C_RESET} ${C_DIM}${DIR##*/}${C_RESET}${GIT_INFO}${DIFF_INFO}\n"

# --- Line 2: context bar + cost + duration + rate limits ---
LINE2="${BAR_COLOR}${BAR}${C_RESET} ${PCT}% ${C_DIM}|${C_RESET} ${C_YELLOW}${COST_FMT}${C_RESET} ${C_DIM}|${C_RESET} ${C_BLUE}${DUR}${C_RESET}"
[ -n "$RATE_INFO" ] && LINE2="${LINE2} ${C_DIM}|${C_RESET} ${RATE_INFO}"

printf '%b' "${LINE2}\n"
