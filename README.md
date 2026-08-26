# Workstation configuration

This repository contains my personal configuration for a new workstation setup.
It is not intended to be used by anyone else, but feel free to use it if you
find it useful.

I am a former Linux desktop that switched to MacOS some years ago. I run a
GNU/Linux-like shell environment on MacOS.

This repository also contains my dotfiles, which are also intended to work on
Linux.

Dotfiles are managed with [GNU Stow](https://www.gnu.org/software/stow/), which
symlinks them from this repository (cloned on my local machine) to the home
directory.

### Automatic GitHub sync

The Stow-managed `dev.workstation.config-auto-sync` LaunchAgent checks this
repository every five minutes. It commits all local changes on the checked-out
branch and pushes that branch to `origin`. Before staging and again before
committing, it runs Gitleaks; a missing scanner or any finding stops the sync.
The same check is installed as a Git pre-commit hook for manual commits.

Install the dependency and activate the automation:

```bash
brew install gitleaks
cd "$HOME/Config"
stow --restow dotfiles
git config core.hooksPath .githooks
launchctl bootout "gui/$UID/dev.workstation.config-auto-sync" 2>/dev/null || true
launchctl bootstrap "gui/$UID" \
    "$HOME/Library/LaunchAgents/dev.workstation.config-auto-sync.plist"
launchctl kickstart -k "gui/$UID/dev.workstation.config-auto-sync"
```

The agent writes diagnostics to `~/Library/Logs/config-auto-sync.log`. Gitleaks
is a strong safeguard, not a guarantee: keep credentials outside this repository
and rotate any credential that is ever committed.

## Installation instructions

Install Homebrew:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Manually activate Homebrew in the shell:

```
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Fetch `brew_formulae_macos` and `brew_casks`:

```
curl -O \
    https://raw.githubusercontent.com/JamesLochhead/workstation_setup/main/brew_formulae_macos
curl -O \
    https://raw.githubusercontent.com/JamesLochhead/workstation_setup/main/brew_casks
```

Install software using Homebrew:

```
xargs brew install < brew_formulae_macos
xargs brew install < brew_casks
```

The shell activates Homebrew only after checking the ownership and permissions
of `/opt`, `/opt/homebrew`, its `bin` directory, and the `brew` executable.
These checks retain the protection against a hostile world-writable install
path without claiming `~/.homebrew`, which Homebrew uses for user configuration
such as third-party tap trust decisions.


### Firefox

Complete Firefox because dotfiles because we will need to overrite the files
created.

Make a profile directory:

```
mkdir "$HOME/.firefox_profile"
```

Make a new profile, set is as default, and point it to the directory above:

```
firefox -p # Linux
/Applications/Firefox.app/Contents/MacOS/firefox -p # MacOS via brew
```

HINT: `Command+Shift+.` to show hidden files in the file picker on MacOS.

### Dotfiles

Clone this repository, including its pinned Neovim plugin submodules:

```
git clone --recurse-submodules \
    git@github.com:JamesLochhead/workstation_setup.git "$HOME/Config"
```

For an existing clone, initialise or restore the pinned plugin revisions with:

```
git submodule update --init --recursive
```

`cd` into the repository and install dotfiles:

```
stow --adopt dotfiles
```

### Bash

Make Bash the default shell:

```
# chsh -s "/opt/homebrew/bin/bash" "james"
```

#### PromptTab

PromptTab is pinned as a Git submodule and installed into its isolated runtime
directory at `~/.local/share/prompttab`. Shell startup remains version controlled
through `dotfiles/.bashrc.d/prompttab.sh`, so its installer is told not to edit
`~/.bashrc` directly.

Install or refresh it with:

```bash
cd "$HOME/Config"
stow --restow dotfiles
git submodule update --init --recursive \
    submodules/PromptTab
PROMPTTAB_HOME="$HOME/.local/share/prompttab" \
PROMPTTAB_MANAGE_BASHRC=0 \
    submodules/PromptTab/install.sh
```

The `dotfiles` Stow package owns `prompttab.toml`, including automatic backend
selection, the local model display name, URL, and generation limits. PromptTab's
installer owns the remaining runtime files and preserves the existing configuration
symlink. The file contains no credentials or authentication material.

The tracked fragment loads PromptTab conditionally, so a machine without it
installed still starts Bash normally. Reload the configuration after installation:

```bash
source "$HOME/.bashrc"
```

PromptTab's local backend uses Homebrew's `llama.cpp` and a resident
`llama-server`. The selected model is Qwen2.5-Coder-1.5B Base Q5_K_M. llama.cpp
downloads and caches that model automatically from Hugging Face when first started:

```bash
brew install llama.cpp
llama-server \
    -hf MaziyarPanahi/Qwen2.5-Coder-1.5B-GGUF:Q5_K_M \
    --host 127.0.0.1 --port 8012 \
    --n-gpu-layers 99 --ctx-size 2048 --parallel 1 --cache-reuse 256 \
    --cors-origins http://127.0.0.1:8012 --no-webui
```

The server is managed at login by the Stow-tracked user LaunchAgent
`~/Library/LaunchAgents/dev.prompttab.llama-server.plist`. It binds only to
loopback, disables the llama.cpp web UI, keeps one model resident for low latency,
and restarts automatically if it exits. Its Stow-managed launcher derives the log
path from `$HOME`, so the setup does not assume a macOS account name. Install or
refresh the configuration and agent with:

```bash
cd "$HOME/Config"
stow --restow dotfiles
launchctl bootout "gui/$UID/dev.prompttab.llama-server" 2>/dev/null || true
launchctl bootstrap "gui/$UID" \
    "$HOME/Library/LaunchAgents/dev.prompttab.llama-server.plist"
launchctl kickstart -k "gui/$UID/dev.prompttab.llama-server"
```

The first start may take longer while the model downloads. Check readiness and
logs with:

```bash
curl -fsS http://127.0.0.1:8012/health
tail -f "$HOME/Library/Logs/prompttab-llama.log"
```

### Neovim additions

The Neovim setup is intended to be portable to a newly provisioned machine
without making the editor fragile. Neovim should always remain usable for core
editing, even before every plugin and external tool has been installed. Once
the machine is fully provisioned, the same configuration should be quiet,
reproducible, and require no machine-local setup that has been forgotten or
left outside this repository.

The design therefore aims to:

- keep trusted plugin revisions explicit and reproducible;
- surface missing assumptions without turning them into startup failures;
- show one concise warning instead of flooding the screen;
- provide an explicit health report when details are needed;
- preserve user content when formatters fail; and
- track human-editable source while regenerating derived files locally.

Neovim plugins are pinned as Git submodules and linked into Neovim's native
package directory by Stow. Update them deliberately by checking out a reviewed
revision inside the submodule and committing the resulting submodule pointer.

The configuration is designed to remain usable while a new machine is only
partially provisioned. Optional plugins, language servers, formatters, their
secondary runtimes, clipboard support, the minimum Neovim version, and an
installed Nerd Font are checked during startup. Missing assumptions produce
one non-fatal warning; use `:ConfigHealth` or `:messages` for the full list.
Option-as-Meta remains a manual check because Neovim cannot inspect terminal
keyboard translation before a key is pressed.

Formatting runs against the in-memory buffer before saving. Formatter commands
receive content through standard input and the buffer is changed only after a
successful result, preventing failed tools from damaging content or leaving
the editor out of sync with the file on disk.

The personal spelling word list is tracked as readable source. Neovim rebuilds
its generated `.spl` file on startup only when the compiled file is absent or
older than the source, so generated machine data does not need to be committed.

### TextEdit

- Set to plain text and turn off spell check.

- Make clicking TextEdit icon in dock open a new document by default:

```
defaults write com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
```

## Restore iTerm2 settings

- Settings > General > Settings > Load preferences from a custom folder or URL

- Point at the location where this was closed to (perhaps `~/Config`).

- Don't symlink the preferences file, as iTerm2 doesn't support this and
  changes will be lost.

## Ghostty

Ghostty reads its version-controlled configuration from
`~/.config/ghostty/config`, which GNU Stow links to
`~/Config/dotfiles/.config/ghostty/config` with the rest of the dotfiles.

The configuration reproduces the former iTerm2 profile's Hack Nerd Font Mono
at 14 pt, 110-column by 35-row initial window size, Solarized Light theme, and
1,000-line scrollback limit.

Left Option acts as terminal Meta so shell and editor shortcuts continue to
work, while Right Option retains normal macOS character composition. The
explicit Option-3 mapping preserves access to `#` on a UK keyboard despite
using Left Option as Meta. Shift-Enter is intentionally left at Ghostty's
default rather than carrying over iTerm2's old explicit newline mapping.

Reload the configuration in a running Ghostty window with `Command-Shift-,`.

### Open Markdown and text files in Neovim from Finder

Finder requires an application bundle for file associations, so
`NeovimFinder/install.sh` builds a small native `Neovim.app` wrapper. The app
opens selected Markdown, plain-text, source-code, and configuration files in
Homebrew Neovim inside a new Ghostty window and safely preserves paths
containing spaces or shell metacharacters.

Install or refresh the wrapper and its Finder associations with:

```sh
cd "$HOME/Config/NeovimFinder"
./install.sh
```

The default installation is `/Applications/Neovim.app`. See
`NeovimFinder/README.md` for prerequisites, installation overrides, and
removal instructions.
