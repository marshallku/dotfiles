#!/usr/bin/env bash
# wait-for.sh — wait for external state with exponential backoff and print one final line.
#
#   wait-for.sh pr <number|url> (--checks | --merged | --approved) [--repo OWNER/NAME]
#   wait-for.sh run [--branch B] [--workflow W] [--sha S] [--repo OWNER/NAME]
#   wait-for.sh url <url> [--status CODE]            (default 200)
#   wait-for.sh cmd -- <command …>                   (until it exits 0)
#
# Common: --timeout SECS (default 600), --interval SECS (first wait, default 5; ×1.5 up to 60).
# Exit: 0 reached · 1 reached a failed terminal state (failing checks, failed run, closed PR)
#       · 124 timed out · 2 usage or tool error. A failed run prints the tail of its failed log.
#
# Requires bash ≥ 4, gh, curl, jq (Linux and macOS).

set -uo pipefail

TIMEOUT=600
INTERVAL=5
MAX_INTERVAL=60
LOG_TAIL=40

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1' "$0" >&2; exit 2; }
die() { echo "[wait-for] $*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found in PATH"; }

[[ $# -ge 1 ]] || usage
KIND="$1"; shift
POSITIONAL=()
MODE="" REPO="" BRANCH="" WORKFLOW="" SHA="" STATUS_WANT=200
COMMAND=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --checks|--merged|--approved) MODE="${1#--}"; shift ;;
        --repo) REPO="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --workflow) WORKFLOW="$2"; shift 2 ;;
        --sha) SHA="$2"; shift 2 ;;
        --status) STATUS_WANT="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --) shift; COMMAND=("$@"); break ;;
        -h|--help) usage ;;
        -*) die "unknown option: $1" ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
[[ "$TIMEOUT" =~ ^[0-9]+$ && "$INTERVAL" =~ ^[0-9]+$ ]] || die "--timeout/--interval take whole seconds"
REPO_ARGS=()
[[ -n "$REPO" ]] && REPO_ARGS=(--repo "$REPO")

# probe prints one status line and returns 0 (reached), 1 (failed terminal state) or 3 (not yet).
probe_pr() {
    local json state merged decision
    json=$(gh pr view "${POSITIONAL[0]}" "${REPO_ARGS[@]}" \
        --json state,mergedAt,reviewDecision,statusCheckRollup,url 2>&1) || { echo "gh: $json"; return 2; }
    state=$(jq -r '.state' <<< "$json")
    merged=$(jq -r '.mergedAt // empty' <<< "$json")
    decision=$(jq -r '.reviewDecision // empty' <<< "$json")
    case "$MODE" in
        merged)
            [[ -n "$merged" ]] && { echo "merged $(jq -r .url <<< "$json") at $merged"; return 0; }
            [[ "$state" == CLOSED ]] && { echo "closed without merge: $(jq -r .url <<< "$json")"; return 1; }
            echo "state $state"; return 3 ;;
        approved)
            [[ "$decision" == APPROVED ]] && { echo "approved: $(jq -r .url <<< "$json")"; return 0; }
            [[ "$decision" == CHANGES_REQUESTED ]] && { echo "changes requested: $(jq -r .url <<< "$json")"; return 1; }
            [[ "$state" != OPEN ]] && { echo "PR is $state"; return 1; }
            echo "review ${decision:-pending}"; return 3 ;;
        checks)
            # CheckRun: status/conclusion; StatusContext: state. Neutral and skipped count as passing.
            local summary
            summary=$(jq -r '
                [.statusCheckRollup[]? | {
                    name: (.name // .context // "?"),
                    done: ((.status // "COMPLETED") == "COMPLETED" and ((.state // "SUCCESS") | IN("PENDING", "EXPECTED") | not)),
                    ok: (((.conclusion // .state // "") | ascii_upcase) | IN("SUCCESS", "NEUTRAL", "SKIPPED"))
                }] as $c
                | "\($c | length)\t\([$c[] | select(.done | not)] | length)\t\([$c[] | select(.done and (.ok | not)) | .name] | join(", "))"
            ' <<< "$json")
            local total pending failed
            IFS=$'\t' read -r total pending failed <<< "$summary"
            if [[ "${total:-0}" -eq 0 ]]; then
                # A finished PR without checks will never get any; an open one may still.
                [[ "$state" != OPEN ]] && { echo "no checks; PR is $state"; return 0; }
                echo "no checks reported yet"; return 3
            fi
            [[ "$pending" -gt 0 ]] && { echo "$pending of $total checks pending"; return 3; }
            [[ -n "$failed" ]] && { echo "checks failed: $failed"; return 1; }
            echo "all $total checks passed: $(jq -r .url <<< "$json")"; return 0 ;;
        *) die "pr needs --checks, --merged or --approved" ;;
    esac
}

probe_run() {
    local args=(run list "${REPO_ARGS[@]}" --limit 1 --json databaseId,status,conclusion,headSha,workflowName,url)
    [[ -n "$BRANCH" ]] && args+=(--branch "$BRANCH")
    [[ -n "$WORKFLOW" ]] && args+=(--workflow "$WORKFLOW")
    [[ -n "$SHA" ]] && args+=(--commit "$SHA")
    local json
    json=$(gh "${args[@]}" 2>&1) || { echo "gh: $json"; return 2; }
    [[ "$(jq 'length' <<< "$json")" -eq 0 ]] && { echo "no run yet"; return 3; }
    local status conclusion name url
    status=$(jq -r '.[0].status' <<< "$json")
    conclusion=$(jq -r '.[0].conclusion // empty' <<< "$json")
    name=$(jq -r '.[0].workflowName' <<< "$json")
    url=$(jq -r '.[0].url' <<< "$json")
    [[ "$status" != completed ]] && { echo "$name $status"; return 3; }
    case "$conclusion" in
        success|neutral|skipped) echo "$name $conclusion: $url"; return 0 ;;
        *) echo "$name ${conclusion:-unknown}: $url"; return 1 ;;
    esac
}

probe_url() {
    local code
    code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${POSITIONAL[0]}" 2>/dev/null) || code="000"
    [[ "$code" == "$STATUS_WANT" ]] && { echo "${POSITIONAL[0]} → $code"; return 0; }
    echo "${POSITIONAL[0]} → $code"; return 3
}

probe_cmd() {
    "${COMMAND[@]}" > "$CMD_LOG" 2>&1 && { echo "command succeeded"; return 0; }
    echo "command exit $?"; return 3
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/wait-for.XXXXXX") || die "cannot create a temp dir"
trap 'rm -rf "${WORK:?}"' EXIT
CMD_LOG="$WORK/cmd.log"
: > "$CMD_LOG"

case "$KIND" in
    pr)
        need gh; need jq; [[ ${#POSITIONAL[@]} -eq 1 ]] || usage
        [[ -n "$MODE" ]] || die "pr needs --checks, --merged or --approved"
        PROBE=probe_pr ;;
    run) need gh; need jq; PROBE=probe_run ;;
    url) need curl; [[ ${#POSITIONAL[@]} -eq 1 ]] || usage; PROBE=probe_url ;;
    cmd) [[ ${#COMMAND[@]} -gt 0 ]] || usage; PROBE=probe_cmd ;;
    *) usage ;;
esac

# bounded SECONDS OUTFILE COMMAND… — run COMMAND (a probe function or a program) in its own
# process group with output to OUTFILE, killing the whole group at the deadline. A hung gh,
# curl or `cmd` child cannot outlive --timeout. Returns COMMAND's status, or 124 when killed.
bounded() {
    local limit=$1 out=$2 pid end
    shift 2
    set -m
    ( "$@" ) > "$out" 2>&1 &
    pid=$!
    set +m
    end=$(( $(date +%s) + limit ))
    while kill -0 "$pid" 2>/dev/null; do
        if (( $(date +%s) >= end )); then
            kill -TERM -- "-$pid" 2>/dev/null
            sleep 1
            kill -KILL -- "-$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 0.2
    done
    wait "$pid"
}

FAILED_LOG_SECONDS=30
START=$(date +%s)
WAIT=$INTERVAL
while :; do
    ELAPSED=$(( $(date +%s) - START ))
    REMAINING=$(( TIMEOUT - ELAPSED ))
    (( REMAINING < 1 )) && REMAINING=1
    bounded "$REMAINING" "$WORK/probe" "$PROBE"
    RC=$?
    LINE=$(tail -n 1 "$WORK/probe")
    ELAPSED=$(( $(date +%s) - START ))
    case "$RC" in
        0) echo "✓ $LINE (${ELAPSED}s)"; exit 0 ;;
        1)
            echo "✗ $LINE (${ELAPSED}s)"
            if [[ "$KIND" == run ]]; then
                id=$(sed -nE 's#.*/actions/runs/([0-9]+).*#\1#p' <<< "$LINE")
                if [[ -n "$id" ]]; then
                    bounded "$FAILED_LOG_SECONDS" "$WORK/log" gh run view "$id" "${REPO_ARGS[@]}" --log-failed
                    tail -n "$LOG_TAIL" "$WORK/log"
                fi
            fi
            exit 1 ;;
        2) echo "[wait-for] $LINE" >&2; exit 2 ;;
        124) LINE="still probing at the deadline" ;;
    esac
    if (( RC == 124 || ELAPSED >= TIMEOUT )); then
        echo "⏱ timed out after ${ELAPSED}s: $LINE"
        [[ "$KIND" == cmd ]] && tail -n "$LOG_TAIL" "$CMD_LOG"
        exit 124
    fi
    # Never sleep past the deadline: the last probe runs at it.
    NAP=$WAIT
    (( NAP > TIMEOUT - ELAPSED )) && NAP=$(( TIMEOUT - ELAPSED ))
    sleep "$NAP"
    WAIT=$(( WAIT * 3 / 2 ))
    (( WAIT > MAX_INTERVAL )) && WAIT=$MAX_INTERVAL
    (( WAIT < 1 )) && WAIT=1
done
