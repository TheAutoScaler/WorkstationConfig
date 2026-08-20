#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$script_dir/build"
module_cache_dir="$build_dir/module-cache"
app_name="Neovim.app"
built_app="$build_dir/$app_name"
install_dir="${NEOVIM_FINDER_INSTALL_DIR:-/Applications}"
installed_app="$install_dir/$app_name"
legacy_app="$HOME/Applications/$app_name"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
bundle_identifier="me.lochhead.NeovimFinder"
signing_identity="${NEOVIM_FINDER_SIGNING_IDENTITY:-Neovim Finder Local Code Signing}"
extensions=(
    md markdown mdown mkd mkdn txt text
    adoc bash c cc conf cpp css fish go h hcl hh hpp ini java js json
    jsx kt kts log lua php py rb rs rst scss sh sql swift tf tfvars toml
    ts tsx vim xml yaml yml zsh
)

for dependency in /usr/bin/swiftc /usr/bin/codesign /usr/bin/ditto /opt/homebrew/bin/nvim /opt/homebrew/bin/duti; do
    if [[ ! -x "$dependency" ]]; then
        echo "Missing required executable: $dependency" >&2
        exit 1
    fi
done

if [[ ! -d /Applications/Ghostty.app ]]; then
    echo "Ghostty is not installed at /Applications/Ghostty.app" >&2
    exit 1
fi

if [[ "$signing_identity" != "-" ]] \
    && ! security find-identity -v -p codesigning 2>/dev/null \
        | grep -F "\"$signing_identity\"" >/dev/null; then
    "$script_dir/setup-code-signing.sh"
fi

rm -rf "$built_app"
rm -rf "$module_cache_dir"
mkdir -p "$built_app/Contents/MacOS" "$built_app/Contents/Resources" "$module_cache_dir"
cp "$script_dir/Info.plist" "$built_app/Contents/Info.plist"
cp "$script_dir/Assets/Neovim.icns" "$built_app/Contents/Resources/Neovim.icns"

CLANG_MODULE_CACHE_PATH="$module_cache_dir" \
SWIFT_MODULECACHE_PATH="$module_cache_dir" \
/usr/bin/swiftc \
    -O \
    -framework AppKit \
    -framework CoreServices \
    "$script_dir/NeovimApp.swift" \
    -o "$built_app/Contents/MacOS/Neovim"

rm -rf "$module_cache_dir"

/usr/bin/codesign --force --deep --sign "$signing_identity" "$built_app"
/usr/bin/plutil -lint "$built_app/Contents/Info.plist"

mkdir -p "$install_dir"
if [[ "${NEOVIM_FINDER_SKIP_REGISTRATION:-0}" != "1" \
    && "$legacy_app" != "$installed_app" && -d "$legacy_app" ]]; then
    "$launch_services" -u "$legacy_app" || true
    rm -rf "$legacy_app"
fi
rm -rf "$installed_app"
/usr/bin/ditto "$built_app" "$installed_app"
"$launch_services" -u "$built_app" 2>/dev/null || true
rm -rf "$built_app"

if [[ "${NEOVIM_FINDER_SKIP_REGISTRATION:-0}" != "1" ]]; then
    "$launch_services" -f "$installed_app"
    for content_type in net.daringfireball.markdown public.plain-text; do
        /opt/homebrew/bin/duti -s "$bundle_identifier" "$content_type" all
    done
    for extension in "${extensions[@]}"; do
        /opt/homebrew/bin/duti -s "$bundle_identifier" ".$extension" all
    done
    for extension in "${extensions[@]}"; do
        registered_handler="$(/opt/homebrew/bin/duti -x "$extension" | tail -n 1)"
        if [[ "$registered_handler" != "$bundle_identifier" ]]; then
            echo "Failed to associate .$extension: found $registered_handler" >&2
            exit 1
        fi
    done
fi

echo "Installed $installed_app"
if [[ "${NEOVIM_FINDER_SKIP_REGISTRATION:-0}" != "1" ]]; then
    echo "Registered Neovim for Markdown, plain text, source code, and configuration files."
fi
