#!/usr/bin/env bash

# Default regular package for a $HOME-relative path. Files under ~/.config are
# owned by the 'config' package and files under ~/.local by the 'local' package;
# everything else defaults to 'home'. Keeps each of those trees from getting split
# across multiple packages over time.
_regular_default_package() {
	case "$1" in
	.config/*) echo "config" ;;
	.local/*) echo "local" ;;
	*) echo "home" ;;
	esac
	return 0
}

add_regular_file() {
	local source_file="$1"
	local package_name="$2"

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	local abs rel src
	if ! resolve_home_rel "${source_file}" abs rel src; then
		warn "File is outside HOME directory, this might cause issues"
		rel="$(basename "${source_file}")"
		abs="${source_file}"
	fi
	source_file="${abs}"

	[ -z "${package_name}" ] && package_name="$(_regular_default_package "${rel}")"

	local package_dir="${DOTFILES_DIR}/${package_name}"
	local stow_rel
	stow_rel="$(home_to_stow_path "${rel}")"
	local target_file="${package_dir}/${stow_rel}"

	info "Adding ${source_file} to package '${package_name}'"

	if [ -n "${DOT_DRY:-}" ]; then
		info "DRY RUN: would add ${package_name}/${stow_rel}"
		[ -z "${DOT_UNA:-}" ] && info "DRY RUN: would prompt to remove original ${source_file}"
		return 0
	fi

	mkdir -p "$(dirname "${target_file}")"
	cp "${source_file}" "${target_file}"
	success "File added as: ${package_name}/${stow_rel}"

	if [ -n "${DOT_DEFER_REMOVE:-}" ]; then
		# Directory add: removal happens once, after all files succeeded
		_DOT_DEFERRED+=("${source_file}|")
	elif [ -z "${DOT_UNA:-}" ]; then
		echo ""
		local remove_choice
		user_read "Remove original file? [y/N]" "N" remove_choice
		if [[ "${remove_choice}" =~ ^[Yy]$ ]]; then
			rm -f -- "${source_file}"
			info "Original file removed"
		else
			info "Original file kept (remember to remove it manually if needed)"
		fi
	fi

	return 0
}

# move_to_flavour <file> <target_flavour>
# Moves a file currently provided by a regular package into a flavour layer
# (encrypted by default). Removes the regular source and materializes the file
# in the flavour's decrypted workspace. Caller is responsible for restowing.
move_to_flavour() {
	local file="$1"
	local target_flavour="${2:-}"
	[ -n "${target_flavour}" ] || flavour_get_current target_flavour

	local abs rel src
	if ! resolve_home_rel "${file}" abs rel src; then
		error "Path is not under \$HOME: ${file}"
		return 1
	fi

	if [ ! -e "${abs}" ]; then
		error "File does not exist: ${abs}"
		return 1
	fi

	if [ -n "${src}" ] && [[ "${src}" == "${DOTFILES_DIR}/flavours/"* ]]; then
		error "File already belongs to a flavour layer: ${src#${DOTFILES_DIR}/}"
		return 1
	fi

	local stow_rel
	stow_rel="$(home_to_stow_path "${rel}")"

	local should_encrypt=true
	[ -n "${DOT_FORCE_NO_ENCRYPT:-}" ] && should_encrypt=false

	# Read contents from the repo source when it is a stow symlink, else the file
	local content="${abs}"
	[ -n "${src}" ] && content="${src}"
	if [ ! -f "${content}" ]; then
		error "Cannot read file contents: ${content}"
		return 1
	fi

	local suffix=""
	[ "${should_encrypt}" = "true" ] && suffix=".age"

	info "Moving ${rel} -> flavour '${target_flavour}'"

	if [ -n "${DOT_DRY:-}" ]; then
		info "DRY RUN: would create flavours/${target_flavour}/${stow_rel}${suffix}"
		[ -n "${src}" ] && info "DRY RUN: would remove regular source ${src#${DOTFILES_DIR}/}"
		return 0
	fi

	if ! flavour_place_file "${content}" "${target_flavour}" "${stow_rel}" "${should_encrypt}"; then
		error "Failed to place file into flavour"
		return 1
	fi

	# Drop the live link/file and the regular source so stow can relink from the
	# flavour workspace on the next restow (verify already passed in
	# flavour_place_file; this asks before deleting unless unattended).
	flavour_remove_original "${abs}" "${src}"

	success "Moved to flavours/${target_flavour}/${stow_rel}${suffix}"
	return 0
}

# copy_flavour_file <file> <from_flavour> <to_flavour>
# Copies a file from one flavour into another as a template. The source may be
# encrypted (.age) or plaintext; the destination is encrypted by default.
copy_flavour_file() {
	local file="$1"
	local from_flavour="$2"
	local to_flavour="$3"

	if [ -z "${from_flavour}" ] || [ -z "${to_flavour}" ]; then
		error "copy requires <from-flavour> and <to-flavour>"
		return 1
	fi
	if [ "${from_flavour}" = "${to_flavour}" ]; then
		error "Source and target flavour are the same"
		return 1
	fi

	# Accept a stow-style path (dot-config/...) or a $HOME-style path (.config/...)
	local stow_rel
	case "${file}" in
	dot-* | */dot-*)
		stow_rel="${file#./}"
		;;
	*)
		case "${file}" in
		"~/"*) file="${HOME}/${file#\~/}" ;;
		esac
		local rel="${file#${HOME}/}"
		rel="${rel#./}"
		stow_rel="$(home_to_stow_path "${rel}")"
		;;
	esac

	local from_dir="${DOTFILES_DIR}/flavours/${from_flavour}"
	local src_enc="${from_dir}/${stow_rel}.age"
	local src_plain="${from_dir}/${stow_rel}"

	local tmp
	tmp="$(mktemp)"

	if [ -f "${src_enc}" ]; then
		if ! age_decrypt_file "${src_enc}" "${tmp}"; then
			error "Failed to decrypt source: flavours/${from_flavour}/${stow_rel}.age"
			rm -f "${tmp}"
			return 1
		fi
	elif [ -f "${src_plain}" ]; then
		cp "${src_plain}" "${tmp}"
	else
		error "Source not found in flavour '${from_flavour}': ${stow_rel}"
		rm -f "${tmp}"
		return 1
	fi

	local should_encrypt=true
	[ -n "${DOT_FORCE_NO_ENCRYPT:-}" ] && should_encrypt=false
	local suffix=""
	[ "${should_encrypt}" = "true" ] && suffix=".age"

	if [ -n "${DOT_DRY:-}" ]; then
		info "DRY RUN: would copy flavours/${from_flavour}/${stow_rel} -> flavours/${to_flavour}/${stow_rel}${suffix}"
		rm -f "${tmp}"
		return 0
	fi

	local rc=0
	if flavour_place_file "${tmp}" "${to_flavour}" "${stow_rel}" "${should_encrypt}"; then
		success "Copied to flavours/${to_flavour}/${stow_rel}${suffix}"
	else
		error "Failed to write into flavour '${to_flavour}'"
		rc=1
	fi
	rm -f "${tmp}"
	return "${rc}"
}

add_file_interactive() {
	local source_file="$1"

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	if [ -z "${DOT_UNA:-}" ]; then
		echo ""
		info "Add file: ${source_file}"
		echo ""
		echo "  1) Add to current flavour ($(flavour_get_current)) - encrypted"
		echo "  2) Add to current flavour ($(flavour_get_current)) - unencrypted"
		echo "  3) Add to common layer (shared, always applied) - encrypted"
		echo "  4) Add to regular package"
		echo ""

		local current_flavour
		flavour_get_current current_flavour

		while true; do
			local choice
			user_read "Select option (1-4)" "" choice
			case "${choice}" in
			1)
				local DOT_FORCE_ENCRYPT=1
				flavour_add_file "${source_file}" "${current_flavour}" &&
					_add_restow_if_active "${current_flavour}"
				return $?
				;;
			2)
				local DOT_FORCE_NO_ENCRYPT=1
				flavour_add_file "${source_file}" "${current_flavour}" &&
					_add_restow_if_active "${current_flavour}"
				return $?
				;;
			3)
				local DOT_FORCE_ENCRYPT=1
				flavour_add_file "${source_file}" "common" &&
					_add_restow_if_active "common"
				return $?
				;;
			4)
				local package_name abs rel src default_pkg="home"
				if resolve_home_rel "${source_file}" abs rel src; then
					default_pkg="$(_regular_default_package "${rel}")"
				fi
				user_read "Enter package name" "${default_pkg}" package_name
				add_regular_file "${source_file}" "${package_name}"
				return $?
				;;
			*)
				warn "Invalid selection. Please try again."
				;;
			esac
		done
	else
		flavour_add_file "${source_file}"
		return $?
	fi
}

# _add_list_dir_files <dir> <array_var>
# Collects all files below <dir> (following symlinks, including hidden files),
# skipping .git directories and .DS_Store. Sorted for a predictable order.
_add_list_dir_files() {
	local dir="$1"
	local __alf_var="$2"
	local __alf_f
	eval "${__alf_var}=()"
	while IFS= read -r -d '' __alf_f; do
		eval "${__alf_var}+=(\"\${__alf_f}\")"
	done < <(find -L "${dir}" -name .git -prune -o -type f ! -name .DS_Store -print0 | LC_ALL=C sort -z)
}

# _add_select_encryption
# Asks once how a directory batch should be encrypted. Sets DOT_FORCE_ENCRYPT /
# DOT_FORCE_NO_ENCRYPT for "all"/"none"; leaves both unset for "mixed" so
# flavour_add_file asks per file. Caller must declare both as locals.
_add_select_encryption() {
	[ -n "${DOT_FORCE_NO_ENCRYPT:-}" ] && return 0
	if [ -n "${DOT_UNA:-}" ]; then
		DOT_FORCE_ENCRYPT=1
		return 0
	fi
	echo ""
	echo "  1) Encrypt all files"
	echo "  2) Encrypt none"
	echo "  3) Mixed - ask per file"
	echo ""
	while true; do
		local choice
		user_read "Select option (1-3)" "1" choice
		case "${choice}" in
		1) DOT_FORCE_ENCRYPT=1 && return 0 ;;
		2) DOT_FORCE_NO_ENCRYPT=1 && return 0 ;;
		3) return 0 ;;
		*) warn "Invalid selection. Please try again." ;;
		esac
	done
}

# add_directory <dir> [flavour|common|regular] [flavour-name|package]
# Adds every file below <dir> using the per-file add functions. Questions are
# asked once for the whole batch. Originals are only removed when every file was
# added successfully. Sets _DOT_ADD_LAYER to the flavour layer that was written
# (empty for regular packages) so the caller can restow.
add_directory() {
	local dir="${1%/}"
	local add_type="${2:-}"
	local arg="${3:-}"
	_DOT_ADD_LAYER=""

	if [ ! -d "${dir}" ]; then
		error "Directory does not exist: ${dir}"
		return 1
	fi

	local files=()
	_add_list_dir_files "${dir}" files
	if [ "${#files[@]}" -eq 0 ]; then
		error "Directory contains no files: ${dir}"
		return 1
	fi

	info "Adding ${#files[@]} files from ${dir}:"
	local f
	for f in "${files[@]}"; do
		echo "    ${f#${dir}/}"
	done

	if [ -z "${DOT_UNA:-}" ]; then
		echo ""
		local ok
		user_yesno "Continue?" "y" ok
		[ "${ok}" -eq 1 ] || {
			info "Aborted"
			return 1
		}
	fi

	local current_flavour
	flavour_get_current current_flavour

	if [ -z "${add_type}" ]; then
		if [ -n "${DOT_UNA:-}" ]; then
			add_type="flavour"
		else
			echo ""
			echo "  1) Add to current flavour (${current_flavour})"
			echo "  2) Add to common layer (shared, always applied)"
			echo "  3) Add to regular package"
			echo ""
			while [ -z "${add_type}" ]; do
				local choice
				user_read "Select option (1-3)" "" choice
				case "${choice}" in
				1) add_type="flavour" ;;
				2) add_type="common" ;;
				3)
					add_type="regular"
					local abs rel src default_pkg="home"
					if resolve_home_rel "${dir}" abs rel src; then
						default_pkg="$(_regular_default_package "${rel}/")"
					fi
					user_read "Enter package name" "${default_pkg}" arg
					;;
				*) warn "Invalid selection. Please try again." ;;
				esac
			done
		fi
	fi

	local DOT_FORCE_ENCRYPT="${DOT_FORCE_ENCRYPT:-}"
	local DOT_FORCE_NO_ENCRYPT="${DOT_FORCE_NO_ENCRYPT:-}"
	case "${add_type}" in
	flavour)
		_DOT_ADD_LAYER="${arg:-${current_flavour}}"
		_add_select_encryption
		;;
	common)
		_DOT_ADD_LAYER="common"
		_add_select_encryption
		;;
	regular | package) ;;
	*)
		error "Invalid add type: ${add_type}"
		return 1
		;;
	esac

	local DOT_DEFER_REMOVE=1
	_DOT_DEFERRED=()
	local added=0 failed=0
	for f in "${files[@]}"; do
		local rc=0
		if [ -n "${_DOT_ADD_LAYER}" ]; then
			flavour_add_file "${f}" "${_DOT_ADD_LAYER}" || rc=$?
		else
			add_regular_file "${f}" "${arg}" || rc=$?
		fi
		if [ "${rc}" -eq 0 ]; then
			added=$((added + 1))
		else
			failed=$((failed + 1))
		fi
	done

	echo ""
	info "Added ${added}, failed ${failed}"

	[ -n "${DOT_DRY:-}" ] && return 0

	if [ "${failed}" -gt 0 ]; then
		warn "Not all files were added; originals were kept in ${dir}"
		return 1
	fi

	_add_remove_deferred "${dir}"
	return 0
}

# _add_remove_deferred <dir>
# Asks once, then removes all originals recorded in _DOT_DEFERRED and prunes
# empty directories below (and including) <dir>.
_add_remove_deferred() {
	local dir="$1"
	[ "${#_DOT_DEFERRED[@]}" -gt 0 ] || return 0

	if [ -z "${DOT_UNA:-}" ]; then
		echo ""
		local ans
		user_yesno "Remove originals in ${dir}?" "y" ans
		if [ "${ans}" -ne 1 ]; then
			warn "Originals kept (remember to remove them manually if needed)"
			return 0
		fi
	fi

	local entry
	for entry in "${_DOT_DEFERRED[@]}"; do
		DOT_UNA=1 flavour_remove_original "${entry%%|*}" "${entry#*|}"
	done
	if [ ! -L "${dir}" ]; then
		find "${dir}" -depth -type d -empty -delete 2>/dev/null || true
	fi
	info "Originals removed"
	return 0
}
