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
alias oc="opencode"

# quick access to #EDITOR
alias e="$EDITOR"
alias ve="$VEDITOR"
alias se="sudo $EDITOR"

alias vim='nvim'
alias vi='nvim'

# verbosity and settings that you pretty much just always are going to want.
alias cp="cp -iv"
alias mv="mv -iv"
alias mkd="mkdir -pv"

alias ts="tmux-sessionizer"
alias tms="tmux-sessionizer"

if [ "$(uname -s)" = "Linux" ]; then
	alias rm="rm -vI"
elif [ "$(uname -s)" = "Darwin" ]; then
	alias rm="rm -v"
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

if [ "$(uname -s)" = "Darwin" ]; then
	setNode() {
		local version=$1
		export PATH="/opt/homebrew/opt/node@${version}/bin:$PATH"

		if [ -z $2 ]; then node --version; fi
	}

	[ -L "/opt/homebrew/opt/node@24" ] && alias node-24="setNode 24"
	[ -L "/opt/homebrew/opt/node@22" ] && alias node-22="setNode 22"
	[ -L "/opt/homebrew/opt/node@20" ] && alias node-20="setNode 20"
	[ -L "/opt/homebrew/opt/node@18" ] && alias node-18="setNode 18"
	[ -L "/opt/homebrew/opt/node@16" ] && alias node-16="setNode 16"
fi

setJava() {
	local version=$1
	export JAVA_HOME=$(/usr/libexec/java_home -v $version)

	if [ -z $2 ]; then java --version; fi
}

alias java-21="setJava 21"
alias java-11="setJava 11"
