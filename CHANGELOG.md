# Changelog

## 1.1.0 (unreleased)

- **Engines window** (Molt → Engines…, ⌘,): lists Filee's optional engines with status, version and size, and installs,
  updates or removes them with Filee's own installer (`filee engines`), with a live progress bar and cancel
- Engines Filee can't download on a Mac (FFmpeg, Ghostscript, Tesseract): the window copies the Homebrew command;
  **Check Again** picks up the new copy
- Format picker: **Install Engines…** next to the optional-engine toggle
- Installing or removing an engine refreshes the targets of the files in the list right away; no restart needed
- Filee updated to 2.3.0, the first release with `filee engines`

## 1.0.1

- Format picker: a category's columns always stay on the same row, so no format ends up under the wrong heading

## 1.0.0

First release.

- Native AppKit window for Filee's conversion engine: drop files or folders, pick a target, convert
- Filee's engine (CLI, rhwp, 7-Zip) embedded in the app; no separate Filee install needed
- Format picker in columns, grouped by category, with search; formats that need an optional engine are hidden
  until asked for
- Live per-file progress, elapsed and remaining time, a log of Filee's output, clean cancel
- Output next to the originals or into a chosen folder; quality for lossy image formats; overwrite and keep-dates
- Optional engines (LibreOffice, FFmpeg, Pandoc, Ghostscript, calibre) used automatically when installed
- "Convert with Molt" in Finder's right-click menu (macOS Services)
- Extract archives (RAR, ZIP, 7Z, TAR and more) to a folder, the way Finder does: a single top-level item is
  extracted directly, several go into a folder named after the archive; `__MACOSX` leftovers are removed
- English and Turkish interface
- Builds for Apple Silicon and Intel
