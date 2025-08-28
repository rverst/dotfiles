#!/usr/bin/env zsh
#
# print.sh
# Helper functions for printing messages
#

info() {
	[ -z ${DOT_SIL} ] && printf "\r[ \033[00;34m..\033[0m ] $1\n"
}

skip() {
	[ -z ${DOT_SIL} ] && printf "\r[ \033[00;34m->\033[0m ] $1\n"
}

user() {
	[ -z ${DOT_SIL} ] && printf "\r[ \033[0;33m??\033[0m ] $1\n"
}

success() {
	[ -z ${DOT_SIL} ] && printf "\r\033[2K[ \033[00;32mOK\033[0m ] $1\n"
}

warn() {
	[ -z ${DOT_SIL} ] && printf "\r\033[2K[ \033[0;31m!!\033[0m ] $1\n"
}

fail() {
	[ -z ${DOT_SIL} ] && printf "\r\033[2K[ \033[0;31mXX\033[0m ] $1\n"
	[ $# -eq 1 ] && return 0

	echo ''
	exit $2
}

user_read() {
	local prompt="$1"
	local default="${2:-}"
	local var_name="$3"

	if [[ -z ${default} ]]; then
		echo -n "\r[ \033[0;33m??\033[0m ] $prompt: " >&2
	else
		echo -n "\r[ \033[0;33m??\033[0m ] $prompt [$default]: " >&2
	fi

	local input
	read input

	if [[ -z $input ]]; then
		eval "$var_name='$default'"
	else
		eval "$var_name='$input'"
	fi
}

user_yesno() {
	local prompt="$1"
	local default="${2:-n}"
	local var_name="$3"

	local default_display
	if [[ "${default}" =~ ^[Yy] ]]; then
		default_display="Y/n"
	else
		default_display="y/N"
	fi

	echo -n "\r[ \033[0;33m??\033[0m ] $prompt [$default_display]: " >&2

	local input
	read input

	if [[ -z $input ]]; then
		input="$default"
	fi

	if [[ "${input}" =~ ^[Yy] ]]; then
		eval "$var_name=1"
	else
		eval "$var_name=0"
	fi
}
