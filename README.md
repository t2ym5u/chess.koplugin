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
- **Undo** — take back the last move
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
| New game | Tap **New** |
| Show rules | Tap **Rules** |

## License

GPL-3.0 — see [LICENSE](LICENSE).
