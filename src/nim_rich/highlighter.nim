## Port of `rich.highlighter` (rich/highlighter.py).
##
## Highlighter classes that apply styling to `rich.text.Text` in place:
## `Highlighter` (ABC, highlighter.py:17), `NullHighlighter` (highlighter.py:50),
## `RegexHighlighter` (highlighter.py:61), `ReprHighlighter` (highlighter.py:80),
## `JSONHighlighter` (highlighter.py:106), `ISO8601Highlighter`
## (highlighter.py:143). `console`/`pretty`/`json`/`syntax` consume
## `ReprHighlighter`/`JSONHighlighter` (`console.py` default highlighter,
## `json.py:11`, `syntax.py`). `highlighter.py` has no `__all__`; all
## non-underscore top-level names are public, while `_combine_regex`
## (highlighter.py:8) is private.
##
## Import graph (rich/highlighter.py:1-5): `import re`, `from abc import ABC,
## abstractmethod`, `from typing import ClassVar, Sequence, Union`, and the one
## rich sibling import `from .text import Span, Text` (highlighter.py:5). `re`/
## `ABC`/`abstractmethod` are body-only (body). Nim needs only `text` for
## `Text`/`TextType` (`Span` is used in the `JSONHighlighter.highlight` body,
## body).
##
## ClassVar modelling (critical). `RegexHighlighter.highlights:
## ClassVar[Sequence[str]]` (highlighter.py:64) and `base_style: ClassVar[str]`
## (highlighter.py:65), plus the per-subclass overrides (`ReprHighlighter.
## base_style = "repr."`, highlighter.py:83; `JSONHighlighter.base_style =
## "json."`, highlighter.py:113; `ISO8601Highlighter.base_style = "iso8601."`,
## highlighter.py:148), are **class-level** attributes (not instance fields). Nim
## forbids redefining an inherited field in a subclass, so modelling them as
## instance fields would not compile. The faithful Nim model is therefore
## **module-level `const`/`let` per class** (a class attribute IS a module-level
## value), with the real default values where they are simple literals
## (`base_style`, `JSON_STR`, `JSON_WHITESPACE`) and stubbed `@[]` for the regex
## `highlights` lists (their real contents are body). This keeps the
## subclass chain free of field redefinition and matches Python's ClassVar
## semantics exactly.
##
## wiring (this file): `import text` (Text, TextType). `Highlighter(ABC)`
## → `ref object of RootObj` (Nim has no abstract classes; the `@abstractmethod
## highlight` is a stub proc). `__call__` → `call`; `Union[str, Text]` → `TextType`
## (`string or Text`, from text.nim). The four `highlight` overloads are
## distinguished by receiver type (Nim overload, not dynamic dispatch — body
## concern). Proc bodies are `discard` (port).

import text   # Text, TextType (highlighter.py:5: `from .text import Span, Text`).
import style  # StyleValue, svkStr + `toStyleValue` converter (key-scan `Span`).
import pcre   # PCRE 8.x C API — `exec` (the JSON key-scan finditer).
import nimgments/pcre_wrap # `compileRegex`/`CompiledRegex` (UTF8|UCP compile).

type
  Highlighter* = ref object of RootObj
    ## rich highlighter.py:17-47 — `class Highlighter(ABC)`: abstract base class
    ## for highlighters. `ABC` → `ref object of RootObj` (Nim has no abstract
    ## classes; `highlight` is the `@abstractmethod` stub proc). Callable via
    ## `__call__` → `call`.

  NullHighlighter* = ref object of Highlighter
    ## rich highlighter.py:50-58 — `class NullHighlighter(Highlighter)`: a
    ## highlighter that does nothing (used to disable highlighting entirely).

  RegexHighlighter* = ref object of Highlighter
    ## rich highlighter.py:61-77 — `class RegexHighlighter(Highlighter)`: applies
    ## highlighting from a list of regexes. Its `highlights: ClassVar`/`base_style:
    ## ClassVar` are class-level → module-level `const`/`let` (see
    ## `regexHighlighterBaseStyle`/`regexHighlighterHighlights` below), not
    ## instance fields, so the subclass chain has no field redefinition.

  ReprHighlighter* = ref object of RegexHighlighter
    ## rich highlighter.py:80-103 — `class ReprHighlighter(RegexHighlighter)`:
    ## highlights the text typically produced by `__repr__` (`base_style =
    ## "repr."` → `reprHighlighterBaseStyle`).

  JSONHighlighter* = ref object of RegexHighlighter
    ## rich highlighter.py:106-140 — `class JSONHighlighter(RegexHighlighter)`:
    ## highlights JSON (`base_style = "json."` → `jsonHighlighterBaseStyle`;
    ## `JSON_STR` → `jsonHighlighterJsonStr`; `JSON_WHITESPACE` →
    ## `jsonHighlighterJsonWhitespace`; overrides `highlight` to also mark keys).

  ISO8601Highlighter* = ref object of RegexHighlighter
    ## rich highlighter.py:143-199 — `class ISO8601Highlighter(RegexHighlighter)`:
    ## highlights ISO8601 date/time strings (`base_style = "iso8601."` →
    ## `iso8601HighlighterBaseStyle`).

const
  regexHighlighterBaseStyle* = ""
    ## rich highlighter.py:65 — `RegexHighlighter.base_style: ClassVar[str] = ""`.
  reprHighlighterBaseStyle* = "repr."
    ## rich highlighter.py:83 — `ReprHighlighter.base_style = "repr."`.
  jsonHighlighterBaseStyle* = "json."
    ## rich highlighter.py:113 — `JSONHighlighter.base_style: ClassVar[str] = "json."`.
  iso8601HighlighterBaseStyle* = "iso8601."
    ## rich highlighter.py:148 — `ISO8601Highlighter.base_style = "iso8601."`.
  jsonHighlighterJsonStr* = """(?<![\\\w])(?P<str>b?\".*?(?<!\\)\")"""
    ## rich highlighter.py:110 — `JSONHighlighter.JSON_STR`: regex capturing the
    ## start/end of JSON strings (handles escaped quotes). Stored triple-quoted
    ## so backslashes are literal, matching Python's raw string `r"…"` (a Nim
    ## `r"…"` would terminate on the embedded `\"`).
  jsonHighlighterJsonWhitespace*: set[char] = {' ', '\n', '\r', '\t'}
    ## rich highlighter.py:111 — `JSONHighlighter.JSON_WHITESPACE = {" ", "\n",
    ## "\r", "\t"}`: whitespace chars skipped when locating JSON keys.
  jsonBraceRe = """(?P<brace>[\{\[\(\)\]\}])"""
    ## rich highlighter.py:115 — sub-pattern of `JSONHighlighter.highlights[0]`
    ## (`_combine_regex` arg 1): the `brace` named group.
  jsonBoolsRe = """\b(?P<bool_true>true)\b|\b(?P<bool_false>false)\b|\b(?P<null>null)\b"""
    ## rich highlighter.py:116 — sub-pattern (arg 2): the `bool_true`/
    ## `bool_false`/`null` named groups.
  jsonNumberRe = """(?P<number>(?<!\w)\-?[0-9]+\.?[0-9]*(e[\-\+]?\d+?)?\b|0x[0-9a-fA-F]*)"""
    ## rich highlighter.py:118 — sub-pattern (arg 3): the `number` named group.

  # ── ReprHighlighter.highlights — the four regex entries (highlighter.py:84-103).
  # Python stores `highlights` as a 4-element list: entries 1-3 are standalone
  # `r"…"` regexes; entry 4 is `_combine_regex(...)` — the `|`-OR-join of 13
  # sub-patterns (highlighter.py:88-102). Each Python `r"…"` raw string is stored
  # here triple-quoted so backslashes (`\w`, `\d`, `\.`, `(?<!\w)`, `(?<!\\)`) and
  # embedded quotes (`"`, the `\"\"\"` triple-double-quote run in the `str`
  # pattern) are literal — a Nim `r"…"` would terminate on an embedded `"`, and a
  # regular `"…"` would process `\` escapes. The 23 named groups across the four
  # entries — tag_start/tag_name/tag_contents/tag_end, attrib_name/attrib_value,
  # brace, ipv4/ipv6/eui64/eui48/uuid/call/bool_true/bool_false/none/ellipsis/
  # number_complex/number/path/filename/str/url — match Rich 15.0.0 exactly. Entry 3
  # is rebuilt at init via `combineRegex(...)` (mirroring `_combine_regex`), see
  # `reprHighlighterHighlights` below. These 16 consts are private: only the
  # assembled `reprHighlighterHighlights` list is the public carrier.
  reprTagRe = """(?P<tag_start><)(?P<tag_name>[-\w.:|]*)(?P<tag_contents>[\w\W]*)(?P<tag_end>>)"""
    ## rich highlighter.py:85 — `ReprHighlighter.highlights[0]`: the tag regex
    ## (`tag_start`/`tag_name`/`tag_contents`/`tag_end` named groups).
  reprAttribRe = """(?P<attrib_name>[\w_]{1,50})=(?P<attrib_value>"?[\w_]+"?)?"""
    ## rich highlighter.py:86 — `ReprHighlighter.highlights[1]`: the attribute
    ## regex (`attrib_name`/`attrib_value` named groups; the embedded `"` chars
    ## are literal inside a triple-quoted string).
  reprBraceRe = """(?P<brace>[][{}()])"""
    ## rich highlighter.py:87 — `ReprHighlighter.highlights[2]`: the brace regex
    ## (`brace` named group; `[][{}()]` matches any of `[]{}()`).
  reprIpv4Re = """(?P<ipv4>[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})"""
    ## rich highlighter.py:89 — sub-pattern of `highlights[3]` (`_combine_regex`
    ## arg 1): the `ipv4` named group.
  reprIpv6Re = """(?P<ipv6>([A-Fa-f0-9]{1,4}::?){1,7}[A-Fa-f0-9]{1,4})"""
    ## rich highlighter.py:90 — sub-pattern of `highlights[3]` (arg 2): the
    ## `ipv6` named group.
  reprEui64Re = """(?P<eui64>(?:[0-9A-Fa-f]{1,2}-){7}[0-9A-Fa-f]{1,2}|(?:[0-9A-Fa-f]{1,2}:){7}[0-9A-Fa-f]{1,2}|(?:[0-9A-Fa-f]{4}\.){3}[0-9A-Fa-f]{4})"""
    ## rich highlighter.py:91 — sub-pattern of `highlights[3]` (arg 3): the
    ## `eui64` named group (three alternations).
  reprEui48Re = """(?P<eui48>(?:[0-9A-Fa-f]{1,2}-){5}[0-9A-Fa-f]{1,2}|(?:[0-9A-Fa-f]{1,2}:){5}[0-9A-Fa-f]{1,2}|(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4})"""
    ## rich highlighter.py:92 — sub-pattern of `highlights[3]` (arg 4): the
    ## `eui48` named group (three alternations).
  reprUuidRe = """(?P<uuid>[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})"""
    ## rich highlighter.py:93 — sub-pattern of `highlights[3]` (arg 5): the
    ## `uuid` named group.
  reprCallRe = """(?P<call>[\w.]*?)\("""
    ## rich highlighter.py:94 — sub-pattern of `highlights[3]` (arg 6): the
    ## `call` named group (`\(` matches a literal `(`).
  reprBoolRe = """\b(?P<bool_true>True)\b|\b(?P<bool_false>False)\b|\b(?P<none>None)\b"""
    ## rich highlighter.py:95 — sub-pattern of `highlights[3]` (arg 7): the
    ## `bool_true`/`bool_false`/`none` named groups (top-level `|` alternation,
    ## preserved as peer alternatives by `combineRegex`).
  reprEllipsisRe = """(?P<ellipsis>\.\.\.)"""
    ## rich highlighter.py:96 — sub-pattern of `highlights[3]` (arg 8): the
    ## `ellipsis` named group.
  reprNumberComplexRe = """(?P<number_complex>(?<!\w)(?:\-?[0-9]+\.?[0-9]*(?:e[-+]?\d+?)?)(?:[-+](?:[0-9]+\.?[0-9]*(?:e[-+]?\d+)?))?j)"""
    ## rich highlighter.py:97 — sub-pattern of `highlights[3]` (arg 9): the
    ## `number_complex` named group.
  reprNumberRe = """(?P<number>(?<!\w)\-?[0-9]+\.?[0-9]*(e[-+]?\d+?)?\b|0x[0-9a-fA-F]*)"""
    ## rich highlighter.py:98 — sub-pattern of `highlights[3]` (arg 10): the
    ## `number` named group.
  reprPathRe = """(?P<path>\B(/[-\w._+]+)*\/)(?P<filename>[-\w._+]*)?"""
    ## rich highlighter.py:99 — sub-pattern of `highlights[3]` (arg 11): the
    ## `path`/`filename` named groups.
  reprStrRe = """(?<![\\\w])(?P<str>b?'''.*?(?<!\\)'''|b?'.*?(?<!\\)'|b?\"\"\".*?(?<!\\)\"\"\"|b?\".*?(?<!\\)\")"""
    ## rich highlighter.py:100 — sub-pattern of `highlights[3]` (arg 12): the
    ## `str` named group (triple-single `'''`, single `'`, triple-double, and
    ## double `"` string alternatives). The backslash-quote runs are literal
    ## backslash+quote pairs with no three consecutive `"`, so the triple-quoted
    ## literal does not terminate early.
  reprUrlRe = """(?P<url>(file|https|http|ws|wss)://[-0-9a-zA-Z$_+!`(),.?/;:&=%#~@]*)"""
    ## rich highlighter.py:101 — sub-pattern of `highlights[3]` (arg 13): the
    ## `url` named group (the backtick and `$` are literal in a Nim string).

# Forward declaration — `reprHighlighterHighlights` (built in the `let` block
# below) calls `combineRegex` to OR-join entry 3, mirroring Python's
# `_combine_regex(...)` (highlighter.py:88-102). The full body follows below; a
# forward declaration is needed so the `let` initializer sees `combineRegex`
# before its textual definition (Nim requires a proc visible before use in a
# module-level initializer).
proc combineRegex(regexes: varargs[string]): string

let
  regexHighlighterHighlights*: seq[string] = @[]
    ## rich highlighter.py:64 — `RegexHighlighter.highlights: ClassVar[Sequence[str]]
    ## = []`. Stub `@[]` (the empty default; unchanged in Python).
  reprHighlighterHighlights*: seq[string] = @[
    reprTagRe, reprAttribRe, reprBraceRe,
    combineRegex(reprIpv4Re, reprIpv6Re, reprEui64Re, reprEui48Re, reprUuidRe,
                 reprCallRe, reprBoolRe, reprEllipsisRe, reprNumberComplexRe,
                 reprNumberRe, reprPathRe, reprStrRe, reprUrlRe)
  ]
    ## rich highlighter.py:84-103 — `ReprHighlighter.highlights`: the four repr
    ## regex entries in source order. Entries 1-3 are standalone; entry 3 is the
    ## `_combine_regex(...)` `|`-OR-join of 13 sub-patterns, mirrored here by
    ## `combineRegex(...)`. 23 named groups total — tag_start/tag_name/
    ## tag_contents/tag_end, attrib_name/attrib_value, brace, ipv4/ipv6/eui64/
    ## eui48/uuid/call/bool_true/bool_false/none/ellipsis/number_complex/number/
    ## path/filename/str/url — match Rich 15.0.0 exactly. `RegexHighlighter.
    ## highlight` loops this list and calls `text.highlightRegex(reHighlight,
    ## stylePrefix = "repr.")` per entry (the audited PCRE scanner in `text.nim`).
  jsonHighlighterHighlights*: seq[string] = @[
    combineRegex(jsonBraceRe, jsonBoolsRe, jsonNumberRe, jsonHighlighterJsonStr)
  ]
    ## rich highlighter.py:114-121 — `JSONHighlighter.highlights`: a single
    ## combined regex (`_combine_regex` of brace/bools/number/JSON_STR) — the
    ## `brace`/`bool_true`/`bool_false`/`null`/`number`/`str` named groups
    ## (highlighter.py:115-120). `RegexHighlighter.highlight` loops this list and
    ## calls `text.highlightRegex(reHighlight, stylePrefix = "json.")` (the
    ## audited PCRE scanner in `text.nim`), adding a `json.<name>` span per
    ## participating group; the JSON-key scan below appends `json.key` spans for
    ## strings followed by `:` (highlighter.py:123-139).
  iso8601HighlighterHighlights*: seq[string] = @[]
    ## rich highlighter.py:149-199 — `ISO8601Highlighter.highlights`: the ISO8601
    ## date/time regex list. Stub `@[]`; body populates the 13 date/time/zone
    ## patterns (highlighter.py:150-198).

proc combineRegex(regexes: varargs[string]): string =
  ## rich highlighter.py:8-14 — `_combine_regex(*regexes: str) -> str`: OR-join a
  ## number of regexes into one. `*regexes: str` → `varargs[string]`. Private
  ## (`_`-prefixed; `highlighter.py` has no `__all__` but the underscore marks it
  ## module-private), so non-`*`. Used at class-definition time to build the
  ## `highlights` lists (body). (body `discard` ⇒ `""`).
  # Faithful to highlighter.py:13-14 (`return "|".join(regexes)` — OR-join,
  # NOT wrapped in `(?:…)`).
  result = ""
  for i in 0 ..< regexes.len:
    if i > 0:
      result.add("|")
    result.add(regexes[i])

# Forward declaration — `call` (line 127) dispatches to `highlight`
# (defined at line ~167+); Nim needs the proc visible before use.
proc highlight*(self: Highlighter, text: Text)

proc call*(self: Highlighter, text: TextType): Text =
  ## rich highlighter.py:20-39 — `Highlighter.__call__(self, text: Union[str,
  ## Text]) -> Text`: highlight a `str` or `Text` (wrap a `str` in `Text`, or
  ## `copy()` an existing `Text`; reject other types with `TypeError`,
  ## highlighter.py:30-35), then call `self.highlight` and return the result.
  ## `__call__` → `call` (Nim cannot overload `()` for objects ; a
  ## callable shim is a body concern); `Union[str, Text]` → `TextType`
  ## (`string or Text`, from text.nim — non-narrowing). (body
  ## `discard` ⇒ returns `nil`).
  # Faithful to highlighter.py:20-39: wrap a `str` in `Text` / `copy()` a `Text`, then
  # `self.highlight(text)`. `TextType = string or Text` is a typeclass, so the
  # proc is generic; dispatch str-vs-Text per instantiation via `when compiles`
  # (`Text` has `.copy()`, `str` does not). The `else` (non-str/non-Text) arm of
  # Python's `isinstance` ladder is structurally rejected by the `string or Text`
  # typeclass (no `TypeError` path needed).
  var highlightText: Text
  when compiles(text.copy()):
    # `text` is a `Text` — copy it so in-place highlighting doesn't mutate the
    # original (highlighter.py:33-34).
    highlightText = text.copy()
  else:
    # `text` is a `str` — wrap it in a new `Text` (highlighter.py:32-33).
    highlightText = initText(text)
  # `self.highlight(text)` (highlighter.py:37) is dynamically dispatched in
  # Python; Nim resolves `self.highlight` by the static `Highlighter` receiver
  # to the base no-op, so route to the concrete subclass overload via an
  # `of`-guarded downcast (the noted Phase-1 dispatch concern, file header).
  # `JSONHighlighter` (a `RegexHighlighter` subtype with its own `highlight`
  # overload) is checked first; the `RegexHighlighter` arm covers
  # `ReprHighlighter`/`ISO8601Highlighter`/plain `RegexHighlighter` (whose
  # overload selects the per-subclass `highlights`/`base_style`); the `else` is
  # `NullHighlighter`/a bare `Highlighter` (the base no-op).
  if self of JSONHighlighter:
    cast[JSONHighlighter](self).highlight(highlightText)
  elif self of RegexHighlighter:
    cast[RegexHighlighter](self).highlight(highlightText)
  else:
    self.highlight(highlightText)
  result = highlightText

proc highlight*(self: Highlighter, text: Text) =
  ## rich highlighter.py:42-47 — `Highlighter.highlight(self, text: Text)`: the
  ## `@abstractmethod` — apply highlighting in place to `text`.
  # Abstract base (highlighter.py:42-47); concrete subclasses override this.
  # `call` now routes a subclass instance to its overload via an `of`-guarded
  # downcast (see `call`), so this base is reached only for a bare `Highlighter`
  # (Python's ABC forbids instantiating it) or via `call`'s `else` fallback — a
  # safe no-op; raising would break that fallback. The dispatch gap this base
  # once documented (file header) is now wired in `call`.
  discard

proc highlight*(self: NullHighlighter, text: Text) =
  ## rich highlighter.py:57-58 — `NullHighlighter.highlight`: no-op ("Nothing to
  ## do").
  # Faithful no-op — `NullHighlighter` does nothing (highlighter.py:57-58).
  discard

proc highlight*(self: RegexHighlighter, text: Text) =
  ## rich highlighter.py:67-77 — `RegexHighlighter.highlight`: for each regex in
  ## `self.highlights`, call `text.highlight_regex(re_highlight,
  ## style_prefix=self.base_style)` (highlighter.py:71-74).
  # Faithful to highlighter.py:67-74: for each regex in `self.highlights`, call
  # `text.highlight_regex(re_highlight, style_prefix=self.base_style)`. The
  # `highlights`/`base_style` ClassVars are module-level `let`/`const` (see file
  # header); a subclass (`ReprHighlighter`/`ISO8601Highlighter`) resolves its
  # OWN ClassVar, so select the per-subclass list/prefix via an `of`-guarded
  # downcast (the noted Phase-1 subclass-dispatch concern, file header).
  # `JSONHighlighter` never reaches here — `call` routes it to its own
  # `highlight` overload (which inlines its `highlights` loop); a plain
  # `RegexHighlighter` uses the base list/prefix. `highlightRegex` is itself a
  # stub (nil-safe `discard`), so this compiles and is structurally faithful;
  # the selected list is a stub `@[]` until a later batch populates it (per its
  # docstring), so the loop is empty for now.
  if self of ReprHighlighter:
    for reHighlight in reprHighlighterHighlights:
      discard text.highlightRegex(reHighlight, stylePrefix = reprHighlighterBaseStyle)
  elif self of ISO8601Highlighter:
    for reHighlight in iso8601HighlighterHighlights:
      discard text.highlightRegex(reHighlight, stylePrefix = iso8601HighlighterBaseStyle)
  else:
    for reHighlight in regexHighlighterHighlights:
      discard text.highlightRegex(reHighlight, stylePrefix = regexHighlighterBaseStyle)

# Forward declaration — `JSONHighlighter.highlight` (below) calls `scanJsonKeys`
# (defined at the end of this module); Nim needs the proc visible before use.
proc scanJsonKeys*(text: Text)

proc highlight*(self: JSONHighlighter, text: Text) =
  ## rich highlighter.py:123-140 — `JSONHighlighter.highlight`: `super().highlight
  ## (text)` then scan `text.plain` for `JSON_STR` matches and append a
  ## `"json.key"` `Span` after a following `:` (highlighter.py:127-139).
  # `super().highlight(text)` (highlighter.py:124) — the `RegexHighlighter` loop
  # using JSON's own `highlights`/`base_style` (`jsonHighlighterHighlights`/
  # `jsonHighlighterBaseStyle`), adding a `json.<name>` span per named group
  # (`brace`/`bool_true`/`bool_false`/`null`/`number`/`str`) via the audited PCRE
  # `text.highlightRegex` scanner.
  for reHighlight in jsonHighlighterHighlights:
    discard text.highlightRegex(reHighlight, stylePrefix = jsonHighlighterBaseStyle)
  # JSON-key scan (highlighter.py:127-139): for each `JSON_STR` match, scan
  # forward from `end` skipping `JSON_WHITESPACE`; if the first non-whitespace
  # char is `:`, the string is a JSON key → append `Span(start, end, "json.key")`.
  # The key span is appended AFTER the `json.str` span from `super().highlight`,
  # so `Style.combine` at render time (sorted-stack, text.py:752-756) lets
  # `json.key` override `json.str` → keys render bold-blue, values green (Rich
  # 15.0.0). The finditer is a non-anchored PCRE `exec` loop (Python `re.finditer`
  # semantics); JSON strings are non-empty, so `pos = mEnd` always advances.
  scanJsonKeys(text)

proc scanJsonKeys*(text: Text) =
  ## [Nim-only helper] rich highlighter.py:127-139 — the JSON-key scan. Finds all
  ## `JSON_STR` matches in `text.plain` and, for each followed (skipping
  ## `JSON_WHITESPACE`) by `:`, appends `Span(start, end, "json.key")`. Compiled
  ## with `UTF8|UCP` (no MULTILINE — matches `re`'s default flags for the
  ## highlighter regexes, as in `text.nim`'s `highlightRegex`).
  let plain = text.plain
  let cr = pcre_wrap.compileRegex(jsonHighlighterJsonStr,
                                  pcre_wrap.rfUtf8 or pcre_wrap.rfUcp)
  let n = plain.len
  var pos = 0
  var ovec: array[64, int32]
  let ovecsize = (cr.groupCount + 1) * 3
  while pos <= n:
    let rc = pcre.exec(cr.code, cr.extra, plain.cstring, n.cint, pos.cint, 0,
                       cast[ptr cint](addr ovec[0]), ovecsize.cint)
    if rc < 0:
      break
    let mStart = int(ovec[0])
    let mEnd = int(ovec[1])
    if mEnd <= mStart:
      pos = mStart + 1
      continue
    var cursor = mEnd
    var isKey = false
    while cursor < n:
      let ch = plain[cursor]
      inc cursor
      if ch == ':':
        isKey = true
        break
      elif ch in jsonHighlighterJsonWhitespace:
        continue
      else:
        break
    if isKey:
      text.spansData.add(Span(start: mStart, `end`: mEnd, style: "json.key"))
    pos = mEnd
