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
./dotfiles add <file> [flavour|regular] [pkg]    # Adopt an existing file into the dotfiles
./dotfiles reencrypt-all                         # Re-encrypt every .age file against current recipients
```

Global flags (before the command): `-n` dry run, `-s` silent, `-u` unattended (non-interactive; defaults flavour to `server`).

`bootstrap` runs `dotfiles` under `bash` deliberately — the scripts use bashisms and must not be run under zsh/sh.

## Architecture

**Entry points.** `bootstrap` ensures dependencies (`zsh`, `stow`, `age`) via Homebrew (macOS) or the native package manager (Linux: apt/pacman/dnf/zypper/apk), then invokes `dotfiles install`. `dotfiles` parses options/commands in `main()` and sources the `.scripts/` modules:
- `print.sh` — colored logging (`info`/`success`/`warn`/`error`) and interactive prompts (`user_read`, `user_yesno`). All prompts write to stderr so command substitution stays clean.
- `utils.sh` — `resolve_path`, plus first-run setup of `~/.gitconfig.local` and `~/.localrc`.
- `age.sh` — keypair init, encrypt/decrypt, `reencrypt-all`.
- `flavours.sh` — flavour resolution, the decrypt→stow workflow, and change re-encryption.
- `add.sh` — adopting regular (`add_regular_file`) vs flavour (`flavour_add_file`) files.

**Stow packages.** Top-level non-hidden directories except `flavours` are stow packages (`apps`, `bin`, `config`, `home`, `nvim`), discovered dynamically in `dotfiles`. Stow runs with `--dotfiles`, so a file named `dot-config` becomes `~/.config`. When adopting files, leading `.` is rewritten to the `dot-` prefix. `nvim` reflects the package's repo-relative path: `nvim/dot-config/nvim` → `~/.config/nvim`.

**Flavours** (`personal`, `work`, `server`, or custom). The active flavour is stored in `~/.dotconfig` (read/written via `git config -f ~/.dotconfig core.flavour`). On stow, `flavour_prepare_stow` decrypts `flavours/<flavour>/*.age` into a working directory `flavours/decrypted-<flavour>/`, which is the package that actually gets stowed. That decrypted directory is the **local source of truth**: it is never blindly overwritten — existing decrypted files (your edits) are preserved, and `dotfiles status` re-encrypts changed ones back into `flavours/<flavour>/*.age`. It is removed only on uninstall/flavour-switch (`flavour_cleanup_stow`).

**Age encryption.** Private key: `.age/keys.txt` (gitignored, generated on first install). Public keys: `.age/recipients.txt` — one block per machine, all files encrypted to every recipient. Multi-machine flow: a new machine generates its own keypair and appends its pubkey to recipients; if it can't decrypt existing files, you must run `dotfiles reencrypt-all` on a machine that *can* decrypt, then pull. In `add.sh`/`flavours.sh`, encryption is auto-suggested by filename heuristics (names containing `secret`/`private`/`key`/`token`/`password`, or `.gitconfig`/`.zshrc`/`.bashrc`/`.profile`).

**Submodules** (clone with `--recursive`): `nvim/dot-config/nvim` (Neovim config) and `config/dot-config/tmux/plugins/tpm` (tmux plugin manager).

## Gotchas

- After editing a flavour file, run `dotfiles status` to re-encrypt it before committing — the `.age` file is what's tracked, not the decrypted copy.
- Adding a new recipient requires a `reencrypt-all` from a machine that can already decrypt, or the new machine gets undecryptable placeholders.
- `.gitignore` has a typo — it ignores `flavours/decrytped-*/` (note the misspelling), so the real `flavours/decrypted-*/` dirs are *not* ignored; `flavours/.stow-local-ignore` keeps them out of stow but they are not git-ignored.

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
