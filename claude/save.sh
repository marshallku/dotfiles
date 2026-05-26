#!/bin/bash

# Commit message prefix conventions (ENFORCED — see style check below):
#   Verb-style:   Add, Remove, Move, Improve, Pass, Verify, Modify, Allow, Bump, Fix, Implement, Make, Update, Use
#   Conventional: feat:, fix:, test:, chore:, doc:
# The subject line must start with one of the above. Mismatches are rejected.

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

# Enforce commit subject style. Either verb-style (capitalized imperative from
# the documented list) or conventional prefix (lowercase type + colon). Both
# require a space/content after, so single-word messages like "Add" fail too.
subject=$(printf '%s' "$msg" | head -n1)
verb_re='^(Add|Remove|Move|Improve|Pass|Verify|Modify|Allow|Bump|Fix|Implement|Make|Update|Use) .+'
conv_re='^(feat|fix|test|chore|doc): .+'
if ! printf '%s' "$subject" | grep -qE "$verb_re" \
    && ! printf '%s' "$subject" | grep -qE "$conv_re"; then
    {
        echo "Error: commit subject does not follow an accepted style."
        echo "       Got: $subject"
        echo ""
        echo "  Use one of:"
        echo "    Verb-style:   <Verb> <subject>"
        echo "                  Verbs: Add, Remove, Move, Improve, Pass, Verify, Modify,"
        echo "                         Allow, Bump, Fix, Implement, Make, Update, Use"
        echo "    Conventional: <type>: <subject>"
        echo "                  Types: feat, fix, test, chore, doc"
    } >&2
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

# Locate the active intent file for THIS commit's session, if any. The
# intent-capture.sh hook + intent-finalize.sh registered a session→intent
# mapping at ~/.claude/state/intent-active-<session>-<repo>.path.
#
# Multiple Claude sessions can touch the same repo, so we cannot just take
# the newest marker — that would risk binding this commit to another
# session's intent. Instead: find the dirty-<session>.log whose entries
# include a file under this repo and which was most recently written
# (track-edit.sh updates its mtime on every Edit/Write). That session is
# the one responsible for the current pending changes, and its intent
# marker is the one we want.
intent_file=""
intent_basename=""
if command -v md5sum >/dev/null 2>&1; then
    repo_hash=$(printf '%s' "$toplevel" | md5sum | head -c 12)
else
    repo_hash=$(printf '%s' "$toplevel" | md5 -q | head -c 12)
fi

session_for_repo=""
# `ls -t` sorts by mtime descending — newest dirty log first
for log in $(ls -t "$HOME/.claude/state"/dirty-*.log 2>/dev/null); do
    if grep -Fq "${toplevel}/" "$log" 2>/dev/null; then
        session_for_repo=$(basename "$log" .log | sed 's/^dirty-//')
        break
    fi
done

if [[ -n "$session_for_repo" ]]; then
    marker_file="$HOME/.claude/state/intent-active-${session_for_repo}-${repo_hash}.path"
    if [[ -f "$marker_file" ]]; then
        candidate=$(cat "$marker_file" 2>/dev/null || true)
        if [[ -n "$candidate" ]] && [[ -f "$candidate" ]]; then
            intent_file="$candidate"
            intent_basename=$(basename "$intent_file" .md)
        fi
    fi
fi

# If we found an intent file, append Intent-Summary / Intent-Ref trailers so
# the commit body carries the "why" for future maintainers reading git log.
# Skip when the user already wrote them manually (idempotent).
final_msg="$msg"
if [[ -n "$intent_file" ]]; then
    commit_summary=$(awk '/^---$/{c++; if(c==2)exit; next} c==1 && /^commit_summary: /{sub(/^commit_summary: /, ""); print; exit}' "$intent_file" 2>/dev/null || true)
    if [[ -n "$commit_summary" ]] && ! printf '%s' "$msg" | grep -q '^Intent-Summary:'; then
        # Display path as ~/docs/... not absolute /home/... for portability
        intent_display="${intent_file/#$HOME/~}"
        final_msg=$(printf '%s\n\nIntent-Summary: %s\nIntent-Ref: %s\n' "$msg" "$commit_summary" "$intent_display")
    fi
fi

git add -A && git commit -m "$final_msg" && git push -u origin "$branch"
git_rc=$?

# After a successful main push, persist the intent file into ~/docs so the
# SourceItem layer reflects this session's captured intent. ~/docs is private
# and not pushed externally — the commit is purely for local SSoT history.
if [[ $git_rc -eq 0 ]] && [[ -n "$intent_file" ]] && [[ -f "$intent_file" ]]; then
    docs_root="$HOME/docs"
    if [[ "$intent_file" == "$docs_root"/* ]]; then
        rel_path="${intent_file#$docs_root/}"
        if cd "$docs_root" 2>/dev/null; then
            # Only commit if the intent file has pending changes
            if git status --porcelain -- "$rel_path" 2>/dev/null | grep -q .; then
                if git add "$rel_path" 2>/dev/null \
                    && git commit -m "ingest: session intent ${intent_basename}" >/dev/null 2>&1; then
                    echo "[save.sh] ~/docs: ingested session intent ($rel_path)" >&2
                else
                    echo "[save.sh] warn: ~/docs ingest commit failed for $rel_path" >&2
                fi
            fi
            cd - >/dev/null
        fi
    fi
fi

exit $git_rc
