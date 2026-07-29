# Git workflow rules

These are enforced by a `PreToolUse` hook (`~/.config/claude/hooks/git-guard.sh`),
not just by convention. Violating them returns a hard denial, so follow them
proactively rather than discovering them by being blocked.

## Never work directly on a protected branch

Protected: `main`, `master`, `develop`, `production`.

Before the first commit of any change, create a working branch:

```bash
git switch -c <type>/<short-description>
```

Types: `feat/`, `fix/`, `chore/`, `refactor/`, `docs/`, `test/`.

While HEAD is on a protected branch, these are **denied**: `commit`, `merge`,
`rebase`, `reset --hard`, `cherry-pick`, `revert`, `am`, `apply`, `push`.
Read-only commands (`status`, `diff`, `log`, `show`, `fetch`) and `switch` /
`checkout` / `branch` always work — that is how you get onto a working branch.

If you are already on a protected branch with uncommitted work, do not try to
commit it. Create the branch first; uncommitted changes carry over.

## Never force-push

`git push --force`, `-f`, and `--force-with-lease` are denied on **every**
branch, as is a `+refspec`. Force-pushing rewrites published history. If a
force-push is genuinely required, say so and let the user run it.

Local history rewriting on a working branch (`rebase -i`, `commit --amend`,
`reset --hard`) is allowed. Just do not push the result with force.

## Never push to a protected branch

Denied even from a working branch, so `git push origin main` and
`git push origin HEAD:main` will both fail. Push the working branch and open a
pull request:

```bash
git push -u origin <branch>
gh pr create --fill
```

## Commits

- One logical change per commit. Do not bundle unrelated edits.
- Imperative subject line, no trailing period, ~72 chars.
- Conventional-commit prefixes where the repository already uses them — check
  `git log --oneline -20` first and match the existing style.
- Stage deliberately. Never `git add -A` without checking `git status` first;
  it picks up build artefacts and unrelated work in progress.
- Do not commit secrets, credentials, `.env` files, or large binaries.

## Overrides

The protected-branch check can be disabled for a session by the user setting
`CLAUDE_ALLOW_PROTECTED_BRANCH=1` before launching `claude`. You cannot set this
yourself — it is read from the launching environment. The force-push and
push-to-protected rules are not overridable this way.

The protected branch list can be changed with `CLAUDE_PROTECTED_BRANCHES`
(space-separated), also set before launch.
