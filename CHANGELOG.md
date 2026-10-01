# Changelog

All notable changes to this project will be documented in this file.

## [1.1.21] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.1.20] - 2026-09-30

### Fixed
- The root search gave every candidate move a fresh (-infinity, +infinity)
  window, discarding every cutoff between siblings — most of what alpha-beta
  is for. It now carries the running best score into the window, widened by
  one either way so a move scoring *exactly* the current best still returns
  its true value and the existing tie collection (which picks randomly among
  equal moves, for variety) keeps working.
- The AI plays identically — verified move for move on 40 random positions at
  both depth 3 and depth 4 — in a quarter of the time. On "hard" that takes
  the worst single move from 4.2s to about 1s on a desktop.

## [1.1.15] - 2026-07-31

### Fixed
- `board_widget.lua` referenced Blitbuffer color constants that don't
  exist (COLOR_GRAY_C), which evaluated to `nil` and crashed the
  color-comparison in `paintTo()` as soon as the corresponding
  highlight was drawn. Now uses the correct constant name(s)
  (COLOR_LIGHT_GRAY).

## [1.1.14] - 2026-07-29

### Changed
- Repository and plugin id renamed from `echecs` to `chess`. Existing
  installs are not migrated automatically — Plugin Manager will install
  this as a new plugin, and per-device settings/stats saved under the old
  `echecs` name are left in place but no longer read.

## [1.1.9] - 2026-07-29

### Added
- Chess clock with configurable per-side base time and increment, live
  time display, and time-forfeit handling.
- PGN import/export — save a game to a `.pgn` file or load one back in,
  via a folder/file picker.
- Optional Stockfish/UCI engine as an alternative to the built-in AI,
  used only when a compatible binary is present; falls back safely to
  the built-in engine otherwise.
- Redo — takebacks made with Undo can now be replayed forward again.

### Fixed
- Draw detection only checked the fifty-move rule, so games with
  insufficient material (e.g. king vs. king) or a threefold-repeated
  position never ended in a draw and could continue indefinitely.
  Both conditions are now detected and correctly end the game.
