#!/usr/bin/env bash
# Helper functions for printing messages

_info_prefix="\r[ \033[00;34m..\033[0m ] "
_skip_prefix="\r[ \033[00;34m->\033[0m ] "
_user_prefix="\r[ \033[0;33m??\033[0m ] "
_success_prefix="\r\033[2K[ \033[00;32mOK\033[0m ] "
_warn_prefix="\r\033[2K[ \033[0;31m!!\033[0m ] "
_error_prefix="\r\033[2K[ \033[0;31mEE\033[0m ] "
_fail_prefix="\r\033[2K[ \033[0;31mXX\033[0m ] "

info() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_info_prefix}" "${1}"
}

skip() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_skip_prefix}" "${1}"
}

user() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_user_prefix}" "${1}"
}

success() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_success_prefix}" "${1}"
}

warn() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_warn_prefix}" "${1}"
}

error() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_error_prefix}" "${1}"
}

fail() {
	[ -z "${DOT_SIL:-}" ] && printf "%b%s\n" "${_fail_prefix}" "${1}"
	[ $# -eq 1 ] && return 0
	echo ""
	exit "${2}"
}

# Reads input into the variable name passed in $3
user_read() {
	local prompt="$1"
	local default="${2:-}"
	local var_name="$3"

	if [[ ! "${var_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		error "Invalid variable name: ${var_name}"
		return 1
	fi

	if [[ -z "${default}" ]]; then
		printf "%b%s: " "${_user_prefix}" "${prompt}" >&2
	else
		printf "%b%s [%s]: " "${_user_prefix}" "${prompt}" "${default}" >&2
	fi

	local input
	IFS= read -r input

	if [[ -z "${input}" ]]; then
		printf -v "${var_name}" "%s" "${default}"
	else
		printf -v "${var_name}" "%s" "${input}"
	fi
}

# Sets var_name to 1 for yes, 0 for no
user_yesno() {
	local prompt="$1"
	local default="${2:-n}"
	local var_name="$3"

	if [[ ! "${var_name}" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
		error "Invalid variable name: ${var_name}"
		return 1
	fi

	local default_display
	if [[ "${default}" =~ ^[Yy]$ ]]; then
		default_display="Y/n"
	else
		default_display="y/N"
	fi

	printf "%b%s [%s]: " "${_user_prefix}" "${prompt}" "${default_display}" >&2

	local input
	IFS= read -r input
	if [[ -z "${input}" ]]; then
		input="${default}"
	fi

	if [[ "${input}" =~ ^[Yy]$ ]]; then
		printf -v "${var_name}" "%d" 1
	else
		printf -v "${var_name}" "%d" 0
	fi
}
