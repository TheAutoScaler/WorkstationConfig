# Neovim Finder application

This directory builds a minimal native `Neovim.app` wrapper so Finder can open
Markdown, plain-text, source-code, and configuration files in Neovim inside
Ghostty. It intentionally does not claim PDFs, office documents, images,
archives, binary formats, HTML pages that Finder normally opens in a browser,
or Apple property lists retained by Xcode.

The wrapper passes file paths as process arguments rather than constructing a
shell command. Spaces and shell metacharacters in filenames are therefore
preserved without shell evaluation. The wrapper uses Ghostty's native
AppleScript API to create one window in the already-authorized Ghostty
application rather than launching a separate app instance. File paths cross
that boundary as base64-encoded JSON and are decoded by the installed helper.
When Ghostty is not already running, the wrapper instead uses Ghostty's native
one-command mode so no redundant initial shell window is created and the
isolated Ghostty instance exits automatically when Neovim closes. A scoped
watcher targets only that isolated process; Ghostty sessions that were already
running are never quit by the wrapper.
The wrapper resolves `PATH` from the configured Homebrew Bash login environment
before creating the terminal, then replaces its foreground helper directly
with Neovim. This keeps terminal job control correct while making the language
servers and formatters configured in `init.lua` available. The generated app
uses the official Neovim icon bundled with this installer.

## Install

Prerequisites are Ghostty at `/Applications/Ghostty.app`, Homebrew Neovim at
`/opt/homebrew/bin/nvim`, and Homebrew `duti`. All are included in this
repository's Homebrew package lists. The installer creates its own stable
`Neovim Finder Local Code Signing` identity automatically when necessary. A
stable identity allows macOS to remember local app-launch consent across
rebuilds.

### Why `duti` is installed

macOS has no built-in command-line interface for assigning a default
application to a list of filename extensions. The installer uses `duti` to
associate Markdown, plain-text, source-code, and configuration extensions with
the generated `Neovim.app`, and then queries those associations to verify that
each change succeeded. `duti` is used only during installation; it does not run
in the background and Neovim does not require it when opening files afterward.

Without `duti`, the application can still be built and selected manually from
Finder's **Open With** menu, but `install.sh` cannot automate or verify the
default file associations.

```sh
./install.sh
```

The installer builds and locally signs a transient `build/Neovim.app`, copies
it to `/Applications/Neovim.app`, removes the build artifact so Finder cannot
register a duplicate application, registers the installed copy with Launch
Services, and makes it
the default editor for a curated list of text and source-code extensions. The
installer verifies every association after registration. Re-running it safely
replaces the generated app.

To install somewhere else:

```sh
NEOVIM_FINDER_INSTALL_DIR="$HOME/Applications" ./install.sh
```

## Remove

```sh
./uninstall.sh
```

This removes the generated application. It does not remove Neovim, Ghostty,
their configuration, or any documents.

Files without an extension are normally classified by macOS as generic
`public.data`, even when their contents are text. The wrapper registers as an
alternate editor for that type so it appears under Finder's **Open With** menu,
but does not become the default for every unknown binary file.

## Test

```sh
./run-tests.sh
```

The test builds an isolated app and verifies signing, its property list, and
the exact argument boundary passed to Ghostty for filenames containing spaces
and shell metacharacters. It does not open a terminal window.
