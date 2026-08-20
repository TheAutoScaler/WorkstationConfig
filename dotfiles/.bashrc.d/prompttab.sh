#!/usr/bin/env bash

# PromptTab's installer owns the runtime; this repository owns shell startup.
export PROMPTTAB_HOME="$HOME/.local/share/prompttab"
[[ -r "$PROMPTTAB_HOME/bashrc.sh" ]] && source "$PROMPTTAB_HOME/bashrc.sh"
