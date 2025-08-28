#!/usr/bin/env zsh

AGE_DIR="${DOTFILES_DIR}/.age"
AGE_KEYS_FILE="${AGE_DIR}/keys.txt"
AGE_RECIPIENTS_FILE="${AGE_DIR}/recipients.txt"

age_init() {
	info "Initializing Age encryption..."

	if [ ! -d "${AGE_DIR}" ]; then
		mkdir -p "${AGE_DIR}"
	fi

	# Generate new keypair if none exists
	if [ ! -f "${AGE_KEYS_FILE}" ]; then
		info "Generating new Age keypair..."
		age-keygen -o "${AGE_KEYS_FILE}" 2>/dev/null
		chmod 600 "${AGE_KEYS_FILE}"

		# Extract public key and add to recipients
		local pubkey=$(age-keygen -y "${AGE_KEYS_FILE}")
		echo "# Machine: $(hostname) - $(date)" >>"${AGE_RECIPIENTS_FILE}"
		echo "${pubkey}" >>"${AGE_RECIPIENTS_FILE}"
		echo "" >>"${AGE_RECIPIENTS_FILE}"

		success "New Age keypair generated"
		info "Public key added to recipients file"
	fi

	# Test if we can decrypt existing files
	if ! age_can_decrypt_existing; then
		warn "Cannot decrypt existing encrypted files"
		info "Adding this machine's public key to recipients..."

		local pubkey=$(age-keygen -y "${AGE_KEYS_FILE}")
		echo "# Machine: $(hostname) - $(date)" >>"${AGE_RECIPIENTS_FILE}"
		echo "${pubkey}" >>"${AGE_RECIPIENTS_FILE}"
		echo "" >>"${AGE_RECIPIENTS_FILE}"

		warn "Re-encryption needed on a machine that can decrypt existing files"
		warn "Run 'dotfiles reencrypt-all' on another machine, then pull changes"
		return 1
	fi

	return 0
}

age_can_decrypt_existing() {
	local test_files=$(find "${DOTFILES_DIR}/flavours" -name "*.age" -type f | head -1)
	if [ -n "${test_files}" ]; then
		echo "test" | age -d -i "${AGE_KEYS_FILE}" "${test_files}" >/dev/null 2>&1
		return $?
	fi
	return 0
}

age_encrypt_file() {
	local input_file="$1"
	local output_file="$2"

	if [ ! -f "${AGE_RECIPIENTS_FILE}" ] || [ ! -s "${AGE_RECIPIENTS_FILE}" ]; then
		error "No recipients file found or empty"
		return 1
	fi

	age -R "${AGE_RECIPIENTS_FILE}" -o "${output_file}" "${input_file}"
}

age_decrypt_file() {
	local input_file="$1"
	local output_file="$2"

	if [ ! -f "${AGE_KEYS_FILE}" ]; then
		error "No private key found"
		return 1
	fi

	age -d -i "${AGE_KEYS_FILE}" -o "${output_file}" "${input_file}"
}

age_reencrypt_all() {
	info "Re-encrypting all files with current recipients..."

	local flavour_dir="${DOTFILES_DIR}/flavours"
	local temp_dir=$(mktemp -d)
	local reencrypted=0

	trap "rm -rf ${temp_dir}" EXIT

	for flavour in work personal server; do
		local flavour_path="${flavour_dir}/${flavour}"
		if [ ! -d "${flavour_path}" ]; then
			continue
		fi

		info "Processing flavour: ${flavour}"

		find "${flavour_path}" -name "*.age" -type f | while read -r encrypted_file; do
			local relative_path="${encrypted_file#${flavour_path}/}"
			local temp_decrypted="${temp_dir}/${relative_path%.age}"

			# Create directory structure
			mkdir -p "$(dirname "${temp_decrypted}")"

			# Decrypt
			if age_decrypt_file "${encrypted_file}" "${temp_decrypted}"; then
				# Re-encrypt
				if age_encrypt_file "${temp_decrypted}" "${encrypted_file}"; then
					info "  ✓ ${relative_path}"
					reencrypted=$((reencrypted + 1))
				else
					error "  ✗ Failed to re-encrypt ${relative_path}"
				fi
			else
				error "  ✗ Failed to decrypt ${relative_path}"
			fi
		done
	done

	success "Re-encrypted ${reencrypted} files"
}
