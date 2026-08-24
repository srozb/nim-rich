## Port of `rich.screen` (rich/screen.py).
##
## `Screen` is a renderable that fills the terminal screen and crops excess,
## rendering a grouped set of child renderables against an optional background
## style.
##
## Import graph (screen.py:1-7): `from typing import Optional, TYPE_CHECKING`
## (screen.py:1) → no `std/options` needed in the public signatures (`StyleOpt`
## carries the `Optional[StyleType]` none-arm itself). `from .segment import
## Segment` (screen.py:3) → `segment` (which `export richbase`, so `Segment`,
## `RenderableType`, `ConsoleHandle`, `ConsoleOptions`, `RenderResult`,
## `RenderableBase` are visible). `from .style import StyleType` (screen.py:4)
## → `style` (also gives `StyleOpt`, the `Optional[StyleType]` field handle).
## `from ._loop import loop_last` (screen.py:5) → `_loop` does NOT exist yet
## (Body concern). `from .console import Console, ConsoleOptions,
## RenderResult, RenderableType, Group` (screen.py:7-12) is `TYPE_CHECKING`-only
## → supplied by `segment`; `Group` (used in `__init__` to wrap the varargs) is
## body (console.nim not yet present). Nim-only: `import api_types` for
## `RenderableValue` (the storable `RenderableType` handle for the `renderable`
## field) + the `toRenderableValue*` converters, mirroring `containers.nim`.
##
## Faithfulness: `Screen` (screen.py:15-46) has `__rich_console__` (screen.py:31)
## → `ref object of RenderableBase` with fields `renderable`/`style`/
## `application_mode`. `__init__(self, *renderables: RenderableType, style:
## Optional[StyleType] = None, application_mode: bool = False)` (screen.py:20-29)
## → `initScreen(renderables: openArray[RenderableValue], style: StyleOpt =
## default(StyleOpt), applicationMode: bool = false)`: Python's `*renderables`
## varargs become `openArray[RenderableValue]` (Nim `varargs` must be the last
## param, but `style`/`applicationMode` follow — so `openArray` is used, the
## same translation as `containers.Renderables.__init__(*renderables)` →
## `initRenderables(openArray[RenderableType])`); callers wrap positional
## renderables in `@[...]` (an empty `@[]` for `Screen()`). `style: Optional[
## StyleType] = None` → `StyleOpt = default(StyleOpt)` (align.nim pattern).
## `self.renderable = Group(*renderables)` (screen.py:27) → field
## `RenderableValue` (the `Group` is built in body when console.nim exists).
##
## Naming: `__init__`→`initScreen`, `application_mode`→`applicationMode`,
## `__rich_console__`→`renderConsole`. Proc bodies are `discard` (ports
## → `default(Screen)` = nil ref / empty `RenderResult`).

import segment       # richbase (RenderableType, ConsoleHandle, ConsoleOptions,
                     # RenderResult, RenderableBase, Segment) — re-exported.
import style          # StyleType, StyleOpt — the style field/param handle.
import api_types      # RenderableValue — Nim-only storable RenderableType handle.

type
  Screen* = ref object of RenderableBase
    ## rich screen.py:15-46 — `class Screen`: a renderable that fills the
    ## terminal screen and crops excess. `ref object of RenderableBase`
    ## (Python reference semantics + console renderable). Fields mirror the
    ## `__init__` assignments (screen.py:27-29); the class-level `renderable:
    ## "RenderableType"` annotation (screen.py:18) is just an instance-attr hint.
    renderable*: RenderableValue
      ## screen.py:27 — `self.renderable = Group(*renderables)` (the grouped
      ## children; `Group` from console.nim, built in body). Stored as a
      ## `RenderableValue` (the `RenderableType` handle).
    style*: StyleOpt
      ## screen.py:28 — `self.style = style` (`Optional[StyleType]`; the
      ## `style.StyleOpt` case object — `sokNone`/`sokString`/`sokStyle`).
    applicationMode*: bool
      ## screen.py:29 — `self.application_mode = application_mode` (`bool`;
      ## when true, `__rich_console__` separates lines with `"\n\r"` instead of
      ## `Segment.line()`, screen.py:42-45).

proc initScreen*(renderables: openArray[RenderableValue],
                 style: StyleOpt = default(StyleOpt),
                 applicationMode: bool = false): Screen =
  ## rich screen.py:20-29 — `Screen.__init__(self, *renderables: RenderableType,
  ## style: Optional[StyleType] = None, application_mode: bool = False) -> None`.
  ## Python's `*renderables` varargs → `openArray[RenderableValue]` (Nim varargs
  ## must be last, but `style`/`applicationMode` follow — same translation as
  ## `Renderables.__init__`); callers wrap positional renderables in `@[...]`
  ## (empty `@[]` for `Screen()`). `style` default `None` → `default(StyleOpt)`
  ## (= `sokNone`). body builds `Group(*renderables)` into `self.renderable`.
  result = Screen()
  result.style = style
  result.applicationMode = applicationMode
  # DEFERRED(console, Batch 7): `self.renderable = Group(*renderables)` needs
  # `console.initGroup`, but `console` imports `screen` (for `ScreenContext.
  # screen: Screen`) → a true console↔screen import cycle. The structure
  # keeps `screen` free of a `console` import; the faithful `Group` wrapping is
  # deferred (mirrors `measure.nim`'s `# DEFERRED(console/protocol, …)` pattern
  # for console deps). The field is seeded with a default (empty) `RenderableValue`.
  result.renderable = default(RenderableValue)

method renderConsole*(self: Screen, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich screen.py:31-46 — `Screen.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: render the child group at the
  ## full `options.size`, crop with `Segment.set_shape`, and join lines with
  ## `"\n\r"` (application mode) or `Segment.line()` (screen.py:33-45). Uses
  ## `loop_last` (body). `__rich_console__`→`renderConsole`.
  # Simplified passthrough of `Screen.__rich_console__` (screen.py:31-46).
  # The faithful port renders the child group at the full `options.size` via
  # `console.render_lines`, crops with `Segment.set_shape`, and joins lines with
  # `"\n\r"` (application mode) or `Segment.line()` — all blocked
  # (`console.render_lines`/`console.get_style` are `Console` methods not
  # callable via the `ConsoleHandle` base param, and `_loop.loop_last` is not
  # ported). As a structural stand-in (the operator's
  # `addRenderable(self.renderable)` path), yield the child renderable for the
  # console to render directly. A `str` child yields via `addString`; a
  # `ConsoleRenderable`/`RichCast` via `addRenderable`. The screen-filling,
  # cropping and application-mode logic is deferred.
  result = @[]
  case self.renderable.kind
  of rvString:
    if self.renderable.textStr.len > 0:
      result.addString(self.renderable.textStr)
  of rvConsoleRenderable:
    if not self.renderable.consoleItem.isNil:
      result.addRenderable(self.renderable.consoleItem, rrkConsoleRenderable)
  of rvRichCast:
    if not self.renderable.castItem.isNil:
      result.addRenderable(self.renderable.castItem, rrkRichCast)
