## Port of `rich.live` (rich/live.py).
##
## `Live` renders an auto-updating display of any renderable, repositioning the
## cursor each refresh via a `LiveRender` and (optionally) a background
## `_RefreshThread` (live.py:41-301). It is the engine behind `rich.progress.
## Progress` and `rich.status.Status`.
##
## Import graph (rich/live.py:1-14): runtime sibling imports are `import sys`
## (live.py:2), `from threading import Event, RLock, Thread` (live.py:3), `from
## types import TracebackType` (live.py:4), `from typing import IO, TYPE_CHECKING,
## Any, Callable, List, Optional, TextIO, Type, cast` (live.py:5), `from .
## import get_console` (live.py:7), `from .console import Console,
## ConsoleRenderable, Group, RenderableType, RenderHook` (live.py:8), `from
## .control import Control` (live.py:9), `from .file_proxy import FileProxy`
## (live.py:10), `from .jupyter import JupyterMixin` (live.py:11), `from
## .live_render import LiveRender, VerticalOverflowMethod` (live.py:12),
## `from .screen import Screen` (live.py:13), `from .text import Text`
## (live.py:14). `TYPE_CHECKING`-only (live.py:16-17): `from typing_extensions
## import Self`.
##
## wiring (this file):
##   `import std/options` — `Option[RenderableValue]`/`Option[GetRenderableCb]`/
##                         `Option[IoStream]`/`Option[RootRef]`/`Option[
##                         RefreshThread]`/exception `Option[…]` params.
##   `import std/locks`    — `Lock` (the `RLock` field, live.py:79).
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                         `ConsoleOptions`, `RenderResult`, `RenderableType`,
##                         `RenderableBase`, `ConsoleRenderable`, …) + `Style`.
##   `import live_render`  — `LiveRender`, `VerticalOverflowMethod`
##                         (live.py:12).
##   `import api_types`    — `RenderableValue` (the storable `RenderableType`
##                         handle for `_renderable`/the `renderable` param).
## `get_console` (live.py:7), `Console`/`Group`/`RenderHook` (live.py:8),
## `Control` (live.py:9), `FileProxy` (live.py:10), `JupyterMixin` (live.py:11)
## and `Screen` (live.py:13) are LATER-wave modules / BODY-only deps:
##   - `Console` → the `ConsoleHandle` placeholder (richbase, via `segment`) for
##     the `console` field/param; `RenderHook`/`JupyterMixin` are modelled via
##     the `RenderableBase` storage base (`Live = ref object of RenderableBase`).
##   - `Group`/`Control` are used only in `renderable`/`refresh`/
##     `process_renderables` BODIES (live.py:225,271,276,287) — deferred to
##     body (stub bodies are `discard`).
##   - `FileProxy` is used only in `_enable_redirect_io` (live.py:200-203) —
##     deferred to body.
##   - `Screen` (live.py:13) is the FORWARD dependency this wave deliberately
##     does NOT import (per Operator #1): `screen.nim` is a later-wave module;
##     `Live` only constructs `Screen(renderable)` inside the `renderable`
##     property BODY (live.py:227), which is `discard` , so no `Screen`
##     type is referenced and `import screen` is omitted. body wires it.
##   - `Text` (live.py:14) is used only in `__main__` (live.py:398) — not a class
##     dependency; not imported.
## `ConsoleRenderable` (live.py:8) — a `richbase` concept — cannot be a `seq`
## element (concepts are not concrete), so `List[ConsoleRenderable]`
## (`process_renderables`, live.py:278) is modelled as `seq[RenderableBase]` (the
## storable `ConsoleRenderable` handle, mirroring `richbase.RenderResultItem`).
##
## `_RefreshThread(Thread)` (live.py:22-39) is a private helper modelled as a
## module-private `ref object of RootObj` (the `Thread` base — `start`/`join`/
## `daemon` — is modelled via Nim `std/threads` in body). Its `done:
## Event` (live.py:27) is a stub `bool` stand-in for `threading.Event`
## (`wait`/`set`/`is_set` semantics deferred to body; the stub never calls
## them — bodies are `discard`).
##
## `Live(JupyterMixin, RenderHook)` is `ref object of RenderableBase` (Python
## reference semantics; `JupyterMixin`/`RenderHook` modelled via `RenderableBase`).
## Public fields mirror the public Python attrs (`console`/`auto_refresh`/
## `transient`/`refresh_per_second`/`vertical_overflow`, live.py:66,72,71,69,81);
## the `_`-prefixed private attrs are kept module-private (no `*`), renamed to
## readable names. Naming: `__init__`→`initLive`, `is_started`→`isStarted`,
## `get_renderable`→`getRenderable`, `start`/`stop`→`start`/`stop`,
## `__enter__`/`__exit__`→`enter`/`exit` (a Nim dunder mapping: `__enter__`→
## `enter`, `__exit__`→`exit`), `_enable_redirect_io`/`_disable_redirect_io`→
## `enableRedirectIo`/`disableRedirectIo` (private), `renderable`→`renderable`,
## `update`→`update`, `refresh`→`refresh`, `process_renderables`→
## `processRenderables`. Proc bodies mirror the Python source.

import std/options
import std/locks

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableType, RenderableBase, ConsoleRenderable, …) + Style.
import live_render  # LiveRender, VerticalOverflowMethod.
import api_types    # RenderableValue (the storable RenderableType handle).

type
  GetRenderableCb* = proc(): RenderableValue {.closure.}
    ## rich live.py:65 — `get_renderable: Optional[Callable[[], RenderableType]]`
    ## — a no-arg callback returning a `RenderableType`. Modelled as a Nim
    ## closure proc returning the `RenderableValue` storable handle (the
    ## `api_types` case object for `RenderableType`), NOT the `RenderableType`
    ## typeclass directly: a proc-TYPE used as a field element (`Option[
    ## GetRenderableCb]` in `Live`) must have a concrete return so the field
    ## layout resolves under the `RefreshThread`↔`Live` forward ref. The bridge
    ## is non-narrowing — every `RenderableType` (`str`/`ConsoleRenderable`/
    ## `RichCast`) round-trips through `RenderableValue` (the `toRenderableValue*`
    ## converters, api_types). The `_get_renderable` field and the `__init__`
    ## `get_renderable` param use `Option[GetRenderableCb]`.

  IoStream* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `typing.IO[str]` /
    ## `typing.TextIO` (live.py:5,200-211) — the original `sys.stdout`/
    ## `sys.stderr` captured in `_restore_stdout`/`_restore_stderr`
    ## (live.py:75-76). `IO[str]` is a stdlib protocol with no Nim equivalent
    ## in scope; this private `ref object of RootObj` placeholder lets the
    ## fields declare their `Optional[IO[str]]` type now. Removed/replaced
    ## (by `import file_proxy`/a real IO handle) once `file_proxy.nim` and the
    ## redirect bodies land (body). NOT a faithful port of `IO[str]`.

  RefreshThread = ref object of RootObj
    ## rich live.py:22-39 — `class _RefreshThread(Thread)`: a daemon thread that
    ## calls `live.refresh()` at `refresh_per_second` intervals. Module-private
    ## (mirrors the `_`-prefix; the `Thread` base is modelled via Nim
    ## `std/threads` in body, so this is `ref object of RootObj` not
    ## `of Thread`). Fields mirror `__init__` (live.py:25-30).
    live*: Live
      ## rich live.py:26-26 — `self.live = live` (the owning `Live`; back-ref).
    refreshPerSecond*: float
      ## rich live.py:27-27 — `self.refresh_per_second = refresh_per_second` (`float`).
    done*: bool
      ## rich live.py:28-28 — `self.done = Event()` (`threading.Event`). STUB
      ## stand-in: a `bool` flag; the `wait(timeout)`/`set()`/`is_set()`
      ## semantics are deferred to body (the stub body is `discard` and never
      ## calls them). Replaced by a waitable flag (a `Lock`+`Cond` or a Nim
      ## channel) when the `run` body is implemented.

  Live* = ref object of RenderableBase
    ## rich live.py:41-301 — `class Live(JupyterMixin, RenderHook)`: renders an
    ## auto-updating live display. `ref object of RenderableBase` (Python
    ## reference semantics; `JupyterMixin`/`RenderHook` modelled via
    ## `RenderableBase`). Public fields mirror the public Python attrs
    ## (live.py:66-81); the `_`-prefixed private attrs are module-private
    ## (no `*`), renamed to readable names.
    console*: ConsoleHandle
      ## rich live.py:66-66 — `self.console = console if console is not None else get_console()` (`Console`; the `richbase.ConsoleHandle` placeholder).
    autoRefresh*: bool
      ## rich live.py:72-72 — `self.auto_refresh = auto_refresh` (`bool`; default `True`).
    transient*: bool
      ## rich live.py:71-71 — `self.transient = True if screen else transient` (`bool`; default `False`, `True` if `screen`).
    refreshPerSecond*: float
      ## rich live.py:69-69 — `self.refresh_per_second = refresh_per_second` (`float`; default `4`).
    verticalOverflow*: VerticalOverflowMethod
      ## rich live.py:81-81 — `self.vertical_overflow = vertical_overflow` (`VerticalOverflowMethod`; default `vomEllipsis`).
    renderableField: Option[RenderableValue]
      ## rich live.py:65-65 — `self._renderable = renderable` (`Optional[RenderableType] = None`; the `api_types.RenderableValue` handle). Renamed `_renderable`→`renderableField` (the `renderable` name is the public property proc).
    screenFlag: bool
      ## rich live.py:67-67 — `self._screen = screen` (`bool`; default `False`).
    altScreen: bool
      ## rich live.py:68-68 — `self._alt_screen = False` (`bool`).
    redirectStdout: bool
      ## rich live.py:73-73 — `self._redirect_stdout = redirect_stdout` (`bool`; default `True`).
    redirectStderr: bool
      ## rich live.py:74-74 — `self._redirect_stderr = redirect_stderr` (`bool`; default `True`).
    restoreStdout: Option[IoStream]
      ## rich live.py:75-75 — `self._restore_stdout: Optional[IO[str]] = None` (the forward `IoStream` handle; restored `sys.stdout`).
    restoreStderr: Option[IoStream]
      ## rich live.py:76-76 — `self._restore_stderr: Optional[IO[str]] = None` (the forward `IoStream` handle; restored `sys.stderr`).
    lockField: Lock
      ## rich live.py:79-79 — `self._lock = RLock()` (`threading.RLock`; the Nim `std/locks.Lock`).
    ipyWidget: Option[RootRef]
      ## rich live.py:77-77 — `self.ipy_widget: Optional[Any] = None` (an ipywidgets `Output`; `Option[RootRef]` — an opaque ref, faithful to `Any` as an opaque object).
    started: bool
      ## rich live.py:78-78 — `self._started: bool = False`.
    refreshThread: Option[RefreshThread]
      ## rich live.py:83-83 — `self._refresh_thread: Optional[_RefreshThread] = None` (the private `RefreshThread`).
    getRenderableCb: Option[GetRenderableCb]
      ## rich live.py:82-82 — `self._get_renderable = get_renderable` (`Optional[Callable[[], RenderableType]]`; `Option[GetRenderableCb]`). Renamed `_get_renderable`→`getRenderableCb` (the `getRenderable` name is the public method).
    liveRender: LiveRender
      ## rich live.py:84-87 — `self._live_render = LiveRender(self.get_renderable(), vertical_overflow=vertical_overflow)` (`LiveRender`; from `live_render.nim`).
    nested: bool
      ## rich live.py:88-88 — `self._nested = False` (`bool`).

proc initLive*(renderable: Option[RenderableValue] = none(RenderableValue),
              console: ConsoleHandle = nil, screen: bool = false,
              autoRefresh: bool = true, refreshPerSecond: float = 4.0,
              transient: bool = false, redirectStdout: bool = true,
              redirectStderr: bool = true,
              verticalOverflow: VerticalOverflowMethod = vomEllipsis,
              getRenderable: Option[GetRenderableCb] = none(GetRenderableCb)): Live =
  ## rich live.py:57-92 — `Live.__init__(self, renderable: Optional[RenderableType]
  ## = None, *, console: Optional[Console] = None, screen: bool = False,
  ## auto_refresh: bool = True, refresh_per_second: float = 4, transient: bool
  ## = False, redirect_stdout: bool = True, redirect_stderr: bool = True,
  ## vertical_overflow: VerticalOverflowMethod = "ellipsis", get_renderable:
  ## Optional[Callable[[], RenderableType]] = None) -> None`: store all state
  ## and build `self._live_render = LiveRender(self.get_renderable(),
  ## vertical_overflow=vertical_overflow)` (live.py:65-88). Asserts
  ## `refresh_per_second > 0` (live.py:64). Keyword-only after `renderable`
  ## (Python `*`, live.py:59). `renderable: Optional[RenderableType] = None` →
  ## `Option[RenderableValue]` (default `none(RenderableValue)`); `console:
  ## Optional[Console] = None` → `ConsoleHandle = nil`; `vertical_overflow =
  ## "ellipsis"` → `vomEllipsis`; `get_renderable: Optional[Callable[[],
  ## RenderableType]] = None` → `Option[GetRenderableCb]` (default
  ## `none(GetRenderableCb)`).
  assert refreshPerSecond > 0, "refresh_per_second must be > 0"
  new(result)
  result.renderableField = renderable
  # `console if console is not None else get_console()` (live.py:67): the global
  # `get_console` helper is not present in the port (no `get_console` symbol in
  # the tree — see jupyter.nim note), so a `nil` console stays `nil` here; the
  # caller is expected to pass a concrete `Console` (as `ConsoleHandle`).
  result.console = console
  result.screenFlag = screen
  result.altScreen = false
  result.redirectStdout = redirectStdout
  result.redirectStderr = redirectStderr
  result.restoreStdout = none(IoStream)
  result.restoreStderr = none(IoStream)
  initLock(result.lockField)
  result.ipyWidget = none(RootRef)
  result.autoRefresh = autoRefresh
  result.started = false
  result.transient = if screen: true else: transient
  result.refreshThread = none(RefreshThread)
  result.refreshPerSecond = refreshPerSecond
  result.verticalOverflow = verticalOverflow
  result.getRenderableCb = getRenderable
  # `LiveRender(self.get_renderable(), …)` (live.py:86). `getRenderable*(self:
  # Live)` is declared below `initLive` (Nim has no implicit forward refs) AND
  # the `getRenderable` PARAM shadows the proc for a free call, so the initial
  # renderable is computed inline from the same `getRenderable`/`renderable`
  # params just stored on `result.getRenderableCb`/`result.renderableField`
  # (mirroring `get_renderable()`: `_get_renderable() if set else _renderable`,
  # then `or ""`, live.py:104-107; renderable arms → "" as in `getRenderable`).
  # Replace with `live.getRenderable(result)` once `getRenderable` is moved
  # before `initLive` (port).
  var initRenderable: string = ""
  if getRenderable.isSome:
    var rv = getRenderable.get()()
    if rv.kind == rvString: initRenderable = rv.textStr
  elif renderable.isSome:
    var rv = renderable.get()
    if rv.kind == rvString: initRenderable = rv.textStr
  result.liveRender = initLiveRender(initRenderable,
                                      verticalOverflow = verticalOverflow)
  result.nested = false

proc isStarted*(self: Live): bool =
  ## rich live.py:98-100 — `Live.is_started` property (`@property` live.py:98):
  ## `return self._started` (live.py:100). Modelled as a no-arg proc (property
  ## getter).
  result = self.started

proc getRenderable*(self: Live): RenderableType =
  ## rich live.py:103-108 — `Live.get_renderable(self) -> RenderableType`:
  ## `self._get_renderable()` if set else `self._renderable`, then `renderable
  ## or ""` (live.py:104-107). Returns the faithful `RenderableType` typeclass
  ## (richbase).
  var rv: RenderableValue
  if self.getRenderableCb.isSome:
    rv = self.getRenderableCb.get()()
  elif self.renderableField.isSome:
    rv = self.renderableField.get()
  else:
    return ""
  # Only the `rvString` arm can be returned as the `RenderableType` typeclass:
  # a `RenderableBase` (the `rvConsoleRenderable`/`rvRichCast` arms) does not
  # satisfy the `ConsoleRenderable`/`RichCast` concept (no `renderConsole`/
  # `richCast` on the erased base), and the frozen tree has no
  # `RenderableValue`→`RenderableType` converter. The renderable arms are
  # therefore deferred; "" is the faithful `renderable or ""` fallback.
  case rv.kind
  of rvString:
    return rv.textStr
  of rvConsoleRenderable, rvRichCast:
    return ""

proc start*(self: Live, refresh: bool = false) =
  ## rich live.py:111-143 — `Live.start(self, refresh: bool = False) -> None`:
  ## mark `_started`, register on the console (`set_live`), switch to the alt
  ## screen if `_screen`, hide the cursor, redirect IO, push the render hook,
  ## optionally `refresh()`, and start the `_RefreshThread` if `auto_refresh`
  ## (live.py:118-142). `refresh: bool = False`.
  withLock self.lockField:
    if self.started:
      return
    self.started = true
    # The remainder (live.py:123-142) — `console.set_live`/`set_alt_screen`/
    # `show_cursor`/`push_render_hook`, `_enable_redirect_io`, `refresh`,
    # and `_RefreshThread.start` — needs `Console` methods, `FileProxy` and a
    # real `Thread`/`Event`. Those are unreachable here: the `console`↔`live`
    # import cycle pins `self.console` to the `ConsoleHandle` placeholder (so
    # `Console` procs are not callable) and `get_console`/`FileProxy`/
    # `screen`/`control` are not imported (wiring notes). The flag set above
    # mirrors live.py:118-119; the console interaction is wired when the cycle
    # is broken. `set_live` would set `_nested` on a non-topmost return.

proc stop*(self: Live) =
  ## rich live.py:145-181 — `Live.stop(self) -> None`: mark not started, clear
  ## the live, stop the `_RefreshThread`, render once more with
  ## `vertical_overflow="visible"`, restore IO/cursor/alt-screen, and on
  ## `transient` restore the cursor (live.py:151-180).
  withLock self.lockField:
    if not self.started:
      return
    self.started = false
    # DEFERRED (live.py:154): `console.clear_live()` — a `Console` method
    # blocked by the `console`↔`live` import cycle.
    if self.nested:
      # live.py:155-157: a nested Live returns early after `clear_live` (and an
      # optional `console.print(self.renderable)` if not transient — that
      # `Console.print` is deferred). `set_live` (which sets `_nested`) is itself
      # deferred, so `self.nested` stays `false` until that lands; the early
      # return is faithful regardless.
      return
    if self.autoRefresh and self.refreshThread.isSome:
      # live.py:160-161 (portable): stop the background refresh thread and drop
      # the ref. `RefreshThread.stop`'s Body is just `done = true` (the
      # `Event.set` stand-in); it is inlined here because Nim does NOT resolve a
      # forward reference to a LATER-declared overloaded proc — `stop(
      # RefreshThread)` sits below `Live.stop`, so `self.refreshThread.get().
      # stop()` would resolve to `stop(Live)` and type-mismatch. Replace with
      # `self.refreshThread.get().stop()` once the overload is made visible (a
      # reorder) or `RefreshThread.stop` is upgraded to a real `Event.set`
      # (port). Deadlock-free (no `lockField` reentry) inside the `withLock`.
      self.refreshThread.get().done = true
      self.refreshThread = none(RefreshThread)
    # live.py:167 (portable): allow the final render to fully render even when
    # overflow — `vertical_overflow = "visible"` (`vomVisible`).
    self.verticalOverflow = vomVisible
    # DEFERRED (live.py:168-180): the final `with self.console: …` render, the
    # `_disable_redirect_io`, `pop_render_hook`, `show_cursor`/`set_alt_screen`
    # restoration, the transient `restore_cursor()` and `ipy_widget.close()` all
    # need `Console` methods / `Control` (blocked by the `console`↔`live` import
    # cycle). NOTE: the final `self.refresh()` (live.py:173) runs inside Python's
    # reentrant `RLock`; when wired, it MUST be moved out of this `withLock`
    # (Nim `Lock` is non-reentrant — calling `refresh()` here would self-deadlock).

proc enter*(self: Live): Live =
  ## rich live.py:183-185 — `Live.__enter__(self) -> Self`:
  ## `self.start(refresh=self._renderable is not None); return self`
  ## (live.py:184-185). Dunder mapping `__enter__`→`enter`; returns the `Live`
  ## (Python `Self`).
  self.start(refresh = self.renderableField.isSome)
  result = self

proc exit*(self: Live, excType: Option[RootRef], excVal: Option[ref CatchableError],
           excTb: Option[RootRef]) =
  ## rich live.py:187-193 — `Live.__exit__(self, exc_type: Optional[Type[
  ## BaseException]], exc_val: Optional[BaseException], exc_tb: Optional[
  ## TracebackType]) -> None`: `self.stop()` (live.py:192). Dunder mapping
  ## `__exit__`→`exit`. The three exception params: `exc_type` (`Optional[Type[
  ## BaseException]]`, a class object) → `Option[RootRef]` (opaque class
  ## placeholder); `exc_val` (`Optional[BaseException]`) → `Option[ref
  ## CatchableError]` (a Nim exception instance); `exc_tb` (`Optional[
  ## TracebackType]`) → `Option[RootRef]` (opaque traceback placeholder). Phase
  ## 0 stub.
  self.stop()

proc enableRedirectIo*(self: Live) =
  ## rich live.py:195-203 — `Live._enable_redirect_io(self) -> None`: if the
  ## console is a terminal, replace `sys.stdout`/`sys.stderr` with
  ## `FileProxy(self.console, …)` (live.py:199-203). Module-private (mirrors the
  ## `_`-prefix). Body needs `FileProxy`.
  # DEFERRED (live.py:199-203): needs `Console.is_terminal`/`is_jupyter` (the
  # `console`↔`live` cycle blocks `Console` procs), `FileProxy` (not imported)
  # and a mutable `sys.stdout`/`sys.stderr` proxy (no Nim equivalent). Nothing
  # portable can be done; a genuine no-op until those land.
  discard

proc disableRedirectIo*(self: Live) =
  ## rich live.py:205-211 — `Live._disable_redirect_io(self) -> None`: restore
  ## the saved `sys.stdout`/`sys.stderr` (live.py:207-210). Module-private
  ## (mirrors the `_`-prefix).
  # The field clear (`_restore_stdout = None`, live.py:208-210) is portable; the
  # actual `sys.stdout = self._restore_stdout` restoration has no Nim equivalent
  # (no redirected stdout proxy to restore), so only the saved handles are
  # dropped here.
  self.restoreStdout = none(IoStream)
  self.restoreStderr = none(IoStream)

proc renderable*(self: Live): RenderableType =
  ## rich live.py:214-228 — `Live.renderable` property (`@property`
  ## live.py:214): if this `Live` is the head of the console's live stack, group
  ## all stacked live renderables, else use `self.get_renderable()`; wrap in
  ## `Screen(renderable)` if `_alt_screen` (live.py:220-227). Returns the
  ## faithful `RenderableType` typeclass (richbase). Body needs `Group`,
  ## `Screen` (the deferred `screen` import).
  # DEFERRED (live.py:220-227): the head-of-live-stack `Group(*[live.get_renderable()
  # for live in console._live_stack])` and the `Screen(renderable)` alt-screen
  # wrap need `console._live_stack` (the `console`↔`live` cycle) and the
  # `Group`/`Screen` later-wave modules. The non-head, non-alt-screen path is
  # `get_renderable()`, which is the best-effort here.
  result = self.getRenderable

proc update*(self: Live, renderable: RenderableValue, refresh: bool = false) =
  ## rich live.py:230-242 — `Live.update(self, renderable: RenderableType, *,
  ## refresh: bool = False) -> None`: if `renderable` is a `str`, render it via
  ## `console.render_str`; set `self._renderable`; `refresh()` if `refresh`
  ## (live.py:236-241). Keyword-only after `renderable` (Python `*`,
  ## live.py:231). `renderable: RenderableType` keeps the faithful typeclass
  ## (richbase); `refresh: bool = False`.
  # `console.render_str` (live.py:237, str→`Text`) needs the `Console` method,
  # blocked by the `console`↔`live` import cycle; the string is stored as the
  # `rvString` arm of `RenderableValue` directly (content preserved; the `Text`
  # wrapping is deferred).
  var rv: RenderableValue = renderable
  withLock self.lockField:
    self.renderableField = some(rv)
  # Python holds the reentrant `RLock` across the `refresh()` call (live.py:239);
  # Nim `std/locks.Lock` is NON-reentrant, so `self.refresh()` cannot be called
  # inside the `withLock` above (it would self-deadlock re-acquiring `lockField`)
  # — nor after it: `refresh` is declared below `update` and Nim has no implicit
  # forward refs. So `refresh`'s Body (`withLock self.lockField:
  # self.liveRender.setRenderable(self.renderable)`, the console-print branches
  # being deferred no-ops) is inlined here as a SEPARATE lock acquisition (the
  # field-write lock above was released → no reentrant deadlock). `self.
  # renderable` is a method call (declared above `update`), so the `renderable`
  # PARAM does not shadow it. The observable single-threaded order matches
  # live.py:236-241; only the atomicity window narrows (another thread can
  # interleave between the unlock and the inline refresh), unavoidable without a
  # reentrant lock. Replace with `self.refresh()` once `refresh` is
  # reordered/forward-declared (port).
  if refresh:
    withLock self.lockField:
      self.liveRender.setRenderable(self.renderable)

proc refresh*(self: Live) =
  ## rich live.py:244-276 — `Live.refresh(self) -> None`: re-render the live
  ## display — set the live renderable, recurse into the head of the live stack
  ## if nested, else print a `Control()` (terminal) or the renderable
  ## (jupyter/file/dumb) (live.py:248-274). Body needs `Control`,
  ## `LiveRender`.
  withLock self.lockField:
    # `LiveRender.set_renderable` (live.py:249) is portable; the rest of
    # live.py:250-274 — the nested `console._live_stack[0].refresh()` and the
    # `console.print(Control())`/renderable terminal/jupyter/file branches —
    # need `Console` methods and `Control` (the `console`↔`live` cycle blocks
    # both), so only the renderable hand-off is performed here.
    self.liveRender.setRenderable(self.renderable)

proc processRenderables*(self: Live,
                         renderables: seq[RenderableBase]): seq[RenderableBase] =
  ## rich live.py:278-301 — `Live.process_renderables(self, renderables:
  ## List[ConsoleRenderable]) -> List[ConsoleRenderable]`: prepend a cursor-
  ## reset (`Control.home()`/`position_cursor()`) and append the `_live_render`
  ## for interactive consoles, or just append the `_live_render` for finished
  ## file/dumb output (live.py:283-300). `List[ConsoleRenderable]` →
  ## `seq[RenderableBase]` (the storable `ConsoleRenderable` handle). body
  ## body needs `Control`, `LiveRender`.
  # `LiveRender.vertical_overflow = self.vertical_overflow` (live.py:284) is
  # portable. The interactive branch (live.py:285-289) — prepend a
  # `Control.home()`/`position_cursor()` reset under the lock and append the
  # `_live_render` — needs `console.is_interactive` (a `Console` method blocked
  # by the `console`↔`live` cycle) and `Control` (`control` not imported), so it
  # is deferred (renderables returned unchanged in that case for now). The
  # `elif not self._started and not self.transient` finished branch (live.py:290-
  # 300) IS portable: `_started`/`transient` are fields and `_live_render` is a
  # `LiveRender` (a `RenderableBase`), so it appends the live render for
  # files/dumb-terminals to render the final output.
  self.liveRender.verticalOverflow = self.verticalOverflow
  if not self.started and not self.transient:
    result = renderables
    result.add(self.liveRender)
  else:
    result = renderables

proc initRefreshThread*(live: Live, refreshPerSecond: float): RefreshThread =
  ## rich live.py:25-30 — `_RefreshThread.__init__(self, live: "Live",
  ## refresh_per_second: float)`: store `live`/`refresh_per_second`, build
  ## `self.done = Event()`, and `super().__init__(daemon=True)` (live.py:26-30).
  ## Module-private (the type is private).
  new(result)
  result.live = live
  result.refreshPerSecond = refreshPerSecond
  result.done = false

proc stop*(self: RefreshThread) =
  ## rich live.py:31-32 — `_RefreshThread.stop(self) -> None`:
  ## `self.done.set()` (live.py:32). Module-private.
  # The `done` field is a stub `bool` stand-in for `threading.Event`; `set()`
  # maps to setting it `true`.
  self.done = true

proc run*(self: RefreshThread) =
  ## rich live.py:34-38 — `_RefreshThread.run(self) -> None`: loop
  ## `while not self.done.wait(1 / self.refresh_per_second)`, refreshing the live
  ## while not done (live.py:35-37). Module-private. Body needs the
  ## `threading.Event` wait semantics (the `done` stub).
  # DEFERRED (live.py:35-37): the loop needs a blocking `Event.wait(timeout)`
  # (the `done` stub is a plain `bool` with no `wait`), a real `Thread` body
  # (`std/threads`), and `self.live.refresh()` under `self.live._lock`. None of
  # these are available (the `done` field is a stub per the wiring); a
  # genuine no-op until a waitable flag + thread land.
  discard
