## Port of `rich.padding` (rich/padding.py).
##
## `Padding` draws space around a renderable (padding.py:19-135); `PaddingDimensions`
## is the `pad` union (padding.py:16).
##
## Import graph (rich/padding.py:1-14): runtime sibling imports are
## `from .jupyter import JupyterMixin` (padding.py:11, the base), `from .measure
## import Measurement` (padding.py:12), `from .segment import Segment`
## (padding.py:13, body-only — `__rich_console__` @99,101,103), `from .style
## import Style` (padding.py:14); `Console`, `ConsoleOptions`, `RenderableType`,
## `RenderResult` come from `.console` (padding.py:4-9) under `TYPE_CHECKING`.
## NOTABLY padding.py does **not** import `cells`/`constrain`/`text` (the
## `cell_len`/`set_cell_size` use is absent — `__rich_console__` measures via
## `Measurement.get`, padding.py:90).
##
## wiring (this file):
##   `import segment`      — re-exports `richbase` (`ConsoleOptions`,
##                         `ConsoleHandle`, `RenderResult`, `RenderableBase`,
##                         `RenderableType`, `NO_CHANGE`, …) + `Segment`.
##   `import style`        — `Style`, `StyleType` (`string or Style`, padding.py:38's
##                         `style: Union[str, Style]` param).
##   `import measure`      — `Measurement` (padding.py:12, the `__rich_measure__`
##                         return + `__rich_console__` @90).
##   `import text`         — `StyleValue` (the `Union[str, Style]` case object, for
##                         the `Padding.style` field — faithful to
##                         `Union[str, Style]`, no `None` arm).
##   `import api_types`    — `RenderableValue` (the storable `RenderableType`
##                         handle, for the `renderable` field).
## `jupyter` is the base (modelled via `RenderableBase`, as `segment.nim`/
## `rule.nim`/`align.nim` do). `renderConsole` (port port of
## `__rich_console__`, padding.py:79-123) adds `std/options` (lazy
## `blankSeg: Option[Segment]` + `renderLines`'s `Option[Style]`/
## `Option[ConsoleOptions]` args), `std/strutils` (`repeat` for the `" "*n` space
## runs), and `console_api` (`ConsoleHandle.getStyle`/`renderLines` dispatch —
## the cycle-breaker leaf, since `padding → console → terminal_theme → palette
## → table → padding` is a real Nim 2.2.10 cycle).
##
## `Padding` is `ref object of RenderableBase` (Python reference semantics). The
## `renderable: "RenderableType"` field (padding.py:41) needs a concrete Nim
## storage type → `api_types.RenderableValue`; the `renderable` PARAM keeps the
## faithful `RenderableType` typeclass (richbase). `pad: "PaddingDimensions" =
## (0, 0, 0, 0)` (padding.py:36) → the `PaddingDimensions` case object (default
## `pdQuad(0,0,0,0)`); the `toPaddingDimensions*` converters accept every legal
## Python variant (`int`, `(v: int)` [the 1-tuple `Tuple[int]`], `(int,int)`,
## `(int,int,int,int)`, padding.py:16) — `Tuple[int]` is a DISTINCT `pdSingle`
## arm (NOT folded into `pdInt`; `pdInt`/`pdSingle` are semantically equivalent
## under `unpack` but distinct union arms, faithful to `Union[int, Tuple[int],
## …]`). `style: Union[str, Style] = "none"` → `StyleType` param (default `"none"`) +
## `StyleValue` field; `expand: bool = True`. `top/right/bottom/left` are the
## unpacked ints (padding.py:42). `indent` classmethod (padding.py:47) →
## `typedesc[Padding]` factory (`Padding.indent(…)`); `unpack` staticmethod
## (padding.py:61) → bare proc. Naming: `__init__`→`initPadding`, `__repr__`→
## `repr`, `__rich_console__`→`renderConsole`, `__rich_measure__`→`richMeasure`.
## Proc bodies mirror the Python source.

import std/options  # Option/some/none — renderConsole's blankSeg + renderLines args.
import std/strutils # repeat — the " "*n space runs (padding.py:99,103,107,111).
import segment      # richbase (ConsoleOptions, ConsoleHandle, RenderResult,
                    # RenderableBase, RenderableType, NO_CHANGE, …) + Segment.
import style        # Style, StyleType.
import measure      # Measurement.
import text         # StyleValue.
import api_types    # RenderableValue.
import console_api  # ConsoleHandle.getStyle/renderLines dispatch (padding.py:83,99) —
                    # the cycle-breaker leaf (no `import console`).

type
  PaddingDimensionsKind* = enum
    ## [Nim-only discriminator] for `PaddingDimensions` (the `Union[int,
    ## Tuple[int], Tuple[int, int], Tuple[int, int, int, int]]` value handle,
    ## padding.py:16). One DISTINCT arm per Python union variant — `int`
    ## (`pdInt`), the single-element `Tuple[int]` (`pdSingle`),
    ## `Tuple[int, int]` (`pdPair`), `Tuple[int, int, int, int]` (`pdQuad`) —
    ## so the union is complete (four arms, not three) and every legal Python
    ## variant compiles to its own arm. `pdInt` and `pdSingle` are
    ## semantically equivalent under `unpack` (both → all-same padding,
    ## padding.py:63-67: `isinstance(pad, int)` → `(pad,pad,pad,pad)`,
    ## `len(pad)==1` → `(_pad,_pad,_pad,_pad)`), but they are DISTINCT union
    ## arms, faithful to `Union[int, Tuple[int], …]` (no folding). Nim has no
    ## anonymous 1-tuple, so `Tuple[int]` is modelled as the named 1-field tuple
    ## `tuple[v: int]` (the field name `v` is a Nim necessity; semantically a
    ## positional 1-tuple, padding.py:16).
    pdInt    ## the `int` arm (padding.py:16) — one value applied to all four sides.
    pdSingle ## the `Tuple[int]` arm (padding.py:16) — a single-element tuple `(v: int)`; all-same padding (padding.py:65-67).
    pdPair   ## the `Tuple[int, int]` arm (padding.py:16) — (vertical, horizontal).
    pdQuad   ## the `Tuple[int, int, int, int]` arm (padding.py:16) — (top, right, bottom, left).

  PaddingDimensions* = object
    ## rich padding.py:16-16 — `PaddingDimensions = Union[int, Tuple[int],
    ## Tuple[int, int], Tuple[int, int, int, int]]` as a Nim case object (a true
    ## tagged union, one arm per Python variant) so it can be used as the `pad`
    ## param (padding.py:36). `Tuple[int]` is a DISTINCT `pdSingle` arm (NOT
    ## folded into `pdInt`) — see `PaddingDimensionsKind`. The
    ## `toPaddingDimensions*` converters accept every legal Python variant
    ## (`int`, `(v: int)` [the 1-tuple], `(int,int)`, `(int,int,int,int)`); the
    ## default is `pdQuad(0,0,0,0)` (padding.py:36). Nim-only handle.
    case kind*: PaddingDimensionsKind
    of pdInt:
      intv*: int                    ## the `int` arm — one value applied to all four sides.
    of pdSingle:
      singlev*: tuple[v: int]       ## the `Tuple[int]` arm — a single-element tuple `(v: int)` (all-same padding).
    of pdPair:
      pair*: (int, int)             ## the `Tuple[int, int]` arm — (vertical, horizontal).
    of pdQuad:
      quad*: (int, int, int, int)   ## the `Tuple[int, int, int, int]` arm — (top, right, bottom, left).

  Padding* = ref object of RenderableBase
    ## rich padding.py:19-135 — `class Padding(JupyterMixin)`: draw space around
    ## a renderable. `ref object of RenderableBase` (Python reference semantics;
    ## `JupyterMixin` modelled via `RenderableBase`). Fields mirror the
    ## `__init__` assignments (padding.py:41-44).
    renderable*: RenderableValue  ## rich padding.py:41-41 — `self.renderable = renderable` (`RenderableType`; the `api_types.RenderableValue` case object).
    top*: int                      ## rich padding.py:42-42 — `self.top, self.right, self.bottom, self.left = self.unpack(pad)` (the `top`).
    right*: int                    ## rich padding.py:42-42 — the `right`.
    bottom*: int                   ## rich padding.py:42-42 — the `bottom`.
    left*: int                     ## rich padding.py:42-42 — the `left`.
    style*: StyleValue             ## rich padding.py:43-43 — `self.style = style` (`Union[str, Style]`; the `text.StyleValue` case object).
    expand*: bool                  ## rich padding.py:44-44 — `self.expand = expand` (`bool`; defaults `True`).

converter toPaddingDimensions*(x: int): PaddingDimensions =
  ## Accept an `int` (padding.py:16) as a `PaddingDimensions` value — the
  ## `pdInt` arm. Lets `Padding(r, pad=2)` compile. (`discard` ⇒
  ## `default(PaddingDimensions)` = `pdInt(0)`); wraps as
  ## `PaddingDimensions(kind: pdInt, intv: x)`.
  result = PaddingDimensions(kind: pdInt, intv: x)

converter toPaddingDimensions*(x: tuple[v: int]): PaddingDimensions =
  ## Accept a `Tuple[int]` (a single-element tuple, padding.py:16) as a
  ## `PaddingDimensions` value — the DISTINCT `pdSingle` arm. Lets
  ## `Padding(r, pad=(v: 2))` (the 1-tuple) compile, distinct from the bare
  ## `int` `pdInt` arm — faithful to `Union[int, Tuple[int], …]` (no folding).
  ## Nim has no anonymous 1-tuple, so `Tuple[int]` is modelled as the named
  ## 1-field tuple `tuple[v: int]` (the field name `v` is a Nim necessity;
  ## semantically a positional 1-tuple, padding.py:16).
  ## (`discard` ⇒ `default(PaddingDimensions)` = `pdInt(0)`); wraps as
  ## `PaddingDimensions(kind: pdSingle, singlev: x)`.
  result = PaddingDimensions(kind: pdSingle, singlev: x)

converter toPaddingDimensions*(x: (int, int)): PaddingDimensions =
  ## Accept a `Tuple[int, int]` (padding.py:16) as a `PaddingDimensions` value —
  ## the `pdPair` arm. Lets `Padding(r, pad=(2, 4))` compile. stub; Phase
  ## 1 wraps as `PaddingDimensions(kind: pdPair, pair: x)`.
  result = PaddingDimensions(kind: pdPair, pair: x)

converter toPaddingDimensions*(x: (int, int, int, int)): PaddingDimensions =
  ## Accept a `Tuple[int, int, int, int]` (padding.py:16) as a
  ## `PaddingDimensions` value — the `pdQuad` arm. Lets
  ## `Padding(r, pad=(1, 2, 3, 4))` compile. stub; wraps as
  ## `PaddingDimensions(kind: pdQuad, quad: x)`.
  result = PaddingDimensions(kind: pdQuad, quad: x)

# [unblock] forward declaration — `initPadding` (below) calls `unpack` (defined
# further down); Nim 2.2.10 disallows forward refs by default, so this bodyless
# forward decl is required. Additive & conflict-safe.
proc unpack*(pad: PaddingDimensions): (int, int, int, int)

proc initPadding*(renderable: RenderableValue,
                  pad: PaddingDimensions = PaddingDimensions(kind: pdQuad, quad: (0, 0, 0, 0)),
                  style: StyleType = "none", expand: bool = true): Padding =
  ## rich padding.py:33-44 — `Padding.__init__(self, renderable: "RenderableType",
  ## pad: "PaddingDimensions" = (0, 0, 0, 0), *, style: Union[str, Style] =
  ## "none", expand: bool = True) -> None`: unpack `pad` to
  ## `top/right/bottom/left` via `unpack` (padding.py:42) and store the fields
  ## (padding.py:41-44). Keyword-only after `pad` (Python `*`, padding.py:37).
  ## `renderable` keeps the faithful `RenderableType` typeclass (richbase); the
  ## field stores it as `RenderableValue` (body bridge). `pad:
  ## PaddingDimensions` default `(0,0,0,0)` →
  ## `PaddingDimensions(kind: pdQuad, quad: (0,0,0,0))` (the
  ## `toPaddingDimensions*` converters accept `int`/`(v: int)` [the 1-tuple]/
  ## `(int,int)`/`(int,int,int,int)`); `style: Union[str, Style] = "none"` → `StyleType`
  ## (typeclass default `"none"`); `expand` default `True`. Body needs
  ## `unpack` (padding.py:42).
  result = Padding()
  result.renderable = renderable
  let (top, right, bottom, left) = unpack(pad)   # [unblock] trailing `_` is invalid in Nim
  result.top = top
  result.right = right
  result.bottom = bottom
  result.left = left
  result.style = style
  result.expand = expand

proc indent*(T: typedesc[Padding], renderable: RenderableValue, level: int): Padding =
  ## rich padding.py:47-58 — `Padding.indent(cls, renderable: "RenderableType",
  ## level: int) -> "Padding"` (`@classmethod` padding.py:46): make a padding
  ## instance to render an indent — `Padding(renderable, pad=(0, 0, 0, level),
  ## expand=False)` (padding.py:58). Modelled as a `typedesc[Padding]` factory
  ## (called `Padding.indent(…)`, matching `fromMarkup`/`join` in text.nim).
  result = initPadding(renderable, (0, 0, 0, level), "none", false)

proc unpack*(pad: PaddingDimensions): (int, int, int, int) =
  ## rich padding.py:61-74 — `Padding.unpack(pad: "PaddingDimensions") ->
  ## Tuple[int, int, int, int]` (`@staticmethod` padding.py:60): unpack CSS-style
  ## padding to `(top, right, bottom, left)` (padding.py:63-74). Modelled as a
  ## bare proc (a staticmethod — no `self`/`cls`); `pdInt` → `(pad, pad, pad, pad)`
  ## (padding.py:64), `pdSingle` (the 1-tuple) → all-same (padding.py:65-67),
  ## `pdPair` → `(top, right, top, right)` (padding.py:68-70), `pdQuad` →
  ## `(top, right, bottom, left)` (padding.py:71-73); else `ValueError`
  ## (padding.py:74).
  case pad.kind
  of pdInt:
    result = (pad.intv, pad.intv, pad.intv, pad.intv)
  of pdSingle:
    let v = pad.singlev.v
    result = (v, v, v, v)
  of pdPair:
    let (top, right) = pad.pair
    result = (top, right, top, right)
  of pdQuad:
    result = pad.quad

proc repr*(self: Padding): string =
  ## rich padding.py:76-77 — `Padding.__repr__(self) -> str`:
  ## `f"Padding({self.renderable!r}, ({self.top},{self.right},{self.bottom},{self.left}))"`.
  ## Overloads `system.repr` on the `Padding` receiver.
  var rrepr: string
  case self.renderable.kind
  of rvString:
    rrepr = "'" & self.renderable.textStr & "'"
  of rvConsoleRenderable:
    rrepr = repr(self.renderable.consoleItem)
  of rvRichCast:
    rrepr = repr(self.renderable.castItem)
  result = "Padding(" & rrepr & ", (" & $self.top & "," & $self.right & "," &
    $self.bottom & "," & $self.left & "))"

method renderConsole*(self: Padding, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich padding.py:79-123 — `Padding.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: draw space around the
  ## renderable (top/right/bottom/left margins; blank lines for top/bottom,
  ## space pads for left/right, padding.py:82-122). richbase `ConsoleHandle`/
  ## `ConsoleOptions`; `RenderResult` from richbase; `Segment`/`initSegment`/
  ## `addSegment` from richbase (re-exported by `segment`).
  ##
  ## Faithful port of padding.py:79-123 via the `console_api` cycle-breaker
  ## leaf: `console.getStyle` (padding.py:83), `Measurement.get` (padding.py:90),
  ## `options.updateWidth`/`updateHeight` (padding.py:92,95-97) and
  ## `console.renderLines` (padding.py:99) are dispatched on `ConsoleHandle`
  ## WITHOUT `import console` — the `padding → console → terminal_theme →
  ## palette → table → padding` cycle is broken by `console_api`'s `{.base.}`
  ## methods. `Segment`/`line`/`addSegment` come from richbase (re-exported by
  ## `segment`); `StyleRef(style)` upcasts the resolved `Style` to the
  ## `Option[StyleRef]` a `Segment` holds. The wrapped renderable is rendered
  ## to padded lines (`renderLines`, `pad=True`) and surrounded by blank
  ## `" "*width + "\n"` lines (top/bottom) and `" "*left`/`" "*right` space
  ## pads (left/right), each content line terminated by `Segment.line()` ("\n")
  ## — matching rich's generator output exactly.
  result = @[]
  # style = console.get_style(self.style) (padding.py:83) — resolve the
  # `Union[str, Style]` field to a `Style` via the matching `StyleType` arm.
  let style: Style =
    case self.style.kind
    of svkStr: console.getStyle(self.style.strv)
    of svkStyle: console.getStyle(self.style.stv)
  let styleRef: Option[StyleRef] = some(StyleRef(style))
  # width (padding.py:85-91): the OUTER width including the left+right padding.
  let width: int =
    if self.expand:
      options.maxWidth
    else:
      let m = Measurement.get(console, options, self.renderable)
      min(m.maximum + self.left + self.right, options.maxWidth)
  # render_options (padding.py:92-97): inner width excludes the side padding;
  # a set height bound is reduced by the top+bottom padding.
  var renderOptions = options.updateWidth(width - self.left - self.right)
  if renderOptions.height.isSome:
    renderOptions =
      renderOptions.updateHeight(renderOptions.height.get - self.top - self.bottom)
  # lines = console.render_lines(self.renderable, render_options, style=style,
  # pad=True) (padding.py:99) — the inner renderable split into padded lines.
  let lines = console.renderLines(self.renderable, some(renderOptions),
                                  some(style), pad = true, newLines = false)
  # left/right segment(s) (padding.py:101-105): `left` is one pad segment (or
  # None); `right` is always a list ending in `Segment.line()` ("\n").
  let leftSeg: Option[Segment] =
    if self.left > 0:
      some(Segment(text: repeat(" ", self.left), style: styleRef))
    else:
      none(Segment)
  let rightSegs: seq[Segment] =
    if self.right > 0:
      @[Segment(text: repeat(" ", self.right), style: styleRef), line()]
    else:
      @[line()]
  # blank_line (padding.py:107-111,120-122): rich yields a single
  # `_Segment(f'{" " * width}\n', style)` segment; the Console render pipeline
  # splits the trailing `\n` OUT of the styled segment (console.py `_render_buffer`
  # → `Style.render` over the pre-`\n` text, then a bare line break), so the
  # emitted bytes are `\x1b[..m{" "*width}\x1b[0m\n` (style-close BEFORE `\n`).
  # The Nim `renderToAnsi` does NOT split `\n` from a styled segment's text (it
  # wraps the whole `text` including `\n` in `Style.render`), so the blank line
  # is emitted as TWO segments — styled spaces + a bare `line()` — which is
  # byte-identical to rich's post-split output (verified: a single
  # `Segment(spaces\n, style)` and `[Segment(spaces, style), Segment.line()]`
  # render identically through rich's pipeline). `blankSpacesSeg` is lazily
  # built on first use (top or bottom) and reused for the other side, mirroring
  # Python's `blank_line or [...]`.
  var blankSpacesSeg: Option[Segment] = none(Segment)
  if self.top > 0:
    blankSpacesSeg = some(Segment(text: repeat(" ", width), style: styleRef))
    for _ in 0 ..< self.top:
      result.addSegment(blankSpacesSeg.get)
      result.addSegment(line())
  # content lines (padding.py:113-118): each is `left? + line + right`.
  if leftSeg.isSome:
    let lseg = leftSeg.get
    for contentLine in lines:
      result.addSegment(lseg)
      for seg in contentLine:
        result.addSegment(seg)
      for seg in rightSegs:
        result.addSegment(seg)
  else:
    for contentLine in lines:
      for seg in contentLine:
        result.addSegment(seg)
      for seg in rightSegs:
        result.addSegment(seg)
  # bottom blank lines (padding.py:120-122): reuse `blankSpacesSeg`, building it
  # here if only the bottom margin is set (Python's `blank_line or [...]`).
  if self.bottom > 0:
    if blankSpacesSeg.isNone:
      blankSpacesSeg = some(Segment(text: repeat(" ", width), style: styleRef))
    for _ in 0 ..< self.bottom:
      result.addSegment(blankSpacesSeg.get)
      result.addSegment(line())

proc richMeasure*(self: Padding, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich padding.py:125-135 — `Padding.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: measure the renderable plus the
  ## left/right padding (`extra_width = self.left + self.right`, padding.py:129),
  ## clamped to `max_width` (padding.py:131,134). The richbase `ConsoleHandle`/
  ## `ConsoleOptions` placeholders; `Measurement` from `measure.nim`. port
  ## stub.
  let max_width = options.maxWidth
  let extra_width = self.left + self.right
  if max_width - extra_width < 1:
    result = Measurement(minimum: max_width, maximum: max_width)
  else:
    var measure_min, measure_max: int
    case self.renderable.kind
    of rvString:
      let m = Measurement.get(console, options, self.renderable.textStr)
      measure_min = m.minimum
      measure_max = m.maximum
    of rvConsoleRenderable, rvRichCast:
      # DEFERRED(api_types/richbase, later batch): a bare `RenderableBase` does
      # not satisfy the `RenderableType` concept, so `Measurement.get` cannot be
      # called on the renderable arms; mirror `measure.nim`'s no-
      # `__rich_measure__` fallback (`Measurement(0, max_width)`, measure.py:108).
      measure_min = 0
      measure_max = max_width
    var measurement = Measurement(minimum: measure_min + extra_width,
                                  maximum: measure_max + extra_width)
    result = measurement.withMaximum(max_width)
