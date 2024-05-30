#!/usr/bin/env zsh
#
# utils.sh
# Various helper functions
#
set -o errexit
set -o nounset
set -o pipefail

__dir="$(cd "$(dirname "$0")" && pwd)"

whence info >/dev/null || source "$__dir/functions.sh"

setup_gitconfig() {
	if [ -z "$(git config --global --include --get user.email)" ]; then
		info "Setting up ~/.gitconfig.local"
		local local_config="$HOME/.gitconfig.local"
		local user_name=$(user_read "Your github commit author name?")
		local user_email=$(user_read "Your github commit author email?")
		local gpg_signing=$(user_yesno "Do you want to sign your commits with GPG?" "n")

		if [ ! -z $DOT_DRY ]; then
			info "DRY RUN: Would have written the following to $local_config"
			echo "git config -f $local_config user.name $user_name"
			echo "git config -f $local_config user.email $user_email"
			if [ "$gpg_signing" -eq 1 ]; then
				echo "git config -f $local_config commit.gpgsign true"
				echo "git config -f $local_config tag.gpgsign true"
			fi
		else
			git config -f $local_config user.name "$user_name"
			git config -f $local_config user.email "$user_email"
			if [ "$gpg_signing" -eq 1 ]; then
				git config -f $local_config commit.gpgsign true
				git config -f $local_config tag.gpgsign true
			fi
			success "Done\n"
		fi
	fi
}

setup_localrc() {
	info "Setting up ~/.localrc"
	if [ ! -f "$HOME/.localrc" ]; then
		local localrc="$HOME/.localrc"
		local content="#!/usr/bin/env zsh\n#\n"
		content="$content# This file is sourced by ~/.zshrc\n"
		content="$content# Put your local environment variables here\n#\n"

		if [ ! -z $DOT_DRY ]; then
			info "DRY RUN: Would have written the following to $localrc"
			echo "$content"
		else
			echo "$content" >$localrc
			success "Done\n"
		fi
	else
		skip "  File ~/.localrc already exists\n"
	fi
}
