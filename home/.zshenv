export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_LOCAL_BIN=$HOME/.local/bin
export XDG_CODE_HOME=$HOME/Dev

export ZDOTDIR=$XDG_CONFIG_HOME/zsh
export EDITOR=nvim
export VISUAL=nvim

export PATH=/opt/homebrew/bin:${PATH}
export PATH=${XDG_LOCAL_BIN}:${PATH}
export PATH=${HOME}/.local/scripts:${PATH}
export PATH=${HOME}/go/bin:${PATH}

setNode() {
	local version=$1
	export PATH="/opt/homebrew/opt/node@${version}/bin:$PATH"

	if [ -z $2 ]; then node --version; fi
}

setJava() {
	local version=$1
	export JAVA_HOME=$(/usr/libexec/java_home -v $version)

	if [ -z $2 ]; then java --version; fi
}

if ! command -v node &>/dev/null; then
	setNode 20 1
fi

if [ -z $JAVA_HOME ]; then
	setJava 21 1
fi

alias java-21="setJava 21"
alias java-11="setJava 11"

alias node-20="setNode 20"
alias node-18="setNode 18"

export HOMEBREW_NO_ENV_HINTS=1

[[ -f .zshenv.local ]] && source .zshenv.local
