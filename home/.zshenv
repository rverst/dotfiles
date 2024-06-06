export XDG_CONFIG_HOME=$HOME/.config
export XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share
export XDG_LOCAL_BIN=$HOME/.local/bin

export ZDOTDIR=$XDG_CONFIG_HOME/zsh
export EDITOR=nvim
export VISUAL=nvim

if [ "$(uname -s)" = "Darwin" ]; then
	setNode() {
		local version=$1
		export PATH="$PATH:/opt/homebrew/opt/node@${version}/bin"

		if [ -z $2 ]; then node --version; fi
	}

	local link="/opt/homebrew/opt/node@"

	if [ -L "${link}20" ]; then
		alias node-20="setNode 20"
		setNode 20 1
	fi
	if [ -L "${link}18" ]; then
		alias node-18="setNode 18"
	fi
fi
