## Port of `rich.text` (rich/text.py).
##
## `Text` is rich's styled-text container: a piece of plain text plus a list of
## `Span`s (marked-up regions each carrying a `Union[str, Style]` style) and
## layout knobs (`justify`/`overflow`/`no_wrap`/`end`/`tab_size`). `Span` is a
## `NamedTuple` (text.py:47-115); `Text(JupyterMixin)` (text.py:118-1335).
##
## Import graph (rich/text.py:1-33): runtime sibling imports are
## `from .align import AlignMethod` (text.py:22), `from .cells import cell_len,
## set_cell_size` (text.py:23), `from .containers import Lines` (text.py:24),
## `from .control import strip_control_codes` (text.py:25),
## `from .emoji import EmojiVariant` (text.py:26),
## `from .jupyter import JupyterMixin` (text.py:27),
## `from .measure import Measurement` (text.py:28),
## `from .segment import Segment` (text.py:29),
## `from .style import Style, StyleType` (text.py:30); `from .console import
## Console, ConsoleOptions, JustifyMethod, OverflowMethod` (text.py:33) is
## TYPE_CHECKING-only. `from ._loop import loop_last` (text.py:19),
## `from ._pick import pick_bool` (text.py:20), `from ._wrap import
## divide_line` (text.py:21) are private helpers used in bodies. `import re`
## (text.py:1) provides `re.Pattern[str]` (used in `highlight_regex`).
##
## wiring (this file):
##   `import segment`  — re-exports `richbase` (`Segment`, `ConsoleOptions`,
##                       `ConsoleHandle`, `RenderResult`, `RenderableBase`,
##                       `RenderableType`, `JustifyMethod`, `OverflowMethod`,
##                       `NO_CHANGE`, …) and `Style` (segment.py:9, 10-11).
##   `import style`     — `Style`, `StyleType` (`string or Style`), `StyleOpt`
##                       (the `Optional[StyleType]` case object), `StyleOptKind`
##                       and the four `toStyleOpt*` converters (style.py:19,405).
##   `import measure`   — `Measurement` (measure.py:11).
## `cells`/`containers`/`control`/`emoji`/`jupyter`/`_loop`/`_pick`/`_wrap`/`re`/
## `markup`/`ansi` are body-only deps and are NOT imported  (their
## names that appear in *signatures* are modelled by the non-narrowing forward
## handles documented below).
##
## Non-narrowing forward handles (PUBLIC, PROVISIONAL — replaced by the real
## module in a later wave, like `color.nim`'s forward handles but exported so
## no legal public-API variant is rejected):
##   `Lines`         — rich `containers.Lines` (text.py:24, containers.py:66; the
##                     return type of `split`/`divide`/`wrap`/`fit`). A PUBLIC
##                     `object` placeholder so a consumer can name and
##                     construct it (`var xs: Lines = t.split()`). Removed when
##                     `containers.nim` is written and `Lines` is imported.
##   `EmojiVariant`  — rich `emoji.EmojiVariant` (emoji.py:13 =
##                     `Literal["emoji", "text"]`, imported by text.py:26; the
##                     `emoji_variant` param of `from_markup`). A PUBLIC
##                     string-valued enum (`evEmoji`/`evText`) faithful to the
##                     two `Literal` arms so `some(evEmoji)`/`some(evText)`
##                     compile; removed when `emoji.nim` is written.
##   `RePattern`     — rich `re.Pattern[str]` (text.py:1; the `re_highlight`
##                     param of `highlight_regex`). A PUBLIC `object`
##                     placeholder so the `string or RePattern` typeclass admits
##                     both arms of `Union[Pattern[str], str]` (text.py:594) and
##                     a consumer can write `highlightRegex(RePattern(), …)`;
##                     removed when a regex module is wired in body.
##
## Hosted public type (mirrors `richbase` hosting `segment.py` types):
##   `AlignMethod`   — rich `align.AlignMethod` (align.py:13-13;
##                     `Literal["left","center","right"]`). `align.nim` is written
##                     *after* `text.nim` in this wave, so `text.nim`
##                     cannot `import align`; instead `AlignMethod` is hosted
##                     here (exported) and `align.nim` re-exports it
##                     (`import text; export AlignMethod`), exactly as
##                     `richbase` hosts `Segment`/`ControlType`/`ControlCode`
##                     (segment.py:32-57,60-696) and `segment.nim` re-exports
##                     `richbase`. One `AlignMethod` type is visible through both
##                     `nim_rich/text` and `nim_rich/align`, matching Python's
##                     `from .align import AlignMethod` (text.py:22) and
##                     `from rich.align import AlignMethod`.
##
## `Text(JupyterMixin)` base: `jupyter.nim` is not yet written, so `Text` is
## `ref object of RenderableBase` (the richbase concrete renderable base,
## richbase.nim), matching how `segment.nim` models `Segments`/`SegmentLines`.
## `JupyterMixin` (jupyter.py) is a mixin adding Jupyter display methods and is
## a Body concern; the renderable protocol (`renderConsole`/
## `richMeasure`) is modelled directly on `Text`.
##
## Naming: Python `__str__`→`$`, `__repr__`→`repr`, `__bool__`→`bool`,
## `__len__`→`len`, `__eq__`→`==`, `__contains__`→`contains`, `__add__`→`+`,
## `__getitem__`→`[]`, `__rich_console__`→`renderConsole`,
## `__rich_measure__`→`richMeasure` (per the cross-cutting decisions in
## `API_CONTRACT.md`; `repr`/`bool`/`len`/`==`/`+`/`[]` overload the system
## procs on the `Text`/`Span` receiver, as `style.nim` does for `Style`).
## `end` is a Nim keyword, so the `end` slot/params are backtick-quoted
## `` `end` `` (mirroring `color.nim`'s backtick `` `type` `` field). snake_case
## keyword params are camelCased (`no_wrap`→`noWrap`, `tab_size`→`tabSize`,
## `include_separator`→`includeSeparator`, `allow_blank`→`allowBlank`,
## `case_sensitive`→`caseSensitive`, `style_prefix`→`stylePrefix`,
## `emoji_variant`→`emojiVariant`, `indent_size`→`indentSize`,
## `max_width`→`maxWidth`, `new_length`→`newLength`, `remove_suffix`→…,
## `right_crop`→`rightCrop`, `extend_style`→`extendStyle`,
## `apply_meta`→`applyMeta`, `set_length`→`setLength`, `expand_tabs`→
## `expandTabs`, `with_indent_guides`→`withIndentGuides`,
## `detect_indentation`→`detectIndentation`, `from_markup`→`fromMarkup`,
## `from_ansi`→`fromAnsi`, `append_text`→`appendText`,
## `append_tokens`→`appendTokens`, `copy_styles`→`copyStyles`,
## `highlight_regex`→`highlightRegex`, `highlight_words`→`highlightWords`,
## `get_style_at_offset`→`getStyleAtOffset`, `stylize_before`→`stylizeBefore`,
## `blank_copy`→`blankCopy`, `_trim_spans`→`trimSpans`, `rstrip_end`→
## `rstripEnd`). Python `Union[str, Style]` (Span.style / Text.style) is the
## `StyleValue` case object (no `None` arm — faithful to `Union[str, Style]`,
## unlike `StyleOpt` which adds the `None` arm of `Optional[StyleType]`); the
## `toStyleValue*` converters let `Span(style: "bold")` / `Span(style: aStyle)`
## / `initText(style: "bold")` / `initText(style: aStyle)` all compile.
## Python `Optional[Union[str, Style]]` (`Style.append`'s `style`,
## `highlight_regex`'s `style`) reuses `style.StyleOpt` (the existing
## `Optional[StyleType]` handle + its converters). `highlight_regex`'s
## `style: Optional[Union[GetStyleCallable, StyleType]]` (text.py:596) is
## modelled as the non-narrowing typeclass `StyleOpt or GetStyleCallable`
## (default `default(StyleOpt)` = `None`): a `str`/`Style` converts to `StyleOpt`
## via the existing `toStyleOpt*` converters, a `GetStyleCallable` satisfies the
## callable arm, and `None` is the default. `Text.assemble`'s `*parts:
## Union[str, "Text", Tuple[str, StyleType]]` (text.py:357) is heterogeneous, so
## `assemble` is a `template` with `varargs[untyped]` (the same technique as
## `style.nim`'s `on` for `**handlers: Any`), with the keyword-only `style`/
## `justify`/… params after the varargs. `Iterable[T]` inputs are `openArray[T]`
## (accepts `seq`/`array`/`openArray` — materialized iterables; raw closure
## iterators / generators are a conscious body boundary, the identical,
## operator-accepted boundary applied to the frozen `segment.nim`, and are NOT
## claimed to be non-narrowing for iterators). Proc bodies mirror the Python source
## (`discard`; `default(T)` for the `assemble`/`on` templates).

import std/[options, tables, json, strutils, sequtils, math, algorithm,
              macros]

import segment      # re-exports richbase (Segment, ConsoleOptions,
                    # ConsoleHandle, RenderResult, RenderableBase,
                    # RenderableType, JustifyMethod, OverflowMethod, NO_CHANGE)
                    # and Style (segment.py:9, 10-11).
import style        # Style, StyleType (string or Style), StyleOpt
                    # (Optional[StyleType]), StyleOptKind, toStyleOpt*.
import measure      # Measurement (measure.py:11).
import control      # stripControlCodes (control.py:119-135) — body dep for
                    # `initText`/`append`/`appendTokens`; cycle-free (control
                    # imports segment, NOT text).
import cells        # cellLen/setCellSize/chopCells (cells.py) — body deps for
                    # `cellLen`/`truncate`/`align`/`richMeasure`/`divideLine`;
                    # cycle-free leaf (cells imports std only).
import errors       # MarkupError — raised by `renderMarkupInline`'s tag-mismatch
                    # arms (markup.py:135,141,158,167). Leaf module (no imports),
                    # so `text` can `import errors` without a cycle.
import console_api  # `ConsoleHandle.getStyle` dispatch (rich text.py:731
                    # `partial(console.get_style, default=Style.null())`):
                    # `Text.render` resolves styles via the real `Console.getStyle`
                    # (theme-aware — `table.title`->italic) instead of the local
                    # `getStyleLocal` stand-in. Cycle-free leaf: `console_api`
                    # imports only richbase/style/segment/measure/api_types
                    # (none import text), so `text` can `import console_api`.
                    # The base `getStyle` mirrors the former `getStyleLocal`
                    # (`Style.parse`/`.copy()`, null on miss), so the placeholder
                    # `ConsoleHandle` used by the plain-Text golden cases is
                    # unaffected (parseable styles resolve identically).
import pcre                # PCRE 8.x C API — `exec`/`fullinfo` + `INFO_NAME*`/
                    # `NOTEMPTY`/`NOTEMPTY_ATSTART` consts (lib/wrappers/pcre.nim);
                    # `highlightRegex`'s `re.finditer` engine. Already linked
                    # via `syntax.nim`→`nimgments`→`pcre_wrap`→`pcre`; the
                    # `nim.cfg` rpath finds `libpcre.so.1` at runtime.
import nimgments/pcre_wrap # `compileRegex`/`CompiledRegex` (UTF8|UCP compile,
                    # JIT study, numbered capture spans) for `highlightRegex`.

type
  AlignMethod* = enum
    ## rich align.py:13-13 — `AlignMethod = Literal["left", "center",
    ## "right"]`. String-valued enum so `$` yields the exact Python token for
    ## byte-identical output. HOSTED in `text.nim` (exported) because
    ## `align.nim` is written after `text.nim` in this wave and
    ## `text.nim` cannot `import align`; `align.nim` re-exports it. One type is
    ## visible via both `nim_rich/text` and `nim_rich/align`, matching Python's
    ## `from .align import AlignMethod` (text.py:22).
    amLeft = "left"      ## the `"left"` literal.
    amCenter = "center"  ## the `"center"` literal.
    amRight = "right"     ## the `"right"` literal.

  ## `StyleValue` (the `Union[str, Style]` handle) lives in `style.nim`
  ## (its logical home, needs `Style`); this module re-uses it via `import style`.

  Span* = object
    ## rich text.py:47-115 — `class Span(NamedTuple)`: a marked up region in
    ## some text. A value object (Python `NamedTuple` ⇒ Nim `object`), with the
    ## three NamedTuple fields and six methods modelled as procs taking a
    ## `Span` value.
    start*: int           ## rich text.py:50-50 — `start: int` (Span start index).
    `end`*: int           ## rich text.py:52-52 — `end: int` (Span end index). Backtick-quoted (`end` is a Nim keyword), like `color.nim`'s `` `type` ``.
    style*: StyleValue    ## rich text.py:54-54 — `style: Union[str, Style]` (the `StyleValue` case object).

  Text* = ref object of RenderableBase
    ## rich text.py:118-1335 — `class Text(JupyterMixin)`: text with color /
    ## style. `ref object of RenderableBase` (Python `Text` has reference
    ## semantics — `__slots__` + mutating methods — so a Nim `ref` is the
    ## faithful mirror, like `style.Style`). `JupyterMixin` (jupyter.py) is not
    ## yet written; modelled via `RenderableBase` (see file header). Fields
    ## mirror the `__slots__` assignments of `__init__` (text.py:157-165).
    textPieces*: seq[string]            ## rich text.py:157-157 — `self._text = [sanitized_text]` (a `List[str]`; renamed `_text`→`textPieces`).
    style*: StyleValue                   ## rich text.py:158-158 — `self.style = style` (`Union[str, Style]`).
    justify*: Option[JustifyMethod]      ## rich text.py:159-159 — `self.justify = justify` (`Optional[JustifyMethod]`).
    overflow*: Option[OverflowMethod]    ## rich text.py:160-160 — `self.overflow = overflow` (`Optional[OverflowMethod]`).
    noWrap*: Option[system.bool]               ## rich text.py:161-161 — `self.no_wrap = no_wrap` (`Optional[bool]`).
    `end`*: string                       ## rich text.py:162-162 — `self.end = end` (`str`). Backtick-quoted (`end` is a Nim keyword).
    tabSize*: Option[int]                ## rich text.py:163-163 — `self.tab_size = tab_size` (`Optional[int]`).
    spansData*: seq[Span]                ## rich text.py:164-164 — `self._spans = spans or []` (a `List[Span]`; renamed `_spans`→`spansData`).
    length*: int                         ## rich text.py:165-165 — `self._length = len(sanitized_text)` (`int`; renamed `_length`→`length`).

  TextType* = string or Text
    ## rich text.py:41-41 — `TextType = Union[str, "Text"]`. A plain string or
    ## a `Text` instance. Modelled as a Nim typeclass (NON-NARROWING: a
    ## `string` or a `Text` value satisfies it; an `int` does not).

  GetStyleCallable* = proc(s: string): StyleOpt {.closure.}
    ## rich text.py:44-44 — `GetStyleCallable = Callable[[str],
    ## Optional[StyleType]]`. A callable accepting a `str` and returning an
    ## `Optional[StyleType]` (modelled as `StyleOpt`, the existing
    ## `Optional[StyleType]` handle). Modelled as a Nim closure proc type.

  # [PUBLIC PROVISIONAL FORWARD HANDLES — NOT FROZEN] (see file header):
  Lines* = object
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `containers.Lines` (text.py:24; the return type of `Text.split`/
    ## `divide`/`wrap`/`fit`, text.py:1062,1106,1201,1252). PUBLIC (exported) so
    ## the public API can name and construct it: a consumer may write
    ## `var xs: Lines = t.split()` and pass a `Lines` value around. PROVISIONAL:
    ## removed by name when `containers.nim` is written and the real `Lines` is
    ## imported (the `split`/`divide`/`wrap`/`fit` return types are *not* frozen
    ## — revisited against the real `Lines`, containers.py:66, once
    ## `containers.nim` exists). The placeholder is public so no legal public
    ## API variant is rejected; it is removed verbatim when `containers.nim` is
    ## imported. Mirrors `color.nim`'s forward-handle technique but exported so
    ## consumers can name the type.

  EmojiVariant* = enum
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `emoji.EmojiVariant` (emoji.py:13-13 = `Literal["emoji", "text"]`,
    ## imported by text.py:26; the `emoji_variant` param of `Text.from_markup`,
    ## text.py:266). PUBLIC (exported) string-valued enum — faithful to the
    ## `Literal["emoji", "text"]` (exactly two variants, NOT
    ## `"default"/"emoji"/"text"`): `evEmoji = "emoji"`, `evText = "text"`,
    ## so `$` yields the exact Python token for byte-identical output. PUBLIC so
    ## the legal variants compile via the public API: a consumer may write
    ## `Text.fromMarkup(t, emojiVariant = some(evEmoji))` /
    ## `some(evText)` / `none(EmojiVariant)`. PROVISIONAL: removed by name when
    ## `emoji.nim` is written and the real `EmojiVariant` is imported
    ## (revisited against emoji.py:13 once `emoji.nim` exists).
    evEmoji = "emoji"  ## the `"emoji"` literal (emoji.py:13).
    evText = "text"    ## the `"text"`  literal (emoji.py:13).

  RePattern* = object
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `re.Pattern[str]` (text.py:1; the `re_highlight` param of
    ## `highlight_regex`, text.py:594). PUBLIC (exported) `object` placeholder
    ## for a compiled regex; the `string or RePattern` typeclass admits both
    ## arms of `Union[Pattern[str], str]` (text.py:594). PUBLIC so the legal
    ## regex variant compiles via the public API: a consumer may write
    ## `t.highlightRegex(RePattern(), "bold")` (compiled-regex arm) alongside
    ## `t.highlightRegex("foo", "bold")` (string arm). PROVISIONAL: removed by
    ## name when a regex module is wired in body. Until then the handle
    ## stores the regex SOURCE `pattern` (not a compiled form): both arms of
    ## `string or RePattern` compile it via PCRE in `highlightRegex`, so
    ## `RePattern(pattern: r"\d+")` and `"\d+"` match identically.
    pattern*: string  ## regex source string (PROVISIONAL — replaced by a real compiled-regex type when a regex module supersedes this handle).

## `toStyleValue` converters live in `style.nim` (with `StyleValue`); this
## module re-uses them via `import style`.

# ---------------------------------------------------------------------------
# Module-level bindings — text.py:35-44
# ---------------------------------------------------------------------------

const DEFAULT_JUSTIFY*: JustifyMethod = jmDefault
  ## rich text.py:35-35 — `DEFAULT_JUSTIFY: "JustifyMethod" = "default"`. The
  ## default justify method. `jmDefault` is richbase's `JustifyMethod` member
  ## whose `$` is `"default"` (byte-identical to the Python literal).

const DEFAULT_OVERFLOW*: OverflowMethod = omFold
  ## rich text.py:36-36 — `DEFAULT_OVERFLOW: "OverflowMethod" = "fold"`. The
  ## default overflow method. `omFold` is richbase's `OverflowMethod` member
  ## whose `$` is `"fold"`.

let reWhitespace* = r"\s+$"
  ## rich text.py:39-39 — `_re_whitespace = re.compile(r"\s+$")`. Mirrors the
  ## private `_re_whitespace` (renamed `reWhitespace`); stores the
  ## pattern string, body compiles it to a `RePattern` (used by
  ## `rstrip_end`, text.py:670).

# ---------------------------------------------------------------------------
# body private helpers & forward declarations (Nim-only; NOT frozen).
# `rich._loop`/`_pick`/`_wrap`/`re` have no Nim modules, so `loop_last`/
# `divide_line`/`words` are inlined here. `markup.escape` is inlined as
# `escapeMarkup` because `markup.nim` imports `text` (text↔markup cycle), so
# `text` cannot `import markup` (Nim forbids the cycle); this is a minimal,
# cycle-forced inline of markup.nim's frozen `escape`. `divideToSeq`/
# `splitToSeq` are the real `divide`/`split` logic returning `seq[Text]` (the
# public `divide`/`split` return the provisional `Lines` placeholder — see file
# header — so the logic is factored here for reuse by `[]`/`wrap`/`fit`/
# `withIndentGuides`/`expandTabs`, which CAN observe a `seq[Text]`).
# ---------------------------------------------------------------------------

# Forward declarations of later-defined public procs, so the `assemble`
# macro (`bindSym "append"`) and the `assemble` template (`applyMeta`) can
# reference them (they are defined further down in the file).
proc append*(self: Text, text: Text or string,
            style: StyleOpt = default(StyleOpt)): Text
proc applyMeta*(self: Text, meta: Table[string, JsonNode], start: int = 0,
                `end`: Option[int] = none(int))
proc trimSpans*(self: Text)
proc rightCrop*(self: Text, amount: int = 1)
proc padRight*(self: Text, count: int, character: string = " ")
proc align*(self: Text, align: AlignMethod, width: int,
           character: string = " ")
proc plain*(self: Text): string
proc copy*(self: Text): Text
proc spans*(self: Text): seq[Span]
proc render*(self: Text, console: ConsoleHandle, `end`: string = ""): RenderResult
proc join*(self: Text, lines: openArray[Text]): Text
proc wrapToSeq*(self: Text, console: ConsoleHandle, width: int,
               justify: JustifyMethod, overflow: OverflowMethod,
               tabSize: int, noWrap: bool): seq[Text]
proc pickBool3(a, b: Option[system.bool], c: bool): bool

proc pyReprStr(s: string): string =
  ## Best-effort Python `repr` for a string (single-quoted), mirroring
  ## `f"{x!r}"` for `Span`/`Text` repr (text.py:57,177). Escapes `\` and `'`;
  ## control-char escaping matches Python for the common cases.
  result = "'"
  for ch in s:
    case ch
    of '\\': result.add("\\\\")
    of '\'': result.add("\\'")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(ch)
  result.add("'")

proc styleValueTruthy(sv: StyleValue): bool =
  ## Python `if style:` truthiness for a `Union[str, Style]`: a non-empty `str`
  ## or a truthy `Style` (text.py:243,540,972,1021).
  case sv.kind
  of svkStr: result = sv.strv.len > 0
  of svkStyle: result = sv.stv.bool

proc styleValueTag(sv: StyleValue): string =
  ## The string form used in a `[style]`/`[/style]` markup tag (text.py:243,256):
  ## `str(style)` — a `str` style is itself; a `Style` is its definition.
  case sv.kind
  of svkStr: result = sv.strv
  of svkStyle: result = $sv.stv

proc styleValueEqual(a, b: StyleValue): bool =
  ## Value equality for `Union[str, Style]` (used by `Text.==` via `spanEqual`).
  if a.kind != b.kind: return false
  case a.kind
  of svkStr: result = a.strv == b.strv
  of svkStyle: result = a.stv == b.stv

proc spanEqual(a, b: Span): bool =
  ## Element-wise `Span` equality (Python `NamedTuple.__eq__`).
  result = a.start == b.start and a.`end` == b.`end` and
           styleValueEqual(a.style, b.style)

proc styleTypeTruthy(style: StyleType): bool =
  ## Python `if style:` for a `StyleType` (`string or Style`) param: a non-empty
  ## `str` or a truthy `Style` (text.py:465,485,972).
  when typeof(style) is string: result = style.len > 0
  else: result = style.bool

proc styleTypeToValue(style: StyleType): StyleValue =
  ## Wrap a `StyleType` (`string or Style`) param as the `StyleValue` field
  ## type (dispatching on the compile-time arm).
  when typeof(style) is string:
    result = StyleValue(kind: svkStr, strv: style)
  else:
    result = StyleValue(kind: svkStyle, stv: style)

proc styleOptTruthy(so: StyleOpt): bool =
  ## Python `if style:` for a `StyleOpt` (`Optional[StyleType]`) value: `None`
  ## ⇒ false, a non-empty `str` ⇒ true (empty `str` ⇒ false, matching Python's
  ## falsy empty string), a `Style` ⇒ its `__bool__`.
  case so.kind
  of sokNone: result = false
  of sokStr: result = so.strv.len > 0
  of sokStyle: result = so.stv.bool

proc styleOptToValue(so: StyleOpt): StyleValue =
  ## Wrap a truthy `StyleOpt` as the `StyleValue` field type (the `None` arm is
  ## unreachable here — callers gate on `styleOptTruthy`; the placeholder is a
  ## benign empty `str` style).
  case so.kind
  of sokNone: result = StyleValue(kind: svkStr, strv: "")
  of sokStr: result = StyleValue(kind: svkStr, strv: so.strv)
  of sokStyle: result = StyleValue(kind: svkStyle, stv: so.stv)

proc escapeMarkup(plain: string): string =
  ## Minimal inline of `rich.markup.escape` (markup.py:43-62). `markup.nim`
  ## imports `text` (text↔markup cycle), so `text` cannot `import markup`; this
  ## is a cycle-forced verbatim copy of markup.nim's frozen `escape` (the
  ## `markup` property's only external dep). Doubles backslashes before
  ## tag-like brackets and guards a trailing backslash.
  proc isTagChar(c: char): bool {.inline.} = c in {'a'..'z', '#', '/', '@'}
  let n = plain.len
  var i = 0
  while i < n:
    let bsStart = i
    while i < n and plain[i] == '\\': inc i
    let bs = i - bsStart
    var consumed = false
    if i < n and plain[i] == '[':
      var j = i + 1
      if j < n and isTagChar(plain[j]):
        inc j
        while j < n and plain[j] != '[' and plain[j] != ']': inc j
        if j < n and plain[j] == ']':
          for k in 1 .. (bs * 2): result.add('\\')
          result.add('\\')
          result.add(plain[i .. j])
          i = j + 1
          consumed = true
    if not consumed:
      for k in 1 .. bs: result.add('\\')
      if bs == 0 and i < n:
        result.add(plain[i])
        inc i
  if result.len >= 1 and result[^1] == '\\' and
      not (result.len >= 2 and result[^2] == '\\'):
    result.add('\\')

proc getStyleLocal(sv: StyleValue): Style =
  ## Best-effort local stand-in for `console.get_style(style)` (text.py:564-567)
  ## — resolves a literal style `str` via `Style.parse` (unresolvable ⇒
  ## `Style.null()`, matching `get_style(style, default="")`) and a `Style` via
  ## `.copy()`. Ignores the console's theme registry (the `Console` is the
  ## opaque `ConsoleHandle` placeholder); themed names therefore resolve to
  ## the null style, unlike a real console. Documented approximation.
  case sv.kind
  of svkStr:
    try: result = Style.parse(sv.strv)
    except CatchableError: result = Style.null()
  of svkStyle: result = sv.stv.copy()

proc resolveStyle(console: ConsoleHandle, sv: StyleValue): Style =
  ## Theme-aware style resolution via the real `Console.getStyle` dispatch
  ## (rich text.py:731 — `partial(console.get_style, default=Style.null())`).
  ## A `str` style resolves through the Console theme registry (e.g.
  ## `table.title`->italic, `table.caption`->dim-italic) and falls back to
  ## `Style.null()` for unresolvable names (`default=Style.null()`, no raise);
  ## a `Style` is returned via the same dispatch (the `Console` override
  ## returns it, the base copies it). A placeholder/nil `ConsoleHandle` (the
  ## `default(ConsoleHandle)` the plain-Text/Rule golden harness uses) cannot
  ## be dispatched on (a method call on a nil ref is a vtable nil-deref), so a
  ## nil handle falls back to `getStyleLocal` — the former local stand-in —
 ## which resolves parseable styles/empty strings identically (the 24
  ## plain-Text/Rule cases are byte-identical); a real `Console` dispatches to
  ## `getStyle` and resolves theme names (`table.title`->italic). Used by
  ## `Text.render` (no-spans + spans paths) so title/caption annotations rendered
  ## through the real `Console` resolve theme names; `getStyleAtOffset` keeps
  ## `getStyleLocal` (not in the render path, out of scope).
  if console.isNil:
    result = getStyleLocal(sv)
  else:
    let nullDefault = StyleOpt(kind: sokStyle, stv: Style.null())
    case sv.kind
    of svkStr: result = console.getStyle(sv.strv, default = nullDefault)
    of svkStyle: result = console.getStyle(sv.stv)

proc isWrapWs(c: char): bool {.inline.} =
  ## `re` `\s` for the `_wrap.words` scan: space/tab/newline/etc.
  c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\v' or c == '\f'

proc words(text: string): seq[(int, int, string)] =
  ## rich `_wrap.words` (inlined, no `std/re`): yield `(start, end, word)` per
  ## `\s*\S+\s*` match — leading whitespace, the word, trailing whitespace.
  result = @[]
  var position = 0
  let n = text.len
  while position < n:
    let startIdx = position
    var i = position
    while i < n and isWrapWs(text[i]): inc i
    let wordStart = i
    while i < n and not isWrapWs(text[i]): inc i
    if i == wordStart: break  # no `\S+` ⇒ `re_word.match` fails
    let wordEnd = i
    while i < n and isWrapWs(text[i]): inc i
    result.add((startIdx, i, text[startIdx ..< i]))
    position = i

proc divideLine(text: string, width: int, fold: bool = true): seq[int] =
  ## rich `_wrap.divide_line` (inlined): the cell offsets at which to break
  ## `text` so it fits `width` cells (text.py via `_wrap.divide_line`, used by
  ## `wrap`). `fold` folds over-long words; else crops. Uses `cells.cellLen`/
  ## `chopCells` (the `cells` body dep).
  result = @[]
  var cellOffset = 0
  for (start0, _, word) in words(text):
    var start = start0
    let wordLength = cellLen(strip(word, leading = false))
    let remainingSpace = width - cellOffset
    if remainingSpace >= wordLength:
      cellOffset += cellLen(word)
    else:
      if wordLength > width:
        if fold:
          let folded = chopCells(word, width)
          let cnt = folded.len
          for k in 0 ..< cnt:
            let last = k == cnt - 1
            let line = folded[k]
            if start != 0: result.add(start)
            if last: cellOffset = cellLen(line)
            else: start += line.len
        else:
          if start != 0: result.add(start)
          cellOffset = cellLen(word)
      elif cellOffset != 0 and start != 0:
        result.add(start)
        cellOffset = cellLen(word)

# ---------------------------------------------------------------------------
# Span methods — text.py:57-115
# ---------------------------------------------------------------------------

proc repr*(s: Span): string =
  ## rich text.py:57-58 — `Span.__repr__(self) -> str`:
  ## `f"Span({self.start}, {self.end}, {self.style!r})"`.
  let styleRepr = case s.style.kind
    of svkStr: pyReprStr(s.style.strv)
    of svkStyle: pyReprStr($s.style.stv)
      # `Style.__repr__` (the `Style(color=Color(...), …)` form) is deferred
      # behind `style.nim`'s `richRepr` stub; fall back to the quoted style
      # definition string (the common span style is a `str`, which is exact).
  result = "Span(" & $s.start & ", " & $s.`end` & ", " & styleRepr & ")"

proc bool*(s: Span): bool =
  ## rich text.py:60-61 — `Span.__bool__(self) -> bool`: `self.end > self.start`
  ## (a span is truthy iff it covers at least one character).
  result = s.`end` > s.start

proc split*(s: Span, offset: int): tuple[a: Span, b: Option[Span]] =
  ## rich text.py:63-74 — `Span.split(self, offset: int) -> Tuple["Span",
  ## Optional["Span"]]`: split a span in two at `offset`; returns `(self, None)`
  ## if `offset < start` or `offset >= end`, else `(Span(start, min(end,
  ## offset), style), Span(span1.end, end, style))` (text.py:66-73). The
  ## Python `Tuple["Span", Optional["Span"]]` is modelled as a named tuple
  ## `tuple[a: Span, b: Option[Span]]` (the second field is the optional
  ## second span).
  if offset < s.start or offset >= s.`end`:
    result = (a: s, b: none(Span))
  else:
    let span1 = Span(start: s.start, `end`: min(s.`end`, offset), style: s.style)
    let span2 = Span(start: span1.`end`, `end`: s.`end`, style: s.style)
    result = (a: span1, b: some(span2))

proc move*(s: Span, offset: int): Span =
  ## rich text.py:76-86 — `Span.move(self, offset: int) -> "Span"`: return a
  ## new span with `start` and `end` shifted by `offset`
  ## (`Span(start + offset, end + offset, style)`, text.py:85).
  result = Span(start: s.start + offset, `end`: s.`end` + offset, style: s.style)

proc rightCrop*(s: Span, offset: int): Span =
  ## rich text.py:88-100 — `Span.right_crop(self, offset: int) -> "Span"`: crop
  ## the span at `offset` — returns `self` if `offset >= end`, else
  ## `Span(start, min(offset, end), style)` (text.py:94-99).
  if offset >= s.`end`:
    result = s
  else:
    result = Span(start: s.start, `end`: min(offset, s.`end`), style: s.style)

proc extend*(s: Span, cells: int): Span =
  ## rich text.py:102-115 — `Span.extend(self, cells: int) -> "Span"`: extend
  ## the span by `cells` — returns `self` if `cells` is falsy, else
  ## `Span(start, end + cells, style)` (text.py:113-114).
  if cells != 0:
    result = Span(start: s.start, `end`: s.`end` + cells, style: s.style)
  else:
    result = s

# ---------------------------------------------------------------------------
# Text dunders & properties — text.py:144-257
# ---------------------------------------------------------------------------

proc initText*(text: string = "", style: StyleType = "",
               justify: Option[JustifyMethod] = none(JustifyMethod),
               overflow: Option[OverflowMethod] = none(OverflowMethod),
               noWrap: Option[system.bool] = none(system.bool), `end`: string = "\n",
               tabSize: Option[int] = none(int),
               spans: Option[seq[Span]] = none(seq[Span])): Text =
  ## rich text.py:144-165 — `Text.__init__(self, text: str = "", style:
  ## Union[str, Style] = "", *, justify: Optional["JustifyMethod"] = None,
  ## overflow: Optional["OverflowMethod"] = None, no_wrap: Optional[bool] =
  ## None, end: str = "\n", tab_size: Optional[int] = None, spans:
  ## Optional[List[Span]] = None) -> None`. Keyword-only after `style` (Python
  ## `*`, text.py:147). `style: Union[str, Style] = ""` modelled as the
  ## typeclass `StyleType = string or Style` with default `""` (every legal
  ## variant compiles — `initText()`, `initText("x", "bold")` (str),
  ## `initText("x", aStyle)` (Style) — while `initText("x", 5)` is rejected).
  ## `justify`/`overflow`/`noWrap`/`tabSize`/`spans` are `Optional[…]` →
  ## `Option[…]`; `end` is backtick-quoted (Nim keyword); `spans:
  ## Optional[List[Span]]` → `Option[seq[Span]]`. (returns a nil
  ## `Text`); body populates the `__slots__` (text.py:157-165).
  new(result)
  let sanitized = stripControlCodes(text)
  result.textPieces = @[sanitized]
  when typeof(style) is string:
    result.style = StyleValue(kind: svkStr, strv: style)
  else:
    result.style = StyleValue(kind: svkStyle, stv: style)
  result.justify = justify
  result.overflow = overflow
  result.noWrap = noWrap
  result.`end` = `end`
  result.tabSize = tabSize
  result.spansData = if spans.isSome: spans.get else: @[]
  result.length = sanitized.len

proc pySlice(s: string, start, finish: int): string =
  ## Python `str[start:end]` slice semantics (clamps negatives via `len+val`,
  ## bounds to `[0,len]`, empty when `start >= end`); used by `divideToSeq` so
  ## the per-line `text[start:end]` matches rich regardless of offset range.
  let n = s.len
  var a = start
  var b = finish
  if a < 0: a = n + a
  if b < 0: b = n + b
  if a < 0: a = 0
  if b < 0: b = 0
  if a > n: a = n
  if b > n: b = n
  if a >= b: result = ""
  else: result = s[a ..< b]

proc initTextFromSV(plain: string, sv: StyleValue,
                   justify: Option[JustifyMethod],
                   overflow: Option[OverflowMethod],
                   noWrap: Option[system.bool], endStr: string,
                   tabSize: Option[int]): Text =
  ## Construct a `Text` from a runtime `StyleValue` (the field type) by
  ## dispatching on its arm to `initText`'s `StyleType` (str|Style) param. Used
  ## wherever a `Text` is built from another `Text`'s `style` field
  ## (`divideToSeq`/`copy`/`blankCopy`).
  case sv.kind
  of svkStr:
    result = initText(plain, style = sv.strv, justify = justify,
                     overflow = overflow, noWrap = noWrap, `end` = endStr,
                     tabSize = tabSize)
  of svkStyle:
    result = initText(plain, style = sv.stv, justify = justify,
                     overflow = overflow, noWrap = noWrap, `end` = endStr,
                     tabSize = tabSize)

proc divideToSeq(self: Text, offsets: openArray[int]): seq[Text] =
  ## rich `Text.divide` core (text.py:1115-1183) returning the divided lines as
  ## `seq[Text]` (the public `divide` returns the provisional `Lines`
  ## placeholder; the logic lives here for reuse by `[]`/`split`/`wrap`/`fit`/
  ## `withIndentGuides`). Binary-searches each span's line range and appends
  ## remapped spans per line.
  if offsets.len == 0:
    return @[self.copy()]
  let plain = self.plain
  let textLength = plain.len
  var divideOffsets: seq[int] = @[0]
  for o in offsets: divideOffsets.add(o)
  divideOffsets.add(textLength)
  var lineRanges: seq[(int, int)] = @[]
  for i in 0 ..< divideOffsets.len - 1:
    lineRanges.add((divideOffsets[i], divideOffsets[i + 1]))
  var newLines: seq[Text] = @[]
  for (s0, e0) in lineRanges:
    newLines.add(initTextFromSV(pySlice(plain, s0, e0), self.style,
                                self.justify, self.overflow, none(system.bool),
                                "\n", none(int)))
  if self.spansData.len == 0:
    return newLines
  let lineCount = lineRanges.len
  for span in self.spansData:
    let spanStart = span.start
    let spanEnd = span.`end`
    let spanStyle = span.style
    var lowerBound = 0
    var upperBound = lineCount
    var startLineNo = (lowerBound + upperBound) div 2
    while true:
      let (ls, le) = lineRanges[startLineNo]
      if spanStart < ls: upperBound = startLineNo - 1
      elif spanStart > le: lowerBound = startLineNo + 1
      else: break
      startLineNo = (lowerBound + upperBound) div 2
    var endLineNo: int
    if spanEnd < lineRanges[startLineNo][1]:
      endLineNo = startLineNo
    else:
      endLineNo = startLineNo
      lowerBound = startLineNo
      upperBound = lineCount
      while true:
        let (ls, le) = lineRanges[endLineNo]
        if spanEnd < ls: upperBound = endLineNo - 1
        elif spanEnd > le: lowerBound = endLineNo + 1
        else: break
        endLineNo = (lowerBound + upperBound) div 2
    for lineNo in startLineNo .. endLineNo:
      let (ls, le) = lineRanges[lineNo]
      let newStart = max(0, spanStart - ls)
      let newEnd = min(spanEnd - ls, le - ls)
      if newEnd > newStart:
        newLines[lineNo].spansData.add(
          Span(start: newStart, `end`: newEnd, style: spanStyle))
  return newLines

proc splitToSeq(self: Text, separator: string, includeSeparator: bool,
                allowBlank: bool): seq[Text] =
  ## rich `Text.split` core (text.py:1079-1104) returning `seq[Text]` (the
  ## public `split` returns the provisional `Lines` placeholder). Splits on
  ## `separator`, optionally keeping the separators, optionally keeping a
  ## trailing blank line.
  assert separator.len > 0, "separator must not be empty"
  let plain = self.plain
  if separator notin plain:
    return @[self.copy()]
  var matchEnds: seq[int] = @[]
  # find each occurrence of `separator` (no `std/re`; manual `find` scan).
  var pos = 0
  while pos <= plain.len - separator.len:
    if plain.continuesWith(separator, pos):
      matchEnds.add(pos + separator.len)
      pos += separator.len
    else:
      inc pos
  var lines: seq[Text]
  if includeSeparator:
    lines = divideToSeq(self, matchEnds)
  else:
    var flat: seq[int] = @[]
    for me in matchEnds:
      flat.add(me - separator.len)  # match start
      flat.add(me)                  # match end
    let divided = divideToSeq(self, flat)
    lines = @[]
    for line in divided:
      if line.plain != separator: lines.add(line)
  if not allowBlank and plain.endsWith(separator):
    if lines.len > 0: discard lines.pop()
  result = lines

proc len*(self: Text): int =
  ## rich text.py:167-168 — `Text.__len__(self) -> int`: `return self._length`
  ## (text.py:168). Overloads `system.len` on the `Text` receiver. port
  ## stub.
  result = self.length

proc bool*(self: Text): bool =
  ## rich text.py:170-171 — `Text.__bool__(self) -> bool`:
  ## `return bool(self._length)` (text.py:171). Overloads `system.bool` on the
  ## `Text` receiver.
  result = self.length != 0

proc `$`*(self: Text): string =
  ## rich text.py:173-174 — `Text.__str__(self) -> str`: `return self.plain`
  ## (text.py:174). Overloads `$` on the `Text` receiver.
  result = self.plain

proc repr*(self: Text): string =
  ## rich text.py:176-177 — `Text.__repr__(self) -> str`:
  ## `return f"text({self.plain!r})"` (text.py:177). Overloads `system.repr` on
  ## the `Text` receiver.
  # Faithful port of the actual rich source (text.py:177):
  # `f"<text {self.plain!r} {self._spans!r} {self.style!r}>"`.
  var spansRepr = "["
  for i, span in self.spansData:
    if i > 0: spansRepr.add(", ")
    spansRepr.add(span.repr)
  spansRepr.add("]")
  let styleRepr = case self.style.kind
    of svkStr: pyReprStr(self.style.strv)
    of svkStyle: pyReprStr($self.style.stv)
  result = "<text " & pyReprStr(self.plain) & " " & spansRepr & " " &
           styleRepr & ">"

proc `+`*[T](self: Text, other: T): Text =
  ## rich text.py:179-184 — `Text.__add__(self, other: Any) -> "Text"`: return
  ## a new `Text` by appending `other` (a `str` or `Text`) to a copy of `self`
  ## via `self.append(other, style=...)` (text.py:181-184). `other: Any` modelled
  ## as a generic `[T]` (NON-NARROWING: any `other` compiles, faithful to
  ## `Any`; the body raises for unsupported `T` in body). Overloads `+` on
  ## the `Text` receiver.
  when typeof(other) is string or typeof(other) is Text:
    result = self.copy()
    discard result.append(other)
  else:
    raise newException(ValueError, "can only append str or Text to Text")

proc `==`*[T](a: Text, b: T): bool =
  ## rich text.py:186-189 — `Text.__eq__(self, other: object) -> bool`: `True`
  ## iff `other` is a `Text` with equal `plain`, `spans`, `justify`, `overflow`
  ## and `end` (text.py:188-189). `other: object` modelled as a generic `[T]`
  ## (NON-NARROWING: any `other` compiles, faithful to `object`; the `discard`
  ## body yields `false` — the `NotImplemented`/`False` outcome for non-`Text`).
  ## Overloads `==` on the `Text` receiver.
  # Faithful to the rich source (text.py:188-189): compares `plain` and
  # `_spans` only (NOT `style`/`justify`/`overflow`/`end`); non-`Text` ⇒ False.
  when typeof(b) is Text:
    if a.plain != b.plain: return false
    if a.spansData.len != b.spansData.len: return false
    for i in 0 ..< a.spansData.len:
      if not spanEqual(a.spansData[i], b.spansData[i]): return false
    result = true
  else:
    result = false

proc contains*[T](self: Text, other: T): bool =
  ## rich text.py:191-196 — `Text.__contains__(self, other: object) -> bool`:
  ## `True` iff `other` (a `str` or `Text`) is contained in `self.plain`
  ## (text.py:193-196). `other: object` modelled as a generic `[T]`
  ## (NON-NARROWING). Backs the `in` operator (`other in self`).
  when typeof(other) is string:
    result = contains(self.plain, other)
  elif typeof(other) is Text:
    result = contains(self.plain, other.plain)
  else:
    result = false

proc `[]`*(self: Text, s: int or HSlice[int, int]): Text =
  ## rich text.py:198-222 — `Text.__getitem__(self, slice: Union[int, slice])
  ## -> "Text"`: return a new `Text` for an `int` offset or a `slice`
  ## (step==1; step!=1 raises `TypeError`, text.py:217). `Union[int, slice]`
  ## modelled as the NON-NARROWING typeclass `int or HSlice[int, int]`
  ## (`HSlice[int, int]` carries start/stop; step is implicitly 1 since
  ## step!=1 raises — the only dropped arm is the always-raising one). port
  ## stub.
  when typeof(s) is int:
    # `get_text_at(offset)` (text.py:200-207): one char + covering spans,
    # `end=""`. Uses the RAW offset in the span check (faithful to rich —
    # negative offsets therefore miss covering spans, as in Python).
    let plain = self.plain
    let length = plain.len
    let idx = if s < 0: length + s else: s
    if idx < 0 or idx >= length:
      raise newException(ValueError, "Text index out of range")
    var spans2: seq[Span] = @[]
    for span in self.spansData:
      if span.`end` > s and s >= span.start:
        spans2.add(Span(start: 0, `end`: 1, style: span.style))
    result = initText(plain[idx .. idx], spans = some(spans2), `end` = "")
  elif typeof(s) is HSlice[int, int]:
    # `slice.indices` then `divide([start, stop])[1]` (text.py:213-216).
    let length = self.plain.len
    var start = s.a
    var stop = s.b
    if start < 0: start = length + start
    if stop < 0: stop = length + stop
    if start < 0: start = 0
    if stop < 0: stop = 0
    if start > length: start = length
    if stop > length: stop = length
    let lines = divideToSeq(self, [start, stop])
    if lines.len >= 2: result = lines[1]
    else: result = initText()
  else:
    result = initText()

proc cellLen*(self: Text): int =
  ## rich text.py:225-227 — `Text.cell_len` property (`@property` text.py:224,
  ## def 225-227): `return cell_len(self.plain)` (text.py:227). Body
  ## needs `cells.cellLen`.
  result = cellLen(self.plain)

proc markup*(self: Text): string =
  ## rich text.py:230-257 — `Text.markup` property (`@property` text.py:229,
  ## def 230-257): get console markup to render this `Text` by escaping
  ## `self.plain` and emitting a `[style]…[/style]` tag per span
  ## (text.py:236-257). Body needs `markup.escape` (text.py:236,
  ## lazy import).
  # `markup.escape` is inlined as `escapeMarkup` (text cannot `import markup` —
  # text↔markup cycle; see file header). Builds the `(offset, closing, style)`
  # event list, stable-sorts by `(offset, closing)` (False<True), and emits
  # escaped plain between events plus `[style]`/`[/style]` tags (text.py:236-257).
  let plain = self.plain
  # `(offset, closing, origIndex, style)` — the `origIndex` tiebreaker makes
  # Nim's (non-stable) `sort` deterministic for equal `(offset, closing)` keys,
  # matching Python's stable `list.sort` (text.py:243).
  var markupSpans: seq[(int, bool, int, StyleValue)] = @[]
  markupSpans.add((0, false, 0, self.style))
  var idx = 1
  for span in self.spansData:
    markupSpans.add((span.start, false, idx, span.style)); inc idx
  for span in self.spansData:
    markupSpans.add((span.`end`, true, idx, span.style)); inc idx
  markupSpans.add((plain.len, true, idx, self.style))
  markupSpans.sort(proc (a, b: (int, bool, int, StyleValue)): int =
    if a[0] != b[0]: result = cmp(a[0], b[0])
    elif a[1] != b[1]: result = cmp(ord(a[1]).int, ord(b[1]).int)
    else: result = cmp(a[2], b[2])
  )
  var output: string = ""
  var position = 0
  for (offset, closing, idx2, style) in markupSpans:
    if offset > position:
      output.add(escapeMarkup(plain[position ..< offset]))
      position = offset
    if styleValueTruthy(style):
      if closing: output.add("[/" & styleValueTag(style) & "]")
      else: output.add("[" & styleValueTag(style) & "]")
  result = output

type
  MarkupTag = tuple[name: string, parameters: Option[string]]
    ## Local mirror of `markup.Tag` (markup.py:19-23). Private to `text.nim`
    ## because `markup.nim` imports `text` (text↔markup cycle), so `text` cannot
    ## reuse `markup.Tag`; a cycle-forced copy (see `escapeMarkup`).
  MarkupTok = tuple[position: int, plainText: Option[string],
                    tag: Option[MarkupTag]]
    ## Local mirror of `markup.ParsedToken` (markup.py:64-99). Private for the
    ## same text↔markup cycle reason as `MarkupTag`.

proc tagStr(t: MarkupTag): string =
  ## Inline of `markup.Tag.str` (markup.py:24-27): `name` if `parameters` is
  ## `None` else `f"{name} {parameters}"`. Yields the `StyleValue(svkStr)` span
  ## style for a stripped open tag.
  if t.parameters.isSome: result = t.name & " " & t.parameters.get
  else: result = t.name

proc tagMarkup(t: MarkupTag): string =
  ## Inline of `markup.Tag.markup` (markup.py:29-33): `f"[{name}]"` /
  ## `f"[{name}={parameters}]"`. Used inside `MarkupError` messages.
  if t.parameters.isSome:
    result = "[" & t.name & "=" & t.parameters.get & "]"
  else:
    result = "[" & t.name & "]"

proc parseMarkupInline(markup: string): seq[MarkupTok] =
  ## Cycle-forced inline of `markup.parse` (markup.py:64-99). `markup.nim`
  ## imports `text` (text↔markup cycle), so `text` cannot `import markup`; this
  ## is a verbatim copy of markup.nim's frozen `parse` (the `fromMarkup` body's
  ## only markup dep), emitting the local `MarkupTok`/`MarkupTag` tokens. See
  ## `escapeMarkup` for the same cycle-forced-inline precedent.
  proc isTagChar(c: char): bool {.inline.} = c in {'a'..'z', '#', '/', '@'}
  let n = markup.len
  var position = 0
  var i = 0
  while i < n:
    let bsStart = i
    var p = i
    while p < n and markup[p] == '\\': inc p
    let escapes = p - bsStart
    var matched = false
    if p < n and markup[p] == '[':
      var j = p + 1
      if j < n and isTagChar(markup[j]):
        inc j
        while j < n and markup[j] != '[' and markup[j] != ']': inc j
        if j < n and markup[j] == ']':
          matched = true
          let mStart = bsStart
          let mEnd = j
          let endExcl = mEnd + 1
          if mStart > position:
            result.add((position, some(markup[position ..< mStart]),
                        none(MarkupTag)))
          var startVar = mStart
          let backslashes = escapes div 2
          let escaped = escapes mod 2
          if escapes > 0:
            if backslashes > 0:
              result.add((mStart, some(repeat("\\", backslashes)),
                          none(MarkupTag)))
              startVar = mStart + backslashes * 2
            if escaped > 0:
              result.add((startVar, some(markup[p .. mEnd]), none(MarkupTag)))
              position = endExcl
              i = endExcl
          if escaped == 0:
            let tagText = markup[p + 1 ..< mEnd]
            let eqPos = tagText.find('=')
            var name = tagText
            var params: Option[string] = none(string)
            if eqPos >= 0:
              name = tagText[0 ..< eqPos]
              params = some(tagText[eqPos + 1 ..< tagText.len])
            result.add((startVar, none(string),
                        some((name: name, parameters: params))))
            position = endExcl
            i = endExcl
    if not matched:
      inc i
  if position < n:
    result.add((position, some(markup[position ..< n]), none(MarkupTag)))

proc renderMarkupInline(markup: string, style: StyleType): Text =
  ## Cycle-forced inline of `markup.render` (markup.py:101-185). `markup.nim`
  ## imports `text` (text↔markup cycle), so `text` cannot `import markup`; this
  ## is a verbatim copy of markup.nim's frozen `render`, building a `Text` whose
  ## plain text is the markup with `[style]…[/style]` tags STRIPPED into
  ## `Span`s — each carrying the style NAME as `StyleValue(svkStr)` (resolved
  ## theme-aware by `Console.getStyle` at render time, e.g.
  ## `[progress.percentage] 50%` → plain ` 50%` +
  ## `Span(0,4,"progress.percentage")`). `emoji` expansion is deferred (see
  ## `fromMarkup`); the `[`-absent fast path returns the text as-is. See
  ## `escapeMarkup` for the same cycle-forced-inline precedent. Raises
  ## `MarkupError` on a syntax error (markup.py:135,141,158,167), matching
  ## `markup.render`.
  if "[" notin markup:
    return initText(markup, style = style)
  let text = initText(style = style)
  var styleStack: seq[(int, MarkupTag)] = @[]
  var spans: seq[Span] = @[]
  for (pos, plainText, tag) in parseMarkupInline(markup):
    if plainText.isSome:
      var pt = plainText.get.replace("\\[", "[")
      # emoji expansion deferred (text↔emoji EmojiVariant-type clash); the
      # `fromMarkup` stub's existing contract — no behaviour change for
      # emoji-free strings.
      discard text.append(pt)
    elif tag.isSome:
      let t = tag.get
      if t.name.startsWith("/"):
        let styleName = t.name[1 ..< t.name.len].strip()
        var startIdx: int
        var openTag: MarkupTag
        var got = false
        if styleName.len > 0:
          let normalized = Style.normalize(styleName)
          for idx in countdown(styleStack.high, 0):
            if styleStack[idx][1].name == normalized:
              let pair = styleStack[idx]
              startIdx = pair[0]
              openTag = pair[1]
              styleStack.del(idx)
              got = true
              break
          if not got:
            raise newException(MarkupError,
              "closing tag '" & tagMarkup(t) & "' at position " & $pos &
              " doesn't match any open tag")
        else:
          if styleStack.len == 0:
            raise newException(MarkupError,
              "closing tag '[/]' at position " & $pos & " has nothing to close")
          let pair = styleStack.pop()
          startIdx = pair[0]
          openTag = pair[1]
          got = true
        if openTag.name.startsWith("@"):
          var metaParams: JsonNode = newJArray()
          if openTag.parameters.isSome:
            let parameters = openTag.parameters.get.strip()
            var handlerName = ""
            var rawParams = "()"
            let lp = parameters.find('(')
            if lp >= 0:
              handlerName = parameters[0 ..< lp]
              rawParams = parameters[lp ..< parameters.len]
            else:
              rawParams = parameters
            if rawParams == "()":
              metaParams = newJArray()
            else:
              try:
                metaParams = parseJson(rawParams)
              except JsonParsingError:
                raise newException(MarkupError,
                  "error parsing " & rawParams & " in " & openTag.parameters.get)
            if handlerName.len > 0:
              let inner = newJArray()
              if metaParams.kind == JArray:
                for e in metaParams.getElems:
                  inner.add(e)
              else:
                inner.add(metaParams)
              let tup = newJArray()
              tup.add(newJString(handlerName))
              tup.add(inner)
              metaParams = tup
          var metaTbl = initTable[string, JsonNode]()
          metaTbl[openTag.name] = metaParams
          spans.add(Span(start: startIdx, `end`: text.len,
                        style: StyleValue(kind: svkStyle,
                                          stv: initStyle(
                                              meta = some(metaTbl)))))
        else:
          spans.add(Span(start: startIdx, `end`: text.len,
                        style: StyleValue(kind: svkStr, strv: tagStr(openTag))))
      else:
        let normalizedTag = (name: Style.normalize(t.name),
                             parameters: t.parameters)
        styleStack.add((text.len, normalizedTag))
  let textLength = text.len
  while styleStack.len > 0:
    let pair = styleStack.pop()
    let st = tagStr(pair[1])
    if st.len > 0:
      spans.add(Span(start: pair[0], `end`: textLength,
                    style: StyleValue(kind: svkStr, strv: st)))
  var sorted = reversed(spans)
  sorted.sort(proc(a, b: Span): int = cmp(a.start, b.start))
  text.setSpans(sorted)
  result = text

proc fromMarkup*(T: typedesc[Text], text: string, style: StyleType = "",
                 emoji: bool = true,
                 emojiVariant: Option[EmojiVariant] = none(EmojiVariant),
                 justify: Option[JustifyMethod] = none(JustifyMethod),
                 overflow: Option[OverflowMethod] = none(OverflowMethod),
                 `end`: string = "\n"): Text =
  ## rich text.py:260-291 — `Text.from_markup(cls, text: str, *, style:
  ## Union[str, Style] = "", emoji: bool = True, emoji_variant:
  ## Optional[EmojiVariant] = None, justify: Optional["JustifyMethod"] = None,
  ## overflow: Optional["OverflowMethod"] = None, end: str = "\n") -> "Text"`
  ## (`@classmethod` text.py:259): create a `Text` from console markup
  ## (text.py:286-291). `style: StyleType = ""` (typeclass default);
  ## `emoji_variant`→`emojiVariant` (`Option[EmojiVariant]`, default `None` via
  ## `none(EmojiVariant)`); `EmojiVariant` is the hosted PUBLIC string-valued
  ## enum (`evEmoji`/`evText`, faithful to `Literal["emoji","text"]`,
  ## emoji.py:13) so `some(evEmoji)` / `some(evText)` / `none(EmojiVariant)`
  ## all compile; `end` backtick-quoted. Body delegates to `markup.render`
  ## (text.py:285, lazy import) then sets `justify`/`overflow`/`end`
  ## (text.py:288-290).
  # Cycle-forced inline of `markup.render` (text.py:285) — `markup.nim` imports
  # `text` (frozen), so `import markup` would form a cycle Nim forbids; the
  # tag-parsing + span-building is inlined as `renderMarkupInline` (see
  # `escapeMarkup` for the same cycle-forced-inline precedent). This STRIPS
  # `[style]…[/style]` tags into `Span`s carrying the style NAME as a
  # `StyleValue(svkStr)` (resolved theme-aware by `Console.getStyle` at render
  # time), so e.g. `[progress.percentage] 50%` → plain ` 50%` +
  # `Span(0,4,"progress.percentage")` — NOT the raw `[progress.percentage] 50%`
  # string the Phase-0 stub returned. `emoji`/`emojiVariant` are accepted but
  # remain deferred (the stub's existing contract; emoji expansion is wired once
  # the text↔emoji EmojiVariant-type clash is reconciled) — no behaviour change
  # for tagless/emoji-free strings.
  result = renderMarkupInline(text, style)
  result.justify = justify
  result.overflow = overflow
  result.`end` = `end`

proc fromAnsi*(T: typedesc[Text], text: string, style: StyleType = "",
               justify: Option[JustifyMethod] = none(JustifyMethod),
               overflow: Option[OverflowMethod] = none(OverflowMethod),
               noWrap: Option[system.bool] = none(system.bool), `end`: string = "\n",
               tabSize: Option[int] = some(8)): Text =
  ## rich text.py:294-329 — `Text.from_ansi(cls, text: str, *, style:
  ## Union[str, Style] = "", justify: Optional["JustifyMethod"] = None,
  ## overflow: Optional["OverflowMethod"] = None, no_wrap: Optional[bool] =
  ## None, end: str = "\n", tab_size: Optional[int] = 8) -> "Text"`
  ## (`@classmethod` text.py:293): create a `Text` from a string with ANSI
  ## escape codes (text.py:322-329). `tab_size: Optional[int] = 8` (default
  ## `8`, an `int` not `None`) → `tabSize: Option[int] = some(8)`. Body
  ## needs `ansi.AnsiDecoder` (text.py:316, lazy import).
  # DEFERRED(text↔ansi import cycle): `ansi.AnsiDecoder` (text.py:316) is
  # unreachable — `ansi.nim` imports `text` (frozen), so `import ansi` cycles.
  # Return a `Text` holding the raw string (ANSI codes un-decoded) with the
  # requested metadata; ANSI decoding is wired once the cycle is broken.
  result = initText(text, style = style, justify = justify,
                   overflow = overflow, noWrap = noWrap, `end` = `end`,
                   tabSize = tabSize)

proc styled*(T: typedesc[Text], text: string, style: StyleType = "",
             justify: Option[JustifyMethod] = none(JustifyMethod),
             overflow: Option[OverflowMethod] = none(OverflowMethod)): Text =
  ## rich text.py:332-354 — `Text.styled(cls, text: str, style: StyleType =
  ## "", *, justify: Optional["JustifyMethod"] = None, overflow:
  ## Optional["OverflowMethod"] = None) -> "Text"` (`@classmethod`
  ## text.py:331): a `Text` with a pre-applied style that is NOT used for
  ## padding when justified (text.py:352-354). `style: StyleType = ""`
  ## (typeclass default).
  result = initText(text, justify = justify, overflow = overflow)
  result.stylize(style)

macro assembleMacro(textObj: typed, parts: varargs[untyped]): untyped =
  ## Body of `Text.assemble` (text.py:395-400): generate
  ## `textObj.append(part)` per `str`/`Text` part, or
  ## `textObj.append(str, style)` for a `(str, StyleType)` tuple part. Mirrors
  ## `style.nim`'s `styleOnMacro` for the heterogeneous `varargs[untyped]`
  ## (Nim `varargs` needs a uniform element type, so a macro dispatches by
  ## AST kind). `append` is forward-declared above so `bindSym` resolves it.
  result = newNimNode(nnkStmtList)
  for p in parts:
    if p.kind == nnkTupleConstr or p.kind == nnkPar:
      result.add(newNimNode(nnkDiscardStmt).add(
        newCall(bindSym("append"), textObj, p[0], p[1])))
    else:
      result.add(newNimNode(nnkDiscardStmt).add(
        newCall(bindSym("append"), textObj, p)))

template assemble*(T: typedesc[Text], parts: varargs[untyped], style: StyleType = "",
                   justify: Option[JustifyMethod] = none(JustifyMethod),
                   overflow: Option[OverflowMethod] = none(OverflowMethod),
                   noWrap: Option[system.bool] = none(system.bool), `end`: string = "\n",
                   tabSize: int = 8,
                   meta: Option[Table[string, JsonNode]] = none(Table[string, JsonNode])): Text =
  ## rich text.py:357-400 — `Text.assemble(cls, *parts: Union[str, "Text",
  ## Tuple[str, StyleType]], style: Union[str, Style] = "", justify:
  ## Optional["JustifyMethod"] = None, overflow: Optional["OverflowMethod"] =
  ## None, no_wrap: Optional[bool] = None, end: str = "\n", tab_size: int = 8,
  ## meta: Optional[Dict[str, Any]] = None) -> "Text"` (`@classmethod`
  ## text.py:356): build a `Text` from a heterogeneous sequence of `str` /
  ## `Text` / `(str, StyleType)` parts (text.py:395-400). The `*parts` is
  ## heterogeneous (a Nim `varargs` requires a uniform element type), so this
  ## is a `template` with `varargs[untyped]` (the same technique as
  ## `style.nim`'s `on` for `**handlers: Any`); the keyword-only `style`/
  ## `justify`/… params follow the varargs. `meta: Optional[Dict[str, Any]]`
  ## → `Option[Table[string, JsonNode]]` (`JsonNode` is the non-narrowing
  ## `Any` handle, per `style.nim`); `tab_size: int = 8` (not `Optional`).
  ## body: `default(Text)`.
  # `initText` is called POSITIONALLY: a template substitutes every occurrence
  # of a param name (including the keyword of a named arg), so
  # `initText(style = style, …)` would expand to `initText("red" = "red", …)`
  # (invalid LHS). Positional args sidestep the LHS-substitution gotcha.
  var assembled = initText("", style, justify, overflow, noWrap, `end`,
                          some(tabSize))
  assembleMacro(assembled, parts)
  if meta.isSome: assembled.applyMeta(meta.get)
  assembled

proc plain*(self: Text): string =
  ## rich text.py:403-407 — `Text.plain` property getter (`@property`
  ## text.py:402, def 403-407): `return "".join(self._text)` — the text as a
  ## single string (text.py:407).
  if self.textPieces.len != 1:
    self.textPieces = @[join(self.textPieces, "")]
  result = self.textPieces[0]

proc setPlain*(self: Text, newText: string) =
  ## rich text.py:410-418 — `Text.plain` property setter (`@plain.setter`
  ## text.py:409, def 410-418): set the text to `new_text`, replacing
  ## `_text`/`_length` and trimming spans (text.py:412-418). Models the
  ## `plain.setter` (named `setPlain`; `new_text`→`newText`).
  if newText != self.plain:
    let sanitized = stripControlCodes(newText)
    self.textPieces = @[sanitized]
    let oldLength = self.length
    self.length = sanitized.len
    if oldLength > self.length:
      self.trimSpans()

proc spans*(self: Text): seq[Span] =
  ## rich text.py:421-423 — `Text.spans` property getter (`@property`
  ## text.py:420, def 421-423): `return self._spans` — a reference to the
  ## internal list of spans (text.py:423).
  result = self.spansData

proc setSpans*(self: Text, spans: openArray[Span]) =
  ## rich text.py:426-428 — `Text.spans` property setter (`@spans.setter`
  ## text.py:425, def 426-428): `self._spans = list(spans)` (text.py:428).
  ## Models the `spans.setter` (named `setSpans`; `spans: List[Span]` modelled
  ## as `openArray[Span]`; accepts `seq`/`array`/`openArray` (materialized
  ## iterables — closure iterators are a conscious body boundary, as for
  ## `segment.nim`).
  self.spansData = @spans

proc blankCopy*(self: Text, plain: string = ""): Text =
  ## rich text.py:430-441 — `Text.blank_copy(self, plain: str = "") -> "Text"`:
  ## return a new `Text` with copied metadata (justify/overflow/no_wrap/end/
  ## tab_size/style) but no string or spans (text.py:436-441).
  result = initTextFromSV(plain, self.style, self.justify, self.overflow,
                         self.noWrap, self.`end`, self.tabSize)

proc copy*(self: Text): Text =
  ## rich text.py:443-455 — `Text.copy(self) -> "Text"`: return a copy of this
  ## instance — a `blank_copy` plus duplicated `_text` and `_spans`
  ## (text.py:449-455).
  result = initTextFromSV(self.plain, self.style, self.justify, self.overflow,
                         self.noWrap, self.`end`, self.tabSize)
  result.spansData = self.spansData

proc stylize*(self: Text, style: StyleType, start: int = 0,
              `end`: Option[int] = none(int)) =
  ## rich text.py:457-481 — `Text.stylize(self, style: Union[str, Style],
  ## start: int = 0, end: Optional[int] = None) -> None`: apply a style to the
  ## text or a portion of it (negative indexing supported, text.py:474-481).
  ## `style: StyleType`; `end: Optional[int]` → `Option[int]` (backtick-quoted
  ## `end`, distinct from the `str` `end` of `__init__`).
  if styleTypeTruthy(style):
    let length = self.length
    var startIdx = start
    var endIdx: int
    if `end`.isSome: endIdx = `end`.get else: endIdx = length
    if startIdx < 0: startIdx = length + startIdx
    if endIdx < 0: endIdx = length + endIdx
    if startIdx >= length or endIdx <= startIdx:
      return
    self.spansData.add(Span(start: startIdx, `end`: min(length, endIdx),
                            style: styleTypeToValue(style)))

proc stylizeBefore*(self: Text, style: StyleType, start: int = 0,
                    `end`: Option[int] = none(int)) =
  ## rich text.py:483-507 — `Text.stylize_before(self, style: Union[str, Style],
  ## start: int = 0, end: Optional[int] = None) -> None`: like `stylize` but
  ## the style is applied BEFORE other styles already present
  ## (text.py:500-507).
  if styleTypeTruthy(style):
    let length = self.length
    var startIdx = start
    var endIdx: int
    if `end`.isSome: endIdx = `end`.get else: endIdx = length
    if startIdx < 0: startIdx = length + startIdx
    if endIdx < 0: endIdx = length + endIdx
    if startIdx >= length or endIdx <= startIdx:
      return
    self.spansData.insert(Span(start: startIdx, `end`: min(length, endIdx),
                               style: styleTypeToValue(style)), 0)

proc applyMeta*(self: Text, meta: Table[string, JsonNode], start: int = 0,
                `end`: Option[int] = none(int)) =
  ## rich text.py:509-521 — `Text.apply_meta(self, meta: Dict[str, Any],
  ## start: int = 0, end: Optional[int] = None) -> None`: apply metadata to the
  ## text or a portion of it (text.py:515-521). `meta: Dict[str, Any]` →
  ## `Table[string, JsonNode]` (`JsonNode` is the non-narrowing `Any` handle,
  ## per `style.nim`).
  let style = Style.fromMeta(some(meta))
  self.stylize(style, start = start, `end` = `end`)

proc toJsonNode(x: auto): JsonNode =
  ## Wrap an `on` handler value as a `JsonNode` (the Nim handle for `Any`).
  ## Mirrors `style.nim`'s private `toJsonNode` (unreachable cross-module; the
  ## single-arg `%` is std/json).
  result = %x

proc mergeMeta(m: var Table[string, JsonNode],
               meta: Table[string, JsonNode]) =
  ## Merge a positional `meta` `Table` into `m`. Mirrors `style.nim`'s private
  ## `mergeMeta` (unreachable cross-module).
  for k, v in meta: m[k] = v

proc mergeMeta(m: var Table[string, JsonNode],
               meta: Option[Table[string, JsonNode]]) =
  if meta.isSome:
    for k, v in meta.get: m[k] = v

proc setMetaKey(m: var Table[string, JsonNode], key: string, val: JsonNode) =
  ## Insert a meta key/value into `m`. Bound by `onMacro` (via `bindSym`) so the
  ## `[]=` resolution happens in `text.nim`'s scope (which `import tables`),
  ## not at the macro call site (which may not import `tables`). Mirrors
  ## `style.nim`'s private `setMetaKey`.

proc newStyleFromMeta(meta: Option[Table[string, JsonNode]]): Style =
  ## Private wrapper so `onMacro` can build a `Style.fromMeta` without passing a
  ## `typedesc[Style]` call arg (mirrors `style.nim`'s private wrapper).
  result = Style.fromMeta(meta)

macro onMacro(selfObj: typed, handlers: varargs[untyped]): Text =
  ## Body of `Text.on` (text.py:539-541): build a `meta` table from the
  ## positional `meta` (optional, index 0) and the `key = value` handlers
  ## (prefixed `@`), then `selfObj.stylize(Style.fromMeta(meta))` and return
  ## `selfObj`. Mirrors `style.nim`'s `styleOnMacro`; local helpers keep the
  ## macro self-contained (`style.nim`'s private helpers aren't exported).
  result = newNimNode(nnkStmtListExpr)
  let mSym = genSym(nskVar, "m")
  result.add(newVarStmt(mSym, newCall(newNimNode(nnkBracketExpr).add(
    bindSym("initTable"), bindSym("string"), bindSym("JsonNode")))))
  let h = handlers
  for i in 0 ..< h.len:
    let node = h[i]
    if node.kind == nnkExprEqExpr:
      let keyStr = newStrLitNode("@" & $node[0])
      result.add(newCall(bindSym("setMetaKey"), mSym, keyStr,
                         newCall(bindSym("toJsonNode"), node[1])))
    elif i == 0:
      result.add(newCall(bindSym("mergeMeta", brForceOpen), mSym, node))
  result.add(newCall(bindSym("stylize"), selfObj,
                     newCall(bindSym("newStyleFromMeta"),
                             newCall(bindSym("some"), mSym))))
  result.add(selfObj)

template on*(self: Text, handlers: varargs[untyped]): Text =
  ## rich text.py:523-541 — `Text.on(self, meta: Optional[Dict[str, Any]] =
  ## None, **handlers: Any) -> "Text"`: apply event handlers (used by the
  ## Textual project), prefixing handler keys with `@` (text.py:539-541).
  ## Python's `**handlers: Any` accepts arbitrary keyword args; Nim has no
  ## `**kwargs`, so this is a `template` with `varargs[untyped]` (the same
  ## technique as `style.nim`'s `on`): each `name = value` is captured as an
  ## `nnkExprColonExpr` AST node, and the positional `meta` dict is captured
  ## among the same varargs and distinguished in the Body. NON-NARROWING
  ## (every keyword handler compiles; there is no compile-time-illegal variant,
  ## matching Python's dynamic `Any`). body: `default(Text)`.
  bind onMacro
  onMacro(self, handlers)

proc removeSuffix*(self: Text, suffix: string) =
  ## rich text.py:543-550 — `Text.remove_suffix(self, suffix: str) -> None`:
  ## remove `suffix` from the end of the text if present (text.py:545-550).
  if self.plain.endsWith(suffix):
    self.rightCrop(suffix.len)

proc getStyleAtOffset*(self: Text, console: ConsoleHandle, offset: int): Style =
  ## rich text.py:552-570 — `Text.get_style_at_offset(self, console: "Console",
  ## offset: int) -> Style`: the style of the character at `offset`
  ## (negative indexing supported, text.py:562-570). `Console` is the richbase
  ## `ConsoleHandle` placeholder.
  # `console.get_style` is approximated by `getStyleLocal` (the `Console` is the
  # opaque `ConsoleHandle` placeholder, no theme registry); see that helper's
  # caveat on themed-name resolution (text.py:564-567).
  var off = offset
  if off < 0:
    off = self.length + off
  result = getStyleLocal(self.style)
  for span in self.spansData:
    if span.`end` > off and off >= span.start:
      result = result + some(getStyleLocal(span.style))

proc extendStyle*(self: Text, spaces: int) =
  ## rich text.py:572-591 — `Text.extend_style(self, spaces: int) -> None`:
  ## extend the text by `spaces` spaces with the same style as the last
  ## character (text.py:577-591).
  if spaces <= 0:
    return
  let spansList = self.spansData
  let newSpaces = repeat(' ', spaces)
  if spansList.len > 0:
    let endOffset = self.length
    var newSpans: seq[Span] = @[]
    for span in spansList:
      if span.`end` >= endOffset:
        newSpans.add(span.extend(spaces))
      else:
        newSpans.add(span)
    self.spansData = newSpans
    self.textPieces.add(newSpaces)
    self.length += spaces
  else:
    self.setPlain(self.plain & newSpaces)

proc highlightRegex*(self: Text, reHighlight: string or RePattern,
                     style: StyleOpt or GetStyleCallable = default(StyleOpt),
                     stylePrefix: string = ""): int =
  ## rich text.py:593-631 — `Text.highlight_regex(self, re_highlight:
  ## Union[Pattern[str], str], style: Optional[Union[GetStyleCallable,
  ## StyleType]] = None, *, style_prefix: str = "") -> int`: highlight text
  ## with a regex, translating group names to styles; returns the number of
  ## matches (text.py:625-631). `re_highlight: Union[Pattern[str], str]` → the
  ## NON-NARROWING typeclass `string or RePattern` (`RePattern` is the PUBLIC
  ## `re.Pattern[str]` placeholder, so `highlightRegex(RePattern(), …)` and
  ## `highlightRegex("foo", …)` both compile — both arms of the union). `style: Optional[Union[GetStyleCallable,
  ## StyleType]]` → the NON-NARROWING typeclass `StyleOpt or GetStyleCallable`
  ## (default `default(StyleOpt)` = `None`): a `str`/`Style` converts to
  ## `StyleOpt` via the existing `toStyleOpt*` converters, a `GetStyleCallable`
  ## satisfies the callable arm, `None` is the default. `style_prefix`→
  ## `stylePrefix`. Body: real PCRE-backed `re.finditer` (see body).
  # Body — PCRE-backed `re.finditer` over `self.plain` (text.py:609-629).
  # `re.compile` (str arm) and the compiled-pattern arm both resolve to a
  # source pattern string (`RePattern.pattern` holds the source; the
  # PROVISIONAL handle is replaced by a real compiled-regex type later).
  # Python default `re.compile` flags (Py3 Unicode; no MULTILINE/DOTALL/
  # IGNORECASE) → PCRE `UTF8|UCP` only (NOT `pcre_wrap.defaultFlags`, which
  # adds MULTILINE for Pygments).
  result = 0
  when typeof(reHighlight) is string:
    let pattern = reHighlight
  else:
    let pattern = reHighlight.pattern
  let plain = self.plain
  let cr = pcre_wrap.compileRegex(pattern, pcre_wrap.rfUtf8 or pcre_wrap.rfUcp)
  # Enumerate named groups via the PCRE name table (`INFO_NAMECOUNT`/
  # `INFO_NAMETABLE`/`INFO_NAMEENTRYSIZE`). PCRE sorts the table ALPHABETICALLY
  # by name, but Python `match.groupdict().keys()` is pattern-DEFINITION order
  # == group-number order, so sort entries by number to match the iteration
  # order. Each entry's first two bytes are the group number BIG-ENDIAN
  # (most-significant byte first); then the NUL-terminated name.
  var named: seq[(int, string)] = @[]
  var nameCount: cint = 0
  discard pcre.fullinfo(cr.code, nil, pcre.INFO_NAMECOUNT.cint, addr nameCount)
  if nameCount > 0:
    var nameTable: pointer = nil
    discard pcre.fullinfo(cr.code, nil, pcre.INFO_NAMETABLE.cint, addr nameTable)
    var nameEntrySize: cint = 0
    discard pcre.fullinfo(cr.code, nil, pcre.INFO_NAMEENTRYSIZE.cint,
                          addr nameEntrySize)
    if nameEntrySize > 0 and not nameTable.isNil:
      let base0 = cast[int](nameTable)
      for i in 0 ..< int(nameCount):
        let entry = base0 + i * int(nameEntrySize)
        let p = cast[ptr UncheckedArray[uint8]](entry)
        let num = (int(p[0]) shl 8) or int(p[1])
        named.add((num, $cast[cstring](addr p[2])))
      named.sort(proc(a, b: (int, string)): int = cmp(a[0], b[0]))
  # `re.finditer` via ANCHORED `pcre.exec` — CPython SRE scanner semantics
  # (bpo-1647489), match-for-match. Every attempt is anchored at `pos` (one
  # match attempt per subject position, exactly as `sre_search` scans forward).
  # After an empty match (`mStart == mEnd`), `mustAdvance` makes the NEXT
  # attempt at the SAME `pos` require a non-empty match there via
  # `NOTEMPTY_ATSTART | NOTEMPTY`, surfacing a non-empty alternative at that
  # position (e.g. `(?=)|a` over `ba` reports the empty `(?=)` at 1, then the
  # retry yields `a` at (1,2) → four matches, not three). Unanchored `exec`
  # would instead JUMP to a later non-empty match and drop the intervening
  # empty matches, so anchoring is essential. If an anchored attempt fails
  # (no match at `pos`, or the non-empty retry fails), advance exactly ONE
  # Unicode code point — never a raw byte — so multi-byte UTF-8 subjects never
  # land mid-character and trigger `ERROR_BADUTF8_OFFSET` (-11) (e.g. `(?=)`
  # over `éa` yields three empty matches, not one + BADUTF8). Terminal empty
  # matches at `pos == n` are retained because the loop condition is `pos <= n`.
  proc utf8Next(s: string, p: int): int {.inline.} =
    # Next UTF-8 code-point boundary at/after byte offset `p` (1–4 bytes per
    # lead byte; continuation/invalid lead bytes step one byte as a fallback).
    if p >= s.len: return p + 1
    let b = ord(s[p])
    result = p + (if b <= 0x7F: 1
                  elif (b shr 5) == 0b00000110: 2
                  elif (b shr 4) == 0b00001110: 3
                  elif (b shr 3) == 0b00011110: 4
                  else: 1)
  var ovec = newSeq[int32]((cr.groupCount + 1) * 3)
  var pos = 0
  var mustAdvance = false
  let n = plain.len
  while pos <= n:
    let opts = if mustAdvance: (pcre.NOTEMPTY or pcre.NOTEMPTY_ATSTART or
                               pcre.ANCHORED).cint
               else: pcre.ANCHORED.cint
    let rc = pcre.exec(cr.code, cr.extra, plain.cstring, n.cint, pos.cint, opts,
                       cast[ptr cint](addr ovec[0]), ovec.len.cint)
    if rc < 0:
      pos = utf8Next(plain, pos)     # no (non-empty) match at pos: step one char
      mustAdvance = false            # an empty match at the new pos is allowed
      continue
    let mStart = int(ovec[0])
    let mEnd = int(ovec[1])
    inc result                       # count += 1 (text.py:625)
    # Optional whole-match style (text.py:614-620): `if style:` is truthy; the
    # callable arm is always truthy, then `match_style is not None` filters the
    # resolved return. Appended BEFORE the named-group spans (overlap → the
    # named-group style wins, matching Python's append order).
    when typeof(style) is StyleOpt:
      if styleOptTruthy(style) and mEnd > mStart:
        self.spansData.add(Span(start: mStart, `end`: mEnd,
                               style: styleOptToValue(style)))
    else:
      if not style.isNil:
        let resolved = style(plain[mStart ..< mEnd])
        if resolved.kind != sokNone and mEnd > mStart:
          self.spansData.add(Span(start: mStart, `end`: mEnd,
                                 style: styleOptToValue(resolved)))
    # Named-group spans in `groupdict().keys()` order (text.py:626-629): only
    # participating (`start != -1`) AND non-empty (`end > start`) captures.
    for (num, name) in named:
      let gStart = int(ovec[2 * num])
      let gEnd = int(ovec[2 * num + 1])
      if gStart != -1 and gEnd > gStart:
        self.spansData.add(Span(start: gStart, `end`: gEnd,
                               style: StyleValue(kind: svkStr,
                                                 strv: stylePrefix & name)))
    mustAdvance = (mStart == mEnd)
    pos = mEnd

proc highlightWords*(self: Text, words: openArray[string], style: StyleType,
                     caseSensitive: bool = true): int =
  ## rich text.py:633-660 — `Text.highlight_words(self, words: Iterable[str],
  ## style: Union[str, Style], *, case_sensitive: bool = True) -> int`:
  ## highlight `words` with `style`; returns the number of words highlighted
  ## (text.py:655-660). `words: Iterable[str]` → `openArray[string]`
  ## (accepts `seq`/`array`/`openArray` — materialized iterables; closure
  ## iterators are a conscious body boundary, as for `segment.nim`);
  ## `style: StyleType`; `case_sensitive`→`caseSensitive`.
  # Python builds `"|".join(re.escape(word) for word in words)` and runs
  # `re.finditer` (text.py:640-654). Without `std/re`, the alternation is
  # evaluated as a leftmost, first-alternative-wins, non-overlapping literal
  # scan (equivalent to `re.escape`+`|` since the words are matched as
  # literals; `re.IGNORECASE` ⇒ ASCII case-fold via `toLowerAscii`, a minor
  # deviation from Python's Unicode case folding). Empty words are skipped
  # (a zero-width search word would yield degenerate zero-width spans).
  result = 0
  let plain = self.plain
  let n = plain.len
  let sv = styleTypeToValue(style)
  var i = 0
  while i < n:
    var matched = false
    for word in words:
      let wl = word.len
      if wl == 0:
        continue
      if i + wl > n:
        continue
      var eq = true
      if caseSensitive:
        for k in 0 ..< wl:
          if plain[i + k] != word[k]:
            eq = false
            break
      else:
        for k in 0 ..< wl:
          if toLowerAscii(plain[i + k]) != toLowerAscii(word[k]):
            eq = false
            break
      if eq:
        self.spansData.add(Span(start: i, `end`: i + wl, style: sv))
        result += 1
        i += wl
        matched = true
        break
    if not matched:
      inc i

proc rstrip*(self: Text) =
  ## rich text.py:662-664 — `Text.rstrip(self) -> None`: strip whitespace from
  ## the end of the text (text.py:664).
  # `strutils.strip` is qualified & trailing-only: the local
  # `rstrip*(self: Text)` proc would otherwise shadow a same-named helper, and
  # `strutils` has no `rstrip` (Python `str.rstrip()` ⇒ trailing `strip`).
  self.setPlain(strutils.strip(self.plain, leading = false, trailing = true))

proc rstripEnd*(self: Text, size: int) =
  ## rich text.py:666-678 — `Text.rstrip_end(self, size: int) -> None`: remove
  ## whitespace beyond `size` cells at the end of the text (text.py:673-678).
  ## Body needs `reWhitespace` (text.py:670).
  # Python `_re_whitespace = re.compile(r"\s+$")` (text.py:39) is anchored
  # to the END (`\s+$`): `_re_whitespace.search(self.plain)` (text.py:675)
  # finds the TRAILING whitespace run — the run of `\s` chars ending at the
  # end of the string — NOT the first whitespace run anywhere. Counting the
  # trailing whitespace run from the end yields the same `group(0)` length as
  # `\s+$` (the `$`-before-final-`\n` subtlety only affects WHERE `$` sits,
  # not the count, since a trailing `\n` is itself `\s`). `isWrapWs` is the
  # inlined ASCII `\s` set; Python `\s` also covers Unicode whitespace
  # (\u00A0, \u2028, ...) — a minor deviation for trailing Unicode space.
  let textLength = self.length
  if textLength > size:
    let excess = textLength - size
    let plain = self.plain
    let n = plain.len
    var endIdx = n
    while endIdx > 0 and isWrapWs(plain[endIdx - 1]):
      dec endIdx
    let wsCount = n - endIdx
    if wsCount > 0:
      self.rightCrop(min(wsCount, excess))

proc setLength*(self: Text, newLength: int) =
  ## rich text.py:680-687 — `Text.set_length(self, new_length: int) -> None`:
  ## set a new length for the text, clipping or padding as required
  ## (text.py:682-687). `new_length`→`newLength`.
  let length = self.length
  if length != newLength:
    if length < newLength:
      self.padRight(newLength - length)
    else:
      self.rightCrop(length - newLength)

method renderConsole*(self: Text, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich text.py:689-705 — `Text.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> Iterable[Segment]`: render the text to
  ## segments, honouring justify/overflow/wrap (text.py:691-705). The
  ## `Console`/`ConsoleOptions` are the richbase placeholders; the renderable
  ## convention (`renderConsole(self, console: ConsoleHandle, options:
  ## ConsoleOptions): RenderResult`) is documented in `richbase.nim`.
  ## `Iterable[Segment]` → `RenderResult`.
  ##
  ## Faithful port (text.py:691-705): resolve `tab_size`/`justify`/`overflow`,
  ## `no_wrap=pick_bool(self.no_wrap, options.no_wrap, False)`, then
  ## `lines = self.wrap(...)`, `all_lines = Text("\n").join(lines)`, and
  ## `yield from all_lines.render(console, end=self.end)`. The wrap is the
  ## private `wrapToSeq` — the faithful `Text.wrap` body (text.py:1201-1250)
  ## returning `seq[Text]`, used because the public `wrap` returns the
  ## provisional `Lines` placeholder that `text.nim` cannot construct (the
  ## text↔containers import cycle; `wrapToSeq` IS `Text.wrap`'s logic). `join`
  ## re-glues the wrapped lines with `\n` separators; `render` emits the
  ## styled content segments plus the unstyled trailing `end`.
  ##
  ## Fitting single-line text is byte-identical to the former fitting branch:
  ## `wrapToSeq` returns a single line and `justifySeq` pads it exactly like
  ## `Text.align`/`Lines.justify` did (the divide/justify/truncate no-ops for
  ## text that fits). Multi-line, over-width, tab, `no_wrap`, overflow and
  ## `full` justify now follow Rich 15.0.0 byte-for-byte.
  ##
  ## Faithful to text.py:692 — `tab_size = console.tab_size if self.tab_size is
  ## None else self.tab_size`: an explicit `Text.tab_size` (`some`) wins; an
  ## unset (`none`) inherits the real Console tab size via `console.getTabSize`
  ## (`console_api` dispatch → real `Console.tabSize`, default `8`). When the
  ## Console handle is nil (no Console, e.g. Rule/nested callers) the literal
  ## `8` fallback mirrors Rich's default `tab_size` (console.py:637).
  let tabSize = if self.tabSize.isSome: self.tabSize.get
                elif console.isNil: 8
                else: console.getTabSize()
  let justify = if self.justify.isSome: self.justify.get
                elif options.justify.isSome: options.justify.get
                else: DEFAULT_JUSTIFY
  let overflow = if self.overflow.isSome: self.overflow.get
                 elif options.overflow.isSome: options.overflow.get
                 else: DEFAULT_OVERFLOW
  let noWrapArg = pickBool3(self.noWrap, options.noWrap, false)
  let lines = self.wrapToSeq(console, options.maxWidth, justify, overflow,
                            tabSize, noWrapArg)
  let allLines = initText("\n").join(lines)
  result = allLines.render(console, self.`end`)

proc richMeasure*(self: Text, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich text.py:707-717 — `Text.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: measure the text — minimum
  ## and maximum width (text.py:713-717). The richbase `ConsoleHandle`/
  ## `ConsoleOptions` placeholders; `Measurement` from `measure.nim`. port
  ## stub.
  let text = self.plain
  let lines = text.splitLines()
  var maxWidth = 0
  for line in lines:
    let w = cellLen(line)
    if w > maxWidth:
      maxWidth = w
  let wordsList = text.splitWhitespace()
  var minWidth = maxWidth
  for word in wordsList:
    let w = cellLen(word)
    if w > minWidth:
      minWidth = w
  result = Measurement(minimum: minWidth, maximum: maxWidth)

proc render*(self: Text, console: ConsoleHandle, `end`: string = ""): RenderResult =
  ## rich text.py:719-776 — `Text.render(self, console: "Console", end: str =
  ## "") -> Iterable["Segment"]`: render the text as segments (the low-level
  ## render used by `__rich_console__`), emitting the final `end` character
  ## (text.py:751-776). `end: str = ""` (backtick-quoted). `Iterable[Segment]`
  ## → `RenderResult`.
  # Faithful port (text.py:751-776): if there are no spans, yield `Segment(text)`
  # (plus `Segment(end)` when `end` is non-empty). Otherwise build the
  # `(offset, leaving, style_id)` span event list — `(0, False, 0)`,
  # `(span.start, False, index)` per span (1-indexed), `(span.end, True, index)`
  # per span, `(len(text), True, 0)` — stable-sort by `(offset, leaving)`
  # (entering before leaving at the same offset), and walk consecutive event
  # pairs maintaining a style-id stack, yielding
  # `Segment(text[offset:next_offset], current_style)` per non-empty gap;
  # finally `yield Segment(end)` if `end` is non-empty.
  # `partial(console.get_style, default=Style.null())` (text.py:731) —
  # styles resolve via the real `Console.getStyle` dispatch (`resolveStyle`),
  # so theme names (`table.title`/`table.caption`/…) resolve through the
  # Console theme registry when rendered via a real `Console`, while a
  # placeholder `ConsoleHandle` falls back to the `console_api.getStyle` base
  # (`Style.parse`/`.copy()`, null on miss) — identical to the former
  # `getStyleLocal` for parseable styles/empty strings. `Style.combine`
  # (text.py:752-756) combines the sorted stack; the per-`styles`
  # `style_cache` (text.py:741) is a pure perf optimization, omitted here
  # (output identical).
  result = @[]
  let text = self.plain
  if self.spansData.len == 0:
    # Fast path: no spans → one Segment with the Text's base style
    # (rich text.py:751-776 — `__rich_console__`'s wrap+join turns the base
    # style into a span, so the styled `Segment(text, base)` matches Rich's
    # spans-path output; the Nim `renderConsole` mirrors this by padding the
    # Text, so the base style IS applied to the text here). The trailing
    # `end` is emitted UNSTYLED (`_Segment(end)`, text.py:734/776) — Rich never
    # styles the trailing newline, so neither does this path.
    let baseStyle = resolveStyle(console, self.style)
    let styleOpt = if baseStyle.isNil: none(StyleRef)
                   else: some(StyleRef(baseStyle))
    result.addSegment(initSegment(text, styleOpt))
    if `end`.len > 0:
      result.addSegment(initSegment(`end`, none(StyleRef)))
    return
  var styleMap: seq[Style] = newSeq[Style](self.spansData.len + 1)
  styleMap[0] = resolveStyle(console, self.style)
  for i, span in self.spansData:
    styleMap[i + 1] = resolveStyle(console, span.style)
  type SpanEvent = tuple[offset: int, leaving: bool, styleId: int]
  var events: seq[SpanEvent] = @[]
  events.add((0, false, 0))
  for i, span in self.spansData:
    events.add((span.start, false, i + 1))
  for i, span in self.spansData:
    events.add((span.`end`, true, i + 1))
  events.add((text.len, true, 0))
  events.sort(proc (a, b: SpanEvent): int =
    if a.offset != b.offset: result = cmp(a.offset, b.offset)
    else: result = cmp(ord(a.leaving).int, ord(b.leaving).int))
  var stack: seq[int] = @[]
  for i in 0 ..< events.high:
    let (offset, leaving, styleId) = events[i]
    let nextOffset = events[i + 1].offset
    if leaving:
      var j = 0
      while j < stack.len and stack[j] != styleId: inc j
      if j < stack.len: stack.delete(j)
    else:
      stack.add(styleId)
    if nextOffset > offset:
      var styles: seq[Style] = @[]
      for sid in sorted(stack):
        styles.add(styleMap[sid])
      let currentStyle = Style.combine(styles)
      result.addSegment(initSegment(text[offset ..< nextOffset],
                                     some(StyleRef(currentStyle))))
  if `end`.len > 0:
    result.addSegment(initSegment(`end`))

proc join*(self: Text, lines: openArray[Text]): Text =
  ## rich text.py:778-815 — `Text.join(self, lines: Iterable["Text"]) -> "Text"`:
  ## join an iterable of `Text` instances with `self` as the separator
  ## (text.py:803-815). `lines: Iterable["Text"]` → `openArray[Text]`
  ## (accepts `seq`/`array`/`openArray` — materialized iterables; closure
  ## iterators are a conscious body boundary, as for `segment.nim`).
  # `loop_last` (text.py:805-809) is inlined: if the separator `self` is
  # non-empty, `self` is yielded between consecutive `lines` (not after the
  # last); else the `lines` are yielded as-is (text.py:805-809). Each yielded
  # text's `_text` pieces are extended, its base style (if truthy) becomes a
  # span `[offset, offset+len)`, and its spans are offset by `offset`.
  result = self.blankCopy()
  let selfPlain = self.plain
  var offset = 0
  if selfPlain.len > 0:
    for i in 0 ..< lines.len:
      let line = lines[i]
      result.textPieces.add(line.textPieces)
      if styleValueTruthy(line.style):
        result.spansData.add(Span(start: offset, `end`: offset + line.length,
                                  style: line.style))
      for s in line.spansData:
        result.spansData.add(Span(start: offset + s.start,
                                 `end`: offset + s.`end`, style: s.style))
      offset += line.length
      if i != lines.len - 1:
        result.textPieces.add(self.textPieces)
        if styleValueTruthy(self.style):
          result.spansData.add(Span(start: offset, `end`: offset + self.length,
                                    style: self.style))
        for s in self.spansData:
          result.spansData.add(Span(start: offset + s.start,
                                   `end`: offset + s.`end`, style: s.style))
        offset += self.length
  else:
    for line in lines:
      result.textPieces.add(line.textPieces)
      if styleValueTruthy(line.style):
        result.spansData.add(Span(start: offset, `end`: offset + line.length,
                                  style: line.style))
      for s in line.spansData:
        result.spansData.add(Span(start: offset + s.start,
                                 `end`: offset + s.`end`, style: s.style))
      offset += line.length
  result.length = offset

proc expandTabs*(self: Text, tabSize: Option[int] = none(int)) =
  ## rich text.py:817-857 — `Text.expand_tabs(self, tab_size: Optional[int] = None) -> None`:
  ## convert tabs to spaces (default `8`, or `None` to use `console.tab_size`,
  ## text.py:820-857). `tab_size: Optional[int] = None` → `tabSize: Option[int]`
  ## (default `None`).
  # Faithful port (text.py:820-857) via the private `splitToSeq` (the public
  # `split` returns the provisional `Lines` placeholder) + the implemented
  # `join`: each line is split on `\t` (separators kept); a part ending in `\t`
  # has its trailing tab replaced by a single space, the cell position
  # advanced, and `tab_size - (cell_position % tab_size)` extra spaces added
  # (via `extendStyle`, which styles them with the last char's style) when the
  # position is not on a tab stop. The divided parts are rejoined with
  # `initText("").join`, preserving spans through the divide/join round-trip
  # (text.py:836-857).
  if '\t' notin self.plain:
    return
  var ts = tabSize
  if ts.isNone: ts = self.tabSize
  if ts.isNone: ts = some(8)
  let tsVal = ts.get
  var newText: seq[Text] = @[]
  for line in splitToSeq(self, "\n", true, false):
    if '\t' notin line.plain:
      newText.add(line)
    else:
      var cellPosition = 0
      for part in splitToSeq(line, "\t", true, false):
        if part.plain.endsWith("\t"):
          let last = part.textPieces[part.textPieces.len - 1]
          part.textPieces[part.textPieces.len - 1] = last[0 ..< ^1] & " "
          cellPosition += part.cellLen()
          let tabRemainder = cellPosition mod tsVal
          if tabRemainder != 0:
            let spaces = tsVal - tabRemainder
            part.extendStyle(spaces)
            cellPosition += spaces
        else:
          cellPosition += part.cellLen()
        newText.add(part)
  let result = initText("").join(newText)
  self.textPieces = @[result.plain]
  self.length = self.plain.len
  self.spansData = result.spansData

proc truncate*(self: Text, maxWidth: int,
               overflow: Option[OverflowMethod] = none(OverflowMethod),
               pad: bool = false) =
  ## rich text.py:859-884 — `Text.truncate(self, max_width: int, *, overflow:
  ## Optional["OverflowMethod"] = None, pad: bool = False) -> None`: truncate the
  ## text if longer than `max_width` (crop/fold/ellipsis; optionally pad,
  ## text.py:875-884). `max_width`→`maxWidth`; keyword-only after `max_width`
  ## (Python `*`, text.py:861).
  var ov = overflow
  if ov.isNone: ov = self.overflow
  let ovVal = if ov.isSome: ov.get else: DEFAULT_OVERFLOW
  if ovVal != omIgnore:
    let length = cellLen(self.plain)
    if length > maxWidth:
      if ovVal == omEllipsis:
        self.setPlain(setCellSize(self.plain, maxWidth - 1) & "\u2026")
      else:
        self.setPlain(setCellSize(self.plain, maxWidth))
    if pad and length < maxWidth:
      let spaces = maxWidth - length
      self.textPieces = @[self.plain & repeat(' ', spaces)]
      self.length = self.plain.len

proc trimSpans*(self: Text) =
  ## rich text.py:886-898 — `Text._trim_spans(self) -> None`: remove or modify
  ## any spans that extend past the end of the text (text.py:888-898). Mirrors
  ## the private `_trim_spans` (exported as `trimSpans`).
  let maxOffset = self.plain.len
  var newSpans: seq[Span] = @[]
  for span in self.spansData:
    if span.start < maxOffset:
      if span.`end` < maxOffset:
        newSpans.add(span)
      else:
        newSpans.add(Span(start: span.start, `end`: min(maxOffset, span.`end`),
                          style: span.style))
  self.spansData = newSpans

proc pad*(self: Text, count: int, character: string = " ") =
  ## rich text.py:900-915 — `Text.pad(self, count: int, character: str = " ") ->
  ## None`: pad left and right with `count` copies of `character` (length 1,
  ## text.py:907-915).
  assert character.len == 1, "Character must be a string of length 1"
  if count != 0:
    let padChars = repeat(character[0], count)
    self.setPlain(padChars & self.plain & padChars)
    var newSpans: seq[Span] = @[]
    for span in self.spansData:
      newSpans.add(Span(start: span.start + count, `end`: span.`end` + count,
                        style: span.style))
    self.spansData = newSpans

proc padLeft*(self: Text, count: int, character: string = " ") =
  ## rich text.py:917-931 — `Text.pad_left(self, count: int, character: str =
  ## " ") -> None`: pad the left with `character` (text.py:924-931). port
  ## stub.
  assert character.len == 1, "Character must be a string of length 1"
  if count != 0:
    self.setPlain(repeat(character[0], count) & self.plain)
    var newSpans: seq[Span] = @[]
    for span in self.spansData:
      newSpans.add(Span(start: span.start + count, `end`: span.`end` + count,
                        style: span.style))
    self.spansData = newSpans

proc padRight*(self: Text, count: int, character: string = " ") =
  ## rich text.py:933-942 — `Text.pad_right(self, count: int, character: str =
  ## " ") -> None`: pad the right with `character` (text.py:939-942). port
  ## stub.
  assert character.len == 1, "Character must be a string of length 1"
  if count != 0:
    self.setPlain(self.plain & repeat(character[0], count))

proc align*(self: Text, align: AlignMethod, width: int, character: string = " ") =
  ## rich text.py:944-962 — `Text.align(self, align: AlignMethod, width: int,
  ## character: str = " ") -> None`: align the text to `width` using `character`
  ## to pad (text.py:950-962). `align: AlignMethod` is the hosted `AlignMethod`
  ## enum (see file header); `align` is a `Union[…]`-free faithful `AlignMethod`.
  self.truncate(width)
  let excessSpace = width - cellLen(self.plain)
  if excessSpace > 0:
    case align
    of amLeft:
      self.padRight(excessSpace, character)
    of amCenter:
      let left = excessSpace div 2
      self.padLeft(left, character)
      self.padRight(excessSpace - left, character)
    of amRight:
      self.padLeft(excessSpace, character)

proc append*(self: Text, text: Text or string,
             style: StyleOpt = default(StyleOpt)): Text =
  ## rich text.py:964-1006 — `Text.append(self, text: Union["Text", str],
  ## style: Optional[Union[str, "Style"]] = None) -> "Text"`: add `text` with
  ## an optional `style`, returning `self` for chaining (text.py:997-1006).
  ## `text: Union["Text", str]` → the NON-NARROWING typeclass `Text or string`;
  ## `style: Optional[Union[str, Style]]` → `StyleOpt` (the existing
  ## `Optional[StyleType]` handle, default `None` via `default(StyleOpt)`), so
  ## `append(t, "x")`, `append(t, "x", "bold")` (str), `append(t, "x", aStyle)`
  ## (Style), `append(t, anotherText)` all compile.
  # Dispatches on the compile-time arm of the `Text or string` typeclass
  # (text.py:985-1006). The `str` arm sanitizes, appends one `_text` piece, and
  # adds a span when the style is truthy (`if style:` — empty `str` is falsy,
  # matched by `styleOptTruthy`). The `Text` arm raises if a style was supplied
  # (`style is not None` ⇒ `kind != sokNone`), then appends the plain, the base
  # style span (if truthy), and the offset-adjusted spans.
  when typeof(text) is string:
    if text.len > 0:
      let sanitized = stripControlCodes(text)
      self.textPieces.add(sanitized)
      let offset = self.length
      let textLength = sanitized.len
      if styleOptTruthy(style):
        self.spansData.add(Span(start: offset, `end`: offset + textLength,
                                style: styleOptToValue(style)))
      self.length += textLength
  else:
    if text.length > 0:
      if style.kind != sokNone:
        raise newException(ValueError,
          "style must not be set when appending Text instance")
      let textLength = self.length
      if styleValueTruthy(text.style):
        self.spansData.add(Span(start: textLength, `end`: textLength + text.length,
                                style: text.style))
      self.textPieces.add(text.plain)
      # `text._spans.copy()` (text.py:1004): iterate a SNAPSHOT — if `text is
      # self`, appending to `self.spansData` (== `text.spansData`) mid-iter trips
      # Nim's `items` assertion (`len(a)==L` ⇒ AssertionDefect). `let srcSpans
      # = text.spansData` is a value copy (Nim seqs copy on bind), matching
      # Python's `.copy()` taken after the base-style span above.
      let srcSpans = text.spansData
      for s in srcSpans:
        self.spansData.add(Span(start: s.start + textLength,
                                `end`: s.`end` + textLength, style: s.style))
      self.length += text.length
  result = self

proc appendText*(self: Text, text: Text): Text =
  ## rich text.py:1008-1028 — `Text.append_text(self, text: "Text") -> "Text"`:
  ## append another `Text` instance (more performant than `append`, only works
  ## for `Text`), returning `self` for chaining (text.py:1024-1028). port
  ## stub.
  let textLength = self.length
  if styleValueTruthy(text.style):
    self.spansData.add(Span(start: textLength, `end`: textLength + text.length,
                            style: text.style))
  self.textPieces.add(text.plain)
  # `text._spans.copy()` (text.py:1023): iterate a snapshot (see `append`'s
  # Text arm) — guards `self.appendText(self)` where `text is self`.
  let srcSpans = text.spansData
  for s in srcSpans:
    self.spansData.add(Span(start: s.start + textLength,
                            `end`: s.`end` + textLength, style: s.style))
  self.length += text.length
  result = self

proc appendTokens*(self: Text, tokens: openArray[(string, StyleOpt)]): Text =
  ## rich text.py:1030-1052 — `Text.append_tokens(self, tokens: Iterable[Tuple[str,
  ## Optional[StyleType]]]) -> "Text"`: append an iterable of `(str, style)`
  ## tokens, returning `self` for chaining (text.py:1048-1052).
  ## `Iterable[Tuple[str, Optional[StyleType]]]` → `openArray[(string,
  ## StyleOpt)]` (`Optional[StyleType]` → `StyleOpt`; accepts `seq`/`array`/
  ## `openArray` — materialized iterables; closure iterators are a conscious
  ## body boundary, as for `segment.nim`).
  var offset = self.length
  for (content, style) in tokens:
    let sanitized = stripControlCodes(content)
    self.textPieces.add(sanitized)
    if styleOptTruthy(style):
      self.spansData.add(Span(start: offset, `end`: offset + sanitized.len,
                              style: styleOptToValue(style)))
    offset += sanitized.len
  self.length = offset
  result = self

proc copyStyles*(self: Text, text: Text) =
  ## rich text.py:1054-1060 — `Text.copy_styles(self, text: "Text") -> None`:
  ## copy styles from another `Text` (which must be the same length,
  ## text.py:1057-1060).
  self.spansData.add(text.spansData)

proc split*(self: Text, separator: string = "\n",
            includeSeparator: bool = false, allowBlank: bool = false): Lines =
  ## rich text.py:1062-1104 — `Text.split(self, separator: str = "\n", *,
  ## include_separator: bool = False, allow_blank: bool = False) -> Lines`:
  ## split the rich text into lines preserving styles (text.py:1079-1104).
  ## Returns `Lines` (the PUBLIC provisional `containers.Lines` forward
  ## handle — see file header). `include_separator`→`includeSeparator`,
  ## `allow_blank`→`allowBlank`; keyword-only after `separator` (Python `*`,
  ## text.py:1064). Body needs `Lines` (containers.nim).
  # DEFERRED(`Lines` construction): the real `split` logic (text.py:1079-1104)
  # lives in `splitToSeq` (returning `seq[Text]`), faithfully ported (a literal
  # separator scan — `re.escape`+`finditer` reduce to literal search since the
  # separator is matched as-is). The public `split` must return `Lines`
  # (`containers.Lines`), but `text.nim` cannot `import containers` (the
  # text↔containers import cycle), so the placeholder `Lines` (declared above)
  # is returned empty; the `Lines`-wrapping is wired once the cycle is broken.
  # `splitToSeq` is exercised directly by `expandTabs`/`withIndentGuides`.
  result = default(Lines)

proc divide*(self: Text, offsets: openArray[int]): Lines =
  ## rich text.py:1106-1183 — `Text.divide(self, offsets: Iterable[int]) ->
  ## Lines`: divide the text into a `Lines` container at the given offsets,
  ## preserving styles (text.py:1115-1183). `offsets: Iterable[int]` →
  ## `openArray[int]` (accepts `seq`/`array`/`openArray` — materialized
  ## iterables; closure iterators are a conscious body boundary, as for
  ## `segment.nim`). Returns `Lines` (PUBLIC provisional forward handle). port
  ## stub.
  # DEFERRED(`Lines` construction): the real `divide` logic (text.py:1115-1183)
  # lives in `divideToSeq` (returning `seq[Text]`, with the per-span binary
  # search over line ranges). The public `divide` must return `Lines`
  # (`containers.Lines`), but `text.nim` cannot `import containers` (the
  # text↔containers import cycle), so the placeholder `Lines` is returned empty;
  # the `Lines`-wrapping is wired once the cycle is broken. `divideToSeq` is
  # exercised directly by `[]`/`splitToSeq`/`withIndentGuides`.
  result = default(Lines)

proc rightCrop*(self: Text, amount: int = 1) =
  ## rich text.py:1185-1199 — `Text.right_crop(self, amount: int = 1) -> None`:
  ## remove `amount` characters from the end of the text (text.py:1188-1199).
  ## (Distinct from `Span.right_crop`; overload on the `Text` receiver.) Phase
  ## 0 stub.
  let p = self.plain
  let maxOffset = p.len - amount
  var newSpans: seq[Span] = @[]
  for span in self.spansData:
    if span.start < maxOffset:
      if span.`end` < maxOffset:
        newSpans.add(span)
      else:
        newSpans.add(Span(start: span.start, `end`: min(maxOffset, span.`end`),
                          style: span.style))
  self.spansData = newSpans
  # `self.plain[:-amount]` — Python's negative slice: `amount==0` ⇒ `[:0]`=""
  # (a known footgun, replicated); `amount>=len` ⇒ ""; else the first
  # `len-amount` bytes.
  let endIdx = if amount == 0: 0 else: max(0, p.len - amount)
  self.textPieces = @[p[0 ..< endIdx]]
  self.length -= amount

proc wrap*(self: Text, console: ConsoleHandle, width: int,
           justify: Option[JustifyMethod] = none(JustifyMethod),
           overflow: Option[OverflowMethod] = none(OverflowMethod),
           tabSize: int = 8, noWrap: Option[system.bool] = none(system.bool)): Lines =
  ## rich text.py:1201-1250 — `Text.wrap(self, console: "Console", width: int,
  ## *, justify: Optional["JustifyMethod"] = None, overflow:
  ## Optional["OverflowMethod"] = None, tab_size: int = 8, no_wrap:
  ## Optional[bool] = None) -> Lines`: word-wrap the text to `width` cells
  ## (text.py:1225-1250). `console` is the richbase `ConsoleHandle`
  ## placeholder; `tab_size: int = 8` (not `Optional`); keyword-only after
  ## `width` (Python `*`, text.py:1203). Returns `Lines` (PUBLIC provisional
  ## forward handle). Body needs `divide_line`/`cells`/`_wrap`. port
  ## stub.
  # DEFERRED(`Lines` construction): the faithful port (text.py:1225-1250) splits
  # on `\n` (via `splitToSeq`), expands tabs, divides each line at
  # `divideLine` offsets, `rstrip_end`s, justifies (`Lines.justify`), and
  # truncates. It must return `Lines` (`containers.Lines`), but `text.nim`
  # cannot `import containers` (the text↔containers cycle) and `Lines.justify`
  # is itself deferred (containers.nim), so the placeholder `Lines` is returned
  # empty; the `divideLine`/`splitToSeq` building blocks are implemented
  # (`divideLine` helper, `splitToSeq`) for the future wiring.
  result = default(Lines)

proc fit*(self: Text, width: int): Lines =
  ## rich text.py:1252-1266 — `Text.fit(self, width: int) -> Lines`: fit the
  ## text into `width` by chopping into lines (text.py:1257-1266). Returns
  ## `Lines` (PUBLIC provisional forward handle).
  # DEFERRED(`Lines` construction): the faithful port (text.py:1257-1266) splits
  # on `\n`, `set_length(width)`s each line, and appends to a `Lines`. It must
  # return `Lines` (`containers.Lines`), but `text.nim` cannot `import
  # containers` (the text↔containers cycle), so the placeholder `Lines` is
  # returned empty; the `splitToSeq`/`setLength` building blocks are
  # implemented for the future wiring.
  result = default(Lines)

proc detectIndentation*(self: Text): int =
  ## rich text.py:1268-1287 — `Text.detect_indentation(self) -> int`: auto-detect
  ## the indentation (number of leading spaces) of the code in the text
  ## (text.py:1275-1287).
  # `re.finditer(r"^(*)(.*)$", plain, re.MULTILINE)` (text.py:1275) collects
  # the leading-space count of each line; `reduce(gcd, [c for c in counts if
  # not c % 2]) or 1` (text.py:1280-1283) returns the gcd of the even-divisible
  # counts, or `1` if empty/all-zero. Inlined without `std/re` (leading spaces
  # are ASCII; `splitLines` + a leading-space count).
  let plain = self.plain
  var divs: seq[int] = @[]
  for line in plain.splitLines():
    var cnt = 0
    for c in line:
      if c == ' ': inc cnt else: break
    if cnt mod 2 == 0:
      divs.add(cnt)
  if divs.len == 0:
    return 1
  var g = divs[0]
  for i in 1 ..< divs.len:
    g = gcd(g, divs[i])
  result = if g == 0: 1 else: g

proc withIndentGuides*(self: Text, indentSize: Option[int] = none(int),
                      character: string = "\u2502",
                      style: StyleType = "dim green"): Text =
  ## rich text.py:1289-1335 — `Text.with_indent_guides(self, indent_size:
  ## Optional[int] = None, *, character: str = "\u2502", style: StyleType =
  ## "dim green") -> "Text"`: add indent guide lines to the text (text.py:1325-1335).
  ## `indent_size: Optional[int] = None` → `indentSize: Option[int]`; `character`
  ## defaults to `"│"` (U+2502, written `"\u2502"`); `style: StyleType = "dim
  ## green"` (typeclass default); keyword-only after `character` (Python `*`,
  ## text.py:1291).
  # Faithful port (text.py:1295-1335) via the private `splitToSeq` (the public
  # `split` returns the provisional `Lines` placeholder). `re_indent =
  # r"^(*)(.*)$"` is inlined: per line the leading-space count is the indent;
  # a line with no non-space content (empty/all-spaces) is blank. The indent is
  # replaced 1:1 (same length) with `indentLine*fullIndents + spaces*remainder`
  # and stylized with `style`; blank lines accumulate and are emitted (as
  # `Text(indent, style)`) before the next non-blank line, trailing blanks as
  # `Text("", style)`. Reassembled with `blankCopy("\n").join` (text.py:1329-1335).
  let indentSizeVal = if indentSize.isSome: indentSize.get else: self.detectIndentation()
  let text = self.copy()
  text.expandTabs()
  let indentLine = character & repeat(' ', indentSizeVal - 1)
  var newLines: seq[Text] = @[]
  var blankLines = 0
  for line in splitToSeq(text, "\n", false, true):
    let lp = line.plain
    var indentCount = 0
    for c in lp:
      if c == ' ': inc indentCount else: break
    let hasContent = indentCount < lp.len
    if not hasContent:
      blankLines += 1
      continue
    let fullIndents = indentCount div indentSizeVal
    let remainingSpace = indentCount mod indentSizeVal
    var newIndent = ""
    for _ in 1 .. fullIndents:
      newIndent.add(indentLine)
    newIndent.add(repeat(' ', remainingSpace))
    line.setPlain(newIndent & lp[indentCount .. ^1])
    line.stylize(style, 0, some(newIndent.len))
    if blankLines > 0:
      let blankText = initText(newIndent, style = style)
      for _ in 1 .. blankLines:
        newLines.add(blankText)
      blankLines = 0
    newLines.add(line)
  if blankLines > 0:
    let emptyText = initText("", style = style)
    for _ in 1 .. blankLines:
      newLines.add(emptyText)
  result = text.blankCopy("\n").join(newLines)

# ---------------------------------------------------------------------------
# port layout — `Text.wrap` body + `Lines.justify` (text.py:1201-1250,
# containers.py:111-167). `text.nim` cannot `import containers` (the text↔
# containers cycle), so `wrap`'s logic is ported as the private `wrapToSeq`
# (returning `seq[Text]`, used by `renderConsole`) and `Lines.justify` as the
# private `justifySeq` (operating on `var seq[Text]`). The public `wrap` keeps
# returning the provisional `Lines` placeholder (pre-existing DEFERRED, NOT
# broadened); the faithful behaviour lives in `wrapToSeq`/`justifySeq`.
# ---------------------------------------------------------------------------

proc pickBool3(a, b: Option[system.bool], c: bool): bool =
  ## rich `_pick.pick_bool(a, b, c)` (first non-`None`), inlined because
  ## `table.nim`'s `pickBool` is unreachable from `text.nim` (text↔table cycle).
  ## `a`/`b` are `Optional[bool]` (`Option[system.bool]`), `c` a fallback `bool`.
  if a.isSome: result = a.get
  elif b.isSome: result = b.get
  else: result = c

proc justifySeq(lines: var seq[Text], console: ConsoleHandle, width: int,
               justify: JustifyMethod, overflow: OverflowMethod) =
  ## rich containers.py:111-167 — `Lines.justify(self, console, width, justify,
  ## overflow)` operating on a `var seq[Text]` (the `Lines._lines` stand-in).
  ## Faithful port of all four branches: `left` (truncate+pad), `center`
  ## (rstrip+truncate+padLeft+padRight), `right` (rstrip+truncate+padLeft),
  ## `full` (word redistribution). `default` is a no-op (Python's `if/elif` chain
  ## has no `default` arm). The `full` branch uses `Text.get_style_at_offset`
  ## for the inter-word space style (containers.py:148-150); that proc resolves
  ## via `getStyleLocal` (`Style.parse`, null for `""`) — identical to Rich's
  ## `console.get_style("", default="")` → `Style.null()` for the empty/base
  ## case, and to `Style.parse` for literal styles (bold/red/…). Theme-name
  ## styles in `full` would need the theme-aware render path; the four Table
  ## goldens use `center` (not `full`), so this is the documented residual.
  case justify
  of jmDefault:
    discard
  of jmLeft:
    for l in lines.mitems:
      l.truncate(width, overflow = some(overflow), pad = true)
  of jmCenter:
    for l in lines.mitems:
      l.rstrip()
      l.truncate(width, overflow = some(overflow))
      l.padLeft((width - cellLen(l.plain)) div 2)
      l.padRight(width - cellLen(l.plain))
  of jmRight:
    for l in lines.mitems:
      l.rstrip()
      l.truncate(width, overflow = some(overflow))
      l.padLeft(width - cellLen(l.plain))
  of jmFull:
    let n = lines.len
    for i in 0 ..< n:
      if i == n - 1:
        break
      let line = lines[i]
      let words = line.splitToSeq(" ", includeSeparator = false,
                                   allowBlank = false)
      var wordsSize = 0
      for w in words:
        wordsSize += cellLen(w.plain)
      var numSpaces = words.len - 1
      var spaces = newSeqWith(max(0, numSpaces), 1)
      var index = 0
      if spaces.len > 0:
        while wordsSize + numSpaces < width:
          spaces[spaces.len - index - 1] += 1
          numSpaces += 1
          index = (index + 1) mod spaces.len
      var tokens: seq[Text] = @[]
      for j in 0 ..< words.len:
        tokens.add(words[j])
        if j < spaces.len:
          let st = words[j].getStyleAtOffset(console, -1)
          let nst = if j + 1 < words.len: words[j + 1].getStyleAtOffset(console, 0)
                    else: Style.null()
          if st == nst:
            tokens.add(initText(repeat(' ', spaces[j]), style = st))
          else:
            tokens.add(initTextFromSV(repeat(' ', spaces[j]), line.style,
                                      line.justify, line.overflow,
                                      none(system.bool), "\n", none(int)))
      lines[i] = initText("").join(tokens)

proc wrapToSeq*(self: Text, console: ConsoleHandle, width: int,
               justify: JustifyMethod, overflow: OverflowMethod,
               tabSize: int, noWrap: bool): seq[Text] =
  ## rich text.py:1201-1250 — `Text.wrap` body returning `seq[Text]` (the public
  ## `wrap` returns the provisional `Lines` placeholder; this IS `wrap`'s logic,
  ## used by `renderConsole`). `justify`/`overflow` are already resolved by the
  ## caller (`__rich_console__`); `noWrap` is `pick_bool(self.no_wrap,
  ## options.no_wrap, False)` (the `no_wrap` arg). Faithful: `wrap_justify`/
  ## `wrap_overflow` = the resolved values; `no_wrap = noWrap or overflow ==
  ## "ignore"`; split on `\n` (`allow_blank=True`), expand tabs, divide (or
  ## single-line for `no_wrap`), `rstrip_end`, `justify` (`justifySeq`),
  ## `truncate`. The `no_wrap` + `overflow=="ignore"` arm appends the line
  ## untouched (skips justify+truncate, text.py:1238-1240).
  let wrapJustify = justify
  let wrapOverflow = overflow
  let effectiveNoWrap = noWrap or overflow == omIgnore
  result = @[]
  for line in self.splitToSeq("\n", includeSeparator = false,
                              allowBlank = true):
    if '\t' in line.plain:
      line.expandTabs(some(tabSize))
    var newLines: seq[Text]
    if effectiveNoWrap:
      if overflow == omIgnore:
        result.add(line)
        continue
      newLines = @[line]
    else:
      let offsets = divideLine(line.plain, width,
                               fold = wrapOverflow == omFold)
      newLines = line.divideToSeq(offsets)
      for l in newLines.mitems:
        l.rstripEnd(width)
    justifySeq(newLines, console, width, wrapJustify, wrapOverflow)
    for l in newLines.mitems:
      l.truncate(width, overflow = some(wrapOverflow))
    result.add(newLines)
