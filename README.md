<p align="center"><img src="docs/icon.png" width="128" alt=""></p>

# DropMe

A small, private drop shelf for macOS, inspired by Dropover. No network, no telemetry, no account.

<p align="center"><img src="docs/fenster.png" width="240" alt="DropMe shelf holding three images"></p>

## What it does

- **Hold Shift while dragging** files to open a floating shelf under the pointer. If nothing is dropped on it, it goes away again.
- Drop files on it (from several places, also attachments from Mail), then drag them all out again later. If they get moved along the way, the shelf empties itself.
- **Action menu** (chevron at the top right): Open With, Show in Finder, Quick Look, Share (AirDrop, Mail, Messages, Notes, More), Add from Clipboard, Copy, Copy to, Move to, quick destinations, Clear Shelf.
- **Quick destinations**: folders with a name of your choice that sit directly in the menu and copy there. Managed via “Einstellungen …” in the action menu.
- **Pill** at the bottom: name or item count; a click lists the individual files (open, reveal, remove).
- Keyboard: Space for Quick Look, Esc or ⌘W to close, ⌘C to copy, ⌘V to paste, double-click to open.
- Menu bar: New Shelf, Close All, Launch at Login.
- `open -a DropMe <files>` puts files straight onto a new shelf.
- Liquid Glass on macOS 26 and later, subtle animations (turned off with “Reduce motion”), light and dark mode.

The user interface is in German for now.

## Privacy

DropMe contains no networking code. You can check that on the binary:

```sh
otool -L /Applications/DropMe.app/Contents/MacOS/DropMe        # no CFNetwork, no Network.framework
nm -u /Applications/DropMe.app/Contents/MacOS/DropMe | grep -i urlsession   # empty
```

To detect a drag, DropMe only looks at the types on the drag pasteboard, never at its contents.
Sharing goes through macOS services (AirDrop, Mail …); DropMe itself sends nothing.

## Installation

With Homebrew:

```sh
brew tap wiredframe/tap
brew trust --cask wiredframe/tap/dropme
brew install --cask wiredframe/tap/dropme
```

Or by hand: download `DropMe-<version>.zip` from [Releases](../../releases), unzip it and move `DropMe.app` to `/Applications`.

Requires a Mac with Apple Silicon and macOS 14 or later.

The app is signed with a Developer ID but not notarized yet, so macOS blocks the first launch (the Homebrew cask takes care of that). Either click “Open Anyway” under System Settings › Privacy & Security, or run once in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/DropMe.app
```

## Building

```sh
./build.sh            # builds build/DropMe.app (Apple Silicon, signed with a Developer ID if available, otherwise ad hoc)
./build.sh --install  # also copies it to ~/Applications and launches it
./build.sh --zip      # also creates build/DropMe-<version>.zip, notarized if a notarytool profile “notary” exists
```

Requirements: a Mac with Apple Silicon, Xcode or Swift 5.10+, macOS 14+.

## License

MIT
