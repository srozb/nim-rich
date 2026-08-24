## Port of `rich.constrain` (rich/constrain.py).
##
## `Constrain` wraps a renderable and caps its render width to a given number
## of characters (constrain.py:10-37). `rich.progress`/`rich.columns` consume
## it (columns.py:8).
##
## Import graph (rich/constrain.py:1-7): runtime sibling imports are
## `from .jupyter import JupyterMixin` (constrain.py:3, the base) and
## `from .measure import Measurement` (constrain.py:4, the `__rich_measure__`
## return); `Console`, `ConsoleOptions`, `RenderableType`, `RenderResult` come
## from `.console` (constrain.py:7) under `TYPE_CHECKING`.
##
## wiring (this file):
##   `import std/options` — `Option[int]` (the `Optional[int]` width
##                         param/field, constrain.py:18).
##   `import segment`      — re-exports `richbase` (`ConsoleOptions`,
##                         `ConsoleHandle`, `RenderResult`, `RenderableBase`,
##                         `RenderableType`, …) + `Style`.
##   `import measure`      — `Measurement` (constrain.py:4, the
##                         `__rich_measure__` return).
##   `import api_types`    — `RenderableValue` (the storable `RenderableType`
##                         handle, for the `renderable` field).
## `jupyter` (`JupyterMixin`, constrain.py:3) is the base — modelled via
## `RenderableBase` (as `align.nim`/`rule.nim` do; `jupyter.nim` is not yet
## written). `console` types are `TYPE_CHECKING`-only — supplied via richbase
## placeholders.
##
## `Constrain(JupyterMixin)` is `ref object of RenderableBase` (Python
## reference semantics). `renderable: "RenderableType"` (constrain.py:18 param
## / constrain.py:19 field) → `RenderableValue` field (api_types) +
## `RenderableType` typeclass param. `width: Optional[int] = 80` (constrain.py:18)
## → `Option[int]`, default `some(80)` (the int 80 wrapped to `Optional` — the
## Python default is the int `80`, not `None`; the body still tests
## `self.width is None`, constrain.py:23). Naming: `__init__`→`initConstrain`,
## `__rich_console__`→`renderConsole`, `__rich_measure__`→`richMeasure`. Proc
## bodies are ports (`discard`).

import std/options

import segment      # richbase (ConsoleOptions, ConsoleHandle, RenderResult,
                    # RenderableBase, RenderableType, …) + Style.
import measure      # Measurement.
import api_types    # RenderableValue.

type
  Constrain* = ref object of RenderableBase
    ## rich constrain.py:10-37 — `class Constrain(JupyterMixin)`: constrain the
    ## width of a renderable to a given number of characters. `ref object of
    ## RenderableBase` (Python reference semantics; `JupyterMixin` modelled via
    ## `RenderableBase` — see file header). Fields mirror the `__init__`
    ## assignments (constrain.py:19-20).
    renderable*: RenderableValue  ## rich constrain.py:19-19 — `self.renderable = renderable` (`RenderableType`; the `api_types.RenderableValue` case object).
    width*: Option[int]           ## rich constrain.py:20-20 — `self.width = width` (`Optional[int]`; `Option[int]`, default `some(80)`).

proc initConstrain*(renderable: RenderableValue, width: Option[int] = some(80)): Constrain =
  ## rich constrain.py:18-20 — `Constrain.__init__(self, renderable:
  ## "RenderableType", width: Optional[int] = 80) -> None`: store
  ## `renderable`/`width` (constrain.py:19-20). `renderable` keeps the faithful
  ## `RenderableType` typeclass (richbase); the field stores it as
  ## `RenderableValue` (body bridge). `width: Optional[int] = 80` →
  ## `Option[int]`, default `some(80)` (the Python default is the int `80`,
  ## wrapped to `Optional`; `none(int)` is the `None` variant).
  result = Constrain()
  result.renderable = renderable
  result.width = width

method renderConsole*(self: Constrain, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich constrain.py:22-29 — `Constrain.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> RenderResult`: if `width is
  ## None` yield the renderable, else render it at `min(width, options.max_width)`
  ## (constrain.py:25-29). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase.
  #
  # The `width is None` arm `yield self.renderable` (constrain.py:26) is fully
  ## console-free and is implemented here by dispatching the `RenderableValue`
  ## arm — a `string` → `addString`, a `ConsoleRenderable`/`RichCast` →
  ## `addRenderable`.
  #
  # DEFERRED (import cycle + Console-method blocker): the `else` arm (constrain.py:28-
  ## 29) `child_options = options.update_width(min(self.width, options.max_width));
  ## yield from console.render(self.renderable, child_options)` needs
  ## `Console.render`, a method on `Console` (not the `ConsoleHandle` this proc
  ## receives). `constrain` is imported by `console.nim` directly as a port
  ## renderConsole-dispatch import (console.nim:174), so `import console` here
  ## would close the cycle `constrain`→`console`→`constrain` and is a hard Nim
  ## error (the operator's `console.nim` header documents these dispatch
  ## imports are "cycle-free: none of these import console"). `Console.render`
  ## is itself still a stub returning the empty `RenderResult`. Same blocker as
  ## `panel.nim`/`padding.nim`/`align.nim`. Emit nothing for the width arm so the
  ## renderable still satisfies the `ConsoleRenderable` contract; wire once
  ## `Console.render` is wired and the `constrain`→`console` cycle is broken.
  result = @[]
  if self.width.isNone:
    case self.renderable.kind
    of rvString:
      result.addString(self.renderable.textStr)
    of rvConsoleRenderable:
      result.addRenderable(self.renderable.consoleItem, rrkConsoleRenderable)
    of rvRichCast:
      result.addRenderable(self.renderable.castItem, rrkRichCast)
  else:
    # DEFERRED — see note above (needs `Console.render`, blocked by the
    # `constrain`→`console` dispatch-import cycle). The faithful body would be:
    #   let c = Console(console)
    #   let childOptions = options.updateWidth(min(self.width.get, options.maxWidth))
    #   result = c.render(self.renderable, some(childOptions))
    discard

proc richMeasure*(self: Constrain, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich constrain.py:31-37 — `Constrain.__rich_measure__(self, console:
  ## "Console", options: "ConsoleOptions") -> Measurement`: if `width is not
  ## None` update options to that width, then `Measurement.get(console,
  ## options, self.renderable)` (constrain.py:34-37). The richbase
  ## `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim`.
  var opts = options
  if self.width.isSome:
    opts = options.updateWidth(self.width.get)
  # DEFERRED(api_types/measure, Batch N): the `RenderableValue`→`RenderableType`
  # bridge is not yet implemented — `Measurement.get` takes a `RenderableType`
  # but `self.renderable` is a storable `RenderableValue`. Mirror measure.nim's
  # `Measurement.get` no-`__rich_measure__` fallback (`Measurement(0, max_width)`,
  # measure.py:108-110) so the `options.update_width(self.width)` step is
  # faithfully ported (constrain.py:34) while the per-renderable measure awaits
  # the bridge.
  if opts.maxWidth < 1:
    return Measurement(minimum: 0, maximum: 0)
  return Measurement(minimum: 0, maximum: opts.maxWidth)
