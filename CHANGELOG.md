# Changelog

All notable changes to this project will be documented in this file.

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
