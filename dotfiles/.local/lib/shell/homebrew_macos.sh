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

		# Homebrew's coreutils gnubin directory may put GNU stat ahead of the
		# macOS utility. Use the system binary because these format strings are
		# intentionally BSD stat syntax.
		owner=$(/usr/bin/stat -f '%Su' "$path") || return 1
		[[ "$owner" == root || "$owner" == "$USER" ]] || return 1

		mode=$(/usr/bin/stat -f '%OLp' "$path") || return 1
		((8#$mode & 0002)) && return 1
	done

	# A successful final arithmetic check has status 1 because the path is not
	# world-writable. Return success explicitly after every path has passed.
	return 0
}

homebrew_macos_activate() {
	if [[ "$OSTYPE" == darwin* ]] && homebrew_macos_is_trusted; then
		eval "$(/opt/homebrew/bin/brew shellenv)"
	fi
}
