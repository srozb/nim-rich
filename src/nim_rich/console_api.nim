## console_api.nim — Console dispatch interface (breaks the console↔table cycle).
##
## `Table`/`Panel` need `Console` methods (`getStyle`/`renderLines`/`render`/
## `measure`) but cannot `import console` — the import cycle
## `table → console → terminal_theme → palette → table` (Nim 2.2.10 rejects it).
## This module declares those methods as `{.base.}` virtual dispatch on
## `ConsoleHandle` (richbase), so table/panel call `console.getStyle(...)` via
## dynamic dispatch WITHOUT importing console.nim. The real `Console`
## (console.nim, `ref object of ConsoleHandle`) overrides them; a minimal test
## console (e.g. golden_nim's `TestConsole`) can override them too.
##
## `renderStrValue` wraps `Console.render_str` (rich console.py:1409) as a
## `RenderableValue`-returning dispatch so `Table.render_annotation`'s string
## arm (table.py:501 — `console.render_str(text, style=style, highlight=False)`)
## can build a `Text` with Rich-equivalent markup/emoji/theme-style
## resolution through the real `Console` WITHOUT importing `console.nim` (the
## cycle-breaker). It returns `RenderableValue` (not `Text`) precisely because
## `console_api` must stay a leaf: a `Text` return would force `import text`, and
## `text` imports `console_api`, closing a cycle. The real `Console` override
## delegates to the existing `renderStr` proc and wraps the `Text` as
## `rvConsoleRenderable`; the base returns a bare `rvString` (so a placeholder
## handle passes the string to `render`'s rvString arm, which itself calls
## `render_str`).
##
## No cycle: this module imports only richbase + style/segment/measure/
## api_types — none of which import terminal_theme/palette/table/console/text
## (verified CLEAN), so it is a leaf reachable from table/panel/text.
##
## Faithfulness: the names mirror console.nim (`get_style`→`getStyle`,
## `render_lines`→`renderLines`, `render_str`→`renderStrValue`). The
## signatures match console.nim's procs (same params + defaults), so a
## `Console` override is a drop-in `method` version of the existing `proc`.
## NB: `Option[system.bool]` defaults are used for the flag-heavy
## `renderStrValue` (verified to compile under Nim 2.2.10 — the former
## `none(bool)` ≥3rd-default quirk no longer reproduces); `system.bool` keeps
## the symbol unambiguous.

import richbase          # ConsoleHandle, ConsoleOptions, RenderResult
import style             # Style, StyleType, StyleOpt, initStyle
import segment           # Segment
import measure           # Measurement
import api_types         # RenderableValue
import std/options

# ── base dispatch — a ConsoleHandle without an override renders/measures as
#    empty (matches richbase's `renderConsole` base policy: degrade to empty
#    rather than raise, so a nil/placeholder handle is safe for empty cases).

method getStyle*(self: ConsoleHandle, name: StyleType,
                 default: StyleOpt = default(StyleOpt)): Style {.base.} =
  ## Base — resolve a style name/string to a `Style`. Override in `Console`.
  ## Default: the null style (no attributes), matching `Style()`/`NULL_STYLE`.
  result = initStyle()

method renderLines*(self: ConsoleHandle, renderable: RenderableValue,
                    options: Option[ConsoleOptions] = none(ConsoleOptions),
                    style: Option[Style] = none(Style), pad: bool = true,
                    newLines: bool = false): seq[seq[Segment]] {.base.} =
  ## Base — render a renderable to lines of `Segment`s. Override in `Console`.
  ## Default: empty (no lines).
  result = @[]

method render*(self: ConsoleHandle, renderable: RenderableValue,
               options: Option[ConsoleOptions] = none(ConsoleOptions)):
    RenderResult {.base.} =
  ## Base — render a renderable to a `RenderResult` (the core render pipeline).
  ## Override in `Console`. Default: empty result.
  result = @[]

method measure*(self: ConsoleHandle, renderable: RenderableValue,
                options: Option[ConsoleOptions] = none(ConsoleOptions)):
    Measurement {.base.} =
  ## Base — measure a renderable. Override in `Console`. Default: 0×0
  ## (matches measure.nim's no-`__rich_measure__` fallback).
  result = Measurement(minimum: 0, maximum: 0)

method getSafeBox*(self: ConsoleHandle): bool {.base.} =
  ## Base — resolve the Console's `safe_box` preference (rich console.py:721,
  ## `self.safe_box = safe_box`; default `True`). Consumed by `Table._render`
  ## (table.py:769) via `pick_bool(self.safe_box, console.safe_box)` so an
  ## explicit Table `safe_box` takes precedence and otherwise the real Console
  ## preference decides box substitution. Default `true` matches
  ## `Console.__init__`'s `safe_box: bool = True`. Override in `Console` to
  ## return the real `self.safeBox`.
  result = true

method getTabSize*(self: ConsoleHandle): int {.base.} =
  ## Base — resolve the Console's `tab_size` (rich console.py:633,
  ## `self.tab_size = tab_size`; default `8`). Consumed by
  ## `Text.__rich_console__` (text.py:692 —
  ## `console.tab_size if self.tab_size is None else self.tab_size`) so an
  ## unset `Text.tab_size` inherits the real Console tab size while an explicit
  ## Text value wins. Default `8` matches `Console.__init__`'s
  ## `tab_size: int = 8` (console.py:637). Override in `Console` to return the
  ## real `self.tabSize`.
  result = 8

method renderStrValue*(self: ConsoleHandle, text: string,
    style: StyleOpt = default(StyleOpt),
    emoji: Option[system.bool] = none(system.bool),
    markup: Option[system.bool] = none(system.bool),
    highlight: Option[system.bool] = none(system.bool)): RenderableValue {.base.} =
  ## Base — convert a string to a renderable `Text` value (rich console.py:1409
  ## `Console.render_str`), wrapped as a `RenderableValue` for the `console_api`
  ## `render` dispatch. Consumed by `Table.render_annotation`'s string arm
  ## (table.py:501 — `console.render_str(text, style=style, highlight=False)`)
  ## so a title/caption string receives Rich-equivalent markup, emoji and
  ## theme-style resolution through the real `Console`. The `emoji`/`markup`/
  ## `highlight` flags mirror `render_str`'s `Optional[bool]` params (`None` ⇒
  ## Console default). Default: a bare `rvString` (a placeholder/nil handle
  ## passes the string through to `render`'s rvString arm, which itself calls
  ## `render_str`). Override in `Console` to run the genuine `render_str`.
  result = RenderableValue(kind: rvString, textStr: text)
