## Nim port of `rich.measure` (rich/measure.py).
##
## `Measurement` stores the minimum and maximum widths (in characters)
## required to render an object, with combinators (`normalize`/`with_maximum`/
## `with_minimum`/`clamp`) and a `get` classmethod that measures a renderable.
##
## Sibling import: `richbase` only. Python `from .console import Console,
## ConsoleOptions, RenderableType` (measure.py:7-8, `TYPE_CHECKING`) is mapped
## to the richbase placeholder handles `ConsoleHandle`/`ConsoleOptions`/
## `RenderableType` — the established cycle-breaking pattern (console.nim is
## not imported here). Body-only deps NOT imported here (the modules exist;
## the body uses a safe fallback instead): `rich.errors`
## (`errors.NotRenderableError`, measure.py:4, raised in `get`), `rich.protocol`
## (`is_renderable`/`rich_cast`, measure.py:5), and `operator.itemgetter`
## (measure.py:1, used in `measure_renderables`); body may wire the real
## deps. Proc bodies are
## ported (span/normalize/withMaximum/withMinimum/clamp/get/measureRenderables
## implement measure.py; `get`/`measureRenderables` use a safe fallback for the
## deferred `console`/`protocol` deps).

import std/options

import richbase
import api_types

type
  Measurement* = object
    ## rich measure.py:11 — `Measurement(NamedTuple)`: stores the minimum and
    ## maximum widths (in characters) required to render an object.
    minimum*: int    ## rich measure.py:14 — minimum number of cells required to render.
    maximum*: int    ## rich measure.py:16 — maximum number of cells required to render.

proc span*(self: Measurement): int =
  ## rich measure.py:20 — `Measurement.span` (`@property` measure.py:19): the
  ## difference between maximum and minimum (`self.maximum - self.minimum`).
  result = self.maximum - self.minimum

proc normalize*(self: Measurement): Measurement =
  ## rich measure.py:24 — `Measurement.normalize(self) -> Measurement`: a
  ## measurement ensuring `minimum <= maximum` and `minimum >= 0`.
  let minimum = min(max(0, self.minimum), self.maximum)
  return Measurement(minimum: max(0, minimum), maximum: max(0, max(minimum, self.maximum)))

proc withMaximum*(self: Measurement, width: int): Measurement =
  ## rich measure.py:34 — `Measurement.with_maximum(self, width: int) ->
  ## Measurement`: a measurement where the widths are `<= width`.
  return Measurement(minimum: min(self.minimum, width), maximum: min(self.maximum, width))

proc withMinimum*(self: Measurement, width: int): Measurement =
  ## rich measure.py:46 — `Measurement.with_minimum(self, width: int) ->
  ## Measurement`: a measurement where the widths are `>= width`.
  let w = max(0, width)
  return Measurement(minimum: max(self.minimum, w), maximum: max(self.maximum, w))

proc clamp*(self: Measurement, minWidth: Option[int] = none(int),
           maxWidth: Option[int] = none(int)): Measurement =
  ## rich measure.py:59 — `Measurement.clamp(self, min_width=None, max_width=None)
  ## -> Measurement`: clamp within the specified range (`None` → no bound).
  var m = self
  if minWidth.isSome:
    m = m.withMinimum(minWidth.get)
  if maxWidth.isSome:
    m = m.withMaximum(maxWidth.get)
  return m

proc get*(T: typedesc[Measurement], console: ConsoleHandle, options: ConsoleOptions,
         renderable: RenderableValue): Measurement =
  ## rich measure.py:79 — `Measurement.get(cls, console: "Console", options:
  ## "ConsoleOptions", renderable: "RenderableType") -> "Measurement"`
  ## (`@classmethod` measure.py:78): get a measurement for a renderable.
  ## `console`/`options` use the richbase placeholder handles; `renderable` is
  ## the `RenderableType` concept (single concept param). Raises
  ## `errors.NotRenderableError` if not renderable (measure.py:115).
  if options.maxWidth < 1:
    return Measurement(minimum: 0, maximum: 0)
  # DEFERRED(console/protocol, later batch): `console.render_str` /
  # `rich_cast` / `is_renderable` / `__rich_measure__` (console.nim /
  # protocol.nim) are not available yet. Mirror the no-`__rich_measure__`
  # branch (measure.py:108-110) as a safe fallback: a renderable with no
  # `__rich_measure__` yields `Measurement(0, max_width)`.
  return Measurement(minimum: 0, maximum: options.maxWidth)

proc measureRenderables*(console: ConsoleHandle, options: ConsoleOptions,
                         renderables: openArray[RenderableValue]): Measurement =
  ## rich measure.py:125 — `measure_renderables(console, options, renderables:
  ## Sequence["RenderableType"]) -> "Measurement"`: a measurement that fits a
  ## number of renderables. `Sequence[RenderableType]` modelled as
  ## `openArray[RenderableType]`.
  if renderables.len == 0:
    return Measurement(minimum: 0, maximum: 0)
  # DEFERRED(console/protocol, later batch): `Measurement.get` delegates to
  # `rich_cast` / `is_renderable` / `__rich_measure__` (not available yet);
  # port the structure of measure.py:125-151 (max of minimums, max of
  # maximums, via `itemgetter(0)` / `itemgetter(1)`).
  var mn = 0
  var mx = 0
  for r in renderables:
    let m = Measurement.get(console, options, r)
    mn = max(mn, m.minimum)
    mx = max(mx, m.maximum)
  return Measurement(minimum: mn, maximum: mx)
