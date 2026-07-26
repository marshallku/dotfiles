#!/usr/bin/env bash
# PreCompact hook: preserve re-injectable state across a context compaction.
#
# Why: an autonomous loop (/goal, /loop) has its work-unit contract injected by
# contract-inject.sh only on the prompt that starts it. A mid-session
# auto-compaction drops that (and the rest of the live context) and nothing
# re-injects it. This hook snapshots the git state + a standing-gate reminder to
# a session-scoped file that session-start.sh re-injects on the following
# SessionStart(source=compact). It also refreshes handoffs/latest.md so a Stop
# is not required to capture the current tree.
#
# Non-blocking: always emits {} and exits 0; every git call is guarded.

set -euo pipefail

. "$(dirname "$0")/_lib.sh"

INPUT=$(cat 2>/dev/null || echo '{}')
SESSION=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || echo "")

STATE_DIR="$HOME/.claude/state"
HANDOFF_DIR="$HOME/.claude/handoffs"
mkdir -p "$STATE_DIR" "$HANDOFF_DIR" 2>/dev/null || true

TS=$(date +"%Y-%m-%d %H:%M")

# Build a git snapshot block if cwd is a work tree (mirrors auto-handoff.sh).
GIT_BLOCK="(no git repo detected in cwd)"
if [ -n "$CWD" ] && git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "detached")
    DIFF_STAT=$(git -C "$CWD" diff --stat 2>/dev/null || true)
    STAGED_STAT=$(git -C "$CWD" diff --cached --stat 2>/dev/null || true)
    RECENT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null || true)
    REPO_NAME=$(basename "$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo repo)")
    GIT_BLOCK="- **Repo:** $REPO_NAME
- **Branch:** $BRANCH
- **Directory:** $CWD

### Recent Commits
\`\`\`
$RECENT_LOG
\`\`\`

### Unstaged Changes
\`\`\`
${DIFF_STAT:-No unstaged changes}
\`\`\`

### Staged Changes
\`\`\`
${STAGED_STAT:-No staged changes}
\`\`\`"

    # Also refresh the handoff so the next non-compact session sees current state.
    cat > "$HANDOFF_DIR/latest.md" 2>/dev/null << EOF || true
# Session Handoff (pre-compaction snapshot)

- **Time:** $TS
$GIT_BLOCK
EOF
fi

# Atomic write of the re-inject snapshot (mktemp in the same dir + mv). Kept until
# GC'd by session-start.sh — deliberately not consumed-and-deleted so a crash
# between compaction and the next SessionStart still leaves the recovery artifact.
TMP=$(mktemp "$STATE_DIR/.compact-reinject-${SESSION}.XXXXXX" 2>/dev/null) || { echo '{}'; exit 0; }
# Promote the temp to the real snapshot ONLY on a fully successful write. A
# partial/failed heredoc (e.g. disk full) must not clobber an existing good
# snapshot, so mv runs only in the `then` branch; otherwise drop the temp.
if cat > "$TMP" << EOF
## Context Compacted ($TS)

The conversation was just compacted; earlier turns may be gone. If you were
mid-task, resume from the git state below — do not restart work already
reflected here.

$GIT_BLOCK

### Standing work-unit gate
If you were driving an autonomous loop or a non-trivial change, the gate still
applies per work-unit — you do not need the user to restate it:
plan (if non-trivial) -> codex review of plan -> implement -> unit test ->
e2e (if applicable) -> codex cross-review -> ~/save.sh (never raw git).
EOF
then
    mv -f "$TMP" "$STATE_DIR/compact-reinject-${SESSION}.md" 2>/dev/null || true
else
    rm -f "$TMP" 2>/dev/null || true
fi

echo '{}'
