# WindowTools

A small macOS menu-bar utility that toggles “always on top” for the currently
focused window.

## Use

- Left-click the pin in the menu bar to pin or unpin the focused window.
- Click the minimize button beside it to minimize all visible windows.
- Press Control-Option-Command-M to minimize all visible windows globally.
- Right-click it to unpin every tracked window or quit.
- Grant Accessibility permission when macOS asks.

WindowTools uses Accessibility to identify and track the focused window. Since
modern macOS does not allow one process to change another process's window
level, WindowTools uses ScreenCaptureKit to display a live floating mirror of
each pinned window. The mirror passes clicks through to the original window.

Grant both Accessibility and Screen Recording permission when macOS asks.

## Build

```sh
./build-app.sh
```

The app is written to `build/WindowTools.app`.

The window-mirroring implementation is adapted from the MIT-licensed
[PinWindow](https://github.com/justwy/PinWindow). See
`THIRD-PARTY-LICENSES/PinWindow.txt` for attribution and license terms.
