#!/usr/bin/env bash

open_file_fzf_neovim() {
	local missing_commands=()
	command -v nvim &>/dev/null || missing_commands+=(nvim)
	command -v fzf &>/dev/null || missing_commands+=(fzf)
	if ((${#missing_commands[@]})); then
		printf 'open_file_fzf_neovim requires: %s\n' "${missing_commands[*]}" >&2
		return 127
	fi

	local OLDIFS=$IFS
	IFS=
	local the_files=""
	readarray -d '' files < <(find -maxdepth 4 -not -path "*/.*" \
		-type f -print0 2>/dev/null)
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No files found"
		return
	else
		for a_file in "${files[@]}"; do
			the_files+="$a_file"
			the_files+=$'\n'
		done
		local chosen_file="$(echo $the_files |
			fzf -0 -1 --tiebreak=end --preview='less {}' \
				--layout=reverse \
				--bind=shift-up:preview-page-up,shift-down:preview-page-down)"
		if [[ -f "$chosen_file" ]]; then
			nvim "$chosen_file"
		else
			echo "No file chosen"
		fi
	fi
	unset files
	IFS=$OLDIFS
}

preview_note_fzf_less() {
	local missing_commands=()
	command -v fzf &>/dev/null || missing_commands+=(fzf)
	command -v less &>/dev/null || missing_commands+=(less)
	if ((${#missing_commands[@]})); then
		printf 'preview_note_fzf_less requires: %s\n' "${missing_commands[*]}" >&2
		return 127
	fi

	local OLDIFS=$IFS
	IFS=
	local the_files=""
	readarray -d '' files < <(find -L "$HOME/Notes" -maxdepth 4 -not \
		-path "*/.*" -name "*.md" -type f -print0 2>/dev/null)
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No files found"
		return
	else
		for a_file in "${files[@]}"; do
			the_files+="$a_file"
			the_files+=$'\n'
		done
		local chosen_file="$(echo $the_files |
			fzf -0 -1 --tiebreak=end --preview='less {}' \
				--layout=reverse --bind=shift-up:preview-page-up,shift-down:preview-page-down)"
		if [[ -f "$chosen_file" ]]; then
			less "$chosen_file"
		else
			echo "No file chosen"
		fi
	fi
	unset files
	IFS=$OLDIFS
}

open_fzf_macos() {
	local missing_commands=()
	command -v fzf &>/dev/null || missing_commands+=(fzf)
	command -v open &>/dev/null || missing_commands+=(open)
	if ((${#missing_commands[@]})); then
		printf 'open_fzf_macos requires: %s\n' "${missing_commands[*]}" >&2
		return 127
	fi

	local OLDIFS=$IFS
	IFS=
	local the_files=""
	readarray -d '' files < <(find -maxdepth 4 -not \
		-path "*/.*" -print0 2>/dev/null)
	if [[ ${#files[@]} -eq 0 ]]; then
		echo "No files found"
		return
	else
		for a_file in "${files[@]}"; do
			the_files+="$a_file"
			the_files+=$'\n'
		done
		local chosen_file="$(echo $the_files |
			fzf -0 -1 --tiebreak=end --preview='less {}' \
				--layout=reverse \
				--bind=shift-up:preview-page-up,shift-down:preview-page-down)"
		if [[ -e "$chosen_file" ]]; then
			open "$chosen_file"
		else
			echo "No file chosen"
		fi
	fi
	unset files
	IFS=$OLDIFS
}

# Keep these helpers local to the interactive shell. They are called by aliases
# defined in the same shell and do not need to be inherited by child processes.
# Bash exports functions as multiline BASH_FUNC_*%% environment variables;
# process launchers that capture those variables incorrectly can truncate them,
# causing every child Bash process to report a malformed function definition.
