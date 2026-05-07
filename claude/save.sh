#!/bin/bash

# Commit message prefix conventions (suggestive, not enforced):
#   Verb-style:   Add, Remove, Move, Improve, Pass, Verify, Modify, Allow, Bump, Fix, Implement, Make, Update, Use
#   Conventional: feat:, fix:, test:, chore:, doc:
# Any non-empty message is accepted — pick one if it fits, or skip the prefix.

if [[ -z "$1" ]]; then
    echo "Usage: $0 <commit message>"
    exit 1
fi

msg="$1"

# Reject AI co-author trailers — defense-in-depth alongside the Claude
# commit-policy-gate hook and the global git commit-msg hook.
if printf '%s' "$msg" | grep -qiE 'Co-Authored-By:.*(Claude|Anthropic|noreply@anthropic\.com|GPT-|Codex|ChatGPT|OpenAI)'; then
    echo "Error: commit message contains an AI co-author trailer." >&2
    echo "       Remove the 'Co-Authored-By: ...' line and try again." >&2
    exit 1
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ -z "$branch" ]]; then
    echo "Error: not on a branch"
    exit 1
fi

# Refuse to commit cross-review / codex-plan brief files left in the
# working tree. They belong in /tmp.
toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
if [[ -z "$toplevel" ]]; then
    echo "Error: not inside a git repository" >&2
    exit 1
fi

bad_brief=""
while IFS= read -r f; do
    case "$f" in
        BRIEF*.md|*/BRIEF*.md|brief.md|*/brief.md|codex-brief*|*/codex-brief*|cross-review-brief*|*/cross-review-brief*)
            bad_brief="${bad_brief}${bad_brief:+, }$f"
            ;;
    esac
done < <(cd "$toplevel" && git ls-files --others --exclude-standard --modified --cached 2>/dev/null)

if [[ -n "$bad_brief" ]]; then
    echo "Error: brief / codex-brief files in working tree: $bad_brief" >&2
    echo "       Move them to /tmp first:  mv <file> /tmp/" >&2
    echo "       (or  git rm --cached <file>  if already tracked)" >&2
    exit 1
fi

git add -A && git commit -m "$msg" && git push -u origin "$branch"
