## Nim port of `rich.box` (rich/box.py).
##
## `Box` defines the characters used to render boxes (box.py:10-182). A `Box` is
## built from an 8-line string of box-drawing characters (`__init__` splits it into
## ~30 single-character attributes, box.py:27-59); 19 named box constants
## (ASCII ... MARKDOWN, box.py:186-401) and two substitution dicts
## (LEGACY_WINDOWS_SUBSTITUTIONS / PLAIN_HEADED_SUBSTITUTIONS, box.py:405-421) are
## defined at module level. `rich.table`/`rich.panel` consume boxes.
##
## wiring: `import richbase` (for `ConsoleOptions`, the param of
## `substitute`, box.py:67); `import std/tables` (for the substitution dicts,
## `Table[Box, Box]`). `from ._loop import loop_last` (box.py:4) is body-only
## (used in `get_top`/`get_row`/`get_bottom`, box.py:107,138,178) -- not imported
## . `from .console import ConsoleOptions` (box.py:6) is TYPE_CHECKING-
## only; `ConsoleOptions` comes from `richbase`.
##
## `Box` is a `ref object` (Python `Box` is a reference class; the substitution
## dicts map `Box`->`Box` keyed by object identity, since `Box` defines no
## `__eq__`/`__hash__` -- a Nim `Table[Box, Box]` hashes `ref` keys by pointer,
## faithfully mirroring Python's id-based dict). The 19 constants are `let` refs
## constructed via object literals that persist the real box string (`boxStr`,
## the `_box` field) and the `ascii` flag -- the box-character DATA is persisted
## now (faithful to rich); the parsed single-char fields default to empty and are
## populated by `initBox`, which splits `boxStr` into them; the 19 constants route
## through `initBox` (e.g. `let ASCII* = initBox(...)`). Naming: `__init__`->`initBox`,
## `__repr__`->`repr`, `__str__`->`$`, `substitute`/`get_plain_headed_box`->
## `substitute`/`getPlainHeadedBox`, `get_top`/`get_row`/`get_bottom`->
## `getTop`/`getRow`/`getBottom`; `_box`->`boxStr`; the snake_case char attrs are
## camelCased. `level: Literal['head','row','foot','mid']` (box.py:118-118) -> the
## `BoxLevel` string-valued enum (default `'row'` -> `blRow`); `widths:
## `Iterable[int]` -> `openArray[int]` (accepts `seq`/`array`/`openArray` —
## materialized iterables; closure iterators are a conscious body boundary,
## as for `segment.nim`, not claimed non-narrowing for iterators). Proc bodies
## are ported (initBox/repr/`$`/getTop/getRow/getBottom/substitute/
## getPlainHeadedBox implement box.py:27-182).

import std/[tables, hashes, strutils, unicode]
import richbase

proc boxRuneStr(line: string, i: int): string =
  ## [Nim-only helper] Return the `i`-th Unicode codepoint of `line` as a
  ## string — box chars may be multi-byte UTF-8, so byte indexing is unsafe.
  let r = line.toRunes
  if i < r.len: $r[i] else: ""

type
  BoxLevel* = enum
    ## rich box.py:118-118 -- the `level` param of `Box.get_row`
    ## (box.py:115-162): `Literal['head', 'row', 'foot', 'mid']`. String-valued enum
    ## so `$` yields the exact Python token for byte-identical output. Default
    ## `'row'` -> `blRow`. Faithful to all four `Literal` arms (head/row/foot/mid).
    blHead = "head"  ## the head  literal.
    blRow = "row"   ## the row  literal (default).
    blFoot = "foot" ## the foot literal.
    blMid = "mid"   ## the mid  literal.

  Box* = ref object
    ## rich box.py:10-182 -- `class Box`: characters to render boxes. A `ref object`
    ## (Python `Box` has reference semantics; substitution dicts key by identity).
    ## Fields mirror the `__init__` assignments (box.py:28-58); the parsed char
    ## fields default to empty  (populated by `initBox` in body).
    boxStr*: string  ## rich box.py:28-28 -- `self._box = box` (the raw 8-line box string; renamed `_box`->`boxStr`).
    ascii*: bool    ## rich box.py:29-29 -- `self.ascii = ascii` (True if this box uses ascii chars only).
    topLeft*: string  ## rich box.py:32-32 -- `self.top_left` (a single box-drawing char; camelCased).
    top*: string  ## rich box.py:32-32 -- `self.top` (a single box-drawing char; camelCased).
    topDivider*: string  ## rich box.py:32-32 -- `self.top_divider` (a single box-drawing char; camelCased).
    topRight*: string  ## rich box.py:32-32 -- `self.top_right` (a single box-drawing char; camelCased).
    headLeft*: string  ## rich box.py:34-34 -- `self.head_left` (a single box-drawing char; camelCased).
    headVertical*: string  ## rich box.py:34-34 -- `self.head_vertical` (a single box-drawing char; camelCased).
    headRight*: string  ## rich box.py:34-34 -- `self.head_right` (a single box-drawing char; camelCased).
    headRowLeft*: string  ## rich box.py:37-37 -- `self.head_row_left` (a single box-drawing char; camelCased).
    headRowHorizontal*: string  ## rich box.py:38-38 -- `self.head_row_horizontal` (a single box-drawing char; camelCased).
    headRowCross*: string  ## rich box.py:39-39 -- `self.head_row_cross` (a single box-drawing char; camelCased).
    headRowRight*: string  ## rich box.py:40-40 -- `self.head_row_right` (a single box-drawing char; camelCased).
    midLeft*: string  ## rich box.py:44-44 -- `self.mid_left` (a single box-drawing char; camelCased).
    midVertical*: string  ## rich box.py:44-44 -- `self.mid_vertical` (a single box-drawing char; camelCased).
    midRight*: string  ## rich box.py:44-44 -- `self.mid_right` (a single box-drawing char; camelCased).
    rowLeft*: string  ## rich box.py:46-46 -- `self.row_left` (a single box-drawing char; camelCased).
    rowHorizontal*: string  ## rich box.py:46-46 -- `self.row_horizontal` (a single box-drawing char; camelCased).
    rowCross*: string  ## rich box.py:46-46 -- `self.row_cross` (a single box-drawing char; camelCased).
    rowRight*: string  ## rich box.py:46-46 -- `self.row_right` (a single box-drawing char; camelCased).
    footRowLeft*: string  ## rich box.py:49-49 -- `self.foot_row_left` (a single box-drawing char; camelCased).
    footRowHorizontal*: string  ## rich box.py:50-50 -- `self.foot_row_horizontal` (a single box-drawing char; camelCased).
    footRowCross*: string  ## rich box.py:51-51 -- `self.foot_row_cross` (a single box-drawing char; camelCased).
    footRowRight*: string  ## rich box.py:52-52 -- `self.foot_row_right` (a single box-drawing char; camelCased).
    footLeft*: string  ## rich box.py:55-55 -- `self.foot_left` (a single box-drawing char; camelCased).
    footVertical*: string  ## rich box.py:55-55 -- `self.foot_vertical` (a single box-drawing char; camelCased).
    footRight*: string  ## rich box.py:55-55 -- `self.foot_right` (a single box-drawing char; camelCased).
    bottomLeft*: string  ## rich box.py:57-57 -- `self.bottom_left` (a single box-drawing char; camelCased).
    bottom*: string  ## rich box.py:57-57 -- `self.bottom` (a single box-drawing char; camelCased).
    bottomDivider*: string  ## rich box.py:57-57 -- `self.bottom_divider` (a single box-drawing char; camelCased).
    bottomRight*: string  ## rich box.py:57-57 -- `self.bottom_right` (a single box-drawing char; camelCased).

proc hash*(b: Box): Hash =
  ## Identity hash for `Box` -- rich `Box` defines no `__eq__`/`__hash__`, so the
  ## substitution dicts (`LEGACY_WINDOWS_SUBSTITUTIONS`/`PLAIN_HEADED_SUBSTITUTIONS`,
  ## box.py:405-421) are keyed by Python's default object identity (`id()`). Phase
  ## 1 mirrors this by hashing the `ref` pointer (`hash(cast[pointer](b))`), so a
  ## Nim `Table[Box, Box]` keys by `Box` identity, faithfully matching Python's
  ## id-based dict. Overloads `system.hash` on the `Box` receiver.
  result = hash(cast[pointer](b))

# ---------------------------------------------------------------------------
# Box methods -- box.py:27-182
# ---------------------------------------------------------------------------

proc initBox*(box: string, ascii: bool = false): Box =
  ## rich box.py:27-59 -- `Box.__init__(self, box: str, *, ascii: bool = False) ->
  ## None`: store the box string and `ascii` flag, then split the 8-line string
  ## into the single-char attributes (box.py:31-58). Keyword-only after `box`
  ## (Python `*`, box.py:27). (`discard` -> nil `Box`); parses
  ## `box` into the char fields. The 19 constants persist `boxStr` via object
  ## literals (not via this stub) so the box-character data is present now.
  result = Box()
  result.boxStr = box
  result.ascii = ascii
  let lines = box.split('\n')
  # top
  result.topLeft = boxRuneStr(lines[0], 0); result.top = boxRuneStr(lines[0], 1)
  result.topDivider = boxRuneStr(lines[0], 2); result.topRight = boxRuneStr(lines[0], 3)
  # head
  result.headLeft = boxRuneStr(lines[1], 0)
  result.headVertical = boxRuneStr(lines[1], 2); result.headRight = boxRuneStr(lines[1], 3)
  # head_row
  result.headRowLeft = boxRuneStr(lines[2], 0); result.headRowHorizontal = boxRuneStr(lines[2], 1)
  result.headRowCross = boxRuneStr(lines[2], 2); result.headRowRight = boxRuneStr(lines[2], 3)
  # mid
  result.midLeft = boxRuneStr(lines[3], 0)
  result.midVertical = boxRuneStr(lines[3], 2); result.midRight = boxRuneStr(lines[3], 3)
  # row
  result.rowLeft = boxRuneStr(lines[4], 0); result.rowHorizontal = boxRuneStr(lines[4], 1)
  result.rowCross = boxRuneStr(lines[4], 2); result.rowRight = boxRuneStr(lines[4], 3)
  # foot_row
  result.footRowLeft = boxRuneStr(lines[5], 0); result.footRowHorizontal = boxRuneStr(lines[5], 1)
  result.footRowCross = boxRuneStr(lines[5], 2); result.footRowRight = boxRuneStr(lines[5], 3)
  # foot
  result.footLeft = boxRuneStr(lines[6], 0)
  result.footVertical = boxRuneStr(lines[6], 2); result.footRight = boxRuneStr(lines[6], 3)
  # bottom
  result.bottomLeft = boxRuneStr(lines[7], 0); result.bottom = boxRuneStr(lines[7], 1)
  result.bottomDivider = boxRuneStr(lines[7], 2); result.bottomRight = boxRuneStr(lines[7], 3)

proc repr*(self: Box): string =
  ## rich box.py:61-62 -- `Box.__repr__(self) -> str`: returns the constant string
  ## `Box(...)`. Overloads `system.repr` on the `Box` receiver.
  result = "Box(...)"

proc `$`*(self: Box): string =
  ## rich box.py:64-65 -- `Box.__str__(self) -> str`: `return self._box` (the raw
  ## box string). Overloads `$` on the `Box` receiver.
  result = self.boxStr

proc getTop*(self: Box, widths: openArray[int]): string =
  ## rich box.py:95-113 -- `Box.get_top(self, widths: Iterable[int]) -> str`: build
  ## the top border string for the given column widths (box.py:105-112).
  ## `widths: Iterable[int]` -> `openArray[int]` (accepts `seq`/`array`/
  ## `openArray` — materialized iterables; closure iterators are a conscious
  ## body boundary, as for `segment.nim`). Body needs `loop_last`
  ## (box.py:107).
  var parts: seq[string] = @[]
  parts.add(self.topLeft)
  for i, width in widths:
    parts.add(self.top.repeat(width))
    if i != widths.high:
      parts.add(self.topDivider)
  parts.add(self.topRight)
  result = parts.join("")

proc getRow*(self: Box, widths: openArray[int], level: BoxLevel = blRow,
             edge: bool = true): string =
  ## rich box.py:115-162 -- `Box.get_row(self, widths: Iterable[int], level:
  ## Literal['head','row','foot','mid'] = 'row', edge: bool = True) -> str`:
  ## build a row border string for the given widths and level (box.py:129-161).
  ## `level` -> `BoxLevel` (default `blRow`); `widths` -> `openArray[int]`
  ## (accepts `seq`/`array`/`openArray` — materialized iterables; closure
  ## iterators are a conscious body boundary, as for `segment.nim`). body
  ## body needs `loop_last` (box.py:138).
  var left, horizontal, cross, right: string
  case level
  of blHead:
    left = self.headRowLeft; horizontal = self.headRowHorizontal
    cross = self.headRowCross; right = self.headRowRight
  of blRow:
    left = self.rowLeft; horizontal = self.rowHorizontal
    cross = self.rowCross; right = self.rowRight
  of blMid:
    left = self.midLeft; horizontal = " "
    cross = self.midVertical; right = self.midRight
  of blFoot:
    left = self.footRowLeft; horizontal = self.footRowHorizontal
    cross = self.footRowCross; right = self.footRowRight
  var parts: seq[string] = @[]
  if edge:
    parts.add(left)
  for i, width in widths:
    parts.add(horizontal.repeat(width))
    if i != widths.high:
      parts.add(cross)
  if edge:
    parts.add(right)
  result = parts.join("")

proc getBottom*(self: Box, widths: openArray[int]): string =
  ## rich box.py:164-182 -- `Box.get_bottom(self, widths: Iterable[int]) -> str`:
  ## build the bottom border string for the given column widths (box.py:174-181).
  ## `widths: Iterable[int]` -> `openArray[int]` (accepts `seq`/`array`/
  ## `openArray` — materialized iterables; closure iterators are a conscious
  ## body boundary, as for `segment.nim`). Body needs `loop_last`
  ## (box.py:178).
  var parts: seq[string] = @[]
  parts.add(self.bottomLeft)
  for i, width in widths:
    parts.add(self.bottom.repeat(width))
    if i != widths.high:
      parts.add(self.bottomDivider)
  parts.add(self.bottomRight)
  result = parts.join("")

# ---------------------------------------------------------------------------
# Box constants -- box.py:186-401 (19 boxes; data persisted verbatim)
# ---------------------------------------------------------------------------

let ASCII* = initBox("+--+\n| ||\n|-+|\n| ||\n|-+|\n|-+|\n| ||\n+--+\n", ascii = true)
  ## rich box.py:186-196 -- `ASCII: Box = Box(...)` (`ascii=True`). The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let ASCII2* = initBox("+-++\n| ||\n+-++\n| ||\n+-++\n+-++\n| ||\n+-++\n", ascii = true)
  ## rich box.py:198-208 -- `ASCII2: Box = Box(...)` (`ascii=True`). The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let ASCII_DOUBLE_HEAD* = initBox("+-++\n| ||\n+=++\n| ||\n+-++\n+-++\n| ||\n+-++\n", ascii = true)
  ## rich box.py:210-220 -- `ASCII_DOUBLE_HEAD: Box = Box(...)` (`ascii=True`). The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let SQUARE* = initBox("┌─┬┐\n│ ││\n├─┼┤\n│ ││\n├─┼┤\n├─┼┤\n│ ││\n└─┴┘\n", ascii = false)
  ## rich box.py:222-231 -- `SQUARE: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let SQUARE_DOUBLE_HEAD* = initBox("┌─┬┐\n│ ││\n╞═╪╡\n│ ││\n├─┼┤\n├─┼┤\n│ ││\n└─┴┘\n", ascii = false)
  ## rich box.py:233-242 -- `SQUARE_DOUBLE_HEAD: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let MINIMAL* = initBox("  ╷ \n  │ \n╶─┼╴\n  │ \n╶─┼╴\n╶─┼╴\n  │ \n  ╵ \n", ascii = false)
  ## rich box.py:244-253 -- `MINIMAL: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let MINIMAL_HEAVY_HEAD* = initBox("  ╷ \n  │ \n╺━┿╸\n  │ \n╶─┼╴\n╶─┼╴\n  │ \n  ╵ \n", ascii = false)
  ## rich box.py:256-265 -- `MINIMAL_HEAVY_HEAD: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let MINIMAL_DOUBLE_HEAD* = initBox("  ╷ \n  │ \n ═╪ \n  │ \n ─┼ \n ─┼ \n  │ \n  ╵ \n", ascii = false)
  ## rich box.py:267-276 -- `MINIMAL_DOUBLE_HEAD: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let SIMPLE* = initBox("    \n    \n ── \n    \n    \n ── \n    \n    \n", ascii = false)
  ## rich box.py:279-288 -- `SIMPLE: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let SIMPLE_HEAD* = initBox("    \n    \n ── \n    \n    \n    \n    \n    \n", ascii = false)
  ## rich box.py:290-299 -- `SIMPLE_HEAD: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let SIMPLE_HEAVY* = initBox("    \n    \n ━━ \n    \n    \n ━━ \n    \n    \n", ascii = false)
  ## rich box.py:302-311 -- `SIMPLE_HEAVY: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let HORIZONTALS* = initBox(" ── \n    \n ── \n    \n ── \n ── \n    \n ── \n", ascii = false)
  ## rich box.py:314-323 -- `HORIZONTALS: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let ROUNDED* = initBox("╭─┬╮\n│ ││\n├─┼┤\n│ ││\n├─┼┤\n├─┼┤\n│ ││\n╰─┴╯\n", ascii = false)
  ## rich box.py:325-334 -- `ROUNDED: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let HEAVY* = initBox("┏━┳┓\n┃ ┃┃\n┣━╋┫\n┃ ┃┃\n┣━╋┫\n┣━╋┫\n┃ ┃┃\n┗━┻┛\n", ascii = false)
  ## rich box.py:336-345 -- `HEAVY: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let HEAVY_EDGE* = initBox("┏━┯┓\n┃ │┃\n┠─┼┨\n┃ │┃\n┠─┼┨\n┠─┼┨\n┃ │┃\n┗━┷┛\n", ascii = false)
  ## rich box.py:347-356 -- `HEAVY_EDGE: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let HEAVY_HEAD* = initBox("┏━┳┓\n┃ ┃┃\n┡━╇┩\n│ ││\n├─┼┤\n├─┼┤\n│ ││\n└─┴┘\n", ascii = false)
  ## rich box.py:358-367 -- `HEAVY_HEAD: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let DOUBLE* = initBox("╔═╦╗\n║ ║║\n╠═╬╣\n║ ║║\n╠═╬╣\n╠═╬╣\n║ ║║\n╚═╩╝\n", ascii = false)
  ## rich box.py:369-378 -- `DOUBLE: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let DOUBLE_EDGE* = initBox("╔═╤╗\n║ │║\n╟─┼╢\n║ │║\n╟─┼╢\n╟─┼╢\n║ │║\n╚═╧╝\n", ascii = false)
  ## rich box.py:380-389 -- `DOUBLE_EDGE: Box = Box(...)`. The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
let MARKDOWN* = initBox("    \n| ||\n|-||\n| ||\n|-||\n|-||\n| ||\n    \n", ascii = true)
  ## rich box.py:391-401 -- `MARKDOWN: Box = Box(...)` (`ascii=True`). The 8-line box string is
  ## persisted verbatim in `boxStr`; the parsed char fields default to empty
  ## (populated by `initBox` in body).

# ---------------------------------------------------------------------------
# Substitution dicts -- box.py:405-421 (identity-keyed `Box`->`Box`)
# ---------------------------------------------------------------------------

let LEGACY_WINDOWS_SUBSTITUTIONS* = [ (ROUNDED, SQUARE), (MINIMAL_HEAVY_HEAD, MINIMAL), (SIMPLE_HEAVY, SIMPLE), (HEAVY, SQUARE), (HEAVY_EDGE, SQUARE), (HEAVY_HEAD, SQUARE) ].toTable
  ## rich box.py:405-412 -- `LEGACY_WINDOWS_SUBSTITUTIONS = {...}`: map boxes that
  ## don't render with raster fonts to equivalents that do (used by
  ## `Box.substitute` on `legacy_windows`, box.py:78). 6 entries. A
  ## `Table[Box, Box]` keyed by `Box` ref identity (Nim hashes `ref` by
  ## pointer, faithfully mirroring Python's id-based dict -- `Box` defines
  ## no `__eq__`/`__hash__`).

let PLAIN_HEADED_SUBSTITUTIONS* = [ (HEAVY_HEAD, SQUARE), (SQUARE_DOUBLE_HEAD, SQUARE), (MINIMAL_DOUBLE_HEAD, MINIMAL), (MINIMAL_HEAVY_HEAD, MINIMAL), (ASCII_DOUBLE_HEAD, ASCII2) ].toTable
  ## rich box.py:415-421 -- `PLAIN_HEADED_SUBSTITUTIONS = {...}`: map headed
  ## boxes to their headerless equivalents (used by
  ## `Box.get_plain_headed_box`, box.py:92). 5 entries. A `Table[Box, Box]`
  ## keyed by `Box` ref identity (see `LEGACY_WINDOWS_SUBSTITUTIONS`).

proc substitute*(self: Box, options: ConsoleOptions, safe: bool = true): Box =
  ## rich box.py:67-83 -- `Box.substitute(self, options: ConsoleOptions, safe:
  ## bool = True) -> Box`: substitute this box for another if it won't render on
  ## the platform -- on `legacy_windows` use `LEGACY_WINDOWS_SUBSTITUTIONS`; if
  ## `ascii_only` and not `box.ascii` use `ASCII` (box.py:78-82). `ConsoleOptions`
  ## from `richbase`.
  result = self
  if options.legacyWindows and safe:
    result = LEGACY_WINDOWS_SUBSTITUTIONS.getOrDefault(result, result)
  if options.asciiOnly and not result.ascii:
    result = ASCII

proc getPlainHeadedBox*(self: Box): Box =
  ## rich box.py:85-93 -- `Box.get_plain_headed_box(self) -> Box`: return the
  ## equivalent box without header-specific chars via
  ## `PLAIN_HEADED_SUBSTITUTIONS.get(self, self)` (box.py:92-93).
  result = PLAIN_HEADED_SUBSTITUTIONS.getOrDefault(self, self)
