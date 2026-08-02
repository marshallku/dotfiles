#!/bin/bash
# Bootstrap the zsh plugins that .zshrc sources directly.
#
# There is no plugin framework here: .zshrc removed oh-my-zsh (it cost ~40ms of
# startup, and of the ~206 aliases it defined only four were ever used). The two
# pieces that were worth keeping are plain git clones under ~/.zsh, sourced by
# path. This script creates them. Run after `stow zsh powerlevel10k`. Idempotent.

set -e

ZSH_PLUGINS="$HOME/.zsh"

if ! command -v zsh >/dev/null 2>&1; then
    echo "✗ zsh not found — install it first"
    exit 1
fi
echo "✓ $(zsh --version)"

if ! command -v git >/dev/null 2>&1; then
    echo "✗ git not found"
    exit 1
fi

mkdir -p "$ZSH_PLUGINS"

# name|repo|extra clone args
plugins=(
    "powerlevel10k|https://github.com/romkatv/powerlevel10k.git|--depth=1"
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions|--depth=1"
)

for entry in "${plugins[@]}"; do
    IFS='|' read -r name repo args <<<"$entry"
    dir="$ZSH_PLUGINS/$name"
    if [ -d "$dir/.git" ]; then
        echo "✓ $name already at $dir"
    else
        echo "→ cloning $name"
        # shellcheck disable=SC2086
        git clone $args "$repo" "$dir"
    fi
done

# p10k reads ~/.p10k.zsh, which `stow powerlevel10k` symlinks out of this repo.
if [ ! -e "$HOME/.p10k.zsh" ]; then
    echo "! ~/.p10k.zsh missing — run \`stow powerlevel10k\` or the prompt falls back to the configure wizard"
fi

echo "✓ zsh bootstrap complete"
