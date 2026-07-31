#!/usr/bin/env bats

load helper

setup() {
	ts_setup
	ts_age_bootstrap
}
teardown() { ts_teardown; }

@test "flavour_prepare_stow writes a placeholder when this machine can't decrypt" {
	mkdir -p "${DOTFILES_DIR}/flavours/common"
	echo "real content" >"${TEST_TMP}/p"
	age_encrypt_file "${TEST_TMP}/p" "${DOTFILES_DIR}/flavours/common/secret.age"

	# Simulate a machine that can't decrypt yet: no machine key, no master key.
	mv "${AGE_KEYS_FILE}" "${TEST_TMP}/keys.bak"
	mv "${AGE_MASTER_KEY}" "${TEST_TMP}/master.bak"

	run flavour_prepare_stow common
	[ "$status" -eq 0 ]

	decrypted="${DOTFILES_DIR}/flavours/decrypted-common/secret"
	[ -f "${decrypted}" ]
	run age_is_placeholder_content "${decrypted}"
	[ "$status" -eq 0 ]
}

@test "flavour_encrypt_changes refuses to promote a stale placeholder over real content" {
	mkdir -p "${DOTFILES_DIR}/flavours/common"
	echo "real content" >"${TEST_TMP}/p"
	age_encrypt_file "${TEST_TMP}/p" "${DOTFILES_DIR}/flavours/common/secret.age"

	# This machine can't decrypt yet -> flavour_prepare_stow writes a placeholder.
	mv "${AGE_KEYS_FILE}" "${TEST_TMP}/keys.bak"
	mv "${AGE_MASTER_KEY}" "${TEST_TMP}/master.bak"
	flavour_prepare_stow common >/dev/null 2>&1

	decrypted="${DOTFILES_DIR}/flavours/decrypted-common/secret"
	run age_is_placeholder_content "${decrypted}"
	[ "$status" -eq 0 ]

	# Now this machine CAN decrypt again (key restored, recipients never changed) -
	# same shape as the real bug: a machine becomes able to decrypt the real .age
	# while its own decrypted workspace still holds the stale placeholder.
	mv "${TEST_TMP}/keys.bak" "${AGE_KEYS_FILE}"
	mv "${TEST_TMP}/master.bak" "${AGE_MASTER_KEY}"

	cp "${DOTFILES_DIR}/flavours/common/secret.age" "${TEST_TMP}/secret.age.before"

	run flavour_encrypt_changes common
	[ "$status" -ne 0 ]

	# The real .age must be byte-for-byte untouched - the placeholder must never
	# get re-encrypted over the real content.
	run cmp -s "${TEST_TMP}/secret.age.before" "${DOTFILES_DIR}/flavours/common/secret.age"
	[ "$status" -eq 0 ]

	# And the real content underneath is still recoverable.
	age_decrypt_file "${DOTFILES_DIR}/flavours/common/secret.age" "${TEST_TMP}/out"
	run cat "${TEST_TMP}/out"
	[ "$output" = "real content" ]
}

@test "flavour_encrypt_changes still re-encrypts genuine (non-placeholder) edits" {
	mkdir -p "${DOTFILES_DIR}/flavours/decrypted-common"

	echo "first version" >"${DOTFILES_DIR}/flavours/decrypted-common/foo"
	run flavour_encrypt_changes common
	[ "$status" -eq 0 ]
	[ -f "${DOTFILES_DIR}/flavours/common/foo.age" ]
	age_decrypt_file "${DOTFILES_DIR}/flavours/common/foo.age" "${TEST_TMP}/out"
	run cat "${TEST_TMP}/out"
	[ "$output" = "first version" ]

	echo "second version" >"${DOTFILES_DIR}/flavours/decrypted-common/foo"
	run flavour_encrypt_changes common
	[ "$status" -eq 0 ]
	age_decrypt_file "${DOTFILES_DIR}/flavours/common/foo.age" "${TEST_TMP}/out2"
	run cat "${TEST_TMP}/out2"
	[ "$output" = "second version" ]
}
