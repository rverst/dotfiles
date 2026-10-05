#!/bin/zsh
# zmodload zsh/zprof  # uncomment to profile

# environment variables
# re-apply user PATH from .zshenv (path_helper in /etc/zprofile reorders it for login shells)
path=($_user_path $path)

export HOMEBREW_NO_ENV_HINTS=1
export GPG_TTY=$TTY
export FZF_DEFAULT_OPTS='--bind ctrl-a:accept --height 40% --tmux 80%'
export LANG=en_US.UTF-8
export COMPOSE_MENU=false
export RBENV_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/rbenv"
export CLAUDE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude"

#vi mode
bindkey -v
export KEYTIMEOUT=1

# plugin manager
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
  mkdir -p "$(dirname $ZINIT_HOME)"
  git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "$ZINIT_HOME/zinit.zsh"

# plugins load immediatly (needed for prompt/completions)
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light Aloxaf/fzf-tab
zinit snippet OMZP::ssh
#zinit ice atinit'zstyle ":omz:plugins:sudo" keyring "^s"'
#zinit snippet OMZ::plugins/sudo

# snippets - deferred with turbo mode (load after shell is interactive)
zinit ice wait lucid
zinit snippet OMZP::command-not-found

zinit light-mode for \
  wait'0' lucid \
  atinit'bindkey "^[[A" history-substring-search-up; bindkey "^[[B" history-substring-search-down' \
  zsh-users/zsh-history-substring-search

# load completions - full check (and dump rebuild) at most once a day
fpath=(~/.docker/completions $fpath)
autoload -U compinit
() {
  setopt local_options extended_glob
  local dump="$ZDOTDIR/.zcompdump"
  if [[ ! -f $dump || -n $dump(#qN.mh+24) ]]; then
    compinit -d "$dump"
    touch "$dump"
  else
    compinit -C -d "$dump"
  fi
  # compile to a unique temp file and rename atomically: parallel shells (tmux) otherwise race on the .zwc
  if [[ ! -f $dump.zwc || $dump -nt $dump.zwc ]]; then
    { zcompile "$dump.$$.zwc" "$dump" 2>/dev/null && command mv -f "$dump.$$.zwc" "$dump.zwc" || command rm -f "$dump.$$.zwc"; } &!
  fi
}

zinit cdreplay -q

# to customize prompt, run `p10k configure` or edit ~/.config/zsh/.p10k.zsh.
[[ ! -f ~/.config/zsh/.p10k.zsh ]] || source ~/.config/zsh/.p10k.zsh

# keybindings
bindkey '^a' autosuggest-accept
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

bindkey '^[[3~' delete-char
bindkey '^?' backward-delete-char

# change cursor shape for different vi modes
function zle-keymap-select {
  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then
    echo -ne '\e[1 q'
  elif [[ ${KEYMAP} == main ]] || [[ ${KEYMAP} == viins ]] ||
    [[ ${KEYMAP} == '' ]] || [[ $1 == 'beam' ]]; then
    echo -ne '\e[5 q'
  fi
}
zle -N zle-keymap-select

function zle-line-init {
  zle -K viins
  echo -ne '\e[5 q'
}
zle -N zle-line-init

echo -ne '\e[5 q'
_cursor_beam_preexec() { echo -ne '\e[5 q'; }
add-zsh-hook preexec _cursor_beam_preexec

# options

#history
HISTSIZE=9001
HISTFILE="$ZDOTDIR/.zsh_history"
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt inc_append_history
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_ignore_dups
setopt hist_save_no_dups

# completion styling (case insensitive completion and colors)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
# disable default completion in favour of fzf
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# functions
fpath=(~/.config/zsh/functions $fpath)
autoload -U bip bup fif fia git_is_clean batch_exec batch_exec_parallel setJava setNode

# aliases
source "$ZDOTDIR/alias.zsh"

# fzf shell integration - cache to avoid subprocess on every shell start
if (($+commands[fzf])); then
  _fzf_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/fzf-init.zsh"
  if [[ ! -f "$_fzf_cache" || $(command -v fzf) -nt "$_fzf_cache" ]]; then
    mkdir -p "${_fzf_cache:h}"
    fzf --zsh >|"$_fzf_cache"
  fi
  source "$_fzf_cache"
  unset _fzf_cache
  # use option + c for fzf-cd-widget (macos)
  bindkey 'ç' fzf-cd-widget
else
  bindkey '^r' history-incremental-search-backward
fi

# zoxide integration - cache to avoid subprocess on every shell start
if (($+commands[zoxide])); then
  _zoxide_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zoxide-init.zsh"
  if [[ ! -f "$_zoxide_cache" || $(command -v zoxide) -nt "$_zoxide_cache" ]]; then
    mkdir -p "${_zoxide_cache:h}"
    zoxide init --cmd cd zsh >|"$_zoxide_cache"
  fi
  source "$_zoxide_cache"
  unset _zoxide_cache
  zstyle ':fzf-tab:complete:cd:__zoxide_z:*' fzf-preview 'ls --color $realpath'
fi

# on macos, .zprofile is used by some apps, like homebrew or jetbrains toolbox to set env vars
[ -f "$HOME/.zprofile" ] && . "$HOME/.zprofile"

# use .localrc for SUPER SECRET CRAP that you don't want in your public, versioned repo.
# shellcheck disable=SC1090
[ -f "$HOME/.localrc" ] && . "$HOME/.localrc"

# prompt - not cached: init registers a per-shell session (POSH_SESSION_ID) holding the config;
# a cached init shares one session across all shells and falls back to the default theme once it's cleaned up
if [ "$TERM_PROGRAM" != "Apple_Terminal" ] && command -v oh-my-posh >/dev/null; then
  _omp_config="$XDG_CONFIG_HOME/oh-my-posh/mytheme.omp.yaml"
  eval "$(oh-my-posh init zsh --config "$_omp_config")"
  # print only reads the config from the session cache and renders the default theme if that entry gets lost;
  # passing --config makes it fall back to our theme instead
  functions[_omp_get_prompt_orig]=$functions[_omp_get_prompt]
  _omp_get_prompt() { _omp_get_prompt_orig "$1" --config="$_omp_config" "${@[2,-1]}"; }
fi

# direnv integration - cache to avoid subprocess on every shell start
if (($+commands[direnv])); then
  _direnv_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/direnv-init.zsh"
  if [[ ! -f "$_direnv_cache" || $(command -v direnv) -nt "$_direnv_cache" ]]; then
    mkdir -p "${_direnv_cache:h}"
    direnv hook zsh >|"$_direnv_cache"
  fi
  source "$_direnv_cache"
  unset _direnv_cache
fi

# rbenv - lazy load: only init when ruby/rbenv/gem/bundle is actually called
if (($+commands[rbenv])); then
  rbenv() {
    unfunction rbenv
    eval "$(command rbenv init - --no-rehash zsh)"
    rbenv "$@"
  }
  ruby() {
    unfunction ruby
    eval "$(command rbenv init - --no-rehash zsh)"
    ruby "$@"
  }
  gem() {
    unfunction gem
    eval "$(command rbenv init - --no-rehash zsh)"
    gem "$@"
  }
  bundle() {
    unfunction bundle
    eval "$(command rbenv init - --no-rehash zsh)"
    bundle "$@"
  }
fi
