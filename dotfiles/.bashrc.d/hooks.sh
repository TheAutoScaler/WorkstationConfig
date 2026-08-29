#!/usr/bin/env bash

if command -v starship &>/dev/null; then
	if [[ -z "${STARSHIP_AWS_CACHE_DIR:-}" ]]; then
		STARSHIP_AWS_CACHE_DIR="$(
			mktemp -d "${TMPDIR:-/tmp}/starship-aws.XXXXXX"
		)"
		export STARSHIP_AWS_CACHE_DIR
		trap 'rm -rf "$STARSHIP_AWS_CACHE_DIR"' EXIT
	fi

	set_win_title() {
		local title

		if [[ "$PWD" == "$HOME" ]]; then
			title="~"
		else
			title="$(basename "$PWD")"
		fi

		printf '\033]0; %s \007' "$title"
	}

	starship_precmd_user_func="set_win_title"
	eval "$(starship init bash)"
fi

if command -v direnv &>/dev/null; then
	eval "$(direnv hook bash)"
fi

if command -v lesspipe &>/dev/null; then
	# make less more friendly for non-text input files, see lesspipe(1)
	eval "$(SHELL=/bin/sh lesspipe)"
fi

if command -v pyenv &>/dev/null; then
	eval "$(pyenv init - bash)"
fi
