#!/usr/bin/env zsh

add_regular_file() {
	local source_file="$1"
	local package_name="$2"

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	# Default to 'home' package if not specified
	[ -z "${package_name}" ] && package_name="home"

	local package_dir="${DOTFILES_DIR}/${package_name}"

	# Create package directory if it doesn't exist
	mkdir -p "${package_dir}"

	# Convert path to stow format
	local filename=$(basename "${source_file}")
	local dirname=$(dirname "${source_file}")
	local relative_home_path="${dirname#${HOME}/}"

	# Build target path
	local target_dir="${package_dir}"
	if [ "${relative_home_path}" != "${dirname}" ] && [ "${relative_home_path}" != "." ]; then
		# File is in subdirectory of HOME
		target_dir="${package_dir}/${relative_home_path}"
		mkdir -p "${target_dir}"
	fi

	local stow_filename
	if [[ "${filename}" == .* ]]; then
		# Dotfile - use stow's dot- prefix
		stow_filename="dot-${filename#.}"
	else
		stow_filename="${filename}"
	fi

	local target_file="${target_dir}/${stow_filename}"

	info "Adding ${source_file} to package '${package_name}'"

	# Copy the file
	cp "${source_file}" "${target_file}"
	success "File added as: ${package_name}/${relative_home_path:+${relative_home_path}/}${stow_filename}"

	# Offer to backup/remove original
	if [ -z "${DOT_UNA}" ]; then
		echo ""
		local remove_choice
		user_read "Remove original file? [y/N]" "N" remove_choice
		if [[ "${remove_choice}" =~ ^[Yy] ]]; then
			rm "${source_file}"
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

	if [ -z "${DOT_UNA}" ]; then
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
				# Force encryption
				DOT_FORCE_ENCRYPT=1 flavour_add_file "${source_file}"
				return $?
				;;
			2)
				# Force no encryption
				DOT_FORCE_NO_ENCRYPT=1 flavour_add_file "${source_file}"
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
		# Unattended mode - add to flavour by default
		flavour_add_file "${source_file}"
		return $?
	fi
}
