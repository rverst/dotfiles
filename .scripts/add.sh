#!/usr/bin/env bash

add_regular_file() {
	local source_file="$1"
	local package_name="$2"

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	local resolved
	resolved=$(resolve_path "${source_file}" 2>/dev/null || true)
	if [ -z "${resolved}" ]; then
		error "Cannot resolve path: ${source_file}"
		return 1
	fi
	source_file="${resolved}"

	if [[ "${source_file}" != "${HOME}"/* ]]; then
		warn "File is outside HOME directory, this might cause issues"
	fi

	[ -z "${package_name}" ] && package_name="home"

	local package_dir="${DOTFILES_DIR}/${package_name}"
	mkdir -p "${package_dir}"

	local filename
	filename=$(basename "${source_file}")
	local dirname
	dirname=$(dirname "${source_file}")
	local relative_home_path="${dirname#${HOME}/}"

	local target_dir="${package_dir}"
	if [ "${relative_home_path}" != "${dirname}" ] && [ "${relative_home_path}" != "." ]; then
		target_dir="${package_dir}/${relative_home_path}"
		mkdir -p "${target_dir}"
	fi

	local stow_filename
	if [[ "${filename}" == .* ]]; then
		stow_filename="dot-${filename#.}"
	else
		stow_filename="${filename}"
	fi

	local target_file="${target_dir}/${stow_filename}"

	info "Adding ${source_file} to package '${package_name}'"

	cp "${source_file}" "${target_file}"
	success "File added as: ${package_name}/${relative_home_path:+${relative_home_path}/}${stow_filename}"

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
		echo "  3) Add to regular package"
		echo ""

		while true; do
			local choice
			user_read "Select option (1-3)" "" choice
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
