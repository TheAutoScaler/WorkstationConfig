#!/usr/bin/env bash

set -euo pipefail

install_dir="${NEOVIM_FINDER_INSTALL_DIR:-/Applications}"
installed_app="$install_dir/Neovim.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -d "$installed_app" ]]; then
    "$launch_services" -u "$installed_app" || true
    rm -rf "$installed_app"
fi

echo "Removed $installed_app"
echo "macOS will choose another available editor for affected document types."
