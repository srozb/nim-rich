## Port of `rich.progress` (rich/progress.py).
##
## `Progress` renders an auto-updating progress display of one or more `Task`s
## as a `Table` of `ProgressColumn`s, driven by a `Live` (progress.py:1061-
## 1644). The module also exports 13 column widgets (`ProgressColumn` ABC +
## `TextColumn`/`BarColumn`/`SpinnerColumn`/…, progress.py:507-924), the
## `Task`/`ProgressSample` dataclasses (progress.py:926-1059), the `track`
## iterator + `wrap_file`/`open` helpers (progress.py:104-506), and the private
## `_TrackThread`/`_Reader`/`_ReadContext` helpers (progress.py:64-305).
##
## Import graph (rich/progress.py:1-52): runtime sibling imports are `io`/
## `typing`/`warnings`/`abc`/`collections.deque`/`dataclasses`/
## `datetime.timedelta`/`io.RawIOBase`/`math.ceil`/`mmap`/
## `operator.length_hint`/`os.PathLike`/`os.stat`/`threading.{Event,RLock,
## Thread}`/`types.TracebackType`/`typing.{…}` (progress.py:1-39,41);
## `from . import filesize, get_console` (progress.py:43), `from .console
## import Console, Group, JustifyMethod, RenderableType` (progress.py:44),
## `from .highlighter import Highlighter` (progress.py:45), `from .jupyter
## import JupyterMixin` (progress.py:46), `from .live import Live`
## (progress.py:47), `from .progress_bar import ProgressBar` (progress.py:48),
## `from .spinner import Spinner` (progress.py:49), `from .style import
## StyleType` (progress.py:50), `from .table import Column, Table`
## (progress.py:51), `from .text import Text, TextType` (progress.py:52).
##
## wiring (this file):
##   `import std/options`   — `Option[float]`/`Option[int]`/`Option[string]`/
##                           `Option[bool]`/`Option[TaskID]`/`Option[
##                           Highlighter]`/`Option[GetTimeCallable]`.
##   `import std/tables`     — `Table` (`_tasks`, `_renderable_cache`).
##   `import std/deques`     — `Deque` (`Task._progress`, maxlen 1000).
##   `import std/locks`      — `Lock` (`Progress._lock`/`Task._lock`,
##                           `threading.RLock`).
##   `import segment`        — re-exports `richbase` (`ConsoleHandle`,
##                           `RenderableType`, `RenderableBase`, `JustifyMethod`,
##                           …) + `Style`.
##   `import style`          — `StyleType` (typeclass) + `StyleOpt`
##                           (`Optional[StyleType]` for `SpinnerColumn.style`).
##   `import text`           — `Text`, `TextType`, `StyleValue` (`Union[str,
##                           Style]` field handle for the `BarColumn`/
##                           `TextColumn` `style` fields).
##   `import table`          — `Table`, `Column` (progress.py:51).
##   `import progress_bar`   — `ProgressBar` (progress.py:48).
##   `import spinner`        — `Spinner` (progress.py:49).
##   `import live`           — `Live` (progress.py:47).
##   `import api_types`      — `RenderableValue` (storable `RenderableType`) +
##                           `Meta` (`Dict[str, Any]` for the `**fields` params).
## `filesize` (progress.py:43), `Console`/`Group` (progress.py:44),
## `Highlighter` (progress.py:45), `JupyterMixin` (progress.py:46) and the
## `io.*`/`os.*`/`mmap`/`PathLike` stdlib types are LATER-wave modules /
## BODY-only deps: `Console` → the `ConsoleHandle` placeholder (richbase);
## `JupyterMixin` modelled via `RenderableBase`; `Group` is BODY-only
## (progress.py:1554); `Highlighter` is a private `ref object of RenderableBase`
## placeholder (a [NON-NARROWING PROVISIONAL FORWARD HANDLE], removed when
## `highlighter.nim` is imported in body); `filesize` is BODY-only
## (progress.py:741,824,833,881,919); `io.BinaryIO`/`io.TextIO`/`RawIOBase` → a
## private `BinaryIo` `ref object of RootObj` placeholder (a [NON-NARROWING
## PROVISIONAL FORWARD HANDLE]); `os.PathLike`/`bytes` (`open`'s `file`,
## progress.py:421) → simplified to `string` (the `str` arm).
##
## `TaskID = NewType("TaskID", int)` (progress.py:62) → `distinct int`.
## `ProgressType`/`_I` (TypeVars) → Nim generics on `track` (the `_ReadContext`
## generic is dropped in the stub). `GetTimeCallable = Callable[[], float]`
## (progress.py:65) → `proc(): float {.closure.}`. `*columns: Union[str,
## ProgressColumn]` (progress.py:1078) → `varargs[ColumnArg]` (a case object
## with `toColumnArg*` converters). `**fields: Any` (`update`/`reset`/`add_task`)
## → `fields: Meta = default(Meta)` (Nim has no `**kwargs`).
##
## Naming: `__init__`→`initT`, `__rich__`→`richCast`, `__enter__`/`__exit__`→
## `enter`/`exit`, `__call__`→`call`, `__iter__`→`iter`, `__next__`→`next`,
## `get_default_columns`→`getDefaultColumns`, `get_renderable(s)`→
## `getRenderable(s)`, `make_tasks_table`→`makeTasksTable`,
## `start_task`/`stop_task`/`add_task`/`remove_task`→`startTask`/`stopTask`/
## `addTask`/`removeTask`, `wrap_file`→`wrapFile`, `task_id`→`taskId`,
## `_tasks`→`tasksMap`, `_task_index`→`taskIndex`, `_get_time`→`getTime`,
## `_reset`→`taskReset`, `_renderable_cache`→`renderableCache`,
## `_update_time`→`updateTime`, `max_refresh`→`maxRefresh`, `bar_width`→
## `barWidth`, `spinner_name`→`spinnerName`, `text_format(_no_percentage)`→
## `textFormat(NoPercentage)`, `binary_units`→`binaryUnits`,
## `elapsed_when_finished`→`elapsedWhenFinished`, `show_speed`→`showSpeed`,
## `speed_estimate_period`→`speedEstimatePeriod`, `auto_refresh`→`autoRefresh`,
## `refresh_per_second`→`refreshPerSecond`, `redirect_stdout`/`redirect_stderr`→
## `redirectStdout`/`redirectStderr`, `get_time`→`getTime`. The private
## `_TrackThread`/`_Reader`/`_ReadContext` classes + their methods are
## module-private (no `*`). `print`/`log` (Python bound-method attrs,
## progress.py:1111-1112) are modelled as stub method procs `print*`/`log*`.
## Proc bodies mirror the Python source.

{.experimental: "codeReordering".}

import std/options
import std/tables
import std/deques
from std/os import getFileSize  # `os.stat(file).st_size` for `open`'s total
                                # (progress.py:1361); selective import —
                                # `os.open` would clash with the `open*` procs.
import bar          # ProgressBar base (frozen).
import progress_bar # ProgressBar (frozen).

import segment      # richbase (ConsoleHandle, RenderableType, RenderableBase,
                    # JustifyMethod, …) + Style.
import style        # StyleType (typeclass) + StyleOpt (Optional[StyleType]).
import text         # Text, TextType, StyleValue (Union[str, Style] field handle).
import table        # Table, Column.
import progress_bar # ProgressBar.
import filesize    # pickUnitAndSuffix*, formatFloatCommas* (consolidated from local copies).
import spinner      # Spinner.
import live         # Live.
import api_types    # RenderableValue (storable RenderableType) + Meta (Dict[str, Any]).
import std/strutils  # align, repeat, startsWith, join — the format helpers below.
import std/times     # epochTime — the `get_time` fallback clock (`self.console.
                    # get_time` is deferred behind the opaque `ConsoleHandle`).
import std/math      # ceil — `Task.time_remaining` (progress.py:1046).
import std/locks     # withLock/initLock — `Progress._lock`/`Task._lock` (RLock).
import std/hashes    # Hash — the `TaskID` `hash` borrow (a `Table` key).
import std/json      # JsonNode accessors — `formatTask` `task.fields[<key>]`.
import padding       # toPaddingDimensions/PaddingDimensions — `Table.grid(
                    # padding=(0,1))` (progress.py:1577).
import filesize      # `decimal` — FileSize/TotalFileSize/TransferSpeed columns
                    # (progress.py:825,833,921). `filesize.pick_unit_and_suffix`
                    # is module-private, so a local `pickUnitAndSuffix` re-implements it.
from console import Group, initGroup, Console, print, log  # Group — `Progress.get_renderable`
                    # (progress.py:1553); `print`/`log` — `Progress.print`/`.log`/`.stop` delegate
                    # to `Console.print`/`.log` (progress.py:1112,1175-1177); `console` does NOT
                    # import `progress` (cycle-free) and does NOT import `jupyter` .

type
  TaskID* = distinct int
    ## rich progress.py:62-62 — `TaskID = NewType("TaskID", int)`: an opaque
    ## task identifier returned by `add_task` and passed to `update`/`advance`/
    ## … A faithful Nim `distinct int`; hashable as a `Table` key.

  GetTimeCallable* = proc(): float {.closure.}
    ## rich progress.py:65-65 — `GetTimeCallable = Callable[[], float]`: a
    ## no-arg clock callback returning seconds. Modelled as a Nim closure proc.

  Highlighter* = ref object of RenderableBase
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `rich.highlighter.
    ## Highlighter` (progress.py:45). `highlighter.nim` is a LATER-wave module
    ## not yet written; this `ref object of RenderableBase` placeholder lets
    ## `TextColumn.highlighter` (and `TaskProgressColumn`'s inherited field)
    ## declare their `Optional[Highlighter]` type now. Removed — replaced by
    ## `import highlighter` — once `highlighter.nim` exists (body). NOT a
    ## faithful port of `Highlighter`; do not extend it.

  BinaryIo* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `io.BinaryIO` /
    ## `io.TextIO` / `io.RawIOBase` (progress.py:182,245,278,1237,1293,1311 …).
    ## The stdlib IO protocols have no Nim equivalent in scope; this `ref object
    ## of RootObj` placeholder lets `_Reader.handle`, `wrap_file`/`open`
    ## returns and `_ReadContext.reader` declare their IO types now.
    ## Removed/replaced once a real IO handle is available (body).

type
  ProgressSample* = tuple[timestamp: float, completed: float]
    ## rich progress.py:926-934 — `class ProgressSample(NamedTuple)`: a sample
    ## of progress for a given time. Modelled as a Nim named `tuple` (faithful
    ## to `NamedTuple`); fields `timestamp`/`completed` (progress.py:927,932).

  Task* = ref object of RootObj
    ## rich progress.py:936-1059 — `@dataclass class Task`: information about a
    ## progress task (read-only outside `Progress`). `ref object of RootObj`
    ## (Python `class` ⇒ reference semantics; not a renderable). Fields mirror
    ## the dataclass fields (progress.py:940-981).
    id*: TaskID                   ## rich progress.py:940-940 — `id: TaskID`.
    description*: string          ## rich progress.py:943-943 — `description: str`.
    total*: Option[float]         ## rich progress.py:946-946 — `total: Optional[float]`.
    completed*: float             ## rich progress.py:949-949 — `completed: float`.
    getTime*: GetTimeCallable     ## rich progress.py:952-952 — `_get_time: GetTimeCallable` (renamed `_get_time`→`getTime`).
    finishedTime*: Option[float]  ## rich progress.py:955-955 — `finished_time: Optional[float] = None`.
    visible*: bool                ## rich progress.py:958-958 — `visible: bool = True`.
    fields*: Meta                 ## rich progress.py:960-960 — `fields: Dict[str, Any] = field(default_factory=dict)` (`Meta`).
    startTime*: Option[float]     ## rich progress.py:963-963 — `start_time: Optional[float] = field(default=None, init=False, repr=False)`.
    stopTime*: Option[float]       ## rich progress.py:966-966 — `stop_time: Optional[float] = field(default=None, init=False, repr=False)`.
    finishedSpeed*: Option[float]  ## rich progress.py:969-969 — `finished_speed: Optional[float] = None`.
    progress*: Deque[ProgressSample]
      ## rich progress.py:972-974 — `_progress: Deque[ProgressSample] = field(
      ## default_factory=lambda: deque(maxlen=1000), init=False, repr=False)`
      ## (renamed `_progress`→`progress`; `Deque[ProgressSample]`, maxlen 1000).
    lock*: Lock
      ## rich progress.py:976-977 — `_lock: RLock = field(repr=False,
      ## default_factory=RLock)` (renamed `_lock`→`lock`; `std/locks.Lock`).

  ProgressColumn* = ref object of RenderableBase
    ## rich progress.py:507-547 — `class ProgressColumn(ABC)`: base class for a
    ## progress column widget. `ref object of RenderableBase` (Python reference
    ## semantics; `ABC` modelled via `RenderableBase`). Fields mirror `__init__`
    ## (progress.py:516-519) plus the `max_refresh` class attr (progress.py:510).
    tableColumn*: Option[Column]
      ## rich progress.py:517-517 — `self._table_column = table_column`
      ## (`Optional[Column] = None`; `Option[Column]`, default `none(Column)`).
    renderableCache*: tables.Table[TaskID, tuple[updateTime: float, renderable: RenderableValue]]
      ## rich progress.py:518-518 — `self._renderable_cache: Dict[TaskID,
      ## Tuple[float, RenderableType]] = {}` (the `__call__` cache).
    updateTime*: Option[float]
      ## rich progress.py:519-519 — `self._update_time: Optional[float] = None`.
    maxRefresh*: Option[float]
      ## rich progress.py:510-510 — `max_refresh: Optional[float] = None` (a
      ## class attribute; modelled as an instance field, default `none(float)`;
      ## `TimeRemainingColumn` overrides it to `some(0.5)`).

  RenderableColumn* = ref object of ProgressColumn
    ## rich progress.py:549-563 — `class RenderableColumn(ProgressColumn)`: a
    ## column that inserts an arbitrary renderable (progress.py:559).
    renderable*: RenderableValue
      ## rich progress.py:559-559 — `self.renderable = renderable`
      ## (`RenderableType = ""`; the `api_types.RenderableValue` handle).

  SpinnerColumn* = ref object of ProgressColumn
    ## rich progress.py:566-614 — `class SpinnerColumn(ProgressColumn)`: a
    ## column with a spinner animation (progress.py:583-590).
    spinnerHandle*: Spinner
      ## rich progress.py:583-583 — `self.spinner = Spinner(spinner_name,
      ## style=style, speed=speed)` (`Spinner`; renamed `spinner`→`spinnerHandle`
      ## to avoid shadowing the imported `spinner` module).
    finishedText*: RenderableValue
      ## rich progress.py:584-588 — `self.finished_text = …` (`TextType = " "`;
      ## the `RenderableValue` handle — `Text ⊂ RenderableType`).

  TextColumn* = ref object of ProgressColumn
    ## rich progress.py:616-644 — `class TextColumn(ProgressColumn)`: a column
    ## containing text (progress.py:627-633).
    textFormat*: string           ## rich progress.py:627-627 — `self.text_format = text_format` (`str`).
    justify*: JustifyMethod       ## rich progress.py:628-628 — `self.justify: JustifyMethod = justify` (default `jmLeft`).
    style*: StyleValue            ## rich progress.py:629-629 — `self.style = style` (`StyleType = "none"`; `StyleValue`).
    markup*: bool                 ## rich progress.py:630-630 — `self.markup = markup` (`bool`; default `True`).
    highlighter*: Option[Highlighter]
      ## rich progress.py:631-631 — `self.highlighter = highlighter`
      ## (`Optional[Highlighter] = None`; the forward `Highlighter` handle).

  BarColumn* = ref object of ProgressColumn
    ## rich progress.py:646-686 — `class BarColumn(ProgressColumn)`: renders a
    ## visual progress bar (progress.py:658-666).
    barWidth*: Option[int]         ## rich progress.py:658-658 — `self.bar_width = bar_width` (`Optional[int] = 40`; `Option[int]`, default `some(40)`).
    style*: StyleValue             ## rich progress.py:659-659 — `self.style = style` (`StyleType = "bar.back"`; `StyleValue`).
    completeStyle*: StyleValue     ## rich progress.py:660-660 — `self.complete_style = complete_style` (`StyleType = "bar.complete"`; `StyleValue`).
    finishedStyle*: StyleValue     ## rich progress.py:661-661 — `self.finished_style = finished_style` (`StyleType = "bar.finished"`; `StyleValue`).
    pulseStyle*: StyleValue        ## rich progress.py:662-662 — `self.pulse_style = pulse_style` (`StyleType = "bar.pulse"`; `StyleValue`).

  TimeElapsedColumn* = ref object of ProgressColumn
    ## rich progress.py:688-695 — `class TimeElapsedColumn(ProgressColumn)`:
    ## renders time elapsed. No `__init__` (inherits `ProgressColumn.__init__`).

  TaskProgressColumn* = ref object of TextColumn
    ## rich progress.py:700-769 — `class TaskProgressColumn(TextColumn)`: shows
    ## task progress as a percentage (subclass of `TextColumn`,
    ## progress.py:728-733).
    textFormatNoPercentage*: string
      ## rich progress.py:728-728 — `self.text_format_no_percentage =
      ## text_format_no_percentage` (`str`; default `""`).
    showSpeed*: bool
      ## rich progress.py:729-729 — `self.show_speed = show_speed` (`bool`;
      ## default `False`).

  TimeRemainingColumn* = ref object of ProgressColumn
    ## rich progress.py:772-818 — `class TimeRemainingColumn(ProgressColumn)`:
    ## renders estimated time remaining. Overrides `max_refresh = 0.5`
    ## (progress.py:781). Fields mirror `__init__` (progress.py:789-791).
    compact*: bool                ## rich progress.py:789-789 — `self.compact = compact` (`bool`; default `False`).
    elapsedWhenFinished*: bool    ## rich progress.py:790-790 — `self.elapsed_when_finished = elapsed_when_finished` (`bool`; default `False`).

  FileSizeColumn* = ref object of ProgressColumn
    ## rich progress.py:820-826 — `class FileSizeColumn(ProgressColumn)`:
    ## renders completed filesize. No `__init__`.

  TotalFileSizeColumn* = ref object of ProgressColumn
    ## rich progress.py:829-835 — `class TotalFileSizeColumn(ProgressColumn)`:
    ## renders total filesize. No `__init__`.

  MofNCompleteColumn* = ref object of ProgressColumn
    ## rich progress.py:838-862 — `class MofNCompleteColumn(ProgressColumn)`:
    ## renders `completed/total` (progress.py:852).
    separator*: string            ## rich progress.py:852-852 — `self.separator = separator` (`str`; default `"/"`).

  DownloadColumn* = ref object of ProgressColumn
    ## rich progress.py:865-911 — `class DownloadColumn(ProgressColumn)`:
    ## renders downloaded/total size (progress.py:876).
    binaryUnits*: bool            ## rich progress.py:876-876 — `self.binary_units = binary_units` (`bool`; default `False`).

  TransferSpeedColumn* = ref object of ProgressColumn
    ## rich progress.py:914-923 — `class TransferSpeedColumn(ProgressColumn)`:
    ## renders transfer speed. No `__init__`.

type
  ColumnArgKind* = enum
    ## [Nim-only discriminator] for `ColumnArg` — the two arms of `Union[str,
    ## ProgressColumn]` (progress.py:1078-1079, the `*columns` varargs element).
    cakStr     ## the `str`            arm — a column-format string (rendered as a `TextColumn`).
    cakColumn  ## the `ProgressColumn` arm — a column widget instance.

  ColumnArg* = object
    ## rich progress.py:1078-1079 — `Union[str, ProgressColumn]` (the element of
    ## `*columns: Union[str, ProgressColumn]`) as a Nim case object (a true
    ## tagged union) so `Progress.columns` can store a heterogeneous seq. The
    ## `toColumnArg*` converters accept both legal variants (`string`,
    ## `ProgressColumn`); `int` is rejected (not in the union). Nim-only handle.
    case kind*: ColumnArgKind
    of cakStr:
      strv*: string          ## the `str` arm — a column-format string.
    of cakColumn:
      columnv*: ProgressColumn
        ## the `ProgressColumn` arm — a column widget instance (backward ref
        ## to the type declared above).

converter toColumnArg*(x: string): ColumnArg =
  ## Accept a `str` as a `*columns` element (progress.py:1078) — the `cakStr`
  ## arm. Lets `initProgress("desc", barCol)` compile (a `str` column becomes a
  ## `TextColumn` in the body). (`discard` ⇒ `default(ColumnArg)`
  ## = `cakStr` arm); wraps as `ColumnArg(kind: cakStr, strv: x)`.
  ColumnArg(kind: cakStr, strv: x)

converter toColumnArg*(x: ProgressColumn): ColumnArg =
  ## Accept a `ProgressColumn` as a `*columns` element (progress.py:1078) — the
  ## `cakColumn` arm. Lets `initProgress(textCol, barCol)` compile. port
  ## stub (`discard` ⇒ `default(ColumnArg)` = `cakStr` arm); wraps as
  ## `ColumnArg(kind: cakColumn, columnv: x)`.
  ColumnArg(kind: cakColumn, columnv: x)

type
  Progress* = ref object of RenderableBase
    ## rich progress.py:1061-1644 — `class Progress(JupyterMixin)`: renders an
    ## auto-updating progress display. `ref object of RenderableBase` (Python
    ## reference semantics; `JupyterMixin` modelled via `RenderableBase`).
    ## Public fields mirror the public Python attrs (progress.py:1096-1112);
    ## the `_`-prefixed private attrs are module-private (no `*`).
    columns*: seq[ColumnArg]
      ## rich progress.py:1096-1096 — `self.columns = columns or
      ## self.get_default_columns()` (`Tuple[Union[str, ProgressColumn], …]`;
      ## `seq[ColumnArg]`).
    speedEstimatePeriod*: float
      ## rich progress.py:1097-1097 — `self.speed_estimate_period =
      ## speed_estimate_period` (`float`; default `30.0`).
    disable*: bool               ## rich progress.py:1099-1099 — `self.disable = disable` (`bool`; default `False`).
    expand*: bool                ## rich progress.py:1100-1100 — `self.expand = expand` (`bool`; default `False`).
    live*: Live
      ## rich progress.py:1103-1110 — `self.live = Live(console=console or
      ## get_console(), auto_refresh=…, refresh_per_second=…, transient=…,
      ## redirect_stdout=…, redirect_stderr=…, get_renderable=
      ## self.get_renderable)` (`Live`; from `live.nim`).
    getTime*: GetTimeCallable
      ## rich progress.py:1111-1111 — `self.get_time = get_time or
      ## self.console.get_time` (`GetTimeCallable`).
    tasksMap*: tables.Table[TaskID, Task]
      ## rich progress.py:1098-1098 — `self._tasks: Dict[TaskID, Task] = {}`
      ## (renamed `_tasks`→`tasksMap`; the `tasks` name is the public property).
    taskIndex*: TaskID
      ## rich progress.py:1099-1099 — `self._task_index: TaskID = TaskID(0)`
      ## (renamed `_task_index`→`taskIndex`; the next `TaskID` counter).
    lockField*: Lock
      ## rich progress.py:1095-1095 — `self._lock = RLock()` (renamed `_lock`→
      ## `lockField`; `std/locks.Lock`).

  TrackThread = ref object of RootObj
    ## rich progress.py:64-101 — `class _TrackThread(Thread)`: a daemon thread
    ## that periodically updates progress. Module-private (mirrors the
    ## `_`-prefix; the `Thread` base is modelled via Nim `std/threads` in Phase
    ## 1, so `ref object of RootObj` not `of Thread`). Fields mirror `__init__`
    ## (progress.py:67-73).
    progressHandle*: Progress
      ## rich progress.py:67-67 — `self.progress = progress` (the owning
      ## `Progress`; renamed `progress`→`progressHandle`).
    taskId*: TaskID               ## rich progress.py:68-68 — `self.task_id = task_id` (`TaskID`).
    updatePeriod*: float          ## rich progress.py:69-69 — `self.update_period = update_period` (`float`).
    done*: bool
      ## rich progress.py:70-70 — `self.done = Event()` (`threading.Event`);
      ## STUB stand-in `bool` (wait/set/is_set deferred to body).
    completed*: float
      ## rich progress.py:72-72 — `self.completed = 0` (`float`; the running
      ## count advanced by the tracked loop).

  Reader = ref object of RootObj
    ## rich progress.py:182-283 — `class _Reader(RawIOBase, BinaryIO)`: a reader
    ## that tracks progress while read. Module-private (mirrors the `_`-prefix;
    ## `RawIOBase`/`BinaryIO` modelled via the `BinaryIo` forward handle, so
    ## `ref object of RootObj` not `of RawIOBase`). Fields mirror `__init__`
    ## (progress.py:190-195).
    handle*: BinaryIo          ## rich progress.py:190-190 — `self.handle = handle` (`BinaryIO`; the forward `BinaryIo` handle).
    progressHandle*: Progress  ## rich progress.py:191-191 — `self.progress = progress` (`Progress`; renamed `progress`→`progressHandle`).
    task*: TaskID              ## rich progress.py:192-192 — `self.task = task` (`TaskID`).
    closeHandle*: bool         ## rich progress.py:193-193 — `self.close_handle = close_handle` (`bool`; default `True`).
    closed*: bool              ## rich progress.py:195-195 — `self._closed = False` (renamed `_closed`→`closed`).

  ReadContext = ref object of RootObj
    ## rich progress.py:285-304 — `class _ReadContext(ContextManager[_I],
    ## Generic[_I])`: a context manager pairing a reader and a progress.
    ## Module-private (mirrors the `_`-prefix; `Generic[_I]` is dropped in the
    ## stub — `reader` is the opaque `BinaryIo` handle, the `_I`). Fields mirror
    ## `__init__` (progress.py:291-293).
    progressHandle*: Progress  ## rich progress.py:291-291 — `self.progress = progress` (`Progress`; renamed `progress`→`progressHandle`).
    reader*: BinaryIo          ## rich progress.py:292-292 — `self.reader: _I = reader` (`_I = TextIO|BinaryIO`; the forward `BinaryIo` handle).

# ---------------------------------------------------------------------------
# Task
# ---------------------------------------------------------------------------

proc getTime*(self: Task): float =
  ## rich progress.py:983-985 — `Task.get_time(self) -> float`:
  ## `return self._get_time()` (progress.py:984).
  let clock = self.getTime   # within-module dot access → the stored GetTimeCallable field
  result = clock()

proc started*(self: Task): bool =
  ## rich progress.py:987-990 — `Task.started` property: `return self.start_time
  ## is not None` (progress.py:989).
  result = self.startTime.isSome

proc remaining*(self: Task): Option[float] =
  ## rich progress.py:992-997 — `Task.remaining` property: `None` if `total is
  ## None`, else `self.total - self.completed` (progress.py:995-996). port
  ## stub.
  if self.total.isNone:
    result = none(float)
  else:
    result = some(self.total.get - self.completed)

proc elapsed*(self: Task): Option[float] =
  ## rich progress.py:999-1006 — `Task.elapsed` property: `None` if not
  ## started, else `stop_time - start_time` (stopped) or `get_time() -
  ## start_time` (running) (progress.py:1001-1005).
  if self.startTime.isNone:
    result = none(float)
  elif self.stopTime.isSome:
    result = some(self.stopTime.get - self.startTime.get)
  else:
    let clock = self.getTime   # `self.get_time()` → the stored clock callable
    result = some(clock() - self.startTime.get)

proc finished*(self: Task): bool =
  ## rich progress.py:1008-1011 — `Task.finished` property:
  ## `return self.finished_time is not None` (progress.py:1010).
  result = self.finishedTime.isSome

proc percentage*(self: Task): float =
  ## rich progress.py:1013-1020 — `Task.percentage` property: `0.0` if no
  ## total, else `min(100.0, max(0.0, (completed/total)*100.0))`
  ## (progress.py:1016-1019).
  if self.total.isNone or self.total.get == 0.0:
    result = 0.0
  else:
    result = min(100.0, max(0.0, (self.completed / self.total.get) * 100.0))

proc speed*(self: Task): Option[float] =
  ## rich progress.py:1022-1038 — `Task.speed` property: the estimated
  ## steps/second from the `_progress` deque (progress.py:1030-1037), or `None`.
  if self.startTime.isNone:
    result = none(float)
  else:
    withLock self.lock:
      if self.progress.len == 0:
        result = none(float)
      else:
        let totalTime = self.progress[^1].timestamp - self.progress[0].timestamp
        if totalTime == 0.0:
          result = none(float)
        else:
          var totalCompleted = 0.0
          for i in 1 ..< self.progress.len:
            totalCompleted += self.progress[i].completed
          result = some(totalCompleted / totalTime)

proc timeRemaining*(self: Task): Option[float] =
  ## rich progress.py:1040-1052 — `Task.time_remaining` property: `0.0` if
  ## finished, `None` if no speed/total, else `ceil(remaining / speed)`
  ## (progress.py:1045-1051).
  if self.finished:
    result = some(0.0)
  else:
    let sp = self.speed
    if sp.isNone or sp.get == 0.0:
      result = none(float)
    else:
      let rem = self.remaining
      if rem.isNone:
        result = none(float)
      else:
        result = some(ceil(rem.get / sp.get))

proc taskReset*(self: Task) =
  ## rich progress.py:1054-1059 — `Task._reset(self) -> None`: clear
  ## `_progress`, reset `finished_time`/`finished_speed` (progress.py:1056-1058).
  ## Renamed `_reset`→`taskReset` (module-private).
  self.progress.clear()
  self.finishedTime = none(float)
  self.finishedSpeed = none(float)

# ---------------------------------------------------------------------------
# ProgressColumn + the 13 column widgets
# ---------------------------------------------------------------------------

proc initProgressColumn*(tableColumn: Option[Column] = none(Column)): ProgressColumn =
  ## rich progress.py:515-519 — `ProgressColumn.__init__(self, table_column:
  ## Optional[Column] = None) -> None` (progress.py:517-519).
  new(result)
  result.tableColumn = tableColumn
  result.renderableCache = initTable[TaskID, tuple[updateTime: float, renderable: RenderableValue]]()
  result.updateTime = none(float)

proc getTableColumn*(self: ProgressColumn): Column =
  ## rich progress.py:521-523 — `ProgressColumn.get_table_column(self) -> Column`:
  ## `return self._table_column or Column()` (progress.py:522). Returns the
  ## concrete `Column` (from `table.nim`).
  if self.tableColumn.isSome:
    result = self.tableColumn.get
  else:
    result = initColumn()

proc call*(self: ProgressColumn, task: Task): RenderableValue =
  ## rich progress.py:525-543 — `ProgressColumn.__call__(self, task: "Task") ->
  ## RenderableType`: return a cached renderable if within `max_refresh`, else
  ## `self.render(task)` and cache it (progress.py:528-542). Dunder mapping
  ## `__call__`→`call`; returns the faithful `RenderableType` typeclass.
  ## body: cache store/return via RenderableValue bridge — currently
  ## SKIPPED (RenderableValue→RenderableType bridge gap, see align.nim);
  ## returns `self.render(task)` directly (functionally correct, no perf cache).
  let renderable: RenderableValue = self.render(task)
  return renderable

method render*(self: ProgressColumn, task: Task): RenderableValue {.base.} =
  ## rich progress.py:544-546 — `ProgressColumn.render(self, task: "Task") ->
  ## RenderableType` (`@abstractmethod`): should return a renderable. The base
  ## stub; subclasses override with concrete returns.
  # Genuine abstract no-op: Python `@abstractmethod` whose body is just the
  # docstring (progress.py:544-546) — subclasses (`RenderableColumn`,
  # `BarColumn`, …) override. Convention per `RenderHook.process_renderables`
  # (`console.nim`) / `Pager.show` (`pager.nim`).
  discard

proc initRenderableColumn*(renderable: RenderableValue = "",
                           tableColumn: Option[Column] = none(Column)): RenderableColumn =
  ## rich progress.py:556-562 — `RenderableColumn.__init__(self, renderable:
  ## RenderableType = "", *, table_column: Optional[Column] = None)`:
  ## store `renderable`, `super().__init__(table_column=table_column)`
  ## (progress.py:559-561). Keyword-only after `renderable`.
  result = RenderableColumn()
  result.renderable = renderable
  # `super().__init__(table_column=table_column)` (progress.py:561): the
  # inherited `ProgressColumn` fields mirror Python's `__init__` — `_table_column`
  # = the param, `_update_time = None`; `max_refresh` is the `ProgressColumn`
  # class attr `None` (not overridden by `RenderableColumn`). `renderableCache`
  # keeps its default empty `Table` (== Python's `_renderable_cache = {}`):
  # `initTable[TaskID,…]` is skipped — the `TaskID` `hash` borrow is not yet
  # declared, and the default `Table` is already a valid empty table.
  result.tableColumn = tableColumn
  result.updateTime = none(float)
  result.maxRefresh = none(float)

method render*(self: RenderableColumn, task: Task): RenderableValue =
  ## rich progress.py:562-563 — `RenderableColumn.render(self, task: "Task") ->
  ## RenderableType`: `return self.renderable` (progress.py:562).
  # Faithful (progress.py:562): `return self.renderable`. The `rvString` arm
  # crosses the `RenderableValue`→`RenderableType` bridge directly (a `string`
  # satisfies `RenderableType`); the renderable arms (`rvConsoleRenderable`/
  # `rvRichCast`) cannot — a stored `RenderableBase` satisfies neither the
  # `ConsoleRenderable` nor `RichCast` concept, and a typeclass return cannot
  # unify `string` with `RenderableBase` — the codebase-wide DEFERRED blocker
  # (cf. `constrain.nim`/`console.nim`); they stay a no-op (`result` defaults
  # to `""`) until the bridge lands.
  case self.renderable.kind
  of rvString:
    result = self.renderable.textStr
  of rvConsoleRenderable, rvRichCast:
    discard

proc initSpinnerColumn*(spinnerName: string = "dots",
                        style: StyleOpt = "progress.spinner",
                        speed: float = 1.0, finishedText: TextType = " ",
                        tableColumn: Option[Column] = none(Column)): SpinnerColumn =
  ## rich progress.py:576-590 — `SpinnerColumn.__init__(self, spinner_name: str
  ## = "dots", style: Optional[StyleType] = "progress.spinner", speed: float =
  ## 1.0, finished_text: TextType = " ", table_column: Optional[Column] =
  ## None)`: build `self.spinner = Spinner(spinner_name, style=style,
  ## speed=speed)` and `self.finished_text`, then `super().__init(…)`
  ## (progress.py:583-590). `spinner_name`→`spinnerName` (avoid shadowing the
  ## `spinner` module); `style: Optional[StyleType] = "progress.spinner"` →
  ## `StyleOpt` (default the string); `finished_text: TextType = " "` →
  ## typeclass param, stored as `RenderableValue`.
  result = SpinnerColumn()
  result.spinnerHandle = initSpinner(spinnerName, style = style, speed = speed)
  # `self.finished_text = Text.from_markup(finished_text) if isinstance(
  # finished_text, str) else finished_text` (progress.py:584-588): a `str`
  # input is markup-parsed to a `Text`, a `Text` input is kept as-is — both
  # stored as a `RenderableValue` via the `Text`→`RenderableBase` converter arm.
  when typeof(finishedText) is string:
    result.finishedText = Text.fromMarkup(finishedText)
  else:
    result.finishedText = finishedText
  # `super().__init__(table_column=table_column)` (progress.py:590) — the
  # inherited `ProgressColumn` fields (see `initRenderableColumn`); `SpinnerColumn`
  # does not override `max_refresh`, so it stays `None`.
  result.tableColumn = tableColumn
  result.updateTime = none(float)
  result.maxRefresh = none(float)

proc setSpinner*(self: SpinnerColumn, spinnerName: string,
                 spinnerStyle: StyleOpt = "progress.spinner", speed: float = 1.0) =
  ## rich progress.py:592-605 — `SpinnerColumn.set_spinner(self, spinner_name:
  ## str, spinner_style: Optional[StyleType] = "progress.spinner", speed: float
  ## = 1.0) -> None`: rebuild `self.spinner` (progress.py:603-605). port
  ## stub.
  self.spinnerHandle = initSpinner(spinnerName, style = spinnerStyle, speed = speed)

method render*(self: SpinnerColumn, task: Task): RenderableValue =
  ## rich progress.py:607-614 — `SpinnerColumn.render(self, task: "Task") ->
  ## RenderableType`: `self.finished_text` if `task.finished` else
  ## `self.spinner.render(task.get_time())` (progress.py:609-613). Returns the
  ## faithful `RenderableType` typeclass.
  # Faithful (progress.py:609-613): `self.finished_text if task.finished else
  # self.spinner.render(task.get_time())`. `self.finishedText` is stored as a
  # `RenderableValue` (always a `Text` after `initSpinnerColumn`, in the
  # `rvConsoleRenderable` arm); recover it via the `RenderableBase`→`Text`
  # downcast (cf. `console.nim`'s `Text(item)` in `collectRenderables`).
  # `self.spinnerHandle.render` returns a `Text` (the frame), so both arms
  # unify to `Text` ⊂ `RenderableType`. The `rvString`/`rvRichCast` arms are
  # defensive (an uninitialised or directly-set field); they never trigger via
  # the public `initSpinnerColumn` path.
  if task.finished:
    case self.finishedText.kind
    of rvString:
      result = initText(self.finishedText.textStr)
    of rvConsoleRenderable:
      result = Text(self.finishedText.consoleItem)
    of rvRichCast:
      result = Text(self.finishedText.castItem)
  else:
    result = self.spinnerHandle.render(task.getTime())

proc initTextColumn*(textFormat: string, style: StyleType = "none",
                     justify: JustifyMethod = jmLeft, markup: bool = true,
                     highlighter: Option[Highlighter] = none(Highlighter),
                     tableColumn: Option[Column] = none(Column)): TextColumn =
  ## rich progress.py:619-633 — `TextColumn.__init__(self, text_format: str,
  ## style: StyleType = "none", justify: JustifyMethod = "left", markup: bool =
  ## True, highlighter: Optional[Highlighter] = None, table_column:
  ## Optional[Column] = None) -> None`: store the fields and
  ## `super().__init(table_column=table_column or Column(no_wrap=True))`
  ## (progress.py:627-633). `style: StyleType = "none"` → typeclass, stored as
  ## `StyleValue`; `justify: JustifyMethod = "left"` → `jmLeft`; `highlighter:
  ## Optional[Highlighter] = None` → `Option[Highlighter]` (the forward handle).
  new(result)
  result.textFormat = textFormat
  result.justify = justify
  result.style = style
  result.markup = markup
  result.highlighter = highlighter
  # `super().__init(table_column=table_column or Column(no_wrap=True))`
  # (progress.py:633): a None `tableColumn` defaults to `Column(no_wrap=True)`.
  result.tableColumn = if tableColumn.isSome: tableColumn else: some(initColumn(noWrap = true))
  # inherited `ProgressColumn` fields (`renderableCache` empty, `updateTime`
  # none, `maxRefresh` none — TextColumn does not override the class attr) stay
  # at their `new(result)` defaults.

method render*(self: TextColumn, task: Task): RenderableValue =
  ## rich progress.py:635-644 — `TextColumn.render(self, task: "Task") -> Text`:
  ## format `self.text_format.format(task=task)`, build a `Text` (markup or
  ## plain), apply `self.highlighter` if set (progress.py:637-643). Returns the
  ## concrete `Text`.
  # `_text = self.text_format.format(task=task)` (progress.py:637) — inline
  # str.format substitution resolving `{task.<field>[:<spec>]}` and
  # `{task.fields[k]}` (the same parser as `TaskProgressColumn.render`; the
  # `render_speed` shortcut and `text_format_no_percentage` selection there do
  # not apply — `TextColumn` always formats `self.textFormat`).
  let textFormat = self.textFormat
  var builtText = ""
  var fi = 0
  let fmtN = textFormat.len
  while fi < fmtN:
    let ch = textFormat[fi]
    if ch == '{':
      if fi + 1 < fmtN and textFormat[fi + 1] == '{':
        builtText.add('{'); fi += 2; continue
      var depth = 1
      var fj = fi + 1
      while fj < fmtN and depth > 0:
        if textFormat[fj] == '{': inc depth
        elif textFormat[fj] == '}': dec depth
        if depth > 0: inc fj
      let content = textFormat[fi + 1 ..< fj]
      var fieldName = content
      var spec = ""
      for ci in 0 ..< content.len:
        if content[ci] == ':':
          fieldName = content[0 ..< ci]
          spec = content[ci + 1 ..< content.len]
          break
      var sval = ""
      var fval = 0.0
      var numeric = false
      if fieldName == "task":
        sval = task.description
      elif fieldName.startsWith("task."):
        let attr = fieldName[5 ..< fieldName.len]
        if attr.startsWith("fields[") and attr.endsWith("]"):
          let keyRaw = attr[7 ..< attr.len - 1]
          let key = if keyRaw.len >= 2 and keyRaw[0] in {'"', '\''} and keyRaw[keyRaw.len - 1] == keyRaw[0]:
                    keyRaw[1 ..< keyRaw.len - 1] else: keyRaw
          if task.fields.hasKey(key):
            let node = task.fields[key]
            case node.kind
            of JString: sval = node.getStr
            of JInt: fval = float(node.getInt); numeric = true
            of JFloat: fval = node.getFloat; numeric = true
            of JBool: sval = if node.getBool: "True" else: "False"
            of JNull: sval = "None"
            else: sval = $node
        else:
          case attr
          of "description": sval = task.description
          of "completed": fval = task.completed; numeric = true
          of "total":
            if task.total.isSome:
              fval = task.total.get; numeric = true
            else:
              sval = ""
          of "percentage": fval = task.percentage; numeric = true
          of "speed":
            let sp = task.speed
            if sp.isSome: fval = sp.get; numeric = true else: sval = ""
          of "remaining":
            let r = task.remaining
            if r.isSome: fval = r.get; numeric = true else: sval = ""
          of "elapsed":
            let e = task.elapsed
            if e.isSome: fval = e.get; numeric = true else: sval = ""
          of "finished": sval = if task.finished: "True" else: "False"
          of "started": sval = if task.started: "True" else: "False"
          of "id": fval = float(int(task.id)); numeric = true
          else: sval = ""
      var si = 0
      var fillC = ' '
      var alignC = char(0)
      var zeroPad = false
      var width = 0
      var precision = -1
      var hasType = false
      var typeC = ' '
      var signC = ' '
      var hasSign = false
      if spec.len >= 2 and spec[1] in {'<', '>', '^', '='}:
        fillC = spec[0]; alignC = spec[1]; si = 2
      elif spec.len >= 1 and spec[0] in {'<', '>', '^', '='}:
        alignC = spec[0]; si = 1
      if si < spec.len and spec[si] in {'+', '-', ' '}: signC = spec[si]; hasSign = true; inc si
      if si < spec.len and spec[si] == '#': inc si
      if si < spec.len and spec[si] == '0': zeroPad = true; inc si
      while si < spec.len and spec[si].isDigit:
        width = width * 10 + (ord(spec[si]) - ord('0')); inc si
      if si < spec.len and spec[si] in {'_', ','}: inc si
      if si < spec.len and spec[si] == '.':
        inc si; var p = 0
        while si < spec.len and spec[si].isDigit:
          p = p * 10 + (ord(spec[si]) - ord('0')); inc si
        precision = p
      if si < spec.len: typeC = spec[si]; hasType = true
      var outStr: string
      if numeric:
        if not hasType or typeC == 's':
          outStr = $fval
        else:
          case typeC
          of 'f', 'F':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffDecimal, p)
            if p == 0 and outStr.endsWith("."): outStr = outStr[0 ..< outStr.len - 1]
          of 'e', 'E':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffScientific, p)
            if typeC == 'E': outStr = outStr.toUpperAscii()
          of 'g', 'G', 'n':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffDefault, p)
            if typeC == 'G': outStr = outStr.toUpperAscii()
          of '%':
            let p = if precision >= 0: precision else: 6
            var num = formatFloat(fval * 100.0, ffDecimal, p)
            if p == 0 and num.endsWith("."): num = num[0 ..< num.len - 1]
            outStr = num & "%"
          of 'd': outStr = $(int(fval))
          of 'b':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = (if (n and 1) == 1: "1" else: "0") & digits; n = n shr 1
            outStr = if neg: "-" & digits else: digits
          of 'o':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = $chr(ord('0') + (n mod 8)) & digits; n = n div 8
            outStr = if neg: "-" & digits else: digits
          of 'x', 'X':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            const hexd = "0123456789abcdef"
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = $hexd[n and 0xF] & digits; n = n shr 4
            if typeC == 'X': digits = digits.toUpperAscii()
            outStr = if neg: "-" & digits else: digits
          else: outStr = $fval
        if fval >= 0.0 and hasSign:
          if signC == '+': outStr = "+" & outStr
          elif signC == ' ': outStr = " " & outStr
      else:
        outStr = sval
      if width > 0 and outStr.len < width:
        let pad = width - outStr.len
        let effAlign = if alignC != char(0): alignC elif zeroPad: '=' else: (if numeric: '>' else: '<')
        let effFill = if zeroPad and alignC == char(0): '0' else: fillC
        case effAlign
        of '<': outStr = outStr & repeat(effFill, pad)
        of '>', '=':
          if effAlign == '=' and zeroPad:
            var signPart = ""; var numPart = outStr
            if outStr.len > 0 and outStr[0] in {'+', '-', ' '}:
              signPart = $outStr[0]; numPart = outStr[1 ..< outStr.len]
            outStr = signPart & repeat('0', pad) & numPart
          else:
            outStr = repeat(effFill, pad) & outStr
        of '^':
          let left = pad div 2
          outStr = repeat(effFill, left) & outStr & repeat(effFill, pad - left)
        else: outStr = repeat(effFill, pad) & outStr
      builtText.add(outStr)
      fi = fj + 1
    elif ch == '}':
      if fi + 1 < fmtN and textFormat[fi + 1] == '}':
        builtText.add('}'); fi += 2; continue
      builtText.add('}'); inc fi
    else:
      builtText.add(ch); inc fi
  # `if self.markup: Text.from_markup(…) else: Text(…)` (progress.py:638-641):
  # branch on the `StyleValue` arm (`str` vs `Style`) for the `style` param.
  if self.markup:
    case self.style.kind
    of svkStr: result = Text.fromMarkup(builtText, style = self.style.strv, justify = some(self.justify))
    of svkStyle: result = Text.fromMarkup(builtText, style = self.style.stv, justify = some(self.justify))
  else:
    case self.style.kind
    of svkStr: result = initText(builtText, style = self.style.strv, justify = some(self.justify))
    of svkStyle: result = initText(builtText, style = self.style.stv, justify = some(self.justify))
  # `if self.highlighter: self.highlighter.highlight(text)` (progress.py:642-
  # 643): the `Highlighter` is a [NON-NARROWING PROVISIONAL FORWARD HANDLE]
  # with no `highlight()` method yet — a genuine deferred no-op (cf.
  # `TaskProgressColumn.render`).
  if self.highlighter.isSome:
    discard  # DEFERRED: highlighter.nim forward handle has no `highlight()` yet

proc initBarColumn*(barWidth: Option[int] = some(40), style: StyleType = "bar.back",
                    completeStyle: StyleType = "bar.complete",
                    finishedStyle: StyleType = "bar.finished",
                    pulseStyle: StyleType = "bar.pulse",
                    tableColumn: Option[Column] = none(Column)): BarColumn =
  ## rich progress.py:657-672 — `BarColumn.__init__(self, bar_width:
  ## Optional[int] = 40, style: StyleType = "bar.back", complete_style:
  ## StyleType = "bar.complete", finished_style: StyleType = "bar.finished",
  ## pulse_style: StyleType = "bar.pulse", table_column: Optional[Column] =
  ## None) -> None`: store the fields and `super().__init(…)` (progress.py:658-
  ## 666). `bar_width: Optional[int] = 40` → `Option[int]`, default `some(40)`;
  ## the four `StyleType` params → typeclass defaults, stored as `StyleValue`.
  new(result)
  result.barWidth = barWidth
  result.style = style
  result.completeStyle = completeStyle
  result.finishedStyle = finishedStyle
  result.pulseStyle = pulseStyle
  # `super().__init(table_column=table_column)` (progress.py:666): BarColumn
  # passes `table_column` as-is (no `or Column(no_wrap=True)` default), so a
  # `none(Column)` stays `none(Column)`.
  result.tableColumn = tableColumn
  # inherited `ProgressColumn` fields (`renderableCache` empty, `updateTime`
  # none, `maxRefresh` none — BarColumn does not override the class attr) stay
  # at their `new(result)` defaults.

method render*(self: BarColumn, task: Task): RenderableValue =
  ## rich progress.py:673-686 — `BarColumn.render(self, task: "Task") ->
  ## ProgressBar`: `ProgressBar(total=…, completed=…, width=…, pulse=not
  ## task.started, animation_time=task.get_time(), style=…, …)` (progress.py:
  ## 675-685). Returns the concrete `ProgressBar` (from `progress_bar.nim`).
  # Faithful (progress.py:675-685): `ProgressBar(total=max(0, task.total) if
  # task.total is not None else None, completed=max(0, task.completed), width=
  # None if self.bar_width is None else max(1, self.bar_width), pulse=not
  # task.started, animation_time=task.get_time(), style=…, complete_style=…,
  # finished_style=…, pulse_style=…)`. The four `StyleValue` style fields copy
  # straight across (ProgressBar's style fields are `StyleValue` too), avoiding
  # a 2^4 case-split over the `StyleType` typeclass constructor params.
  var bar = ProgressBar()
  bar.total = if task.total.isSome: some(max(0.0, task.total.get)) else: none(float)
  bar.completed = max(0.0, task.completed)
  bar.width = if self.barWidth.isNone: none(int) else: some(max(1, self.barWidth.get))
  bar.pulse = not task.started
  bar.animationTime = some(task.getTime())
  bar.style = self.style
  bar.completeStyle = self.completeStyle
  bar.finishedStyle = self.finishedStyle
  bar.pulseStyle = self.pulseStyle
  result = bar  # `ProgressBar ⊂ RenderableBase` → `toRenderableValue` converter arm
  # `_pulse_segments = None` (progress_bar.py:42) stays at its `new` default.

proc initTimeElapsedColumn*(tableColumn: Option[Column] = none(Column)): TimeElapsedColumn =
  ## rich time-elapsed column has no own `__init__` (inherits
  ## `ProgressColumn.__init__`, progress.py:688-695); this constructor mirrors
  ## the inherited `__init__(table_column=None)`.
  new(result)
  # inherits `ProgressColumn.__init__(table_column=table_column)`
  # (progress.py:517-519): `self._table_column = table_column`;
  # `self._renderable_cache = {}`; `self._update_time = None` (class attr
  # `max_refresh = None`). After `new(result)` the cache/time/max-refresh
  # fields already match those defaults, so only the param-driven `tableColumn`
  # needs an explicit assignment here.
  result.tableColumn = tableColumn

method render*(self: TimeElapsedColumn, task: Task): RenderableValue =
  ## rich progress.py:691-695 — `TimeElapsedColumn.render(self, task: "Task")
  ## -> Text`: `Text("-:--:--", style="progress.elapsed")` if no elapsed, else
  ## `Text(str(timedelta(seconds=…)), style="progress.elapsed")`
  ## (progress.py:693-694). Returns the concrete `Text`.
  # Faithful (progress.py:693-694): `elapsed = task.finished_time if
  # task.finished else task.elapsed`; `Text("-:--:--", style="progress.elapsed")`
  # if `elapsed is None`, else `Text(str(timedelta(seconds=max(0, int(elapsed)))),
  # style="progress.elapsed")`. `str(timedelta(seconds=n))` is `H:MM:SS` for
  # sub-day spans and `N day[s], H:MM:SS` once `n >= 86400` (hours unpadded,
  # minutes/seconds 2-digit zero-padded).
  let elapsed = if task.finished: task.finishedTime else: task.elapsed
  if elapsed.isNone:
    result = initText("-:--:--", style = "progress.elapsed")
  else:
    let secs = max(0, int(elapsed.get))
    let days = secs div 86400
    let rem = secs mod 86400
    let hours = rem div 3600
    let minutes = (rem mod 3600) div 60
    let seconds = rem mod 60
    let hms = $hours & ":" & align($minutes, 2, '0') & ":" & align($seconds, 2, '0')
    let delta =
      if days == 1: "1 day, " & hms
      elif days > 1: $days & " days, " & hms
      else: hms
    result = initText(delta, style = "progress.elapsed")

proc initTaskProgressColumn*(textFormat: string = "[progress.percentage]{task.percentage:>3.0f}%",
                             textFormatNoPercentage: string = "",
                             style: StyleType = "none",
                             justify: JustifyMethod = jmLeft, markup: bool = true,
                             highlighter: Option[Highlighter] = none(Highlighter),
                             tableColumn: Option[Column] = none(Column),
                             showSpeed: bool = false): TaskProgressColumn =
  ## rich progress.py:714-735 — `TaskProgressColumn.__init__(self, text_format:
  ## str = "[progress.percentage]{task.percentage:>3.0f}%",
  ## text_format_no_percentage: str = "", style: StyleType = "none", justify:
  ## JustifyMethod = "left", markup: bool = True, highlighter: Optional[
  ## Highlighter] = None, table_column: Optional[Column] = None, show_speed:
  ## bool = False) -> None`: store `text_format_no_percentage`/`show_speed` and
  ## call `super().__init(…)` (progress.py:728-735).
  new(result)
  result.textFormat = textFormat
  result.textFormatNoPercentage = textFormatNoPercentage
  result.style = style
  result.justify = justify
  result.markup = markup
  result.highlighter = highlighter
  result.showSpeed = showSpeed
  # `super().__init__(table_column=table_column or Column(no_wrap=True))`
  # (progress.py:727,633): a None `tableColumn` defaults to `Column(no_wrap=True)`.
  result.tableColumn = if tableColumn.isSome: tableColumn else: some(initColumn(noWrap = true))
  # inherited `ProgressColumn` fields (`renderableCache` empty, `updateTime`
  # none, `maxRefresh` none — TaskProgressColumn does not override the class
  # attr) stay at their `new(result)` defaults.

proc renderSpeed*(T: typedesc[TaskProgressColumn], speed: Option[float]): Text =
  ## rich progress.py:737-754 — `TaskProgressColumn.render_speed(cls, speed:
  ## Optional[float]) -> Text` (`@classmethod`, progress.py:736): `Text("",
  ## style="progress.percentage")` if `speed is None`, else
  ## `filesize.pick_unit_and_suffix` + `Text(f"{data_speed:.1f}{suffix} it/s",
  ## style=…)` (progress.py:740-753). Classmethod → `T: typedesc[
  ## TaskProgressColumn]`; returns the concrete `Text`. Body needs
  ## `filesize`.
  if speed.isNone:
    result = initText("", style = "progress.percentage")
  else:
    let speedVal = speed.get
    let suffixes = ["", "×10³", "×10⁶", "×10⁹", "×10¹²"]
    var unit = 1
    var suffix = ""
    let sz = int(speedVal)
    # `filesize.pick_unit_and_suffix(int(speed), suffixes, 1000)` (progress.py:741):
    # the helper is module-private, so the loop is inlined here.
    for i, sfx in suffixes:
      if i > 0: unit *= 1000
      suffix = sfx
      if sz div 1000 < unit: break
    let dataSpeed = speedVal / float(unit)
    result = initText(formatFloat(dataSpeed, ffDecimal, 1) & suffix & " it/s",
                      style = "progress.percentage")

method render*(self: TaskProgressColumn, task: Task): RenderableValue =
  ## rich progress.py:756-770 — `TaskProgressColumn.render(self, task: "Task")
  ## -> Text`: if `task.total is None and self.show_speed`, `render_speed(
  ## task.finished_speed or task.speed)`; else format `text_format` (or
  ## `text_format_no_percentage` if no total) and build a `Text`
  ## (progress.py:758-769). Returns the concrete `Text`.
  if task.total.isNone and self.showSpeed:
    # `task.finished_speed or task.speed` (progress.py:758): Python `or` returns
    # the first truthy operand — `None`/`0.0` are both falsy, so a finished speed of
    # `0.0` falls through to `task.speed` (cf. `TransferSpeedColumn.render`).
    let sp = if task.finishedSpeed.isSome and task.finishedSpeed.get != 0.0:
               task.finishedSpeed
             else:
               task.speed
    return renderSpeed(TaskProgressColumn, sp)
  let textFormat = if task.total.isNone: self.textFormatNoPercentage else: self.textFormat
  # `text_format.format(task=task)` (progress.py:762) — inline str.format
  # substitution resolving `{task.<field>[:<spec>]}` and `{task.fields[k]}`.
  var builtText = ""
  var fi = 0
  let fmtN = textFormat.len
  while fi < fmtN:
    let ch = textFormat[fi]
    if ch == '{':
      if fi + 1 < fmtN and textFormat[fi + 1] == '{':
        builtText.add('{'); fi += 2; continue
      var depth = 1
      var fj = fi + 1
      while fj < fmtN and depth > 0:
        if textFormat[fj] == '{': inc depth
        elif textFormat[fj] == '}': dec depth
        if depth > 0: inc fj
      let content = textFormat[fi + 1 ..< fj]
      var fieldName = content
      var spec = ""
      for ci in 0 ..< content.len:
        if content[ci] == ':':
          fieldName = content[0 ..< ci]
          spec = content[ci + 1 ..< content.len]
          break
      var sval = ""
      var fval = 0.0
      var numeric = false
      if fieldName == "task":
        sval = task.description
      elif fieldName.startsWith("task."):
        let attr = fieldName[5 ..< fieldName.len]
        if attr.startsWith("fields[") and attr.endsWith("]"):
          let keyRaw = attr[7 ..< attr.len - 1]
          let key = if keyRaw.len >= 2 and keyRaw[0] in {'"', '\''} and keyRaw[keyRaw.len - 1] == keyRaw[0]:
                    keyRaw[1 ..< keyRaw.len - 1] else: keyRaw
          if task.fields.hasKey(key):
            let node = task.fields[key]
            case node.kind
            of JString: sval = node.getStr
            of JInt: fval = float(node.getInt); numeric = true
            of JFloat: fval = node.getFloat; numeric = true
            of JBool: sval = if node.getBool: "True" else: "False"
            of JNull: sval = "None"
            else: sval = $node
        else:
          case attr
          of "description": sval = task.description
          of "completed": fval = task.completed; numeric = true
          of "total":
            if task.total.isSome:
              fval = task.total.get; numeric = true
            else:
              sval = ""
          of "percentage": fval = task.percentage; numeric = true
          of "speed":
            let sp = task.speed
            if sp.isSome: fval = sp.get; numeric = true else: sval = ""
          of "remaining":
            let r = task.remaining
            if r.isSome: fval = r.get; numeric = true else: sval = ""
          of "elapsed":
            let e = task.elapsed
            if e.isSome: fval = e.get; numeric = true else: sval = ""
          of "finished": sval = if task.finished: "True" else: "False"
          of "started": sval = if task.started: "True" else: "False"
          of "id": fval = float(int(task.id)); numeric = true
          else: sval = ""
      # Python format-spec mini-language subset: [fill][align][sign][#][0]
      # [width][,][.precision][type] with types s d f F e E g G n % b o x X.
      var si = 0
      var fillC = ' '
      var alignC = char(0)
      var zeroPad = false
      var width = 0
      var precision = -1
      var hasType = false
      var typeC = ' '
      var signC = ' '
      var hasSign = false
      if spec.len >= 2 and spec[1] in {'<', '>', '^', '='}:
        fillC = spec[0]; alignC = spec[1]; si = 2
      elif spec.len >= 1 and spec[0] in {'<', '>', '^', '='}:
        alignC = spec[0]; si = 1
      if si < spec.len and spec[si] in {'+', '-', ' '}: signC = spec[si]; hasSign = true; inc si
      if si < spec.len and spec[si] == '#': inc si
      if si < spec.len and spec[si] == '0': zeroPad = true; inc si
      while si < spec.len and spec[si].isDigit:
        width = width * 10 + (ord(spec[si]) - ord('0')); inc si
      if si < spec.len and spec[si] in {'_', ','}: inc si
      if si < spec.len and spec[si] == '.':
        inc si; var p = 0
        while si < spec.len and spec[si].isDigit:
          p = p * 10 + (ord(spec[si]) - ord('0')); inc si
        precision = p
      if si < spec.len: typeC = spec[si]; hasType = true
      var outStr: string
      if numeric:
        if not hasType or typeC == 's':
          outStr = $fval
        else:
          case typeC
          of 'f', 'F':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffDecimal, p)
            if p == 0 and outStr.endsWith("."): outStr = outStr[0 ..< outStr.len - 1]
          of 'e', 'E':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffScientific, p)
            if typeC == 'E': outStr = outStr.toUpperAscii()
          of 'g', 'G', 'n':
            let p = if precision >= 0: precision else: 6
            outStr = formatFloat(fval, ffDefault, p)
            if typeC == 'G': outStr = outStr.toUpperAscii()
          of '%':
            let p = if precision >= 0: precision else: 6
            var num = formatFloat(fval * 100.0, ffDecimal, p)
            if p == 0 and num.endsWith("."): num = num[0 ..< num.len - 1]
            outStr = num & "%"
          of 'd': outStr = $(int(fval))
          of 'b':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = (if (n and 1) == 1: "1" else: "0") & digits; n = n shr 1
            outStr = if neg: "-" & digits else: digits
          of 'o':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = $chr(ord('0') + (n mod 8)) & digits; n = n div 8
            outStr = if neg: "-" & digits else: digits
          of 'x', 'X':
            var n = int(fval); var neg = false
            if n < 0: neg = true; n = -n
            const hexd = "0123456789abcdef"
            var digits = if n == 0: "0" else: ""
            while n > 0: digits = $hexd[n and 0xF] & digits; n = n shr 4
            if typeC == 'X': digits = digits.toUpperAscii()
            outStr = if neg: "-" & digits else: digits
          else: outStr = $fval
        if fval >= 0.0 and hasSign:
          if signC == '+': outStr = "+" & outStr
          elif signC == ' ': outStr = " " & outStr
      else:
        outStr = sval
      if width > 0 and outStr.len < width:
        let pad = width - outStr.len
        let effAlign = if alignC != char(0): alignC elif zeroPad: '=' else: (if numeric: '>' else: '<')
        let effFill = if zeroPad and alignC == char(0): '0' else: fillC
        case effAlign
        of '<': outStr = outStr & repeat(effFill, pad)
        of '>', '=':
          if effAlign == '=' and zeroPad:
            var signPart = ""; var numPart = outStr
            if outStr.len > 0 and outStr[0] in {'+', '-', ' '}:
              signPart = $outStr[0]; numPart = outStr[1 ..< outStr.len]
            outStr = signPart & repeat('0', pad) & numPart
          else:
            outStr = repeat(effFill, pad) & outStr
        of '^':
          let left = pad div 2
          outStr = repeat(effFill, left) & outStr & repeat(effFill, pad - left)
        else: outStr = repeat(effFill, pad) & outStr
      builtText.add(outStr)
      fi = fj + 1
    elif ch == '}':
      if fi + 1 < fmtN and textFormat[fi + 1] == '}':
        builtText.add('}'); fi += 2; continue
      builtText.add('}'); inc fi
    else:
      builtText.add(ch); inc fi
  if self.markup:
    case self.style.kind
    of svkStr: result = Text.fromMarkup(builtText, style = self.style.strv, justify = some(self.justify))
    of svkStyle: result = Text.fromMarkup(builtText, style = self.style.stv, justify = some(self.justify))
  else:
    case self.style.kind
    of svkStr: result = initText(builtText, style = self.style.strv, justify = some(self.justify))
    of svkStyle: result = initText(builtText, style = self.style.stv, justify = some(self.justify))
  if self.highlighter.isSome:
    discard  # DEFERRED: highlighter.nim forward handle has no `highlight()` yet

proc initTimeRemainingColumn*(compact: bool = false,
                              elapsedWhenFinished: bool = false,
                              tableColumn: Option[Column] = none(Column)): TimeRemainingColumn =
  ## rich progress.py:783-791 — `TimeRemainingColumn.__init__(self, compact:
  ## bool = False, elapsed_when_finished: bool = False, table_column:
  ## Optional[Column] = None)`: store `compact`/`elapsed_when_finished` and
  ## `super().__init(…)` (progress.py:789-791); the class attr `max_refresh =
  ## 0.5` (progress.py:781) sets `maxRefresh` in the body.
  new(result)
  result.compact = compact
  result.elapsedWhenFinished = elapsedWhenFinished
  result.tableColumn = tableColumn
  # class-attr override `max_refresh = 0.5` (progress.py:781).
  result.maxRefresh = some(0.5)

method render*(self: TimeRemainingColumn, task: Task): RenderableValue =
  ## rich progress.py:793-818 — `TimeRemainingColumn.render(self, task: "Task")
  ## -> Text`: `Text("", style=…)` if no total; `Text("--:--"/"-:--:--",
  ## style=…)` if no `task_time`; else `f"{hours:d}:{minutes:02d}:{seconds:02d}"`
  ## (or `MM:SS` when compact & <1h) (progress.py:799-816). Returns the concrete
  ## `Text`.
  var taskTime: Option[float]
  var style: string
  if self.elapsedWhenFinished and task.finished:
    taskTime = task.finishedTime
    style = "progress.elapsed"
  else:
    taskTime = task.timeRemaining
    style = "progress.remaining"
  if task.total.isNone:
    result = initText("", style = style)
  elif taskTime.isNone:
    result = initText(if self.compact: "--:--" else: "-:--:--", style = style)
  else:
    let total = int(taskTime.get)
    let seconds = total mod 60
    let minutes = (total div 60) mod 60
    let hours = total div 3600
    var formatted: string
    if self.compact and hours == 0:
      formatted = align($minutes, 2, '0') & ":" & align($seconds, 2, '0')
    else:
      formatted = $hours & ":" & align($minutes, 2, '0') & ":" & align($seconds, 2, '0')
    result = initText(formatted, style = style)

proc initFileSizeColumn*(tableColumn: Option[Column] = none(Column)): FileSizeColumn =
  ## rich filesize column has no own `__init__` (inherits
  ## `ProgressColumn.__init__`, progress.py:820-826); this constructor mirrors
  ## the inherited `__init__(table_column=None)`.
  new(result)
  result.tableColumn = tableColumn

method render*(self: FileSizeColumn, task: Task): RenderableValue =
  ## rich progress.py:823-826 — `FileSizeColumn.render(self, task: "Task") ->
  ## Text`: `Text(filesize.decimal(int(task.completed)), style="progress.
  ## filesize")` (progress.py:825). Returns the concrete `Text`. Body
  ## needs `filesize`.
  result = initText(decimal(int(task.completed)), style = "progress.filesize")

proc initTotalFileSizeColumn*(tableColumn: Option[Column] = none(Column)): TotalFileSizeColumn =
  ## rich total-filesize column has no own `__init__` (inherits
  ## `ProgressColumn.__init__`, progress.py:829-835); this constructor mirrors
  ## the inherited `__init__(table_column=None)`.
  new(result)
  result.tableColumn = tableColumn

method render*(self: TotalFileSizeColumn, task: Task): RenderableValue =
  ## rich progress.py:832-835 — `TotalFileSizeColumn.render(self, task: "Task")
  ## -> Text`: `Text(filesize.decimal(int(task.total)) if task.total is not
  ## None else "", style="progress.filesize.total")` (progress.py:833). Returns
  ## the concrete `Text`. Body needs `filesize`.
  let data = if task.total.isSome: decimal(int(task.total.get)) else: ""
  result = initText(data, style = "progress.filesize.total")

proc initMofNCompleteColumn*(separator: string = "/",
                             tableColumn: Option[Column] = none(Column)): MofNCompleteColumn =
  ## rich progress.py:850-853 — `MofNCompleteColumn.__init__(self, separator:
  ## str = "/", table_column: Optional[Column] = None)`: store `separator` and
  ## `super().__init(…)` (progress.py:852-853).
  new(result)
  result.separator = separator
  # `super().__init__(table_column=table_column)` → `ProgressColumn.__init__`
  # (progress.py:517-519): `self._table_column = table_column`;
  # `self._renderable_cache = {}`; `self._update_time = None` (class attr
  # `max_refresh = None`). After `new(result)` the `renderableCache`/
  # `updateTime`/`maxRefresh` fields already equal those defaults, so only the
  # param-driven `tableColumn` needs an explicit assignment here.
  result.tableColumn = tableColumn

method render*(self: MofNCompleteColumn, task: Task): RenderableValue =
  ## rich progress.py:854-862 — `MofNCompleteColumn.render(self, task: "Task")
  ## -> Text`: `Text(f"{completed:{total_width}d}{self.separator}{total}",
  ## style="progress.download")` (progress.py:856-861). Returns the concrete
  ## `Text`.
  let completed = int(task.completed)
  let totalStr = if task.total.isSome: $int(task.total.get) else: "?"
  let totalWidth = totalStr.len
  # `f"{completed:{total_width}d}"` — right-align the int to `totalWidth`
  # (minimum width, no truncation), mirroring Python's `d` format spec.
  let completedStr = align($completed, totalWidth)
  result = initText(completedStr & self.separator & totalStr,
                   style = "progress.download")

proc initDownloadColumn*(binaryUnits: bool = false,
                         tableColumn: Option[Column] = none(Column)): DownloadColumn =
  ## rich progress.py:872-877 — `DownloadColumn.__init__(self, binary_units:
  ## bool = False, table_column: Optional[Column] = None)`: store
  ## `binary_units` and `super().__init(…)` (progress.py:876-877). port
  ## stub.
  new(result)
  result.binaryUnits = binaryUnits
  # `super().__init__(table_column=table_column)` → `ProgressColumn.__init__`
  # (progress.py:517-519): `self._table_column = table_column`;
  # `self._renderable_cache = {}`; `self._update_time = None` (class attr
  # `max_refresh = None`). After `new(result)` the cache/time/max-refresh
  # fields already match those defaults, so only the param-driven `tableColumn`
  # needs an explicit assignment here.
  result.tableColumn = tableColumn

method render*(self: DownloadColumn, task: Task): RenderableValue =
  ## rich progress.py:878-911 — `DownloadColumn.render(self, task: "Task") ->
  ## Text`: pick a common unit (binary or decimal via
  ## `filesize.pick_unit_and_suffix`) for completed/total and build
  ## `Text(f"{completed_str}/{total_str} {suffix}", style="progress.download")`
  let completed = int(task.completed)
  let calcBase = if task.total.isSome: int(task.total.get) else: completed
  let (unit, suffix) =
    if self.binaryUnits:
      pickUnitAndSuffix(calcBase,
        ["bytes", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"], 1024)
    else:
      pickUnitAndSuffix(calcBase,
        ["bytes", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"], 1000)
  let precision = if unit == 1: 0 else: 1
  let completedStr = formatFloatCommas(completed / unit, precision)
  let totalStr =
    if task.total.isSome: formatFloatCommas(int(task.total.get) / unit, precision)
    else: "?"
  result = initText(completedStr & "/" & totalStr & " " & suffix,
                   style = "progress.download")

proc initTransferSpeedColumn*(tableColumn: Option[Column] = none(Column)): TransferSpeedColumn =
  ## rich transfer-speed column has no own `__init__` (inherits
  ## `ProgressColumn.__init__`, progress.py:914-923); this constructor mirrors
  ## the inherited `__init__(table_column=None)`.
  new(result)
  # inherits `ProgressColumn.__init__(table_column=table_column)`
  # (progress.py:517-519): `self._table_column = table_column`;
  # `self._renderable_cache = {}`; `self._update_time = None` (class attr
  # `max_refresh = None`). After `new(result)` the cache/time/max-refresh
  # fields already match those defaults, so only the param-driven `tableColumn`
  # needs an explicit assignment here.
  result.tableColumn = tableColumn

method render*(self: TransferSpeedColumn, task: Task): RenderableValue =
  ## rich progress.py:917-923 — `TransferSpeedColumn.render(self, task: "Task")
  ## -> Text`: `Text("?", style="progress.data.speed")` if no speed, else
  ## `Text(f"{filesize.decimal(int(speed))}/s", style="progress.data.speed")`
  ## (progress.py:919-922). Returns the concrete `Text`. Body needs
  ## `filesize`.
  # `speed = task.finished_speed or task.speed` (progress.py:919): Python `or`
  # returns the first truthy operand — `None`/`0.0` are both falsy, so a
  # finished speed of `0.0` falls through to `task.speed`; `task.speed` is the
  # (currently stubbed) `Option[float]` proc.
  let finished = task.finishedSpeed
  let speed = if finished.isSome and finished.get != 0.0: finished else: task.speed
  if speed.isNone:
    return initText("?", style = "progress.data.speed")
  let dataSpeed = filesize.decimal(int(speed.get))
  result = initText(dataSpeed & "/s", style = "progress.data.speed")

# ---------------------------------------------------------------------------
# Progress
# ---------------------------------------------------------------------------

proc getDefaultColumns*(T: typedesc[Progress]): seq[ColumnArg]
proc getRenderable*(self: Progress): RenderableType
proc getRenderables*(self: Progress): seq[RenderableValue]
proc makeTasksTable*(self: Progress, tasks: openArray[Task]): table.Table
proc richCast*(self: Progress): RenderableType

proc initProgress*(columns: varargs[ColumnArg], console: ConsoleHandle = nil,
                   autoRefresh: bool = true, refreshPerSecond: float = 10.0,
                   speedEstimatePeriod: float = 30.0, transient: bool = false,
                   redirectStdout: bool = true, redirectStderr: bool = true,
                   getTime: Option[GetTimeCallable] = none(GetTimeCallable),
                   disable: bool = false, expand: bool = false): Progress =
  ## rich progress.py:1077-1112 — `Progress.__init__(self, *columns: Union[str,
  ## ProgressColumn], console: Optional[Console] = None, auto_refresh: bool =
  ## True, refresh_per_second: float = 10, speed_estimate_period: float = 30.0,
  ## transient: bool = False, redirect_stdout: bool = True, redirect_stderr:
  ## bool = True, get_time: Optional[GetTimeCallable] = None, disable: bool =
  ## False, expand: bool = False) -> None`: assert `refresh_per_second > 0`
  ## (progress.py:1080); `self._lock = RLock()`, `self.columns = columns or
  ## self.get_default_columns()`, store `speed_estimate_period`/`disable`/
  ## `expand`, `self._tasks = {}`, `self._task_index = TaskID(0)`, `self.live =
  ## Live(console=console or get_console(), auto_refresh=…, refresh_per_second=…,
  ## transient=…, redirect_stdout=…, redirect_stderr=…, get_renderable=
  ## self.get_renderable)`, `self.get_time = get_time or self.console.get_time`,
  ## `self.print = self.console.print`, `self.log = self.console.log`
  ## (progress.py:1095-1112). `*columns: Union[str, ProgressColumn]` →
  ## `varargs[ColumnArg]` (the `toColumnArg*` converters); `console:
  ## Optional[Console] = None` → `ConsoleHandle = nil`; `get_time: Optional[
  ## GetTimeCallable] = None` → `Option[GetTimeCallable]`, default
  ## `none(GetTimeCallable)`.
  assert refreshPerSecond > 0, "refresh_per_second must be > 0"
  new(result)
  # `self._lock = RLock()` (progress.py:1092) → `initLock(result.lockField)`
  # (std/locks.Lock; the `RLock()`↔`initLock` convention, cf. `live.nim`/
  # `layout.nim`).
  initLock(result.lockField)
  # `self.columns = columns or self.get_default_columns()` (progress.py:1093):
  # Python `or` returns the first truthy operand — an empty `columns` tuple is
  # falsy, so no columns ⇒ the classmethod defaults. `varargs[ColumnArg]` is
  # falsy iff empty (`columns.len == 0`); `@columns` lifts it to `seq[ColumnArg]`.
  if columns.len == 0:
    result.columns = Progress.getDefaultColumns()
  else:
    result.columns = @columns
  # `self.speed_estimate_period = speed_estimate_period` (progress.py:1094).
  result.speedEstimatePeriod = speedEstimatePeriod
  # `self.disable = disable` / `self.expand = expand` (progress.py:1096-1097).
  result.disable = disable
  result.expand = expand
  # `self._tasks: Dict[TaskID, Task] = {}` (progress.py:1098) → an empty
  # `Table[TaskID, Task]`.
  result.tasksMap = initTable[TaskID, Task]()
  # `self._task_index: TaskID = TaskID(0)` (progress.py:1099) → `TaskID(0)`
  # (the `distinct int` next-id counter, seeded at 0).
  result.taskIndex = TaskID(0)
  # `self.live = Live(console=console or get_console(), auto_refresh=…,
  #   refresh_per_second=…, transient=…, redirect_stdout=…, redirect_stderr=…,
  #   get_renderable=self.get_renderable)` (progress.py:1100-1108): `get_console`
  #   is not exposed in the Nim port (a `nil` console stays `nil`, per
  #   `live.nim`), so `console or get_console()` → `console`. `renderable`/`screen`
  #   are left at their `Live` defaults (Python omits them too). The bound method
  #   `self.get_renderable` (= `Group(*self.get_renderables())`, progress.py:1553)
  #   is wired as a closure computing `initGroup(p.getRenderables())`; the
  #   `Group`→`RenderableBase`→`RenderableValue` converter bridges the result
  #   (the same conversion as `status.nim`/`initSpinnerColumn`). `p` captures
  #   `result` (an alias avoids capturing the implicit `result` var).
  let p = result
  let getRenderableCb: GetRenderableCb = proc(): RenderableValue =
    result = initGroup(p.getRenderables())
  result.live = initLive(
    console = console,
    autoRefresh = autoRefresh,
    refreshPerSecond = refreshPerSecond,
    transient = transient,
    redirectStdout = redirectStdout,
    redirectStderr = redirectStderr,
    getRenderable = some(getRenderableCb))
  # `self.get_time = get_time or self.console.get_time` (progress.py:1109): the
  # console's `get_time` (`time.monotonic`) is deferred behind the opaque
  # `ConsoleHandle` (`self.console` = `self.live.console`, an opaque base with
  # no `getTime` accessor), so the fallback clock is `epochTime()` (std/times)
  # — the port's stand-in for `time.monotonic` (see the `std/times` import).
  if getTime.isSome:
    result.getTime = getTime.get
  else:
    result.getTime = proc(): float = epochTime()
  # `self.print = self.console.print` / `self.log = self.console.log`
  # (progress.py:1110-1111) are Python bound-method attrs modelled as stub
  # method procs `print*`/`log*` (no `print`/`log` fields on `Progress`), so
  # they are not assigned in the Nim port.

proc getDefaultColumns*(T: typedesc[Progress]): seq[ColumnArg] =
  ## rich progress.py:1114-1143 — `Progress.get_default_columns(cls) ->
  ## Tuple[ProgressColumn, ...]` (`@classmethod`, progress.py:1114): returns
  ## `(TextColumn("[progress.description]{task.description}"), BarColumn(),
  ## TaskProgressColumn(), TimeRemainingColumn(elapsed_when_finished=True))`
  ## (progress.py:1140-1143). Classmethod → `T: typedesc[Progress]`; returns
  ## `seq[ColumnArg]` (the four columns wrapped).
  # rich progress.py:1137-1142 — `(TextColumn("[progress.description]{task.
  # description}"), BarColumn(), TaskProgressColumn(), TimeRemainingColumn())`.
  # Each column widget (a `ProgressColumn` subtype) is wrapped in the
  # `cakColumn` arm of `ColumnArg` (the `toColumnArg*` converter's arm).
  # `TimeRemainingColumn()` takes no `elapsed_when_finished` here — the
  # classmethod uses the default `False` (progress.py:1141); the `=True` form
  # is the module-level `track` helper (progress.py:159), not the defaults.
  result = @[
    ColumnArg(kind: cakColumn, columnv: initTextColumn("[progress.description]{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initBarColumn()),
    ColumnArg(kind: cakColumn, columnv: initTaskProgressColumn()),
    ColumnArg(kind: cakColumn, columnv: initTimeRemainingColumn()),
  ]

proc console*(self: Progress): ConsoleHandle =
  ## rich progress.py:1144-1146 — `Progress.console` property: `return
  ## self.live.console` (progress.py:1145). Returns the `ConsoleHandle`
  ## placeholder (richbase).
  # Faithful (progress.py:1145): `return self.live.console` — the `Live.console`
  # field (`ConsoleHandle`). The Python property is lock-free (no `with self._lock`).
  result = self.live.console

proc tasks*(self: Progress): seq[Task] =
  ## rich progress.py:1148-1152 — `Progress.tasks` property: `with self._lock:
  ## return list(self._tasks.values())` (progress.py:1150-1151). Returns
  ## `seq[Task]` (`list(self._tasks.values())`).
  # Faithful (progress.py:1150-1151): `with self._lock: return list(self._tasks.
  # values())` → under `lockField`, materialise the values into a `seq[Task]`
  # (the `values` iterator needs no `TaskID` hash, only insertion does).
  withLock self.lockField:
    for v in self.tasksMap.values:
      result.add(v)

proc taskIds*(self: Progress): seq[TaskID] =
  ## rich progress.py:1154-1158 — `Progress.task_ids` property: `with self._lock:
  ## return list(self._tasks.keys())` (progress.py:1156-1157). Returns
  ## `seq[TaskID]`.
  # Faithful (progress.py:1156-1157): `with self._lock: return list(self._tasks.
  # keys())` → under `lockField`, materialise the keys into a `seq[TaskID]`
  # (the `keys` iterator needs no `TaskID` hash).
  withLock self.lockField:
    for k in self.tasksMap.keys:
      result.add(k)

proc finished*(self: Progress): bool =
  ## rich progress.py:1160-1166 — `Progress.finished` property: `True` if no
  ## tasks, else `all(task.finished for task in self._tasks.values())`
  ## (progress.py:1162-1165).
  # Faithful (progress.py:1162-1165): `with self._lock: if not self._tasks: return
  # True; return all(task.finished for task in self._tasks.values())`. Empty ⇒
  # True; else `all` short-circuits False on the first non-`finished` task
  # (`task.finished` is the `Task.finished*` proc; `break` exits the loop and
  # `withLock`'s `finally` releases `lockField`).
  withLock self.lockField:
    if self.tasksMap.len == 0:
      result = true
    else:
      result = true
      for task in self.tasksMap.values:
        if not task.finished:
          result = false
          break

proc start*(self: Progress) =
  ## rich progress.py:1168-1171 — `Progress.start(self) -> None`: if not
  ## `self.disable`, `self.live.start(refresh=True)` (progress.py:1170). Phase
  ## 0 stub.
  if not self.disable:
    self.live.start(refresh = true)

proc stop*(self: Progress) =
  ## rich progress.py:1173-1178 — `Progress.stop(self) -> None`: if not
  ## `self.disable`, `self.live.stop()` and (for non-interactive non-jupyter
  ## consoles) `self.console.print()` (progress.py:1175-1177).
  if not self.disable:
    self.live.stop()
    let c = Console(self.console)
    if not c.isInteractive and not c.isJupyter:
      let objs: seq[RenderableValue] = @[]
      c.print(objs)

proc enter*(self: Progress): Progress =
  ## rich progress.py:1180-1182 — `Progress.__enter__(self) -> Self`:
  ## `self.start(); return self` (progress.py:1181). Dunder mapping
  ## `__enter__`→`enter`; returns the `Progress` (Python `Self`).
  self.start()
  return self

proc exit*(self: Progress, excType: Option[RootRef],
          excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich progress.py:1184-1190 — `Progress.__exit__(self, exc_type, exc_val,
  ## exc_tb) -> None`: `self.stop()` (progress.py:1189). Dunder mapping
  ## `__exit__`→`exit` (mirroring `live.nim`). The three exception params:
  ## `exc_type` → `Option[RootRef]`; `exc_val` → `Option[ref CatchableError]`;
  ## `exc_tb` → `Option[RootRef]`.
  self.stop()

proc print*(self: Progress, renderables: varargs[RenderableValue]) =
  ## rich progress.py:1112 — `self.print = self.console.print` (a bound-method
  ## attribute). Modelled as a stub method proc so `progress.print(…)` is
  ## callable (faithful to the call sites); `*objects: Any` →
  ## `varargs[RenderableValue]` (the `toRenderableValue*` converters accept
  ## `str`/`RenderableBase`). body delegates to the real `Console.print`.
  let c = Console(self.console)
  var objs: seq[RenderableValue] = @[]
  for r in renderables:
    objs.add(r)
  c.print(objs)

proc log*(self: Progress, renderables: varargs[RenderableValue]) =
  ## rich progress.py:1112 — `self.log = self.console.log` (a bound-method
  ## attribute). Modelled as a stub method proc so `progress.log(…)` is
  ## callable; `*objects: Any` → `varargs[RenderableValue]`. body delegates
  ## to the real `Console.log`.
  let c = Console(self.console)
  var objs: seq[RenderableValue] = @[]
  for r in renderables:
    objs.add(r)
  c.log(objs)

proc track*[T](self: Progress, sequence: openArray[T],
               total: Option[float] = none(float), completed: int = 0,
               taskId: Option[TaskID] = none(TaskID),
               description: string = "Working...",
               updatePeriod: float = 0.1): seq[T] =
  ## rich progress.py:1192-1235 — `Progress.track(self, sequence: Iterable[
  ## ProgressType], total: Optional[float] = None, completed: int = 0, task_id:
  ## Optional[TaskID] = None, description: str = "Working...", update_period:
  ## float = 0.1) -> Iterable[ProgressType]`: create/update the task, then yield
  ## each value while a `_TrackThread` (auto_refresh) or a manual advance loop
  ## updates progress (progress.py:1209-1233). `ProgressType` TypeVar → Nim
  ## generic `T`; `Iterable[ProgressType]` → `openArray[T]` in / `seq[T]` out
  ## (a stub cannot `yield`, so the generator is materialised); `task_id:
  ## Optional[TaskID] = None` → `Option[TaskID]`, default `none(TaskID)`. Phase
  ## 0 stub.
  # Faithful (progress.py:1209-1233): recover `total` from `length_hint` (the
  # `openArray` length; `float(0) or None` → `None` when the sequence is
  # empty), create/update the task, then iterate. The auto-refresh
  # `_TrackThread` (progress.py:1219-1223) is a Phase-0 stub, so it is
  # collapsed to a synchronous per-item `advance`; the non-auto branch
  # additionally forces a manual `refresh()` per item (progress.py:1228-1233).
  # A stub cannot `yield`, so the iterable is materialised into a `seq[T]`.
  var totalOpt = total
  if totalOpt.isNone and sequence.len > 0:
    totalOpt = some(float(sequence.len))
  var tid: TaskID
  if taskId.isNone:
    tid = self.addTask(description, total = totalOpt, completed = completed)
  else:
    tid = taskId.get
    self.update(tid, total = totalOpt, completed = some(float(completed)))
  result = newSeq[T](sequence.len)
  for i in 0 ..< sequence.len:
    result[i] = sequence[i]
    self.advance(tid, 1.0)
    if not self.live.autoRefresh:
      self.refresh()

proc wrapFile*(self: Progress, file: BinaryIo, total: Option[int] = none(int),
               taskId: Option[TaskID] = none(TaskID),
               description: string = "Reading..."): BinaryIo =
  ## rich progress.py:1237-1262 — `Progress.wrap_file(self, file: BinaryIO, total:
  ## Optional[int] = None, *, task_id: Optional[TaskID] = None, description: str
  ## = "Reading...") -> BinaryIO`: recover/create the task and return a
  ## `_Reader(file, self, task_id, close_handle=False)` (progress.py:1253-1261).
  ## Keyword-only after `total`. `file: BinaryIO` → `BinaryIo`; `total:
  ## Optional[int] = None` → `Option[int]`; returns `BinaryIo` (the `_Reader`).
  # Faithful (progress.py:1246-1261): recover `total_bytes` from the param or
  # the task's existing `total` (under `lockField`); raise `ValueError` if no
  # total is available; create or update the task; return a `_Reader`. The
  # `Reader`/`BinaryIo` are both `ref object of RootObj` (no Nim subtype), so
  # the `_Reader` is produced via `initReader` and `cast` to the `BinaryIo`
  # return (pointer-sized refs). `initReader` is a Phase-0 stub (returns nil)
  # until the `_Reader` body is wired.
  var totalBytes: Option[float] = none(float)
  if total.isSome:
    totalBytes = some(float(total.get))
  elif taskId.isSome:
    withLock self.lockField:
      totalBytes = self.tasksMap[taskId.get].total
  if totalBytes.isNone:
    raise newException(ValueError,
        "unable to get the total number of bytes, please specify 'total'")
  var tid: TaskID
  if taskId.isNone:
    tid = self.addTask(description, total = totalBytes)
  else:
    tid = taskId.get
    self.update(tid, total = totalBytes)
  result = cast[BinaryIo](initReader(file, self, tid, closeHandle = false))

proc open*(self: Progress, file: string, mode: string = "r", buffering: int = -1,
          encoding: Option[string] = none(string), errors: Option[string] = none(string),
          newline: Option[string] = none(string), total: Option[int] = none(int),
          taskId: Option[TaskID] = none(TaskID),
          description: string = "Reading..."): BinaryIo =
  ## rich progress.py:1280-1386 — `Progress.open(self, file, mode: "r" = …,
  ## buffering: int = -1, encoding/errors/newline: Optional[str] = None, *,
  ## total: Optional[int] = None, task_id: Optional[TaskID] = None, description:
  ## str = "Reading...") -> Union[BinaryIO, TextIO]`: normalise `mode`,
  ## patch `buffering`, `os.stat` for `total` if needed, create/update the
  ## task, `io.open(file, "rb", …)`, wrap in a `_Reader`, and a `TextIOWrapper`
  ## for text mode (progress.py:1320-1384). `file: Union[str, PathLike[str],
  ## bytes]` → `string` (the `str` arm; `PathLike`/`bytes` deferred); `mode` →
  ## `string = "r"`; returns `BinaryIo` (the reader / text wrapper). body
  ## body needs `io.open`/`os.stat`/`TextIOWrapper`.
  # Faithful (progress.py:1340-1384): normalise `mode` (`_mode = "".join(sorted
  # (mode))` — the only raw modes sorting into `("br","rt","r")` are
  # `{"r","rb","br","rt","tr"}`); patch `buffering` — binary line-buffering
  # (== 1) → -1 (Python emits a `RuntimeWarning`, deferred: no `std/warnings`
  # in scope), text unbuffered (== 0) → `ValueError`; the patched value is
  # consumed by the deferred `io.open` (body), so only the `ValueError` is
  # observable now. `os.stat(file).st_size` for `total` via `getFileSize`;
  # create/update the task.
  if not (mode == "r" or mode == "rb" or mode == "br" or mode == "rt" or mode == "tr"):
    raise newException(ValueError, "invalid mode '" & mode & "'")
  if not (mode == "rb" or mode == "br"):
    if buffering == 0:
      raise newException(ValueError, "can't have unbuffered text I/O")
  var totalOpt = total
  if totalOpt.isNone:
    totalOpt = some(int(getFileSize(file)))
  var tid: TaskID
  if taskId.isNone:
    tid = self.addTask(description, total = some(float(totalOpt.get)))
  else:
    tid = taskId.get
    self.update(tid, total = some(float(totalOpt.get)))
  # body: `io.open(file, "rb", buffering=<patched>)` + `_Reader(handle, …,
  # close_handle=True)` + the text-mode `TextIOWrapper(reader, encoding=…,
  # errors=…, newline=…, line_buffering=(buffering == 1))` wrap
  # (progress.py:1369-1384) need a real IO handle, not yet available; return a
  # default (nil) reader until then.
  result = default(BinaryIo)

proc startTask*(self: Progress, taskId: TaskID) =
  ## rich progress.py:1388-1400 — `Progress.start_task(self, task_id: TaskID) ->
  ## None`: under the lock, set `task.start_time = self.get_time()` if not set
  ## (progress.py:1392-1397).
  # Faithful (progress.py:1392-1397): under `lockField`, set `task.start_time`
  # to the current clock only if not already set. `self.getTime()` calls the
  # `Progress.getTime` field (the clock callable), not the `Task.getTime*` proc.
  withLock self.lockField:
    let task = self.tasksMap[taskId]
    if task.startTime.isNone:
      task.startTime = some(self.getTime())

proc stopTask*(self: Progress, taskId: TaskID) =
  ## rich progress.py:1402-1415 — `Progress.stop_task(self, task_id: TaskID) ->
  ## None`: under the lock, set `task.start_time`/`task.stop_time =
  ## self.get_time()` (progress.py:1407-1413).
  # Faithful (progress.py:1407-1413): under `lockField`, read the current
  # clock, seed `start_time` if unset, then set `stop_time` (freezing the
  # elapsed time).
  withLock self.lockField:
    let task = self.tasksMap[taskId]
    let currentTime = self.getTime()
    if task.startTime.isNone:
      task.startTime = some(currentTime)
    task.stopTime = some(currentTime)

proc update*(self: Progress, taskId: TaskID, total: Option[float] = none(float),
             completed: Option[float] = none(float), advance: Option[float] = none(float),
             description: Option[string] = none(string),
             visible: Option[system.bool] = none(system.bool), refresh: bool = false,
             fields: Meta = default(Meta)) =
  ## rich progress.py:1417-1476 — `Progress.update(self, task_id: TaskID, *,
  ## total: Optional[float] = None, completed: Optional[float] = None, advance:
  ## Optional[float] = None, description: Optional[str] = None, visible:
  ## Optional[bool] = None, refresh: bool = False, **fields: Any) -> None`:
  ## under the lock, update the task fields, trim/append the `_progress` deque,
  ## set `finished_time` if completed ≥ total; `refresh()` if `refresh`
  ## (progress.py:1432-1475). Keyword-only after `task_id` (Python `*`,
  ## progress.py:1418). `total`/`completed`/`advance: Optional[float] = None` →
  ## `Option[float]`; `description: Optional[str] = None` → `Option[string]`;
  ## `visible: Optional[bool] = None` → `Option[bool]`; `**fields: Any` →
  ## `fields: Meta = default(Meta)` (Nim has no `**kwargs`).
  # Faithful (progress.py:1432-1475): under `lockField`, snapshot `completed`,
  # reset the task if `total` changed (the explicit `task.total.isNone or …`
  # form avoids relying on `Option[float]` `!=` for the float payload), apply
  # `advance`/`completed`/`description`/`visible`, merge `fields`, trim/append
  # the `progress` deque, set `finished_time` when `completed >= total`;
  # `refresh()` OUTSIDE the lock if `refresh`.
  withLock self.lockField:
    let task = self.tasksMap[taskId]
    let completedStart = task.completed
    if total.isSome and (task.total.isNone or task.total.get != total.get):
      task.total = total
      task.taskReset()
    if advance.isSome:
      task.completed += advance.get
    if completed.isSome:
      task.completed = completed.get
    if description.isSome:
      task.description = description.get
    if visible.isSome:
      task.visible = visible.get
    for k, v in fields.pairs:
      task.fields[k] = v
    let updateCompleted = task.completed - completedStart
    let currentTime = self.getTime()
    let oldSampleTime = currentTime - self.speedEstimatePeriod
    while task.progress.len > 0 and task.progress[0].timestamp < oldSampleTime:
      discard task.progress.popFirst()
    if updateCompleted > 0.0:
      task.progress.addLast((timestamp: currentTime, completed: updateCompleted))
    if task.total.isSome:
      if task.completed >= task.total.get and task.finishedTime.isNone:
        task.finishedTime = task.elapsed
  if refresh:
    self.refresh()

# `TaskID` `hash`/`==` — `distinct int` does not auto-borrow the base `int`
# `hash`/`==`, so the `Table[TaskID, Task]` keyed ops (`tasksMap[taskId]`, `del`,
# `hasKey`) cannot resolve without these. Anticipated by `import std/hashes`
# (line 108) + the `initProgressColumn` note (the `TaskID` `hash` borrow);
# faithful to Python's `TaskID = NewType("TaskID", int)` (identity-equality +
# `hash(int)`). Explicit bodies (not `{.borrow.}`) sidestep the overloaded
# `std/hashes.hash` resolution ambiguity.
proc hash*(x: TaskID): Hash = hash(int(x))
proc `==`*(a, b: TaskID): bool = int(a) == int(b)

proc reset*(self: Progress, taskId: TaskID, start: bool = true,
            total: Option[float] = none(float), completed: int = 0,
            visible: Option[system.bool] = none(system.bool),
            description: Option[string] = none(string),
            fields: Meta = default(Meta)) =
  ## rich progress.py:1478-1515 — `Progress.reset(self, task_id: TaskID, *,
  ## start: bool = True, total: Optional[float] = None, completed: int = 0,
  ## visible: Optional[bool] = None, description: Optional[str] = None, **fields:
  ## Any) -> None`: under the lock, `_reset` the task, reset `start_time`/
  ## `total`/`completed`/`visible`/`fields`/`description`/`finished_time`, then
  ## `refresh()` (progress.py:1487-1513). Keyword-only after `task_id`. `**fields:
  ## Any` → `fields: Meta = default(Meta)`.
  let currentTime = self.getTime()
  withLock self.lockField:
    let task = self.tasksMap[taskId]
    task.taskReset()
    task.startTime = if start: some(currentTime) else: none(float)
    if total.isSome:
      task.total = total
    task.completed = float(completed)
    if visible.isSome:
      task.visible = visible.get
    if fields.len > 0:
      task.fields = fields
    if description.isSome:
      task.description = description.get
    task.finishedTime = none(float)
  self.refresh()

proc advance*(self: Progress, taskId: TaskID, advance: float = 1.0) =
  ## rich progress.py:1517-1545 — `Progress.advance(self, task_id: TaskID,
  ## advance: float = 1) -> None`: under the lock, `task.completed += advance`,
  ## trim/append `_progress`, set `finished_time`/`finished_speed` if completed
  ## ≥ total (progress.py:1525-1542).
  let currentTime = self.getTime()
  withLock self.lockField:
    let task = self.tasksMap[taskId]
    let completedStart = task.completed
    task.completed += advance
    let updateCompleted = task.completed - completedStart
    let oldSampleTime = currentTime - self.speedEstimatePeriod
    while task.progress.len > 0 and task.progress[0].timestamp < oldSampleTime:
      task.progress.popFirst()
    while task.progress.len > 1000:
      task.progress.popFirst()
    task.progress.addLast((timestamp: currentTime, completed: updateCompleted))
    if task.total.isSome and task.completed >= task.total.get and task.finishedTime.isNone:
      task.finishedTime = task.elapsed
      task.finishedSpeed = task.speed

proc refresh*(self: Progress) =
  ## rich progress.py:1547-1549 — `Progress.refresh(self) -> None`: if not
  ## `self.disable and self.live.is_started`, `self.live.refresh()`
  ## (progress.py:1548).
  if not self.disable and self.live.isStarted:
    self.live.refresh()

proc getRenderable*(self: Progress): RenderableType =
  ## rich progress.py:1552-1554 — `Progress.get_renderable(self) -> RenderableType`:
  ## `return Group(*self.get_renderables())` (progress.py:1553). Returns the
  ## faithful `RenderableType` typeclass (the `Group`). Body needs
  ## `Group`.
  result = initGroup(self.getRenderables())

proc getRenderables*(self: Progress): seq[RenderableValue] =
  ## rich progress.py:1557-1559 — `Progress.get_renderables(self) -> Iterable[
  ## RenderableType]`: `yield self.make_tasks_table(self.tasks)`
  ## (progress.py:1558). `Iterable[RenderableType]` → `seq[RenderableValue]`
  ## (materialised; a stub cannot `yield`).
  result.add(self.makeTasksTable(self.tasks))

proc makeTasksTable*(self: Progress, tasks: openArray[Task]): table.Table =
  ## rich progress.py:1562-1593 — `Progress.make_tasks_table(self, tasks:
  ## Iterable[Task]) -> Table`: build a `Table.grid(…)` of the column table-
  ## columns and add a row per visible task, calling each column (str columns
  ## via `.format(task=task)`, `ProgressColumn`s via `column(task)`) (progress.py:
  ## 1567-1591). Returns the concrete `Table` (from `table.nim`). Body
  ## needs `Table.grid`/`Column`.
  result = Table.grid(padding = (0, 1), expand = self.expand)
  # `table_columns` (progress.py:1567-1572): `Column(no_wrap=True)` for a str
  # column, else `_column.get_table_column().copy()`. `grid`'s varargs `*headers`
  # can't be splatted from a runtime `seq`, so (mirroring `grid`'s `thColumn`
  # header-append in `table.nim` `initTable`) each column's `index` is set and it
  # is appended straight to `result.columns`.
  for colArg in self.columns:
    var col: Column
    case colArg.kind
    of cakStr: col = initColumn(noWrap = true)
    of cakColumn: col = colArg.columnv.getTableColumn().copy()
    col.index = result.columns.len
    result.columns.add(col)
  # one row per visible task (progress.py:1574-1591): each cell is the column's
  # render — a str column via `str.format(task=task)` (reused through a
  # transient `TextColumn.render`, which ports the same `{task.<f>[:<spec>}`
  # mini-language, progress.py:635-644; the `Text` renders like a `str` cell —
  # markup at render, base `style="none"` no-op, no highlighter), or a
  # `ProgressColumn` via `column(task)` (`ProgressColumn.__call__`). Cells append
  # to each column's `rawCells` + a `Row` is added, mirroring `Table.add_row`
  # (table.py:425-466). The `column(task)` arm crosses the body
  # `RenderableType`→`RenderableValue` bridge (cf. `ProgressColumn.call`'s cache
  # store, progress.py:528-542) — the codebase-wide deferred gap.
  for task in tasks:
    if task.visible:
      for i, colArg in self.columns:
        case colArg.kind
        of cakStr:
          result.columns[i].rawCells.add(initTextColumn(colArg.strv).render(task))
        of cakColumn:
          result.columns[i].rawCells.add(colArg.columnv.call(task))
      result.rows.add(initRow())

proc richCast*(self: Progress): RenderableType =
  ## rich progress.py:1595-1597 — `Progress.__rich__(self) -> RenderableType`:
  ## `with self._lock: return self.get_renderable()` (progress.py:1596). Dunder
  ## mapping `__rich__`→`richCast`; returns the faithful `RenderableType`
  ## typeclass.
  withLock self.lockField:
    result = self.getRenderable()

proc addTask*(self: Progress, description: string, start: bool = true,
              total: Option[float] = some(100.0), completed: int = 0,
              visible: bool = true, fields: Meta = default(Meta)): TaskID =
  ## rich progress.py:1600-1641 — `Progress.add_task(self, description: str,
  ## start: bool = True, total: Optional[float] = 100.0, completed: int = 0,
  ## visible: bool = True, **fields: Any) -> TaskID`: under the lock, build a
  ## `Task(self._task_index, description, total, completed, visible=visible,
  ## fields=fields, _get_time=self.get_time, _lock=self._lock)`, store it,
  ## `start_task` if `start`, bump `_task_index`, `refresh()`, return the id
  ## (progress.py:1619-1639). `total: Optional[float] = 100.0` → `Option[float]`,
  ## default `some(100.0)`; `**fields: Any` → `fields: Meta = default(Meta)`;
  ## returns `TaskID`.
  var newTaskIndex: TaskID
  withLock self.lockField:
    let task = Task(
      id: self.taskIndex,
      description: description,
      total: total,
      completed: float(completed),
      getTime: self.getTime,
      finishedTime: none(float),
      visible: visible,
      fields: fields,
      startTime: none(float),
      stopTime: none(float),
      finishedSpeed: none(float),
      progress: initDeque[ProgressSample](),
      lock: self.lockField)
    self.tasksMap[self.taskIndex] = task
    if start:
      # Inline `startTask` logic (progress.py:1392-1397) to avoid nested
      # `withLock self.lockField` — std/locks.Lock is NOT reentrant, so calling
      # `self.startTask` here (which takes the same lock) deadlocks. Python
      # uses RLock (reentrant); Nim's `Lock` is not. Set `start_time` directly.
      let startedTask = self.tasksMap[self.taskIndex]
      if startedTask.startTime.isNone:
        startedTask.startTime = some(self.getTime())
    newTaskIndex = self.taskIndex
    self.taskIndex = TaskID(int(self.taskIndex) + 1)
  self.refresh()
  result = newTaskIndex

proc removeTask*(self: Progress, taskId: TaskID) =
  ## rich progress.py:1643-1649 — `Progress.remove_task(self, task_id: TaskID) ->
  ## None`: under the lock, `del self._tasks[task_id]` (progress.py:1647). Phase
  ## 0 stub.
  withLock self.lockField:
    self.tasksMap.del(taskId)

# ---------------------------------------------------------------------------
# _TrackThread / _Reader / _ReadContext (module-private)
# ---------------------------------------------------------------------------

proc initTrackThread*(progress: Progress, taskId: TaskID,
                      updatePeriod: float): TrackThread =
  ## rich progress.py:67-73 — `_TrackThread.__init__(self, progress: "Progress",
  ## task_id: "TaskID", update_period: float)`: store `progress`/`task_id`/
  ## `update_period`, `self.done = Event()`, `self.completed = 0`,
  ## `super().__init__(daemon=True)` (progress.py:69-73). Module-private (the
  ## type is private).
  result = TrackThread()
  result.progressHandle = progress
  result.taskId = taskId
  result.updatePeriod = updatePeriod
  result.done = false
  result.completed = 0.0
  # `super().__init__(daemon=True)` (progress.py:73): the `Thread` base + the
  # daemon flag are a body threading concern (the `TrackThread` type is `ref
  # object of RootObj`, not `of Thread`, and `done` is a stub `bool` stand-in for
  # `Event()`, line 356) — deferred; `done = false` mirrors the `Event()` initial
  # unset state.

proc run*(self: TrackThread) =
  ## rich progress.py:76-88 — `_TrackThread.run(self) -> None`: loop
  ## `while not wait(update_period) and self.progress.live.is_started`,
  ## advancing the task on `completed` change, then a final `update`
  ## (progress.py:78-87). Module-private.
  # `while not wait(update_period) and self.progress.live.is_started` (progress.py:
  # 78-87): the loop hinges on `self.done.wait(update_period)` — `Event.wait`
  # with a timeout, a blocking sleep returning `True` once `done.set()` fires
  # (else `False` after `update_period`). `done` is a stub `bool` stand-in (line
  # 356; `Event.wait`/`set`/`is_set` deferred to body), so the loop — and the
  # running `completed` it accumulates (advanced via `self.progress.advance` and
  # flushed by the final `self.progress.update(self.task_id, completed=self.
  # completed, refresh=True)`, progress.py:82-87) — is unportable until `Event`
  # + `std/threads` land. Module-private. body deferred to body.
  discard

proc enter*(self: TrackThread): TrackThread =
  ## rich progress.py:90-92 — `_TrackThread.__enter__(self) -> "_TrackThread"`:
  ## `self.start(); return self` (progress.py:91). Module-private. port
  ## stub.
  # `self.start()` (progress.py:91) is `Thread.start()` — spawning the daemon
  # thread that runs `run` (progress.py:76-88). `TrackThread` is `ref object of
  # RootObj`, NOT `std/threads.Thread`, and `run` is itself a deferred no-op (no
  # `Event.wait`/real threading), so `Thread.start()` has no portable target
  # here (`createThread` + a thread proc is a body concern). Only the
  # `return self` (progress.py:91) is portable.
  result = self

proc exit*(self: TrackThread, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich progress.py:94-101 — `_TrackThread.__exit__(self, exc_type, exc_val,
  ## exc_tb) -> None`: `self.done.set(); self.join()` (progress.py:99-100).
  ## Module-private.
  # `self.done.set()` (progress.py:99): `done` is a stub `bool` stand-in for
  # `threading.Event` (`initTrackThread` seeds it `false`; `Event.set()` →
  # `self.done = true`, the signal `run`'s `wait()` loop would exit on). The
  # `self.join()` (progress.py:100) blocks until the daemon thread from `enter`
  # finishes; with no real `Thread` base and `run` a no-op there is nothing to
  # join — deferred to body (`std/threads`). Only the `set()` is portable.
  self.done = true

proc initReader*(handle: BinaryIo, progress: Progress, task: TaskID,
                closeHandle: bool = true): Reader =
  ## rich progress.py:185-195 — `_Reader.__init__(self, handle: BinaryIO,
  ## progress: "Progress", task: TaskID, close_handle: bool = True) -> None`:
  ## store `handle`/`progress`/`task`/`close_handle`, `self._closed = False`
  ## (progress.py:190-195). Module-private.
  # Faithful (progress.py:190-195): store the five `__init__` fields. `progress`
  # → `progressHandle` (renamed to avoid shadowing the `progress` module); the
  # `RawIOBase`/`BinaryIO` bases are modelled via the `BinaryIo` forward handle
  # (line 141, a `ref object of RootObj` placeholder), so `handle` is stored
  # opaquely. `self._closed = False` → `closed = false` (progress.py:195).
  result = Reader()
  result.handle = handle
  result.progressHandle = progress
  result.task = task
  result.closeHandle = closeHandle
  result.closed = false

proc enter*(self: Reader): Reader =
  ## rich progress.py:198-200 — `_Reader.__enter__(self) -> "_Reader"`:
  ## `self.handle.__enter__(); return self` (progress.py:199). Module-private.
  # Faithful portable subset of progress.py:199. The `self.handle.__enter__()`
  # half is not portable — `BinaryIo` (line 141) is an opaque forward handle
  # with no `__enter__` surface (deferred to body). io's `__enter__` contract
  # for file-like objects returns `self`, so `result = self` is the faithful
  # portable subset (cf. `TrackThread.enter`/`ReadContext.enter`).
  result = self

proc exit*(self: Reader, excType: Option[RootRef],
          excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich progress.py:202-207 — `_Reader.__exit__(self, exc_type, exc_val,
  ## exc_tb) -> None`: `self.close()` (progress.py:206). Module-private. Phase
  ## 0 stub.
  # Faithful (progress.py:206): `self.close()` → `closeReader` (renamed
  # `close`→`closeReader` to avoid overloading `system.close`; see line 2254).
  # The `excType`/`excVal`/`excTb` params are an unused pass-through (Python's
  # `__exit__` ignores them here), matching the contract.
  self.closeReader()

proc iter*(self: Reader): Reader =
  ## rich progress.py:210-211 — `_Reader.__iter__(self) -> BinaryIO`:
  ## `return self` (progress.py:211). Dunder mapping `__iter__`→`iter`. Module-
  ## private.
  # Faithful (progress.py:211): `return self` — a `_Reader` is its own iterator
  # (`__next__` reads one line per call). The `BinaryIO` return widens to the
  # `Reader` ref here (the handle protocol is opaque).
  result = self

proc next*(self: Reader): string =
  ## rich progress.py:213-216 — `_Reader.__next__(self) -> bytes`:
  ## `line = next(self.handle); self.progress.advance(self.task, advance=len(
  ## line)); return line` (progress.py:214-215). Dunder mapping `__next__`→`next`;
  ## `bytes` → `string` (Nim has no `bytes`; the binary line is a `string`).
  ## Module-private.
  # `next(self.handle)` (progress.py:214) drives the wrapped handle's own
  # iterator (`__next__`), then `self.progress.advance(self.task, advance=len(
  # line))` (progress.py:215). `BinaryIo` is a `ref object of RootObj` forward
  # placeholder (line 141) exposing no iterator/IO surface, so the call has no
  # portable target until a concrete binary-stream handle lands (body);
  # `discard` returns the `string` default (`""`).
  discard

proc closed*(self: Reader): bool =
  ## rich progress.py:218-220 — `_Reader.closed` property (`@property`
  ## progress.py:219): `return self._closed` (progress.py:220). Module-private.
  # Faithful (progress.py:220): `return self._closed`. Nim resolves `self.closed`
  # to the `closed*` FIELD (same field/proc name-sharing as `Task.getTime`, where
  # `self.getTime` reads the stored callable field — `x.f` is field access when a
  # field `f` exists, so the same-named proc is NOT re-entered), returning the
  # private flag seeded `false` by `initReader` (progress.py:195).
  result = self.closed

proc fileno*(self: Reader): int =
  ## rich progress.py:222-223 — `_Reader.fileno(self) -> int`:
  ## `return self.handle.fileno()` (progress.py:223). Module-private. port
  ## stub.
  # `return self.handle.fileno()` (progress.py:223): `fileno` lives on the
  # wrapped `BinaryIO`/`RawIOBase` handle, but `BinaryIo` is a `ref object of
  # RootObj` forward placeholder (line 141) with no I/O surface — no portable
  # target until a concrete binary-stream handle lands (body); `discard`
  # returns the `int` default (`0`).
  discard

proc isatty*(self: Reader): bool =
  ## rich progress.py:225-226 — `_Reader.isatty(self) -> bool`:
  ## `return self.handle.isatty()` (progress.py:226). Module-private. port
  ## stub.
  # `return self.handle.isatty()` (progress.py:226): `isatty` lives on the
  # wrapped `BinaryIO`/`RawIOBase` handle, but `BinaryIo` is a `ref object of
  # RootObj` forward placeholder (line 141) with no I/O surface — no portable
  # target until a concrete binary-stream handle lands (body); `discard`
  # returns the `bool` default (`false`).
  discard

proc modeReader*(self: Reader): string =
  ## rich progress.py:228-230 — `_Reader.mode` property (`@property`
  ## progress.py:229): `return self.handle.mode` (progress.py:230). Renamed
  ## `mode`→`modeReader` (module-private; `mode` would clash with the `mode`
  ## params of `open`).
  # `return self.handle.mode` (progress.py:230): `mode` lives on the wrapped
  # `BinaryIO`/`TextIO` handle, but `BinaryIo` is a `ref object of RootObj`
  # forward placeholder (line 141) with no `mode` field — no portable target
  # until a concrete binary-stream handle lands (body); `discard` returns
  # the `string` default (`""`).
  discard

proc nameReader*(self: Reader): string =
  ## rich progress.py:232-234 — `_Reader.name` property (`@property`
  ## progress.py:233): `return self.handle.name` (progress.py:234). Renamed
  ## `name`→`nameReader` (module-private).
  # `return self.handle.name` (progress.py:234): `name` lives on the wrapped
  # `BinaryIO`/`TextIO` handle, but `BinaryIo` is a `ref object of RootObj`
  # forward placeholder (line 141) with no `name` field — no portable target
  # until a concrete binary-stream handle lands (body); `discard` returns
  # the `string` default (`""`).
  discard

proc readable*(self: Reader): bool =
  ## rich progress.py:236-237 — `_Reader.readable(self) -> bool`:
  ## `return self.handle.readable()` (progress.py:237). Module-private. port
  ## stub.
  # `return self.handle.readable()` (progress.py:237): `readable` lives on the
  # wrapped `BinaryIO`/`RawIOBase` handle, but `BinaryIo` is a `ref object of
  # RootObj` forward placeholder (line 141) with no I/O surface — no portable
  # target until a concrete binary-stream handle lands (body); `discard`
  # returns the `bool` default (`false`).
  discard

proc seekable*(self: Reader): bool =
  ## rich progress.py:239-240 — `_Reader.seekable(self) -> bool`:
  ## `return self.handle.seekable()` (progress.py:240). Module-private. port
  ## stub.
  # `return self.handle.seekable()` (progress.py:240): `seekable` lives on the
  # wrapped `BinaryIO`/`RawIOBase` handle, but `BinaryIo` is a `ref object of
  # RootObj` forward placeholder (line 141) with no I/O surface — no portable
  # target until a concrete binary-stream handle lands (body); `discard`
  # returns the `bool` default (`false`).
  discard

proc writable*(self: Reader): bool =
  ## rich progress.py:242-243 — `_Reader.writable(self) -> bool: return False`
  ## (progress.py:243). Module-private.
  # Faithful (progress.py:243): `return False` — a literal constant, NOT a
  # `self.handle.writable()` delegation (unlike `readable`/`seekable`): a
  # `_Reader` wraps a handle opened for reading, so it is never writable.
  result = false

proc read*(self: Reader, size: int = -1): string =
  ## rich progress.py:245-248 — `_Reader.read(self, size: int = -1) -> bytes`:
  ## `block = self.handle.read(size); self.progress.advance(self.task, advance=
  ## len(block)); return block` (progress.py:246-247). `bytes` → `string`.
  ## Module-private.
  # GENUINE NO-OP: `self.handle.read` is not callable on the opaque `BinaryIo`
  # forward handle (line 141); kept as `discard` (returns `""`) until body.
  # `block = self.handle.read(size); self.progress.advance(self.task, advance=
  # len(block)); return block` (progress.py:246-247): `read` lives on the wrapped
  # `BinaryIO`/`RawIOBase` handle, but `BinaryIo` is a `ref object of RootObj`
  # forward placeholder (line 141) with no I/O surface — no portable target
  # until a concrete binary-stream handle lands (body); `discard` returns
  # the `string` default (`""`).
  discard

proc readinto*(self: Reader, b: var seq[byte]): int =
  ## rich progress.py:250-253 — `_Reader.readinto(self, b: Union[bytearray,
  ## memoryview, mmap]) -> int`: `n = self.handle.readinto(b);
  ## self.progress.advance(self.task, advance=n); return n` (progress.py:251-
  ## 252). The buffer is `var seq[byte]` (a simplified stand-in for
  ## `bytearray`/`memoryview`/`mmap`; body may widen). Module-private. Phase
  ## 0 stub.
  # GENUINE NO-OP: `self.handle.readinto` is not callable on the opaque
  # `BinaryIo` forward handle (line 141); kept as `discard` (returns `0`).
  # `n = self.handle.readinto(b); self.progress.advance(self.task, advance=n);
  # return n` (progress.py:251-252): `readinto` lives on the wrapped `BinaryIO`/
  # `RawIOBase` handle, but `BinaryIo` is a `ref object of RootObj` forward
  # placeholder (line 141) with no I/O surface — no portable target until a
  # concrete binary-stream handle lands (body); `discard` returns the `int`
  # default (`0`).
  discard

proc readline*(self: Reader, size: int = -1): string =
  ## rich progress.py:255-258 — `_Reader.readline(self, size: int = -1) ->
  ## bytes`: `line = self.handle.readline(size); self.progress.advance(
  ## self.task, advance=len(line)); return line` (progress.py:256-257). `bytes`
  ## → `string`. Module-private.
  # GENUINE NO-OP: `self.handle.readline` is not callable on the opaque
  # `BinaryIo` forward handle (line 141); kept as `discard` (returns `""`).
  discard

proc readlines*(self: Reader, hint: int = -1): seq[string] =
  ## rich progress.py:260-263 — `_Reader.readlines(self, hint: int = -1) ->
  ## List[bytes]`: `lines = self.handle.readlines(hint); self.progress.advance(
  ## self.task, advance=sum(map(len, lines))); return lines` (progress.py:261-
  ## 262). `List[bytes]` → `seq[string]`. Module-private.
  # GENUINE NO-OP: `self.handle.readlines` is not callable on the opaque
  # `BinaryIo` forward handle (line 141); kept as `discard` (returns `@[]`).
  discard

proc closeReader*(self: Reader) =
  ## rich progress.py:265-268 — `_Reader.close(self) -> None`: if `close_handle`,
  ## `self.handle.close()`; `self._closed = True` (progress.py:266-267).
  ## Renamed `close`→`closeReader` (module-private; avoids overloading
  ## `system.close`).
  # Faithful portable subset of progress.py:266-267. The `if self.close_handle:
  # self.handle.close()` half is not portable — `BinaryIo` (line 141) is an
  # opaque forward handle with no `close` surface (deferred to body). The
  # `self._closed = True` assignment is unconditional in Python (outside the
  # `if close_handle`), so `self.closed = true` here is the faithful subset.
  # (`self.closed` resolves to the `closed*` field, not the `closed*` accessor
  # proc — see line 2128; assignment always targets the field.)
  self.closed = true

proc seekReader*(self: Reader, offset: int, whence: int = 0): int =
  ## rich progress.py:270-273 — `_Reader.seek(self, offset: int, whence: int = 0)
  ## -> int`: `pos = self.handle.seek(offset, whence); self.progress.update(
  ## self.task, completed=pos); return pos` (progress.py:271-272). Renamed
  ## `seek`→`seekReader` (module-private; `seek` clashes with `system.seek`).
  # GENUINE NO-OP: `self.handle.seek` is not callable on the opaque `BinaryIo`
  # forward handle (line 141); kept as `discard` (returns `0`) until body.
  discard

proc tell*(self: Reader): int =
  ## rich progress.py:275-276 — `_Reader.tell(self) -> int`:
  ## `return self.handle.tell()` (progress.py:276). Module-private. port
  ## stub.
  # GENUINE NO-OP: `self.handle.tell` is not callable on the opaque `BinaryIo`
  # forward handle (line 141); kept as `discard` (returns `0`) until body.
  discard

proc writeReader*(self: Reader, s: string): int =
  ## rich progress.py:278-279 — `_Reader.write(self, s: Any) -> int`: `raise
  ## UnsupportedOperation("write")` (progress.py:279). Renamed `write`→
  ## `writeReader` (module-private; `write` would clash with the `write*`
  ## method names of other types). `s: Any` → `string` (simplified). port
  ## stub.
  # Faithful (progress.py:279): `raise UnsupportedOperation("write")`. Python's
  # `io.UnsupportedOperation` subclasses both `OSError` and `ValueError`; Nim
  # has no equivalent, so it maps to the built-in `IOError` — the codebase's
  # IO-error convention (e.g. theme.nim:156 `raise newException(IOError, ...)`).
  # A `_Reader` wraps a read handle, so `write` is an unsupported operation.
  raise newException(IOError, "write")

proc writelinesReader*(self: Reader, lines: openArray[string]) =
  ## rich progress.py:281-282 — `_Reader.writelines(self, lines: Iterable[Any])
  ## -> None`: `raise UnsupportedOperation("writelines")` (progress.py:282).
  ## Renamed `writelines`→`writelinesReader` (module-private).
  # Faithful (progress.py:282): `raise UnsupportedOperation("writelines")`. As
  # with `writeReader`, `io.UnsupportedOperation` (OSError+ValueError subclass)
  # maps to the built-in `IOError` (codebase convention; theme.nim:156).
  raise newException(IOError, "writelines")

proc initReadContext*(progress: Progress, reader: BinaryIo): ReadContext =
  ## rich progress.py:288-293 — `_ReadContext.__init__(self, progress: "Progress",
  ## reader: _I) -> None`: store `progress`/`reader` (progress.py:291-293).
  ## Module-private.
  # Faithful (progress.py:291-293): `self.progress = progress; self.reader =
  # reader`. `ReadContext` is a `ref object`, so `ReadContext(...)` allocates a
  # new instance and initializes both fields (the only two; see lines 384-385).
  result = ReadContext(progressHandle: progress, reader: reader)

proc enter*(self: ReadContext): BinaryIo =
  ## rich progress.py:292-294 — `_ReadContext.__enter__(self) -> _I`:
  ## `self.progress.start(); return self.reader.__enter__()` (progress.py:293-
  ## 294). Returns the `BinaryIo` handle (the `_I`). Module-private. port
  ## stub.
  # Faithful portable subset of progress.py:293-294. `self.progress.start()`
  # (progress.py:293) is portable — `Progress.start*` (line 1577) calls
  # `self.live.start(refresh=true)`. The `return self.reader.__enter__()`
  # (progress.py:294) half is not portable — `BinaryIo` (line 141) is an opaque
  # forward handle with no `__enter__` surface. io's `__enter__` contract for
  # file-like objects returns `self`, so `result = self.reader` is the faithful
  # portable subset (matching the docstring: "Returns the `BinaryIo` handle").
  self.progressHandle.start()
  result = self.reader

proc exit*(self: ReadContext, excType: Option[RootRef],
          excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich progress.py:296-304 — `_ReadContext.__exit__(self, exc_type, exc_val,
  ## exc_tb) -> None`: `self.progress.stop(); self.reader.__exit__(exc_type,
  ## exc_val, exc_tb)` (progress.py:300-303). Module-private.
  # Faithful portable subset of progress.py:300-303. `self.progress.stop()`
  # (progress.py:300) is portable — `Progress.stop*` (line 1584) calls
  # `self.live.stop()`. The `self.reader.__exit__(exc_type, exc_val, exc_tb)`
  # (progress.py:303) half is not portable — `BinaryIo` (line 141) has no
  # `__exit__` surface (deferred to body); the `excType`/`excVal`/`excTb`
  # params are therefore an unused pass-through, matching Python's contract.
  self.progressHandle.stop()

# ---------------------------------------------------------------------------
# Module-level functions: track / wrap_file / open
# ---------------------------------------------------------------------------

proc track*[T](sequence: openArray[T], description: string = "Working...",
               total: Option[float] = none(float), completed: int = 0,
               autoRefresh: bool = true, console: ConsoleHandle = nil,
               transient: bool = false, getTime: Option[GetTimeCallable] = none(GetTimeCallable),
               refreshPerSecond: float = 10.0, style: StyleType = "bar.back",
               completeStyle: StyleType = "bar.complete",
               finishedStyle: StyleType = "bar.finished",
               pulseStyle: StyleType = "bar.pulse", updatePeriod: float = 0.1,
               disable: bool = false, showSpeed: bool = true): seq[T] =
  ## rich progress.py:104-181 — `track(sequence: Iterable[ProgressType],
  ## description: str = "Working...", total: Optional[float] = None, completed:
  ## int = 0, auto_refresh: bool = True, console: Optional[Console] = None,
  ## transient: bool = False, get_time: Optional[Callable[[], float]] = None,
  ## refresh_per_second: float = 10, style: StyleType = "bar.back",
  ## complete_style: StyleType = "bar.complete", finished_style: StyleType =
  ## "bar.finished", pulse_style: StyleType = "bar.pulse", update_period: float
  ## = 0.1, disable: bool = False, show_speed: bool = True) -> Iterable[
  ## ProgressType]`: build the default columns, construct a `Progress`, and
  ## `yield from progress.track(…)` (progress.py:148-179). `ProgressType` TypeVar
  ## → Nim generic `T`; `Iterable[ProgressType]` → `openArray[T]` in / `seq[T]`
  ## out; `console: Optional[Console] = None` → `ConsoleHandle = nil`;
  ## `get_time: Optional[Callable[[], float]] = None` → `Option[
  ## GetTimeCallable]`; the four `StyleType` params → typeclass defaults. Phase
  ## 0 stub.
  # Faithful (progress.py:148-179): build the column list — a leading
  # `TextColumn("[progress.description]{task.description}")` iff `description`
  # is non-empty (Python `if description`, progress.py:148-149; the default
  # `"Working..."` is truthy), then `BarColumn(style=…, complete_style=…,
  # finished_style=…, pulse_style=…)`, `TaskProgressColumn(show_speed=showSpeed)`,
  # `TimeRemainingColumn(elapsed_when_finished=True)` (progress.py:150-159 —
  # NOTE: this `TimeRemainingColumn` takes `elapsed_when_finished=True`, unlike
  # `getDefaultColumns`/the `open` helper's default `False`, progress.py:159).
  # Each column widget (a `ProgressColumn` subtype) is wrapped in the `cakColumn`
  # arm of `ColumnArg` (matching `Progress.get_default_columns`, line 1507).
  # Construct the `Progress` (progress.py:161-168; `refresh_per_second or 10`
  # → guard `0.0`→`10.0` before the `initProgress` `> 0` assert; `expand`/
  # `speed_estimate_period`/`redirect_*` omitted by Python ⇒ defaults), then
  # `with progress:` (progress.py:170) ≡ `progress.start()` … `progress.stop()`
  # (the `Progress.enter`/`exit` context-manager pair, lines 1595/1602 — `enter`
  # calls `start`, `exit` calls `stop`), and `yield from progress.track(…)`
  # (progress.py:171-178). A stub cannot `yield`, so the iterable is
  # materialised: the instance `Progress.track` (line 1635) returns `seq[T]`
  # directly. `try`/`finally` mirrors `with progress:`, ensuring `stop()` runs
  # even if the iteration raises (Python `__exit__` guarantee); `start()` stays
  # outside the `try` so a `start` failure skips `stop` (Python `__enter__`
  # contract).
  var columns: seq[ColumnArg] = @[]
  if description.len > 0:
    columns.add ColumnArg(kind: cakColumn,
        columnv: initTextColumn("[progress.description]{task.description}"))
  columns.add ColumnArg(kind: cakColumn,
      columnv: initBarColumn(style = style, completeStyle = completeStyle,
          finishedStyle = finishedStyle, pulseStyle = pulseStyle))
  columns.add ColumnArg(kind: cakColumn,
      columnv: initTaskProgressColumn(showSpeed = showSpeed))
  columns.add ColumnArg(kind: cakColumn,
      columnv: initTimeRemainingColumn(elapsedWhenFinished = true))
  let rps = if refreshPerSecond != 0.0: refreshPerSecond else: 10.0
  let progress = initProgress(columns, console = console,
      autoRefresh = autoRefresh, refreshPerSecond = rps, transient = transient,
      getTime = getTime, disable = disable)
  progress.start()
  try:
    result = progress.track(sequence, total = total, completed = completed,
        description = description, updatePeriod = updatePeriod)
  finally:
    progress.stop()

proc wrapFile*(file: BinaryIo, total: int, description: string = "Reading...",
               autoRefresh: bool = true, console: ConsoleHandle = nil,
               transient: bool = false, getTime: Option[GetTimeCallable] = none(GetTimeCallable),
               refreshPerSecond: float = 10.0, style: StyleType = "bar.back",
               completeStyle: StyleType = "bar.complete",
               finishedStyle: StyleType = "bar.finished",
               pulseStyle: StyleType = "bar.pulse",
               disable: bool = false): BinaryIo =
  ## rich progress.py:306-339 — `wrap_file(file: BinaryIO, total: int, *,
  ## description: str = "Reading...", auto_refresh: bool = True, console:
  ## Optional[Console] = None, transient: bool = False, get_time: Optional[
  ## Callable[[], float]] = None, refresh_per_second: float = 10, style:
  ## StyleType = "bar.back", complete_style: StyleType = "bar.complete",
  ## finished_style: StyleType = "bar.finished", pulse_style: StyleType =
  ## "bar.pulse", disable: bool = False) -> ContextManager[BinaryIO]`: build
  ## the columns, construct a `Progress`, `reader = progress.wrap_file(file,
  ## total=total, description=description)`, return `_ReadContext(progress,
  ## reader)` (progress.py:330-337). Keyword-only after `total`. `file: BinaryIO`
  ## → `BinaryIo`; `total: int` (positional, required); returns `BinaryIo` (the
  ## `_ReadContext`).
  # Faithful (progress.py:322-337): build the column list — a leading
  # `TextColumn("[progress.description]{task.description}")` iff `description`
  # is non-empty (Python `if description`, progress.py:322-323), then
  # `BarColumn(style=…, complete_style=…, finished_style=…, pulse_style=…)`,
  # `DownloadColumn()`, `TimeRemainingColumn()` (progress.py:324-334 — the
  # `TimeRemainingColumn()` takes the DEFAULT `elapsed_when_finished=False`,
  # like the `open` helper, progress.py:333). Each column widget (a
  # `ProgressColumn` subtype) is wrapped in the `cakColumn` arm of `ColumnArg`
  # (matching `Progress.get_default_columns`, line 1507). Construct the
  # `Progress` (progress.py:336; `refresh_per_second or 10` → guard `0.0`→`10.0`
  # before the `initProgress` `> 0` assert; `expand`/`speed_estimate_period`/
  # `redirect_*` omitted by Python ⇒ defaults), then `reader = progress.
  # wrap_file(file, total=total, description=description)` (progress.py:336 —
  # `task_id` omitted ⇒ default `none`; the module `total: int` → `some(total)`
  # for the method's `Option[int]`, line 1673), and `return _ReadContext(progress,
  # reader)` (progress.py:337) → `cast[BinaryIo](initReadContext(progress,
  # reader))` (the `cast` mirrors `Progress.wrap_file`'s `cast[BinaryIo](
  # initReader(…))`, line 1705 — both `ReadContext`/`BinaryIo` are pointer-sized
  # `ref object of RootObj`; `initReadContext` is line 2308).
  var columns: seq[ColumnArg] = @[]
  if description.len > 0:
    columns.add ColumnArg(kind: cakColumn,
        columnv: initTextColumn("[progress.description]{task.description}"))
  columns.add ColumnArg(kind: cakColumn,
      columnv: initBarColumn(style = style, completeStyle = completeStyle,
          finishedStyle = finishedStyle, pulseStyle = pulseStyle))
  columns.add ColumnArg(kind: cakColumn, columnv: initDownloadColumn())
  columns.add ColumnArg(kind: cakColumn, columnv: initTimeRemainingColumn())
  let rps = if refreshPerSecond != 0.0: refreshPerSecond else: 10.0
  let progress = initProgress(columns, console = console,
      autoRefresh = autoRefresh, refreshPerSecond = rps, transient = transient,
      getTime = getTime, disable = disable)
  let reader = progress.wrapFile(file, total = some(total),
      description = description)
  result = cast[BinaryIo](initReadContext(progress, reader))

proc open*(file: string, mode: string = "r", buffering: int = -1,
          encoding: Option[string] = none(string), errors: Option[string] = none(string),
          newline: Option[string] = none(string), total: Option[int] = none(int),
          description: string = "Reading...", autoRefresh: bool = true,
          console: ConsoleHandle = nil, transient: bool = false,
          getTime: Option[GetTimeCallable] = none(GetTimeCallable),
          refreshPerSecond: float = 10.0, style: StyleType = "bar.back",
          completeStyle: StyleType = "bar.complete",
          finishedStyle: StyleType = "bar.finished",
          pulseStyle: StyleType = "bar.pulse",
          disable: bool = false): BinaryIo =
  ## rich progress.py:421-504 — `open(file: Union[str, PathLike[str], bytes],
  ## mode: Union[Literal["rb"], Literal["rt"], Literal["r"]] = "r",
  ## buffering: int = -1, encoding: Optional[str] = None, errors: Optional[str]
  ## = None, newline: Optional[str] = None, *, total: Optional[int] = None,
  ## description: str = "Reading...", auto_refresh: bool = True, console:
  ## Optional[Console] = None, transient: bool = False, get_time: Optional[
  ## Callable[[], float]] = None, refresh_per_second: float = 10, style:
  ## StyleType = "bar.back", complete_style: StyleType = "bar.complete",
  ## finished_style: StyleType = "bar.finished", pulse_style: StyleType =
  ## "bar.pulse", disable: bool = False) -> Union[ContextManager[BinaryIO],
  ## ContextManager[TextIO]]`: build the columns, construct a `Progress`, `reader
  ## = progress.open(file, mode=…, …)`, return `_ReadContext(progress, reader)`
  ## (progress.py:489-503). The two `@typing.overload` stubs (progress.py:372-
  ## 420) are type-check-only (not real functions) and omitted. `file: Union[str,
  ## PathLike[str], bytes]` → `string` (the `str` arm); `mode` → `string = "r"`;
  ## `total: Optional[int] = None` → `Option[int]`; returns `BinaryIo` (the
  ## `_ReadContext`). Body needs `io.open`/`os.stat`/`TextIOWrapper`.
  # Faithful (progress.py:483-503): build the column list — a leading
  # `TextColumn("[progress.description]{task.description}")` iff `description`
  # is non-empty (Python `if description`, progress.py:483-484; the default
  # `"Reading..."` is truthy), then `BarColumn(style=…, complete_style=…,
  # finished_style=…, pulse_style=…)`, `DownloadColumn()`,
  # `TimeRemainingColumn()` (progress.py:485-495 — NOTE: this
  # `TimeRemainingColumn()` takes the DEFAULT `elapsed_when_finished=False`,
  # unlike the `track` helper's `=True`, progress.py:159). Each column widget (a
  # `ProgressColumn` subtype) is wrapped in the `cakColumn` arm of `ColumnArg`,
  # matching `Progress.get_default_columns` (line 1516). Construct the `Progress`
  # (progress.py:497-499; `refresh_per_second or 10` → guard `0.0`→`10.0` before
  # the `initProgress` `> 0` assert; `expand`/`speed_estimate_period`/`redirect_*`
  # omitted by Python ⇒ defaults), then `reader = progress.open(file, mode=…,
  # buffering=…, encoding=…, errors=…, newline=…, total=…, description=…)`
  # (progress.py:501-502; `task_id` omitted ⇒ default `none`) and return
  # `_ReadContext(progress, reader)` (progress.py:503). Passing the `seq[
  # ColumnArg]` to `initProgress`'s `varargs[ColumnArg]` is the Nim varargs-as-seq
  # call form. `reader` is the `BinaryIo` from `Progress.open` (a Phase-1 stub
  # returning `default(BinaryIo)` until `io.open`/`TextIOWrapper` land), and
  # `_ReadContext` is `initReadContext` (a Phase-0 stub returning nil); the
  # `cast[BinaryIo]` mirrors `Progress.wrap_file`'s
  # `cast[BinaryIo](initReader(…))` (line 1686 — both `ReadContext`/`BinaryIo`
  # are pointer-sized `ref object of RootObj`).
  var columns: seq[ColumnArg] = @[]
  if description.len > 0:
    columns.add ColumnArg(kind: cakColumn,
        columnv: initTextColumn("[progress.description]{task.description}"))
  columns.add ColumnArg(kind: cakColumn,
      columnv: initBarColumn(style = style, completeStyle = completeStyle,
          finishedStyle = finishedStyle, pulseStyle = pulseStyle))
  columns.add ColumnArg(kind: cakColumn, columnv: initDownloadColumn())
  columns.add ColumnArg(kind: cakColumn, columnv: initTimeRemainingColumn())
  let rps = if refreshPerSecond != 0.0: refreshPerSecond else: 10.0
  let progress = initProgress(columns, console = console,
      autoRefresh = autoRefresh, refreshPerSecond = rps, transient = transient,
      getTime = getTime, disable = disable)
  let reader = progress.open(file, mode = mode, buffering = buffering,
      encoding = encoding, errors = errors, newline = newline, total = total,
      description = description)
  result = cast[BinaryIo](initReadContext(progress, reader))