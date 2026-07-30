#!/usr/bin/env bash
#
# Claude Code PreToolUse guard for the Bash tool.
#
# Enforces, by returning permissionDecision=deny:
#   1. No commit/merge/rebase/reset --hard/cherry-pick/revert/am/apply/push
#      while HEAD is on a protected branch.
#   2. No push to a protected branch by explicit refspec, from any branch.
#   3. No force-push to a remote, from any branch.
#   4. No obviously destructive shell commands (sudo rm, rm -rf /, rm -rf ~,
#      chmod 777, curl|wget piped into a shell).
#
# WHY A HOOK AND NOT permissions.deny:
#   The `rtk hook claude` PreToolUse hook rewrites commands before execution
#   (`git push --force` -> `rtk git push --force`). Claude Code documents
#   re-evaluation of a rewritten input against deny rules for PermissionRequest
#   only, not for PreToolUse, so a `Bash(git push --force*)` deny rule is not
#   dependable here. Hooks all receive the ORIGINAL input and run in parallel,
#   and `deny` outranks every other decision (deny > defer > ask > allow), so
#   this guard cannot be bypassed by the rewrite.
#
# CONFIGURATION (read from Claude Code's inherited environment, so a coding
# agent cannot set these mid-session -- only you can, before launching claude):
#   CLAUDE_PROTECTED_BRANCHES    space-separated; default below
#   CLAUDE_ALLOW_PROTECTED_BRANCH=1   disable check 1 and 2 for the session
#
# Never blocked: switch, checkout, branch, status, diff, log, show, fetch.
# Those are how the agent gets itself off a protected branch.

set -uo pipefail

PROTECTED_BRANCHES=${CLAUDE_PROTECTED_BRANCHES:-"main master develop production"}

# --- output -----------------------------------------------------------------

deny() {
	jq -n --arg reason "$1" '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: $reason
		}
	}'
	exit 0
}

# --- input ------------------------------------------------------------------

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Cheap bail-out: if none of the interesting words appear, do no further work.
# Substring false positives (e.g. "format" contains "rm") are harmless because
# the per-segment parser only ever looks at a segment's first real token.
case "$cmd" in
*git* | *rm* | *chmod* | *sudo* | *curl* | *wget*) ;;
*) exit 0 ;;
esac

# --- branch helpers ---------------------------------------------------------

# True when a path argument refers to the filesystem root or the whole home
# directory. Both the expanded form and the literal text an agent may have
# written (~, $HOME) are checked, since the hook sees the command unexpanded.
is_root_or_home() {
	local target=${1%/} # trailing slash is irrelevant
	target=${target%/\*}       # 'rm -rf /*' is 'rm -rf /'
	# Deliberately unexpanded: matches the literal text an agent may have typed.
	# shellcheck disable=SC2016
	local literal_home='$HOME'
	case "$target" in
	'' | / | '~' | "$literal_home") return 0 ;;
	esac
	[ -n "${HOME:-}" ] && [ "$target" = "${HOME%/}" ] && return 0
	return 1
}

branch_is_protected() {
	local candidate=$1 p
	[ -n "$candidate" ] || return 1
	[ "$candidate" != "HEAD" ] || return 1 # detached HEAD
	for p in $PROTECTED_BRANCHES; do
		[ "$candidate" = "$p" ] && return 0
	done
	return 1
}

# Resolved lazily and cached: only shells out to git when a git op is found.
_head_branch=""
_head_branch_known=0
head_branch() {
	if [ "$_head_branch_known" -eq 0 ]; then
		_head_branch=$(git -C "$git_dir_opt" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
		_head_branch_known=1
	fi
	printf '%s' "$_head_branch"
}

# --- segment splitting ------------------------------------------------------

# Split on shell operators so each subcommand is inspected on its own, and
# expose command substitutions. Over-splitting is safe: a nonsense fragment
# simply has a first token that is not one we act on. Under-splitting is the
# only real risk, hence being liberal here.
#
# Pure bash expansion is used rather than sed because BSD sed (macOS) does not
# interpret \n in a replacement.
split=${cmd//&&/$'\n'}
split=${split//\|\|/$'\n'}
split=${split//|/$'\n'}
split=${split//;/$'\n'}
split=${split//\$(/$'\n'}
split=${split//)/$'\n'}
split=${split//\`/$'\n'}

# Pipe-to-shell needs whole-command context: after splitting, `curl x | sh`
# is two segments, so remember whether a downloader appeared anywhere.
downloader_present=0
case "$cmd" in
*curl* | *wget*) downloader_present=1 ;;
esac

git_dir_opt="."

while IFS= read -r segment; do
	[ -n "${segment//[[:space:]]/}" ] || continue

	# Word-split the segment; this also trims surrounding whitespace.
	read -r -a tokens <<<"$segment"
	[ "${#tokens[@]}" -gt 0 ] || continue

	# `read -a` splits words but performs no quote removal, so a token can
	# arrive as "$HOME/" with the quote characters attached. Peel one layer of
	# matching outer quotes so target comparisons see the bare word.
	for ti in "${!tokens[@]}"; do
		t=${tokens[$ti]}
		case "$t" in
		\"*\") t=${t:1:${#t}-2} ;;
		\'*\') t=${t:1:${#t}-2} ;;
		esac
		tokens[ti]=$t
	done

	# Strip leading `VAR=value` assignments and wrapper commands to find the
	# real executable. Track sudo separately, it is itself a signal.
	saw_sudo=0
	idx=0
	while [ "$idx" -lt "${#tokens[@]}" ]; do
		token=${tokens[$idx]}
		case "$token" in
		sudo | doas)
			saw_sudo=1
			idx=$((idx + 1))
			continue
			;;
		rtk | env | command | nice | nohup | time)
			idx=$((idx + 1))
			continue
			;;
		-*)
			# A flag before the executable belongs to the wrapper; skip it.
			idx=$((idx + 1))
			continue
			;;
		*=*)
			# Only a syntactically valid NAME=... is an assignment.
			name=${token%%=*}
			case "$name" in
			'' | *[!A-Za-z0-9_]*) break ;;
			*)
				idx=$((idx + 1))
				continue
				;;
			esac
			;;
		*) break ;;
		esac
	done
	[ "$idx" -lt "${#tokens[@]}" ] || continue

	exe=${tokens[$idx]}
	exe=${exe##*/} # tolerate /usr/bin/git
	args=("${tokens[@]:$((idx + 1))}")

	case "$exe" in

	# ---- 4. destructive shell ------------------------------------------
	sh | bash | zsh | dash)
		if [ "$downloader_present" -eq 1 ]; then
			deny "Refusing to pipe downloaded content into a shell. Download to a file, inspect it, then run it deliberately."
		fi
		;;

	rm)
		if [ "$saw_sudo" -eq 1 ]; then
			deny "Refusing to run 'sudo rm'. Remove files without elevated privileges, or ask the user to do it."
		fi
		recursive=0
		for a in ${args+"${args[@]}"}; do
			case "$a" in
			--recursive | --force) recursive=1 ;;
			-*[rRf]*) recursive=1 ;;
			esac
		done
		if [ "$recursive" -eq 1 ]; then
			for a in ${args+"${args[@]}"}; do
				case "$a" in
				-*) continue ;;
				esac
				if is_root_or_home "$a"; then
					deny "Refusing 'rm -rf' against '$a'. That would delete the filesystem root or the entire home directory."
				fi
			done
		fi
		;;

	chmod)
		for a in ${args+"${args[@]}"}; do
			case "$a" in
			777 | 0777 | a+rwx | -R777)
				deny "Refusing 'chmod $a'. World-writable permissions are almost never the right fix; set a narrower mode."
				;;
			esac
		done
		;;

	# ---- git ------------------------------------------------------------
	git)
		# Peel git's global options to find the subcommand, and honour -C so
		# branch detection inspects the repository git will actually act on.
		gidx=0
		while [ "$gidx" -lt "${#args[@]}" ]; do
			case "${args[$gidx]}" in
			-C)
				git_dir_opt=${args[$((gidx + 1))]:-.}
				_head_branch_known=0
				gidx=$((gidx + 2))
				;;
			-c | --exec-path | --git-dir | --work-tree | --namespace)
				gidx=$((gidx + 2))
				;;
			--git-dir=* | --work-tree=* | -c*)
				gidx=$((gidx + 1))
				;;
			-*)
				gidx=$((gidx + 1))
				;;
			*)
				break
				;;
			esac
		done
		[ "$gidx" -lt "${#args[@]}" ] || continue

		sub=${args[$gidx]}
		subargs=("${args[@]:$((gidx + 1))}")

		# ---- 3. force-push, on any branch ---------------------------
		if [ "$sub" = "push" ]; then
			for a in ${subargs+"${subargs[@]}"}; do
				case "$a" in
				-f | --force | --force-with-lease | --force-with-lease=* | --force-if-includes | +*)
					deny "Refusing to force-push ('$a'). Force-pushing rewrites published history. If this is genuinely required, the user must run it manually."
					;;
				-[a-zA-Z]*f*)
					deny "Refusing to force-push ('$a' contains -f). Force-pushing rewrites published history. If this is genuinely required, the user must run it manually."
					;;
				esac
			done
		fi

		if [ "${CLAUDE_ALLOW_PROTECTED_BRANCH:-0}" = "1" ]; then
			continue
		fi

		# ---- 2. push to a protected branch by refspec ----------------
		if [ "$sub" = "push" ]; then
			for a in ${subargs+"${subargs[@]}"}; do
				case "$a" in
				-*) continue ;;
				esac
				target=${a##*:}  # HEAD:main -> main
				target=${target##refs/heads/}
				if branch_is_protected "$target"; then
					deny "Refusing to push to protected branch '$target'. Push a feature branch and open a pull request instead."
				fi
			done
		fi

		# ---- 1. write operations while on a protected branch ---------
		case "$sub" in
		commit | merge | rebase | cherry-pick | revert | am | apply | push)
			;;
		reset)
			# Only --hard is destructive enough to block.
			hard=0
			for a in ${subargs+"${subargs[@]}"}; do
				[ "$a" = "--hard" ] && hard=1
			done
			[ "$hard" -eq 1 ] || continue
			;;
		*)
			continue
			;;
		esac

		branch=$(head_branch)
		if branch_is_protected "$branch"; then
			deny "Refusing 'git $sub' while on protected branch '$branch'. Create a working branch first:

  git switch -c <type>/<short-description>

then re-run this command. Use feat/, fix/, chore/, refactor/ or docs/ as the type. Set CLAUDE_ALLOW_PROTECTED_BRANCH=1 before launching claude to override."
		fi
		;;
	esac
done <<<"$split"

exit 0
