#!/usr/bin/env bats

load helper

setup() { ts_setup; }
teardown() { ts_teardown; }

@test "home_to_stow_path dots every dotted component" {
	run home_to_stow_path ".config/nvim/init.lua"
	[ "$status" -eq 0 ]
	[ "$output" = "dot-config/nvim/init.lua" ]
}

@test "home_to_stow_path handles a top-level dotfile" {
	run home_to_stow_path ".zshrc"
	[ "$output" = "dot-zshrc" ]
}

@test "stow_to_home_path is the inverse" {
	run stow_to_home_path "dot-config/nvim/init.lua"
	[ "$output" = ".config/nvim/init.lua" ]
	run stow_to_home_path "dot-zshrc"
	[ "$output" = ".zshrc" ]
}

@test "resolve_home_rel computes rel and finds no src for a plain file" {
	mkdir -p "${HOME}/.config/foo"
	echo hi >"${HOME}/.config/foo/bar"
	resolve_home_rel "${HOME}/.config/foo/bar" abs rel src
	[ "$rel" = ".config/foo/bar" ]
	[ -z "$src" ]
	[ "$abs" = "${HOME}/.config/foo/bar" ]
}

@test "resolve_home_rel detects a stow symlink source" {
	mkdir -p "${DOTFILES_DIR}/home/dot-config/foo"
	echo hi >"${DOTFILES_DIR}/home/dot-config/foo/bar"
	mkdir -p "${HOME}/.config/foo"
	ln -s "${DOTFILES_DIR}/home/dot-config/foo/bar" "${HOME}/.config/foo/bar"
	resolve_home_rel "${HOME}/.config/foo/bar" abs rel src
	[ "$rel" = ".config/foo/bar" ]
	[ -n "$src" ]
}

@test "resolve_home_rel rejects a path outside HOME" {
	run resolve_home_rel "/etc/hosts" a r s
	[ "$status" -ne 0 ]
}
