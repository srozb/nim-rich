## Port of `rich.palette` (rich/palette.py).
##
## `Palette` (palette.py:11-72): a palette of RGB colors with index lookup,
## nearest-match search, and a `__rich__` table rendering. Used by
## `terminal_theme` (terminal_theme.py:4, `from .palette import Palette`) and
## the 8-bit/standard palette machinery.
##
## Import graph (rich/palette.py:1-5): runtime imports are `from math import
## sqrt` (palette.py:1), `from functools import lru_cache` (palette.py:2),
## `from typing import Sequence, Tuple, TYPE_CHECKING` (palette.py:3),
## `from .color_triplet import ColorTriplet` (palette.py:5); `from rich.table
## import Table` @ palette.py:8 is `TYPE_CHECKING`-only (and the `__rich__`
## body lazy-imports `Color`/`Style`/`Text`/`Table`, palette.py:21-24).
##
## wiring (this file):
##   `import color_triplet` — `ColorTriplet` (the `tuple[red, green, blue]`,
##                       palette.py:5; the `_colors` element type and the
##                       `__getitem__`/`match` value type).
##   `import richbase`     — `RenderableBase` — the return handle for
##                       `richCast` (the `__rich__` returns a `Table`,
##                       palette.py:20-46; a `Table` is a `RenderableBase`
##                       subtype, so the stub returns the base and body
##                       returns the concrete `Table` — non-narrowing). This
##                       keeps `palette`'s footprint to `color_triplet` +
##                       `richbase` (both already in the build transitively);
##                       `table`/`color`/`style`/`text` are `__rich__`-body-only
##                       (lazy, palette.py:21-24) → not imported .
## `sqrt`/`lru_cache` (palette.py:1-2) are `match`-body-only → not imported in
## port.
##
## `Palette` (palette.py:11, `class Palette`, no base → a `RichCast` via
## `__rich__`) is `ref object of RootObj` (Python `Palette` has reference
## semantics — `self._colors` is stored once; `match` mutates no state — so a
## Nim `ref` is the faithful mirror; `RootObj` because it is NOT a
## `ConsoleRenderable` — it renders via `__rich__`/`RichCast`, not
## `__rich_console__`). `_colors` (palette.py:14, the `__init__` store) →
## `colors*` (`_` dropped, public, like `style.nim`'s `_color`→`color*`);
## `Sequence[Tuple[int,int,int]]` → `openArray[ColorTriplet]` (param) /
## `seq[ColorTriplet]` (field). `__getitem__`→`` `[]` ``, `match`→`match`
## (`@lru_cache(maxsize=1024)` is a Phase-1 caching detail), `__rich__`→
## `richCast`. Bodies mirror the Python source (`discard`).

import color_triplet   # ColorTriplet — the _colors element / __getitem__ / match value type.
import richbase        # RenderableBase — the richCast return handle (Table is a subtype).
import std/math        # sqrt — the low-red-mean weighted RGB distance (palette.py:33-46).
import std/strutils    # repeat — the 16-space swatch (palette.py:44).
# The `__rich__` body lazily imports Table/Color/Style/Text (palette.py:21-24);
# wired here so `richCast` can build the palette Table.
import table           # Table (initTable, addRow) — palette.py:24.
import color           # Color (Color.fromRgb) — palette.py:21.
import style           # Style (initStyle) — palette.py:22.
import text            # Text (initText) — palette.py:23.

type
  Palette* = ref object of RootObj
    ## rich palette.py:11-72 — `class Palette`: "A palette of available colors."
    ## `ref object of RootObj` (reference semantics; NOT a `ConsoleRenderable`
    ## — renders via `__rich__`/`RichCast`). Field mirrors the `__init__` store
    ## (palette.py:14).
    colors*: seq[ColorTriplet]  ## rich palette.py:14-14 — `self._colors = colors` (`Sequence[Tuple[int,int,int]]`; `_` dropped → `colors*`, the `seq[ColorTriplet]` storage).

proc initPalette*(colors: openArray[ColorTriplet]): Palette =
  ## rich palette.py:13-14 — `Palette.__init__(self, colors: Sequence[Tuple[
  ## int,int,int]]) -> None`: `self._colors = colors`. `Sequence[Tuple[int,
  ## int,int]]` → `openArray[ColorTriplet]` (the param; stored as
  ## `seq[ColorTriplet]`). Faithful: store the colours.
  result = Palette(colors: @colors)

proc `[]`*(self: Palette, number: int): ColorTriplet =
  ## rich palette.py:16-17 — `Palette.__getitem__(self, number: int)
  ## -> ColorTriplet`: `return ColorTriplet(*self._colors[number])`
  ## (palette.py:17). `__getitem__`→`` `[]` `` (the Nim indexer). Faithful:
  ## `ColorTriplet(*self._colors[number])`.
  result = self.colors[number]

proc match*(self: Palette, color: ColorTriplet): int =
  ## rich palette.py:25-46 — `Palette.match(self, color: Tuple[int,int,int])
  ## -> int` (`@lru_cache(maxsize=1024)`, palette.py:24): find the index of the
  ## closest color by the low-red-mean weighted RGB distance (palette.py:33-46).
  ## `Tuple[int,int,int]` → `ColorTriplet`; `@lru_cache` is a Phase-1 caching
  ## detail. Faithful port of the low-red-mean weighted RGB distance
  ## (palette.py:33-46).
  if self.colors.len == 0:
    return 0
  let red1 = color.red
  let green1 = color.green
  let blue1 = color.blue
  var bestIdx = 0
  var bestDist = Inf
  for index in 0 ..< self.colors.len:
    let c2 = self.colors[index]
    let red2 = c2.red
    let green2 = c2.green
    let blue2 = c2.blue
    let redMean = (red1 + red2) div 2
    let red = red1 - red2
    let green = green1 - green2
    let blue = blue1 - blue2
    let dist = sqrt(float(((512 + redMean) * red * red) shr 8) +
                    float(4 * green * green) +
                    float(((767 - redMean) * blue * blue) shr 8))
    if dist < bestDist:
      bestDist = dist
      bestIdx = index
  result = bestIdx

proc richCast*(self: Palette): RenderableBase =
  ## rich palette.py:20-46 — `Palette.__rich__(self) -> "Table"`: build a
  ## `Table` of `index`/`RGB`/`Color` rows (palette.py:25-45) lazily importing
  ## `Color`/`Style`/`Text`/`Table` (palette.py:21-24). `richCast` (the
  ## `__rich__`→`RichCast` bridge) returns a `RenderableBase` (a `Table` is a
  ## `RenderableBase` subtype — non-narrowing stub; body returns the concrete
  ## `Table`, importing `table`/`color`/`style`/`text`). Faithful port of
  ## palette.py:20-46 (the palette `Table`).
  let tbl = initTable("index", "RGB", "Color", title = "Palette",
                      caption = $self.colors.len & " colors", highlight = true,
                      captionJustify = jmRight)
  for index, col in self.colors:
    let rgbText = "(" & $col.red & ", " & $col.green & ", " & $col.blue & ")"
    let swatch = initText(repeat(" ", 16),
                          style = initStyle(bgcolor = Color.fromRgb(
                              col.red.float, col.green.float, col.blue.float)))
    tbl.addRow($index, RenderableOpt(kind: roStr, strv: rgbText),
               RenderableOpt(kind: roRenderable, renderablev: swatch),
               style = default(StyleOpt), endSection = false)
  result = tbl
