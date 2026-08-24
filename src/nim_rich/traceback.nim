## nim_rich / traceback.nim — port of rich source.
## =====================================================================
## rich port, `rich/traceback.py` (924 lines).
##
## Rich's exception-traceback renderer: `Traceback` (a `ConsoleRenderable`)
## plus its supporting dataclasses (`Frame`, `_SyntaxError`, `Stack`, `Trace`),
## the `PathHighlighter` (a `RegexHighlighter` subclass), the `install`
## `sys.excepthook` installer, and the `_iter_syntax_lines` generator.
##
## Import graph (faithful to traceback.py:1-49; keeps only
## signature-needed siblings; body-only siblings are body):
##   `segment`    → richbase (ConsoleHandle, ConsoleOptions, RenderResult,
##                 OverflowMethod, RenderableBase)  (traceback.py:32 ↔ console;
##                 `segment` re-exports `richbase`)
##   `console`    → `Console` (traceback.py:32)   [signature dep — `install`'s
##                 `console: Option[Console]` param]
##   `highlighter`→ `RegexHighlighter` (traceback.py:33) [signature dep —
##                 `PathHighlighter` base]
##   `pretty`     → `Node` (traceback.py:29, `from . import pretty`)
##                 [signature dep — `Frame.locals` field type]
## Body-only body siblings (omitted from imports, documented here
## for the Body): `text` (`Text`, traceback.py:47), `theme` (`Theme`,
## traceback.py:48), `panel` (`Panel`, traceback.py:30), `columns` (`Columns`,
## traceback.py:31), `constrain` (`Constrain`, traceback.py:35), `style`
## (`Style`, traceback.py:37), `scope` (`render_scope`, traceback.py:43),
## `syntax` (`Syntax`, traceback.py:45 — also absent from the port;
## `SyntaxPosition` is a provisional handle below), and the std-lib `os`/`sys`/
## `inspect`/`linecache` (traceback.py:1-7, all body-only). Pygments
## (traceback.py:40-41) is not ported; lexer work (`_guess_lexer`) is a body
## body. `std/options` and `std/tables` are imported for `Option` and `Table`
## (the `Frame.locals` field type).
##
## Provisional forward handle :
##   `SyntaxPosition* = tuple[line: int, column: int]` — rich `syntax.py`
##   `SyntaxPosition` (a `NamedTuple`); `syntax.nim` is not yet ported, so this
##   is a provisional stand-in. When `syntax.nim` lands, replace
##   this alias with `import syntax` + `syntax.SyntaxPosition`.
##
## Deviations (documented):
##   * `WINDOWS` (traceback.py:50): rich defines a module-level `WINDOWS =
##     sys.platform == "win32"` here AND in `console.py:66`. To avoid a
##     duplicate-export ambiguity in the umbrella (both modules exporting
##     `WINDOWS*`), the Nim port does NOT re-declare `WINDOWS` in this module;
##     the shared `console.WINDOWS` (console.nim:66, same value) is used
##     instead. (`WINDOWS` is body-only in `traceback` — `extract` path handling
##     — so no signature needs it.)
##   * `_iter_syntax_lines` is exported as `iterSyntaxLines*` (the leading `_`
##     private-marker is dropped, consistent with how the port renamed
##     `richbase._trim_spans` → `trimSpans*`).
##   * `_SyntaxError` is exported as `SyntaxErrorInfo*` (dropping the `_`
##     private marker; `SyntaxError` alone would risk a clash with Nim's
##     `system.SyntaxError`).
##   * `PathHighlighter.highlights` (traceback.py:236-243) — a class attribute
##     of compiled path regexes — is a Body concern (pygments/regex
##     not ported); only the type is declared here.
##   * `_render_syntax_error`/`_render_stack` (traceback.py:728,767) carry
##     rich's `@group()` decorator; the decorator (a Nim template/pragma) is a
##     body concern, so the procs are declared plain here (named
##     `renderSyntaxError`/`renderStack`, dropping the `_` private marker).
##   * `_visited_exceptions: Optional[Set[BaseException]]` (`extract`,
##     traceback.py:422) is modelled as `Option[seq[ref CatchableError]]` (a
##     `Set[BaseException]` → `seq` of exception refs; `BaseException` →
##     `CatchableError`).
##   * `from_exception`/`extract`'s `exc_type: Type[Any]` / `exc_value:
##     BaseException` / `traceback: Optional[TracebackType]` →
##     `typedesc[CatchableError]` / `ref CatchableError` / `Option[RootRef]`.
##   * `_guess_lexer` (classmethod) → `guessLexer*` (drops `_`).
##
## Naming (convention): `__init__`→`initXxx`; `__rich_console__`→
## `renderConsole`; snake_case `a_b`→`aB`; dataclass privates stay exported
## fields; `@classmethod`→`T: typedesc[Type]` first param (per `text.nim`
## `fromMarkup*(T: typedesc[Text], ...)`).

import std/options          # Option, none, some.
import std/tables           # Table (Frame.locals: Table[string, pretty.Node]).
import std/typetraits       # name(typedesc) - extract's Stack.excType type-name.
import std/os              # splitFile (guessLexer's `os.path.splitext`, traceback.py:755).
import std/strutils         # startsWith/toLower/find (guessLexer hashbang, traceback.py:758-760).
import segment              # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                            # OverflowMethod, RenderableBase) — `segment` re-exports
                            # `richbase`.
import highlighter          # RegexHighlighter (traceback.py:33) — PathHighlighter base.
import pretty              # Node (traceback.py:29) — Frame.locals field type.

# ---------------------------------------------------------------------------
# Constants (traceback.py:50-54).
# ---------------------------------------------------------------------------
## `LOCALS_MAX_LENGTH` (traceback.py:52) — default max length for local-var
## keys in the traceback. A `const` (compile-time) so it may serve as a default
## param value in `install`/`initTraceback`/`extract`. (See the header note re
## the omitted `WINDOWS`.)
const LOCALS_MAX_LENGTH* = 10

## `LOCALS_MAX_STRING` (traceback.py:54) — default max length for local-var
## string values. `const` for the same reason as `LOCALS_MAX_LENGTH`.
const LOCALS_MAX_STRING* = 80

type
  # -------------------------------------------------------------------------
  # Provisional / alias types.
  # -------------------------------------------------------------------------
  SyntaxPosition* = tuple[line: int, column: int]
    ## rich `syntax.py` `SyntaxPosition` (a `NamedTuple`); `syntax.nim` is not
    ## yet ported, so this is a provisional stand-in. See the header
    ## note; replace with `import syntax` + `syntax.SyntaxPosition` when
    ## `syntax.nim` lands.

  LastInstruction* = tuple[start: tuple[row: int, col: int],
                          `end`: tuple[row: int, col: int]]
    ## rich `Frame.last_instruction: Optional[Tuple[Tuple[int, int], Tuple[int,
    ## int]]]` (traceback.py:228). A named nested-tuple alias so the
    ## `Option[LastInstruction]` field (and its `none(LastInstruction)` default)
    ## reads cleanly; `end` is a Nim keyword → backtick-quoted field name.

  ExcepthookCallable* = proc(excType: typedesc[CatchableError],
                            excValue: ref CatchableError,
                            excTb: Option[RootRef]) {.closure.}
    ## rich `install` return (traceback.py:58-84): the `sys.excepthook`
    ## signature `Callable[[Type[BaseException], BaseException,
    ## Optional[TracebackType]], Any]`. `Type[BaseException]` →
    ## `typedesc[CatchableError]`; `BaseException` → `ref CatchableError`;
    ## `Optional[TracebackType]` → `Option[RootRef]` (a traceback is an opaque
    ## ref handle in Nim).

  # -------------------------------------------------------------------------
  # Dataclasses (traceback.py:221-256) — value objects (Python `@dataclass`).
  # -------------------------------------------------------------------------
  Frame* = object
    ## rich traceback.py:223-229 — `@dataclass class Frame`: a single frame in
    ## the traceback. Value object (Nim `object`).
    filename*: string                          ## traceback.py:224 — `filename: str`.
    lineno*: int                                ## traceback.py:225 — `lineno: int`.
    name*: string                               ## traceback.py:226 — `name: str`.
    line*: string                               ## traceback.py:227 — `line: str = ""`.
    locals*: Option[Table[string, pretty.Node]] ## traceback.py:228 — `locals:
                                                ## Optional[Dict[str, pretty.Node]]
                                                ## = None` → `Option[Table[string,
                                                ## pretty.Node]]`, default `None`.
    lastInstruction*: Option[LastInstruction]   ## traceback.py:229 —
                                                ## `last_instruction:
                                                ## Optional[Tuple[Tuple[int, int],
                                                ## Tuple[int, int]]] = None`.

  SyntaxErrorInfo* = object
    ## rich traceback.py:231-238 — `@dataclass class _SyntaxError`: a
    ## syntax-error description. Exported as `SyntaxErrorInfo*` (dropping the
    ## `_` private marker; see header note). Value object.
    offset*: int        ## traceback.py:232 — `offset: int`.
    filename*: string   ## traceback.py:233 — `filename: str`.
    line*: string       ## traceback.py:234 — `line: str`.
    lineno*: int        ## traceback.py:235 — `lineno: int`.
    msg*: string        ## traceback.py:236 — `msg: str`.
    notes*: seq[string] ## traceback.py:238 — `notes: List[str] = field(
                        ## default_factory=list)` → `seq[string]`, default `@[]`.

  Stack* = object
    ## rich traceback.py:240-251 — `@dataclass class Stack`: an exception
    ## stack (one per cause / exception-group member). Value object; mutually
    ## recursive with `Trace` (`exceptions: seq[Trace]` ↔ `stacks: seq[Stack]`),
    ## which Nim permits within a single `type` block (the `seq` indirection
    ## breaks the size cycle).
    excType*: string                       ## traceback.py:241 — `exc_type: str`.
    excValue*: string                      ## traceback.py:242 — `exc_value: str`.
    syntaxError*: Option[SyntaxErrorInfo]  ## traceback.py:243 — `syntax_error:
                                           ## Optional[_SyntaxError] = None`.
    isCause*: bool                         ## traceback.py:244 — `is_cause: bool
                                           ## = False`.
    frames*: seq[Frame]                     ## traceback.py:245 — `frames:
                                           ## List[Frame] = field(
                                           ## default_factory=list)`.
    notes*: seq[string]                     ## traceback.py:246 — `notes:
                                           ## List[str] = field(
                                           ## default_factory=list)`.
    isGroup*: bool                          ## traceback.py:247 — `is_group:
                                           ## bool = False`.
    exceptions*: seq[Trace]                  ## traceback.py:248 — `exceptions:
                                           ## List["Trace"] = field(
                                           ## default_factory=list)`.

  Trace* = object
    ## rich traceback.py:253-256 — `@dataclass class Trace`: the top-level
    ## trace (a list of `Stack`s). Value object; mutually recursive with
    ## `Stack`.
    stacks*: seq[Stack]   ## traceback.py:255 — `stacks: List[Stack]`.

  # -------------------------------------------------------------------------
  # PathHighlighter (traceback.py:211-219) — a RegexHighlighter subclass.
  # -------------------------------------------------------------------------
  PathHighlighter* = ref object of RegexHighlighter
    ## rich traceback.py:211-219 — `class PathHighlighter(RegexHighlighter)`:
    ## highlights filesystem paths in traceback frames. No `__init__` (uses
    ## `RegexHighlighter`'s); the `highlights` class attribute
    ## (traceback.py:236-243, compiled path regexes) is a Body concern
    ## (pygments/regex not ported) — only the type is declared here.

  # -------------------------------------------------------------------------
  # Traceback (traceback.py:262-895) — the Console renderable.
  # -------------------------------------------------------------------------
  Traceback* = ref object of RenderableBase
    ## rich traceback.py:262-895 — `class Traceback` (a `ConsoleRenderable`):
    ## renders an exception traceback. `ref object of RenderableBase` (so it
    ## satisfies the renderable concept; rich's `ConsoleRenderable` is the
    ## `richbase` `RenderableBase` concept). Fields mirror `__init__` params
    ## (traceback.py:295-350); rich's `locals_overlow` typo (traceback.py:346)
    ## is renamed `localsOverflow`.
    trace*: Option[Trace]                ## traceback.py:296 — `trace:
                                         ## Optional[Trace] = None`.
    width*: Option[int]                  ## traceback.py:337 — `width:
                                         ## Optional[int] = 100`.
    codeWidth*: Option[int]              ## traceback.py:338 — `code_width:
                                         ## Optional[int] = 88`.
    extraLines*: int                     ## traceback.py:339 — `extra_lines:
                                         ## int = 3`.
    theme*: Option[string]               ## traceback.py:340 — `theme:
                                         ## Optional[str] = None`.
    wordWrap*: bool                      ## traceback.py:341 — `word_wrap:
                                         ## bool = False`.
    showLocals*: bool                    ## traceback.py:342 — `show_locals:
                                         ## bool = False`.
    localsMaxLength*: int                ## traceback.py:343 — `locals_max_length:
                                         ## int = LOCALS_MAX_LENGTH`.
    localsMaxString*: int                ## traceback.py:344 — `locals_max_string:
                                         ## int = LOCALS_MAX_STRING`.
    localsMaxDepth*: Option[int]         ## traceback.py:345 — `locals_max_depth:
                                         ## Optional[int] = None`.
    localsHideDunder*: bool             ## traceback.py:346 — `locals_hide_dunder:
                                         ## bool = True`.
    localsHideSunder*: Option[bool]     ## traceback.py:347 — `locals_hide_sunder:
                                         ## Optional[bool] = False` (a present
                                         ## `False` → `some(false)`; note
                                         ## `fromException`/`install` default this
                                         ## to `None` → `none(bool)`).
    localsOverflow*: Option[OverflowMethod] ## traceback.py:348 — `locals_overlow:
                                         ## Optional[OverflowMethod] = None` (rich
                                         ## typo `overlow` → `overflow`).
    indentGuides*: bool                 ## traceback.py:349 — `indent_guides:
                                         ## bool = True`.
    suppress*: seq[string]               ## traceback.py:350 — `suppress:
                                         ## Iterable[Union[str, ModuleType]] = ()`
                                         ## → `seq[string]` (narrowed to the `str`
                                         ## arm; `ModuleType` is body).
    maxFrames*: int                     ## traceback.py:351 — `max_frames:
                                         ## int = 100`.

# ---------------------------------------------------------------------------
# Dataclass constructors (traceback.py:221-256).
# ---------------------------------------------------------------------------
proc initFrame*(filename: string, lineno: int, name: string, line: string = "",
                locals: Option[Table[string, pretty.Node]] =
                    none(Table[string, pretty.Node]),
                lastInstruction: Option[LastInstruction] = none(LastInstruction)):
    Frame =
  ## rich traceback.py:223-229 — `Frame` dataclass `__init__` (auto-generated):
  ## positional `filename`/`lineno`/`name`; `line` defaults `""`; `locals` and
  ## `last_instruction` default `None` → `none(...)`. (returns a
  ## default `Frame`; body populates the fields, per the   ## `initNode`/`initPretty` stub convention).
  result.filename = filename
  result.lineno = lineno
  result.name = name
  result.line = line
  result.locals = locals
  result.lastInstruction = lastInstruction

proc initSyntaxErrorInfo*(offset: int, filename: string, line: string,
                          lineno: int, msg: string,
                          notes: seq[string] = @[]): SyntaxErrorInfo =
  ## rich traceback.py:231-238 — `_SyntaxError` dataclass `__init__`
  ## (auto-generated): positional `offset`/`filename`/`line`/`lineno`/`msg`;
  ## `notes` defaults `field(default_factory=list)` → `@[]`.
  result.offset = offset
  result.filename = filename
  result.line = line
  result.lineno = lineno
  result.msg = msg
  result.notes = notes

proc initStack*(excType: string, excValue: string,
               syntaxError: Option[SyntaxErrorInfo] = none(SyntaxErrorInfo),
               isCause: bool = false, frames: seq[Frame] = @[],
               notes: seq[string] = @[], isGroup: bool = false,
               exceptions: seq[Trace] = @[]): Stack =
  ## rich traceback.py:240-251 — `Stack` dataclass `__init__` (auto-generated):
  ## positional `exc_type`/`exc_value`; `syntax_error`/`is_cause`/`frames`/
  ## `notes`/`is_group`/`exceptions` default `None`/`False`/`[]`. `exc_type`→
  ## `excType`, `exc_value`→`excValue`, `is_cause`→`isCause`, `is_group`→
  ## `isGroup`.
  result.excType = excType
  result.excValue = excValue
  result.syntaxError = syntaxError
  result.isCause = isCause
  result.frames = frames
  result.notes = notes
  result.isGroup = isGroup
  result.exceptions = exceptions

proc initTrace*(stacks: seq[Stack]): Trace =
  ## rich traceback.py:253-256 — `Trace` dataclass `__init__` (auto-generated):
  ## the single required field `stacks: List[Stack]`.
  result.stacks = stacks

# ---------------------------------------------------------------------------
# PathHighlighter construction (traceback.py:211-219).
# ---------------------------------------------------------------------------
## `PathHighlighter` has no explicit `__init__` in rich (it inherits
## `RegexHighlighter`'s, which inherits `Highlighter`'s no-op). Per the
## `highlighter.nim` convention (no `initXxx` constructors for the
## highlighter subtypes — `ReprHighlighter`/`NullHighlighter` use ref
## construction `PathHighlighter()`), construction is by ref construction; no
## `initPathHighlighter` is provided.

# ---------------------------------------------------------------------------
# Traceback methods (traceback.py:262-895).
# ---------------------------------------------------------------------------
proc initTraceback*(trace: Option[Trace] = none(Trace),
                   width: Option[int] = some(100),
                   codeWidth: Option[int] = some(88), extraLines: int = 3,
                   theme: Option[string] = none(string), wordWrap: bool = false,
                   showLocals: bool = false,
                   localsMaxLength: int = LOCALS_MAX_LENGTH,
                   localsMaxString: int = LOCALS_MAX_STRING,
                   localsMaxDepth: Option[int] = none(int),
                   localsHideDunder: bool = true,
                   localsHideSunder: Option[bool] = some(false),
                   localsOverflow: Option[OverflowMethod] = none(OverflowMethod),
                   indentGuides: bool = true, suppress: openArray[string] = @[],
                   maxFrames: int = 100): Traceback =
  ## rich traceback.py:295-350 — `Traceback.__init__(self, trace: Optional[Trace]
  ## = None, *, width: Optional[int] = 100, code_width: Optional[int] = 88,
  ## extra_lines: int = 3, theme: Optional[str] = None, word_wrap: bool = False,
  ## show_locals: bool = False, locals_max_length: int = LOCALS_MAX_LENGTH,
  ## locals_max_string: int = LOCALS_MAX_STRING, locals_max_depth: Optional[int]
  ## = None, locals_hide_dunder: bool = True, locals_hide_sunder: Optional[bool]
  ## = False, locals_overlow: Optional[OverflowMethod] = None, indent_guides:
  ## bool = True, suppress: Iterable[Union[str, ModuleType]] = (), max_frames:
  ## int = 100) -> None`: the rendering configuration. `width`/`code_width`
  ## defaults `100`/`88` (present ints) → `some(100)`/`some(88)`; `theme` →
  ## `Option[string]`; `locals_hide_sunder` default `False` (present) →
  ## `some(false)` (distinct from `fromException`/`install`'s `none(bool)`);
  ## `locals_overlow` (rich typo) → `localsOverflow`; `suppress` →
  ## `openArray[string]` (default `@[]`).
  new(result)
  result.trace = trace
  result.width = width
  result.codeWidth = codeWidth
  result.extraLines = extraLines
  result.theme = theme
  result.wordWrap = wordWrap
  result.showLocals = showLocals
  result.localsMaxLength = localsMaxLength
  result.localsMaxString = localsMaxString
  result.localsMaxDepth = localsMaxDepth
  result.localsHideDunder = localsHideDunder
  result.localsHideSunder = localsHideSunder
  result.localsOverflow = localsOverflow
  result.indentGuides = indentGuides
  result.suppress = @suppress
  result.maxFrames = maxFrames

proc extract*(T: typedesc[Traceback], excType: typedesc[CatchableError],
              excValue: ref CatchableError, traceback: Option[RootRef],
              showLocals: bool = false,
              localsMaxLength: int = LOCALS_MAX_LENGTH,
              localsMaxString: int = LOCALS_MAX_STRING,
              localsMaxDepth: Option[int] = none(int),
              localsHideDunder: bool = true,
              localsHideSunder: Option[bool] = some(false),
              localsOverflow: Option[OverflowMethod] = none(OverflowMethod),
              visitedExceptions: Option[seq[ref CatchableError]] =
                  none(seq[ref CatchableError])): Trace

proc fromException*(T: typedesc[Traceback], excType: typedesc[CatchableError],
                   excValue: ref CatchableError, traceback: Option[RootRef],
                   width: Option[int] = some(100),
                   codeWidth: Option[int] = some(88), extraLines: int = 3,
                   theme: Option[string] = none(string), wordWrap: bool = false,
                   showLocals: bool = false,
                   localsMaxLength: int = LOCALS_MAX_LENGTH,
                   localsMaxString: int = LOCALS_MAX_STRING,
                   localsMaxDepth: Option[int] = none(int),
                   localsHideDunder: bool = true,
                   localsHideSunder: Option[bool] = none(bool),
                   localsOverflow: Option[OverflowMethod] = none(OverflowMethod),
                   indentGuides: bool = true, suppress: openArray[string] = @[],
                   maxFrames: int = 100): Traceback =
  ## rich traceback.py:267-291 — `Traceback.from_exception(cls, exc_type:
  ## Type[Any], exc_value: BaseException, traceback: Optional[TracebackType], *,
  ## width: Optional[int] = 100, code_width: Optional[int] = 88, extra_lines:
  ## int = 3, theme: Optional[str] = None, word_wrap: bool = False,
  ## show_locals: bool = False, locals_max_length: int = LOCALS_MAX_LENGTH,
  ## locals_max_string: int = LOCALS_MAX_STRING, locals_max_depth:
  ## Optional[int] = None, locals_hide_dunder: bool = True, locals_hide_sunder:
  ## Optional[bool] = None, locals_overflow: Optional[OverflowMethod] = None,
  ## indent_guides: bool = True, suppress: Iterable[Union[str, ModuleType]] = (),
  ## max_frames: int = 100) -> "Traceback"` (`@classmethod`): build a `Traceback`
  ## from an exception. `exc_type`→`excType: typedesc[CatchableError]`;
  ## `exc_value`→`excValue: ref CatchableError`; `traceback`→`Option[RootRef]`.
  ## Classmethod → `T: typedesc[Traceback]` first param (per `text.nim`
  ## `fromMarkup*(T: typedesc[Text], ...)`). `locals_hide_sunder` default `None`
  ## → `none(bool)` (note: differs from `initTraceback`'s `some(false)`).
  let trace = extract(T, excType, excValue, traceback, showLocals, localsMaxLength, localsMaxString, localsMaxDepth, localsHideDunder, localsHideSunder, localsOverflow)
  result = initTraceback(some(trace), width, codeWidth, extraLines, theme, wordWrap, showLocals, localsMaxLength, localsMaxString, localsMaxDepth, localsHideDunder, localsHideSunder, localsOverflow, indentGuides, suppress, maxFrames)

proc extract*(T: typedesc[Traceback], excType: typedesc[CatchableError],
              excValue: ref CatchableError, traceback: Option[RootRef],
              showLocals: bool = false,
              localsMaxLength: int = LOCALS_MAX_LENGTH,
              localsMaxString: int = LOCALS_MAX_STRING,
              localsMaxDepth: Option[int] = none(int),
              localsHideDunder: bool = true,
              localsHideSunder: Option[bool] = some(false),
              localsOverflow: Option[OverflowMethod] = none(OverflowMethod),
              visitedExceptions: Option[seq[ref CatchableError]] =
                  none(seq[ref CatchableError])): Trace =
  ## rich traceback.py:418-548 — `Traceback.extract(cls, exc_type: Type[Any],
  ## exc_value: BaseException, traceback: Optional[TracebackType], *,
  ## show_locals: bool = False, locals_max_length: int = LOCALS_MAX_LENGTH,
  ## locals_max_string: int = LOCALS_MAX_STRING, locals_max_depth:
  ## Optional[int] = None, locals_hide_dunder: bool = True, locals_hide_sunder:
  ## Optional[bool] = False, locals_overflow: Optional[OverflowMethod] = None,
  ## _visited_exceptions: Optional[Set[BaseException]] = None) -> "Trace"`
  ## (`@classmethod`): extract a `Trace` from an exception's stack. `_visited_
  ## exceptions`→`visitedExceptions: Option[seq[ref CatchableError]]` (a
  ## `Set[BaseException]` → `seq` of exception refs); `locals_hide_sunder`
  ## default `False` (present) → `some(false)`. Classmethod → `T:
  ## typedesc[Traceback]`.
  # Python walks the Python traceback (traceback.py:418-548) building Frames/
  # Stacks from `exc_type`/`exc_value`/`traceback`. Nim has no equivalent
  # traceback-introspection API (the `traceback: Option[RootRef]` is an opaque
  # handle; the frame stack is not reachable from `excType`/`excValue`), so the
  # faithful Frame-per-call-site construction and the cause/context chain
  # (`_visited_exceptions`) are DEFERRED. Best-effort: a single `Stack`
  # carrying the exception type name (`name(excType)`) and value message
  # (`excValue.msg`), wrapped in a `Trace` — a non-empty trace shell for
  # `fromException`.
  let typeStr = name(excType)
  let valueStr = if excValue != nil: excValue.msg else: ""
  result = initTrace(@[initStack(typeStr, valueStr)])

method renderConsole*(self: Traceback, console: ConsoleHandle,
                   options: ConsoleOptions): RenderResult =
  ## rich traceback.py:626-726 — `Traceback.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> RenderResult`: render the
  ## traceback. `__rich_console__`→`renderConsole`; rich types the `console`
  ## param as `Console`, but the renderable concept in `richbase` types it as
  ## `ConsoleHandle` (the base; `Console` is a subtype) — consistent with the
  ## `pretty.nim` `renderConsole` signature. Returns `RenderResult`
  ## (a `seq[RenderResultItem]`).
  # DEFERRED (traceback.py:626-726): the rendering pipeline (`renderStack` per
  # `Stack` in `self.trace`, plus a Traceback title / syntax-error header) is
  # wired via `renderStack`/`renderSyntaxError`, but `RenderResult =
  # seq[RenderResultItem]` and `RenderResultItem` has no public constructor in
  # so the assembled segments cannot be produced — the same
  # codebase-wide deferral `pretty.nim`/`live_render.nim` record. The Trace
  # structure is built (`fromException`/`extract`); the yield is wired when a
  # `RenderResultItem` constructor lands.
  result = @[]

proc renderSyntaxError*(self: Traceback, syntaxError: SyntaxErrorInfo):
    RenderResult =
  ## rich traceback.py:728-765 — `Traceback._render_syntax_error(self,
  ## syntax_error: _SyntaxError) -> RenderResult` (`@group()`, traceback.py:727):
  ## render a single `_SyntaxError`. `_render_syntax_error`→`renderSyntaxError`
  ## (drops the `_` private marker); the `@group()` decorator (a Nim
  ## template/pragma) is a body concern, so the proc is declared plain.
  ## `syntax_error: _SyntaxError` → `syntaxError: SyntaxErrorInfo`. port
  ## stub.
  # DEFERRED (traceback.py:728-765): renders a single `_SyntaxError` (filename,
  # lineno, the offending line with a caret at the offset, the `msg` and
  # `notes`). `RenderResultItem` has no public constructor , so the
  # assembled segments cannot be produced — the same deferral as
  # `renderConsole`. The `SyntaxErrorInfo` is consumed here; the yield is wired
  # when a `RenderResultItem` constructor lands.
  result = @[]

proc renderStack*(self: Traceback, stack: Stack): RenderResult =
  ## rich traceback.py:767-893 — `Traceback._render_stack(self, stack: Stack)
  ## -> RenderResult` (`@group()`, traceback.py:766): render a single `Stack`
  ## (its frames, locals, and the cause chain). `_render_stack`→`renderStack`
  ## (drops the `_`); the `@group()` decorator is a body concern. port
  ## stub.
  # DEFERRED (traceback.py:767-893): renders a single `Stack` (the exception
  # type/value header, each `Frame`'s file/lineno/name/source-line + optional
  # `locals`, and the cause chain). `RenderResultItem` has no public constructor
  # , so the assembled segments cannot be produced — the same
  # deferral as `renderConsole`. The `Stack` is consumed here; the yield is
  # wired when a `RenderResultItem` constructor lands.
  result = @[]

proc guessLexer*(T: typedesc[Traceback], filename: string, code: string): string =
  ## rich traceback.py:752-764 — `Traceback._guess_lexer(cls, filename: str,
  ## code: str) -> str` (`@staticmethod`): guess a Pygments lexer name for the
  ## given file/code. `_guess_lexer`→`guessLexer` (drops the `_`). Modelled with
  ## `T: typedesc[Traceback]` (the classmethod convention; a
  ## `@staticmethod` would be a free proc, but rich calls this as
  ## `cls._guess_lexer`, so the classmethod form is kept). The `LEXERS`
  ## extension map + the no-extension `#!…python` hashbang check are ported
  ## faithfully; the `guess_lexer_for_filename` Pygments fallback is not ported
  ## (returns "text", matching the `ClassNotFound` branch, traceback.py:764).
  let ext = splitFile(filename).ext
  if ext.len == 0:
    # No extension: a `#!…python` hashbang on the first line ⇒ "python"
    # (traceback.py:756-761). `code.find('\n')` returns -1 if absent (rich's
    # `code.index("\n")` would raise — this is a defensive superset).
    let nl = code.find('\n')
    let firstLine = if nl >= 0: code[0 ..< nl] else: code
    if firstLine.startsWith("#!") and "python" in firstLine.toLower():
      return "python"
  # `cls.LEXERS.get(ext)` (traceback.py:763) — the small class-level map. The
  # `or guess_lexer_for_filename(...)` Pygments fallback is DEFERRED (Pygments
  # not ported) → "text" (the `ClassNotFound` branch, traceback.py:764).
  case ext
  of ".py": result = "python"
  of ".pxd", ".pyx": result = "cython"
  of ".pxi": result = "pyrex"
  else: result = "text"

# Forward declaration: `excepthookNoop` is used in `install` below but defined
# later (~line 600). Nim order-dependent resolution needs this.
proc excepthookNoop(excType: typedesc[CatchableError], excValue: ref CatchableError,
                   excTb: Option[RootRef])

# ---------------------------------------------------------------------------
# Module-level functions (traceback.py:58-84, 86-209).
# ---------------------------------------------------------------------------
proc install*(console: Option[ConsoleHandle] = none(ConsoleHandle),
             width: Option[int] = some(100),
             codeWidth: Option[int] = some(88), extraLines: int = 3,
             theme: Option[string] = none(string), wordWrap: bool = false,
             showLocals: bool = false,
             localsMaxLength: int = LOCALS_MAX_LENGTH,
             localsMaxString: int = LOCALS_MAX_STRING,
             localsMaxDepth: Option[int] = none(int),
             localsHideDunder: bool = true,
             localsHideSunder: Option[bool] = none(bool),
             localsOverflow: Option[OverflowMethod] = none(OverflowMethod),
             indentGuides: bool = true, suppress: openArray[string] = @[],
             maxFrames: int = 100): ExcepthookCallable =
  ## rich traceback.py:58-84 — `install(*, console: Optional[Console] = None,
  ## width: Optional[int] = 100, code_width: Optional[int] = 88, extra_lines:
  ## int = 3, theme: Optional[str] = None, word_wrap: bool = False,
  ## show_locals: bool = False, locals_max_length: int = LOCALS_MAX_LENGTH,
  ## locals_max_string: int = LOCALS_MAX_STRING, locals_max_depth: Optional[int]
  ## = None, locals_hide_dunder: bool = True, locals_hide_sunder: Optional[bool]
  ## = None, locals_overflow: Optional[OverflowMethod] = None, indent_guides:
  ## bool = True, suppress: Iterable[Union[str, ModuleType]] = (),
  ## max_frames: int = 100) -> Callable[[Type[BaseException], BaseException,
  ## Optional[TracebackType]], Any]`: install a `sys.excepthook` that prints
  ## rich tracebacks, returning the previous handler. `console: Optional[
  ## Console] = None` → `Option[Console] = none(Console)` (the `Console`
  ## signature dep that forces `import console`); returns `ExcepthookCallable`.
  ## `locals_hide_sunder` default `None` → `none(bool)` (matches `fromException`,
  ## differs from `initTraceback`'s `some(false)`).
  # Python installs a `sys.excepthook` (traceback.py:58-84) returning the
  # previous handler. Nim has no `sys.excepthook`; the hook installation is
  # DEFERRED. Best-effort: return a closure matching `ExcepthookCallable` (the
  # `excepthookNoop` helper) that, when invoked, would build a
  # `fromException(Traceback, ...)` + render + `Console.print` — but those are
  # Phase-0 stubs, so the closure is a no-op for now (the frozen
  # `ExcepthookCallable` signature takes only the exception triple, so the
  # install config cannot be threaded through the hook without a richer env).
  result = excepthookNoop

# ---------------------------------------------------------------------------
# Nim-only helpers (deferred generator / excepthook bodies).
# ---------------------------------------------------------------------------
iterator iterSyntaxLinesIter(start: SyntaxPosition, `end`: SyntaxPosition): tuple[a: int, b: int, c: int] {.closure.} =
  ## [Nim-only helper] Faithful port of `_iter_syntax_lines` (traceback.py:56-84):
  ## yield `(line, column1, column2)` spans for syntax-error highlighting. A
  ## single-line range yields once; a multi-line range yields a first span
  ## `(line, column1, -1)`, middle spans `(line, 0, -1)`, then a last span
  ## `(line, 0, column2)` — `loop_first_last` (rich `_loop.py`) is inlined
  ## (`_loop` is not imported), mirroring the `ansi.nim` `ansiTokenizeIter`
  ## generator-port convention.
  let (line1, column1) = start
  let (line2, column2) = `end`
  if line1 == line2:
    yield (a: line1, b: column1, c: column2)
  else:
    let n = line2 - line1 + 1
    for i in 0 ..< n:
      let lineNo = line1 + i
      if i == 0:        # first
        yield (a: lineNo, b: column1, c: -1)
      elif i == n - 1:  # last
        yield (a: lineNo, b: 0, c: column2)
      else:             # middle
        yield (a: lineNo, b: 0, c: -1)

proc iterSyntaxLines*(start: SyntaxPosition, `end`: SyntaxPosition):
    iterator(): tuple[a: int, b: int, c: int] {.closure.} =
  ## rich traceback.py:56-84 — `_iter_syntax_lines(start: SyntaxPosition, end:
  ## SyntaxPosition) -> Iterable[Tuple[int, int, int]]`: generate the (line,
  ## start-col, end-col) spans for syntax-error highlighting. A Python
  ## generator → a Nim closure iterator (`iterator(): tuple[a: int, b: int, c:
  ## int] {.closure.}`), the generator convention (cf. `ansi.nim`
  ## `decode`). Exported `iterSyntaxLines*` (drops the `_` private marker, per
  ## the `richbase._trim_spans`→`trimSpans*` rename). `end` is a Nim keyword →
  ## backtick-quoted param. `SyntaxPosition` is the provisional stand-in (see
  ## the header note). Delegates to the `iterSyntaxLinesIter` helper — a
  ## faithful port of the `loop_first_last` span algorithm (traceback.py:78-84).
  result = iterator(): tuple[a: int, b: int, c: int] {.closure.} =
    for span in iterSyntaxLinesIter(start, `end`):
      yield span

# ---------------------------------------------------------------------------
# Module-level functions (traceback.py:58-84, 86-209).
# ---------------------------------------------------------------------------

proc excepthookNoop(excType: typedesc[CatchableError], excValue: ref CatchableError,
                    excTb: Option[RootRef]) =
  ## [Nim-only helper] the deferred `sys.excepthook` body (`install`,
  ## traceback.py:58-84): would `fromException(Traceback, excType, excValue,
  ## excTb, ...)` + `renderConsole` + `Console.print`, but those are Phase-0
  ## stubs — no-op for now. A named module-level proc (not a closure literal)
  ## so the `typedesc[CatchableError]` param is unambiguous; assigned to
  ## `ExcepthookCallable` via nimcall->closure (the `algorithm.nim` idiom).
  discard
