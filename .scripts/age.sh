#!/usr/bin/env bash

AGE_DIR="${DOTFILES_DIR}/.age"
AGE_KEYS_FILE="${AGE_DIR}/keys.txt"
AGE_RECIPIENTS_FILE="${AGE_DIR}/recipients.txt"

age_init() {
	info "Initializing Age encryption..."

	mkdir -p "${AGE_DIR}"

	if [ ! -f "${AGE_KEYS_FILE}" ]; then
		info "Generating new Age keypair..."
		age-keygen -o "${AGE_KEYS_FILE}" 2>/dev/null
		chmod 600 "${AGE_KEYS_FILE}"

		local pubkey
		pubkey=$(age-keygen -y "${AGE_KEYS_FILE}")
		{
			echo "# Machine: $(hostname) - $(date)"
			echo "${pubkey}"
			echo ""
		} >>"${AGE_RECIPIENTS_FILE}"

		success "New Age keypair generated"
		info "Public key added to recipients file"
	fi

	if ! age_can_decrypt_existing; then
		warn "Cannot decrypt existing encrypted files"
		info "Adding this machine's public key to recipients..."

		local pubkey
		pubkey=$(age-keygen -y "${AGE_KEYS_FILE}")
		{
			echo "# Machine: $(hostname) - $(date)"
			echo "${pubkey}"
			echo ""
		} >>"${AGE_RECIPIENTS_FILE}"

		warn "Re-encryption needed on a machine that can decrypt existing files"
		warn "Run 'dotfiles reencrypt-all' on another machine, then pull changes"
		return 1
	fi

	return 0
}

age_can_decrypt_existing() {
	local test_file
	test_file=$(find "${DOTFILES_DIR}/flavours" -type f -name "*.age" -print -quit 2>/dev/null || true)
	if [ -n "${test_file}" ]; then
		age -d -i "${AGE_KEYS_FILE}" "${test_file}" >/dev/null 2>&1
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
	local temp_dir
	temp_dir=$(mktemp -d)
	local reencrypted=0

	trap 'rm -rf -- "${temp_dir}"' EXIT

	local flavour
	while IFS= read -r flavour; do
		[ -z "${flavour}" ] && continue
		info "Processing flavour: ${flavour}"
		while IFS= read -r -d '' encrypted_file; do
			local relative_path="${encrypted_file#${flavour_dir}/${flavour}/}"
			local temp_decrypted="${temp_dir}/${relative_path%.age}"

			mkdir -p "$(dirname "${temp_decrypted}")"

			if age_decrypt_file "${encrypted_file}" "${temp_decrypted}"; then
				if age_encrypt_file "${temp_decrypted}" "${encrypted_file}"; then
					info "  ✓ ${relative_path}"
					reencrypted=$((reencrypted + 1))
				else
					error "  ✗ Failed to re-encrypt ${relative_path}"
				fi
			else
				error "  ✗ Failed to decrypt ${relative_path}"
			fi
		done < <(find "${flavour_dir}/${flavour}" -type f -name '*.age' -print0 2>/dev/null)
	done < <(find "${flavour_dir}" -mindepth 1 -maxdepth 1 -type d ! -name 'decrypted-*' -printf '%f\n' 2>/dev/null)

	success "Re-encrypted ${reencrypted} files"
}
