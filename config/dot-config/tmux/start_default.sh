#!/usr/bin/env bash
#
# Start a default tmux session if it does not exist.
# Otherwise ask the user if they want to attach to the existing session
# or create a new session.

SESSION="Development"
EXITS=$(tmux list-sessions | grep $SESSION)

if [ -z "$EXITS" ]; then
	tmux new-session -d -s $SESSION

	tmux rename-window -t $SESSION:1 "nvim"
	tmux send-keys -t "nvim" "cd ~/Dev" C-m "nvim" C-m

	tmux new-window -t $SESSION:2 -n "shell-1"

	tmux new-window -t $SESSION:3 -n "shell-2"

	tmux attach-session -t $SESSION:1
else
	read -p "Session '$SESSION' already exists. Do you want to attach to it? [y/N] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		tmux attach-session -t $SESSION:2
	else
		SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})

		files=$(ls $SCRIPT_DIR/start_*.sh | grep -v $(basename $0))
		show_files=$(echo $files | sed "s|$SCRIPT_DIR/start_||g; s|.sh||g")

		echo "Choose a session template or quit:"
		echo ""
		count=1
		for item in $show_files; do
			echo "$count) $item"
			count=$((count + 1))
		done
		echo "q) Quit"
		read -n 1 answer

		case $answer in
		[1-9])
			file=$(echo $files | cut -d " " -f $answer)
			source $file
			;;
		q)
			exit 0
			;;
		*)
			echo "Invalid option"
			exit 1
			;;
		esac
	fi
fi
