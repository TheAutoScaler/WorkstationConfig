#!/bin/sh
set -eu

# Match the user-local npm prefix used by the shell and Ansible.
export PATH="${npm_config_prefix:-$HOME/.local}/bin:$PATH"

if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
    printf '%s\n' 'Install npm_tools before running this script (see README.md).' >&2
    exit 1
fi

# Forward installer options, including --yes for unattended setup.
codebase-memory-mcp install "$@"
codebase-memory-mcp config set auto_index true
codebase-memory-mcp config set auto_watch true
codebase-memory-mcp config set watcher_enabled true
