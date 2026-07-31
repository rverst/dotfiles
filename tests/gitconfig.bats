#!/usr/bin/env bats

load helper

setup() { ts_setup; }
teardown() { ts_teardown; }

# Writes a global ~/.gitconfig that pulls in ~/.gitconfig.local via [include].
_write_gitconfig_with_include() {
	printf '[include]\n\tpath = ~/.gitconfig.local\n' >"${HOME}/.gitconfig"
}

@test "setup_gitconfig skips prompt when identity lives in an included ~/.gitconfig.local" {
	_write_gitconfig_with_include
	printf '[user]\n\tname = Included Name\n\temail = inc@example.com\n' >"${HOME}/.gitconfig.local"

	# stdin is closed: if the guard failed to follow the include it would try to
	# read a name/email here and either hang or overwrite with empty values.
	run setup_gitconfig </dev/null
	[ "$status" -eq 0 ]

	# The pre-existing identity must be untouched.
	run git config -f "${HOME}/.gitconfig.local" --get user.email
	[ "$output" = "inc@example.com" ]
}

@test "setup_gitconfig prompts and writes when no identity is configured" {
	printf '[core]\n\teditor = nvim\n' >"${HOME}/.gitconfig"

	# name, email, gpg-signing (default n)
	run setup_gitconfig <<-'EOF'
		Test Name
		test@example.com

	EOF
	[ "$status" -eq 0 ]

	run git config -f "${HOME}/.gitconfig.local" --get user.name
	[ "$output" = "Test Name" ]
	run git config -f "${HOME}/.gitconfig.local" --get user.email
	[ "$output" = "test@example.com" ]
}
