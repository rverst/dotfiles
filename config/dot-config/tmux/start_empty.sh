#!/usr/bin/env bash
#
# Start an empty tmux session and attach to it. Use a random session name.

SESSION="base"

tmux new-session -A -s $SESSION
