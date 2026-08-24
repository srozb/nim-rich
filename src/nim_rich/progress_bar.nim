## Port of `rich.progress_bar` (rich/progress_bar.py).
##
## `ProgressBar` renders a (progress) bar — a solid block of `━` (or `-` in
## ascii) that fills as `completed` approaches `total`, with an optional pulse
## animation when `total` is `None` (progress_bar.py:24-180). Used by
## `rich.progress.BarColumn` (progress.py:646-686) — NOT to be confused with
## `rich.bar.Bar` (the simpler block bar); this is the richer pulsing variant.
##
## Import graph (rich/progress_bar.py:1-9): runtime sibling imports are
## `from .color import Color, blend_rgb` (progress_bar.py:2), `from
## .color_triplet import ColorTriplet` (progress_bar.py:3), `from .console
## import Console, ConsoleOptions, RenderResult` (progress_bar.py:4), `from
## .jupyter import JupyterMixin` (progress_bar.py:5, the base), `from .measure
## import Measurement` (progress_bar.py:6), `from .segment import Segment`
## (progress_bar.py:7), `from .style import Style, StyleType` (progress_bar.py:8).
##
## wiring (this file):
##   `import std/options`  — `Option[float]`/`Option[int]` (total/width/anim).
##   `import segment`       — re-exports `richbase` (`ConsoleHandle`,
##                          `ConsoleOptions`, `RenderResult`, `RenderableBase`,
##                          `RenderableType`, …) + `Segment` (progress_bar.py:7) +
##                          `Style` (progress_bar.py:8, re-exported by segment).
##   `import measure`       — `Measurement` (progress_bar.py:6, the
##                          `__rich_measure__` return).
##   `import style`         — `StyleType` (progress_bar.py:8; the typeclass for
##                          the `style`/`complete_style`/… params).
##   `import text`          — `StyleValue` (the case object for the `style`/
##                          `completeStyle`/… fields; `Union[str, Style]`).
## `color` (`Color`, `blend_rgb`, progress_bar.py:2) and `color_triplet`
## (`ColorTriplet`, progress_bar.py:3) are BODY-only deps (`_get_pulse_segments`
## blends colors, progress_bar.py:84-99) — deferred to body; not imported
##  (no signature references them). `jupyter` (`JupyterMixin`,
## progress_bar.py:5) is the base — modelled via `RenderableBase` (as
## `bar.nim`/`panel.nim` do; `jupyter.nim` is not yet written). `console` types
## are `TYPE_CHECKING`-only — supplied via richbase placeholders (through
## `segment`).
##
## `ProgressBar(JupyterMixin)` is `ref object of RenderableBase` (Python
## reference semantics). `total: Optional[float] = 100.0` (progress_bar.py:31)
## → `Option[float]`, default `some(100.0)` (a `None` total enables the pulse
## animation, progress_bar.py:113). `completed: float = 0`,
## `width: Optional[int] = None` (progress_bar.py:32-33), `pulse: bool =
## False` (progress_bar.py:34). `style`/`complete_style`/`finished_style`/
## `pulse_style: StyleType = "bar.back"/"bar.complete"/"bar.finished"/
## "bar.pulse"` (progress_bar.py:35-38) → typeclass `StyleType` params
## (default strings), stored as `StyleValue` fields (the `Union[str, Style]`
## handle from `text`). `animation_time: Optional[float] = None`
## (progress_bar.py:39) → `Option[float]`. The private `_pulse_segments:
## Optional[List[Segment]] = None` (progress_bar.py:42) → `Option[seq[Segment]]`
## (module-private, mirrors the `_`-prefix). Naming: `__init__`→
## `initProgressBar`, `__repr__`→`repr`, `percentage_completed`→
## `percentageCompleted`, `_get_pulse_segments`→`getPulseSegments` (private),
## `update`→`update`, `_render_pulse`→`renderPulse` (private),
## `__rich_console__`→`renderConsole`, `__rich_measure__`→`richMeasure`. The
## module const `PULSE_SIZE = 20` (progress_bar.py:17) is a `const int`. Proc
## bodies are ports (`discard`).

import std/[options, math, strutils]

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableBase, RenderableType, …) + Segment + Style.
import measure      # Measurement.
import style        # StyleType (the typeclass for the style* params).
import text         # StyleValue (the Union[str, Style] field handle).
import color        # Color (fromTriplet), blendRgb — the truecolor pulse
                    # gradient (progress_bar.py:84-99).
import color_triplet # ColorTriplet — the pulse blend base/fore colours.

const PULSE_SIZE* = 20
  ## rich progress_bar.py:17-17 — `PULSE_SIZE` (an `int`): number of
  ## characters before the pulse animation repeats (progress_bar.py:101).
  ## Exact literal from progress_bar.py:17.

type
  ProgressBar* = ref object of RenderableBase
    ## rich progress_bar.py:24-180 — `class ProgressBar(JupyterMixin)`: renders
    ## a (progress) bar with an optional pulse animation. `ref object of
    ## RenderableBase` (Python reference semantics; `JupyterMixin` modelled via
    ## `RenderableBase`). Fields mirror the `__init__` assignments
    ## (progress_bar.py:41-42).
    total*: Option[float]            ## rich progress_bar.py:41-41 — `self.total = total` (`Optional[float] = 100.0`; `Option[float]`, default `some(100.0)`, `none(float)` enables pulse).
    completed*: float                ## rich progress_bar.py:41-41 — `self.completed = completed` (`float`; default `0`).
    width*: Option[int]              ## rich progress_bar.py:41-41 — `self.width = width` (`Optional[int] = None`; `Option[int]`, default `none(int)`).
    pulse*: bool                     ## rich progress_bar.py:41-41 — `self.pulse = pulse` (`bool`; default `False`).
    style*: StyleValue               ## rich progress_bar.py:41-41 — `self.style = style` (`StyleType = Union[str, Style]`; the `text.StyleValue` field, default `"bar.back"`).
    completeStyle*: StyleValue       ## rich progress_bar.py:41-41 — `self.complete_style = complete_style` (`StyleType`; the `text.StyleValue` field, default `"bar.complete"`).
    finishedStyle*: StyleValue       ## rich progress_bar.py:41-41 — `self.finished_style = finished_style` (`StyleType`; the `text.StyleValue` field, default `"bar.finished"`).
    pulseStyle*: StyleValue          ## rich progress_bar.py:41-41 — `self.pulse_style = pulse_style` (`StyleType`; the `text.StyleValue` field, default `"bar.pulse"`).
    animationTime*: Option[float]    ## rich progress_bar.py:41-41 — `self.animation_time = animation_time` (`Optional[float] = None`; `Option[float]`, default `none(float)`).
    pulseSegments*: Option[seq[Segment]]
      ## rich progress_bar.py:42-42 — `self._pulse_segments: Optional[List[Segment]]
      ## = None` (module-private, mirrors the `_`-prefix; `Option[seq[Segment]]`,
      ## default `none(seq[Segment])`).

proc initProgressBar*(total: Option[float] = some(100.0), completed: float = 0.0,
                     width: Option[int] = none(int), pulse: bool = false,
                     style: StyleType = "bar.back",
                     completeStyle: StyleType = "bar.complete",
                     finishedStyle: StyleType = "bar.finished",
                     pulseStyle: StyleType = "bar.pulse",
                     animationTime: Option[float] = none(float)): ProgressBar =
  ## rich progress_bar.py:29-42 — `ProgressBar.__init__(self, total:
  ## Optional[float] = 100.0, completed: float = 0, width: Optional[int] =
  ## None, pulse: bool = False, style: StyleType = "bar.back",
  ## complete_style: StyleType = "bar.complete", finished_style: StyleType =
  ## "bar.finished", pulse_style: StyleType = "bar.pulse", animation_time:
  ## Optional[float] = None)`: store all ten fields (progress_bar.py:41-42).
  ## `total: Optional[float] = 100.0` → `Option[float]`, default `some(100.0)`
  ## (a `none(float)` total enables the pulse animation, progress_bar.py:113);
  ## `width: Optional[int] = None` → `Option[int]`; `style`/`complete_style`/
  ## `finished_style`/`pulse_style: StyleType = "…"` → typeclass `StyleType`
  ## params (default strings), stored as `StyleValue` fields;
  ## `animation_time: Optional[float] = None` → `Option[float]`.
  result = ProgressBar()
  result.total = total
  result.completed = completed
  result.width = width
  result.pulse = pulse
  result.style = style
  result.completeStyle = completeStyle
  result.finishedStyle = finishedStyle
  result.pulseStyle = pulseStyle
  result.animationTime = animationTime
  result.pulseSegments = none(seq[Segment])

proc repr*(self: ProgressBar): string =
  ## rich progress_bar.py:44-45 — `ProgressBar.__repr__(self) -> str`:
  ## `f"<Bar {self.completed!r} of {self.total!r}>"` (progress_bar.py:45).
  ## Overloads `system.repr` on the `ProgressBar` receiver.
  let totalRepr = if self.total.isSome: $self.total.get else: "None"
  result = "<Bar " & $self.completed & " of " & totalRepr & ">"

proc percentageCompleted*(self: ProgressBar): Option[float] =
  ## rich progress_bar.py:48-54 — `ProgressBar.percentage_completed` property
  ## (`@property` progress_bar.py:48): `None` if `total is None`, else
  ## `min(100, max(0.0, (self.completed / self.total) * 100.0))`
  ## (progress_bar.py:50-53). Modelled as a no-arg proc (property getter); the
  ## `None` arm → `none(float)`.
  if self.total.isNone:
    result = none(float)
  else:
    let completed = (self.completed / self.total.get) * 100.0
    result = some(min(100.0, max(0.0, completed)))

proc getPulseSegments*(self: ProgressBar, foreStyle: Style, backStyle: Style,
                       colorSystem: string, noColor: bool,
                       ascii: bool = false): seq[Segment] =
  ## rich progress_bar.py:57-99 — `ProgressBar._get_pulse_segments(self,
  ## fore_style: Style, back_style: Style, color_system: str, no_color: bool,
  ## ascii: bool = False) -> List[Segment]` (`@lru_cache(maxsize=16)`,
  ## progress_bar.py:56): build the `PULSE_SIZE`-segment pulse animation — a
  ## fixed `-`/`━` bar for monochrome/no-color terminals, else a cosine-blended
  ## truecolor gradient (`blend_rgb`, progress_bar.py:84-99). Module-public
  ## (the `_`-prefix is dropped; `@lru_cache` is deferred to body). Returns
  ## `seq[Segment]` (the `List[Segment]`). Faithful port of
  ## progress_bar.py:64-99 (the `PULSE_SIZE`-segment pulse animation).
  proc mkSeg(t: string; s: Style): Segment =
    Segment(text: t, style: some(StyleRef(s)), control: none(seq[ControlCode]))
  let bar = if ascii: "-" else: "━"
  if colorSystem notin ["standard", "eight_bit", "truecolor"] or noColor:
    for i in 0 ..< (PULSE_SIZE div 2):
      result.add(mkSeg(bar, foreStyle))
    let backChar = if noColor: " " else: bar
    for i in 0 ..< (PULSE_SIZE - (PULSE_SIZE div 2)):
      result.add(mkSeg(backChar, backStyle))
    return
  var foreColor: ColorTriplet = (red: 255, green: 0, blue: 255)
  if foreStyle.color.isSome:
    foreColor = foreStyle.color.get.getTruecolor()
  var backColor: ColorTriplet = (red: 0, green: 0, blue: 0)
  if backStyle.color.isSome:
    backColor = backStyle.color.get.getTruecolor()
  for index in 0 ..< PULSE_SIZE:
    let position = index.float / PULSE_SIZE.float
    let fade = 0.5 + cos(position * PI * 2.0) / 2.0
    let color = blendRgb(foreColor, backColor, crossFade = fade)
    result.add(mkSeg(bar, initStyle(color = Color.fromTriplet(color))))

proc update*(self: ProgressBar, completed: float, total: Option[float] = none(float)) =
  ## rich progress_bar.py:101-110 — `ProgressBar.update(self, completed: float,
  ## total: Optional[float] = None) -> None`: set `self.completed = completed`
  ## and `self.total = total if total is not None else self.total`
  ## (progress_bar.py:108-109). `total: Optional[float] = None` →
  ## `Option[float]`, default `none(float)`.
  self.completed = completed
  if total.isSome:
    self.total = total

proc renderPulse*(self: ProgressBar, console: ConsoleHandle, width: int,
                  ascii: bool = false): seq[Segment] =
  ## rich progress_bar.py:112-130 — `ProgressBar._render_pulse(self, console:
  ## Console, width: int, ascii: bool = False) -> Iterable[Segment]`: render
  ## the scrolling pulse animation — fetch the cached pulse segments, tile
  ## them across `width` and offset by `int(-current_time * 15)` (the
  ## `animation_time` overrides `monotonic()`, progress_bar.py:120-129). The
  ## richbase `ConsoleHandle` placeholder; the `Iterable[Segment]` return is
  ## materialised as `seq[Segment]` (a stub cannot yield). Module-public (the
  ## `_`-prefix is dropped).
  # Faithful intent (progress_bar.py:112-130): fetch the cached pulse segments,
  # tile across `width`, offset by `int(-current_time * 15)`. Blocked: needs
  # `console.get_style`/`color_system`/`no_color` (Console methods, not on the
  # opaque `ConsoleHandle`) + `std/times.monotonic`. Return empty as a stand-in.
  result = @[]

proc svToSegStyle(sv: StyleValue): Option[StyleRef] =
  ## [Nim-only helper] Best-effort `StyleValue` → `Option[StyleRef]` for
  ## `renderConsole`. `ProgressBar`'s `style`/`completeStyle`/`finishedStyle` are
  ## `StyleType` defaults (`"bar.back"`/`"bar.complete"`/`"bar.finished"`),
  ## theme names rich resolves via `console.get_style`; the opaque
  ## `ConsoleHandle` has no `get_style`, so a `str` style is resolved via
  ## `Style.parse` (themed names are unresolvable and fall back to `none`, the
  ## `text.getStyleLocal` pattern) and a `Style` is upcast (copied). Degraded
  ## for themed-name strings (null style → no color), correct for concrete
  ## `Style` values.
  case sv.kind
  of svkStr:
    if sv.strv.len == 0: result = none(StyleRef)
    else:
      try: result = some(StyleRef(Style.parse(sv.strv)))
      except CatchableError: result = none(StyleRef)
  of svkStyle:
    result = some(StyleRef(sv.stv.copy()))

method renderConsole*(self: ProgressBar, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich progress_bar.py:132-172 — `ProgressBar.__rich_console__(self,
  ## console: Console, options: ConsoleOptions) -> RenderResult`: render the
  ## bar — pulse if `should_pulse` (progress_bar.py:136-138), else a solid
  ## `━`/`-` bar with optional half-bar `╸`/`╺` and a remaining-space suffix
  ## (progress_bar.py:140-171). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase. Body needs `Segment`,
  ## `BEGIN/END/FULL` glyphs (from `bar`), `getPulseSegments`/`renderPulse`.
  result = @[]
  # Faithful port of `ProgressBar.__rich_console__` (progress_bar.py:132-172).
  # `width = min(self.width or options.max_width, options.max_width)`
  # (progress_bar.py:140); `ascii = options.legacy_windows or options.ascii_only`
  # (progress_bar.py:141); `should_pulse = self.pulse or self.total is None`
  # (progress_bar.py:142). The pulse arm (`_render_pulse`, progress_bar.py:136-138)
  # needs `console.get_style`/`color_system`/`no_color` + `monotonic()` — all
  # blocked — so it is DEFERRED (returns empty); the common solid-bar arm
  # (progress_bar.py:144-171) is ported. `console.get_style(self.style)` is
  # blocked, so the styles are best-effort-resolved via `svToSegStyle` (themed
  # names degrade to null). `console.no_color`/`console.color_system` (the
  # `if not console.no_color`/`color_system is not None` guards for the remaining
  # bars, progress_bar.py:156-164) are Console attrs unavailable via
  # `ConsoleHandle`; the color-terminal case (remaining bars rendered) is
  # assumed — a deviation for monochrome terminals, matching the operator's
  # `fill × completed + empty × remaining` intent.
  let width = min(if self.width.isSome: self.width.get else: options.maxWidth,
                  options.maxWidth)
  let ascii = options.legacyWindows or options.asciiOnly
  let shouldPulse = self.pulse or self.total.isNone
  if shouldPulse:
    # DEFERRED: `_render_pulse` needs console.get_style/color_system/no_color +
    # monotonic().
    return
  let completed: Option[float] =
    if self.total.isSome: some(min(self.total.get, max(0.0, self.completed)))
    else: none(float)
  let bar = if ascii: "-" else: "━"
  let halfBarRight = if ascii: " " else: "╸"
  let halfBarLeft = if ascii: " " else: "╺"
  let completeHalves =
    if self.total.isSome and self.total.get != 0.0 and completed.isSome:
      int(width.float * 2.0 * completed.get / self.total.get)
    else:
      width * 2
  let barCount = completeHalves div 2
  let halfBarCount = completeHalves mod 2
  let backStyle = svToSegStyle(self.style)
  let isFinished = self.total.isNone or (self.completed >= self.total.get)
  let completeStyle = svToSegStyle(
    if isFinished: self.finishedStyle else: self.completeStyle)
  if barCount > 0:
    result.addSegment(initSegment(repeat(bar, barCount), completeStyle))
  if halfBarCount > 0:
    result.addSegment(initSegment(repeat(halfBarRight, halfBarCount), completeStyle))
  # Remaining bars — color-terminal assumption (see note above).
  let remainingBars = width - barCount - halfBarCount
  if remainingBars > 0:
    var rb = remainingBars
    if halfBarCount == 0 and barCount > 0:
      result.addSegment(initSegment(halfBarLeft, backStyle))
      rb -= 1
    if rb > 0:
      result.addSegment(initSegment(repeat(bar, rb), backStyle))

proc richMeasure*(self: ProgressBar, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich progress_bar.py:174-179 — `ProgressBar.__rich_measure__(self,
  ## console: Console, options: ConsoleOptions) -> Measurement`:
  ## `Measurement(self.width, self.width) if self.width is not None else
  ## Measurement(4, options.max_width)` (progress_bar.py:177-179). The
  ## richbase `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim`.
  if self.width.isSome:
    let w = self.width.get
    result = Measurement(minimum: w, maximum: w)
  else:
    result = Measurement(minimum: 4, maximum: options.maxWidth)
