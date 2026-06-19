#!/usr/bin/env bash
# Shared setup for the dotfiles bats suite. Each test runs in a throwaway
# sandbox: DOTFILES_DIR and HOME point at fresh temp dirs, and the real
# .scripts/*.sh are sourced (they only define functions).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

ts_setup() {
	TEST_TMP="$(mktemp -d)"
	export TEST_TMP
	export DOTFILES_DIR="${TEST_TMP}/repo"
	export HOME="${TEST_TMP}/home"
	mkdir -p "${DOTFILES_DIR}/.age" "${DOTFILES_DIR}/flavours" "${HOME}"

	# Quiet + non-interactive defaults; individual tests may flip DOT_UNA.
	export DOT_SIL=1
	export DOT_DRY=
	export DOT_UNA=
	export DOT_FORCE_NO_ENCRYPT=
	export DOT_FORCE_ENCRYPT=
	export DOT_RECOVERY_KEY=

	# DOTFILES_DIR must be set before sourcing age.sh (it derives AGE_DIR).
	# shellcheck source=/dev/null
	source "${REPO_ROOT}/.scripts/print.sh"
	# shellcheck source=/dev/null
	source "${REPO_ROOT}/.scripts/utils.sh"
	# shellcheck source=/dev/null
	source "${REPO_ROOT}/.scripts/age.sh"
	# shellcheck source=/dev/null
	source "${REPO_ROOT}/.scripts/flavours.sh"
	# shellcheck source=/dev/null
	source "${REPO_ROOT}/.scripts/add.sh"
}

ts_teardown() {
	[ -n "${TEST_TMP:-}" ] && [ -d "${TEST_TMP}" ] && rm -rf "${TEST_TMP}"
}

# Bootstrap machine key + recipients + master recovery key in the sandbox.
ts_age_bootstrap() {
	age_init >/dev/null 2>&1 || true
}
