## Nim port of `rich.bar` (rich/bar.py).
##
## `Bar` renders a solid block bar at a fractional position (bar.py:17-93);
## the three module constants `BEGIN_BLOCK_ELEMENTS`/`END_BLOCK_ELEMENTS`/
## `FULL_BLOCK` (bar.py:12-14) hold the 1/8th block glyphs.
##
## Import graph (rich/bar.py:1-8): runtime sibling imports are
## `from .color import Color` (bar.py:3), `from .console import Console,
## ConsoleOptions, RenderResult` (bar.py:4), `from .jupyter import JupyterMixin`
## (bar.py:5, the base), `from .measure import Measurement` (bar.py:6), `from
## .segment import Segment` (bar.py:7), `from .style import Style` (bar.py:8);
## `from typing import Optional, Union` (bar.py:1).
##
## Operator note (dependency check): the operator flagged a possible
## dependency on `progress`. Direct inspection of
## `rich/bar.py` (bar.py:1-8) shows `Bar` imports `color`/`console`/`jupyter`/
## `measure`/`segment`/`style` ONLY — it does **not** import `progress` (nor
## `progress_bar`). Conversely no rich module does `from .bar import Bar`
## (`rich.progress` uses the separate `ProgressBar` class from
## `progress_bar.py`, progress.py:48, not `bar.Bar`). `bar.nim` therefore
## needs **no** `progress` import; it is a clean leaf-ish module. This
## directly fulfils the contract's "check `rich/bar.py` and inventory" step.
##
## wiring (this file):
##   `import color`   — `Color` (bar.py:3, the `Union[Color, str]` color arms).
##   `import segment` — re-exports `richbase` (`ConsoleOptions`, `ConsoleHandle`,
##                     `RenderResult`, `RenderableBase`, `RenderableType`, …) +
##                     `Segment` (bar.py:7) + `Style` (bar.py:8, re-exported).
##   `import measure` — `Measurement` (bar.py:6, the `__rich_measure__` return).
## `jupyter` (`JupyterMixin`, bar.py:5) is the base — modelled via
## `RenderableBase` (as `align.nim`/`rule.nim` do; `jupyter.nim` is not imported
## here). `console` types are `TYPE_CHECKING`-only — supplied via richbase
## placeholders (through `segment`).
##
## `Bar(JupyterMixin)` is `ref object of RenderableBase` (Python reference
## semantics). `size`/`begin`/`end` are `float` (bar.py:39-41); `begin`/`end` are
## clamped in the body (`max(begin, 0)`/`min(end, size)`, bar.py:40-41). `width:
## Optional[int] = None` (bar.py:35, keyword-only after `*`) → `Option[int]`,
## default `none(int)`. `color`/`bgcolor: Union[Color, str] = "default"`
## (bar.py:36-37) → typeclass `Color or string` (a `str` or `Color` compiles in
## one signature; the int arm is rejected), default `"default"`; these feed
## `Style(color=color, bgcolor=bgcolor)` stored in the `style` field (bar.py:43).
## Naming: `__init__`→`initBar`, `__repr__`→`repr`, `__rich_console__`→
## `renderConsole`, `__rich_measure__`→`richMeasure`. The three constants are
## `const array[8, string]` (fixed-length, const-evaluable; the body indexes
## 0..7 — bar.py:75,79). Proc bodies are ported (initBar/repr/renderConsole/
## richMeasure implement bar.py:29-93).

import std/[options, math, strutils, unicode]

import color        # Color.
import segment      # richbase (ConsoleOptions, ConsoleHandle, RenderResult,
                    # RenderableBase, RenderableType, …) + Segment + Style.
import measure      # Measurement.
import style        # Style + initStyle (Style(color=…, bgcolor=…), bar.py:43).

const
  BEGIN_BLOCK_ELEMENTS* = ["█", "█", "█", "▐", "▐", "▐", "▕", "▕"]
    ## rich bar.py:12-12 — `BEGIN_BLOCK_ELEMENTS` (a `list[str]`): the 1/8th
    ## right-aligned block glyphs (8 elements). Modelled as a `const
    ## array[8, string]` (fixed-length, const-evaluable; the body indexes it
    ## 0..7, bar.py:75). Exact literal from bar.py:12.

  END_BLOCK_ELEMENTS* = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
    ## rich bar.py:13-13 — `END_BLOCK_ELEMENTS` (a `list[str]`): the 1/8th
    ## left-aligned block glyphs (8 elements). Modelled as a `const
    ## array[8, string]` (the body indexes it 0..7, bar.py:79). Exact literal
    ## from bar.py:13.

  FULL_BLOCK* = "█"
    ## rich bar.py:14-14 — `FULL_BLOCK` (a `str`): the full block glyph. Exact
    ## literal from bar.py:14.

type
  Bar* = ref object of RenderableBase
    ## rich bar.py:17-93 — `class Bar(JupyterMixin)`: renders a solid block bar.
    ## `ref object of RenderableBase` (Python reference semantics; `JupyterMixin`
    ## modelled via `RenderableBase` — see file header). Fields mirror the
    ## `__init__` assignments (bar.py:39-43); `begin`/`end` are clamped in the
    ## body (`max(begin, 0)`/`min(end, size)`, bar.py:40-41).
    size*: float       ## rich bar.py:39-39 — `self.size = size` (`float`).
    begin*: float      ## rich bar.py:40-40 — `self.begin = max(begin, 0)` (`float`; clamped to `>= 0` in the body).
    `end`*: float      ## rich bar.py:41-41 — `self.end = min(end, size)` (`float`; clamped to `<= size` in the body). Backtick-quoted (`end` is a Nim keyword).
    width*: Option[int] ## rich bar.py:42-42 — `self.width = width` (`Optional[int]`; `Option[int]`, default `none(int)`).
    style*: Style       ## rich bar.py:43-43 — `self.style = Style(color=color, bgcolor=bgcolor)` (`Style`).

proc initBar*(size: float, begin: float, `end`: float,
              width: Option[int] = none(int),
              color: Color or string = "default",
              bgcolor: Color or string = "default"): Bar =
  ## rich bar.py:29-43 — `Bar.__init__(self, size: float, begin: float, end:
  ## float, *, width: Optional[int] = None, color: Union[Color, str] =
  ## "default", bgcolor: Union[Color, str] = "default")`: store `size`, clamp
  ## `begin`/`end`, store `width`, build `style = Style(color=color,
  ## bgcolor=bgcolor)` (bar.py:39-43). Keyword-only after `end` (Python `*`,
  ## bar.py:34). `width: Optional[int] = None` → `Option[int]`, default
  ## `none(int)`; `color`/`bgcolor: Union[Color, str] = "default"` → typeclass
  ## `Color or string` (a `str` or `Color` compiles; an `int` is rejected —
  ## not in `Union[Color, str]`), default `"default"`.
  result = Bar()
  result.size = size
  result.begin = max(begin, 0.0)
  result.`end` = min(`end`, size)
  result.width = width
  result.style = initStyle(color = color, bgcolor = bgcolor)

proc repr*(self: Bar): string =
  ## rich bar.py:45-46 — `Bar.__repr__(self) -> str`:
  ## `f"Bar({self.size}, {self.begin}, {self.end})"`. Overloads `system.repr`
  ## on the `Bar` receiver.
  result = "Bar(" & $self.size & ", " & $self.begin & ", " & $self.`end` & ")"

method renderConsole*(self: Bar, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich bar.py:48-84 — `Bar.__rich_console__(self, console: Console,
  ## options: ConsoleOptions) -> RenderResult`: render the solid block bar —
  ## a blank line if `begin >= end`, else a `prefix`+`body`+`suffix` line of
  ## 1/8th block glyphs (bar.py:51-84). The richbase `ConsoleHandle`/
  ## `ConsoleOptions` placeholders; `RenderResult` from richbase. Body
  ## needs `Segment` (bar.py:57,83,84) + `BEGIN_BLOCK_ELEMENTS`/`FULL_BLOCK`/
  ## `END_BLOCK_ELEMENTS` (bar.py:75,77,79).
  # Faithful port of `Bar.__rich_console__` (bar.py:48-84). `self.style` is a
  # concrete `Style` resolved at construction (`Style(color=color,
  # bgcolor=bgcolor)`, bar.py:43), so no `console.get_style` is needed — the
  # 1/8th-block glyph math (bar.py:51-84) is ported verbatim. `width = min(self.width
  # or options.max_width, options.max_width)` (bar.py:53-56); a blank line if
  # `begin >= end` (bar.py:58-61), else `prefix`+`body[len(prefix):]`+`suffix` of
  # 1/8th block glyphs in `self.style` (bar.py:63-83), then `Segment.line()`.
  # `len(body)`/`len(prefix)` are rune counts (Python `len` counts code points),
  # so `runeLen`/`runeSubStr` are used for the slice — byte `len` would mis-split
  # the multi-byte box glyphs.
  result = @[]
  let width = min(if self.width.isSome: self.width.get else: options.maxWidth,
                  options.maxWidth)
  let segStyle = some(StyleRef(self.style))
  if self.begin >= self.`end`:
    result.addSegment(initSegment(repeat(" ", width), segStyle))
    result.addSegment(line())
    return
  let prefixCompleteEights = int(width.float * 8.0 * self.begin / self.size)
  let prefixBarCount = prefixCompleteEights div 8
  let prefixEightsCount = prefixCompleteEights mod 8
  let bodyCompleteEights = int(width.float * 8.0 * self.`end` / self.size)
  let bodyBarCount = bodyCompleteEights div 8
  let bodyEightsCount = bodyCompleteEights mod 8
  var prefix = repeat(" ", prefixBarCount)
  if prefixEightsCount > 0:
    prefix.add(BEGIN_BLOCK_ELEMENTS[prefixEightsCount])
  var body = repeat(FULL_BLOCK, bodyBarCount)
  if bodyEightsCount > 0:
    body.add(END_BLOCK_ELEMENTS[bodyEightsCount])
  # bar.py:79 — `suffix = " " * (width - len(body))`. Python `len(body)` counts
  # code points; `runeLen(body)` is the codepoint count (a full block is 1 rune
  # but 3 UTF-8 bytes, so byte `len` would miscount). `max(0, …)` mirrors
  # Python's graceful `" " * negative = ""` — `strutils.repeat` takes
  # `Natural` and would raise `RangeDefect` on a negative count; for valid
  # Bars `width - runeLen(body) ≥ 0` always holds (body is at most `width`
  # runes), so the guard is a no-op equivalent, never altering output.
  let suffix = repeat(" ", max(0, width - runeLen(body)))
  # bar.py:83 — `prefix + body[len(prefix):] + suffix`. `len(prefix)` is a
  # codepoint count; `runeSubStr(body, runeLen(prefix))` is the codepoint-safe
  # slice from rune index `runeLen(prefix)` to the end (returns `""` when
  # `runeLen(prefix) ≥ runeLen(body)`), exactly Python's `body[len(prefix):]`.
  let text = prefix & runeSubStr(body, runeLen(prefix)) & suffix
  result.addSegment(initSegment(text, segStyle))
  result.addSegment(line())

proc richMeasure*(self: Bar, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich bar.py:86-93 — `Bar.__rich_measure__(self, console: Console,
  ## options: ConsoleOptions) -> Measurement`:
  ## `Measurement(self.width, self.width) if self.width is not None else
  ## Measurement(4, options.max_width)` (bar.py:89-93). The richbase
  ## `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim`.
  if self.width.isSome:
    let w = self.width.get
    return Measurement(minimum: w, maximum: w)
  else:
    return Measurement(minimum: 4, maximum: options.maxWidth)
