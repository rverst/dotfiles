#!/usr/bin/env bash

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

	[ -z "${package_name}" ] && package_name="home"

	local package_dir="${DOTFILES_DIR}/${package_name}"
	local stow_rel
	stow_rel="$(home_to_stow_path "${rel}")"
	local target_file="${package_dir}/${stow_rel}"

	info "Adding ${source_file} to package '${package_name}'"

	mkdir -p "$(dirname "${target_file}")"
	cp "${source_file}" "${target_file}"
	success "File added as: ${package_name}/${stow_rel}"

	if [ -z "${DOT_UNA:-}" ]; then
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
	# flavour workspace on the next restow.
	[ -L "${abs}" ] && rm -f "${abs}"
	if [ -n "${src}" ]; then
		rm -f "${src}"
		rmdir -p "$(dirname "${src}")" 2>/dev/null || true
	elif [ -f "${abs}" ]; then
		rm -f "${abs}"
	fi

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

		while true; do
			local choice
			user_read "Select option (1-4)" "" choice
			case "${choice}" in
			1)
				local DOT_FORCE_ENCRYPT=1
				flavour_add_file "${source_file}"
				return $?
				;;
			2)
				local DOT_FORCE_NO_ENCRYPT=1
				flavour_add_file "${source_file}"
				return $?
				;;
			3)
				local DOT_FORCE_ENCRYPT=1
				flavour_add_file "${source_file}" "common"
				return $?
				;;
			4)
				local package_name
				user_read "Enter package name" "home" package_name
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
