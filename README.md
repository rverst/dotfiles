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
  local/dot-local/scripts/secret   # keyring-backed runtime secrets (see below)
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

## Runtime secrets (`secret`)

Age encryption protects *files at rest*. It does nothing for **runtime**
secrets — API tokens a tool needs in its environment. Putting those in
`~/.localrc` means two problems: they sit in cleartext on disk, and `export`
hands them to **every** process the shell ever launches (any `npm` postinstall
script, any random CLI). `secret` fixes both.

`local/dot-local/scripts/secret` stores values in the OS keyring and injects
them into **one** child process at a time. `~/.local/scripts` is already on
`PATH`, so it works from zsh, bash, `.envrc`, a Makefile or a build script.

```
secret set <name>                 store a value (hidden prompt, never in argv/history)
secret get <name>                 print a value to stdout
secret rm <name>                  delete a value
secret list                       list stored names (no values)
secret run <NAME>... -- <cmd>...  run cmd with NAME exported, and nothing else
secret sync <name> [item]         pull one value from the vault into the keyring
secret sync --all                 pull every item of the vault folder
secret sync --list                list vault item names (no values)
```

Backends are auto-detected: `security(1)` on macOS (login keychain, already
unlocked, no prompt), `secret-tool(1)` on Linux (needs **libsecret** —
`libsecret-tools` on Debian/Ubuntu, `libsecret` on Arch/Fedora — plus a running
keyring daemon), and `pwsh.exe` on **WSL2** (see below). Server flavours have no
keyring; `secret` errors cleanly there. `SECRET_BACKEND` forces a specific one.

`get` **fails loudly** when a secret is missing rather than printing an empty
string, so you get a clear error instead of a confusing `401` from the far end.

### WSL2 / Windows

Windows' keychain is reached through **PowerShell 7 + SecretManagement**, over
WSL interop — so the same `secret` script, and the same commands, work inside a
WSL2 distro. PowerShell 5.1 is deliberately not supported: its UTF-16LE/CRLF
output makes the boundary needlessly painful.

One-time setup, on the **Windows** side:
```powershell
winget install Microsoft.PowerShell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Set-SecretStoreConfiguration -Authentication None -Interaction None
```

The script keeps values off the command line: the PowerShell snippet travels in
`-EncodedCommand`, the verb and name travel in environment variables (forwarded
with `WSLENV`), and the **value only ever crosses on stdin/stdout, base64-encoded
both ways** — invisible in the Windows process list, and immune to encoding and
quoting problems. That is actually stricter than the macOS path, where
`security(1)` forces the value through `argv`.

Notes:

- Each interop call costs a few hundred milliseconds. `secret run A B C` batches
  into a **single** call, but don't put `secret get` in a shell prompt or a loop.
- The vault lives in the Windows user profile, so it is shared across every WSL
  distro and native Windows tooling. Usually what you want.
- `Authentication None` trades the unlock prompt for DPAPI-only protection at
  rest. Reasonable on a single-user laptop; a conscious tradeoff, not an oversight.
- `secret sync` needs no special handling — `rbw` and `keepassxc-cli` run
  natively inside WSL, and only the store step crosses the boundary.
- If `secret` can't find `pwsh.exe`, check `appendWindowsPath` in `/etc/wsl.conf`;
  the default install location is probed as a fallback.

### The vault as the source of truth

The keyring is a fast local cache; the **vault** is where secrets are backed up
and rotated. Two vault backends are supported, and `secret sync` treats them
identically:

| backend | tool | good for |
| --- | --- | --- |
| `rbw` | [`rbw`](https://git.tozt.net/rbw) | Bitwarden / Vaultwarden (a server you or someone else hosts) |
| `keepassxc` | `keepassxc-cli` | a local `.kdbx` file — no server, syncs over whatever you already use |

Detection order: `SECRET_VAULT` if set → a configured `SECRET_KEEPASS_DB` with
`keepassxc-cli` present → `rbw` → `keepassxc-cli`. So on a machine with both,
pointing `SECRET_KEEPASS_DB` at a database is enough to choose KeePass, and
`SECRET_VAULT=rbw` overrides even that.

#### Vault layout

One convention for both backends:

- a **folder** (Bitwarden) / **group** (KeePass) named `dotfiles` —
  override with `SECRET_VAULT_FOLDER`;
- **one item per secret**, the item name being exactly the secret name
  (`GITLAB_TOKEN`, `NPM_REGISTRY_TOKEN`);
- the value in the **password** field — override with `SECRET_VAULT_FIELD`.

```
dotfiles/
├── GITLAB_TOKEN        password: glpat-…
├── NPM_REGISTRY_TOKEN  password: npm_…
└── OPENAI_API_KEY      password: sk-…
```

That is what makes `secret sync --all` work: it enumerates the folder and pulls
everything in one unlock. Items whose name isn't a valid secret name (spaces,
`/`, a regular login you parked there) are **skipped with a warning**, not a
failure — including anything in a nested group, so keep the layout flat. Items
with a name that differs from the variable still work the old way:
`secret sync MY_TOKEN some-oddly-named-item`.

#### Bitwarden / Vaultwarden (`rbw`)

`rbw` (in the `Brewfile`) is used instead of the official `bw` because `bw`
makes you keep a long-lived `BW_SESSION` token in your environment — exactly
what this whole setup exists to avoid. `rbw-agent` caches the unlock, so you
type the master password once per `lock_timeout`, not once per command.

```bash
rbw config set base_url https://your-vaultwarden.example.com
rbw config set email you@example.com
rbw login
secret sync --all               # vault folder -> keyring
```

> A YubiKey/passkey **cannot** replace the master password for CLI unlock.
> Bitwarden's YubiKey support is 2FA at login only; biometric/FIDO2 unlock is a
> desktop-app and browser feature the CLI can't reach. The agent's cache is the
> practical answer to prompt fatigue.

#### KeePassXC (`keepassxc-cli`)

No server, no account: a single `.kdbx` file you sync however you like.
`keepassxc-cli` ships with the KeePassXC app (`brew install --cask keepassxc`,
`apt install keepassxc`); it is deliberately **not** in the `Brewfile`, since
it's a per-machine choice.

Configure it with environment variables at the bottom of `~/.localrc` (which is
per-flavour and encrypted, so it's the right place):

```bash
export SECRET_KEEPASS_DB="$HOME/Sync/passwords.kdbx"
# optional:
export SECRET_KEEPASS_KEYFILE="$HOME/.config/keepass/key"
export SECRET_KEEPASS_YUBIKEY=1              # or 1:7370001
export SECRET_KEEPASS_NO_PASSWORD=1          # key-file / YubiKey-only database
export SECRET_VAULT_FOLDER=dotfiles          # the group inside the database
```

```bash
secret sync --list              # what's in the group
secret sync --all               # group -> keyring
```

The passphrase is read **once per run** from a hidden prompt and handed to each
`keepassxc-cli` call on **stdin** — never in argv, so it never shows up in `ps`.
It is also accepted on stdin non-interactively (`printf '%s\n' "$pw" | secret
sync --all`), which is how the test suite drives it.

Two honest caveats: KeePassXC has **no agent**, so every item costs one full
KDF derivation — `sync --all` over a high-round database takes a few seconds
per item. And there is nothing like `rbw sync`: the `.kdbx` is only as fresh as
whatever file sync you put under it.

### Using secrets

**Transparent shell wrappers** — keep these at the **bottom** of `~/.localrc`,
below its own `PATH` exports: the `$+commands` guards resolve at definition
time, so a tool added to `PATH` later in the file wouldn't be seen.

```zsh
# wrap tools that need a token, without exporting it globally
for _tool in glab gitlab-mr; do
  (( $+commands[$_tool] )) && eval "
    ${_tool}() { secret run GITLAB_TOKEN GITLAB_API_TOKEN -- command ${_tool} \"\$@\" }"
done
for _tool in npm npx; do
  (( $+commands[$_tool] )) && eval "
    ${_tool}() { secret run NPM_REGISTRY_TOKEN -- command ${_tool} \"\$@\" }"
done
for _tool in mvn mvnd; do
  (( $+commands[$_tool] )) && eval "
    ${_tool}() { secret run GITLAB_TOKEN -- command ${_tool} \"\$@\" }"
done
unset _tool
```

Config files then reference the variable instead of holding the secret:
`~/.npmrc` → `:_authToken=${NPM_REGISTRY_TOKEN}`, `~/.m2/settings.xml` →
`<value>${env.GITLAB_TOKEN}</value>`. Both files are then safe to adopt into a
flavour.

**Per-project via direnv** (already hooked in `.zshrc`). This is the more
important mechanism — see the caveat below. The file holds only a *reference*,
so it is safe to commit:
```bash
# ~/Dev/<work-tree>/.envrc
export GITLAB_TOKEN="$(secret get GITLAB_TOKEN)"
export NPM_REGISTRY_TOKEN="$(secret get NPM_REGISTRY_TOKEN)"
```

**Docker** — use BuildKit secrets. Never `--build-arg`: build args are baked
into the image and visible in `docker history`.
```dockerfile
RUN --mount=type=secret,id=npmtoken \
    NPM_REGISTRY_TOKEN="$(cat /run/secrets/npmtoken)" npm ci
```
```bash
secret run NPM_REGISTRY_TOKEN -- docker build --secret id=npmtoken,env=NPM_REGISTRY_TOKEN .
```
Compose supports the same through `build.secrets`.

### Known gap

Shell wrappers only catch commands the **interactive shell** resolves. They do
**not** cover `./mvnw` (invoked by path, so shell functions are bypassed),
IDE-launched builds, or anything started from Spotlight/Dock. Since the
templated `.npmrc`/`settings.xml` *require* the variable, those paths break.
The `.envrc` at the work-tree root is the actual fix — it covers `./mvnw` and
anything else run from a shell in that tree. For an IDE, launch it from inside
the tree (`idea .`) so it inherits the environment, or set the variables in its
run configuration.

### Rotating a secret

```bash
rbw sync && secret sync GITLAB_TOKEN    # Bitwarden, after rotating in the vault
secret sync GITLAB_TOKEN                # KeePass, after saving the .kdbx
secret sync --all                       # or just re-pull everything
secret set GITLAB_TOKEN                 # or type the new value directly
```
Nothing else changes: no file to edit, no re-encryption, no commit.

---

## Runtime versions (Java / Node)

Two autoloaded zsh functions switch the runtime for the current shell:

```bash
setJava      # fzf picker over every installed JDK
setJava 21   # switch to JDK 21 (major, or a prefix like 21.0)
setNode      # fzf picker over every installed Node
setNode 22   # switch to Node 22
```

Both set `PATH` (and `setJava` also `JAVA_HOME`), **removing the previously
selected entry first**, so repeated calls are idempotent and `PATH` never
grows. Nothing is hardcoded: the installed versions are discovered at call time
by `~/.local/scripts/jdk-home` and `~/.local/scripts/node-bin`. Asking for a
version that is not installed fails loudly and lists what is.

> Homebrew symlinks every *unreleased* versioned alias at the current
> unversioned keg — `node@23` … `node@26` can all point at `Cellar/node/26.5.1`.
> `node-bin` reads the version from the resolved Cellar directory and dedupes,
> so it will not silently hand you a different major.

**Defaults per machine** are pinned in the flavour's `~/.localrc`, which
`.zshrc` sources after the functions are autoloaded:

```zsh
setJava -q 21   # -q: switch silently
```

### Per-project, automatically

`direnv` (already hooked in `.zshrc`) gains `use java` / `use node` from
`config/dot-config/direnv/direnvrc`:

```bash
# ~/Dev/<project>/.envrc
use java 21
use node 22
```

With no argument, `use java` reads `.java-version` and `use node` reads
`.node-version` or `.nvmrc`, so repos that already carry one need a one-line
`.envrc`. direnv restores the previous environment when you leave the tree.

**Scope.** direnv walks *up* and loads the nearest `.envrc`, which then applies
to every subdirectory. One `~/Dev/work/.envrc` with `use java 21` covers all
projects beneath it after a single `direnv allow`.

**Caveat.** A child `.envrc` *replaces* the parent rather than merging. Start
the child with `source_up_if_exists` to inherit:

```bash
# ~/Dev/work/someproject/.envrc
source_up_if_exists
use node 22        # keeps the parent's java, overrides only node
```

---

## Development

```bash
bats tests/          # run the suite (sandboxed HOME/DOTFILES_DIR)
shellcheck -x dotfiles bootstrap .scripts/*.sh .githooks/pre-commit tests/*.bash local/dot-local/scripts/secret
```

Notes:

- `print.sh` logging helpers and `_age_build_identities` must always `return 0`
  — they run under `set -o errexit`, so a short-circuited `[ test ] && cmd` on
  the last line would abort the caller.
- Run the suite after touching any `.scripts/*.sh`.
- Submodules (clone with `--recursive`): `nvim/dot-config/nvim` and
  `config/dot-config/tmux/plugins/tpm`.
