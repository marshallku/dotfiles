# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment the following line to disable bi-weekly auto-update checks.
# DISABLE_AUTO_UPDATE="true"

# Uncomment the following line to automatically update without prompting.
# DISABLE_UPDATE_PROMPT="true"

# Uncomment the following line to change how often to auto-update (in days).
# export UPDATE_ZSH_DAYS=13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR='vim'
else
  export EDITOR='nvim'
fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Aliases
# Git
alias g='git'

alias ga='git add'
alias gaa='git add -A'

alias gb='git branch'
alias gbd='git branch -D'
alias gbcl="git branch -d $(git branch --merged | grep -v '^\(\*\| \+master$\)')"

alias gc='git commit'
alias gcm='git commit -m'
alias gch='git checkout'
alias gchb='git checkout -b'
alias gchm='git checkout $(git_main_branch)'
alias gcr='git cherry-pick'

alias gd='git diff'
alias gdc='git diff --cached'
alias gdm='git diff $(git_main_branch)'
alias gdd='git diff dev'

alias gf='git fetch'
alias gfo='git fetch origin'

alias gl='git log'
alias glg='git log --graph'

alias gm='git merge'
alias gms='git merge --squash'
alias gmnf='git merge --no-ff'

alias gp='git push'
alias gpo='git push origin'
alias gpoc='git push origin $(git_current_branch)'
alias gpom='git push -u origin $(git_main_branch)'
alias gpl='git pull'
alias gplc='git pull origin $(git_current_branch)'
alias gplo='git pull origin'

alias gs='git status'
alias gst='git stash'
alias gstp='git stash pop'

alias gchd='TARGET_BRANCH="${1:-$(git_main_branch)}";CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD)";git checkout $TARGET_BRANCH;git branch -D $CUR_BRANCH;git pull origin $TARGET_BRANCH'

# NPM
alias n='npm'

alias ni='npm i'
alias nid='npm i -D'

alias nr='npm run'
alias nrm='npm uninstall'

alias nu='npm update'
alias nud='npm update --save/--save-dev'

# Python
alias py='python3'
alias pip='pip3'

# PNPM
alias pi='pnpm i'
alias pid='pnpm i -D'

alias pci='pnpm i --frozen-lockfile'

function pr {
  local scripts=$(py -c "import json; print('\n'.join(json.load(open('package.json'))['scripts'].keys()))")
  local script=$(echo "$scripts" | fzf)

  if [[ -z "$script" ]]; then
    return 1
  fi

  echo 'Please enter any extra arguments'
  read -r args
  eval "pnpm $script $args"
}
alias prm='pnpm remove'

# Yarn
alias y='yarn'

alias ya='yarn add'
alias yad='yarn add -D'

alias yci='yarn install --frozen-lockfile'

alias yr='yarn run'
alias yrv='yarn remove'

alias yu='yarn upgrade'

# Universal package manager
function p {
  if [[ -f pnpm-lock.yaml ]]; then
    command pnpm "$@"
  elif [[ -f package-lock.json ]]; then
    command npm "$@"
  elif [[ -f yarn.lock ]]; then
    command yarn "$@"
  elif [[ -f bun.lockb ]]; then
    command bun "$@"
  else
    command pnpm "$@"
  fi
}

# Vim
alias vi='nvim'
alias vim='nvim'

# Docker
alias d='docker'
alias dc='docker compose'

# Kubernetes
alias k='kubectl'
alias mk='minikube'
alias mkk='minikube kubectl --'

# Replace built-in commands
alias cd='z'

# Common Typo
alias 칟ㅁㄱ='clear'
alias c='clear'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

export PATH="$HOME/.local/bin:$PATH"

eval "$(zoxide init zsh)"
