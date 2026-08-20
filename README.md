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

### WindowTools

WindowTools provides “always on top” and “minimize all” controls in the macOS
menu bar.
Build the standalone app, then use `ditto` to copy the complete app bundle into
`/Applications` while preserving its directory structure and macOS metadata:

```
cd "$HOME/Config/WindowTools"
./build-app.sh
ditto build/WindowTools.app /Applications/WindowTools.app
open /Applications/WindowTools.app
```

The build script applies an ad-hoc signature with `codesign --sign -`. This
makes the app bundle internally consistent for local use, but it is not signed
with an Apple Developer ID and is not notarized. macOS may therefore ask you to
confirm the first launch. Grant Accessibility permission only after copying the
app to `/Applications`, because that permission is associated with the app's
code identity and location. Rebuilding and replacing the app changes its code
signature and may require Accessibility permission to be granted again. A
stable Developer ID signature would avoid most of that permission churn.

Grant Accessibility and Screen Recording permission to WindowTools under
**System Settings > Privacy & Security**. Left-click its menu-bar pin to mirror
the focused window in an always-on-top panel; right-click to select or unpin
windows and quit.

The adjacent minimize button minimizes all visible windows. The global
`Control-Option-Command-M` shortcut performs the same action without using the
menu bar.

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
