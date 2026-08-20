#!/usr/bin/env bash

set -euo pipefail

: "${NEOVIM_FINDER_CAPTURE_PATH:?capture path is required}"
printf '%s\0' "$@" > "$NEOVIM_FINDER_CAPTURE_PATH"
