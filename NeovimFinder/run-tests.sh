#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d /tmp/neovim-finder-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT

test_app="$test_dir/Neovim.app"
capture_path="$test_dir/arguments"
first_file="$test_dir/first file.md"
second_file="$test_dir/second; file.txt"

NEOVIM_FINDER_INSTALL_DIR="$test_dir" \
NEOVIM_FINDER_SKIP_REGISTRATION=1 \
NEOVIM_FINDER_SIGNING_IDENTITY=- \
"$script_dir/install.sh"
touch "$first_file" "$second_file"

NEOVIM_FINDER_OSASCRIPT_EXECUTABLE="$script_dir/Tests/fake-open.sh" \
NEOVIM_FINDER_FORCE_APPLESCRIPT=1 \
NEOVIM_FINDER_CAPTURE_PATH="$capture_path" \
"$test_app/Contents/MacOS/Neovim" --launch "$first_file" "$second_file"

for _ in {1..50}; do
    [[ -f "$capture_path" ]] && break
    sleep 0.02
done

if [[ ! -f "$capture_path" ]]; then
    echo "The fake open command was not invoked." >&2
    exit 1
fi

/usr/bin/python3 - "$capture_path" "$first_file" "$second_file" <<'PY'
import pathlib
import sys

import base64
import json

actual = pathlib.Path(sys.argv[1]).read_bytes().rstrip(b"\0").decode().split("\0")
if actual[0] != "-e" or actual[2] != "--":
    raise SystemExit(f"unexpected osascript arguments: {actual!r}")
if "tell application \"Ghostty\"" not in actual[1]:
    raise SystemExit("AppleScript does not target Ghostty")
if not actual[3].endswith("/Contents/MacOS/Neovim --ghostty-launch"):
    raise SystemExit(f"unexpected helper command: {actual[3]!r}")
prefix = "NEOVIM_FINDER_FILES="
if not actual[4].startswith(prefix):
    raise SystemExit(f"missing file payload: {actual[4]!r}")
files = json.loads(base64.b64decode(actual[4][len(prefix):]))
if files != [sys.argv[2], sys.argv[3]]:
    raise SystemExit(f"file mismatch: {files!r}")
PY

codesign --verify --deep --strict "$test_app"
plutil -lint "$test_app/Contents/Info.plist" >/dev/null
if [[ ! -f "$test_app/Contents/Resources/Neovim.icns" ]]; then
    echo "The Neovim application icon is missing." >&2
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$test_app/Contents/Info.plist")" != "Neovim.icns" ]]; then
    echo "CFBundleIconFile does not reference the packaged Neovim icon." >&2
    exit 1
fi
echo "Neovim Finder tests passed."
