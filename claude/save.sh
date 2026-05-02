#!/bin/bash

if [[ -z "$1" ]]; then
    echo "Usage: $0 <commit message>"
    exit 1
fi

allowed_verbs="Add|Remove|Move|Improve|Pass|Verify|Modify|Allow|Bump|Fix|Implement|Make|Update|Use"
if [[ ! "$1" =~ ^($allowed_verbs)[[:space:]] ]]; then
    echo "Error: commit message must start with one of: ${allowed_verbs//|/, }"
    exit 1
fi

branch=$(git symbolic-ref --short HEAD 2>/dev/null)
if [[ -z "$branch" ]]; then
    echo "Error: not on a branch"
    exit 1
fi

git add -A && git commit -m "$1" && git push -u origin "$branch"
