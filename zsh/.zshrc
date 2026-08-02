if command -v gdate &>/dev/null; then
  date() { gdate "$@"; }
fi

if command -v gsed &>/dev/null; then
  sed() { gsed "$@"; }
fi

zmodload -F zsh/datetime b:strftime p:EPOCHSECONDS
dday() {
	if [ $# -ne 2 ]; then
		echo "Usage: dday YYYY-MM-DD \"Message to display\""
		return 1
	fi

	local target today
	if ! strftime -r -s target '%Y-%m-%d' "$1" 2>/dev/null; then
		echo "Invalid date format. Use YYYY-MM-DD"
		return 1
	fi
	today=$EPOCHSECONDS
	diff_seconds=$((target - today))
	diff_days=$((diff_seconds / 86400))

	set_format='\033[1;31m'
	reset_format='\033[0m'


	if [ $diff_days -eq 0 ]; then
		echo "It's D-Day of $2"
	elif [ $diff_days -gt 0 ]; then
		echo "${set_format}${diff_days}${reset_format} days before $2"
	else
		echo "${set_format}$((diff_days * -1 + 1))${reset_format} days after $2"
	fi
}

dday '2024-03-02' 'I met the love of my life'
dday '2026-08-22' 'Our marriage'

# Homebrew (must come before oh-my-zsh to take precedence over /usr/bin)
[[ "$(uname)" == "Darwin" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
# ── Powerlevel10k instant prompt (must stay near the top) ──────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH="$HOME/.oh-my-zsh"   # still the on-disk home of p10k + zsh-autosuggestions

# ── History (was: omz lib/history.zsh) ─────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=10000
setopt extended_history hist_expire_dups_first hist_ignore_dups hist_ignore_space \
       hist_verify inc_append_history share_history

# ── Shell options (was: omz lib/directories.zsh + misc.zsh) ────────────────
setopt auto_cd auto_pushd pushd_ignore_dups pushdminus interactive_comments \
       long_list_jobs multios prompt_subst
alias -g ...='../..'
alias ..='cd ..'
alias -- -='cd -'
alias md='mkdir -p'
alias _='sudo '

# ls/grep/history: the only oh-my-zsh aliases that actually show up in
# ~/.zsh_history (ls 709x, history 25x, grep 9x, l 4x). The other ~200 the
# framework defined were never used, so they are not carried over.
alias ls='ls --color=tty'
alias l='ls -lah'
alias lsa='ls -lah'
alias ll='ls -lh'
alias la='ls -lAh'
alias grep='grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox,.venv,venv}'
alias egrep='grep -E'
alias fgrep='grep -F'

# `history` with no args must list from 1, not zsh's default last-16. Ported from
# omz's omz_history so `-c` (clear), `-f/-E/-i/-t` (timestamps) and explicit
# ranges keep working, rather than only the bare no-argument case.
function zsh_history {
  local clear list stamp REPLY
  zparseopts -E -D c=clear l=list f=stamp E=stamp i=stamp t:=stamp

  if [[ -n "$clear" ]]; then
    print -nu2 "This action will irreversibly delete your command history. Are you sure? [y/N] "
    builtin read -E
    [[ "$REPLY" = [yY] ]] || return 0
    print -nu2 >| "$HISTFILE"
    fc -p "$HISTFILE"
    print -u2 History file deleted.
  elif [[ $# -eq 0 ]]; then
    builtin fc "${stamp[@]}" -l 1
  else
    builtin fc "${stamp[@]}" -l "$@"
  fi
}
alias history='zsh_history'

# ── Completion (was: omz lib/completion.zsh) ───────────────────────────────
# Full compinit at most once a day; cached (-C) otherwise. This is the single
# biggest win over oh-my-zsh, which re-audits every start.
autoload -Uz compinit
_zcompdump="$HOME/.zcompdump-${HOST%%.*}-${ZSH_VERSION}"
# Dump younger than 24h -> cached load (-C, skips the compaudit security scan).
# Otherwise a full compinit, and recompile the dump in the background.
# extended_glob is enabled locally: (#q..) qualifiers need it, and turning it on
# globally would change pattern semantics for the rest of the file.
if () { emulate -L zsh -o extended_glob; [[ -n ${_zcompdump}(#qNmh-24) ]] }; then
  compinit -C -d "$_zcompdump"
else
  compinit -d "$_zcompdump"
  # Compile via a PID-unique temp + atomic rename. Writing "$dump.zwc" in place
  # would race when several shells start at once (tmux restoring a session), and
  # a half-written .zwc is what the next `compinit -C` would source.
  { local _t="${_zcompdump}.zwc.$$"
    if zcompile -R -- "$_t" "$_zcompdump" 2>/dev/null; then
      command mv -f -- "$_t" "${_zcompdump}.zwc" 2>/dev/null || command rm -f -- "$_t"
    else
      command rm -f -- "$_t"
    fi } &!
fi
unset _zcompdump

zmodload -i zsh/complist
autoload -U +X bashcompinit && bashcompinit
unsetopt menu_complete flowcontrol
setopt auto_menu complete_in_word always_to_end
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "$HOME/.cache/zsh/zcompcache"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*:*:kill:*:processes' command 'ps -u $USER -o pid,user,comm -w'
WORDCHARS=''

# ── Key bindings (was: omz lib/key-bindings.zsh) ───────────────────────────
bindkey -e
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search   ; bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search ; bindkey '^[OB' down-line-or-beginning-search
bindkey '^[[1;5C' forward-word  ; bindkey '^[[1;5D' backward-word
bindkey '^[[H' beginning-of-line ; bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[3;5~' kill-word
bindkey '^[[1~' beginning-of-line ; bindkey '^[[4~' end-of-line
bindkey '^[[5~' up-line-or-history ; bindkey '^[[6~' down-line-or-history
bindkey '^[[Z' reverse-menu-complete
bindkey '^[w' kill-region
bindkey '^[m' copy-prev-shell-word
bindkey ' ' magic-space
bindkey '^R' history-incremental-search-backward
autoload -Uz edit-command-line && zle -N edit-command-line
bindkey '^X^E' edit-command-line

# ── Terminal title + cwd reporting (was: omz lib/termsupport.zsh) ──────────
autoload -Uz add-zsh-hook

ZSH_THEME_TERM_TAB_TITLE_IDLE="%15<..<%~%<<"   # 15-char left-truncated pwd
ZSH_THEME_TERM_TITLE_IDLE="%n@%m:%~"
[[ "$TERM_PROGRAM" == Apple_Terminal ]] && ZSH_THEME_TERM_TITLE_IDLE="%n@%m"

function title {
  setopt localoptions nopromptsubst
  [[ -n "${INSIDE_EMACS:-}" && "$INSIDE_EMACS" != vterm ]] && return
  : ${2=$1}
  case "$TERM" in
    cygwin|xterm*|putty*|rxvt*|konsole*|ansi|mlterm*|alacritty*|st*|foot*|contour*|wezterm*)
      print -Pn "\e]2;${2:q}\a"   # window name
      print -Pn "\e]1;${1:q}\a"   # tab name
      ;;
    screen*|tmux*)
      print -Pn "\ek${1:q}\e\\"   # screen/tmux hardstatus
      ;;
    *)
      if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
        print -Pn "\e]2;${2:q}\a"
        print -Pn "\e]1;${1:q}\a"
      elif (( ${+terminfo[fsl]} && ${+terminfo[tsl]} )); then
        print -Pn "${terminfo[tsl]}$1${terminfo[fsl]}"
      fi
      ;;
  esac
}

function _title_precmd {
  [[ "${DISABLE_AUTO_TITLE:-}" != true ]] || return 0
  title "$ZSH_THEME_TERM_TAB_TITLE_IDLE" "$ZSH_THEME_TERM_TITLE_IDLE"
}

# Shows the running command in the title, including resolving `fg %job` back to
# the job's command text.
function _title_preexec {
  [[ "${DISABLE_AUTO_TITLE:-}" != true ]] || return 0
  emulate -L zsh
  setopt extended_glob

  local -a cmdargs
  cmdargs=("${(z)2}")
  if [[ "${cmdargs[1]}" = fg ]]; then
    local job_id jobspec="${cmdargs[2]#%}"
    case "$jobspec" in
      <->)     job_id=${jobspec} ;;
      ""|%|+)  job_id=${(k)jobstates[(r)*:+:*]} ;;
      -)       job_id=${(k)jobstates[(r)*:-:*]} ;;
      [?]*)    job_id=${(k)jobtexts[(r)*${(Q)jobspec}*]} ;;
      *)       job_id=${(k)jobtexts[(r)${(Q)jobspec}*]} ;;
    esac
    if [[ -n "${jobtexts[$job_id]}" ]]; then
      1="${jobtexts[$job_id]}"
      2="${jobtexts[$job_id]}"
    fi
  fi

  # cmd name only, or if this is sudo/ssh/etc, the next cmd
  local CMD="${1[(wr)^(*=*|sudo|ssh|mosh|rake|-*)]:gs/%/%%}"
  local LINE="${2:gs/%/%%}"
  title "$CMD" "%100>...>${LINE}%<<"
}

# OSC 7: tells the terminal the current directory, so "new tab/split here"
# opens in the same place (kitty and ghostty both use this).
function _osc7_cwd {
  emulate -L zsh -o extended_glob
  local LC_ALL=C   # byte-wise, so multibyte paths percent-encode correctly
  local url_host="$HOST" url_path
  url_path=${PWD//(#m)[^A-Za-z0-9_.\!~*\'\(\)\/-]/%${(l:2::0:)$(([##16]#MATCH))}}
  # Konsole errors out when the host is supplied
  [[ -z "$KONSOLE_PROFILE_NAME" && -z "$KONSOLE_DBUS_SESSION" ]] || url_host=""
  printf '\e]7;file://%s%s\e\\' "$url_host" "$url_path"
}

add-zsh-hook precmd _title_precmd
add-zsh-hook preexec _title_preexec

# OSC 7 only where it is meaningful, matching termsupport.zsh: not inside Emacs,
# not over SSH (the path would be remote but the terminal is local — omz#11696),
# and only on terminals that handle or ignore the sequence cleanly.
if [[ -z "$INSIDE_EMACS" && -z "$SSH_CLIENT" && -z "$SSH_TTY" ]]; then
  case "$TERM" in
    xterm*|putty*|rxvt*|konsole*|mlterm*|alacritty*|screen*|tmux*|contour*|foot*)
      add-zsh-hook precmd _osc7_cwd ;;
    *)
      case "$TERM_PROGRAM" in
        Apple_Terminal|iTerm.app) add-zsh-hook precmd _osc7_cwd ;;
      esac ;;
  esac
fi

# ── git helpers used by the aliases below (was: omz git plugin) ────────────
function git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2>/dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return
    ref=$(command git rev-parse --short HEAD 2>/dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

function git_main_branch() {
  command git rev-parse --git-dir &>/dev/null || return
  local remote ref
  for ref in refs/{heads,remotes/{origin,upstream}}/{main,trunk,mainline,default,stable,master}; do
    command git show-ref -q --verify $ref && { echo ${ref:t}; return 0 }
  done
  for remote in origin upstream; do
    ref=$(command git rev-parse --abbrev-ref $remote/HEAD 2>/dev/null)
    [[ $ref == $remote/* ]] && { echo ${ref#"$remote/"}; return 0 }
  done
  echo master
  return 1
}

# ── Plugins (sourced directly; no oh-my-zsh loader) ────────────────────────
source $ZSH/custom/themes/powerlevel10k/powerlevel10k.zsh-theme
ZSH_AUTOSUGGEST_MANUAL_REBIND=1
source $ZSH/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh


# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

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
#alias gbcl="git branch -d $(git branch --merged | grep -v '^\(\*\| \+master$\)')"

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

function gchd {
        local target_branch="${1-$(git_main_branch)}"
        local current_branch="$(git rev-parse --abbrev-ref HEAD)"

        git checkout $target_branch
        git branch -D $current_branch
        git pull origin $target_branch
}

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

# Claude
alias cc='claude --dangerously-skip-permissions'
alias ccr='claude --dangerously-skip-permissions --resume'

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

# Hyprland wallpaper (hyprpaper + hyprlock); see scripts/wallpaper.sh
alias wp="$HOME/.config/hypr/scripts/wallpaper.sh"

# Claude Code freeze/unfreeze
freeze() {
  local dir="${1:?Usage: freeze <directory>}"
  dir="$(realpath "$dir")"
  if [ ! -d "$dir" ]; then
    echo "Error: $dir is not a directory" >&2
    return 1
  fi
  echo "$dir" > "$HOME/.claude/freeze-dir.txt"
  echo "Frozen to: $dir"
}

unfreeze() {
  rm -f "$HOME/.claude/freeze-dir.txt"
  echo "Unfrozen — edits allowed everywhere"
}

freeze-status() {
  local f="$HOME/.claude/freeze-dir.txt"
  if [ -f "$f" ] && [ -s "$f" ]; then
    echo "Frozen to: $(cat "$f")"
  else
    echo "Not frozen"
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
#alias cd='z'

# Common Typo
alias 칟ㅁㄱ='clear'
alias c='clear'

function ppid {
	sudo lsof -t -i :$1
}

function kp {
    # Kill process by port
    if [ -z "$1" ]; then
        echo "Usage: kp <port>"
        return 1
    fi

    # Try with SIGTERM
    local pid=$(ppid $1)
    local timeout=${2:-30}
    if [ -z "$pid" ]; then
        echo "Process is not running."
        return 1
    fi

    kill $pid

    local count=0
    while ps -p $pid >/dev/null && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
        echo "Waiting for process to be killed... $count/$timeout"
    done

    if ps -p $pid >/dev/null; then
        echo "Process is still running. Trying SIGKILL."
        kill -9 $pid
    else
        echo "Process killed."
    fi
}

# Long-running command notification (notify if command takes >10 seconds)
__cmd_notify_threshold=10
__cmd_notify_exclude="^(vim|nvim|htop|top|less|man|ssh|tmux|tms|tmx|fzf)"

preexec() {
  __cmd_start_time=$EPOCHSECONDS
  __cmd_name="$1"
}

precmd() {
  local exit_code=$?
  if [[ -n "$__cmd_start_time" ]]; then
    local elapsed=$(( EPOCHSECONDS - __cmd_start_time ))
    if (( elapsed >= __cmd_notify_threshold )); then
      if [[ ! "$__cmd_name" =~ $__cmd_notify_exclude ]]; then
        local status_icon
        if (( exit_code == 0 )); then
          status_icon="✓"
        else
          status_icon="✗ ($exit_code)"
        fi
        if command -v notify >/dev/null 2>&1; then
          notify -u normal -t 5000 \
            "Command finished ${status_icon}" \
            "${__cmd_name}\nTook ${elapsed}s"
        fi
      fi
    fi
    unset __cmd_start_time
    unset __cmd_name
  fi
}

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Input method (fcitx5) — SSH 세션에서만 적용
if [[ -n "$SSH_CONNECTION" || -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
    export GTK_IM_MODULE=fcitx
    export QT_IM_MODULE=fcitx
    export XMODIFIERS=@im=fcitx
fi

export PATH="$HOME/.local/bin:$PATH"

#eval "$(zoxide init zsh)"
eval "$(mise activate zsh)"
command -v tmx >/dev/null && eval "$(tmx shell-init zsh)"
alias tms='tmx switch'

# bun completions
[ -s "/home/marshall/.bun/_bun" ] && source "/home/marshall/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
#. "/home/marshall/.deno/env"

# go
export PATH=$PATH:/usr/local/go/bin

# chromium
export CHROME_EXECUTABLE=/usr/bin/chromium

# default browser
export BROWSER=firefox

export PATH="$HOME/docs/scripts:$PATH"

alias tmux="tmux -u"

#[[ "$TERM" == "xterm-ghostty" ]] && (~/ghostty-random-bg.sh &>/dev/null &)
[[ "$TERM" == "xterm-kitty" ]] && (~/kitty-random-bg.sh --daemon --interval 300 &>/dev/null &)


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm (PNPM_HOME is set per-OS in ~/.zshenv; fallback here if unset)
: "${PNPM_HOME:=$HOME/.local/share/pnpm}"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
# pnpm end



# macOS-only PATH entries (these used to run unguarded on Linux, adding
# directories that do not exist here).
if [[ "$(uname)" == "Darwin" ]]; then
  PATH="/opt/homebrew/opt/coreutils/libexec/gnubin:$PATH"
  ### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
  export PATH="/Users/marshallku/.rd/bin:$PATH"
  ### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)
fi
