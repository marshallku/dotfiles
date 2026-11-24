#!/usr/bin/env bash
# Claude Code status line. A refresh spawns one jq; the transcript is rescanned at most every
# RECAP_INTERVAL seconds, from where the previous scan stopped, so its size never matters.

C_RESET=$'\e[0m'
C_DIM=$'\e[2m'
C_CYAN=$'\e[36m'
C_GREEN=$'\e[32m'
C_YELLOW=$'\e[33m'
C_RED=$'\e[31m'
C_MAGENTA=$'\e[35m'
C_BLUE=$'\e[34m'

BAR_W=15
RECAP_MAX=140
RECAP_INTERVAL=20
# Re-read this much before the previous offset so a record cut mid-write is seen whole next time.
SCAN_OVERLAP=65536
# The latest title and recap sit near the end; a first scan of a 100MB+ transcript reads only this tail.
SCAN_WINDOW=8388608
STATE_DIR="${TMPDIR:-/tmp}"
STATE_DIR="${STATE_DIR%/}/claude-statusline-${UID}"

IFS=$'\x1f' read -r MODEL DIR PCT COST DURATION_MS FIVE_H SEVEN_D LINES_ADD LINES_DEL TRANSCRIPT < <(
    jq -r '
        [
            .model.display_name // "",
            .workspace.current_dir // .cwd // "",
            (.context_window.used_percentage // 0 | floor),
            (.cost.total_cost_usd // 0),
            (.cost.total_duration_ms // 0 | floor),
            (.rate_limits.five_hour.used_percentage // ""),
            (.rate_limits.seven_day.used_percentage // ""),
            (.cost.total_lines_added // 0),
            (.cost.total_lines_removed // 0),
            .transcript_path // ""
        ] | map(tostring) | join("\u001f")
    ' 2>/dev/null
)

is_int() { [[ $1 =~ ^[0-9]+$ ]]; }
for v in PCT DURATION_MS LINES_ADD LINES_DEL; do is_int "${!v}" || printf -v "$v" 0; done
[[ $COST =~ ^[0-9.eE+-]+$ ]] || COST=0
for v in FIVE_H SEVEN_D; do
    [ -n "${!v}" ] && printf -v "$v" '%.0f' "${!v}" 2>/dev/null && is_int "${!v}" || printf -v "$v" ''
done

# threshold_color <var> <value> <red-at> <yellow-at>: sets <var> to the color for <value>.
threshold_color() {
    if [ "$2" -ge "$3" ]; then printf -v "$1" '%s' "$C_RED"
    elif [ "$2" -ge "$4" ]; then printf -v "$1" '%s' "$C_YELLOW"
    else printf -v "$1" '%s' "$C_GREEN"; fi
}

# Sets BRANCH (short sha when detached) and LINKED_WT=1 inside a linked worktree, reading
# .git and HEAD directly so no git process runs.
read_git_head() {
    local d=$1 gitdir line
    while :; do
        if [ -d "$d/.git" ]; then
            gitdir=$d/.git
            break
        fi
        if [ -f "$d/.git" ]; then
            read -r line < "$d/.git" || return 1
            gitdir=${line#gitdir: }
            [[ $gitdir == /* ]] || gitdir=$d/$gitdir
            [[ $gitdir == */worktrees/* ]] && LINKED_WT=1
            break
        fi
        [[ $d == */* ]] || return 1
        d=${d%/*}
    done
    read -r line < "$gitdir/HEAD" || return 1
    case $line in
        "ref: refs/heads/"*) BRANCH=${line#ref: refs/heads/} ;;
        *) BRANCH=${line:0:7} ;;
    esac
}

# Loads TITLE and RECAP for the transcript in $1 from the per-transcript cache, scanning only
# the bytes appended since the last scan once RECAP_INTERVAL has passed.
load_recap() {
    local transcript=$1 cache now checked=0 offset=0 size start out
    cache=$STATE_DIR/${transcript##*/}
    if [ -f "$cache" ] && [ -O "$cache" ] && [ ! -L "$cache" ]; then
        { read -r checked offset; read -r TITLE; read -r RECAP; } < "$cache"
    fi
    is_int "$checked" || checked=0
    is_int "$offset" || offset=0
    if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 402 )); then
        printf -v now '%(%s)T' -1
    else
        now=$(date +%s)
    fi
    (( now - checked < RECAP_INTERVAL )) && return 0

    size=$(wc -c < "$transcript") || return 0
    size=$(( size ))
    if (( size < offset )); then
        offset=0 TITLE='' RECAP=''
    fi
    if (( size > offset )); then
        start=$(( offset > SCAN_OVERLAP ? offset - SCAN_OVERLAP : 0 ))
        (( offset == 0 && size > SCAN_WINDOW )) && start=$(( size - SCAN_WINDOW ))
        out=$(tail -c +"$(( start + 1 ))" "$transcript" \
            | LC_ALL=C grep -F -e '"type":"ai-title"' -e '"subtype":"away_summary"' \
            | jq -nrR --arg title "$TITLE" --arg recap "$RECAP" '
                def oneline: gsub("[\r\n]+"; " ");
                reduce (inputs | fromjson? | objects) as $r ({title: $title, recap: $recap};
                    if $r.type == "ai-title" and ($r.aiTitle | type) == "string" then
                        .title = $r.aiTitle
                    elif $r.subtype == "away_summary" and ($r.content | type) == "string" then
                        .recap = ($r.content | sub(" *\\(disable recaps in /config\\)\\s*$"; ""))
                    else . end)
                | (.title | oneline), (.recap | oneline)
            ')
        if [ -n "$out" ]; then
            { read -r TITLE; read -r RECAP; } <<< "$out"
        fi
        offset=$size
    fi

    [ -d "$STATE_DIR" ] || mkdir -m 700 "$STATE_DIR" 2>/dev/null
    [ -d "$STATE_DIR" ] && [ ! -L "$STATE_DIR" ] && [ -O "$STATE_DIR" ] || return 0
    [ -L "$cache" ] && return 0
    printf '%s %s\n%s\n%s\n' "$now" "$offset" "$TITLE" "$RECAP" > "$cache" 2>/dev/null
}

# --- Line 1: model + dir + branch + lines changed ---
LINE1="${C_CYAN}${MODEL}${C_RESET} ${C_DIM}${DIR##*/}${C_RESET}"
BRANCH='' LINKED_WT=''
if [ -n "$DIR" ] && read_git_head "$DIR"; then
    LINE1="${LINE1} ${C_MAGENTA}${BRANCH}${C_RESET}"
    [ -n "$LINKED_WT" ] && LINE1="${LINE1} ${C_DIM}(worktree)${C_RESET}"
fi
if [ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]; then
    LINE1="${LINE1} ${C_DIM}|${C_RESET} ${C_GREEN}+${LINES_ADD}${C_RESET}${C_RED}-${LINES_DEL}${C_RESET}"
fi
printf '%s\n' "$LINE1"

# --- Line 2: context bar + cost + duration + rate limits ---
(( PCT > 100 )) && PCT=100
FILLED=$((PCT * BAR_W / 100))
EMPTY=$((BAR_W - FILLED))
BAR=''
[ "$FILLED" -gt 0 ] && printf -v F "%${FILLED}s" '' && BAR="${F// /━}"
[ "$EMPTY" -gt 0 ] && printf -v E "%${EMPTY}s" '' && BAR="${BAR}${E// /╌}"

SECS=$((DURATION_MS / 1000))
if [ "$SECS" -ge 3600 ]; then DUR="$((SECS / 3600))h$((SECS % 3600 / 60))m"
elif [ "$SECS" -ge 60 ]; then DUR="$((SECS / 60))m$((SECS % 60))s"
else DUR="${SECS}s"; fi

printf -v COST_FMT '$%.2f' "$COST" 2>/dev/null || COST_FMT='$0.00'

threshold_color BAR_C "$PCT" 90 70
LINE2="${BAR_C}${BAR}${C_RESET} ${PCT}% ${C_DIM}|${C_RESET} ${C_YELLOW}${COST_FMT}${C_RESET}"
LINE2="${LINE2} ${C_DIM}|${C_RESET} ${C_BLUE}${DUR}${C_RESET}"
RATE_INFO=''
if is_int "$FIVE_H"; then
    threshold_color RATE_C "$FIVE_H" 80 50
    RATE_INFO="${C_DIM}5h${C_RESET}${RATE_C}${FIVE_H}%${C_RESET}"
fi
if is_int "$SEVEN_D"; then
    threshold_color RATE_C "$SEVEN_D" 80 50
    RATE_INFO="${RATE_INFO:+$RATE_INFO }${C_DIM}7d${C_RESET}${RATE_C}${SEVEN_D}%${C_RESET}"
fi
[ -n "$RATE_INFO" ] && LINE2="${LINE2} ${C_DIM}|${C_RESET} ${RATE_INFO}"
printf '%s\n' "$LINE2"

# --- Line 3: session title + latest recap, which Claude Code shows inline only once ---
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
TITLE='' RECAP=''
load_recap "$TRANSCRIPT"
[ -z "$TITLE" ] && [ -z "$RECAP" ] && exit 0

[ "${#RECAP}" -gt "$RECAP_MAX" ] && RECAP="${RECAP:0:$RECAP_MAX}…"
LINE3="${C_CYAN}◆${C_RESET}"
[ -n "$TITLE" ] && LINE3="${LINE3} ${TITLE}"
[ -n "$RECAP" ] && LINE3="${LINE3} ${C_DIM}— ${RECAP}${C_RESET}"
printf '%s\n' "$LINE3"
