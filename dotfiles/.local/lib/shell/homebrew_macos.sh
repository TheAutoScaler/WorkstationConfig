#!/usr/bin/env bash

# Homebrew needs ~/.homebrew for user-owned configuration such as third-party
# tap trust decisions. Validate the installation itself instead of occupying
# that path with a marker file.
homebrew_macos_is_trusted() {
	local path owner mode
	local trusted_paths=(
		/opt
		/opt/homebrew
		/opt/homebrew/bin
		/opt/homebrew/bin/brew
	)

	for path in "${trusted_paths[@]}"; do
		[[ -e "$path" ]] || return 1

		owner=$(stat -f '%Su' "$path") || return 1
		[[ "$owner" == root || "$owner" == "$USER" ]] || return 1

		mode=$(stat -f '%OLp' "$path") || return 1
		((8#$mode & 0002)) && return 1
	done
}

homebrew_macos_activate() {
	if [[ "$OSTYPE" == darwin* ]] && homebrew_macos_is_trusted; then
		eval "$(/opt/homebrew/bin/brew shellenv)"
	fi
}
