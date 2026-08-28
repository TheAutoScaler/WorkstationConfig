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

Open `firefox-profile/Firefox-Feeling-Lucky.mobileconfig`, then approve it in
System Settings under General > Device Management. Restart Firefox and confirm
the policy at `about:policies`; type `! search terms` to use it.

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

PromptTab provides local AI-powered shell completions. Install or refresh it
from the pinned submodule:

```bash
cd "$HOME/Config"
stow --restow dotfiles
git submodule update --init --recursive \
    submodules/PromptTab
PROMPTTAB_HOME="$HOME/.local/share/prompttab" \
PROMPTTAB_MANAGE_BASHRC=0 \
    submodules/PromptTab/install.sh
```

Its configuration and local `llama.cpp` service are managed by the dotfiles.

### Neovim additions

Run `:ConfigHealth` to inspect configuration dependencies and optional tools.
Use `:messages` to review any startup warnings from the current session.

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

The Ghostty configuration is a clone of the iTerm2 configuration.

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

### Automatic GitHub sync

The Stow-managed LaunchAgent commits and pushes this repository every five
minutes on the branch named in `~/.config-auto-sync`. It runs Gitleaks before
committing and logs to `~/Library/Logs/config-auto-sync.log`; remove the
configuration file to disable syncing.

```bash
brew install gitleaks
printf '%s\n' main > "$HOME/.config-auto-sync"
cd "$HOME/Config"
stow --restow dotfiles
git config core.hooksPath .githooks
launchctl bootstrap "gui/$UID" \
    "$HOME/Library/LaunchAgents/dev.workstation.config-auto-sync.plist"
```
