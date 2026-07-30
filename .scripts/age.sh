#!/usr/bin/env bash

AGE_DIR="${DOTFILES_DIR}/.age"
AGE_KEYS_FILE="${AGE_DIR}/keys.txt"
AGE_RECIPIENTS_FILE="${AGE_DIR}/recipients.txt"
# Master recovery key: its PUBLIC key is committed and always added as an
# encryption recipient, so any file can be decrypted with the master key even if
# every machine key is lost. The PRIVATE key is generated once, must be copied
# into a password manager, and is gitignored.
AGE_MASTER_PUB="${AGE_DIR}/master.txt"
AGE_MASTER_KEY="${AGE_DIR}/master-key.txt"

# age_ensure_recipient <pubkey> <label>
# Appends a recipient block only if the pubkey is not already present. This is
# the dedupe primitive that prevents the same machine key being added twice.
age_ensure_recipient() {
	local pubkey="$1"
	local label="${2:-unknown}"

	[ -n "${pubkey}" ] || return 1

	if [ -f "${AGE_RECIPIENTS_FILE}" ] && grep -qF "${pubkey}" "${AGE_RECIPIENTS_FILE}"; then
		return 0
	fi

	{
		echo "# Machine: ${label} - $(date)"
		echo "${pubkey}"
		echo ""
	} >>"${AGE_RECIPIENTS_FILE}"
	info "Added recipient: ${label}"
	return 0
}

# age_master_init
# Generates the master recovery keypair if it does not exist yet. The public key
# is committed; the private key is written to a gitignored file and the user is
# loudly told to store it in their password manager. Idempotent.
age_master_init() {
	[ -f "${AGE_MASTER_PUB}" ] && return 0

	info "Generating master recovery key..."
	age-keygen -o "${AGE_MASTER_KEY}" 2>/dev/null
	chmod 600 "${AGE_MASTER_KEY}"

	local pubkey
	pubkey=$(age-keygen -y "${AGE_MASTER_KEY}")
	echo "${pubkey}" >"${AGE_MASTER_PUB}"

	warn "============================================================"
	warn "MASTER RECOVERY KEY GENERATED"
	warn "Private key written to: ${AGE_MASTER_KEY}"
	warn "COPY IT INTO YOUR PASSWORD MANAGER NOW (you may delete the file after)."
	warn "Without it, a fully-wiped fleet cannot decrypt your secrets."
	warn "------------------------------------------------------------"
	cat "${AGE_MASTER_KEY}" >&2
	warn "============================================================"
	success "Master public key stored at ${AGE_MASTER_PUB}"
	return 0
}

age_init() {
	info "Initializing Age encryption..."

	mkdir -p "${AGE_DIR}"

	if [ ! -f "${AGE_KEYS_FILE}" ]; then
		info "Generating new Age keypair..."
		age-keygen -o "${AGE_KEYS_FILE}" 2>/dev/null
		chmod 600 "${AGE_KEYS_FILE}"
		success "New Age keypair generated"
	fi

	# Ensure this machine's public key is a recipient (idempotent: never adds a
	# duplicate block).
	local pubkey
	pubkey=$(age-keygen -y "${AGE_KEYS_FILE}")
	age_ensure_recipient "${pubkey}" "$(hostname)"

	# Ensure the master recovery key exists (idempotent).
	age_master_init

	if ! age_can_decrypt_existing; then
		warn "Cannot decrypt existing encrypted files on this machine"
		warn "Either run 'dotfiles reencrypt-all' on a machine that can decrypt and"
		warn "pull, or export the master key and run:"
		warn "  DOT_RECOVERY_KEY=/path/to/master-key.txt dotfiles reencrypt-all"
		return 1
	fi

	return 0
}

# _age_build_identities
# Populates the global array AGE_ID_ARGS with "-i <identity>" pairs for every
# available decryption identity, in priority order: machine key, recovery key
# (DOT_RECOVERY_KEY), master key. age tries each identity until one matches.
_age_build_identities() {
	AGE_ID_ARGS=()
	[ -f "${AGE_KEYS_FILE}" ] && AGE_ID_ARGS+=(-i "${AGE_KEYS_FILE}")
	if [ -n "${DOT_RECOVERY_KEY:-}" ] && [ -f "${DOT_RECOVERY_KEY}" ]; then
		AGE_ID_ARGS+=(-i "${DOT_RECOVERY_KEY}")
	fi
	[ -f "${AGE_MASTER_KEY}" ] && AGE_ID_ARGS+=(-i "${AGE_MASTER_KEY}")
	# Must return success: a trailing failed `&&` would abort callers under
	# `set -o errexit` whenever the master key file is absent.
	return 0
}

age_can_decrypt_existing() {
	local test_file
	test_file=$(find "${DOTFILES_DIR}/flavours" -type f -name "*.age" 2>/dev/null | head -n 1 || true)
	[ -n "${test_file}" ] || return 0

	local -a AGE_ID_ARGS
	_age_build_identities
	[ ${#AGE_ID_ARGS[@]} -gt 0 ] || return 1

	age "${AGE_ID_ARGS[@]}" -d "${test_file}" >/dev/null 2>&1
}

# age_require_can_decrypt
# Guard for any command that produces encrypted content: refuse if this machine
# cannot decrypt existing files with any available identity, so you never add
# encrypted content you cannot read back.
age_require_can_decrypt() {
	if age_can_decrypt_existing; then
		return 0
	fi
	error "This machine cannot decrypt existing encrypted files."
	error "Refusing to encrypt new content you would not be able to read back."
	error "Recover first, then retry:"
	error "  - run 'dotfiles reencrypt-all' on a machine that can decrypt, then pull; or"
	error "  - export the master key and run:"
	error "      DOT_RECOVERY_KEY=/path/to/master-key.txt dotfiles reencrypt-all"
	return 1
}

# age_can_decrypt_file <encrypted_file>
# True if the file decrypts with any available identity (machine/recovery/master).
age_can_decrypt_file() {
	local f="$1"
	local -a AGE_ID_ARGS
	_age_build_identities
	[ ${#AGE_ID_ARGS[@]} -gt 0 ] || return 1
	age "${AGE_ID_ARGS[@]}" -d "${f}" >/dev/null 2>&1
}

age_encrypt_file() {
	local input_file="$1"
	local output_file="$2"

	if [ ! -f "${AGE_RECIPIENTS_FILE}" ] || [ ! -s "${AGE_RECIPIENTS_FILE}" ]; then
		error "No recipients file found or empty"
		return 1
	fi

	# Always encrypt to the per-machine recipients and, when present, the master
	# recovery key.
	local -a rcpt_args=(-R "${AGE_RECIPIENTS_FILE}")
	[ -f "${AGE_MASTER_PUB}" ] && rcpt_args+=(-R "${AGE_MASTER_PUB}")

	age "${rcpt_args[@]}" -o "${output_file}" "${input_file}"
}

age_decrypt_file() {
	local input_file="$1"
	local output_file="$2"

	local -a AGE_ID_ARGS
	_age_build_identities
	if [ ${#AGE_ID_ARGS[@]} -eq 0 ]; then
		error "No private key found (machine key, recovery key, or master key)"
		return 1
	fi

	age "${AGE_ID_ARGS[@]}" -d -o "${output_file}" "${input_file}"
}

# age_verify_roundtrip <plaintext_file> <encrypted_file>
# Confirms the encrypted file decrypts (with an available identity) to bytes
# identical to the plaintext. Used to gate every deletion of an original.
age_verify_roundtrip() {
	local plaintext="$1"
	local encrypted="$2"

	[ -f "${plaintext}" ] || return 1
	[ -f "${encrypted}" ] || return 1

	local tmp rc=0
	tmp="$(mktemp)"
	if age_decrypt_file "${encrypted}" "${tmp}" >/dev/null 2>&1; then
		cmp -s "${plaintext}" "${tmp}" || rc=1
	else
		rc=1
	fi
	rm -f "${tmp}"
	return "${rc}"
}

age_reencrypt_all() {
	info "Re-encrypting all files with current recipients..."

	local flavour_dir="${DOTFILES_DIR}/flavours"
	local temp_dir
	temp_dir=$(mktemp -d)
	local reencrypted=0

	trap " [ -n '${temp_dir}' ] && [ -d '${temp_dir}' ] && rm -rf '${temp_dir}' " EXIT INT TERM

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
	done < <(find "${flavour_dir}" -mindepth 1 -maxdepth 1 -type d ! -name 'decrypted-*' -exec basename {} \; 2>/dev/null)

	success "Re-encrypted ${reencrypted} files"
}
