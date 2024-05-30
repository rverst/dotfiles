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
	if [[ -z ${2-} ]]; then
		echo -n "\r[ \033[0;33m??\033[0m ] $1: " >&2
	else
		echo -n "\r[ \033[0;33m??\033[0m ] $1 [$2]: " >&2
	fi
	read input
	[[ -z $input ]] && echo $2 || echo $input
}

user_yesno() {
	[[ -z ${2-} ]] && 2="n"
	if [[ $2 == "y" || $2 == "Y" ]]; then
		echo -n "\r[ \033[0;33m??\033[0m ] $1 [Y/n]: " >&2
	else
		echo -n "\r[ \033[0;33m??\033[0m ] $1 [y/N]: " >&2
	fi
	read input
	[[ -z $input ]] && input=$2
	[[ $input == "y" || $input == "Y" ]] && echo 1 || echo 0
}
