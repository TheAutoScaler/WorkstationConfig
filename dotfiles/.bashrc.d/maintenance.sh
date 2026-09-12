#!/usr/bin/env bash

workstation_maintenance_file() {
	local component=$1
	local cache_dir

	if [[ "${OSTYPE:-}" == darwin* ]]; then
		cache_dir="$HOME/Library/Caches"
	else
		cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}"
	fi
	printf '%s/workstation-maintenance-%s-last-run\n' "$cache_dir" "$component"
}

record_workstation_maintenance() {
	local maintenance_file

	maintenance_file=$(workstation_maintenance_file "$1")
	mkdir -p "${maintenance_file%/*}" 2>/dev/null \
		&& date +%s > "$maintenance_file" 2>/dev/null
}

workstation_maintenance_has_argument() {
	local expected=$1
	shift
	local argument

	for argument in "$@"; do
		[[ "$argument" == "$expected" ]] && return 0
	done
	return 1
}

if type -P brew &>/dev/null; then
	brew() {
		local status

		command brew "$@"
		status=$?
		if ((status == 0)) && workstation_maintenance_has_argument update "$@"; then
			record_workstation_maintenance brew-check
		fi
		if ((status == 0)) && workstation_maintenance_has_argument upgrade "$@"; then
			record_workstation_maintenance brew-upgrade
		fi
		return "$status"
	}
fi

if type -P softwareupdate &>/dev/null; then
	softwareupdate() {
		local status

		command softwareupdate "$@"
		status=$?
		if ((status == 0)) \
			&& { workstation_maintenance_has_argument --list "$@" \
				|| workstation_maintenance_has_argument -l "$@" \
				|| workstation_maintenance_has_argument --install "$@" \
				|| workstation_maintenance_has_argument -i "$@"; }; then
			record_workstation_maintenance softwareupdate
		fi
		return "$status"
	}
fi

workstation_maintenance() {
	local status=0

	if type -P brew &>/dev/null; then
		brew update && brew outdated || status=$?
	fi
	if type -P softwareupdate &>/dev/null; then
		softwareupdate --list || status=$?
	fi
	if ((status == 0)); then
		printf 'Maintenance checks completed.\n'
	fi

	return "$status"
}

workstation_maintenance_reminder() {
	local component
	local last_run
	local maintenance_file
	local now
	local overdue=()
	local remind_after=$((7 * 24 * 60 * 60))

	now=$(date +%s)
	for component in brew-check brew-upgrade softwareupdate; do
		if [[ "$component" == brew-* ]]; then
			type -P brew &>/dev/null || continue
		else
			type -P "$component" &>/dev/null || continue
		fi
		last_run=0
		maintenance_file=$(workstation_maintenance_file "$component")
		if [[ "$component" == brew-check && ! -r "$maintenance_file" ]]; then
			maintenance_file=$(workstation_maintenance_file brew)
		fi
		if [[ -r "$maintenance_file" ]]; then
			read -r last_run < "$maintenance_file"
			[[ "$last_run" =~ ^[0-9]+$ ]] || last_run=0
		fi
		if ((now - last_run >= remind_after)); then
			overdue+=("$component")
		fi
	done

	if ((${#overdue[@]})); then
		printf '\n🧰 Maintenance overdue:\n'
		for component in "${overdue[@]}"; do
			case "$component" in
			brew-check)
				printf '  brew update && brew outdated\n'
				;;
			brew-upgrade)
				printf '  brew upgrade\n'
				;;
			softwareupdate)
				printf '  softwareupdate --list\n'
				printf '  sudo softwareupdate --install --all\n'
				;;
			esac
		done
		printf '\n'
	fi
}

workstation_maintenance_reminder
unset -f workstation_maintenance_reminder
