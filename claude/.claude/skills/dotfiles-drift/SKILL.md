---
name: dotfiles-drift
description: Compare dotfiles source packages against deployed runtime copies, report divergence
user-invocable: true
arguments: package
argument-hint: [package-name] (optional; omit to scan all packages)
allowed-tools: Bash
effort: low
---

## Purpose

Replace the ad-hoc multi-step diff sequences used when checking whether dotfiles
packages are in sync with their deployed runtime counterparts. The manual form
(enumerate packages → find source files → diff against runtime) was observed across
5 sessions, most explicitly in 414ad1a6 as a 6-command sequence.

## Steps

Run the drift scan:

```bash
SRC="${HOME}/dotfiles"
FILTER="${1:-}"
PROBLEMS=0

for PKG_DIR in "${SRC}"/*/; do
    PKG="$(basename "${PKG_DIR}")"
    [[ -n "${FILTER}" && "${PKG}" != "${FILTER}" ]] && continue

    while IFS= read -r -d '' SRCFILE; do
        REL="${SRCFILE#${PKG_DIR}}"
        DST="${HOME}/${REL}"

        if [[ -f "${DST}" ]]; then
            if ! diff -q "${SRCFILE}" "${DST}" &>/dev/null; then
                echo "DRIFT    ${SRCFILE}"
                echo "      →  ${DST}"
                diff --unified=2 "${SRCFILE}" "${DST}" | tail -n +3 | head -20
                echo ""
                (( PROBLEMS++ )) || true
            fi
        else
            echo "MISSING  ${DST}"
            echo "   src:  ${SRCFILE}"
            echo ""
            (( PROBLEMS++ )) || true
        fi
    done < <(find "${PKG_DIR}" -type f -print0 2>/dev/null)
done

echo "────────────────────────────────────"
echo "Drifted/missing files: ${PROBLEMS}"
```

Pass an optional package name to scope the scan (e.g., `/dotfiles-drift zsh` checks
only the `zsh` package). Omit to scan all packages under `~/dotfiles/`.

