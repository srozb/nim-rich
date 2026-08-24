## Port of `rich.status` (rich/status.py).
##
## `Status` displays a status indicator with a spinner animation, delegating
## the live display to a `Live` and the animation to a `Spinner` (status.py:23-
## 100). It is a thin context-manager wrapper: `with console.status("…") as s`.
##
## Import graph (rich/status.py:1-8): runtime sibling imports are `from types
## import TracebackType` (status.py:1), `from typing import Optional, Type`
## (status.py:2), `from .console import Console, RenderableType` (status.py:3),
## `from .jupyter import JupyterMixin` (status.py:4, the base), `from .live
## import Live` (status.py:5), `from .spinner import Spinner` (status.py:6),
## `from .style import StyleType` (status.py:7).
##
## wiring (this file):
##   `import std/options` — `Option[RenderableValue]`/`Option[string]`/
##                         `Option[float]`/exception `Option[…]` params.
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                         `RenderableType`, `RenderableBase`, …) + `Style`.
##   `import style`        — `StyleType` (the typeclass for the `spinnerStyle`
##                         param) + `StyleOpt` (the `Optional[StyleType]`
##                         handle for the `update` `spinnerStyle` param).
##   `import text`        — `StyleValue` (the `Union[str, Style]` field handle
##                         for `spinnerStyle`).
##   `import api_types`   — `RenderableValue` (the storable `RenderableType`
##                         handle for `status`/the `update` `status` param).
##   `import live`        — `Live` (the `_live` field, status.py:5,42-46).
##   `import spinner`     — `Spinner` (the `_spinner` field + `renderable`
##                         property return, status.py:6,42).
## `Console` (status.py:3) and `JupyterMixin` (status.py:4) are LATER-wave /
## placeholder types: `Console` → the `ConsoleHandle` placeholder (richbase,
## via `segment`) for the `console` property return; `JupyterMixin` is modelled
## via the `RenderableBase` storage base (`Status = ref object of
## RenderableBase`). `TracebackType`/`Type[BaseException]` (status.py:1-2,87-90)
## are exception params of `__exit__` → opaque `Option[RootRef]`/`Option[ref
## CatchableError]` placeholders (mirroring `live.nim`).
##
## `Status(JupyterMixin)` is `ref object of RenderableBase` (Python reference
## semantics). `status: RenderableType` (status.py:38) → field `RenderableValue`
## (param stays the `RenderableType` typeclass); `spinner_style: StyleType =
## "status.spinner"` (status.py:41) → field `StyleValue` (param the `StyleType`
## typeclass, default `"status.spinner"`); `speed: float = 1.0` (status.py:42);
## the private `_spinner: Spinner` (status.py:43) → `spinnerHandle` (module-
## private, mirrors the `_`-prefix); the private `_live: Live` (status.py:44-46)
## → `liveHandle` (module-private). Naming: `__init__`→`initStatus`,
## `renderable`→`renderable`, `console`→`console`, `update`→`update`,
## `start`/`stop`→`start`/`stop`, `__rich__`→`richCast`, `__enter__`/`__exit__`→
## `enter`/`exit` (the `live.nim` dunder mapping). The `spinner` `__init__`
## param (a spinner NAME string) is renamed `spinnerName` to avoid shadowing
## the imported `spinner` module. Proc bodies mirror the Python source.

import std/options

import segment      # richbase (ConsoleHandle, RenderableType, RenderableBase, …) + Style.
import style        # StyleType (typeclass param) + StyleOpt (Optional[StyleType] handle).
import text         # StyleValue (the Union[str, Style] field handle).
import api_types    # RenderableValue (the storable RenderableType handle).
import live         # Live (the _live field).
import spinner      # Spinner (the _spinner field + renderable property return).

type
  Status* = ref object of RenderableBase
    ## rich status.py:23-100 — `class Status(JupyterMixin)`: a status indicator
    ## with a spinner animation. `ref object of RenderableBase` (Python
    ## reference semantics; `JupyterMixin` modelled via `RenderableBase`).
    ## Fields mirror the `__init__` assignments (status.py:38-46).
    status*: RenderableValue
      ## rich status.py:38-38 — `self.status = status` (`RenderableType`; the
      ## `api_types.RenderableValue` case object).
    spinnerStyle*: StyleValue
      ## rich status.py:39-39 — `self.spinner_style = spinner_style`
      ## (`StyleType = Union[str, Style]`; the `text.StyleValue` field, default
      ## `"status.spinner"`).
    speed*: float
      ## rich status.py:40-40 — `self.speed = speed` (`float`; default `1.0`).
    spinnerHandle: Spinner
      ## rich status.py:41-41 — `self._spinner = Spinner(spinner, text=status,
      ## style=spinner_style, speed=speed)` (`Spinner`; module-private, mirrors
      ## the `_`-prefix).
    liveHandle: Live
      ## rich status.py:42-46 — `self._live = Live(self.renderable,
      ## console=console, refresh_per_second=refresh_per_second,
      ## transient=True)` (`Live`; module-private, mirrors the `_`-prefix).
      ## Renamed `_live`→`liveHandle` (the `live` name is the imported module).

proc styleValueToOpt(sv: StyleValue): StyleOpt =
  ## Helper: `StyleValue` → `StyleOpt` (parallel case-object arms; `StyleValue`
  ## has no `None` arm). Used by `update` to pass the stored `spinnerStyle` to
  ## the `StyleOpt`-typed `Spinner` params.
  case sv.kind
  of svkStr: result = StyleOpt(kind: sokStr, strv: sv.strv)
  of svkStyle: result = StyleOpt(kind: sokStyle, stv: sv.stv)

proc initStatus*(status: RenderableValue, console: ConsoleHandle = nil,
                 spinnerName: string = "dots",
                 spinnerStyle: StyleType = "status.spinner",
                 speed: float = 1.0, refreshPerSecond: float = 12.5): Status =
  ## rich status.py:30-46 — `Status.__init__(self, status: RenderableType, *,
  ## console: Optional[Console] = None, spinner: str = "dots", spinner_style:
  ## StyleType = "status.spinner", speed: float = 1.0, refresh_per_second:
  ## float = 12.5)`: store `status`/`spinner_style`/`speed`, build
  ## `self._spinner = Spinner(spinner, text=status, style=spinner_style,
  ## speed=speed)` and `self._live = Live(self.renderable, console=console,
  ## refresh_per_second=refresh_per_second, transient=True)` (status.py:38-46).
  ## Keyword-only after `status` (Python `*`, status.py:31). `status:
  ## RenderableType` keeps the faithful typeclass (richbase), stored as
  ## `RenderableValue`; `console: Optional[Console] = None` → `ConsoleHandle =
  ## nil`; `spinner: str = "dots"` → `spinnerName` (renamed to avoid shadowing
  ## the `spinner` module); `spinner_style: StyleType = "status.spinner"` →
  ## typeclass param, stored as `StyleValue`; `speed: float = 1.0`;
  ## `refresh_per_second: float = 12.5`.
  result = Status()
  result.status = status
  result.spinnerStyle = spinnerStyle
  result.speed = speed
  result.spinnerHandle = initSpinner(spinnerName, text = status,
                                      style = spinnerStyle, speed = speed)
  # `Live(self.renderable, console=console, refresh_per_second=…, transient=True)`
  # (status.py:44-46). `self.renderable` is the just-built spinner; wrap it as a
  # `RenderableValue` for `initLive`'s `Option[RenderableValue]` param. Use
  # `result.spinnerHandle` directly (== `result.renderable`, which just returns
  # `self.spinnerHandle`) — calling `result.renderable` here would resolve to
  # the imported `live.renderable(self: Live)` overload (name collision with this
  # module's `renderable(self: Status)`), so the spinner handle is used directly.
  var rv: RenderableValue = result.spinnerHandle
  result.liveHandle = initLive(renderable = some(rv), console = console,
                               refreshPerSecond = refreshPerSecond,
                               transient = true)

proc renderable*(self: Status): Spinner =
  ## rich status.py:48-50 — `Status.renderable` property (`@property`
  ## status.py:48): `return self._spinner` (status.py:50). Modelled as a no-arg
  ## proc (property getter); returns the concrete `Spinner` (from
  ## `spinner.nim`).
  result = self.spinnerHandle

proc console*(self: Status): ConsoleHandle =
  ## rich status.py:53-57 — `Status.console` property (`@property`
  ## status.py:53): `return self._live.console` (status.py:56). Modelled as a
  ## no-arg proc (property getter); returns the `ConsoleHandle` placeholder
  ## (richbase, for `Console`).
  result = self.liveHandle.console

proc update*(self: Status, status: Option[RenderableValue] = none(RenderableValue),
             spinnerName: Option[string] = none(string),
             spinnerStyle: StyleOpt = default(StyleOpt),
             speed: Option[float] = none(float)) =
  ## rich status.py:59-81 — `Status.update(self, status: Optional[
  ## RenderableType] = None, *, spinner: Optional[str] = None, spinner_style:
  ## Optional[StyleType] = None, speed: Optional[float] = None) -> None`: update
  ## the non-`None` fields and rebuild `_spinner` if `spinner` changed (else
  ## `_spinner.update(...)`), refreshing the live (status.py:66-80). Keyword-only
  ## after `status` (Python `*`, status.py:60). `status: Optional[RenderableType]
  ## = None` → `Option[RenderableValue]` (default `none(RenderableValue)`);
  ## `spinner: Optional[str] = None` → `spinnerName: Option[string]` (renamed,
  ## default `none(string)`); `spinner_style: Optional[StyleType] = None` →
  ## `StyleOpt` (default `sokNone` — `StyleOpt` already carries the `None` arm);
  ## `speed: Optional[float] = None` → `Option[float]` (default `none(float)`).
  if status.isSome:
    self.status = status.get
  if spinnerStyle.kind != sokNone:
    case spinnerStyle.kind
    of sokStr:
      self.spinnerStyle = StyleValue(kind: svkStr, strv: spinnerStyle.strv)
    of sokStyle:
      self.spinnerStyle = StyleValue(kind: svkStyle, stv: spinnerStyle.stv)
    else:
      discard
  if speed.isSome:
    self.speed = speed.get
  let styleOpt = styleValueToOpt(self.spinnerStyle)
  # `text=self.status` (status.py:74,80): the stored `status` is a
  # `RenderableValue`; only the `rvString` arm unwraps to a `RenderableType`
  # (`string`). The renderable arms are typed `RenderableBase` (don't satisfy
  # the `ConsoleRenderable`/`RichCast` concepts statically) and can't be passed
  # to the `Spinner` `text: RenderableType` param — collapse to the string arm
  # (empty for a renderable status; a known limitation until the unwrap is
  # available).
  let statusText = if self.status.kind == rvString: self.status.textStr else: ""
  if spinnerName.isSome:
    self.spinnerHandle = initSpinner(spinnerName.get, text = statusText,
                                        style = styleOpt, speed = self.speed)
    self.liveHandle.update(self.renderable, refresh = true)
  else:
    self.spinnerHandle.update(text = statusText, style = styleOpt,
                              speed = some(self.speed))

proc start*(self: Status) =
  ## rich status.py:83-85 — `Status.start(self) -> None`:
  ## `self._live.start()` (status.py:84).
  self.liveHandle.start()

proc stop*(self: Status) =
  ## rich status.py:87-89 — `Status.stop(self) -> None`:
  ## `self._live.stop()` (status.py:88).
  self.liveHandle.stop()

proc richCast*(self: Status): RenderableType =
  ## rich status.py:91-92 — `Status.__rich__(self) -> RenderableType`:
  ## `return self.renderable` (status.py:92). Dunder mapping `__rich__`→
  ## `richCast` (the richbase `RichCast` bridge); returns the faithful
  ## `RenderableType` typeclass (richbase).
  result = self.renderable

proc enter*(self: Status): Status =
  ## rich status.py:94-96 — `Status.__enter__(self) -> "Status"`:
  ## `self.start(); return self` (status.py:95-96). Dunder mapping
  ## `__enter__`→`enter`; returns the `Status` (Python `Self`).
  self.start()
  result = self

proc exit*(self: Status, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich status.py:98-100 — `Status.__exit__(self, exc_type: Optional[Type[
  ## BaseException]], exc_val: Optional[BaseException], exc_tb: Optional[
  ## TracebackType]) -> None`: `self.stop()` (status.py:99). Dunder mapping
  ## `__exit__`→`exit` (mirroring `live.nim`). The three exception params:
  ## `exc_type` → `Option[RootRef]` (opaque class placeholder); `exc_val` →
  ## `Option[ref CatchableError]`; `exc_tb` → `Option[RootRef]` (opaque
  ## traceback placeholder).
  self.stop()
