#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir="$project_dir/build"
app_dir="$build_dir/WindowTools.app"
executable="$app_dir/Contents/MacOS/WindowTools"
new_executable="$executable.new"

trap 'status=$?; rm -f "$new_executable"; exit "$status"' EXIT

mkdir -p "$app_dir/Contents/MacOS"

swiftc \
	"$project_dir/Sources/WindowTools/main.swift" \
	-o "$new_executable" \
	-module-cache-path "/private/tmp/ai.vernir.windowtools-module-cache" \
	-framework AppKit \
	-framework ApplicationServices \
	-framework AVFoundation \
	-framework Carbon \
	-framework ScreenCaptureKit

mv "$new_executable" "$executable"

cp "$project_dir/WindowTools-Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"

echo "$app_dir"
