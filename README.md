# echecs.koplugin

A Chess plugin for [KOReader](https://github.com/koreader/koreader).

## Screenshot

*(Screenshot to be added.)*

## Rules

Standard chess rules. Move pieces to put the opponent's king in checkmate. Special moves include castling, en passant, and pawn promotion.

| Piece | Movement |
|-------|----------|
| King | 1 square any direction |
| Queen | Any distance, any direction |
| Rook | Any distance, horizontal/vertical |
| Bishop | Any distance, diagonal |
| Knight | L-shape (2+1 squares) |
| Pawn | Forward 1 (or 2 on first move); captures diagonally |

## Features

- **Two-player local mode**
- **Move highlight** — shows legal moves for selected piece
- **Check indicator** — alerts when a king is in check
- **Undo / Redo** — take back the last move, or replay it forward again
- **Chess clock** — optional per-side time controls with increment
- **PGN import/export** — save a game to file or load one back in
- **Optional Stockfish/UCI engine** — use an external engine instead of the built-in AI, when available
- **Auto-save** — game state saved and restored on next launch

## Installation

1. Download `echecs.koplugin.zip` from the [latest release](../../releases/latest).
2. Extract into the `plugins/` folder of your KOReader data directory.
3. Restart KOReader.
4. Open the menu → **Tools** → **Chess**.

## Controls

| Action | How |
|--------|-----|
| Select a piece | Tap it |
| Move to a square | Tap the destination |
| Undo last move | Tap **Undo** |
| Redo last undone move | Tap **Redo** |
| New game | Tap **New** |
| Show rules | Tap **Rules** |
| Configure clock | Tap **Pendule** |
| Export/import PGN | Tap **Exporter PGN** / **Importer PGN** |

## Known limitations

The optional Stockfish/UCI engine is not bundled with this plugin. It is
only available if you supply your own compatible UCI engine binary at
`bin/stockfish` inside the plugin folder. When no such binary is present
(the default), the **Moteur** menu entry is hidden entirely and the game
uses only the built-in engine — nothing needs to be configured either way.

## License

GPL-3.0 — see [LICENSE](LICENSE).
