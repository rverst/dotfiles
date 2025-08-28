#!/usr/bin/env bash

DOTCONFIG_FILE="${HOME}/.dotconfig"

flavour_get_current() {
	if [ -f "${DOTCONFIG_FILE}" ]; then
		local flavour
		flavour=$(git config -f "${DOTCONFIG_FILE}" core.flavour 2>/dev/null || true)
		if [ -n "${flavour}" ]; then
			echo "${flavour}"
			return 0
		fi
	fi

	flavour_prompt_selection
}

flavour_prompt_selection() {
	if [ -n "${DOT_UNA:-}" ]; then
		echo "server"
		return 0
	fi

	local available_flavours=()
	local standard_flavours=("work" "personal" "server")

	while IFS= read -r flavour; do
		[ -n "${flavour}" ] && available_flavours+=("${flavour}")
	done < <(flavour_list_available)

	for std_flavour in "${standard_flavours[@]}"; do
		if [[ ! " ${available_flavours[*]} " =~ " ${std_flavour} " ]]; then
			available_flavours+=("${std_flavour}")
		fi
	done

	echo "" >&2
	info "No flavour configured. Please select a flavour:" >&2
	echo "" >&2
	local j=1
	for flavour in "${available_flavours[@]}"; do
		echo "  ${j}) ${flavour}" >&2
		((j++))
	done
	echo "  c) Create new flavour" >&2
	echo "" >&2

	while true; do
		local choice
		user_read "Select flavour (1-${#available_flavours[@]}, 'c' for custom)" "" choice

		if [ "${choice}" = "c" ]; then
			local new_flavour
			user_read "Enter new flavour name" "" new_flavour
			if [[ "${new_flavour}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
				flavour_set_current "${new_flavour}"
				echo "${new_flavour}"
				return 0
			else
				warn "Invalid flavour name. Use only letters, numbers, hyphens and underscores." >&2
				continue
			fi
		elif [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#available_flavours[@]}" ]; then
			local idx=$((choice - 1))
			local selected_flavour="${available_flavours[$idx]}"
			flavour_set_current "${selected_flavour}"
			echo "${selected_flavour}"
			return 0
		else
			warn "Invalid selection. Please try again." >&2
			echo "" >&2
			local j=1
			for flavour in "${available_flavours[@]}"; do
				echo "  ${j}) ${flavour}" >&2
				((j++))
			done
			echo "  c) Create new flavour" >&2
			echo "" >&2
		fi
	done
}

flavour_set_current() {
	local flavour="$1"

	[ -f "${DOTCONFIG_FILE}" ] || : >"${DOTCONFIG_FILE}"

	git config -f "${DOTCONFIG_FILE}" core.flavour "${flavour}"
	success "Flavour set to: ${flavour}"
}

flavour_list_available() {
	local flavours_dir="${DOTFILES_DIR}/flavours"
	[ -d "${flavours_dir}" ] || return 0

	find "${flavours_dir}" -mindepth 1 -maxdepth 1 -type d ! -name 'decrypted-*' -printf '%f\n' 2>/dev/null | sort || true
}

flavour_add_file() {
	local source_file="$1"
	local current_flavour
	current_flavour=$(flavour_get_current)
	local flavour_dir="${DOTFILES_DIR}/flavours/${current_flavour}"

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	local filename
	filename=$(basename "${source_file}")
	local stow_filename

	if [[ "${filename}" == .* ]]; then
		stow_filename="dot-${filename#.}"
	else
		stow_filename="dot-${filename}"
	fi

	local target_file="${flavour_dir}/${stow_filename}"
	local encrypted_file="${target_file}.age"

	mkdir -p "${flavour_dir}"

	info "Adding ${source_file} to flavour '${current_flavour}'"

	local should_encrypt=false

	if [ -n "${DOT_FORCE_ENCRYPT:-}" ]; then
		should_encrypt=true
	elif [ -n "${DOT_FORCE_NO_ENCRYPT:-}" ]; then
		should_encrypt=false
	else
		if [[ "${filename}" == *"secret"* ]] || [[ "${filename}" == *"private"* ]] || [[ "${filename}" == *"key"* ]] ||
			[[ "${filename}" == *"token"* ]] || [[ "${filename}" == *"password"* ]] || [[ "${filename}" == ".gitconfig"* ]] ||
			[[ "${filename}" == ".zshrc"* ]] || [[ "${filename}" == ".bashrc"* ]] || [[ "${filename}" == ".profile"* ]]; then
			should_encrypt=true
		fi

		if [ -z "${DOT_UNA:-}" ]; then
			echo ""
			local encrypt_choice
			if [ "${should_encrypt}" = true ]; then
				user_yesno "Encrypt this file?" "y" encrypt_choice
				[ -z "${encrypt_choice}" ] && encrypt_choice=1
			else
				user_yesno "Encrypt this file?" "n" encrypt_choice
				[ -z "${encrypt_choice}" ] && encrypt_choice=0
			fi
			if [ "${encrypt_choice}" -eq 1 ]; then
				should_encrypt=true
			else
				should_encrypt=false
			fi
		fi
	fi

	if [ "${should_encrypt}" = true ]; then
		if age_encrypt_file "${source_file}" "${encrypted_file}"; then
			success "File encrypted and added as: flavours/${current_flavour}/${stow_filename}.age"
			info "Original file: ${source_file}"
			info "Encrypted file: ${encrypted_file}"
		else
			error "Failed to encrypt file"
			return 1
		fi
	else
		cp "${source_file}" "${target_file}"
		success "File added as: flavours/${current_flavour}/${stow_filename}"
	fi

	return 0
}

flavour_prepare_stow() {
	local flavour="$1"
	local flavour_dir="${DOTFILES_DIR}/flavours/${flavour}"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"

	if [ ! -d "${flavour_dir}" ]; then
		info "No flavour directory for: ${flavour}"
		return 0
	fi

	[ ! -d "${decrypted_dir}" ] || rm -rf "${decrypted_dir}"
	mkdir -p "${decrypted_dir}"

	find "${flavour_dir}" -type f | while IFS= read -r file; do
		local relative_path="${file#${flavour_dir}/}"
		local target_path="${decrypted_dir}/${relative_path}"

		mkdir -p "$(dirname "${target_path}")"

		if [[ "${file}" == *.age ]]; then
			local decrypted_name="${target_path%.age}"
			if age_decrypt_file "${file}" "${decrypted_name}"; then
				info "  ✓ Decrypted ${relative_path}"
			else
				cat >"${decrypted_name}" <<EOF
# File: ${relative_path}
# Could not decrypt on this machine. Ensure this machine's public key is in .age/recipients.txt,
# then run 'dotfiles reencrypt-all' on a machine that can decrypt, and pull changes.
EOF
				warn "  ✗ Failed to decrypt ${relative_path} - placeholder created"
			fi
		else
			cp "${file}" "${target_path}"
		fi
	done

	echo "${decrypted_dir}"
}

flavour_cleanup_stow() {
	local flavour="$1"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"

	[ ! -d "${decrypted_dir}" ] || rm -rf "${decrypted_dir}"
}

flavour_encrypt_changes() {
	local current_flavour
	current_flavour=$(flavour_get_current)
	local flavour_dir="${DOTFILES_DIR}/flavours/${current_flavour}"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${current_flavour}"

	[ -d "${decrypted_dir}" ] || return 0

	info "Checking for changes in flavour files..."

	find "${decrypted_dir}" -type f | while IFS= read -r decrypted_file; do
		local relative_path="${decrypted_file#${decrypted_dir}/}"
		local encrypted_file="${flavour_dir}/${relative_path}.age"
		local temp_file
		temp_file=$(mktemp)

		if [[ "${relative_path}" == dot-* ]] || [[ "${relative_path}" == *secret* ]] || [[ "${relative_path}" == *private* ]]; then
			if [ -f "${encrypted_file}" ]; then
				if age_decrypt_file "${encrypted_file}" "${temp_file}"; then
					if ! cmp -s "${decrypted_file}" "${temp_file}"; then
						info "  Updating ${relative_path}.age"
						age_encrypt_file "${decrypted_file}" "${encrypted_file}"
					fi
				fi
			else
				info "  Creating ${relative_path}.age"
				mkdir -p "$(dirname "${encrypted_file}")"
				age_encrypt_file "${decrypted_file}" "${encrypted_file}"
			fi
		fi

		rm -f "${temp_file}"
	done
}
