#!/bin/zsh
# uncomment this and the last line for zprof info
# zmodload zsh/zprof

typeset -U path
path=(~/.local/bin ~/.local/scripts ~/go/bin /opt/homebrew/bin $path)

export HOMEBREW_NO_ENV_HINTS=1
export GPG_TTY=$(tty)
export LSCOLORS='exfxcxdxbxegedabagacad'
export CLICOLOR=true
export KEYTIMEOUT=10

zsh_plugins=${ZDOTDIR}/.zsh_plugins
if [[ ! ${zsh_plugins}.zsh -nt ${zsh_plugins}.txt ]]; then
	echo "INSTALL PLUGINS"
	source /opt/homebrew/opt/antidote/share/antidote/antidote.zsh
	antidote bundle <${zsh_plugins}.txt >${zsh_plugins}.zsh
fi
source ${zsh_plugins}.zsh

#fpath=($ZDOTDIR/functions $fpath)
#autoload -U "$ZDOTDIT"/functions/*(:t)

autoload -U up-line-or-beginning-search
autoload -U down-line-or-beginning-search
autoload -U edit-command-line

HISTFILE="$XDG_CACHE_HOME/.zsh_history"
HISTSIZE=20000
SAVEHIST=20000

# don't nice background tasks
setopt NO_BG_NICE
setopt NO_HUP
setopt NO_BEEP
# allow functions to have local options
setopt LOCAL_OPTIONS
# allow functions to have local traps
setopt LOCAL_TRAPS
# share history between sessions ???
setopt SHARE_HISTORY
# add timestamps to history
setopt EXTENDED_HISTORY
setopt PROMPT_SUBST
setopt CORRECT
setopt COMPLETE_IN_WORD
# adds history
setopt APPEND_HISTORY
# adds history incrementally and share it across sessions
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
# don't record dupes in history
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt HIST_EXPIRE_DUPS_FIRST
# dont ask for confirmation in rm globs*
# setopt RM_STAR_SILENT

zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
zle -N edit-command-line

# fuzzy find: start to type
bindkey "$terminfo[kcuu1]" up-line-or-beginning-search
bindkey "$terminfo[kcud1]" down-line-or-beginning-search
bindkey "$terminfo[cuu1]" up-line-or-beginning-search
bindkey "$terminfo[cud1]" down-line-or-beginning-search

# delete char with backspaces and delete
bindkey '^[[3~' delete-char
bindkey '^?' backward-delete-char

bindkey '^f' 'tmux-sessionizer\n'

autoload -Uz compinit
compinit

# forces zsh to realize new commands
zstyle ':completion:*' completer _oldlist _expand _complete _match _ignored _approximate
# matches case insensitive for lowercase
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# pasting with tabs doesn't perform completion
zstyle ':completion:*' insert-tab pending
# rehash if command not found (possibly recently installed)
zstyle ':completion:*' rehash true
# menu if nb items > 2
zstyle ':completion:*' menu select=2

# search history with fzf if installed, default otherwise
if [ -L /opt/homebrew/bin/fzf ]; then
	local target=$(readlink -f /opt/homebrew/bin/fzf)
	. ${target%bin*}shell/key-bindings.zsh
	. ${target%bin*}shell/completion.zsh
elif test -d /usr/local/opt/fzf/shell; then
	# shellcheck disable=SC1091
	. /usr/local/opt/fzf/shell/key-bindings.zsh
else
	bindkey '^R' history-incremental-search-backward
fi

source "$ZDOTDIR/alias.zsh"

export LS_COLORS="rs=0:di=34:ln=35:mh=00:pi=40;33:so=01;35:\
do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:mi=00:\
su=37;41:sg=30;43:ca=30;41:tw=35;01:ow=33;01:st=37;44:ex=01;32:\
*.tar=01;31:*.tgz=01;31:*.arc=01;31:*.arj=01;31:*.taz=01;31:*.lha=01;31:\
*.lz4=01;31:*.lzh=01;31:*.lzma=01;31:*.tlz=01;31:*.txz=01;31:*.tzo=01;31:\
*.t7z=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.dz=01;31:*.gz=01;31:*.lrz=01;31:\
*.lz=01;31:*.lzo=01;31:*.xz=01;31:*.zst=01;31:*.tzst=01;31:*.bz2=01;31:\
*.bz=01;31:*.tbz=01;31:*.tbz2=01;31:*.tz=01;31:*.deb=01;31:*.rpm=01;31:\
*.jar=01;31:*.war=01;31:*.ear=01;31:*.sar=01;31:*.rar=01;31:\
*.alz=01;31:*.ace=01;31:*.zoo=01;31:*.cpio=01;31:*.7z=01;31:*.rz=01;31:\
*.cab=01;31:*.wim=01;31:*.swm=01;31:*.dwm=01;31:*.esd=01;31:*.jpg=01;35:\
*.jpeg=01;35:*.mjpg=01;35:*.mjpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:\
*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:\
*.tiff=01;35:*.png=01;35:*.svg=01;35:*.svgz=01;35:*.mng=01;35:*.pcx=01;35:\
*.mov=01;35:*.mpg=01;35:*.mpeg=01;35:*.m2v=01;35:*.mkv=01;35:*.webm=01;35:\
*.ogm=01;35:*.mp4=01;35:*.m4v=01;35:*.mp4v=01;35:*.vob=01;35:*.qt=01;35:\
*.nuv=01;35:*.wmv=01;35:*.asf=01;35:*.rm=01;35:*.rmvb=01;35:*.flc=01;35:\
*.avi=01;35:*.fli=01;35:*.flv=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:\
*.xwd=01;35:*.yuv=01;35:*.cgm=01;35:*.emf=01;35:*.ogv=01;35:*.ogx=01;35:\
*.aac=00;36:*.au=00;36:*.flac=00;36:*.m4a=00;36:*.mid=00;36:*.midi=00;36:\
*.mka=00;36:*.mp3=00;36:*.mpc=00;36:*.ogg=00;36:*.ra=00;36:*.wav=00;36:\
*.oga=00;36:*.opus=00;36:*.spx=00;36:*.xspf=00;36:"

# use .localrc for SUPER SECRET CRAP that you don't want in your public, versioned repo.
# shellcheck disable=SC1090
[ -f "$HOME/.localrc" ] && . "$HOME/.localrc"

# on macos, .zprofile is used by some apps, like homebrew ot jetbrains toolbox to set env vars
[ -f "$HOME/.zprofile" ] && . "$HOME/.zprofile"

eval "$(starship init zsh)"
# . "$ZDOTDIR/prompt.zsh"
# zprof
