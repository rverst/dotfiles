#!/usr/bin/env bash

# Various helper functions, sourced by main script.

resolve_path() {
	local path="$1"
	if command -v realpath >/dev/null 2>&1; then
		realpath "$path" 2>/dev/null && return 0
	fi
	if command -v readlink >/dev/null 2>&1; then
		readlink -f "$path" 2>/dev/null && return 0
	fi
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" && return 0
	fi
	if command -v python >/dev/null 2>&1; then
		python -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path" && return 0
	fi
	if command -v perl >/dev/null 2>&1; then
		perl -MCwd=realpath -e 'print realpath($ARGV[0])' "$path" && return 0
	fi
	# Best-effort fallback
	(cd "$(dirname "$path")" 2>/dev/null && printf "%s/%s\n" "$PWD" "$(basename "$path")") || echo "$path"
}

# home_to_stow_path <home-relative-path>
# Converts a $HOME-relative path into a `stow --dotfiles` path: every path
# component that starts with a dot becomes "dot-<rest>". Echoes the result.
#   .config/nvim/init.lua -> dot-config/nvim/init.lua
#   .zshrc                -> dot-zshrc
home_to_stow_path() {
	local rel="$1"
	local out="" part
	local old_ifs="$IFS"
	IFS='/'
	set -f
	for part in $rel; do
		[ -z "$part" ] && continue
		if [[ "$part" == .* ]]; then
			part="dot-${part#.}"
		fi
		out="${out:+${out}/}${part}"
	done
	set +f
	IFS="$old_ifs"
	printf '%s' "$out"
}

# stow_to_home_path <stow-path>
# Inverse of home_to_stow_path: "dot-" prefixed components become ".".
#   dot-config/nvim/init.lua -> .config/nvim/init.lua
stow_to_home_path() {
	local rel="$1"
	local out="" part
	local old_ifs="$IFS"
	IFS='/'
	set -f
	for part in $rel; do
		[ -z "$part" ] && continue
		if [[ "$part" == dot-* ]]; then
			part=".${part#dot-}"
		fi
		out="${out:+${out}/}${part}"
	done
	set +f
	IFS="$old_ifs"
	printf '%s' "$out"
}

# resolve_home_rel <path> <abs_var> <rel_var> <src_var>
# Resolves a (possibly ~-prefixed or relative) path and writes:
#   abs_var: absolute path of the live location under $HOME
#   rel_var: path relative to $HOME (e.g. .config/foo/bar)
#   src_var: if the live path is a stow symlink into DOTFILES_DIR, the resolved
#            repo source file; otherwise empty
# Returns non-zero if the path is not under $HOME.
resolve_home_rel() {
	local input="$1"
	local abs_var="$2"
	local rel_var="$3"
	local src_var="$4"

	case "${input}" in
	"~") input="${HOME}" ;;
	"~/"*) input="${HOME}/${input#\~/}" ;;
	esac

	# Internal names are prefixed to avoid colliding with the caller's variable
	# names passed in *_var (printf -v would otherwise target our own locals).
	local __rhr_dir __rhr_base __rhr_abs __rhr_rel __rhr_src
	__rhr_dir="$(cd "$(dirname "${input}")" 2>/dev/null && pwd)" || return 1
	__rhr_base="$(basename "${input}")"
	__rhr_abs="${__rhr_dir%/}/${__rhr_base}"

	if [ "${__rhr_abs#${HOME}/}" = "${__rhr_abs}" ]; then
		return 1
	fi
	__rhr_rel="${__rhr_abs#${HOME}/}"

	__rhr_src=""
	if [ -L "${__rhr_abs}" ]; then
		__rhr_src="$(resolve_path "${__rhr_abs}")"
		# Canonicalize the repo root too, so the prefix check is not defeated by
		# symlinked path components (e.g. macOS /var -> /private/var).
		local __rhr_root
		__rhr_root="$(resolve_path "${DOTFILES_DIR}")"
		if [ "${__rhr_src#${__rhr_root}/}" = "${__rhr_src}" ]; then
			__rhr_src=""
		fi
	fi

	printf -v "${abs_var}" "%s" "${__rhr_abs}"
	printf -v "${rel_var}" "%s" "${__rhr_rel}"
	printf -v "${src_var}" "%s" "${__rhr_src}"
	return 0
}

setup_gitconfig() {
	if [ -z "$(git config --global --get user.email 2>/dev/null || true)" ]; then
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
