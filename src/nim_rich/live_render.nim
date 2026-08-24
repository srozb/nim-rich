## nim_rich / live_render.nim — faithful port of `rich.live_render` (rich/live_render.py).
## =====================================================================
## `LiveRender` creates a renderable that may be updated in place — it is the
## rendering engine behind `rich.live.Live` (live_render.py:18-116). It tracks
## the last render's shape so the cursor can be repositioned (carriage-return +
## cursor-up + erase-in-line) for the next refresh (live_render.py:64-85).
##
## Import graph (faithful to live_render.py:1-8): runtime sibling imports are
## `from typing import Literal, Optional, Tuple` (live_render.py:1), `from
## ._loop import loop_last` (live_render.py:3), `from .console import Console,
## ConsoleOptions, RenderableType, RenderResult` (live_render.py:4), `from
## .control import Control` (live_render.py:5), `from .segment import
## ControlType, Segment` (live_render.py:6), `from .style import StyleType`
## (live_render.py:7), `from .text import Text` (live_render.py:8).
##
## Nim wiring:
##   `import std/options` — `Option[tuple[…]]` (the `_shape` field).
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                         `ConsoleOptions`, `RenderResult`, `RenderableType`, …)
##                         + `ControlType`/`ControlCode`/`controlCode`/
##                         `ctCarriageReturn`/`ctCursorUp`/`ctEraseInLine`
##                         (live_render.py:6) + `Segment` (live_render.py:6) +
##                         `Style`/`StyleRef` (re-exported) + `getShape` (the
##                         `Segment.get_shape` classmethod, segment.py:411-423).
##   `import style`        — `StyleType` (live_render.py:7; the typeclass for
##                         the `style` param) + `StyleValue`/`svkStr`/`svkStyle`.
##   `import text`         — `Text` (live_render.py:8) + `initText`.
##   `import api_types`    — `RenderableValue` (the `RenderableType` field
##                         handle for `renderable`).
##   `import console_api`  — the cycle-breaker leaf exposing `getStyle`/
##                         `renderLines`/`render` as `{.base.}` methods on
##                         `ConsoleHandle` (the real `Console`, `ref object of
##                         ConsoleHandle`, overrides them — virtual dispatch).
##                         `live_render` cannot `import console` (the cycle
##                         `live_render`→`console`→`live`→`live_render`); this
##                         leaf mirrors how `table.nim` reaches `Console`
##                         methods. `console.get_style`→`getStyle`,
##                         `console.render_lines`→`renderLines`,
##                         `console.render`→`render` (live_render.py:91-92,101).
##   `import control`      — `Control` (live_render.py:5) for the
##                         `positionCursor`/`restoreCursor` return type +
##                         cursor-code construction. Cycle-safe (`control`
##                         imports only `segment` + stdlib).
## `loop_last` (`_loop`, live_render.py:3) is inlined here as an index test
## (`i < working.len - 1` ≡ `not last`), so no `_loop` module is needed.
##
## `VerticalOverflowMethod = Literal["crop", "ellipsis", "visible"]`
## (live_render.py:11) is DEFINED here (not in `console`) and re-exported to
## `live.nim` (live.py:7 `from .live_render import …, VerticalOverflowMethod`)
## — modelled as a Nim `enum` (`vomCrop`/`vomEllipsis`/`vomVisible`), mirroring
## the `JustifyMethod`/`OverflowMethod` pattern in `richbase`.
##
## `LiveRender` (no rich base class — plain `class`) is `ref object of
## RenderableBase` (Nim-only storage base, matching how `bar.nim`/`panel.nim`
## model baseless renderables). `renderable: RenderableType` (live_render.py:23)
## → field `RenderableValue` (param stays the `RenderableType` typeclass);
## `style: StyleType = ""` (live_render.py:24) → field `StyleValue` (param the
## `StyleType` typeclass, default `""`); `vertical_overflow:
## VerticalOverflowMethod = "ellipsis"` (live_render.py:25) → field
## `VerticalOverflowMethod` (default `vomEllipsis`). The private `_shape:
## Optional[Tuple[int, int]] = None` (live_render.py:26) → `Option[tuple
## [columns, rows: int]]` (module-private, mirrors the `_`-prefix). Naming:
## `__init__`→`initLiveRender`, `last_render_height`→`lastRenderHeight`,
## `set_renderable`→`setRenderable`, `position_cursor`→`positionCursor`,
## `restore_cursor`→`restoreCursor`, `__rich_console__`→`renderConsole`.

import std/options

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableType, …) + ControlType/ControlCode/controlCode/
                    # ctCarriageReturn/ctCursorUp/ctEraseInLine + Segment +
                    # Style/StyleRef + getShape (Segment.get_shape).
import style        # StyleType (the typeclass for the `style` param) +
                    # StyleValue/svkStr/svkStyle (the Union[str, Style] field).
import text         # Text (live_render.py:8) + initText (overflow ellipsis).
import api_types    # RenderableValue (the RenderableType field handle).
import console_api  # getStyle/renderLines/render on ConsoleHandle (the
                    # cycle-breaker leaf — `import console` would cycle
                    # live_render→console→live→live_render). Virtual dispatch
                    # reaches the real Console overrides (live_render.py:91-92,101).
import control      # Control (live_render.py:5) — the positionCursor/
                    # restoreCursor return type + cursor-code construction.
                    # Cycle-safe (control imports only segment + stdlib).

type
  VerticalOverflowMethod* = enum
    ## rich live_render.py:11-11 — `VerticalOverflowMethod = Literal["crop",
    ## "ellipsis", "visible"]` — how `LiveRender`/`Live` handle a renderable
    ## that is too tall for the console. Modelled as a Nim `enum` mirroring the
    ## `JustifyMethod`/`OverflowMethod` pattern in richbase (a `Literal[…]`
    ## has a fixed member set, exactly like an enum). Re-exported to `live.nim`
    ## (live.py:7 `from .live_render import …, VerticalOverflowMethod`).
    vomCrop      ## the `"crop"`     literal — clip overflow lines to `options.size.height` (live_render.py:74-76).
    vomEllipsis  ## the `"ellipsis"` literal (the default) — clip to `height-1` and append a centred `"…"` line (live_render.py:77-87).
    vomVisible   ## the `"visible"`  literal — render the full renderable regardless of height (live.py:122 sets this on the final `stop`).

  LiveRender* = ref object of RenderableBase
    ## rich live_render.py:18-116 — `class LiveRender`: a renderable that may be
    ## updated in place; tracks the last render's shape for cursor
    ## repositioning. `ref object of RenderableBase` (Nim-only storage base;
    ## rich `LiveRender` has no base class — matching how `bar.nim`/`panel.nim`
    ## model baseless renderables). Fields mirror the `__init__` assignments
    ## (live_render.py:23-26).
    renderable*: RenderableValue
      ## rich live_render.py:23-23 — `self.renderable = renderable`
      ## (`RenderableType`; the `api_types.RenderableValue` case object).
    styleField*: StyleValue
      ## rich live_render.py:24-24 — `self.style = style` (`StyleType =
      ## Union[str, Style]`; the `text.StyleValue` field, default `""`). Renamed
      ## `style`→`styleField` to avoid clashing with the `style` import module
      ## name (an Nim module-id conflict on `self.style`).
    verticalOverflow*: VerticalOverflowMethod
      ## rich live_render.py:25-25 — `self.vertical_overflow = vertical_overflow`
      ## (`VerticalOverflowMethod`; default `vomEllipsis`).
    shape*: Option[tuple[columns, rows: int]]
      ## rich live_render.py:26-26 — `self._shape: Optional[Tuple[int, int]] =
      ## None` (module-private, mirrors the `_`-prefix; `Option[tuple[columns,
      ## rows: int]]`, default `none(…)` — the `(width, height)` of the last
      ## render; `lastRenderHeight` reads `shape[1]`).

proc initLiveRender*(renderable: RenderableValue, style: StyleType = "",
                     verticalOverflow: VerticalOverflowMethod = vomEllipsis): LiveRender =
  ## rich live_render.py:18-26 — `LiveRender.__init__(self, renderable:
  ## RenderableType, style: StyleType = "", vertical_overflow:
  ## VerticalOverflowMethod = "ellipsis") -> None`: store `renderable`,
  ## `style`, `vertical_overflow` and init `_shape = None` (live_render.py:23-
  ## 26). `renderable` keeps the faithful `RenderableType` typeclass (richbase)
  ## and is stored as `RenderableValue`; `style: StyleType = ""` → typeclass
  ## param (default `""`), stored as `StyleValue`; `vertical_overflow:
  ## VerticalOverflowMethod = "ellipsis"` → `VerticalOverflowMethod` default
  ## `vomEllipsis`.
  result = LiveRender()
  result.renderable = renderable
  result.styleField = style
  result.verticalOverflow = verticalOverflow
  # `_shape = None` (live_render.py:26) — default-init already `none`.
  result.shape = none(tuple[columns, rows: int])

proc lastRenderHeight*(self: LiveRender): int =
  ## rich live_render.py:30-34 — `LiveRender.last_render_height` property
  ## (`@property` live_render.py:30): `0` if `_shape is None`, else
  ## `self._shape[1]` (live_render.py:33-34). Modelled as a no-arg proc
  ## (property getter).
  if self.shape.isNone:
    result = 0
  else:
    result = self.shape.get.rows

proc setRenderable*(self: LiveRender, renderable: RenderableValue) =
  ## rich live_render.py:38-44 — `LiveRender.set_renderable(self, renderable:
  ## RenderableType) -> None`: set `self.renderable = renderable`
  ## (live_render.py:43). `renderable` keeps the faithful `RenderableType`
  ## typeclass (richbase); the field stores it as `RenderableValue`.
  self.renderable = renderable

proc renderCtrlCodes(codes: seq[ControlCode]): string =
  ## Inline ANSI formatting for the three `ControlType`s `LiveRender` emits
  ## (mirrors `control.formatControlCode`, which is module-private in
  ## `control.nim`). Faithful to rich `CONTROL_CODES_FORMAT`
  ## (control.py:33-40): `CARRIAGE_RETURN`→`"\r"`, `CURSOR_UP`→`"\x1b[NA"`,
  ## `ERASE_IN_LINE`→`"\x1b[NK"`. `LiveRender` emits only these three
  ## (live_render.py:56-82); the `else` arm is unreachable but kept for
  ## exhaustiveness.
  for code in codes:
    case code.control()
    of ctCarriageReturn: result.add("\r")
    of ctCursorUp:       result.add("\x1b[" & $code.singleInt() & "A")
    of ctEraseInLine:    result.add("\x1b[" & $code.singleInt() & "K")
    else: discard

proc positionCursor*(self: LiveRender): Control =
  ## rich live_render.py:46-64 — `LiveRender.position_cursor(self) -> Control`:
  ## build the control codes to move the cursor to the beginning of the live
  ## render — `CARRIAGE_RETURN` + `ERASE_IN_LINE(2)`, then per extra line
  ## `CURSOR_UP(1)` + `ERASE_IN_LINE(2)` (live_render.py:56-64); an empty
  ## `Control()` if `_shape is None` (live_render.py:62-63). Returns the real
  ## `control.Control` carrying the rendered codes + source `ControlCode` list
  ## (mirrors `Control.__init__`, control.py:51-58).
  if self.shape.isSome:
    let height = self.shape.get.rows
    var codes: seq[ControlCode] = @[controlCode(ctCarriageReturn),
                                    controlCode(ctEraseInLine, 2)]
    if height > 1:
      for _ in 1 .. height - 1:
        codes.add(controlCode(ctCursorUp, 1))
        codes.add(controlCode(ctEraseInLine, 2))
    new(result)
    result.segment = Segment(text: renderCtrlCodes(codes),
                              style: none(StyleRef), control: some(codes))
  else:
    result = initControl()

proc restoreCursor*(self: LiveRender): Control =
  ## rich live_render.py:66-83 — `LiveRender.restore_cursor(self) -> Control`:
  ## build the control codes to clear the render and restore the cursor —
  ## `CARRIAGE_RETURN`, then per line `CURSOR_UP(1)` + `ERASE_IN_LINE(2)`
  ## (live_render.py:74-82); an empty `Control()` if `_shape is None`
  ## (live_render.py:82-83). Returns the real `control.Control` carrying the
  ## rendered codes + source `ControlCode` list (mirrors `Control.__init__`,
  ## control.py:51-58).
  if self.shape.isSome:
    let height = self.shape.get.rows
    var codes: seq[ControlCode] = @[controlCode(ctCarriageReturn)]
    for _ in 1 .. height:
      codes.add(controlCode(ctCursorUp, 1))
      codes.add(controlCode(ctEraseInLine, 2))
    new(result)
    result.segment = Segment(text: renderCtrlCodes(codes),
                              style: none(StyleRef), control: some(codes))
  else:
    result = initControl()

method renderConsole*(self: LiveRender, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich live_render.py:85-115 — `LiveRender.__rich_console__(self, console:
  ## Console, options: ConsoleOptions) -> RenderResult`: render `renderable`
  ## to lines (`console.render_lines`, live_render.py:92) with `pad=False` and
  ## the resolved `style` applied, capture the shape (`Segment.get_shape`,
  ## live_render.py:93), apply the `vertical_overflow` policy (crop/ellipsis,
  ## live_render.py:95-105) when the height exceeds `options.size.height`,
  ## store `self._shape`, then yield the lines joined by new-line segments
  ## (`loop_last`, live_render.py:108-113). The `console.getStyle`/
  ## `console.renderLines`/`console.render` calls dispatch via the
  ## `console_api` `{.base.}` methods to the real `Console` overrides.
  ##
  ## Non-interactive render semantics: a single `console.print(LiveRender(R),
  ## end="")` renders `R` to lines (no right-padding — `pad=False`), joins them
  ## with `"\n"` between lines (NOT after the last), and the print path's crop
  ## is idempotent on the already-cropped lines — so the output equals
  ## `console.print(R, end="")` minus exactly one trailing `"\n"` (when `R`
  ## yields a trailing `"\n"`, as Panel/Table/Columns do; Text does not). This
  ## is the byte-exact behaviour verified against rich 15.0.0.
  result = @[]
  # live_render.py:91 — `style = console.get_style(self.style)`. The `styleField`
  # is `StyleValue` (`Union[str, Style]`); dispatch the arm to the handle's
  # `getStyle` (str → theme-lookup+parse, Style → as-is).
  let style: Style =
    case self.styleField.kind
    of svkStr: console.getStyle(self.styleField.strv)
    of svkStyle: self.styleField.stv
  # live_render.py:92 — `lines = console.render_lines(renderable, options,
  # style=style, pad=False)`. `pad=False` ⇒ lines are cropped to `maxWidth`
  # but NOT right-padded (the key divergence from `console.print(R)`'s direct
  # yield: only the trailing `"\n"` differs).
  let lines = console.renderLines(self.renderable, some(options),
                                  style = some(style), pad = false)
  # live_render.py:93 — `shape = Segment.get_shape(lines)`.
  var shape = getShape(lines)
  var working = lines
  # live_render.py:95-105 — vertical_overflow crop/ellipsis (only when
  # `height > options.size.height`).
  let h = shape.rows
  if h > options.size.height:
    if self.verticalOverflow == vomCrop:
      # live_render.py:96-98 — `lines = lines[:options.size.height]`.
      working = lines[0 ..< options.size.height]
      shape = getShape(working)
    elif self.verticalOverflow == vomEllipsis:
      # live_render.py:99-105 — `lines = lines[:options.size.height-1]` then
      # append a centred `"…"` line (`Text("...", overflow="crop",
      # justify="center", end="", style="live.ellipsis")`).
      working = lines[0 ..< max(0, options.size.height - 1)]
      let overflowText = initText("...", overflow = some(omCrop),
                                  justify = some(jmCenter), `end` = "",
                                  style = "live.ellipsis")
      let rendered = console.render(overflowText, some(options))
      var ovLine: seq[Segment] = @[]
      for it in rendered:
        if it.kind == rrkSegment: ovLine.add(it.segmentItem)
      working.add(ovLine)
      shape = getShape(working)
  self.shape = some(shape)
  # live_render.py:108-113 — yield each line, joined by a new-line `Segment`
  # between lines (NOT after the last) — `loop_last(lines)` inlined as
  # `i < working.len - 1` (≡ `not last`).
  let newLine = Segment(text: "\n")
  for i, line in working:
    for seg in line:
      addSegment(result, seg)
    if i < working.len - 1:
      addSegment(result, newLine)
