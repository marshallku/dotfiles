#!/bin/bash

# Commit message prefix conventions (suggestive, not enforced):
#   Verb-style:   Add, Remove, Move, Improve, Pass, Verify, Modify, Allow, Bump, Fix, Implement, Make, Update, Use
#   Conventional: feat:, fix:, test:, chore:, doc:
# Any non-empty message is accepted — pick one if it fits, or skip the prefix.

if [[ -z "$1" ]]; then
    echo "Usage: $0 <commit message>"
    exit 1
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ -z "$branch" ]]; then
    echo "Error: not on a branch"
    exit 1
fi

git add -A && git commit -m "$1" && git push -u origin "$branch"
