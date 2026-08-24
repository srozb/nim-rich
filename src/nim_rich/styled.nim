## Port of `rich.styled` (rich/styled.py).
##
## `Styled` (styled.py:11-41): wrap any renderable and apply a single style
## across its whole rendered output (`__rich_console__` re-renders the
## renderable then `Segment.apply_style`s it; styled.py:29-36). A thin
## `ConsoleRenderable` adapter.
##
## Import graph (rich/styled.py:1-5): runtime imports are `from typing import
## TYPE_CHECKING` (styled.py:1), `from .measure import Measurement`
## (styled.py:3), `from .segment import Segment` (styled.py:4), `from .style
## import StyleType` (styled.py:5); `from .console import Console,
## ConsoleOptions, RenderResult, RenderableType` @ styled.py:8 is
## `TYPE_CHECKING`-only.
##
## wiring (this file):
##   `import segment`    — re-exports `richbase` (`RenderResult`,
##                       `ConsoleOptions`, `ConsoleHandle`, `RenderableBase`,
##                       `RenderableType`, …) + `Segment` (the `apply_style`
##                       body, styled.py:34).
##   `import measure`     — `Measurement` (the `__rich_measure__` return,
##                       styled.py:40).
##   `import style`       — `StyleType` (`style: StyleType` param, styled.py:16;
##                       `StyleType = Union[str, Style]`, style.py:19).
##   `import text`        — `StyleValue` (the storable `Union[str, Style]` handle
##                       for the `Styled.style` field — `text.StyleValue` is the
##                       no-`None` case object, mirroring `rule.nim`'s
##                       `Rule.style`).
##   `import api_types`   — `RenderableValue` (the storable `RenderableType`
##                       handle for the `Styled.renderable` field, mirroring
##                       `align.nim`/`padding.nim`).
##
## `Styled` (styled.py:11, `class Styled`, no base shown → a `ConsoleRenderable`
## with `__rich_console__`/`__rich_measure__`) is `ref object of RenderableBase`
## (Python `Styled` has reference semantics; `JupyterMixin` is NOT a base here,
## unlike most rich widgets — `Styled` is a plain adapter, so `of
## RenderableBase`). `renderable: "RenderableType"` field (styled.py:22) →
## `api_types.RenderableValue` (the storable `Union[ConsoleRenderable,
## RichCast, str]` case object — a typeclass cannot be a field type, mirroring
## `align.nim`); the `renderable` PARAM keeps the faithful `RenderableType`
## typeclass (richbase). `style: StyleType` field (styled.py:23) →
## `text.StyleValue` (the no-`None` `Union[str, Style]` case object, like
## `rule.nim`'s `Rule.style`); the `style` PARAM keeps `StyleType` (typeclass,
## no default — `Styled.__init__` has none, styled.py:16). `__rich_console__`
## →`renderConsole`, `__rich_measure__`→`richMeasure`. Bodies mirror the Python source
## (`discard`).

import std/options  # `some`/`none`/`Option` for `Segment.style`/`applyStyle`.
import segment      # richbase re-export (RenderResult, ConsoleOptions,
                    # ConsoleHandle, RenderableBase, RenderableType, …) + Segment.
import measure      # Measurement.
import style        # StyleType (the style param type, Union[str, Style]).
import text         # StyleValue — the storable Union[str, Style] handle for the
                    # Styled.style field (mirrors rule.nim's Rule.style).
import api_types    # RenderableValue — the storable RenderableType handle for
                    # the Styled.renderable field (mirrors align.nim).

type
  Styled* = ref object of RenderableBase
    ## rich styled.py:11-41 — `class Styled`: "Apply a style to a renderable."
    ## `ref object of RenderableBase` (Python `Styled` has reference semantics;
    ## no `JupyterMixin` base — a plain adapter). Fields mirror the `__init__`
    ## assignments (styled.py:22-23).
    renderable*: RenderableValue  ## rich styled.py:22-22 — `self.renderable = renderable` (`RenderableType`; the `api_types.RenderableValue` case object).
    style*: StyleValue            ## rich styled.py:23-23 — `self.style = style` (`StyleType`/`Union[str, Style]`; the `text.StyleValue` case object).

proc initStyled*(renderable: RenderableValue, style: StyleType): Styled =
  ## rich styled.py:16-23 — `Styled.__init__(self, renderable: "RenderableType",
  ## style: "StyleType") -> None`: store `renderable`/`style` (styled.py:22-23).
  ## No defaults (Python `__init__` has none, styled.py:16). `renderable:
  ## RenderableType` → the richbase typeclass (a typeclass param compiles, as in
  ## `align.nim`); the field stores it as `RenderableValue` (body bridge).
  ## `style: StyleType` → the `style.StyleType` typeclass (no default); the
  ## field stores it as `StyleValue` (body bridge). (body
  ## `discard` ⇒ returns `nil`).
  result = Styled()
  result.renderable = renderable
  result.style = style

method renderConsole*(self: Styled, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich styled.py:25-36 — `Styled.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: render `self.renderable` then
  ## `Segment.apply_style(…, console.get_style(self.style))` (styled.py:30-35).
  ## The richbase `ConsoleHandle`/`ConsoleOptions` placeholders; `RenderResult`
  ## from richbase (via `segment`). The `Console` is the opaque `ConsoleHandle`
  ## placeholder, so `console.render`/`console.get_style` (styled.py:31,33) are
  ## unreachable; the dominant arms are special-cased and the rest delegated
  ## (see body).
  result = @[]
  # `console.get_style(self.style)` (styled.py:31) — resolve the `StyleValue`
  # locally (str → `Style.parse` / error → `Style.null()`, Style → `.copy()`),
  # the documented approximation of `console.get_style` (theme lookups miss).
  var style: Style
  case self.style.kind
  of svkStr:
    try: style = Style.parse(self.style.strv)
    except CatchableError: style = Style.null()
  of svkStyle:
    style = self.style.stv.copy()
  # `console.render(self.renderable, options)` (styled.py:33) — `Console` is
  # unavailable via `ConsoleHandle`, so the general recursive render is blocked.
  # Special-case the dominant arms where the segments are obtainable without
  # `console.render`, apply `Segment.apply_style` (styled.py:34) and emit them;
  # a generic `ConsoleRenderable`/`RichCast` arm is delegated via `addRenderable`
  # (the style is NOT applied there — documented limitation, wired when
  # `Console` is reachable).
  case self.renderable.kind
  of rvString:
    # `console.render(str)` → `[Segment(str)]`; `apply_style` → `[Segment(str, style)]`.
    result.addSegment(initSegment(self.renderable.textStr, some(StyleRef(style))))
  of rvConsoleRenderable:
    let rend = self.renderable.consoleItem
    if rend of Text:
      let t = Text(rend)
      var segs: seq[Segment] = @[]
      for item in t.renderConsole(console, options):
        if item.kind == rrkSegment:
          segs.add(item.segmentItem)
      for s in applyStyle(segs, some(style)):
        result.addSegment(s)
    else:
      result.addRenderable(rend, rrkConsoleRenderable)
  of rvRichCast:
    result.addRenderable(self.renderable.castItem, rrkRichCast)

proc richMeasure*(self: Styled, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich styled.py:38-41 — `Styled.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: `return Measurement.get(
  ## console, options, self.renderable)` (styled.py:40) — defer to the wrapped
  ## renderable's measure. The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `Measurement` from `measure.nim`. Body needs
  ## `measure.measureRenderables`/`Measurement.get` (styled.py:40).
  ## (body `discard` ⇒ returns `default(Measurement)`).
  # Faithful (styled.py:40): `Measurement.get(console, options, self.renderable)`.
  # The stored `RenderableValue`'s `rvString` arm unwraps to a `string` (a
  # `RenderableType`); the `rvConsoleRenderable`/`rvRichCast` arms are typed
  # `RenderableBase`, which does NOT satisfy the `ConsoleRenderable`/`RichCast`
  # concepts statically, so it can't be passed to `Measurement.get`. Mirror
  # `Measurement.get`'s own no-`__rich_measure__` fallback (`Measurement(0,
  # max_width)`) for those arms.
  case self.renderable.kind
  of rvString:
    result = Measurement.get(console, options, self.renderable.textStr)
  of rvConsoleRenderable, rvRichCast:
    result = Measurement(minimum: 0, maximum: options.maxWidth)
