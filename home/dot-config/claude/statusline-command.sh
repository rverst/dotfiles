#!/bin/sh
# Claude Code status line
# Layout: LEFT: model | dir | branch    RIGHT: ctx | 5h | 7d

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
context_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Compact, human-readable countdown until a Unix-epoch reset time:
#   >= 24h -> whole days (2d); >= 2h -> whole hours (3h); < 2h -> h:mm (1:23)
fmt_reset() {
  target="$1"
  now=$(date +%s)
  secs=$(( target - now ))
  [ "$secs" -lt 0 ] && secs=0
  if   [ "$secs" -ge 86400 ]; then printf '%dd' $(( secs / 86400 ))
  elif [ "$secs" -ge 7200  ]; then printf '%dh' $(( secs / 3600 ))
  else printf '%d:%02d' $(( secs / 3600 )) $(( (secs % 3600) / 60 ))
  fi
}

# --- LEFT SIDE ---

# Model segment
left=""
if [ -n "$model" ]; then
  left=$(printf "\033[35m%s\033[0m" "$model")
fi

# Dir segment
dir_label="${cwd:-~}"
if [ -n "$left" ]; then
  left=$(printf "%s \033[90m|\033[0m \033[34m%s\033[0m" "$left" "$dir_label")
else
  left=$(printf "\033[34m%s\033[0m" "$dir_label")
fi

# Branch segment (with ahead/behind/dirty indicators)
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null \
           || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    ahead=$(git -C "$cwd" --no-optional-locks rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
    behind=$(git -C "$cwd" --no-optional-locks rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
    dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    branch_label="$branch"
    [ "$ahead"  -gt 0 ] 2>/dev/null && branch_label="$branch_label ⇡"
    [ "$behind" -gt 0 ] 2>/dev/null && branch_label="$branch_label ⇣"
    [ "$dirty"  -gt 0 ] 2>/dev/null && branch_label="$branch_label *"
    left=$(printf "%s \033[90m|\033[0m \033[90m%s\033[0m" "$left" "$branch_label")
  fi
fi

# --- RIGHT SIDE ---

right=""

# Context window usage
if [ -n "$context_pct" ]; then
  ctx_int=$(printf "%.0f" "$context_pct")
  right=$(printf "\033[37mctx %s%%\033[0m" "$ctx_int")
fi

# 5-hour rolling limit
if [ -n "$five_hour_pct" ]; then
  five_int=$(printf "%.0f" "$five_hour_pct")
  segment=$(printf "\033[37m5h %s%%\033[0m" "$five_int")
  if [ -n "$five_hour_reset" ]; then
    segment=$(printf "%s \033[90m⟳%s\033[0m" "$segment" "$(fmt_reset "$five_hour_reset")")
  fi
  if [ -n "$right" ]; then
    right=$(printf "%s \033[90m|\033[0m %s" "$right" "$segment")
  else
    right="$segment"
  fi
fi

# 7-day rolling limit
if [ -n "$seven_day_pct" ]; then
  seven_int=$(printf "%.0f" "$seven_day_pct")
  segment=$(printf "\033[37m7d %s%%\033[0m" "$seven_int")
  if [ -n "$seven_day_reset" ]; then
    segment=$(printf "%s \033[90m⟳%s\033[0m" "$segment" "$(fmt_reset "$seven_day_reset")")
  fi
  if [ -n "$right" ]; then
    right=$(printf "%s \033[90m|\033[0m %s" "$right" "$segment")
  else
    right="$segment"
  fi
fi

# --- OUTPUT ---
# Right-align the right side by padding with spaces.
# Strip ANSI escape codes to get the visible (printable) length of a string.
strip_ansi() {
  printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g'
}

visible_len() {
  printf '%s' "$(strip_ansi "$1")" | wc -m | tr -d ' '
}

if [ -n "$right" ]; then
  # Use COLUMNS if positive, otherwise query the terminal, fallback to 220
  cols="$COLUMNS"
  [ "${cols:-0}" -le 0 ] 2>/dev/null && cols="$(tput cols 2>/dev/null)"
  [ "${cols:-0}" -le 0 ] 2>/dev/null && cols=220

  left_len=$(visible_len "$left")
  right_len=$(visible_len "$right")
  pad=$(( cols - left_len - right_len - 4 ))
  [ "$pad" -lt 1 ] && pad=1

  padding=$(printf '%*s' "$pad" '')
  printf "%s%s%s" "$left" "$padding" "$right"
else
  printf "%s" "$left"
fi

