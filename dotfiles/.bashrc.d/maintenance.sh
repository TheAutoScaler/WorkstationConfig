#!/usr/bin/env bash

weekly_maintenance_reminder() {
	local cache_dir
	local nag_file
	local nag_after=$((7 * 24 * 60 * 60))
	local last_nag=0
	local now

	if [[ "${OSTYPE:-}" == darwin* ]]; then
		cache_dir="$HOME/Library/Caches"
	else
		cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
	fi

	nag_file="$cache_dir/workstation-maintenance-nag"
	if [[ -r "$nag_file" ]]; then
		read -r last_nag < "$nag_file"
		[[ "$last_nag" =~ ^[0-9]+$ ]] || last_nag=0
	fi

	now=$(date +%s)
	if ((now - last_nag < nag_after)); then
		return
	fi

	if command -v brew &>/dev/null; then
		printf '\n🍺 Maintenance due: run brew update && brew outdated\n'
	fi
	if [[ "${OSTYPE:-}" == darwin* ]]; then
		printf '🍎 Also check: softwareupdate --list\n'
	fi
	printf '\n'

	mkdir -p "$cache_dir" && printf '%s\n' "$now" > "$nag_file"
}

weekly_maintenance_reminder
unset -f weekly_maintenance_reminder
