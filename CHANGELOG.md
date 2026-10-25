# Changelog

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
