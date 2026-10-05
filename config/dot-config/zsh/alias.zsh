#!/usr/bin/env zsh

if [ "$(uname -s)" = "Darwin" ]; then
	alias ls="ls -hFG"
else
	# alias ls="ls -F --color"
	alias ls="ls -hN --color=auto --group-directories-first"
fi

# some basics
alias c='clear'
alias ..="cd .."
alias cd..="cd .."
alias l="ls -l"
alias la="ls -A"
alias ll="ls -lAH"

alias cfg="cd $XDG_CONFIG_HOME"
alias dev="cd $XDG_CODE_HOME"

alias lg="lazygit"
alias ldock="lazydocker"
alias cl="claude"
alias oc="opencode"

# quick access to #EDITOR
alias e="$EDITOR"
alias se="sudo $EDITOR"

alias vim='nvim'
alias vi='nvim'

# verbosity and settings that you pretty much just always are going to want.
alias cp="cp -iv"
alias mv="mv -iv"
alias mkd="mkdir -pv"

if [ "$(uname -s)" = "Linux" ]; then
	alias rm="rm -vI"
	alias netlis="netstat -tulpn"
elif [ "$(uname -s)" = "Darwin" ]; then
	# rm moves to the macOS Trash instead (has saved me before). rm-style flags
	# (-r, -f, -i, ...) are dropped so muscle memory keeps working; with -f,
	# missing files are skipped silently like rm does.
	rm() {
		local -a files
		local force=0 opts_done=0 ret=0 arg
		for arg in "$@"; do
			if ((!opts_done)) && [[ $arg == -- ]]; then
				opts_done=1
			elif ((!opts_done)) && [[ $arg == -?* ]]; then
				[[ $arg == -*f* ]] && force=1
			elif [[ -e $arg || -L $arg ]]; then
				[[ $arg == -* ]] && arg="./$arg" # trash has no --
				files+=("$arg")
			elif ((!force)); then
				print -u2 "rm: $arg: No such file or directory"
				ret=1
			fi
		done
		((${#files})) || return $ret
		/usr/bin/trash "${files[@]}" || ret=$?
		return $ret
	}
	alias rrm='command rm -v' # if you really mean it :-)
	alias netlis="netstat -p tcp -van | grep LISTEN"
fi

# more colors
alias grep="grep --color=auto"
alias diff="diff --color=auto"
alias ccat="highlight --out-format=ansi"

# quick hack to make watch work with aliases
alias watch='watch -c -d -t '

alias gic="git_is_clean"
alias be="batch_exec"
alias bep="batch_exec_parallel"

if [ "$(uname -s)" = "Linux" ]; then
	# open, pbcopy and pbpaste on linux
	if [ -z "$(command -v pbcopy)" ]; then
		if [ -n "$(command -v xclip)" ]; then
			alias pbcopy="xclip -selection clipboard"
			alias pbpaste="xclip -selection clipboard -o"
		elif [ -n "$(command -v xsel)" ]; then
			alias pbcopy="xsel --clipboard --input"
			alias pbpaste="xsel --clipboard --output"
		fi
	fi
	if [ -e /usr/bin/xdg-open ]; then
		alias open="xdg-open"
	fi

	alias \
		sys="sudo systemctl"
fi

# Runtime version switching lives in the `setJava` and `setNode` autoloaded
# functions (see ~/.config/zsh/functions), not here.
