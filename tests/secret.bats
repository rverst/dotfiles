#!/usr/bin/env bats
#
# Tests for local/dot-local/scripts/secret.
#
# The keyring is stubbed: a fake `security` binary is put first on PATH and
# backed by a plain file, so the suite never touches a real login keychain and
# runs identically on macOS and on the Linux CI runner.

load helper

setup() {
	ts_setup

	SECRET="${REPO_ROOT}/local/dot-local/scripts/secret"
	export SECRET

	# Stub store. One "name<TAB>value" line per entry.
	export STUB_STORE="${TEST_TMP}/keychain"
	: >"${STUB_STORE}"

	export STUB_BIN="${TEST_TMP}/bin"
	mkdir -p "${STUB_BIN}"
	_install_security_stub
	PATH="${STUB_BIN}:${PATH}"
	export PATH
}

teardown() { ts_teardown; }

# A minimal security(1) that implements only the four subcommands `secret`
# uses, with the same exit-status contract (non-zero when an item is missing).
_install_security_stub() {
	cat >"${STUB_BIN}/security" <<-'STUB'
		#!/usr/bin/env bash
		set -o errexit
		set -o nounset

		cmd="$1"; shift

		svce=""
		value=""
		while [ $# -gt 0 ]; do
			case "$1" in
			-s) svce="$2"; shift 2 ;;
			-a) shift 2 ;;
			-w) if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then value="$2"; shift 2; else shift; fi ;;
			-U) shift ;;
			*) shift ;;
			esac
		done

		case "${cmd}" in
		find-generic-password)
			line="$(grep -F "${svce}	" "${STUB_STORE}" || true)"
			[ -n "${line}" ] || exit 44
			printf '%s\n' "${line#*	}"
			;;
		add-generic-password)
			grep -vF "${svce}	" "${STUB_STORE}" >"${STUB_STORE}.tmp" || true
			mv "${STUB_STORE}.tmp" "${STUB_STORE}"
			printf '%s\t%s\n' "${svce}" "${value}" >>"${STUB_STORE}"
			;;
		delete-generic-password)
			grep -qF "${svce}	" "${STUB_STORE}" || exit 44
			grep -vF "${svce}	" "${STUB_STORE}" >"${STUB_STORE}.tmp" || true
			mv "${STUB_STORE}.tmp" "${STUB_STORE}"
			;;
		dump-keychain)
			while IFS="	" read -r svce _; do
				[ -n "${svce}" ] || continue
				printf '    "svce"<blob>="%s"\n' "${svce}"
			done <"${STUB_STORE}"
			;;
		*)
			exit 1
			;;
		esac
	STUB
	chmod +x "${STUB_BIN}/security"
}

# Store a value without going through `secret set` (which wants a prompt).
_seed() {
	printf 'dotfiles:%s\t%s\n' "$1" "$2" >>"${STUB_STORE}"
}

@test "set stores a value read from stdin, get reads it back" {
	run bash "${SECRET}" set MY_TOKEN <<<"s3cr3t"
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "s3cr3t" ]
}

@test "set overwrites an existing value instead of duplicating it" {
	_seed MY_TOKEN old

	run bash "${SECRET}" set MY_TOKEN <<<"new"
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "new" ]

	# Exactly one entry survives; a duplicate would make `get` ambiguous.
	run grep -c "dotfiles:MY_TOKEN" "${STUB_STORE}"
	[ "$output" = "1" ]
}

@test "set refuses an empty value" {
	run bash "${SECRET}" set MY_TOKEN <<<""
	[ "$status" -ne 0 ]
	[[ "$output" == *"empty value"* ]]
}

@test "get on a missing secret fails loudly instead of printing nothing" {
	run bash "${SECRET}" get NOPE
	[ "$status" -ne 0 ]
	[[ "$output" == *"no secret"* ]]
	[[ "$output" == *"secret set NOPE"* ]]
}

@test "get rejects an invalid name before touching the keyring" {
	run bash "${SECRET}" get 'bad name;rm'
	[ "$status" -ne 0 ]
	[[ "$output" == *"invalid secret name"* ]]
}

@test "get requires a name" {
	run bash "${SECRET}" get
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing secret name"* ]]
}

@test "rm deletes a stored secret" {
	_seed MY_TOKEN s3cr3t

	run bash "${SECRET}" rm MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$status" -ne 0 ]
}

@test "list prints stored names without values" {
	_seed ALPHA one
	_seed BRAVO two

	run bash "${SECRET}" list
	[ "$status" -eq 0 ]
	[[ "$output" == *"ALPHA"* ]]
	[[ "$output" == *"BRAVO"* ]]
	[[ "$output" != *"one"* ]]
	[[ "$output" != *"two"* ]]
}

@test "run exports the secret into the child process only" {
	_seed SECRET_TEST_TOKEN glpat-xxx

	run bash "${SECRET}" run SECRET_TEST_TOKEN -- printenv SECRET_TEST_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "glpat-xxx" ]

	# ...and does not leak into the calling shell.
	[ -z "${SECRET_TEST_TOKEN:-}" ]
}

@test "run injects several secrets at once" {
	_seed A one
	_seed B two

	run bash "${SECRET}" run A B -- sh -c 'printf "%s-%s" "$A" "$B"'
	[ "$status" -eq 0 ]
	[ "$output" = "one-two" ]
}

@test "run passes arguments through to the command untouched" {
	_seed A one

	run bash "${SECRET}" run A -- printf '%s|%s' 'x y' 'z'
	[ "$status" -eq 0 ]
	[ "$output" = "x y|z" ]
}

@test "run propagates the command's exit status" {
	_seed A one

	run bash "${SECRET}" run A -- sh -c 'exit 3'
	[ "$status" -eq 3 ]
}

@test "run aborts without executing the command when a secret is missing" {
	marker="${TEST_TMP}/ran"

	run bash "${SECRET}" run MISSING -- touch "${marker}"
	[ "$status" -ne 0 ]
	# The command must not have run half-configured.
	[ ! -e "${marker}" ]
}

@test "run requires the -- separator" {
	_seed A one

	run bash "${SECRET}" run A printenv A
	[ "$status" -ne 0 ]
	[[ "$output" == *"missing -- separator"* ]]
}

@test "run requires a command after --" {
	_seed A one

	run bash "${SECRET}" run A --
	[ "$status" -ne 0 ]
	[[ "$output" == *"no command given"* ]]
}

@test "sync fails with a clear hint when rbw is absent" {
	# Shadow rbw with nothing: PATH here contains only the stub dir + coreutils.
	run env PATH="${STUB_BIN}:/usr/bin:/bin" bash "${SECRET}" sync MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"rbw not installed"* ]]
}

@test "sync stores the value rbw returns" {
	cat >"${STUB_BIN}/rbw" <<-'STUB'
		#!/usr/bin/env bash
		case "$1" in
		unlocked) exit 0 ;;
		get) printf 'from-vault\n' ;;
		esac
	STUB
	chmod +x "${STUB_BIN}/rbw"

	run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault" ]
}

@test "fails cleanly when no keyring backend is available" {
	# An empty PATH dir: on macOS /usr/bin/security would otherwise be found.
	# bash is invoked by absolute path, since the stripped PATH can't find it.
	mkdir -p "${TEST_TMP}/nobin"

	run env PATH="${TEST_TMP}/nobin" /bin/bash "${SECRET}" get MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"no keyring backend"* ]]
}

@test "unknown command is rejected" {
	run bash "${SECRET}" frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown command"* ]]
}

@test "no arguments prints usage and exits non-zero" {
	run bash "${SECRET}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"Usage:"* ]]
}
