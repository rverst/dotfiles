#!/usr/bin/env bats

load helper

setup() {
	ts_setup
	ts_age_bootstrap
	export DOT_UNA=1 # non-interactive: auto-encrypt, auto-remove original
}
teardown() { ts_teardown; }

@test "flavour_add_file adopts: encrypts, verifies, removes original" {
	mkdir -p "${HOME}/.config/app"
	echo "cfg" >"${HOME}/.config/app/conf"

	flavour_add_file "${HOME}/.config/app/conf" "common"

	[ -f "${DOTFILES_DIR}/flavours/common/dot-config/app/conf.age" ]
	[ ! -e "${HOME}/.config/app/conf" ]

	age_decrypt_file "${DOTFILES_DIR}/flavours/common/dot-config/app/conf.age" "${TEST_TMP}/back"
	run cat "${TEST_TMP}/back"
	[ "$output" = "cfg" ]
}

@test "flavour_add_file syncs the decrypted workspace when it exists" {
	mkdir -p "${DOTFILES_DIR}/flavours/decrypted-common"
	mkdir -p "${HOME}/.config/app"
	echo "cfg" >"${HOME}/.config/app/conf"

	flavour_add_file "${HOME}/.config/app/conf" "common"

	[ -f "${DOTFILES_DIR}/flavours/decrypted-common/dot-config/app/conf" ]
	run cat "${DOTFILES_DIR}/flavours/decrypted-common/dot-config/app/conf"
	[ "$output" = "cfg" ]
}

@test "abort keeps plaintext when the encrypted file cannot be verified" {
	# Recipients = a key we do not hold; no master -> verify must fail.
	rm -f "${AGE_MASTER_PUB}" "${AGE_MASTER_KEY}"
	age-keygen -o "${TEST_TMP}/foreign.txt" 2>/dev/null
	fpub="$(age-keygen -y "${TEST_TMP}/foreign.txt")"
	printf '%s\n' "$fpub" >"${AGE_RECIPIENTS_FILE}"

	mkdir -p "${HOME}/.config/app"
	echo "cfg" >"${HOME}/.config/app/conf"

	run flavour_add_file "${HOME}/.config/app/conf" "common"
	[ "$status" -ne 0 ]
	[ -f "${HOME}/.config/app/conf" ]
	[ ! -f "${DOTFILES_DIR}/flavours/common/dot-config/app/conf.age" ]
}

@test "move_to_flavour moves a regular-package file into a flavour" {
	mkdir -p "${DOTFILES_DIR}/home/dot-config/app"
	echo "cfg" >"${DOTFILES_DIR}/home/dot-config/app/conf"
	mkdir -p "${HOME}/.config/app"
	ln -s "${DOTFILES_DIR}/home/dot-config/app/conf" "${HOME}/.config/app/conf"

	move_to_flavour "${HOME}/.config/app/conf" "common"

	[ -f "${DOTFILES_DIR}/flavours/common/dot-config/app/conf.age" ]
	[ ! -e "${HOME}/.config/app/conf" ]
	[ ! -f "${DOTFILES_DIR}/home/dot-config/app/conf" ]
}

@test "plaintext add (no encryption) writes a plain file, no .age" {
	export DOT_FORCE_NO_ENCRYPT=1
	mkdir -p "${HOME}/.config/app"
	echo "cfg" >"${HOME}/.config/app/conf"

	flavour_add_file "${HOME}/.config/app/conf" "common"

	[ -f "${DOTFILES_DIR}/flavours/common/dot-config/app/conf" ]
	[ ! -f "${DOTFILES_DIR}/flavours/common/dot-config/app/conf.age" ]
}

@test "add_regular_file dry run writes nothing" {
	export DOT_DRY=1
	mkdir -p "${HOME}/.local/scripts"
	echo "hi" >"${HOME}/.local/scripts/foo"

	run add_regular_file "${HOME}/.local/scripts/foo" ""
	[ "$status" -eq 0 ]
	[ ! -e "${DOTFILES_DIR}/local/dot-local/scripts/foo" ]
	[ -f "${HOME}/.local/scripts/foo" ] # original untouched
}
