#!/usr/bin/env bash

# Various helper functions, sourced by main script.

setup_gitconfig() {
	if [ -z "$(git config --global --include --get user.email 2>/dev/null || true)" ]; then
		info "Setting up ~/.gitconfig.local"
		local local_config="$HOME/.gitconfig.local"

		local user_name
		user_read "Your github commit author name?" "" user_name

		local user_email
		user_read "Your github commit author email?" "" user_email

		local gpg_signing
		user_yesno "Do you want to sign your commits with GPG?" "n" gpg_signing

		if [ -n "${DOT_DRY:-}" ]; then
			info "DRY RUN: Would have written the following to ${local_config}"
			echo "git config -f ${local_config@Q} user.name ${user_name@Q}"
			echo "git config -f ${local_config@Q} user.email ${user_email@Q}"
			if [ "${gpg_signing}" -eq 1 ]; then
				echo "git config -f ${local_config@Q} commit.gpgsign true"
				echo "git config -f ${local_config@Q} tag.gpgsign true"
			fi
		else
			git config -f "${local_config}" user.name "${user_name}"
			git config -f "${local_config}" user.email "${user_email}"
			if [ "${gpg_signing}" -eq 1 ]; then
				git config -f "${local_config}" commit.gpgsign true
				git config -f "${local_config}" tag.gpgsign true
			fi
			success "Done"
		fi
	fi
}

setup_localrc() {
	info "Setting up ~/.localrc"
	local localrc="$HOME/.localrc"
	if [ ! -f "${localrc}" ]; then
		if [ -n "${DOT_DRY:-}" ]; then
			info "DRY RUN: Would have written a default ~/.localrc"
		else
			cat >"${localrc}" <<'EOF'
#!/usr/bin/env zsh
#
# This file is sourced by ~/.zshrc
# Put your local environment variables here
#
EOF
			success "Done"
		fi
	else
		skip "File ~/.localrc already exists"
	fi
}
