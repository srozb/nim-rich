## Port of `rich.spinner` (rich/spinner.py).
##
## `Spinner` is a frame-based animation that cycles through a named set of
## frames (`SPINNERS`) at a given `interval`/`speed`, optionally with a
## renderable to its right (spinner.py:23-132). Used by `rich.status.Status`
## (status.py:42) and `rich.progress.SpinnerColumn` (progress.py:566-614).
##
## Import graph (rich/spinner.py:1-15): runtime sibling imports are
## `from typing import TYPE_CHECKING, List, Optional, Union, cast`
## (spinner.py:1), `from .spinners_data import SPINNERS` (spinner.py:3), `from
## .measure import Measurement` (spinner.py:4), `from .table import Table`
## (spinner.py:5), `from .text import Text` (spinner.py:6). `TYPE_CHECKING`-only
## (spinner.py:8-10): `from .console import Console, ConsoleOptions,
## RenderableType, RenderResult` (spinner.py:9), `from .style import StyleType`
## (spinner.py:10).
##
## wiring (this file):
##   `import std/options` — `Option[float]` (start_time/speed param).
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                         `ConsoleOptions`, `RenderResult`, `RenderableType`, …)
##                         + `Style` (re-exported).
##   `import measure`      — `Measurement` (spinner.py:4; the
##                         `__rich_measure__` return).
##   `import style`        — `StyleOpt` (the `Optional[StyleType]` handle for
##                         the `style` field/param, spinner.py:40,61,127).
##   `import api_types`    — `RenderableValue` (the `RenderableType` field
##                         handle for `text`).
## `SPINNERS` (`spinners_data`, spinner.py:3) is a private `_*` helper not yet
## written — a non-empty `Table[string, SpinnerSpec]` placeholder stands in for
## it here (a [NON-NARROWING PROVISIONAL FORWARD HANDLE], replaced by `import
## spinners_data` once that helper exists). `Table` (spinner.py:5) and `Text`
## (spinner.py:6) are BODY-only deps (`render` builds a `Table.grid` /
## `Text.assemble`, spinner.py:96-114) — deferred to body; not imported in
## (no signature references them). `console`/`style.StyleType` are
## `TYPE_CHECKING`-only — supplied via richbase/`style` placeholders.
##
## `Spinner` (no rich base class — plain `class`) is `ref object of
## RenderableBase` (Nim-only storage base, matching how `live_render.nim`
## models baseless renderables). `name: str` (spinner.py:39) → `string`;
## `text: "RenderableType" = ""` (spinner.py:38) → field `RenderableValue`
## (param stays the `RenderableType` typeclass, default `""`); `frames:
## List[str]` (spinner.py:43) → `seq[string]`; `interval: float` (spinner.py:44)
## → `float`; `start_time: Optional[float] = None` (spinner.py:45) →
## `Option[float]`; `style: Optional["StyleType"] = None` (spinner.py:40) →
## field `StyleOpt` (param `StyleOpt = default(StyleOpt)` = `sokNone`);
## `speed: float = 1.0` (spinner.py:41); `frame_no_offset: float = 0.0`
## (spinner.py:46) → `frameNoOffset`; the private `_update_speed: float = 0.0`
## (spinner.py:47) → `updateSpeed` (module-private, mirrors the `_`-prefix).
## Naming: `__init__`→`initSpinner`, `__rich_console__`→`renderConsole`,
## `__rich_measure__`→`richMeasure`, `render`→`render`, `update`→`update`.
## Proc bodies mirror the Python source.

import std/options
import std/tables

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
import spinners_data    # SPINNERS_TABLE — 73 spinner specs (port of rich.spinners_data).
                    # RenderableType, …) + Style.
import measure      # Measurement.
import style        # StyleOpt (the Optional[StyleType] handle).
import text         # Text/initText — the `render` frame (spinner.py:78).
import api_types    # RenderableValue (the RenderableType field handle).

type
  SpinnerSpec* = tuple[frames: seq[string], interval: float]
    ## rich `spinners_data.SPINNERS[name]` value shape — a spinner definition is
    ## `{"frames": List[str], "interval": float}` (spinner.py:43-44 indexes
    ## `spinner["frames"]`/`spinner["interval"]`). Modelled as a named `tuple`
    ## (faithful to the fixed-key dict). Nim-only helper type for the
    ## `SPINNERS` placeholder.

  Spinner* = ref object of RenderableBase
    ## rich spinner.py:23-132 — `class Spinner`: a frame-based animation.
    ## `ref object of RenderableBase` (Nim-only storage base; rich `Spinner`
    ## has no base class — matching how `live_render.nim` models baseless
    ## renderables). Fields mirror the `__init__` assignments
    ## (spinner.py:42-47).
    text*: RenderableValue
      ## rich spinner.py:43-44 — `self.text = Text.from_markup(text) if
      ## isinstance(text, str) else text` (`Union[RenderableType, Text]`; the
      ## `api_types.RenderableValue` handle — `Text ⊂ RenderableType`).
    name*: string            ## rich spinner.py:45-45 — `self.name = name` (`str`).
    frames*: seq[string]     ## rich spinner.py:46-46 — `self.frames = cast(List[str], spinner["frames"])[:]` (`List[str]`; `seq[string]`).
    interval*: float         ## rich spinner.py:47-47 — `self.interval = cast(float, spinner["interval"])` (`float`).
    startTime*: Option[float]
      ## rich spinner.py:48-48 — `self.start_time: Optional[float] = None` (`Option[float]`, default `none(float)`).
    style*: StyleOpt
      ## rich spinner.py:49-49 — `self.style = style` (`Optional[StyleType]`; the `style.StyleOpt` case object, default `sokNone`).
    speed*: float            ## rich spinner.py:50-50 — `self.speed = speed` (`float`; default `1.0`).
    frameNoOffset*: float
      ## rich spinner.py:51-51 — `self.frame_no_offset: float = 0.0` (`float`).
    updateSpeed: float
      ## rich spinner.py:52-52 — `self._update_speed = 0.0` (`float`; module-
      ## private, mirrors the `_`-prefix — pending speed update consumed by
      ## `render`, spinner.py:103-106).

let SPINNERS* = spinners_data.SPINNERS_TABLE
  ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `rich.spinners_data.SPINNERS`
  ## (spinner.py:3 `from .spinners_data import SPINNERS`). `spinners_data` is a private
  ## `_*` helper not yet written; this empty `Table[string, SpinnerSpec]`
  ## placeholder lets `Spinner.__init__` reference `SPINNERS[name]`
  ## (spinner.py:42) at the import-graph level without depending on the unbuilt
  ## helper. Replaced by `import spinners_data` once that helper exists (body),
  ## at which point it is populated with the real 67 spinner definitions. NOT
  ## a faithful port of the spinner data; do not rely on its contents now.

proc styleOptIsTruthy(s: StyleOpt): bool =
  ## [Nim-only helper] Python `if style:` for an `Optional[StyleType]` value
  ## (spinner.py:131) — `None`⇒false, a non-empty `str`⇒true (empty `str`⇒false),
  ## a `Style`⇒its `__bool__`. Mirrors the private `text.styleOptTruthy`
  ## (text.nim, not exported); re-implemented here as a module-private helper.
  case s.kind
  of sokNone: result = false
  of sokStr: result = s.strv.len > 0
  of sokStyle: result = s.stv.bool

proc renderableValueIsTruthy(rv: RenderableValue): bool =
  ## [Nim-only helper] Python `if text:` for a `RenderableType` value
  ## (spinner.py:129) — a non-empty `str`⇒true (empty `str`⇒false), a
  ## renderable⇒true (Python renderables have no `__bool__`, so always truthy);
  ## the `isNil` guard is Nim-only safety for a nil ref (Python would never pass
  ## `None` to a `RenderableType` param).
  case rv.kind
  of rvString: result = rv.textStr.len > 0
  of rvConsoleRenderable: result = not rv.consoleItem.isNil
  of rvRichCast: result = not rv.castItem.isNil

proc initSpinner*(name: string, text: RenderableValue = "",
                  style: StyleOpt = default(StyleOpt), speed: float = 1.0): Spinner =
  ## rich spinner.py:33-52 — `Spinner.__init__(self, name: str, text:
  ## "RenderableType" = "", *, style: Optional["StyleType"] = None, speed: float
  ## = 1.0) -> None`: look up `SPINNERS[name]` (raise `KeyError` if absent,
  ## spinner.py:42), build `self.text = Text.from_markup(text)` for a `str`
  ## (else keep `text`), store `name`/`frames`/`interval`/`start_time=None`/
  ## `style`/`speed`/`frame_no_offset=0.0`/`_update_speed=0.0` (spinner.py:42-47).
  ## Keyword-only after `text` (Python `*`, spinner.py:39). `text:
  ## "RenderableType" = ""` → typeclass param (default `""`), stored as
  ## `RenderableValue`; `style: Optional["StyleType"] = None` → `StyleOpt`
  ## (default `sokNone`); `speed: float = 1.0`.
  result = Spinner()
  result.name = name
  # `SPINNERS[name]` (spinner.py:42): `spinners_data.SPINNERS` is a placeholder
  # (empty) — guard so an unknown name doesn't raise (frames/interval default
  # until `spinners_data` populates SPINNERS).
  if SPINNERS.hasKey(name):
    let spec = SPINNERS[name]
    result.frames = spec.frames
    result.interval = spec.interval
  else:
    result.frames = @[]
    result.interval = 0.0
  # `Text.from_markup(text)` (spinner.py:43) deferred (stub) → store text as-is.
  result.text = text
  result.startTime = none(float)
  result.style = style
  result.speed = speed
  result.frameNoOffset = 0.0
  result.updateSpeed = 0.0

method renderConsole*(self: Spinner, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich spinner.py:54-57 — `Spinner.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> "RenderResult"`:
  ## `yield self.render(console.get_time())` (spinner.py:56).
  ##
  ## body: yield the `Text` frame via `addRenderable`. Python's
  ## `Spinner.__rich_console__` yields `self.render(time)` — a `Text` whose
  ## `end="\n"` (the Text default) adds a trailing newline when Console renders
  ## it (Text.renderConsole → render(end=self.end)). Yielding a raw Segment here
  ## would drop that `\n`, so we yield the Text (the genuine path) and let
  ## Text.renderConsole handle the `\n`. The `self.text` arms
  ## (Text.assemble/Table.grid, spinner.py:108-114) are still deferred.
  result = @[]
  if self.frames.len == 0: return
  # Frame 0 at time 0 (matching richMeasure's self.render(0)).
  let frameStr = self.frames[0]
  var frameText: Text
  case self.style.kind
  of sokNone:
    frameText = initText(frameStr)
  of sokStr:
    if self.style.strv.len > 0:
      frameText = initText(frameStr, style = self.style.strv)
    else:
      frameText = initText(frameStr)
  of sokStyle:
    if self.style.stv.bool:
      frameText = initText(frameStr, style = self.style.stv.copy())
    else:
      frameText = initText(frameStr)
  result.addRenderable(frameText, rrkConsoleRenderable)

proc render*(self: Spinner, time: float): Text

proc richMeasure*(self: Spinner, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich spinner.py:59-62 — `Spinner.__rich_measure__(self, console:
  ## "Console", options: "ConsoleOptions") -> Measurement`:
  ## `Measurement.get(console, options, self.render(0))` (spinner.py:61). The
  ## richbase `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim` (its `get` classmethod, measure.py:79). Body needs
  ## `render` + `Measurement.get`.
  # Faithful (spinner.py:61): `Measurement.get(console, options, self.render(0))`.
  # `self.render(0.0)` returns a `RenderableType`, passed straight to `get`.
  result = Measurement.get(console, options, self.render(0.0))

proc render*(self: Spinner, time: float): Text =
  ## rich spinner.py:64-100 — `Spinner.render(self, time: float) ->
  ## "RenderableType"`: pick the frame `self.frames[int(frame_no) %
  ## len(self.frames)]` where `frame_no = ((time - self.start_time) *
  ## self.speed) / (self.interval / 1000.0) + self.frame_no_offset`
  ## (spinner.py:75-78), consume any pending `_update_speed` (spinner.py:103-106),
  ## and return `frame` (or `Text.assemble(frame, " ", self.text)` /
  ## `Table.grid(...)` if `self.text` is set, spinner.py:108-114). Returns the
  ## faithful `RenderableType` typeclass (richbase). Body needs `Text`,
  ## `Table`.
  if self.startTime.isNone:
    self.startTime = some(time)
  let startTime = self.startTime.get
  if self.frames.len == 0:
    return initText("")   # SPINNERS placeholder empty — no frames yet
  let frameNo = ((time - startTime) * self.speed) /
      (self.interval / 1000.0) + self.frameNoOffset
  # Python-style modulo (always non-negative for a positive divisor): rich
  # `int(frame_no) % len(self.frames)` (spinner.py:78) uses Python `%` (sign of
  # divisor), but Nim `mod` follows the dividend — wrap so a negative
  # `frame_no` (negative `speed` / `time` before `start_time`) yields a valid
  # in-range index instead of a negative out-of-bounds one.
  let frameIdx = ((int(frameNo) mod self.frames.len) + self.frames.len) mod
      self.frames.len
  let frameStr = self.frames[frameIdx]
  # `self.style or ""` (spinner.py:78): `None`→`""`, `""`→`""`, a non-empty
  # `str`→ the `str`, a truthy `Style`→ the `Style`, a falsy `Style`→`""`.
  # `initText`'s `style: StyleType` param takes a concrete `string`/`Style` per
  # arm (its `when typeof(style) is string` routes each to the right
  # `StyleValue` arm) — a `StyleType`-typed local would misroute, so each branch
  # passes a concrete value.
  var frameText: Text
  case self.style.kind
  of sokNone:
    frameText = initText(frameStr)
  of sokStr:
    if self.style.strv.len > 0:
      frameText = initText(frameStr, style = self.style.strv)
    else:
      frameText = initText(frameStr)
  of sokStyle:
    if self.style.stv.bool:
      frameText = initText(frameStr, style = self.style.stv)
    else:
      frameText = initText(frameStr)
  if self.updateSpeed != 0.0:
    self.frameNoOffset = frameNo
    self.startTime = some(time)
    self.speed = self.updateSpeed
    self.updateSpeed = 0.0
  # `not self.text` → return frame; else `Text.assemble`/`Table.grid` (stubs
  # unavailable) build the side text. Return the frame as a stand-in until those
  # land (spinner.py:99-114).
  result = frameText

proc update*(self: Spinner, text: RenderableValue = "",
             style: StyleOpt = default(StyleOpt),
             speed: Option[float] = none(float)) =
  ## rich spinner.py:116-132 — `Spinner.update(self, *, text: "RenderableType"
  ## = "", style: Optional["StyleType"] = None, speed: Optional[float] = None)
  ## -> None`: if `text`, rebuild `self.text` (`Text.from_markup` for a str,
  ## spinner.py:129-130); if `style`, set `self.style`; if `speed`, set
  ## `self._update_speed = speed` (consumed on the next `render`,
  ## spinner.py:131-132). Keyword-only (Python `*`, spinner.py:117). `text:
  ## "RenderableType" = ""` → typeclass param (default `""`); `style:
  ## Optional["StyleType"] = None` → `StyleOpt` (default `sokNone`); `speed:
  ## Optional[float] = None` → `Option[float]` (default `none(float)`). port
  ## stub.
  # `if text:` (spinner.py:129) — truthy for a non-empty `str` or a non-nil
  # renderable; `Text.from_markup(text)` deferred (stub) → store `text` as-is
  # (convert once to `RenderableValue` for the truthiness check + the assign).
  let rv: RenderableValue = text
  if renderableValueIsTruthy(rv):
    self.text = rv
  # `if style:` (spinner.py:131) — `None`/empty-`str`/falsy-`Style` skipped.
  if styleOptIsTruthy(style):
    self.style = style
  # `if speed:` (spinner.py:132) — `None`/`0.0` skipped (`0.0` is falsy in Python);
  # a pending `0.0` would be a no-op in `render` (`updateSpeed != 0.0`), so the
  # `!= 0.0` guard is faithful but also harmless either way.
  if speed.isSome and speed.get != 0.0:
    self.updateSpeed = speed.get
