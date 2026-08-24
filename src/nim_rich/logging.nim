## Port of `rich.logging` (rich/logging.py, 305 lines).
##
## `RichHandler` is a `logging.Handler` subclass that renders log records with
## Rich — time/level/message/path in columns, the level colour-coded, the
## message syntax-highlighted, and optional rich tracebacks (logging.py:24-247).
##
## Import graph (rich/logging.py:1-21): runtime sibling imports are `import
## logging` (logging.py:3), `import os` (logging.py:4), `from datetime import
## datetime` (logging.py:5), `from logging import Handler, LogRecord`
## (logging.py:6), `from types import ModuleType` (logging.py:7), `from typing
## import TYPE_CHECKING, ClassVar, Iterable, List, Optional, Type, Union`
## (logging.py:8), `from rich._null_file import NullFile` (logging.py:16),
## `from . import get_console` (logging.py:18), `from ._log_render import
## LogRender` (logging.py:19), `from .highlighter import ReprHighlighter`
## (logging.py:20), `from .text import Text` (logging.py:21). TYPE_CHECKING-only
## (logging.py:10-14): `FormatTimeCallable` (`_log_render`), `Console`/
## `ConsoleRenderable` (`console`), `Highlighter` (`highlighter`), `Traceback`
## (`traceback`).
##
## wiring (this file):
##   `import std/options`  — `Option[int]`/`Option[string]`/`Option[Highlighter]`/
##                           `Option[seq[string]]`/`Option[Traceback]` params.
##   `import std/times`     — `DateTime` (the `FormatTimeCallable` arg,
##                           logging.py:5,226).
##   `import segment`      — re-exports `richbase` (`ConsoleOptions`,
##                           `RenderResult`, `RenderableType`, `RenderableBase`,
##                           …) + `Style`.
##   `import console`      — `Console` (logging.py:12,124; the real console
##                           type, post-).
##   `import highlighter`   — `Highlighter` (logging.py:13,127) +
##                           `ReprHighlighter` (logging.py:20, the
##                           `HIGHLIGHTER_CLASS` default).
##   `import text`         — `Text` (logging.py:21, the `get_level_text`/render
##                           return and the `FormatTimeCallable` return).
##   `import traceback`    — `Traceback` (logging.py:14, the `render` `traceback`
##                           param).
##
## `get_console` (rich.__init__, logging.py:18) and `NullFile` (`_null_file`,
## logging.py:16) are NOT imported : `get_console` is an
## `__init__`-mirror helper (no sibling module) used only in the `__init__` body
## (`console or get_console()`, logging.py:124); `NullFile` is used only in the
## `emit` body (`isinstance(self.console.file, NullFile)`, logging.py:170) — both
## BODY-only, deferred to body.
##
## Provisional forward handles (placeholders, removed/replaced when the
## real type lands):
##   * `LogRender*` — `rich._log_render.LogRender` (logging.py:19); the
##     `_log_render` private helper is not yet ported. The `_logRender` field is
##     typed `LogRender`.
##   * `LogRecord*` — Python's `logging.LogRecord` (logging.py:6); a stdlib type
##     with many fields (`levelname`/`pathname`/`lineno`/`created`/`exc_info`/…)
##     used in `emit`/`render`/`get_level_text` bodies — a faithful port is a
##     Body concern. Used as the `record` param type here.
##   * `FormatTimeCallable*` — `rich._log_render.FormatTimeCallable` (logging.py:
##     11, `Union[TimeFormatter, Callable[[datetime], Text]]`); modelled as
##     `proc(dt: DateTime): Text {.closure.}` (the `Text` return subsumes `str`
##     via `Text`).
##
## Union params (non-narrowing case objects):
##   * `LogLevel*` — `Union[int, str]` (logging.py:71, `level: Union[int, str] =
##     logging.NOTSET`); `llInt`/`llStr`. `default(LogLevel)` = `llInt(0)` =
##     `logging.NOTSET` (the rich default — NOTSET is 0).
##   * `LogTimeFormat*` — `Union[str, FormatTimeCallable]` (logging.py:99,
##     `log_time_format`); `ltfStr`/`ltfCallable`. Default `ltfStr("[%x %X]")`
##     (the rich default, logging.py:99).
##   * `TracebackSuppress*` — `Union[str, ModuleType]` (logging.py:89,
##     `tracebacks_suppress: Iterable[Union[str, ModuleType]]`); `tsStr`/`tsModule`
##     (`ModuleType` → `RootRef` opaque handle). The param is
##     `openArray[TracebackSuppress]` (faithful to the `Iterable`, default `@[]`
##     = the empty tuple `()`).
##
## `RichHandler(Handler)` → `ref object of RootObj` (the `logging.Handler` base
## is modelled via `RootObj`; the `level`/`format`/`handle` infrastructure is a
## Body concern — `super().__init__(level=level)`, logging.py:122).
## Public fields mirror the `__init__` assignments (logging.py:124-145); the
## Python *class attributes* `KEYWORDS` (ClassVar, logging.py:60-69) and
## `HIGHLIGHTER_CLASS` (ClassVar[Type[Highlighter]] = ReprHighlighter,
## logging.py:71) become a module `const`/`let`: `KEYWORDS*` is the verbatim
## 8-method list; `highlighterClass*` is a `HighlighterFactory*` (a `proc():
## Highlighter`), the Nim analogue of `Type[Highlighter]` (a class object is not
## storable; the factory `() => ReprHighlighter()` is the faithful callable
## form, set in the Body). Naming: `__init__`→`initRichHandler`;
## `get_level_text`→`getLevelText`; `render_message`→`renderMessage`; `_log_render`→`logRender`;
## `_log_render`-param → `logTimeFormat`. The `emit`/`render`/`render_message`
## return `ConsoleRenderable` → `RenderableType` (the richbase typeclass, as
## `live.nim`'s `renderable` does). Proc bodies mirror the Python source.

import std/options
import std/times
import std/strutils

import segment      # richbase (ConsoleOptions, RenderResult, RenderableType,
                    # RenderableBase, …) + Style.
import console      # Console (logging.py:12,124; real console type).
import highlighter  # Highlighter (logging.py:13,127), ReprHighlighter
                    # (logging.py:20, the HIGHLIGHTER_CLASS default).
import text         # Text (logging.py:21; get_level_text/render return).
import traceback    # Traceback (logging.py:14; the render `traceback` param).
import api_types    # RenderableValue (the render `messageRenderable` param handle).
import table       # Table grid (LogRender.__call__ output; the `render` return).
import box         # Box, none(Box) (Table.grid sets box=None).
import padding     # PaddingDimensions (Table.grid padding=(0,1)).
import style       # StyleOpt, sokStr (Table grid column styles).

type
  LogRender* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `rich._log_render.LogRender`
    ## (logging.py:19). The `_log_render` private helper is not yet ported; this
    ## `ref object of RootObj` placeholder lets the `_logRender` field declare
    ## its type now. Removed/replaced by `import`ing a real `log_render.nim`
    ## when that helper lands (body). NOT a faithful port of `LogRender`.

  LogRecord* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for Python's `logging.LogRecord`
    ## (logging.py:6). A stdlib type with many fields (`levelname`/`pathname`/
    ## `lineno`/`created`/`exc_info`/`getMessage`/…) used in `emit`/`render`/
    ## `get_level_text` bodies; a faithful port is a Body concern. This
    ## `ref object of RootObj` placeholder lets the `record` params declare
    ## their type now. NOT a faithful port of `LogRecord`.
    levelname*: string
      ## rich logging.py — `record.levelname` (the level name, e.g. "INFO"/
      ## "WARNING"); consumed by `getLevelText` (`Text.styled(levelname.ljust(8),
      ## f"logging.level.{levelname.lower()}")`, logging.py:132-134). The only
      ## field the Slice 11 golden path needs (show_time=False/show_path=False
      ## elide `created`/`pathname`/`lineno`); the remaining stdlib fields stay
      ## deferred.

  FormatTimeCallable* = proc(dt: DateTime): Text {.closure.}
    ## rich logging.py:11 — `_log_render.FormatTimeCallable = Union[TimeFormatter,
    ## Callable[[datetime], Text]]` where `TimeFormatter = Callable[[datetime],
    ## str]`. Modelled as a closure proc `proc(dt: DateTime): Text` (the `Text`
    ## return subsumes the `str` arm via `Text`). The `_log_render` helper is not
    ## yet ported; this is the Nim analogue used by the `logTimeFormat` union.

  LogLevelKind* = enum
    ## [Nim-only discriminator] for `LogLevel` — the two arms of `Union[int,
    ## str]` (logging.py:71, `level: Union[int, str] = logging.NOTSET`).
    llInt   ## the `int` arm (`logging.NOTSET` = 0, a numeric level).
    llStr   ## the `str` arm (a named level like `"INFO"`).

  LogLevel* = object
    ## rich logging.py:71 — `level: Union[int, str] = logging.NOTSET` as a Nim
    ## case object (non-narrowing). `default(LogLevel)` = `llInt(0)` =
    ## `logging.NOTSET` (the rich default — NOTSET is 0).
    case kind*: LogLevelKind
    of llInt:
      i*: int       ## the `int` arm — a numeric log level (`logging.NOTSET`=0).
    of llStr:
      s*: string    ## the `str` arm — a named level (`"INFO"`, `"WARNING"`, …).

  LogTimeFormatKind* = enum
    ## [Nim-only discriminator] for `LogTimeFormat` — the two arms of
    ## `Union[str, FormatTimeCallable]` (logging.py:99, `log_time_format`).
    ltfStr       ## the `str` arm — a `strftime` format string (`"[%x %X]"`).
    ltfCallable  ## the `FormatTimeCallable` arm — a `proc(dt): Text`.

  LogTimeFormat* = object
    ## rich logging.py:99 — `log_time_format: Union[str, FormatTimeCallable] =
    ## "[%x %X]"` as a Nim case object (non-narrowing). Default
    ## `LogTimeFormat(kind: ltfStr, strv: "[%x %X]")` (the rich default).
    case kind*: LogTimeFormatKind
    of ltfStr:
      strv*: string             ## the `str` arm — a `strftime` format string.
    of ltfCallable:
      callable*: FormatTimeCallable  ## the callable arm — `proc(dt: DateTime): Text`.

  TracebackSuppressKind* = enum
    ## [Nim-only discriminator] for `TracebackSuppress` — the two arms of
    ## `Union[str, ModuleType]` (logging.py:89, `tracebacks_suppress:
    ## Iterable[Union[str, ModuleType]]`).
    tsStr     ## the `str` arm — a module/path name to suppress.
    tsModule  ## the `ModuleType` arm — a module object to suppress.

  TracebackSuppress* = object
    ## rich logging.py:89 — `Union[str, ModuleType]` (an element of
    ## `tracebacks_suppress`) as a Nim case object (non-narrowing). `ModuleType`
    ## → `RootRef` opaque handle (a Python module object has no Nim equivalent
    ## in scope).
    case kind*: TracebackSuppressKind
    of tsStr:
      s*: string        ## the `str` arm — a module/path name.
    of tsModule:
      m*: RootRef       ## the `ModuleType` arm — an opaque module-object handle.

  HighlighterFactory* = proc(): Highlighter {.closure.}
    ## [Nim-only] the callable analogue of `ClassVar[Type[Highlighter]]`
    ## (logging.py:71, `HIGHLIGHTER_CLASS: ClassVar[Type[Highlighter]] =
    ## ReprHighlighter`). A class object (`Type[Highlighter]`) is not storable in
    ## Nim; the factory `proc(): Highlighter` is the faithful callable form
    ## (`self.HIGHLIGHTER_CLASS()` constructs an instance, logging.py:127). The
    ## `highlighterClass` placeholder is `default(HighlighterFactory)`
    ## (`nil`); body sets it to `() => (a ReprHighlighter instance)`.

  RichHandler* = ref object of RootObj
    ## rich logging.py:24-247 — `class RichHandler(Handler)`: a logging handler
    ## rendering records with Rich. `ref object of RootObj` (the `logging.Handler`
    ## base is modelled via `RootObj`; the `level`/`format`/`handle`
    ## infrastructure is a Body concern). Fields mirror the `__init__`
    ## assignments (logging.py:124-145).
    console*: Console
      ## rich logging.py:124-124 — `self.console = console or get_console()` (`Console`; default `nil` ⇒ body uses `get_console()`).
    highlighter*: Highlighter
      ## rich logging.py:127-127 — `self.highlighter = highlighter or self.HIGHLIGHTER_CLASS()` (`Highlighter`; default `nil` ⇒ body uses `highlighterClass()`).
    logRender*: LogRender
      ## rich logging.py:128-135 — `self._log_render = LogRender(show_time=…, show_level=…, show_path=…, time_format=…, omit_repeated_times=…, level_width=None)` (the forward `LogRender` handle; renamed `_log_render`→`logRender`).
    enableLinkPath*: bool
      ## rich logging.py:136-136 — `self.enable_link_path = enable_link_path` (`bool`; default `True`).
    markup*: bool
      ## rich logging.py:137-137 — `self.markup = markup` (`bool`; default `False`).
    richTracebacks*: bool
      ## rich logging.py:138-138 — `self.rich_tracebacks = rich_tracebacks` (`bool`; default `False`).
    tracebacksWidth*: Option[int]
      ## rich logging.py:139-139 — `self.tracebacks_width = tracebacks_width` (`Optional[int]`; `Option[int]`, default `none(int)`).
    tracebacksExtraLines*: int
      ## rich logging.py:140-140 — `self.tracebacks_extra_lines = tracebacks_extra_lines` (`int`; default `3`).
    tracebacksTheme*: Option[string]
      ## rich logging.py:141-141 — `self.tracebacks_theme = tracebacks_theme` (`Optional[str]`; `Option[string]`, default `none(string)`).
    tracebacksWordWrap*: bool
      ## rich logging.py:142-142 — `self.tracebacks_word_wrap = tracebacks_word_wrap` (`bool`; default `True`).
    tracebacksShowLocals*: bool
      ## rich logging.py:143-143 — `self.tracebacks_show_locals = tracebacks_show_locals` (`bool`; default `False`).
    tracebacksSuppress*: seq[TracebackSuppress]
      ## rich logging.py:144-144 — `self.tracebacks_suppress = tracebacks_suppress` (`Iterable[Union[str, ModuleType]]`; `seq[TracebackSuppress]`, default `@[]`).
    tracebacksMaxFrames*: int
      ## rich logging.py:145-145 — `self.tracebacks_max_frames = tracebacks_max_frames` (`int`; default `100`).
    tracebacksCodeWidth*: Option[int]
      ## rich logging.py:130-130 — `self.tracebacks_code_width = tracebacks_code_width` (`Optional[int] = 88`; `Option[int]`, default `some(88)`).
    localsMaxLength*: int
      ## rich logging.py:146-146 — `self.locals_max_length = locals_max_length` (`int`; default `10`).
    localsMaxString*: int
      ## rich logging.py:147-147 — `self.locals_max_string = locals_max_string` (`int`; default `80`).
    keywords*: Option[seq[string]]
      ## rich logging.py:148-148 — `self.keywords = keywords` (`Optional[List[str]]`; `Option[seq[string]]`, default `none(seq[string])`).
    showTime*: bool
      ## [Nim-only] cached `show_time` (logging.py:128 → `LogRender.show_time`);
      ## the `LogRender` placeholder is fieldless, so the render flags are stored
      ## on the handler for the Slice 11 `render` Table-grid construction.
    showLevel*: bool
      ## [Nim-only] cached `show_level` (logging.py:129 → `LogRender.show_level`).
    showPath*: bool
      ## [Nim-only] cached `show_path` (logging.py:130 → `LogRender.show_path`).
    levelWidth*: int
      ## [Nim-only] cached `level_width` (`LogRender` default `8`,
      ## logging.py:135 → `LogRender.level_width`).

const KEYWORDS* = ["GET", "POST", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE",
                   "PATCH"]
  ## rich logging.py:60-69 — `RichHandler.KEYWORDS: ClassVar[Optional[List[str]]]`:
  ## the 8 HTTP-method words highlighted in log messages (logging.py:212). The
  ## `ClassVar` becomes a module `const` (a class-level immutable value).
  ## Verbatim 8-element list.

let highlighterClass* = default(HighlighterFactory)
  ## rich logging.py:71-71 — `RichHandler.HIGHLIGHTER_CLASS: ClassVar[
  ## Type[Highlighter]] = ReprHighlighter`: the default highlighter class. The
  ## `ClassVar[Type[Highlighter]]` (a class object) becomes a `HighlighterFactory`
  ## (the callable analogue — `self.HIGHLIGHTER_CLASS()` constructs an instance,
  ## logging.py:127). placeholder (`default(HighlighterFactory)` = `nil`);
  ## body sets it to `() => (a ReprHighlighter instance)`.

proc initLogRecord*(levelname: string): LogRecord =
  ## [Nim-only] construct a `LogRecord` with just the `levelname` field (the
  ## only field the Slice 11 golden path needs — show_time=False/show_path=False
  ## elide `created`/`pathname`/`lineno`). A faithful port of Python's
  ## `logging.LogRecord` (with all stdlib fields) stays deferred.
  result = LogRecord()
  result.levelname = levelname

proc initRichHandler*(level: LogLevel = default(LogLevel), console: Console = nil,
                      showTime: bool = true, omitRepeatedTimes: bool = true,
                      showLevel: bool = true, showPath: bool = true,
                      enableLinkPath: bool = true,
                      highlighter: Option[Highlighter] = none(Highlighter),
                      markup: bool = false, richTracebacks: bool = false,
                      tracebacksWidth: Option[int] = none(int),
                      tracebacksCodeWidth: Option[int] = some(88),
                      tracebacksExtraLines: int = 3,
                      tracebacksTheme: Option[string] = none(string),
                      tracebacksWordWrap: bool = true,
                      tracebacksShowLocals: bool = false,
                      tracebacksSuppress: openArray[TracebackSuppress] = @[],
                      tracebacksMaxFrames: int = 100,
                      localsMaxLength: int = 10, localsMaxString: int = 80,
                      logTimeFormat: LogTimeFormat = LogTimeFormat(
                          kind: ltfStr, strv: "[%x %X]"),
                      keywords: Option[seq[string]] = none(seq[string])): RichHandler =
  ## rich logging.py:71-121 — `RichHandler.__init__(self, level: Union[int, str]
  ## = logging.NOTSET, console: Optional[Console] = None, *, show_time=True,
  ## omit_repeated_times=True, show_level=True, show_path=True,
  ## enable_link_path=True, highlighter: Optional[Highlighter] = None, markup=
  ## False, rich_tracebacks=False, tracebacks_width=None, tracebacks_code_width=
  ## 88, tracebacks_extra_lines=3, tracebacks_theme=None, tracebacks_word_wrap=
  ## True, tracebacks_show_locals=False, tracebacks_suppress=(),
  ## tracebacks_max_frames=100, locals_max_length=10, locals_max_string=80,
  ## log_time_format="[%x %X]", keywords=None) -> None`: `super().__init__(
  ## level=level)`, set `self.console = console or get_console()`,
  ## `self.highlighter = highlighter or self.HIGHLIGHTER_CLASS()`, build
  ## `self._log_render = LogRender(...)`, store all fields (logging.py:122-145).
  ## Keyword-only after `console` (Python `*`, logging.py:73). `level:
  ## Union[int, str] = NOTSET` → `LogLevel` (`default(LogLevel)` = `llInt(0)` =
  ## NOTSET); `console: Optional[Console] = None` → `Console = nil`;
  ## `highlighter: Optional[Highlighter] = None` → `Option[Highlighter]`;
  ## `tracebacks_code_width: Optional[int] = 88` → `some(88)`; `log_time_format:
  ## Union[str, FormatTimeCallable] = "[%x %X]"` → `LogTimeFormat(kind: ltfStr,
  ## strv: "[%x %X]")`; `tracebacks_suppress: Iterable[…] = ()` →
  ## `openArray[TracebackSuppress] = @[]`.
  result = RichHandler()
  # `super().__init__(level=level)` (logging.py:122) — the `logging.Handler`
  # base init is a Body concern (base `level`/`format`/`handle` not
  # modelled); the `level`/`showTime`/`omitRepeatedTimes`/`showLevel`/`showPath`/
  # `logTimeFormat` params feed the base + `LogRender` construction, both
  # deferred.
  # `console or get_console()` (logging.py:124): `get_console()` is body-only
  # (not imported) → store `console` as-is (nil if not given).
  result.console = console
  # `highlighter or self.HIGHLIGHTER_CLASS()` (logging.py:127): the
  # `highlighterClass` factory is a `nil` placeholder → use the passed
  # highlighter if given, else the zero-init `nil` (factory deferred).
  if highlighter.isSome:
    result.highlighter = highlighter.get
  # `self._log_render = LogRender(show_time=…, …)` (logging.py:128-135):
  # `LogRender` is a forward placeholder (no fields); allocate it — the real
  # parametrised construction is deferred.
  result.logRender = LogRender()
  result.enableLinkPath = enableLinkPath
  result.markup = markup
  result.richTracebacks = richTracebacks
  result.tracebacksWidth = tracebacksWidth
  result.tracebacksExtraLines = tracebacksExtraLines
  result.tracebacksTheme = tracebacksTheme
  result.tracebacksWordWrap = tracebacksWordWrap
  result.tracebacksShowLocals = tracebacksShowLocals
  result.tracebacksSuppress = @tracebacksSuppress
  result.tracebacksMaxFrames = tracebacksMaxFrames
  result.tracebacksCodeWidth = tracebacksCodeWidth
  result.localsMaxLength = localsMaxLength
  result.localsMaxString = localsMaxString
  result.keywords = keywords
  # Slice 11: cache the render flags on the handler (the `LogRender` placeholder
  # is fieldless, so `render`'s Table-grid construction reads them from here).
  result.showTime = showTime
  result.showLevel = showLevel
  result.showPath = showPath
  result.levelWidth = 8

proc getLevelText*(self: RichHandler, record: LogRecord): Text =
  ## rich logging.py:123-136 — `RichHandler.get_level_text(self, record:
  ## LogRecord) -> Text`: `Text.styled(level_name.ljust(8),
  ## f"logging.level.{level_name.lower()}")` (logging.py:132-134). Returns
  ## `Text`. Body needs `LogRecord.levelname`.
  # Slice 11: implemented — `LogRecord.levelname` is now a field.
  # `Text.styled(level_name.ljust(8), f"logging.level.{level_name.lower()}")`
  # (logging.py:132-134). The level name is left-justified to width 8 (Python
  # `str.ljust`) and styled via the theme name `logging.level.<lower>`.
  let levelName = record.levelname
  let padded = if levelName.len >= 8: levelName
               else: levelName & repeat(' ', 8 - levelName.len)
  result = initText(padded, style = "logging.level." & levelName.toLowerAscii())

proc emit*(self: RichHandler, record: LogRecord) =
  ## rich logging.py:138-188 — `RichHandler.emit(self, record: LogRecord) ->
  ## None`: format the message, build a `Traceback` (if `rich_tracebacks` and
  ## `record.exc_info`), render the message + log renderable, and
  ## `self.console.print(log_renderable)` (or `handleError` on `NullFile`)
  ## (logging.py:143-187). Body needs `LogRender`, `Traceback`,
  ## `Console.print`, `NullFile`.
  # DEFERRED(LogRender/Console/NullFile/LogRecord, later batch): the faithful
  # `emit` (logging.py:138-188) formats the message (`self.format` — the
  # `logging.Handler.format` base, not modelled), builds a `Traceback` (if
  # `rich_tracebacks` and `record.exc_info`), renders via `self.renderMessage`/
  # `self.render`/`self._log_render`, and `self.console.print(...)`. Five
  # blockers — the `LogRecord` placeholder (no `exc_info`/`getMessage`/`created`/
  # `pathname` fields), `LogRender` placeholder, `Console.print`, `NullFile`,
  # and the `Handler` base. No-op until wired.
  discard

proc renderMessage*(self: RichHandler, record: LogRecord, message: string): RenderableType =
  ## rich logging.py:190-213 — `RichHandler.render_message(self, record:
  ## LogRecord, message: str) -> ConsoleRenderable`: build `Text.from_markup` or
  ## `Text(message)` (per `markup`), apply the highlighter, highlight
  ## `self.keywords` (logging.py:204-212). `message: str` → `string`; returns
  ## `RenderableType` (the `ConsoleRenderable` typeclass).
  # DEFERRED(highlighter/markup, later batch): the faithful port (logging.py:190-213)
  # builds `Text.from_markup(message)` (if `markup`) or `Text(message)`, applies
  # the highlighter (`self.highlighter(message)` — a stub), and highlights
  # `self.keywords`. `Text.from_markup`/`highlighter.call` are stubs (return
  # `nil`); return the raw `message` (a valid `RenderableType` `str` arm) as a
  # safe stand-in until highlighting is wired.
  result = message

proc rvToRowOpt(rv: RenderableValue): RenderableOpt =
  ## [Nim-only helper] `RenderableValue` → `RenderableOpt` (the `add_row` cell
  ## handle): `rvString`→`roStr`, `rvConsoleRenderable`/`rvRichCast`→`roRenderable`.
  case rv.kind
  of rvString:
    result = RenderableOpt(kind: roStr, strv: rv.textStr)
  of rvConsoleRenderable:
    result = RenderableOpt(kind: roRenderable, renderablev: rv.consoleItem)
  of rvRichCast:
    result = RenderableOpt(kind: roRenderable, renderablev: rv.castItem)

proc render*(self: RichHandler, record: LogRecord, traceback: Option[Traceback],
             messageRenderable: RenderableValue): Table =
  ## rich logging.py:215-247 + `_log_render.LogRender.__call__`
  ## (_log_render.py:43-103): build the log renderable as a `Table.grid` (no
  ## box, expand=True) with a `log.level` column (width=`levelWidth`,
  ## show_level) and a `log.message` column (ratio=1, overflow=fold); the row is
  ## [level, message] (show_time/show_path elided when False). Returns the
  ## `Table` (a real renderable); the caller renders it through a `Console`
  ## whose theme resolves `logging.level.*` and `log.*` styles (matching Python
  ## rich 15.0.0 `DEFAULT_STYLES`: `logging.level.info`=blue,
  ## `logging.level.warning`=yellow, `log.level`/`log.message`=none).
  result = initTable(box = none(Box),
                     padding = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                     collapsePadding = true, padEdge = false, expand = true,
                     showHeader = false, showEdge = false, showFooter = false)
  if self.showLevel:
    result.addColumn(style = StyleOpt(kind: sokStr, strv: "log.level"),
                     width = some(self.levelWidth))
  result.addColumn(style = StyleOpt(kind: sokStr, strv: "log.message"),
                   overflow = omFold, ratio = some(1))
  let level = self.getLevelText(record)
  let msgOpt = rvToRowOpt(messageRenderable)
  if self.showLevel:
    result.addRow(RenderableOpt(kind: roRenderable, renderablev: level),
                  msgOpt, style = default(StyleOpt), endSection = false)
  else:
    result.addRow(msgOpt, style = default(StyleOpt), endSection = false)
