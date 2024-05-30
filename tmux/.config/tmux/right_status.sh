#!/usr/bin/env bash
# simple script to display the right status bar
#
# - date_time: display the current time and timezone
#

function date_time() {
	printf "%s " "$(date +'%H:%M %Z')"
}

function main() {
	date_time
}

main
