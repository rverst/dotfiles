#!/usr/bin/env bats

load helper

setup() {
	ts_setup
	ts_age_bootstrap
}
teardown() { ts_teardown; }

@test "reencrypt_all adds a newly registered recipient" {
	mkdir -p "${DOTFILES_DIR}/flavours/common"
	echo "s" >"${TEST_TMP}/p"
	age_encrypt_file "${TEST_TMP}/p" "${DOTFILES_DIR}/flavours/common/secret.age"

	age-keygen -o "${TEST_TMP}/B.txt" 2>/dev/null
	bpub="$(age-keygen -y "${TEST_TMP}/B.txt")"
	age_ensure_recipient "$bpub" "B"

	run age_reencrypt_all
	[ "$status" -eq 0 ]

	# Machine B alone can now decrypt.
	age -d -i "${TEST_TMP}/B.txt" "${DOTFILES_DIR}/flavours/common/secret.age" >"${TEST_TMP}/out"
	run cat "${TEST_TMP}/out"
	[ "$output" = "s" ]
}

@test "require_can_decrypt passes when an identity exists" {
	mkdir -p "${DOTFILES_DIR}/flavours/common"
	echo "s" >"${TEST_TMP}/p"
	age_encrypt_file "${TEST_TMP}/p" "${DOTFILES_DIR}/flavours/common/secret.age"
	run age_require_can_decrypt
	[ "$status" -eq 0 ]
}

@test "require_can_decrypt blocks when no identity can decrypt" {
	mkdir -p "${DOTFILES_DIR}/flavours/common"
	echo "s" >"${TEST_TMP}/p"
	age_encrypt_file "${TEST_TMP}/p" "${DOTFILES_DIR}/flavours/common/secret.age"
	rm -f "${AGE_KEYS_FILE}" "${AGE_MASTER_KEY}"
	export DOT_RECOVERY_KEY=
	run age_require_can_decrypt
	[ "$status" -ne 0 ]
}
