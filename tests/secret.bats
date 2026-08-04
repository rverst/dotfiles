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

	# Vault stub state. Exported so the stubs (separate processes) see it.
	export STUB_VAULT_INDEX="${TEST_TMP}/vault-index"
	export STUB_VAULT_EMPTY="${TEST_TMP}/vault-empty"
	export STUB_KDBX="${TEST_TMP}/vault.kdbx"
	export STUB_KP_LOG="${TEST_TMP}/kp-argv"
	export STUB_KP_STDIN="${TEST_TMP}/kp-stdin"

	_install_security_stub
	_install_pwsh_stub
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

# A minimal pwsh.exe standing in for the Windows side. It ignores the
# -EncodedCommand payload entirely and acts on the env vars the bridge sets,
# which is exactly the contract the real PowerShell script implements. Values
# cross base64-encoded, so the encoding layer is genuinely exercised.
_install_pwsh_stub() {
	cat >"${STUB_BIN}/pwsh.exe" <<-'STUB'
		#!/usr/bin/env bash
		set -o errexit
		set -o nounset

		if [ "${STUB_PWSH_NO_MODULE:-}" = "1" ]; then exit 8; fi
		if [ "${STUB_PWSH_LOCKED:-}" = "1" ]; then exit 9; fi

		# One byte per invocation, so a test can assert the batching.
		if [ -n "${STUB_COUNTER:-}" ]; then printf 'x' >>"${STUB_COUNTER}"; fi

		b64d() { if printf 'eA==' | base64 -d >/dev/null 2>&1; then base64 -d; else base64 -D; fi; }
		b64e() { base64 | tr -d '\n'; }

		full="${SECRET_PS_PREFIX}:${SECRET_PS_NAME:-}"

		case "${SECRET_PS_VERB}" in
		get)
			line="$(grep -F "${full}	" "${STUB_STORE}" || true)"
			[ -n "${line}" ] || exit 0
			printf '%s' "${line#*	}" | b64d | b64e
			;;
		getmany)
			IFS=',' read -r -a names <<<"${SECRET_PS_NAMES}"
			for n in "${names[@]}"; do
				[ -n "${n}" ] || continue
				line="$(grep -F "${SECRET_PS_PREFIX}:${n}	" "${STUB_STORE}" || true)"
				if [ -n "${line}" ]; then
					printf '%s\t%s\n' "${n}" "$(printf '%s' "${line#*	}" | b64d | b64e)"
				else
					printf '%s\t\n' "${n}"
				fi
			done
			;;
		set)
			value="$(cat)"
			grep -vF "${full}	" "${STUB_STORE}" >"${STUB_STORE}.tmp" || true
			mv "${STUB_STORE}.tmp" "${STUB_STORE}"
			# Store base64 so values with tabs/newlines survive the flat file.
			printf '%s\t%s\n' "${full}" "${value}" >>"${STUB_STORE}"
			;;
		rm)
			grep -qF "${full}	" "${STUB_STORE}" || exit 9
			grep -vF "${full}	" "${STUB_STORE}" >"${STUB_STORE}.tmp" || true
			mv "${STUB_STORE}.tmp" "${STUB_STORE}"
			;;
		list)
			while IFS="	" read -r svce _; do
				[ -n "${svce}" ] || continue
				case "${svce}" in
				"${SECRET_PS_PREFIX}:"*) printf '%s\n' "${svce#"${SECRET_PS_PREFIX}":}" ;;
				esac
			done <"${STUB_STORE}"
			;;
		*)
			exit 1
			;;
		esac
	STUB
	chmod +x "${STUB_BIN}/pwsh.exe"
}

# Drive `secret` down the WSL path: no security(1)/secret-tool on PATH.
_wsl() {
	env PATH="${STUB_BIN}:/usr/bin:/bin" \
		STUB_STORE="${STUB_STORE}" \
		SECRET_BACKEND=wsl \
		"${BASH}" "${SECRET}" "$@"
}

# Seed a value the way the pwsh stub stores it (base64).
_seed_wsl() {
	printf 'dotfiles:%s\t%s\n' "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')" >>"${STUB_STORE}"
}

# Store a value without going through `secret set` (which wants a prompt).
_seed() {
	printf 'dotfiles:%s\t%s\n' "$1" "$2" >>"${STUB_STORE}"
}

# A minimal rbw(1). The folder index (one "folder<TAB>name" line per item)
# backs `list`; `get` echoes a value that encodes the folder and item it was
# asked for, so a test can assert the lookup was actually scoped.
_install_rbw_stub() {
	printf 'dotfiles\tMY_TOKEN\ndotfiles\tOTHER_TOKEN\nother\tELSEWHERE\n' \
		>"${STUB_VAULT_INDEX}"
	: >"${STUB_VAULT_EMPTY}"

	cat >"${STUB_BIN}/rbw" <<-'STUB'
		#!/usr/bin/env bash
		set -o nounset

		case "$1" in
		unlocked) exit 0 ;;
		unlock) exit 0 ;;
		list)
			cat "${STUB_VAULT_INDEX}"
			;;
		get)
			shift
			folder=""
			item=""
			while [ $# -gt 0 ]; do
				case "$1" in
				--folder) folder="$2"; shift 2 ;;
				--field) shift 2 ;;
				*) item="$1"; shift ;;
				esac
			done
			[ "${item}" = "MISSING" ] && exit 1
			grep -qxF "${item}" "${STUB_VAULT_EMPTY}" && exit 0
			printf 'from-vault:%s/%s\n' "${folder}" "${item}"
			;;
		*) exit 1 ;;
		esac
	STUB
	chmod +x "${STUB_BIN}/rbw"
}

# A minimal keepassxc-cli. It logs its argv (pipe separated) and appends its
# stdin, so tests can assert that the passphrase travels on stdin only and that
# the flags are built correctly.
_install_keepassxc_stub() {
	: >"${STUB_KDBX}"
	: >"${STUB_KP_LOG}"
	: >"${STUB_KP_STDIN}"

	cat >"${STUB_BIN}/keepassxc-cli" <<-'STUB'
		#!/usr/bin/env bash
		set -o nounset

		printf '%s\n' "$(IFS='|'; printf '%s' "$*")" >>"${STUB_KP_LOG}"

		if [ ! -t 0 ]; then
			# Consume at most the passphrase line; the real CLI does the same.
			IFS= read -r pass || pass=""
			[ -n "${pass}" ] && printf '%s\n' "${pass}" >>"${STUB_KP_STDIN}"
		fi

		cmd="$1"; shift
		args=()
		while [ $# -gt 0 ]; do
			case "$1" in
			-q | -s | --no-password | -R | -f) shift ;;
			-a | -k | -y) shift 2 ;;
			*) args+=("$1"); shift ;;
			esac
		done

		case "${cmd}" in
		show)
			entry="${args[1]}"
			case "${entry}" in
			*/MY_TOKEN | */OTHER_TOKEN) printf 'from-kdbx:%s\n' "${entry}" ;;
			*) printf 'Could not find entry with path %s.\n' "${entry}" >&2; exit 1 ;;
			esac
			;;
		ls)
			printf 'MY_TOKEN\nsubgroup/\nOTHER_TOKEN\n'
			;;
		*) exit 1 ;;
		esac
	STUB
	chmod +x "${STUB_BIN}/keepassxc-cli"
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

@test "sync fails with a clear hint when no vault backend is present" {
	# Shadow rbw/keepassxc-cli with nothing: PATH here contains only the stub
	# dir + coreutils.
	run env PATH="${STUB_BIN}:/usr/bin:/bin" bash "${SECRET}" sync MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"no vault backend available"* ]]
}

@test "sync stores the value rbw returns" {
	_install_rbw_stub

	run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault:dotfiles/MY_TOKEN" ]
}

@test "sync scopes the rbw lookup to the vault folder" {
	_install_rbw_stub

	SECRET_VAULT_FOLDER=work run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault:work/MY_TOKEN" ]
}

@test "sync accepts an explicit item name that differs from the secret name" {
	_install_rbw_stub

	run bash "${SECRET}" sync MY_TOKEN gitlab-pat
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault:dotfiles/gitlab-pat" ]
}

@test "sync --list prints the folder's item names" {
	_install_rbw_stub

	run bash "${SECRET}" sync --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"MY_TOKEN"* ]]
	[[ "$output" == *"OTHER_TOKEN"* ]]
	# An item in another folder must not show up.
	[[ "$output" != *"ELSEWHERE"* ]]
}

@test "sync --all pulls every item of the folder" {
	_install_rbw_stub

	run bash "${SECRET}" sync --all
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault:dotfiles/MY_TOKEN" ]

	run bash "${SECRET}" get OTHER_TOKEN
	[ "$output" = "from-vault:dotfiles/OTHER_TOKEN" ]

	run bash "${SECRET}" get ELSEWHERE
	[ "$status" -ne 0 ]
}

@test "sync --all skips items that are not valid secret names, and empty ones" {
	_install_rbw_stub

	printf 'dotfiles\tsome login\n' >>"${STUB_VAULT_INDEX}"
	printf 'dotfiles\tEMPTY_ONE\n' >>"${STUB_VAULT_INDEX}"
	printf 'EMPTY_ONE\n' >"${STUB_VAULT_EMPTY}"

	run bash "${SECRET}" sync --all
	[ "$status" -eq 0 ]
	[[ "$output" == *"skipping vault item some login"* ]]
	[[ "$output" == *"skipping vault item EMPTY_ONE"* ]]
	[[ "$output" == *"synced 2 of 4"* ]]
}

@test "sync --all takes no further arguments" {
	_install_rbw_stub

	run bash "${SECRET}" sync --all MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"takes no further arguments"* ]]
}

@test "sync rejects an unknown option" {
	_install_rbw_stub

	run bash "${SECRET}" sync --frobnicate
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown option"* ]]
}

@test "sync fails clearly on a missing vault item" {
	_install_rbw_stub

	run bash "${SECRET}" sync MISSING
	[ "$status" -ne 0 ]
	[[ "$output" == *"no vault item 'MISSING'"* ]]
}

# --- vault backend selection ------------------------------------------------

@test "SECRET_VAULT rejects an unknown backend" {
	_install_rbw_stub

	SECRET_VAULT=1password run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"unknown SECRET_VAULT"* ]]
}

@test "an explicitly configured keepass database wins over an installed rbw" {
	_install_rbw_stub
	_install_keepassxc_stub

	SECRET_KEEPASS_DB="${STUB_KDBX}" \
		SECRET_KEEPASS_NO_PASSWORD=1 \
		run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-kdbx:/dotfiles/MY_TOKEN" ]
}

@test "SECRET_VAULT=rbw wins over a configured keepass database" {
	_install_rbw_stub
	_install_keepassxc_stub

	SECRET_VAULT=rbw SECRET_KEEPASS_DB="${STUB_KDBX}" \
		run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-vault:dotfiles/MY_TOKEN" ]
}

# --- keepassxc vault backend ------------------------------------------------

@test "keepass sync requires SECRET_KEEPASS_DB" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"SECRET_KEEPASS_DB is not set"* ]]
}

@test "keepass sync rejects a database path that does not exist" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${TEST_TMP}/nope.kdbx" \
		run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"does not exist"* ]]
}

@test "keepass sync reads the password field of the folder entry" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${STUB_KDBX}" \
		SECRET_KEEPASS_NO_PASSWORD=1 \
		run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-kdbx:/dotfiles/MY_TOKEN" ]

	# -q (quiet) and -s (show protected) must both be passed, or the value
	# would come back masked or polluted with prompt text.
	run cat "${STUB_KP_LOG}"
	[[ "$output" == "show|"* ]]
	[[ "$output" == *"|-q|"* ]]
	[[ "$output" == *"|-s|"* ]]
	[[ "$output" == *"|-a|Password|"* ]]
	[[ "$output" == *"|/dotfiles/MY_TOKEN"* ]]
}

@test "keepass passes the key file and yubikey flags through" {
	_install_keepassxc_stub
	: >"${TEST_TMP}/key"

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${STUB_KDBX}" \
		SECRET_KEEPASS_KEYFILE="${TEST_TMP}/key" \
		SECRET_KEEPASS_YUBIKEY=1:7370001 \
		SECRET_KEEPASS_NO_PASSWORD=1 \
		run bash "${SECRET}" sync MY_TOKEN
	[ "$status" -eq 0 ]

	run cat "${STUB_KP_LOG}"
	[[ "$output" == *"-k|${TEST_TMP}/key"* ]]
	[[ "$output" == *"-y|1:7370001"* ]]
	[[ "$output" == *"--no-password"* ]]
}

@test "keepass takes the passphrase on stdin, never in argv" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${STUB_KDBX}" \
		run bash -c "printf 'hunter2\n' | bash '${SECRET}' sync MY_TOKEN"
	[ "$status" -eq 0 ]

	run cat "${STUB_KP_LOG}"
	[[ "$output" != *"hunter2"* ]]

	run cat "${STUB_KP_STDIN}"
	[ "$output" = "hunter2" ]
}

@test "keepass prompts for the passphrase only once for sync --all" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${STUB_KDBX}" \
		run bash -c "printf 'hunter2\n' | bash '${SECRET}' sync --all"
	[ "$status" -eq 0 ]

	run bash "${SECRET}" get MY_TOKEN
	[ "$output" = "from-kdbx:/dotfiles/MY_TOKEN" ]
	run bash "${SECRET}" get OTHER_TOKEN
	[ "$output" = "from-kdbx:/dotfiles/OTHER_TOKEN" ]

	# One `ls` plus two `show` calls, all with the same passphrase, from a
	# single read: a second prompt would have hit EOF and failed.
	run bash -c "grep -c hunter2 '${STUB_KP_STDIN}'"
	[ "$output" = "3" ]
}

@test "keepass sync --list strips group prefixes and drops nested groups" {
	_install_keepassxc_stub

	SECRET_VAULT=keepassxc SECRET_KEEPASS_DB="${STUB_KDBX}" \
		SECRET_KEEPASS_NO_PASSWORD=1 \
		run bash "${SECRET}" sync --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"MY_TOKEN"* ]]
	[[ "$output" == *"OTHER_TOKEN"* ]]
	[[ "$output" != *"subgroup/"* ]]
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

# --- WSL2 / PowerShell backend ---------------------------------------------

@test "wsl: set stores a value through the base64 layer, get reads it back" {
	run _wsl set MY_TOKEN <<<"s3cr3t"
	[ "$status" -eq 0 ]

	run _wsl get MY_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "s3cr3t" ]
}

@test "wsl: values with quotes, spaces and shell metacharacters survive" {
	# The whole point of the base64 layer: none of this needs quoting.
	tricky='a b"c$d`e;f|g%PATH% \\ é'

	run _wsl set TRICKY <<<"${tricky}"
	[ "$status" -eq 0 ]

	run _wsl get TRICKY
	[ "$status" -eq 0 ]
	[ "$output" = "${tricky}" ]
}

@test "wsl: get on a missing secret fails loudly" {
	run _wsl get NOPE
	[ "$status" -ne 0 ]
	[[ "$output" == *"no secret"* ]]
}

@test "wsl: rm deletes a stored secret" {
	_seed_wsl MY_TOKEN s3cr3t

	run _wsl rm MY_TOKEN
	[ "$status" -eq 0 ]

	run _wsl get MY_TOKEN
	[ "$status" -ne 0 ]
}

@test "wsl: list prints stored names without values" {
	_seed_wsl ALPHA one
	_seed_wsl BRAVO two

	run _wsl list
	[ "$status" -eq 0 ]
	[[ "$output" == *"ALPHA"* ]]
	[[ "$output" == *"BRAVO"* ]]
	[[ "$output" != *"one"* ]]
	[[ "$output" != *"two"* ]]
}

@test "wsl: run injects the secret into the child process only" {
	_seed_wsl SECRET_TEST_TOKEN glpat-xxx

	run _wsl run SECRET_TEST_TOKEN -- printenv SECRET_TEST_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "glpat-xxx" ]
	[ -z "${SECRET_TEST_TOKEN:-}" ]
}

@test "wsl: run fetches several secrets in a single interop call" {
	_seed_wsl A one
	_seed_wsl B two
	_seed_wsl C three

	# The stub counts its own invocations: batching must cost exactly one.
	counter="${TEST_TMP}/pwsh-calls"
	: >"${counter}"

	run env PATH="${STUB_BIN}:/usr/bin:/bin" \
		STUB_STORE="${STUB_STORE}" \
		STUB_COUNTER="${counter}" \
		SECRET_BACKEND=wsl \
		"${BASH}" "${SECRET}" run A B C -- sh -c 'printf "%s-%s-%s" "$A" "$B" "$C"'
	[ "$status" -eq 0 ]
	[ "$output" = "one-two-three" ]
	[ "$(wc -c <"${counter}" | tr -d ' ')" = "1" ]
}

@test "wsl: run aborts when one of the batched secrets is missing" {
	_seed_wsl A one
	marker="${TEST_TMP}/ran"

	run _wsl run A MISSING -- touch "${marker}"
	[ "$status" -ne 0 ]
	[[ "$output" == *"no secret"* ]]
	[[ "$output" == *"MISSING"* ]]
	[ ! -e "${marker}" ]
}

@test "wsl: a missing SecretManagement module gives an actionable error" {
	run env PATH="${STUB_BIN}:/usr/bin:/bin" \
		STUB_STORE="${STUB_STORE}" \
		STUB_PWSH_NO_MODULE=1 \
		SECRET_BACKEND=wsl \
		"${BASH}" "${SECRET}" get MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"Install-Module"* ]]
}

@test "wsl: a locked vault gives an actionable error" {
	run env PATH="${STUB_BIN}:/usr/bin:/bin" \
		STUB_STORE="${STUB_STORE}" \
		STUB_PWSH_LOCKED=1 \
		SECRET_BACKEND=wsl \
		"${BASH}" "${SECRET}" get MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"Set-SecretStoreConfiguration"* ]]
}

@test "a real keyring wins over pwsh.exe when both are present" {
	# secret-tool implies a Linux desktop keyring; interop is the fallback.
	rm -f "${STUB_BIN}/security"
	cat >"${STUB_BIN}/secret-tool" <<-'STUB'
		#!/bin/sh
		printf 'from-libsecret\n'
	STUB
	chmod +x "${STUB_BIN}/secret-tool"

	# PATH is the stub dir alone: /usr/bin would otherwise supply a real
	# security(1) on the macOS runner.
	run env PATH="${STUB_BIN}" "${BASH}" "${SECRET}" get MY_TOKEN
	[ "$status" -eq 0 ]
	[ "$output" = "from-libsecret" ]
}

@test "powershell.exe without pwsh.exe is refused with a PowerShell 7 hint" {
	rm -f "${STUB_BIN}/pwsh.exe" "${STUB_BIN}/security"
	cat >"${STUB_BIN}/powershell.exe" <<-'STUB'
		#!/usr/bin/env bash
		exit 0
	STUB
	chmod +x "${STUB_BIN}/powershell.exe"

	run env PATH="${STUB_BIN}" "${BASH}" "${SECRET}" get MY_TOKEN
	[ "$status" -ne 0 ]
	[[ "$output" == *"PowerShell 7 is required"* ]]
}
