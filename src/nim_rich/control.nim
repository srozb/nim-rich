## Port of `rich.control` (rich/control.py).
##
## `Control` is a renderable that inserts a non-printable ANSI control code
## sequence (cursor moves, screen clear, alt-screen, window title, …). It is
## built from `ControlType`/`ControlCode` values (from `richbase`, re-exported
## via `segment`) and rendered as a single control `Segment`.
##
## Import graph (control.py:1-8): `import time` (control.py:1, body-only in the
## `__main__` demo — not imported), `from typing import TYPE_CHECKING,
## Callable, Dict, Iterable, List, Union, Final` (control.py:2) → `std/options`
## is NOT needed (no `Optional` in the public API); the `Dict[int, Callable]`
## / `Final` typing is Nim-only structural (see data notes below).
## `from .segment import ControlCode, ControlType, Segment` (control.py:4) →
## `segment` (which `export richbase`, so `ControlType`/`ControlCode`/`Segment`
## /`ConsoleHandle`/`ConsoleOptions`/`RenderResult`/`RenderableBase` are all
## visible). `from .console import Console, ConsoleOptions, RenderResult`
## (control.py:6-7) is `TYPE_CHECKING`-only → supplied by `segment`.
##
## Module-level data (control.py:11-40): `STRIP_CONTROL_CODES: Final = [7, 8,
## 11, 12, 13]` (control.py:11-17) → `const stripControlCodes` (a plain
## `array[5, int]`, the control codepoints stripped by
## `strip_control_codes`). `CONTROL_ESCAPE: Final = {7: "\\a", 8: "\\b", 11:
## "\\v", 12: "\\f", 13: "\\r"}` (control.py:24-31) → `const controlEscape`
## (`array[5, (int, string)]`, the escaped-name table used by
## `escape_control_codes`). `_CONTROL_STRIP_TRANSLATE` (control.py:19-22) and
## `CONTROL_CODES_FORMAT: Dict[int, Callable[..., str]]` (control.py:33-40)
## are runtime dispatch tables (a `str.translate` map and a `ControlType`→ANSI
## formatter dict whose lambdas are parameterised); both are Body
## concerns, so they are documented here rather than persisted as Nim data.
##
## Faithfulness: `Control` (control.py:43-118) has `__slots__ = ["segment"]`
## (control.py:48) and `__rich_console__` (control.py:111-116) → `ref object of
## RenderableBase` with a `segment: Segment` field (Python reference semantics
## + renderable). `__init__(self, *codes: Union[ControlType, ControlCode])`
## (control.py:51-58) → `initControl(codes: varargs[ControlCode])`; a bare
## `ControlType` is wrapped via `controlCode(...)` (the `Union[ControlType,
## ControlCode]` arg maps to `ControlCode`, with `controlCode(ctX)` standing in
## for the Python `(ControlType.X,)` tuple). The 9 classmethods
## (control.py:60-108) become `proc`s returning `Control`.
##
## Naming: `__init__`→`initControl`, `__str__`→`str`, `__rich_console__`→
## `renderConsole`; `strip_control_codes`→`stripControlCodes`,
## `escape_control_codes`→`escapeControlCodes`; classmethods `bell`/`home`/
## `move`/`move_to_column`→`moveToColumn`/`move_to`→`moveTo`/`clear`/
## `show_cursor`→`showCursor`/`alt_screen`→`altScreen`/`title`. Proc bodies are
## `discard` (port)` = nil ref / empty `RenderResult`).

import std/[options, unicode]

import segment       # richbase (ControlType, ControlCode, Segment, ConsoleHandle,
                     # ConsoleOptions, RenderResult, RenderableBase) — re-exported.

const
  STRIP_CONTROL_CODES* = [7, 8, 11, 12, 13]
    ## rich control.py:11-17 — `STRIP_CONTROL_CODES: Final = [7, 8, 11, 12, 13]`
    ## (Bell, Backspace, Vertical tab, Form feed, Carriage return): the
    ## codepoints removed by `stripControlCodes`. Keeps the Python SCREAMING
    ## name (like `default_styles.DEFAULT_STYLES`); the const (first char 'S')
    ## and the `stripControlCodes` proc (first char 's') coexist via Nim's
    ## first-char case sensitivity. A plain `array[5, int]`.

  CONTROL_ESCAPE*: array[5, (int, string)] = [
    (7, "\\a"),
    (8, "\\b"),
    (11, "\\v"),
    (12, "\\f"),
    (13, "\\r"),
  ]
    ## rich control.py:24-31 — `CONTROL_ESCAPE: Final = {7: "\\a", 8: "\\b",
    ## 11: "\\v", 12: "\\f", 13: "\\r"}`: the escaped-name table used by
    ## `escapeControlCodes` (e.g. `"\b"` → `"\\b"`). Keeps the Python SCREAMING
    ## name (coexists with the `escapeControlCodes` proc via first-char case).
    ## A `array[5, (int, string)]` (Nim has no `int`-keyed dict literal; body's
    ## body can build a `Table[int, string]` from it).

type
  Control* = ref object of RenderableBase
    ## rich control.py:43-118 — `class Control`: a renderable that inserts a
    ## control code. `ref object of RenderableBase` (Python reference semantics
    ## + console renderable). `__slots__ = ["segment"]` (control.py:48) → the
    ## single `segment` field.
    segment*: Segment
      ## control.py:57 — `self.segment = Segment(rendered_codes, None,
      ## control_codes)` (the rendered ANSI string + the source `ControlCode`
      ## list). `Segment` (text, style=None, control=codes) from richbase.

# `CONTROL_CODES_FORMAT` (control.py:33-40) is a `Dict[int, Callable[..., str]]`
# dispatch table mapping a `ControlType` to a parameterised ANSI formatter. As
# the data note above says, it is a Body concern, so it is not persisted
# as Nim data; this private helper is the faithful dispatch — one branch per
# `ControlType`, reading the matching `ControlCode` payload via the richbase
# accessors (the `cckSingle`/`cckDouble` payloads are only read for the
# `ControlType`s that carry them, so the branch-conditional reads are safe).
proc formatControlCode(code: ControlCode): string =
  case code.control()
  of ctBell:
    result = "\x07"
  of ctCarriageReturn:
    result = "\r"
  of ctHome:
    result = "\x1b[H"
  of ctClear:
    result = "\x1b[2J"
  of ctEnableAltScreen:
    result = "\x1b[?1049h"
  of ctDisableAltScreen:
    result = "\x1b[?1049l"
  of ctShowCursor:
    result = "\x1b[?25h"
  of ctHideCursor:
    result = "\x1b[?25l"
  of ctCursorUp:
    result = "\x1b[" & $code.singleInt() & "A"
  of ctCursorDown:
    result = "\x1b[" & $code.singleInt() & "B"
  of ctCursorForward:
    result = "\x1b[" & $code.singleInt() & "C"
  of ctCursorBackward:
    result = "\x1b[" & $code.singleInt() & "D"
  of ctCursorMoveToColumn:
    result = "\x1b[" & $(code.singleInt() + 1) & "G"
  of ctEraseInLine:
    result = "\x1b[" & $code.singleInt() & "K"
  of ctCursorMoveTo:
    # rich lambda is `lambda x, y: f"\x1b[{y+1};{x+1}H"`; the `ControlCode`
    # `doubleI1` is `x` (column), `doubleI2` is `y` (row).
    result = "\x1b[" & $(code.doubleI2() + 1) & ";" & $(code.doubleI1() + 1) & "H"
  of ctSetWindowTitle:
    result = "\x1b]0;" & code.singleStr() & "\x07"

proc initControl*(codes: varargs[ControlCode]): Control =
  ## rich control.py:51-58 — `Control.__init__(self, *codes: Union[ControlType,
  ## ControlCode]) -> None`: wrap each bare `ControlType` as `(code,)` and
  ## format the codes via `CONTROL_CODES_FORMAT` into a single `Segment`
  ## (control.py:53-58). The Nim arg is `varargs[ControlCode]`; a bare
  ## `ControlType` is passed as `controlCode(ctX)` (the `Union[ControlType,
  ## ControlCode]`→`ControlCode` mapping).
  new(result)
  var controlCodes: seq[ControlCode] = @codes
  var rendered: string = ""
  for code in controlCodes:
    rendered.add(formatControlCode(code))
  result.segment = Segment(text: rendered, style: none(StyleRef),
                            control: some(controlCodes))

proc bell*(): Control =
  ## rich control.py:60-62 — `Control.bell(cls) -> Control` (`@classmethod`):
  ## ring the bell — `Control(ControlType.BELL)`.
  result = initControl(controlCode(ctBell))

proc home*(): Control =
  ## rich control.py:64-66 — `Control.home(cls) -> Control`: move cursor to
  ## home — `Control(ControlType.HOME)`.
  result = initControl(controlCode(ctHome))

proc move*(x: int = 0, y: int = 0): Control =
  ## rich control.py:68-92 — `Control.move(cls, x: int = 0, y: int = 0) ->
  ## Control`: move cursor relative to the current position, emitting
  ## `CURSOR_FORWARD`/`CURSOR_BACKWARD` for `x` and `CURSOR_DOWN`/`CURSOR_UP`
  ## for `y` (control.py:79-90).
  if x == 0 and y == 0:
    result = initControl()
  elif x != 0 and y != 0:
    let cx = if x > 0: controlCode(ctCursorForward, abs(x))
             else: controlCode(ctCursorBackward, abs(x))
    let cy = if y > 0: controlCode(ctCursorDown, abs(y))
             else: controlCode(ctCursorUp, abs(y))
    result = initControl(cx, cy)
  elif x != 0:
    let cx = if x > 0: controlCode(ctCursorForward, abs(x))
             else: controlCode(ctCursorBackward, abs(x))
    result = initControl(cx)
  else:
    let cy = if y > 0: controlCode(ctCursorDown, abs(y))
             else: controlCode(ctCursorUp, abs(y))
    result = initControl(cy)

proc moveToColumn*(x: int, y: int = 0): Control =
  ## rich control.py:94-108 — `Control.move_to_column(cls, x: int, y: int = 0)
  ## -> Control`: move to the given column, optionally adding a row offset
  ## (control.py:103-108).
  let col = controlCode(ctCursorMoveToColumn, x)
  if y == 0:
    result = initControl(col)
  else:
    let row = if y > 0: controlCode(ctCursorDown, abs(y))
              else: controlCode(ctCursorUp, abs(y))
    result = initControl(col, row)

proc moveTo*(x: int, y: int): Control =
  ## rich control.py:110-118 — `Control.move_to(cls, x: int, y: int) ->
  ## Control`: move cursor to absolute position — `Control((ControlType.
  ## CURSOR_MOVE_TO, x, y))`.
  result = initControl(controlCode(ctCursorMoveTo, x, y))

proc clear*(): Control =
  ## rich control.py:120-122 — `Control.clear(cls) -> Control`: clear the
  ## screen — `Control(ControlType.CLEAR)`.
  result = initControl(controlCode(ctClear))

proc showCursor*(show: bool): Control =
  ## rich control.py:124-126 — `Control.show_cursor(cls, show: bool) ->
  ## Control`: show or hide the cursor — `Control(ControlType.SHOW_CURSOR if
  ## show else ControlType.HIDE_CURSOR)`.
  result = initControl(controlCode(if show: ctShowCursor else: ctHideCursor))

proc altScreen*(enable: bool): Control =
  ## rich control.py:128-132 — `Control.alt_screen(cls, enable: bool) ->
  ## Control`: enable/disable the alt screen — `Control(ControlType.
  ## ENABLE_ALT_SCREEN, ControlType.HOME)` if `enable` else
  ## `Control(ControlType.DISABLE_ALT_SCREEN)` (control.py:130-132).
  if enable:
    result = initControl(controlCode(ctEnableAltScreen), controlCode(ctHome))
  else:
    result = initControl(controlCode(ctDisableAltScreen))

proc title*(title: string): Control =
  ## rich control.py:134-141 — `Control.title(cls, title: str) -> Control`:
  ## set the terminal window title — `Control((ControlType.SET_WINDOW_TITLE,
  ## title))`.
  result = initControl(controlCode(ctSetWindowTitle, title))

proc str*(self: Control): string =
  ## rich control.py:107-108 — `Control.__str__(self) -> str`: return
  ## `self.segment.text` (the rendered ANSI string). `__str__`→`str` (a
  ## descriptive dunder name, consistent with `emoji.nim`).
  result = self.segment.text

method renderConsole*(self: Control, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich control.py:111-116 — `Control.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> RenderResult`: yield
  ## `self.segment` if it has text (control.py:113-115). `__rich_console__`→
  ## `renderConsole`; `ConsoleHandle`/`ConsoleOptions`/`RenderResult` from
  ## richbase.
  # Faithful guard (control.py:113-115): a `Control` with a non-empty rendered
  # string yields its single `Segment` (`self.segment`, carrying both the
  # rendered ANSI text and the source `ControlCode` list set in `initControl`).
  # `yield self.segment` (control.py:115) verbatim via `addSegment`.
  result = @[]
  if self.segment.text.len > 0:
    result.addSegment(self.segment)

proc stripControlCodes*(text: string): string =
  ## rich control.py:119-135 — `strip_control_codes(text: str) -> str`:
  ## remove the `STRIP_CONTROL_CODES` codepoints from `text` via
  ## `str.translate(_CONTROL_STRIP_TRANSLATE)` (control.py:132).
  result = ""
  for r in text.runes:
    let cp = ord(r).int
    var keep = true
    for stripped in STRIP_CONTROL_CODES:
      if cp == stripped:
        keep = false
        break
    if keep:
      result.add(toUTF8(r))

proc escapeControlCodes*(text: string): string =
  ## rich control.py:138-154 — `escape_control_codes(text: str) -> str`:
  ## replace control codes with their escaped equivalent (e.g. `"\b"` →
  ## `"\\b"`) via `str.translate(CONTROL_ESCAPE)` (control.py:152).
  result = ""
  for r in text.runes:
    let cp = ord(r).int
    var esc = ""
    var found = false
    for (codepoint, name) in CONTROL_ESCAPE:
      if cp == codepoint:
        esc = name
        found = true
        break
    if found:
      result.add(esc)
    else:
      result.add(toUTF8(r))
