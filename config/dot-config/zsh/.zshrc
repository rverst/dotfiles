#!/bin/zsh

# environment variables
typeset -U path
path=(~/.local/bin ~/.local/scripts $path)

[ -d ~/go/bin ] && path=(~/go/bin $path)

# on macos, .zprofile is used by some apps, like homebrew ot jetbrains toolbox to set env vars
[ -f "$HOME/.zprofile" ] && . "$HOME/.zprofile"

export HOMEBREW_NO_ENV_HINTS=1
export GPG_TTY=$(tty)
export FZF_DEFAULT_OPTS='--bind ctrl-a:accept --height 40% --tmux 80%'

#vi mode
bindkey -v
export KEYTIMEOUT=1

# plugin manager
ZINIT_HOME="${ZDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
	mkdir -p "$(dirname $ZINIT_HOME)"
	git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

source "$ZINIT_HOME/zinit.zsh"

# some other plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

zinit snippet OMZP::git
zinit snippet OMZP::aws
zinit snippet OMZP::azure
zinit snippet OMZP::command-not-found
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::ssh

# load completions
autoload -U compinit && compinit

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
preexec() { echo -ne '\e[5 q' ;}

# options

#history
HISTSIZE=9001
HISTFILE="$ZDOTDIR/.zsh_history"
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups

# completion styling (case insensitive completion and colors)
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
# disable default completion in favour of fzf
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# functions
fpath=(~/.config/zsh/functions $fpath)
autoload -U bip bup

# aliases
source "$ZDOTDIR/alias.zsh"

# fzf shell integration
if [ ! -z $(command -v fzf) ]; then
  eval "$(fzf --zsh)"
else
  bindkey '^r' history-incremental-search-backward
fi

# zoxide integration
if [ ! -z $(command -v zoxide) ]; then
  eval "$(zoxide init --cmd cd zsh)"
  zstyle ':fzf-tab:complete:cd:__zoxide_z:*' fzf-preview 'ls --color $realpath'
fi

# use .localrc for SUPER SECRET CRAP that you don't want in your public, versioned repo.
# shellcheck disable=SC1090
[ -f "$HOME/.localrc" ] && . "$HOME/.localrc"

# prompt
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(oh-my-posh init zsh --config $XDG_CONFIG_HOME/oh-my-posh/mytheme.omp.yaml)"
fi

