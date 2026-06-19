# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles managed with **GNU Stow**, layered with a **flavour system** (per-machine configs) and **Age encryption** for secrets. Pure Bash + Stow — no build step, no test suite. The two executables are `bootstrap` and `dotfiles`; all logic lives in `.scripts/*.sh`.

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
- `age.sh` — keypair init, encrypt/decrypt, `reencrypt-all`.
- `flavours.sh` — flavour resolution, the decrypt→stow workflow, change re-encryption, and `flavour_place_file` (writes a file into a flavour, encrypted or not, and keeps the decrypted workspace in sync).
- `add.sh` — adopting regular (`add_regular_file`) vs flavour (`flavour_add_file`) files; `move_to_flavour` and `copy_flavour_file`.

**Stow packages.** Top-level non-hidden directories except `flavours` are stow packages (`apps`, `bin`, `config`, `home`, `nvim`), discovered dynamically in `dotfiles`. Stow runs with `--dotfiles --no-folding`, so a `dot-config` component becomes `~/.config` and directories are materialized as real dirs with per-file symlinks (this lets regular packages and the flavour layers safely share parent dirs like `~/.config`). When adopting/moving files, the full `$HOME`-relative path is converted via `home_to_stow_path` (every dotted component → `dot-`), so nested configs like `~/.config/nvim/init.lua` map correctly.

**Flavours** (`personal`, `work`, `server`, or custom) **plus the always-applied `common` layer.** The active machine flavour is stored in `~/.dotconfig` (`git config -f ~/.dotconfig core.flavour`). On stow, both `common` (if present) and the active flavour are layered on top of the regular packages: `flavour_prepare_stow` decrypts `flavours/<layer>/*.age` into `flavours/decrypted-<layer>/`, which is what gets stowed. `common` is **not** a selectable flavour (excluded from `flavour`/switch); it holds configs shared across all machines. The decrypted directory is the **local source of truth**: existing decrypted files (your edits) are preserved, `dotfiles status` re-encrypts changed ones back into `flavours/<layer>/`, and a flavour switch first re-encrypts + unstows the outgoing flavour (keeping its decrypted dir). Decrypted dirs are removed on uninstall/`flavour_cleanup_stow`. **Do not place the same target file in both `common` and a machine flavour** — they'd collide at stow time.

**Encryption is the default** for flavour files (`add`/`move`/`copy`). Opt out per-invocation with `-p`, interactively at the prompt, or via `DOT_FORCE_NO_ENCRYPT`. `flavour_encrypt_changes` writes each file back in the form it already has (`.age` stays encrypted, plaintext stays plaintext) and encrypts brand-new files by default.

**Age encryption.** Private key: `.age/keys.txt` (gitignored, generated on first install). Public keys: `.age/recipients.txt` — one block per machine, all files encrypted to every recipient. Multi-machine flow: a new machine generates its own keypair and appends its pubkey to recipients; if it can't decrypt existing files, you must run `dotfiles reencrypt-all` on a machine that *can* decrypt, then pull.

**Submodules** (clone with `--recursive`): `nvim/dot-config/nvim` (Neovim config) and `config/dot-config/tmux/plugins/tpm` (tmux plugin manager).

## Gotchas

- After editing a flavour file, run `dotfiles status` to re-encrypt it before committing — the `.age` file is what's tracked, not the decrypted copy. (`status` covers the active flavour + `common`; a switch also re-encrypts the outgoing flavour.)
- Adding a new recipient requires a `reencrypt-all` from a machine that can already decrypt, or the new machine gets undecryptable placeholders.
- `copy` into a non-active flavour only writes the `.age`; it materializes (and goes live) when you switch to that flavour. Copy into the active flavour or `common` restows immediately.
- Don't put the same target path in both `common` and a machine flavour — stow will refuse the overlap.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->
