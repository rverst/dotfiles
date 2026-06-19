#!/usr/bin/env bash

DOTCONFIG_FILE="${HOME}/.dotconfig"

flavour_get_current() {
	local result_var="${1:-}"
	local flavour=""
	if [ -f "${DOTCONFIG_FILE}" ]; then
		flavour=$(git config -f "${DOTCONFIG_FILE}" --get core.flavour 2>/dev/null || true)
	fi
	if [ -z "${flavour}" ]; then
		flavour="$(flavour_prompt_selection)"
		[ -n "${flavour}" ] || return 1
	fi
	if [ -n "${result_var}" ]; then
		printf -v "${result_var}" "%s" "${flavour}"
	else
		echo "${flavour}"
	fi
}

flavour_prompt_selection() {
	if [ -n "${DOT_UNA:-}" ]; then
		echo "server"
		return 0
	fi

	local -a available_flavours=("personal" "work" "server")
	local -a standard_flavours=()

	while IFS= read -r flavour; do
		[ -n "${flavour}" ] && available_flavours+=("${flavour}")
	done < <(flavour_list_available)

	local flavour existing
	for flavour in "${standard_flavours[@]}"; do
		local found=0
		for existing in "${available_flavours[@]}"; do
			if [ "${existing}" = "${flavour}" ]; then
				found=1
				break
			fi
		done
		[ "${found}" -eq 0 ] && available_flavours+=("${flavour}")
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
				echo "${new_flavour}"
				return 0
			else
				warn "Invalid flavour name. Use only letters, numbers, hyphens and underscores." >&2
			fi
		elif [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#available_flavours[@]}" ]; then
			local idx=$((choice - 1))
			echo "${available_flavours[$idx]}"
			return 0
		else
			warn "Invalid selection. Please try again." >&2
		fi
	done
}

flavour_set_current() {
	local flavour="$1"

	if [ "${flavour}" = "common" ]; then
		error "'common' is the shared layer, not a selectable flavour"
		return 1
	fi

	[ -f "${DOTCONFIG_FILE}" ] || : >"${DOTCONFIG_FILE}"

	git config -f "${DOTCONFIG_FILE}" core.flavour "${flavour}"
	success "Flavour set to: ${flavour}"
}

flavour_list_available() {
	local flavours_dir="${DOTFILES_DIR}/flavours"
	[ -d "${flavours_dir}" ] || return 0
	find "${flavours_dir}" -mindepth 1 -type d -prune ! -name 'decrypted-*' ! -name 'common' -exec basename {} \; 2>/dev/null | sort || true
}

# flavour_place_file <content_file> <flavour> <stow_rel> <encrypt:true|false>
# Writes the file into flavours/<flavour>/<stow_rel>(.age). When a decrypted
# workspace for that flavour already exists, the decrypted copy is kept in sync
# so the change is live without a re-decrypt.
flavour_place_file() {
	local content_file="$1"
	local flavour="$2"
	local stow_rel="$3"
	local encrypt="$4"

	local flavour_dir="${DOTFILES_DIR}/flavours/${flavour}"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"
	local target="${flavour_dir}/${stow_rel}"

	mkdir -p "$(dirname "${target}")"

	if [ "${encrypt}" = "true" ]; then
		age_encrypt_file "${content_file}" "${target}.age" || return 1
		# Never trust an .age we cannot read back. If the round-trip fails,
		# discard the bad ciphertext and do not touch the decrypted workspace.
		if ! age_verify_roundtrip "${content_file}" "${target}.age"; then
			error "Encrypted file failed decrypt verification: ${stow_rel}.age"
			rm -f "${target}.age"
			return 1
		fi
		[ -f "${target}" ] && rm -f "${target}"
	else
		cp "${content_file}" "${target}"
		[ -f "${target}.age" ] && rm -f "${target}.age"
	fi

	if [ -d "${decrypted_dir}" ]; then
		local dwork="${decrypted_dir}/${stow_rel}"
		mkdir -p "$(dirname "${dwork}")"
		cp "${content_file}" "${dwork}"
	fi

	return 0
}

# flavour_remove_original <abs> <src>
# Called after a file has been placed (and verified) into a flavour. Verify
# already happened in flavour_place_file; here we ask (unless unattended) and
# then remove the live file plus, if it was a stow symlink, its repo source, so
# stow can relink from the flavour workspace. Returns 0 if removed, 1 if kept.
flavour_remove_original() {
	local abs="$1"
	local src="${2:-}"

	if [ -z "${DOT_UNA:-}" ]; then
		echo ""
		local ans
		user_yesno "Remove original and link it from the flavour?" "y" ans
		if [ "${ans}" -ne 1 ]; then
			warn "Original kept; the file now also lives in the flavour (duplicate)."
			return 1
		fi
	fi

	[ -L "${abs}" ] && rm -f "${abs}"
	if [ -n "${src}" ]; then
		rm -f "${src}"
		rmdir -p "$(dirname "${src}")" 2>/dev/null || true
	elif [ -e "${abs}" ]; then
		rm -f "${abs}"
	fi
	return 0
}

flavour_add_file() {
	local source_file="$1"
	local target_flavour="${2:-}"
	[ -n "${target_flavour}" ] || flavour_get_current target_flavour

	if [ ! -f "${source_file}" ]; then
		error "Source file does not exist: ${source_file}"
		return 1
	fi

	local abs="" rel="" src="" stow_rel under_home=0
	if resolve_home_rel "${source_file}" abs rel src; then
		stow_rel="$(home_to_stow_path "${rel}")"
		under_home=1
	else
		warn "File is outside HOME; it will be added but not removed/relinked"
		stow_rel="$(home_to_stow_path "$(basename "${source_file}")")"
	fi

	info "Adding ${source_file} to flavour '${target_flavour}'"

	local should_encrypt=true
	if [ -n "${DOT_FORCE_NO_ENCRYPT:-}" ]; then
		should_encrypt=false
	elif [ -n "${DOT_FORCE_ENCRYPT:-}" ]; then
		should_encrypt=true
	elif [ -z "${DOT_UNA:-}" ]; then
		echo ""
		local encrypt_choice
		user_yesno "Encrypt this file?" "y" encrypt_choice
		if [ "${encrypt_choice}" -eq 1 ]; then
			should_encrypt=true
		else
			should_encrypt=false
		fi
	fi

	# Read contents from the repo source when the live path is a stow symlink,
	# otherwise from the file itself.
	local content="${source_file}"
	[ "${under_home}" -eq 1 ] && [ -n "${src}" ] && content="${src}"

	if [ -n "${DOT_DRY:-}" ]; then
		local suffix=""
		[ "${should_encrypt}" = "true" ] && suffix=".age"
		info "DRY RUN: would create flavours/${target_flavour}/${stow_rel}${suffix}"
		[ "${under_home}" -eq 1 ] && info "DRY RUN: would remove original ${rel} and relink"
		return 0
	fi

	if ! flavour_place_file "${content}" "${target_flavour}" "${stow_rel}" "${should_encrypt}"; then
		error "Failed to add file to flavour"
		return 1
	fi

	if [ "${should_encrypt}" = "true" ]; then
		success "File encrypted and added as: flavours/${target_flavour}/${stow_rel}.age"
	else
		success "File added as: flavours/${target_flavour}/${stow_rel}"
	fi

	# Adopt: drop the original so stow can relink from the flavour workspace.
	# Only for files under HOME (a stowable target).
	if [ "${under_home}" -eq 1 ]; then
		flavour_remove_original "${abs}" "${src}"
	fi

	return 0
}

# Replace flavour_prepare_stow with this version
flavour_prepare_stow() {
	local flavour="$1"
	local flavour_dir="${DOTFILES_DIR}/flavours/${flavour}"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"

	if [ ! -d "${flavour_dir}" ]; then
		info "No flavour directory for: ${flavour}" >&2
		echo ""
		return 0
	fi

	# Do NOT remove existing decrypted dir; it is the local source-of-truth
	mkdir -p "${decrypted_dir}"

	find "${flavour_dir}" -type f | while IFS= read -r file; do
		local relative_path="${file#${flavour_dir}/}"
		local target_path="${decrypted_dir}/${relative_path}"

		mkdir -p "$(dirname "${target_path}")"

		if [[ "${file}" == *.age ]]; then
			local decrypted_name="${target_path%.age}"

			# If user already has a decrypted file, keep it (do not overwrite their edits)
			if [ -f "${decrypted_name}" ]; then
				continue
			fi

			if age_decrypt_file "${file}" "${decrypted_name}"; then
				info "  ✓ Decrypted ${relative_path}" >&2
			else
				# Create placeholder only if no decrypted file existed
				cat >"${decrypted_name}" <<EOF
# File: ${relative_path}
# Could not decrypt on this machine. Ensure this machine's public key is in .age/recipients.txt,
# then run 'dotfiles reencrypt-all' on a machine that can decrypt, and pull changes.
EOF
				warn "  ✗ Failed to decrypt ${relative_path} - placeholder created" >&2
			fi
		else
			# Unencrypted flavour files: copy into decrypted workspace only if missing
			if [ ! -f "${target_path}" ]; then
				cp "${file}" "${target_path}"
			fi
		fi
	done

	echo "${decrypted_dir}"
}

flavour_cleanup_stow() {
	local flavour="$1"
	local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"
	info "tearing down decrypted flavour directory...${decrypted_dir}" >&2

	[ ! -d "${decrypted_dir}" ] || rm -rf "${decrypted_dir}"
}

# flavour_encrypt_changes [flavour...]
# Syncs each flavour's decrypted workspace back into flavours/<flavour>/.
# Each file is written back in the form it already has (encrypted .age stays
# encrypted, plaintext stays plaintext); brand-new files are encrypted by
# default. With no arguments, processes the current flavour plus 'common'.
flavour_encrypt_changes() {
	local -a flavours=("$@")
	if [ ${#flavours[@]} -eq 0 ]; then
		local current_flavour
		flavour_get_current current_flavour
		flavours=("${current_flavour}")
		[ -d "${DOTFILES_DIR}/flavours/common" ] && flavours+=("common")
	fi

	local flavour
	for flavour in "${flavours[@]}"; do
		local flavour_dir="${DOTFILES_DIR}/flavours/${flavour}"
		local decrypted_dir="${DOTFILES_DIR}/flavours/decrypted-${flavour}"
		[ -d "${decrypted_dir}" ] || continue

		info "Checking for changes in flavour '${flavour}'..."

		find "${decrypted_dir}" -type f | while IFS= read -r decrypted_file; do
			local relative_path="${decrypted_file#${decrypted_dir}/}"
			local encrypted_file="${flavour_dir}/${relative_path}.age"
			local plain_file="${flavour_dir}/${relative_path}"

			if [ -f "${encrypted_file}" ]; then
				local temp_file
				temp_file=$(mktemp)
				if age_decrypt_file "${encrypted_file}" "${temp_file}"; then
					if ! cmp -s "${decrypted_file}" "${temp_file}"; then
						info "  Updating ${relative_path}.age"
						age_encrypt_file "${decrypted_file}" "${encrypted_file}"
					fi
				fi
				rm -f "${temp_file}"
			elif [ -f "${plain_file}" ]; then
				if ! cmp -s "${decrypted_file}" "${plain_file}"; then
					info "  Updating ${relative_path}"
					cp "${decrypted_file}" "${plain_file}"
				fi
			else
				info "  Creating ${relative_path}.age"
				mkdir -p "$(dirname "${encrypted_file}")"
				age_encrypt_file "${decrypted_file}" "${encrypted_file}"
			fi
		done
	done
}
