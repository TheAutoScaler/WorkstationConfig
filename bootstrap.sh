#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$repo_dir"

case "$(uname -m)" in
    arm64) brew_bin=/opt/homebrew/bin/brew ;;
    *) brew_bin=/usr/local/bin/brew ;;
esac

if command -v ansible-playbook >/dev/null 2>&1; then
    ansible_playbook=$(command -v ansible-playbook)
    ansible_galaxy=$(command -v ansible-galaxy)
else
    if [ ! -x "$brew_bin" ]; then
        /bin/bash -c "$(curl -fsSL \
            https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    "$brew_bin" install ansible
    ansible_playbook=$(dirname "$brew_bin")/ansible-playbook
    ansible_galaxy=$(dirname "$brew_bin")/ansible-galaxy
fi

"$ansible_galaxy" collection install -r requirements.yml
"$ansible_playbook" playbook.yml --ask-become-pass "$@"
