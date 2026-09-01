#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
types_file="${IINA_TYPES_FILE:-$script_dir/iina-types.plist}"
iina_app="${IINA_APP_PATH:-/Applications/IINA.app}"
iina_bundle_id="com.colliderli.iina"

if [[ -n "${IINA_HOMEBREW_PREFIX:-}" ]]; then
    iina_brew_prefix="$IINA_HOMEBREW_PREFIX"
elif [[ "$(uname -m)" == "arm64" ]]; then
    iina_brew_prefix="/opt/homebrew"
else
    iina_brew_prefix="/usr/local"
fi

utiluti_bin="$iina_brew_prefix/bin/utiluti"
jq_bin="$iina_brew_prefix/bin/jq"
launch_services="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
iina_cli="$iina_app/Contents/MacOS/iina-cli"

for dependency in \
    /usr/bin/codesign \
    /usr/bin/plutil \
    /usr/bin/xattr \
    "$utiluti_bin" \
    "$jq_bin" \
    "$launch_services"; do
    if [[ ! -x "$dependency" ]]; then
        echo "Missing required executable: $dependency" >&2
        exit 1
    fi
done

if [[ ! -d "$iina_app" ]]; then
    echo "IINA is not installed at $iina_app" >&2
    exit 1
fi

/usr/bin/plutil -lint "$types_file" >/dev/null

metadata_changed=0
if /usr/bin/xattr -p com.apple.metadata:kMDItemAlternateNames \
    "$iina_cli" >/dev/null 2>&1; then
    /usr/bin/xattr -d com.apple.metadata:kMDItemAlternateNames "$iina_cli"
    metadata_changed=1
fi
/usr/bin/codesign --verify --deep --strict "$iina_app"
"$launch_services" -f "$iina_app"

registered_apps="$("$utiluti_bin" app for-id "$iina_bundle_id")"
if [[ -z "$registered_apps" ]]; then
    echo "Launch Services cannot find $iina_bundle_id" >&2
    exit 1
fi

association_data="$(
    /usr/bin/plutil -convert json -o - "$types_file" \
        | "$jq_bin" -r 'to_entries[] | [.key, .value] | @tsv'
)"
if [[ -z "$association_data" ]]; then
    echo "No IINA media associations are configured" >&2
    exit 1
fi

changed=0
while IFS=$'\t' read -r association expected_bundle_id; do
    if [[ "$expected_bundle_id" != "$iina_bundle_id" ]]; then
        echo "Unexpected bundle identifier for $association: $expected_bundle_id" >&2
        exit 1
    fi

    if [[ "$association" == extension:* ]]; then
        extension="${association#extension:}"
        type_args=(--extension "$extension")
        display_type=".$extension"
    elif [[ "$association" == *.* ]]; then
        type_args=("$association")
        display_type="$association"
    else
        echo "Invalid media type key: $association" >&2
        exit 1
    fi

    current_bundle_id="$(
        "$utiluti_bin" type get "${type_args[@]}" --bundle-id
    )"
    if [[ "$current_bundle_id" == "$expected_bundle_id" ]]; then
        continue
    fi

    echo "Setting IINA as the default for $display_type"
    "$utiluti_bin" type set "${type_args[@]}" "$expected_bundle_id"

    current_bundle_id="$(
        "$utiluti_bin" type get "${type_args[@]}" --bundle-id
    )"
    if [[ "$current_bundle_id" != "$expected_bundle_id" ]]; then
        echo "Failed to set IINA as the default for $display_type" >&2
        exit 1
    fi
    changed=$((changed + 1))
done <<< "$association_data"

echo "Changed associations: $changed"
echo "Repaired app metadata: $metadata_changed"
