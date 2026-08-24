## richbase.nim — shared base types & signatures for nim-rich (port).
##
## This is a Nim-only base module (no direct counterpart in Python `rich`): it
## collects the *shared* base types that many rich modules depend on, so the
## Nim import graph stays acyclic. In Python `rich` these live in
## `rich/console.py` and `rich/segment.py`; here they are extracted to a common
## leaf so that e.g. `segment.nim` (which needs `ConsoleOptions` for
## `__rich_console__`) and `console.nim` (which needs `Segment` for
## `RenderResult`) do not import each other.
##
## All proc/converter bodies in this file are ports (`discard`); body
## fills them. Every declaration carries a `rich <file>:<line>` source reference
## mapping it to `/workspace/python-rich/rich/`, verified against
## `.inventory/inv5/rich_api_inventory.md` and the authoritative source.
##
## Closure policy: `ControlCode`, `Change[T]` and `RenderResultItem` are Nim
## case objects modelling rich tagged unions (`Union[...]`). Every selector and
## payload field is *private*; the only public surface is a set of read accessors
## (`control*`, `kind*`, …) and constructors (`controlCode*`, `noChange*`,
## `setChange*`). A client of the module therefore cannot construct a
## contradictory state: object literals naming a private field fail with
## "field is not accessible", and post-construction writes fail with
## "<accessor>(x) cannot be assigned to" (accessors are procs, not fields). This
## is faithful to the Python unions, which are immutable `tuple`s / `Union`s.
##
## Module map (type/proc/converter → rich file:line, exact):
##   ControlType            → segment.py:32-50   (IntEnum; members 35-50)
##   ControlCodeKind         → Nim discriminator for the union segment.py:53-57
##   ControlCode             → segment.py:53-57   (Union[…]; Nim case object,
##                            all fields private)
##     control/kind/singleIsStr/singleInt/singleStr/doubleI1/doubleI2
##                          → private fields of ControlCode (segment.py:53-57);
##                            read via the accessors below
##   control*/kind*/singleIsStr*/singleInt*/singleStr*/doubleI1*/doubleI2*
##                          → read accessors for the private ControlCode fields
##                            (segment.py:53-57). ports (`discard`).
##   controlCode* (×4)       → segment.py:53-57   (constructors per union arm)
##   JustifyMethod          → console.py:69
##   OverflowMethod         → console.py:70
##   NoChangeType            → console.py:73-74   (class NoChange; renamed:
##                            Nim identifiers are case- and underscore-
##                            insensitive, so `NoChange` and `NO_CHANGE` are the
##                            *same* symbol; the type is therefore `NoChangeType`
##                            and the sentinel stays `NO_CHANGE`)
##   NO_CHANGE              → console.py:77      (exported const singleton)
##   Change[T]              → Nim port of `Union[T, NoChange]` used as the
##                            parameter type of `ConsoleOptions.update`
##                            (console.py:157-169). Case object, all fields
##                            private (`isChange`, `value`).
##   isChange*/value*       → read accessors for the private Change fields
##                            (console.py:73-77, 157-169). ports.
##   noChangeToInt*/noChangeToOptJustify*/noChangeToOptOverflow*/
##   noChangeToOptBool*/noChangeToOptInt*
##                          → converters NoChangeType → Change[T], one per
##                            concrete `update` parameter type (console.py:73-77
##                            for NoChange, console.py:157-169 for the
##                            `Union[T, NoChange]` parameters). They let the
##                            exported `NO_CHANGE` sentinel be passed directly
##                            as e.g. `options.update(width = NO_CHANGE)`, faithful
##                            to the Python `= NO_CHANGE` default. Each returns
##                            the no-change `Change[T]` (its `discard` body yields
##                            `default(Change[T])`, i.e. `isChange == false`).
##   noChange*[T]           → console.py:77      (builds a no-change Change)
##   setChange*[T]          → console.py:157-169 (builds a set Change)
##   ConsoleDimensions      → console.py:103-109 (NamedTuple)
##   ConsoleOptions         → console.py:113-243 (dataclass @112; fields
##                            116-140; methods 142-243)
##     asciiOnly            → console.py:142-145 (@property @142, def 143-145)
##     copyOpts             → console.py:147-155
##     update               → console.py:157-192 (signature 157-169)
##     updateWidth          → console.py:194-205
##     updateHeight         → console.py:207-218
##     resetHeight          → console.py:220-228
##     updateDimensions     → console.py:230-243
##   initConsoleOptions*    → console.py:113-140 (dataclass defaults)
##   StyleRef               → placeholder handle for `Style` (style.py:40-759)
##   ConsoleHandle          → placeholder handle for `Console`
##                            (console.py:581-2642)
##   Segment                → segment.py:60-696   (@rich_repr @60, class 61;
##                            fields 74-76)
##     cellLength           → segment.py:78-86   (@property @78, def 79-86)
##     hasText              → segment.py:97-99   (__bool__)
##     isControl            → segment.py:101-104 (@property @101, def 102-104)
##     splitCellsImpl       → segment.py:106-153 (@classmethod @106,
##                            @lru_cache @107, def 108-153)
##     splitCells           → segment.py:155-179
##     line                 → segment.py:181-184 (@classmethod @181, def 182-184)
##   RenderableBase         → Nim-only storage base (Python uses Protocols with
##                            no shared base class; Nim needs a concrete ref
##                            base to store heterogeneous renderables in a seq)
##   RenderResultKind       → Nim discriminator for console.py:267,271
##                            (rrkSegment, rrkString, rrkConsoleRenderable,
##                            rrkRichCast — one arm per Python variant)
##   RenderResultItem       → models `Union[RenderableType, Segment]`
##                            (console.py:271), i.e. `Union[ConsoleRenderable,
##                            RichCast, str, Segment]` (console.py:267,271).
##                            Four arms, all fields private.
##     kind/segmentItem/textStr/consoleItem/castItem
##                          → private fields (console.py:267,271); read via the
##                            accessors below
##   kind*/segmentItem*/textStr*/consoleItem*/castItem*
##                          → read accessors for the private RenderResultItem
##                            fields (console.py:267,271). ports.
##   RenderResult           → console.py:271
##   RichCast               → console.py:246-253 (@runtime_checkable @246,
##                            class 247; __rich__ @250-253)
##   ConsoleRenderable      → console.py:256-263 (@runtime_checkable @256,
##                            class 257; __rich_console__ @260-263)
##   RenderableType         → console.py:267
##
## Extended `Segment` operations (`applyStyle`, `splitLines`, `divide`,
## `alignTop`/`alignBottom`/`alignMiddle`, `simplify`, `stripLinks`,
## `stripStyles`, `removeColor`, `adjustLineLength`, `getLineLength`,
## `getShape`, `setShape`, `splitLinesTerminator`, `splitAndCropLines`) and the
## `Segments`/`SegmentLines` renderables live in `segment.nim`
## (segment.py:187-746) — they need `cells`/`style`/`measure` written later in
## port; `richbase` stays a pure leaf importing only `std`.

import std/options
import std/strutils
import std/unicode

type
  ControlType* = enum
    ## Non-printable control codes which typically translate to ANSI codes —
    ## rich `ControlType(IntEnum)` (segment.py:32-50). Members mirror the enum
    ## order/values exactly (BELL=1 … SET_WINDOW_TITLE=16).
    ctBell = 1,                ## BELL
    ctCarriageReturn = 2,      ## CARRIAGE_RETURN
    ctHome = 3,                ## HOME
    ctClear = 4,               ## CLEAR
    ctShowCursor = 5,          ## SHOW_CURSOR
    ctHideCursor = 6,          ## HIDE_CURSOR
    ctEnableAltScreen = 7,     ## ENABLE_ALT_SCREEN
    ctDisableAltScreen = 8,    ## DISABLE_ALT_SCREEN
    ctCursorUp = 9,            ## CURSOR_UP
    ctCursorDown = 10,         ## CURSOR_DOWN
    ctCursorForward = 11,      ## CURSOR_FORWARD
    ctCursorBackward = 12,     ## CURSOR_BACKWARD
    ctCursorMoveToColumn = 13,  ## CURSOR_MOVE_TO_COLUMN
    ctCursorMoveTo = 14,       ## CURSOR_MOVE_TO
    ctEraseInLine = 15,        ## ERASE_IN_LINE
    ctSetWindowTitle = 16      ## SET_WINDOW_TITLE

  ControlCodeKind* = enum
    ## Which arm of the rich `ControlCode` tagged union is in use — a Nim-only
    ## discriminator mirroring `Union[Tuple[ControlType],
    ## Tuple[ControlType, Union[int, str]], Tuple[ControlType, int, int]]`
    ## (segment.py:53-57). The discriminator and every payload field are
    ## *private* to this module, so a client cannot construct a contradictory
    ## combination at all: an object literal naming `kind` or a payload field
    ## fails with "field is not accessible", and a post-construction write to a
    ## payload/discriminator fails with "<accessor>(x) cannot be assigned to"
    ## (the public `kind*`/`singleInt*`/… are read procs, not settable fields).
    cckEmpty   ## `Tuple[ControlType]`                  — no payload.
    cckSingle  ## `Tuple[ControlType, Union[int, str]]` — one int or str payload.
    cckDouble  ## `Tuple[ControlType, int, int]`        — two int payloads.

  ControlCode* = object
    ## A single control code — faithful port of rich `ControlCode`
    ## (segment.py:53-57). Modelled as a Nim `case` object (a true tagged
    ## union): `kind` discriminates the union arm and every payload field lives
    ## *only* inside its matching branch. All fields (`control`, `kind`,
    ## `singleIsStr`, `singleInt`, `singleStr`, `doubleI1`, `doubleI2`) are
    ## private, so the only public construction path is the `controlCode*`
    ## constructors and the only public reads are the accessors of the same
    ## names — a client can neither construct a contradictory combination of a
    ## `kind` and a payload from a different arm nor mutate any field after
    ## construction. A valid payload of `0` (e.g. `(ControlType.HOME, 0)` —
    ## tests/test_segment.py:12,108) stays distinct from the no-payload arm
    ## `(ControlType.HOME,)` (tests/test_windows_renderer.py:70): the
    ## `cckSingle`+`singleIsStr:false`+`singleInt:0` construction carries a real
    ## zero, whereas `cckEmpty` carries no integer at all. Use the
    ## `controlCode*` constructors for the canonical construction paths.
    control: ControlType
    case kind: ControlCodeKind
    of cckEmpty:
      discard
    of cckSingle:
      case singleIsStr: bool
      of false:
        singleInt: int    ## first payload as an int (`Tuple[ControlType, int]`).
      of true:
        singleStr: string ## first payload as a str (`Tuple[ControlType, str]`).
    of cckDouble:
      doubleI1: int        ## first int payload  (`Tuple[ControlType, int, int]`).
      doubleI2: int        ## second int payload (`Tuple[ControlType, int, int]`).

  JustifyMethod* = enum
    ## rich `JustifyMethod = Literal["default", "left", "center", "right",
    ## "full"]` (console.py:69). String-valued enum so `$` yields the exact
    ## Python token for byte-identical output.
    jmDefault = "default"
    jmLeft = "left"
    jmCenter = "center"
    jmRight = "right"
    jmFull = "full"

  OverflowMethod* = enum
    ## rich `OverflowMethod = Literal["fold", "crop", "ellipsis", "ignore"]`
    ## (console.py:70). String-valued enum so `$` yields the exact Python token
    ## for byte-identical output.
    omFold = "fold"
    omCrop = "crop"
    omEllipsis = "ellipsis"
    omIgnore = "ignore"

  NoChangeType* = object
    ## Sentinel type marking "leave this field unchanged" — rich `NoChange`
    ## (console.py:73-74). The Nim type is named `NoChangeType` (not `NoChange`)
    ## because Nim identifiers are case- and underscore-insensitive, so a type
    ## `NoChange` would collide with the exported sentinel `NO_CHANGE`
    ## (console.py:77). An empty value object so the singleton can be a
    ## compile-time `const`. Used as the marker arm of `Union[T, NoChange]`
    ## (see `Change[T]`), modelled by `Change[T](isChange: false)`.

  Change*[T] = object
    ## Nim port of rich `Union[T, NoChange]` as used by the keyword-only
    ## parameters of `ConsoleOptions.update` (console.py:157-169, body 157-192).
    ## A `case` object: `isChange == false` ⇒ the `NoChange` sentinel (keep the
    ## current value); `isChange == true` ⇒ set the field to `value`. For
    ## optional fields such as `height` use `Change[Option[int]]` to encode all
    ## three states (no-change / set-None / set-value). Both `isChange` and
    ## `value` are private; the public reads are the `isChange*`/`value*`
    ## accessors and the public constructors are `noChange*`/`setChange*`, so a
    ## client cannot put the type in the contradictory state "isChange == false
    ## with a value". The exported `NO_CHANGE` sentinel converts to a no-change
    ## `Change[T]` via the `noChangeTo…*` converters, so
    ## `options.update(width = NO_CHANGE)` compiles (matching the Python
    ## `= NO_CHANGE` default).
    case isChange: bool
    of true:
      value: T
    of false:
      discard

  ConsoleDimensions* = tuple
    ## Size of the terminal — rich `ConsoleDimensions` NamedTuple
    ## (console.py:103-109).
    width: int   ## The width of the console in 'cells'.
    height: int  ## The height of the console in lines.

  ConsoleOptions* = object
    ## Options for `__rich_console__` — rich `ConsoleOptions` dataclass
    ## (console.py:113-243; decorator @112). The first seven fields have no
    ## Python defaults (required, console.py:116-128); the remaining six mirror
    ## the dataclass defaults exactly (console.py:130-140): `no_wrap` defaults
    ## to `False` (not `None`), the others default to `None`. Field defaults
    ## preserve those values so a Nim object literal `ConsoleOptions(size: <the
    ## required fields>, <defaulted optional fields>)` mirrors the Python
    ## dataclass constructor.
    size*: ConsoleDimensions                ## Size of console.            (console.py:116)
    legacyWindows*: bool                     ## legacy_windows flag.         (console.py:118)
    minWidth*: int                           ## Minimum width of renderable. (console.py:120)
    maxWidth*: int                           ## Maximum width of renderable. (console.py:122)
    isTerminal*: bool                        ## True if the target is a terminal. (console.py:124)
    encoding*: string                        ## Encoding of terminal.        (console.py:126)
    maxHeight*: int                          ## Height of container (starts as terminal). (console.py:128)
    justify*: Option[JustifyMethod] = none(JustifyMethod)     ## None. (console.py:130)
    overflow*: Option[OverflowMethod] = none(OverflowMethod)  ## None. (console.py:132)
    noWrap*: Option[bool] = some(false)                       ## False. (console.py:134)
    highlight*: Option[bool] = none(bool)                      ## None. (console.py:136)
    markup*: Option[bool] = none(bool)                         ## None. (console.py:138)
    height*: Option[int] = none(int)                           ## None. (console.py:140)

  StyleRef* = ref object of RootObj
    ## Opaque base handle for `Style` (defined in `style.nim`). `richbase` is
    ## the leaf written before `style.nim` exists, so `Segment.style` holds this
    ## handle; `style.nim` is expected to declare
    ## `Style = ref object of StyleRef` (Python `Style` has reference
    ## semantics, so a Nim `ref` is the faithful mirror — style.py:40-759). A
    ## `Style` value is stored in a `Segment` via `some(StyleRef(style))`.
    ## placeholder.

  ConsoleHandle* = ref object of RootObj
    ## Opaque base handle for `Console` (defined in `console.nim`). `richbase`
    ## is a leaf and `Console` (console.py:581-2642) is the central type that
    ## many modules depend on, so it cannot live in `richbase`; instead this
    ## handle lets the `ConsoleRenderable` concept (and renderable signatures)
    ## reference "a console" without importing `console.nim`. `console.nim` is
    ## expected to declare `Console = ref object of ConsoleHandle`; a renderable
    ## declares `renderConsole(self, console: ConsoleHandle, options:
    ## ConsoleOptions): RenderResult` and receives any `Console` (a subtype) at
    ## runtime. placeholder.

  JupyterMixin* = ref object of RenderableBase
    ## rich `JupyterMixin` (jupyter.py:30-46): a marker base class (Python
    ## `__slots__ = ()`, jupyter.py:34 — no instance state) that adds Jupyter
    ## notebook rendering (`_repr_mimebundle_`, jupyter.py:38-46) to a
    ## renderable. Rich renderables inherit it (e.g. `class Emoji(JupyterMixin)`
    ## emoji.py:20, `class Text(JupyterMixin)` text.py:118). `of RenderableBase`
    ## (the concrete renderable base) so every `JupyterMixin` subtype is a
    ## `RenderableBase` and dispatches via the virtual `renderConsole` method —
    ## UNIFIED (audit): the former `of RootObj` here + a competing
    ## `of RenderableBase` in `jupyter.nim` left `Emoji` (which imports
    ## `richbase`) off the `RenderableBase` hierarchy (no dispatch). Now the
    ## single canonical definition lives in `richbase` (cycle-breaker leaf);
    ## `jupyter.nim` imports it (no redefine) and adds `_repr_mimebundle_`.

  Segment* = object
    ## A piece of text with associated style — rich `Segment` NamedTuple
    ## (segment.py:60-696; @rich_repr @60, class @61; fields segment.py:74-76).
    ## Segments are produced by the Console render process and are ultimately
    ## converted to strings written to the terminal.
    text*: string                        ## A piece of text. (segment.py:74)
    style*: Option[StyleRef]             ## Optional style (None ⇒ no style). (segment.py:75)
    control*: Option[seq[ControlCode]]   ## Optional sequence of control codes. (segment.py:76)

  RenderableBase* = ref object of RootObj
    ## Concrete base for renderables stored in a `RenderResult` for recursive
    ## rendering. Python `rich` uses structural Protocols (`ConsoleRenderable`,
    ## `RichCast`) with no shared base class, but Nim needs a concrete ref base
    ## to store heterogeneous renderables in a `seq`. Concrete renderables in
    ## other modules are declared as `ref object of RenderableBase` and
    ## additionally satisfy the `ConsoleRenderable`/`RichCast` concepts. A bare
    ## `string` renderable is carried by the `rrkString` arm of
    ## `RenderResultItem`, so it is not forced through this base.

  RenderResultKind* = enum
    ## Which element a `RenderResultItem` carries — a Nim-only discriminator
    ## modelling the four arms of `Union[RenderableType, Segment]`
    ## (console.py:271), where `RenderableType = Union[ConsoleRenderable,
    ## RichCast, str]` (console.py:267). One arm per Python variant:
    ## `rrkSegment` ⇒ `Segment`; `rrkString` ⇒ `str`; `rrkConsoleRenderable` ⇒
    ## `ConsoleRenderable` (stored as a `RenderableBase`); `rrkRichCast` ⇒
    ## `RichCast` (stored as a `RenderableBase`). This is exactly bidirectionally
    ## consistent with `RenderableType`: its three members (`ConsoleRenderable`,
    ## `RichCast`, `str`) map one-to-one to the three non-`Segment` arms, and
    ## `Segment` is the extra arm beyond `RenderableType`.
    rrkSegment
    rrkString
    rrkConsoleRenderable
    rrkRichCast

  RenderResultItem* = object
    ## One element of a `RenderResult` — models `Union[RenderableType, Segment]`
    ## (console.py:271), i.e. `Union[ConsoleRenderable, RichCast, str, Segment]`
    ## (console.py:267,271). An element is exactly one of: a terminal `Segment`
    ## (`rrkSegment`), a bare `string` renderable (`rrkString`), a
    ## `ConsoleRenderable` (`rrkConsoleRenderable`, stored as a `RenderableBase`),
    ## or a `RichCast` (`rrkRichCast`, stored as a `RenderableBase`). This admits
    ## the recursive renderables real rich renderers yield — a plain
    ## `seq[Segment]` would silently drop them — and keeps the membership exact
    ## and bidirectionally consistent with `RenderableType`. All fields are
    ## private; construction is via (body) constructors that accept a member
    ## of the matching concept, and reads are via the accessors below, so a
    ## client cannot construct a contradictory arm/field combination.
    case kind: RenderResultKind
    of rrkSegment:
      segmentItem: Segment
    of rrkString:
      textStr: string
    of rrkConsoleRenderable:
      consoleItem: RenderableBase
    of rrkRichCast:
      castItem: RenderableBase

  RenderResult* = seq[RenderResultItem]
    ## rich `RenderResult = Iterable[Union[RenderableType, Segment]]`
    ## (console.py:271). Materialised as a sequence of `RenderResultItem`s so
    ## each element can be a terminal `Segment` *or* a renderable (`string`,
    ## `ConsoleRenderable` or `RichCast`) the Console renders recursively —
    ## matching the exact membership `Union[RenderableType, Segment]`.

  RichCast* = concept x
    ## rich `RichCast` Protocol (console.py:246-253; @runtime_checkable @246,
    ## class @247; `__rich__` @250-253): an object that may be 'cast' to a
    ## console renderable via `__rich__`, returning
    ## `Union[ConsoleRenderable, RichCast, str]`. Mirrored as a structural
    ## concept requiring a `richCast()` accessor whose result is a `string` or a
    ## `RenderableBase` (which covers `ConsoleRenderable` and `RichCast`
    ## subtypes, since every concrete Nim renderable inherits `RenderableBase`).
    ## A type whose `richCast()` returns a non-renderable such as `int` does
    ## *not* satisfy this concept (e.g. `richCast(): int` is rejected), matching
    ## the Python Protocol's return contract. A correct *recursive* rich-cast
    ## (e.g. `richCast(): B` where `B` is itself a `RenderableBase`/`RichCast`)
    ## satisfies the concept.
    (x.richCast() is (string or RenderableBase))

  ConsoleRenderable* = concept x
    ## rich `ConsoleRenderable` Protocol (console.py:256-263;
    ## @runtime_checkable @256, class @257; `__rich_console__` @260-263): an
    ## object that supports the console protocol via
    ## `__rich_console__(self, console, options) -> RenderResult`. Mirrored as
    ## a structural concept requiring a `renderConsole(console, options)` whose
    ## result is a `RenderResult`; `console` is the `ConsoleHandle` placeholder
    ## and `options` is `ConsoleOptions`. A type without such a method (e.g.
    ## `int`) does not satisfy this concept. (Nim concepts cannot infer extra
    ## type parameters from a method call, so the console/options types are
    ## fixed via local bindings rather than inferred parameters.)
    var c: ConsoleHandle
    var o: ConsoleOptions
    (x.renderConsole(c, o) is RenderResult)

  RenderableType* = ConsoleRenderable or RichCast or string
    ## rich `RenderableType = Union[ConsoleRenderable, RichCast, str]`
    ## (console.py:267). A string or any object that may be rendered by Rich.
    ## The `string` arm is included so the type class covers *all* Python
    ## variants; `Console` additionally accepts strings directly. An
    ## unauthorized type such as `int` does not satisfy this union (it is not a
    ## `string`, lacks `renderConsole`, and lacks `richCast`), and a bare
    ## nominal `RenderableBase` subclass (no `renderConsole`/`richCast`) is
    ## likewise rejected.

# ---------------------------------------------------------------------------
# NoChange / Change helpers — console.py:73-77, 157-169
# ---------------------------------------------------------------------------

const NO_CHANGE*: NoChangeType = NoChangeType()
  ## Module-level `NO_CHANGE = NoChange()` singleton (console.py:77) — the
  ## exported sentinel for the `NoChange` arm of `Union[T, NoChange]`. A
  ## compile-time `const` (empty value object) so it is a true immutable
  ## singleton, faithful to the Python module-level instance. It is distinct
  ## from ordinary optional values: it is a `NoChangeType` (not an `int` or
  ## `Option[…]`), and it is accepted by `ConsoleOptions.update` only via the
  ## `noChangeTo…*` converters below (a plain `some(5)` or bare `5` is rejected
  ## with a type mismatch). Used directly where the sentinel itself is needed;
  ## `Change[T](isChange: false)` is its typed representation inside the
  ## `update` parameters.

converter noChangeToInt*(x: NoChangeType): Change[int] =
  ## Convert the `NO_CHANGE` sentinel to a no-change `Change[int]` — the
  ## `NoChange` arm of `Union[int, NoChange]` for the `width`/`min_width`/
  ## `max_width` parameters of `ConsoleOptions.update` (console.py:77,
  ## console.py:157-169). Its `discard` body yields `default(Change[int])`,
  ## i.e. `isChange == false` (the no-change arm), so the conversion is already
  ## correct . This lets `options.update(width = NO_CHANGE)` compile,
  ## matching the Python `= NO_CHANGE` default.
  result = Change[int](isChange: false)

converter noChangeToOptJustify*(x: NoChangeType): Change[Option[JustifyMethod]] =
  ## Convert `NO_CHANGE` to a no-change `Change[Option[JustifyMethod]]` for the
  ## `justify` parameter of `ConsoleOptions.update` (console.py:77,
  ## console.py:157-169). `discard` body ⇒ `default(Change[…])` = no-change arm.
  result = Change[Option[JustifyMethod]](isChange: false)

converter noChangeToOptOverflow*(x: NoChangeType): Change[Option[OverflowMethod]] =
  ## Convert `NO_CHANGE` to a no-change `Change[Option[OverflowMethod]]` for
  ## the `overflow` parameter of `ConsoleOptions.update` (console.py:77,
  ## console.py:157-169). `discard` body ⇒ no-change arm.
  result = Change[Option[OverflowMethod]](isChange: false)

converter noChangeToOptBool*(x: NoChangeType): Change[Option[bool]] =
  ## Convert `NO_CHANGE` to a no-change `Change[Option[bool]]` for the
  ## `no_wrap`/`highlight`/`markup` parameters of `ConsoleOptions.update`
  ## (console.py:77, console.py:157-169). `discard` body ⇒ no-change arm.
  result = Change[Option[bool]](isChange: false)

converter noChangeToOptInt*(x: NoChangeType): Change[Option[int]] =
  ## Convert `NO_CHANGE` to a no-change `Change[Option[int]]` for the `height`
  ## parameter of `ConsoleOptions.update` (console.py:77, console.py:157-169).
  ## `discard` body ⇒ no-change arm.
  result = Change[Option[int]](isChange: false)

proc noChange*[T](): Change[T] =
  ## Build a no-change `Change[T]` — the `NoChange` arm of `Union[T, NoChange]`
  ## (console.py:77, used by `update` at console.py:157-169). Equivalent to
  ## the `NO_CHANGE` default of an `update` keyword parameter.
  result = Change[T](isChange: false)

proc setChange*[T](value: T): Change[T] =
  ## Wrap a concrete value as a `Change[T]` — the "set" arm of
  ## `Union[T, NoChange]` (console.py:157-169).
  result = Change[T](isChange: true, value: value)

proc isChange*[T](c: Change[T]): bool =
  ## Read the discriminator of `Change[T]` — `true` ⇒ a set value, `false` ⇒ the
  ## `NoChange` sentinel (console.py:73-77, 157-169). Read accessor for the
  ## private `isChange` field.
  result = c.isChange

proc value*[T](c: Change[T]): T =
  ## Read the set value of `Change[T]` — valid only when `isChange` is `true`
  ## (console.py:157-169). Read accessor for the private `value` field. port
  ## stub.
  result = c.value

# ---------------------------------------------------------------------------
# ControlCode accessors — private-field readers (segment.py:53-57)
# ---------------------------------------------------------------------------

proc control*(c: ControlCode): ControlType =
  ## Read the `ControlType` of a `ControlCode` — the first element of every
  ## union arm (segment.py:53-57). Read accessor for the private `control`
  ## field.
  result = c.control

proc kind*(c: ControlCode): ControlCodeKind =
  ## Read which union arm a `ControlCode` carries (segment.py:53-57). Read
  ## accessor for the private `kind` discriminator.
  result = c.kind

proc singleIsStr*(c: ControlCode): bool =
  ## For a `cckSingle` arm, whether the payload is a `str` (`true`) or an `int`
  ## (`false`) (segment.py:53-57). Read accessor for the private `singleIsStr`
  ## nested discriminator.
  result = c.singleIsStr

proc singleInt*(c: ControlCode): int =
  ## For a `cckSingle` arm with `singleIsStr == false`, the int payload
  ## (segment.py:53-57). Read accessor for the private `singleInt` field.
  result = c.singleInt

proc singleStr*(c: ControlCode): string =
  ## For a `cckSingle` arm with `singleIsStr == true`, the str payload
  ## (segment.py:53-57). Read accessor for the private `singleStr` field.
  result = c.singleStr

proc doubleI1*(c: ControlCode): int =
  ## For a `cckDouble` arm, the first int payload (segment.py:53-57). Read
  ## accessor for the private `doubleI1` field.
  result = c.doubleI1

proc doubleI2*(c: ControlCode): int =
  ## For a `cckDouble` arm, the second int payload (segment.py:53-57). Read
  ## accessor for the private `doubleI2` field.
  result = c.doubleI2

# ---------------------------------------------------------------------------
# ControlCode constructors — one per union arm (segment.py:53-57)
# ---------------------------------------------------------------------------

proc controlCode*(control: ControlType): ControlCode =
  ## Construct a no-payload control code — `Tuple[ControlType]` arm of
  ## `ControlCode` (segment.py:53-57).
  result = ControlCode(control: control, kind: cckEmpty)

proc controlCode*(control: ControlType, payload: int): ControlCode =
  ## Construct a single-int control code — `Tuple[ControlType, int]` arm of
  ## `ControlCode` (segment.py:53-57). A `payload` of `0` is a valid, distinct
  ## payload (e.g. `(ControlType.HOME, 0)`).
  result = ControlCode(control: control, kind: cckSingle, singleIsStr: false,
                       singleInt: payload)

proc controlCode*(control: ControlType, payload: string): ControlCode =
  ## Construct a single-str control code — `Tuple[ControlType, str]` arm of
  ## `ControlCode` (segment.py:53-57), e.g. `(ControlType.SET_WINDOW_TITLE,
  ## "title")`.
  result = ControlCode(control: control, kind: cckSingle, singleIsStr: true,
                       singleStr: payload)

proc controlCode*(control: ControlType, a: int, b: int): ControlCode =
  ## Construct a two-int control code — `Tuple[ControlType, int, int]` arm of
  ## `ControlCode` (segment.py:53-57), e.g. `(ControlType.CURSOR_UP, 1, 2)`.
  result = ControlCode(control: control, kind: cckDouble, doubleI1: a,
                       doubleI2: b)

# ---------------------------------------------------------------------------
# RenderResultItem constructors — unfreeze (console.py:267,271)
# ---------------------------------------------------------------------------
# rich `RenderResult = Iterable[Union[RenderableType, Segment]]` (console.py:271)
# where `RenderableType = Union[ConsoleRenderable, RichCast, str]` (console.py:267).
# The four `RenderResultItem` arms are constructed by these procs so clients
# cannot build a contradictory kind/field combination. `Segment` has public
# fields so it may also be constructed directly; these helpers are convenient.

proc initSegment*(text: string, style: Option[StyleRef] = none(StyleRef),
                  control: Option[seq[ControlCode]] = none(seq[ControlCode])): Segment =
  ## Construct a `Segment` (segment.py:74-76). `text` is the piece of text,
  ## `style` is an optional `StyleRef` (None ⇒ no style), `control` an optional
  ## sequence of control codes. Mirrors the Python `Segment(text, style, control)`
  ## NamedTuple field order so call sites read naturally.
  result = Segment(text: text, style: style, control: control)

proc initRenderResultItem*(segment: Segment): RenderResultItem =
  ## Construct an `rrkSegment` item — a terminal `Segment` (console.py:271).
  result = RenderResultItem(kind: rrkSegment, segmentItem: segment)

proc initRenderResultItem*(text: string): RenderResultItem =
  ## Construct an `rrkString` item — a bare `string` renderable (console.py:267,271).
  result = RenderResultItem(kind: rrkString, textStr: text)

proc initRenderResultItem*(renderable: RenderableBase,
                           kind: RenderResultKind): RenderResultItem =
  ## Construct an `rrkConsoleRenderable` or `rrkRichCast` item — a renderable
  ## stored as a `RenderableBase` (console.py:246-271). `kind` must be
  ## `rrkConsoleRenderable` or `rrkRichCast`; the matching field is set.
  assert kind == rrkConsoleRenderable or kind == rrkRichCast,
    "initRenderResultItem(renderable, kind): kind must be rrkConsoleRenderable or rrkRichCast, got " & $kind
  result = RenderResultItem(kind: kind)
  if kind == rrkConsoleRenderable:
    result.consoleItem = renderable
  else:
    result.castItem = renderable

# Convenience adders for `RenderResult = seq[RenderResultItem]` — keep call
# sites terse and self-documenting at render-construction points.
proc addSegment*(r: var RenderResult, segment: Segment) =
  ## Append a terminal `Segment` to the render result (console.py:271).
  r.add(initRenderResultItem(segment))

proc addString*(r: var RenderResult, text: string) =
  ## Append a bare `string` renderable to the render result (console.py:267,271).
  r.add(initRenderResultItem(text))

proc addRenderable*(r: var RenderResult, renderable: RenderableBase,
                    kind: RenderResultKind) =
  ## Append a `ConsoleRenderable`/`RichCast` renderable to the result. `kind`
  ## must be `rrkConsoleRenderable` or `rrkRichCast`.
  r.add(initRenderResultItem(renderable, kind))

# ---------------------------------------------------------------------------
# renderConsole — virtual dispatch base (console.py:1294-1343)
# ---------------------------------------------------------------------------
# rich dispatches `render` via the structural `__rich_console__` Protocol — any
# type with the method is renderable; others raise `NotRenderableError`. In Nim
# the concrete renderables are `ref object of RenderableBase`, so a `method` on
# `RenderableBase` gives the faithful dynamic dispatch WITHOUT console.nim
# importing every renderable module (which would close import cycles). The
# base returns an empty result; concrete subtypes override it. Generic
# renderables (e.g. `Pretty[T]`) cannot be `method`s and keep a `proc`
# (reached via the concept/static path, not this virtual table). A subtype
# without an override degrades to empty output rather than raising, so the
# build stays robust; console.nim's `render` already validates renderability
# by `RenderableValue` kind.
method renderConsole*(self: RenderableBase, console: ConsoleHandle,
                      options: ConsoleOptions): RenderResult {.base.} =
  ## Base — a `RenderableBase` subtype without an `renderConsole` override
  ## renders to an empty result. Override in concrete renderable modules.
  result = @[]

# ---------------------------------------------------------------------------
# RenderResultItem accessors — private-field readers (console.py:267,271)
# ---------------------------------------------------------------------------

proc kind*(r: RenderResultItem): RenderResultKind =
  ## Read which variant a `RenderResultItem` carries (console.py:267,271).
  ## Read accessor for the private `kind` discriminator.
  result = r.kind

proc segmentItem*(r: RenderResultItem): Segment =
  ## For an `rrkSegment` item, the `Segment` (console.py:271, segment.py:60-696).
  ## Read accessor for the private `segmentItem` field.
  result = r.segmentItem

proc textStr*(r: RenderResultItem): string =
  ## For an `rrkString` item, the bare `string` renderable (console.py:267,271).
  ## Read accessor for the private `textStr` field.
  result = r.textStr

proc consoleItem*(r: RenderResultItem): RenderableBase =
  ## For an `rrkConsoleRenderable` item, the `ConsoleRenderable` (stored as a
  ## `RenderableBase`) (console.py:256-263, 271). Read accessor for the private
  ## `consoleItem` field.
  result = r.consoleItem

proc castItem*(r: RenderResultItem): RenderableBase =
  ## For an `rrkRichCast` item, the `RichCast` (stored as a `RenderableBase`)
  ## (console.py:246-253, 271). Read accessor for the private `castItem` field.
  result = r.castItem

# ---------------------------------------------------------------------------
# ConsoleOptions constructor — mirrors the dataclass defaults (console.py:113-140)
# ---------------------------------------------------------------------------

proc initConsoleOptions*(
    size: ConsoleDimensions,
    legacyWindows: bool,
    minWidth: int,
    maxWidth: int,
    isTerminal: bool,
    encoding: string,
    maxHeight: int,
    justify: Option[JustifyMethod] = none(JustifyMethod),
    overflow: Option[OverflowMethod] = none(OverflowMethod),
    noWrap: Option[bool] = some(false),
    highlight: Option[bool] = none(bool),
    markup: Option[bool] = none(bool),
    height: Option[int] = none(int)
): ConsoleOptions =
  ## Construct a `ConsoleOptions` mirroring the rich dataclass defaults
  ## (console.py:113-140). The first seven fields are required (no Python
  ## defaults); the remaining six default to their Python values, notably
  ## `noWrap = some(false)` matching `no_wrap: Optional[bool] = False`
  ## (console.py:134) — *not* `None`. body; body populates fields.
  result = ConsoleOptions(size: size, legacyWindows: legacyWindows,
                          minWidth: minWidth, maxWidth: maxWidth,
                          isTerminal: isTerminal, encoding: encoding,
                          maxHeight: maxHeight, justify: justify,
                          overflow: overflow, noWrap: noWrap,
                          highlight: highlight, markup: markup, height: height)

# ---------------------------------------------------------------------------
# ConsoleOptions methods — console.py:142-243
# ---------------------------------------------------------------------------

proc asciiOnly*(options: ConsoleOptions): bool =
  ## Check if renderables should use ascii only — rich `ConsoleOptions.ascii_only`
  ## property (console.py:142-145; @property @142, def @143-145):
  ## `not encoding.startswith("utf")`.
  result = not options.encoding.startsWith("utf")

proc copyOpts*(options: ConsoleOptions): ConsoleOptions =
  ## Return a copy of the options — rich `ConsoleOptions.copy`
  ## (console.py:147-155).
  result = options

proc update*(
    options: ConsoleOptions,
    width: Change[int] = noChange[int](),
    min_width: Change[int] = noChange[int](),
    max_width: Change[int] = noChange[int](),
    justify: Change[Option[JustifyMethod]] = noChange[Option[JustifyMethod]](),
    overflow: Change[Option[OverflowMethod]] = noChange[Option[OverflowMethod]](),
    no_wrap: Change[Option[bool]] = noChange[Option[bool]](),
    highlight: Change[Option[bool]] = noChange[Option[bool]](),
    markup: Change[Option[bool]] = noChange[Option[bool]](),
    height: Change[Option[int]] = noChange[Option[int]]()
): ConsoleOptions =
  ## Update values, return a copy — rich `ConsoleOptions.update`
  ## (console.py:157-192; signature 157-169). Keyword-only in Python; here
  ## modelled with `Change[T]` defaults equivalent to `NO_CHANGE`
  ## (`Union[T, NoChange]`). The exported `NO_CHANGE` sentinel is also accepted
  ## directly via the `noChangeTo…*` converters, so `options.update(width =
  ## NO_CHANGE)` compiles.
  result = options.copyOpts()
  if width.isChange:
    let w = max(0, width.value)
    result.minWidth = w
    result.maxWidth = w
  if min_width.isChange:
    result.minWidth = min_width.value
  if max_width.isChange:
    result.maxWidth = max_width.value
  if justify.isChange:
    result.justify = justify.value
  if overflow.isChange:
    result.overflow = overflow.value
  if no_wrap.isChange:
    result.noWrap = no_wrap.value
  if highlight.isChange:
    result.highlight = highlight.value
  if markup.isChange:
    result.markup = markup.value
  if height.isChange:
    if height.value.isSome:
      result.maxHeight = height.value.get
    result.height = if height.value.isSome: some(max(0, height.value.get))
                    else: none(int)

proc updateWidth*(options: ConsoleOptions, width: int): ConsoleOptions =
  ## Update just the width (sets both `minWidth` and `maxWidth`), return a copy —
  ## rich `ConsoleOptions.update_width` (console.py:194-205).
  result = options.copyOpts()
  let w = max(0, width)
  result.minWidth = w
  result.maxWidth = w

proc updateHeight*(options: ConsoleOptions, height: int): ConsoleOptions =
  ## Update the height, and return a copy — rich `ConsoleOptions.update_height`
  ## (console.py:207-218).
  result = options.copyOpts()
  result.maxHeight = height
  result.height = some(height)

proc resetHeight*(options: ConsoleOptions): ConsoleOptions =
  ## Return a copy with `height` set to `None` — rich `ConsoleOptions.reset_height`
  ## (console.py:220-228).
  result = options.copyOpts()
  result.height = none(int)

proc updateDimensions*(options: ConsoleOptions, width: int, height: int): ConsoleOptions =
  ## Update the width and height, and return a copy — rich
  ## `ConsoleOptions.update_dimensions` (console.py:230-243).
  result = options.copyOpts()
  let w = max(0, width)
  result.minWidth = w
  result.maxWidth = w
  result.height = some(height)
  result.maxHeight = height

# ---------------------------------------------------------------------------
# Segment core signatures — segment.py:60-184
# (Extended operations live in `segment.nim` — see file header.)
# ---------------------------------------------------------------------------

proc cellLength*(segment: Segment): int =
  ## The number of terminal cells required to display `segment.text` — rich
  ## `Segment.cell_length` property (segment.py:78-86; @property @78, def
  ## 79-86): `0 if control else cell_len(text)`. Body needs
  ## `cells.cellLen`.
  if segment.control.isSome:
    result = 0
  else:
    # [body deferral] `cell_len` (rich `cells.cell_len`) measures wide
    # (2-cell) characters; `cells` is not ported. `runeLen` approximates
    # cell count as 1 cell per rune — correct for ASCII/1-cell text; the
    # wide-char correction is wired when `cells.cellLen` lands.
    result = runeLen(segment.text)

proc isControl*(segment: Segment): bool =
  ## Check if the segment contains control codes — rich `Segment.is_control`
  ## property (segment.py:101-104; @property @101, def 102-104):
  ## `control is not None`.
  result = segment.control.isSome

proc hasText*(segment: Segment): bool =
  ## Check if the segment contains text — rich `Segment.__bool__`
  ## (segment.py:97-99): `bool(self.text)`.
  result = segment.text.len > 0

proc line*(): Segment =
  ## Make a new line segment — rich `Segment.line` classmethod
  ## (segment.py:181-184; @classmethod @181, def 182-184). Returns
  ## `Segment("\n")`.
  result = Segment(text: "\n")

# [Nim-only forward declaration] `splitCellsImpl` is defined below (richbase
# `_split_cells` worker); declared here so `splitCells` (the public entry) can
# delegate to it (Nim requires declaration before use).
proc splitCellsImpl*(segment: Segment, cut: int): tuple[a: Segment, b: Segment]

proc splitCells*(segment: Segment, cut: int): tuple[a: Segment, b: Segment] =
  ## Split a segment into two at `cut` cells — rich `Segment.split_cells`
  ## (segment.py:155-179). If the cut point falls in the middle of a 2-cell
  ## wide character it is replaced by two spaces to preserve display width.
  assert cut >= 0
  # [body deferral] `_is_single_cell_widths` (rich `cells`) is not ported,
  # so the all-1-cell fast path cannot be distinguished from the multi-cell
  # case. Delegate to `splitCellsImpl` (the wide-char worker) — which itself
  # rune-slices as a 1-cell approximation until `cells.getCharacterCellSize`
  # lands. Correct for ASCII/1-cell text; 2-cell boundary handling deferred.
  result = splitCellsImpl(segment, cut)

proc splitCellsImpl*(segment: Segment, cut: int): tuple[a: Segment, b: Segment] =
  ## Cached worker for `splitCells` — rich `Segment._split_cells` classmethod
  ## (segment.py:106-153; @classmethod @106, @lru_cache @107, def 108-153).
  ## Body needs `cells.getCharacterCellSize`.
  # [body deferral] the wide-char boundary cases (out_by ±1 with a 2-cell
  # character replaced by two spaces, segment.py:130-145) need
  # `cells.cellLen`/`getCharacterCellSize`; `cells` is not ported. Approximate
  # by rune-slicing at `cut` (treats each rune as 1 cell) — correct for
  # all-1-cell text; the 2-cell space-replacement is wired when `cells` lands.
  let rl = runeLen(segment.text)
  if cut >= rl:
    result = (a: segment,
              b: Segment(text: "", style: segment.style, control: segment.control))
  else:
    let before = runeSubStr(segment.text, 0, cut)
    let after = runeSubStr(segment.text, cut)
    result = (a: Segment(text: before, style: segment.style,
                         control: segment.control),
              b: Segment(text: after, style: segment.style,
                         control: segment.control))
