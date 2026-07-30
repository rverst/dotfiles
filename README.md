# dotfiles

Personal dotfiles managed with [GNU Stow](https://www.gnu.org/software/stow/),
layered with a **flavour system** for per-machine configs and
[**Age**](https://age-encryption.org/) encryption for secrets.

Pure Bash + Stow — no build step, no framework. Two executables (`bootstrap`,
`dotfiles`); all logic lives in `.scripts/*.sh`. A [`bats`](https://github.com/bats-core/bats-core)
suite lives in `tests/` and CI additionally runs `shellcheck`.

---

## TL;DR — new machine

```bash
# 1. Install deps (zsh, stow, age; gitleaks best-effort) and stow everything
git clone --recursive https://github.com/rverst/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap                 # add --set-default-zsh to also chsh to zsh
```

`bootstrap` installs dependencies, then runs `dotfiles install`, which stows all
packages for the resolved flavour. If this machine can't yet decrypt existing
secrets, see [Recovery](#encryption--recovery).

---

## Concepts

### Stow packages

Every top-level non-hidden directory except `flavours` and `tests` is a Stow
package (`apps`, `config`, `home`, `local`, `nvim`), discovered dynamically.
Stow runs with `--dotfiles --no-folding`:

- `--dotfiles` maps a `dot-foo` path component to `~/.foo` (so
  `config/dot-config/nvim/init.lua` → `~/.config/nvim/init.lua`).
- `--no-folding` materializes real directories with **per-file** symlinks
  instead of symlinking whole directories. This is what lets regular packages
  and the flavour layers safely share parent dirs like `~/.config`.

Conventions enforced by `add`/`move`:

| Package | Owns | Example |
| ------- | ---- | ------- |
| `config` | everything under `~/.config` | `config/dot-config/...` |
| `local`  | everything under `~/.local`  | `local/dot-local/scripts/...` |
| `home`   | `$HOME`-root dotfiles        | `home/dot-gitconfig`, `home/dot-zshenv` |

Payload inside a package that must **not** be stowed (e.g. `apps/Brewfile`) is
excluded via a `.stow-local-ignore` in that package.

### Flavours + the `common` layer

A **flavour** is a per-machine profile: `personal`, `work`, `server`, or a
custom name. The active flavour is stored in `~/.dotconfig`
(`git config -f ~/.dotconfig core.flavour`).

On stow, two layers are applied **on top of** the regular packages:

1. `common` — shared across all machines. Always applied if present. **Not**
   selectable as a flavour.
2. the active machine flavour.

> ⚠️ Never put the same target path in both `common` and a machine flavour —
> Stow refuses the overlap.

Flavour files are stored encrypted (`flavours/<layer>/*.age`) and decrypted at
stow time into `flavours/decrypted-<layer>/` (gitignored). **The decrypted dir
is the local source of truth**: your edits there are preserved, and
`dotfiles status` (or the pre-commit hook) re-encrypts changed files back into
`flavours/<layer>/`.

### Age encryption

- **Per-machine key:** `.age/keys.txt` (gitignored, generated on first install).
- **Recipients:** `.age/recipients.txt` — one public-key block per machine.
  `age_ensure_recipient` de-dupes, so re-adding a machine is a no-op.
- **Master recovery key:** `.age/master.txt` (public, committed) is **always**
  an encryption recipient. Its private half `.age/master-key.txt` (gitignored)
  is generated once on first init — **copy it into your password manager**, then
  you may delete the file.

Every secret is encrypted to all machine recipients **plus** the master key.
Decryption tries, in order: the machine key → `$DOT_RECOVERY_KEY` → the master
key. So any file is recoverable with the master key alone.

### Secret scanning

The pre-commit hook runs [`gitleaks`](https://github.com/gitleaks/gitleaks)
over staged changes to stop a **plaintext** secret from being committed into a
regular package. This repo's real secrets are always Age ciphertext (`*.age`)
or gitignored `decrypted-*` workspaces — both allowlisted in `.gitleaks.toml` —
so the scan only fires on unencrypted credentials that slipped through.

`gitleaks` is best-effort: `bootstrap` installs it when it can, and the hook
skips the scan with a warning when it's absent. Install manually with
`brew install gitleaks` (or your package manager).

---

## Layout

```
bootstrap              # new-machine entry point: install deps, then `dotfiles install`
dotfiles               # the CLI (install/status/flavour/add/move/copy/...)
.scripts/
  print.sh             # colored logging + interactive prompts (all to stderr)
  utils.sh             # path helpers (home_to_stow_path etc.), first-run setup
  age.sh               # keypair/master-key init, encrypt/decrypt, reencrypt-all
  flavours.sh          # flavour resolution, decrypt→stow, re-encrypt, place-file
  add.sh               # adopt/move/copy files (regular vs flavour)
.githooks/pre-commit   # re-encrypt edits, verify decryptability, gitleaks scan
.gitleaks.toml         # secret-scanner config (allowlists this repo's ciphertext)
.age/                  # keys, recipients, master key
apps/ config/ home/ local/ nvim/   # stow packages
flavours/<name>/       # encrypted per-flavour payload (+ decrypted-<name>/ at runtime)
tests/                 # bats suite
```

---

## Command reference

```
dotfiles [options] <command> [args]
```

| Command | What it does |
| ------- | ------------ |
| `install` | Init age, enable git hooks, stow all packages for the current flavour. |
| `reinstall` | Restow (unlink → relink). Used after switching flavour. |
| `uninstall` | Unstow all packages; remove decrypted workspaces. |
| `update` | Refuse if dirty, else unstow → `git pull` + submodule update → restow. |
| `status` | `git status` + re-encrypt changed flavour/`common` files. |
| `flavour [name]` | Show current flavour, or switch to `name`. |
| `add <file> [flavour\|common\|regular] [name\|pkg]` | Adopt an existing file. |
| `move <file> [flavour]` | Move a regular-package file into a flavour. |
| `copy <file> <from> <to>` | Copy a file between flavours as a template. |
| `reencrypt-all` | Re-encrypt every `.age` against the current recipient set. |

**Global options** (before the command): `-n` dry run · `-s` silent ·
`-u` unattended (non-interactive; defaults flavour to `server`) · `-p` plaintext
(skip encryption for `add`/`move`/`copy`).

Encryption is the **default** for flavour files. `add`/`move`/`copy` and
`reencrypt-all` refuse to run if this machine can't decrypt existing secrets
(so you can never add content you couldn't read back). After `add`/`move`/`copy`
and `reencrypt-all`, an interactive session offers to commit the result.

---

## Common workflows

**Adopt a config file into the current flavour (encrypted):**
```bash
dotfiles add ~/.config/foo/config.toml flavour
```

**Adopt a non-secret file into a regular package:**
```bash
dotfiles add ~/.config/bar/bar.conf regular    # routed to the `config` package
```

**Edit a secret:** edit the decrypted copy under `flavours/decrypted-<layer>/`
(it's what's symlinked into `$HOME`), then:
```bash
dotfiles status        # re-encrypts changed files back into flavours/<layer>/
git commit             # pre-commit hook also re-encrypts + scans as a backstop
```

**Switch flavour** (re-encrypts + unstows the outgoing flavour, then stows the new one):
```bash
dotfiles flavour work
```

**Add a new machine to the recipient set:** the new machine generates its own
keypair on first `install` and appends its pubkey to `recipients.txt`. Because
existing `.age` files aren't yet encrypted to it, run **on a machine that can
already decrypt**:
```bash
dotfiles reencrypt-all && git push
```
then `git pull` on the new machine. (Or recover via the master key — below.)

---

## Encryption & recovery

The pre-commit hook (`git config core.hooksPath .githooks`, set by
`dotfiles install`) guarantees what you commit stays readable:

1. Re-encrypts any edited `decrypted-*` workspace.
2. If `recipients.txt`/`master.txt` changed, re-encrypts everything.
3. **Blocks the commit if any staged `.age` can't be decrypted on this machine.**
4. Runs the gitleaks secret scan.

**Recovering a wiped machine** (no machine key, can't decrypt): export the master
key from your password manager and either drop it at `.age/master-key.txt`, or:
```bash
DOT_RECOVERY_KEY=/path/to/master-key.txt dotfiles reencrypt-all
```
then commit/push so this machine's key becomes a recipient going forward.

---

## Development

```bash
bats tests/          # run the suite (sandboxed HOME/DOTFILES_DIR)
shellcheck -x dotfiles bootstrap .scripts/*.sh .githooks/pre-commit tests/*.bash
```

Notes:

- `print.sh` logging helpers and `_age_build_identities` must always `return 0`
  — they run under `set -o errexit`, so a short-circuited `[ test ] && cmd` on
  the last line would abort the caller.
- Run the suite after touching any `.scripts/*.sh`.
- Submodules (clone with `--recursive`): `nvim/dot-config/nvim` and
  `config/dot-config/tmux/plugins/tpm`.
