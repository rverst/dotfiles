# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles managed with **GNU Stow**, layered with a **flavour system** (per-machine configs) and **Age encryption** for secrets. Pure Bash + Stow — no build step. The two executables are `bootstrap` and `dotfiles`; all logic lives in `.scripts/*.sh`. A `bats` test suite lives in `tests/` (run `bats tests/`; CI also runs `shellcheck`).

## Commands

```bash
./bootstrap [--set-default-zsh] [--unattended]   # New machine: install zsh/stow/age, then run `dotfiles install`
./dotfiles install                               # Stow all packages for the current flavour
./dotfiles reinstall                             # Restow (unlink -> relink); also used after switching flavour
./dotfiles uninstall                             # Unstow all packages
./dotfiles update                                # git pull + submodule update, restowing around it
./dotfiles status                                # git status + encrypt any changed flavour files
./dotfiles flavour [name]                        # Show current flavour, or switch to it
./dotfiles add <file> [flavour|regular] [pkg]    # Adopt an existing file (flavour files encrypted by default)
./dotfiles move <file> [flavour]                 # Move a regular-package file into a flavour (encrypted by default)
./dotfiles copy <file> <from> <to>               # Copy a file from one flavour into another as a template
./dotfiles reencrypt-all                         # Re-encrypt every .age file against current recipients
```

Global flags (before the command): `-n` dry run, `-s` silent, `-u` unattended (non-interactive; defaults flavour to `server`), `-p` plaintext (skip encryption when adding/moving/copying).

`bootstrap` runs `dotfiles` under `bash` deliberately — the scripts use bashisms and must not be run under zsh/sh.

## Architecture

**Entry points.** `bootstrap` ensures dependencies (`zsh`, `stow`, `age`) via Homebrew (macOS) or the native package manager (Linux: apt/pacman/dnf/zypper/apk), then invokes `dotfiles install`. `dotfiles` parses options/commands in `main()` and sources the `.scripts/` modules:

- `print.sh` — colored logging (`info`/`success`/`warn`/`error`) and interactive prompts (`user_read`, `user_yesno`). All prompts write to stderr so command substitution stays clean.
- `utils.sh` — `resolve_path`; path helpers `home_to_stow_path`/`stow_to_home_path` (convert each path component between `.foo` and `dot-foo`) and `resolve_home_rel` (resolve a live path to its `$HOME`-relative form + originating repo source); first-run setup of `~/.gitconfig.local` and `~/.localrc`.
- `age.sh` — keypair + master-key init, encrypt/decrypt (multi-identity), recipient dedupe (`age_ensure_recipient`), verify-before-delete (`age_verify_roundtrip`), the can-decrypt guard (`age_require_can_decrypt`), and `reencrypt-all`.
- `flavours.sh` — flavour resolution, the decrypt→stow workflow, change re-encryption, and `flavour_place_file` (writes a file into a flavour, encrypted or not, and keeps the decrypted workspace in sync).
- `add.sh` — adopting regular (`add_regular_file`) vs flavour (`flavour_add_file`) files; `move_to_flavour` and `copy_flavour_file`.

**Stow packages.** Top-level non-hidden directories except `flavours` and `tests` are stow packages (`apps`, `config`, `home`, `local`, `nvim`), discovered dynamically in `dotfiles`. Non-config payload that lives inside a package but must not be stowed (e.g. `apps/Brewfile`) is excluded via a `.stow-local-ignore` in that package. Stow runs with `--dotfiles --no-folding`, so a `dot-config` component becomes `~/.config` and directories are materialized as real dirs with per-file symlinks (this lets regular packages and the flavour layers safely share parent dirs like `~/.config`). By convention the `config` package owns everything under `~/.config` (`config/dot-config/...`), the `local` package owns everything under `~/.local` (`local/dot-local/...`, e.g. `~/.local/scripts`), and `home` holds `$HOME`-root dotfiles (`dot-gitconfig`, `dot-ideavimrc`, `dot-zshenv`); `add`/`move` enforce this by defaulting `~/.config` files to `config` and `~/.local` files to `local` (via `_regular_default_package` in `add.sh`), everything else to `home`. When adopting/moving files, the full `$HOME`-relative path is converted via `home_to_stow_path` (every dotted component → `dot-`), so nested configs like `~/.config/nvim/init.lua` map correctly.

**Flavours** (`personal`, `work`, `server`, or custom) **plus the always-applied `common` layer.** The active machine flavour is stored in `~/.dotconfig` (`git config -f ~/.dotconfig core.flavour`). On stow, both `common` (if present) and the active flavour are layered on top of the regular packages: `flavour_prepare_stow` decrypts `flavours/<layer>/*.age` into `flavours/decrypted-<layer>/`, which is what gets stowed. `common` is **not** a selectable flavour (excluded from `flavour`/switch); it holds configs shared across all machines. The decrypted directory is the **local source of truth**: existing decrypted files (your edits) are preserved, `dotfiles status` re-encrypts changed ones back into `flavours/<layer>/`, and a flavour switch first re-encrypts + unstows the outgoing flavour (keeping its decrypted dir). Decrypted dirs are removed on uninstall/`flavour_cleanup_stow`. **Do not place the same target file in both `common` and a machine flavour** — they'd collide at stow time.

**Encryption is the default** for flavour files (`add`/`move`/`copy`). Opt out per-invocation with `-p`, interactively at the prompt, or via `DOT_FORCE_NO_ENCRYPT`. `flavour_encrypt_changes` writes each file back in the form it already has (`.age` stays encrypted, plaintext stays plaintext) and encrypts brand-new files by default.

**Age encryption.** Per-machine private key: `.age/keys.txt` (gitignored, generated on first install). Recipients: `.age/recipients.txt` — one block per machine; `age_ensure_recipient` adds a pubkey only if absent (no duplicates). **Master recovery key:** `.age/master.txt` (public, committed) is **always** an encryption recipient, and `.age/master-key.txt` (private, gitignored) is generated once on first init — **copy it into your password manager**, then you can delete the file. Because the master key is always a recipient, any file can be recovered with it.

Every file is encrypted to all per-machine recipients **plus** the master key (`age_encrypt_file`). Decryption (`age_decrypt_file`) tries, in order: the machine key, `$DOT_RECOVERY_KEY` (a path you point at an exported identity), then the master key. So a wiped machine recovers by exporting the master key and running `DOT_RECOVERY_KEY=/path/to/master-key.txt dotfiles reencrypt-all` (or by dropping it at `.age/master-key.txt`), then pull.

**Safety invariants.** Encryption never deletes the plaintext until the new `.age` is decrypt-verified (`age_verify_roundtrip` in `flavour_place_file`); `add`/`move` then ask before removing the original. Commands that _produce_ encrypted content (`add`/`move`/`copy`/`status`/`reencrypt-all`) first call `age_require_can_decrypt` and refuse if this machine can't read existing secrets — so you can never add encrypted content you couldn't read back. A `add` into a flavour/`common` now fully adopts the file: encrypt → verify → ask → remove original → restow (relink) when the target layer is active.

Multi-machine flow: a new machine generates its own keypair and `age_init` adds its pubkey to recipients; if it can't decrypt existing files, run `dotfiles reencrypt-all` on a machine that _can_ decrypt (or use the master key as above), then pull.

**Pre-commit hook.** `.githooks/pre-commit` (enabled by `dotfiles install` via `git config core.hooksPath .githooks`) re-encrypts edited decrypted workspaces, re-encrypts everything if the recipient set changed, and **blocks the commit if any staged `.age` is not decryptable on this machine** — so what you commit is always readable after a pull.

**Runtime secrets** are deliberately *not* handled by Age. `local/dot-local/scripts/secret` (stowed to `~/.local/scripts`, already on `PATH`) stores API tokens in the OS keyring (`security` on macOS, `secret-tool`/libsecret on Linux; no backend on servers → clean error) and injects them into a single child process via `secret run NAME... -- cmd`, so they never sit in cleartext on disk nor get exported globally. `secret sync` pulls from Bitwarden/Vaultwarden through `rbw`. Config files reference the variable (`${NPM_REGISTRY_TOKEN}`, `${env.GITLAB_TOKEN}`) instead of embedding the value. Tool wrappers live at the bottom of `~/.localrc` (below its `PATH` exports, since `$+commands` guards resolve at definition time). See the README's "Runtime secrets" section, including the known gap around `./mvnw` and IDE-launched builds.

**Submodules** (clone with `--recursive`): `nvim/dot-config/nvim` (Neovim config) and `config/dot-config/tmux/plugins/tpm` (tmux plugin manager).

## Gotchas

- After editing a flavour file, run `dotfiles status` to re-encrypt it before committing — the `.age` file is what's tracked, not the decrypted copy. (`status` covers the active flavour + `common`; a switch also re-encrypts the outgoing flavour.) The pre-commit hook also re-encrypts, but `status` is the explicit path.
- Adding a new recipient requires a `reencrypt-all` from a machine that can already decrypt (or with the master key), or the new machine gets undecryptable placeholders. The master key is the always-available fallback — keep its private half in your password manager.
- `print.sh` logging helpers must always return success; they run under `set -o errexit`, so a short-circuited `[ test ] && cmd` (or any function whose last line is one) would abort the caller. Same for `_age_build_identities`. Keep a trailing `return 0`.
- Run `bats tests/` after touching `.scripts/*.sh`; the suite sources them in a sandboxed `HOME`/`DOTFILES_DIR`.
- `copy` into a non-active flavour only writes the `.age`; it materializes (and goes live) when you switch to that flavour. Copy into the active flavour or `common` restows immediately.
- Don't put the same target path in both `common` and a machine flavour — stow will refuse the overlap.
