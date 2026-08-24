## Port of `rich.json` (rich/json.py).
##
## `JSON` (json.py:9-79): a renderable that pretty-prints JSON data. `__init__`
## (json.py:14-41) parses+re-dumps the string (so the rendered text is
## canonical) and highlights it via `JSONHighlighter`/`NullHighlighter`;
## `from_data` (json.py:48-79) does the same from arbitrary data; `__rich__`
## (json.py:65-66) returns the highlighted `Text`.
##
## Import graph (rich/json.py:1-6): runtime imports are `from pathlib import
## Path` (json.py:1), `from json import loads, dumps` (json.py:2), `from
## typing import Any, Callable, Optional, Union` (json.py:3), `from .text
## import Text` (json.py:5), `from .highlighter import JSONHighlighter,
## NullHighlighter` (json.py:6).
##
## wiring (this file):
##   `import std/[options, json]` — `Option[JsonDefault]` (the `default:
##                       Optional[Callable[[Any], Any]] = None` param,
##                       json.py:21); `JsonNode` is the non-narrowing Nim
##                       handle for rich `Any` (`typing.Any`), exactly as
##                       `api_types.JsonAny = JsonNode` (covers every rich `Any`
##                       value type) — used for the `from_data` `data: Any`
##                       param (json.py:49) and the `JsonDefault` callable's
##                       `Any` args (json.py:21). The Python stdlib `loads`/
##                       `dumps` (json.py:2) map to Nim `std/json` `parseJson`/
##                       `pretty`/`compact` (Body).
##   `import text`       — `Text` (the `JSON.text` field type, json.py:39, and
##                       the `__rich__` return, json.py:66).
## `highlighter` (`JSONHighlighter`/`NullHighlighter`, json.py:6, used in the
## `__init__`/`from_data` bodies, json.py:37,77) is body-only → not imported in
## (mirrors `rule.nim`'s body-only deps); `Path` (json.py:1) is
## `__main__`-only.
##
## `JSON` (json.py:9, `class JSON`, no base → a `RichCast` via `__rich__`) is
## `ref object of RootObj` (reference semantics; NOT a `ConsoleRenderable` —
## renders via `__rich__`/`RichCast`). `self.text: Text` (json.py:39) → field
## `text*` (a field named `text` of type `Text` from the imported `text`
## module — `self.text` is member access, no module/field clash). `indent:
## Union[None, int, str] = 2` (json.py:15) → `JsonIndent`, a tagged case object
## (`jiNone`/`jiInt`/`jiStr`) with the faithful default
## `JsonIndent(kind: jiInt, spaces: 2)` (a case-object default param, verified
## to compile). `default: Optional[Callable[[Any], Any]] = None` (json.py:21)
## → `` `default`: Option[JsonDefault] = none(JsonDefault) `` (`default` is
## backtick-quoted to avoid any `system.default` confusion; `Callable[[Any],
## Any]` → `proc(x: JsonNode): JsonNode {.closure.}`, the `JsonDefault` alias).
## `from_data` classmethod (json.py:48) → `fromData*(T: typedesc[Json], …)`.
## `__rich__`→`richCast`. The bool params keep their Python defaults
## (`highlight=true`, `skipKeys=false`, `ensureAscii=false`, `checkCircular=
## true`, `allowNan=true`, `sortKeys=false`). Bodies mirror the Python source
## (`discard`).

import std/[options, json]

import text        # Text — the JSON.text field type (json.py:39) and the
                   # __rich__ return (json.py:66).
import highlighter  # JSONHighlighter, NullHighlighter, Highlighter (json.py:37).
import segment      # re-exports richbase → `OverflowMethod` (json.py:39 `text.overflow`).

type
  JsonIndentKind* = enum
    ## [Nim-only discriminator] for `JsonIndent` — the three arms of rich
    ## `Union[None, int, str]` (json.py:15, the `indent` param annotation). One
    ## arm per Python variant, exactly bidirectionally consistent (no
    ## narrowing).
    jiNone   ## the `None` arm (`Union[None, int, str]`, json.py:15) — compact, no indent.
    jiInt    ## the `int` arm (`Union[None, int, str]`, json.py:15) — N spaces (default `2`).
    jiStr    ## the `str` arm (`Union[None, int, str]`, json.py:15) — a literal indent string.

  JsonIndent* = object
    ## rich json.py:15 — `indent: Union[None, int, str] = 2` (the `__init__`/
    ## `from_data` param) as a Nim case object (a true tagged union) so the
    ## `int`-vs-`str`-vs-`None` distinction is faithful (Python `indent=2` → 2
    ## spaces; `indent=None` → compact; `indent="\t"` → tab). The default is
    ## `JsonIndent(kind: jiInt, spaces: 2)` (the Python default `2`). Nim-only
    ## handle.
    case kind*: JsonIndentKind
    of jiNone:
      discard
    of jiInt:
      spaces*: int       ## the `int` arm — number of indent spaces.
    of jiStr:
      indentStr*: string  ## the `str` arm — a literal indent string.

  JsonDefault* = proc(x: JsonNode): JsonNode {.closure.}
    ## rich json.py:21 — `default: Optional[Callable[[Any], Any]] = None`: the
    ## callable that converts values that cannot be JSON-encoded into
    ## something that can (the `json.dumps` `default=` kwarg, json.py:21,77).
    ## `Callable[[Any], Any]` → `proc(x: JsonNode): JsonNode {.closure.}`
    ## (`Any` → `JsonNode`, the non-narrowing handle). Nim-only alias.

  Json* = ref object of RootObj
    ## rich json.py:9-79 — `class JSON`: "A renderable which pretty prints JSON."
    ## `ref object of RootObj` (reference semantics; NOT a `ConsoleRenderable`
    ## — renders via `__rich__`/`RichCast`). Field mirrors the `__init__`/
    ## `from_data` store (json.py:39,80).
    text*: Text          ## rich json.py:39-39 — `self.text = highlighter(json)` (the highlighted `Text`; `__rich__` returns it, json.py:66).

proc buildJsonText(node: JsonNode, indent: JsonIndent, highlight: bool): Text =
  ## [Nim-only helper] Shared `dumps` + highlight + `no_wrap`/`overflow` set for
  ## `initJson`/`fromData` (json.py:32-39, 76-79). `std/json`'s `pretty` models
  ## only the `jiInt` (spaces) arm; `jiNone`→compact (`$`); `jiStr` (a literal
  ## indent like `"\t"`) is not supported by `std/json.pretty` (DEFERRED — falls
  ## back to 2-space). The `skip_keys`/`ensure_ascii`/`sort_keys`/`default`/
  ## `allow_nan` `dumps` options are not modelled by `std/json`'s pretty-printer
  ## (deferred). Highlight via `JSONHighlighter`/`NullHighlighter` + `call`
  ## (stub → `nil` `Text`); the `no_wrap=True`/`overflow=None` field sets are
  ## guarded against the stub `nil`.
  var dumped: string
  case indent.kind
  of jiNone:
    dumped = $node
  of jiInt:
    dumped = pretty(node, indent.spaces)
  of jiStr:
    # DEFERRED(std/json): a literal-string indent (`json.dumps(indent="\t")`)
    # is not supported by `std/json.pretty`; fall back to 2-space pretty.
    dumped = pretty(node, 2)
  result = initText(dumped)
  # Apply the highlighter DIRECTLY (NOT via `Highlighter.call`): `call` is
  # generic over `TextType = string or Text`, and Nim evaluates its
  # `when compiles(text.copy())` gate against the typeclass (TRUE — the `Text`
  # arm has `.copy()`), so the string arm wrongly takes the `text.copy()` path
  # and applies no spans. Dispatch to the concrete `highlight` overload on the
  # freshly-built `Text` (mirrors `call`'s intent; `NullHighlighter.highlight` is
  # a no-op for `highlight=false`).
  if highlight:
    JSONHighlighter().highlight(result)
  else:
    NullHighlighter().highlight(result)
  if not result.isNil:
    result.noWrap = some(true)
    result.overflow = none(OverflowMethod)

proc initJson*(json: string, indent: JsonIndent = JsonIndent(kind: jiInt,
               spaces: 2), highlight: bool = true, skipKeys: bool = false,
               ensureAscii: bool = false, checkCircular: bool = true,
               allowNan: bool = true,
               `default`: Option[JsonDefault] = none(JsonDefault),
               sortKeys: bool = false): Json =
  ## rich json.py:14-41 — `JSON.__init__(self, json: str, indent: Union[None,
  ## int, str] = 2, highlight: bool = True, skip_keys: bool = False,
  ## ensure_ascii: bool = False, check_circular: bool = True, allow_nan: bool
  ## = True, default: Optional[Callable[[Any], Any]] = None, sort_keys: bool
  ## = False) -> None`: `loads(json)` then `dumps(...)` (canonicalising,
  ## json.py:31-40), highlight via `JSONHighlighter()`/`NullHighlighter()`
  ## (json.py:37), store `self.text` and set `no_wrap=True`/`overflow=None`
  ## (json.py:38-39). `indent` → `JsonIndent` (default `JsonIndent(kind: jiInt,
  ## spaces: 2)`); `default` → `` `default`: Option[JsonDefault] `` (backtick-
  ## quoted; default `none(JsonDefault)`); `skip_keys`/`ensure_ascii`/
  ## `check_circular`/`allow_nan`/`sort_keys` → `skipKeys`/`ensureAscii`/
  ## `checkCircular`/`allowNan`/`sortKeys` (snake→camel). Body needs
  ## `std/json` (`parseJson`/`pretty`) + `highlighter.JSONHighlighter`/
  ## `NullHighlighter` (json.py:37). (body `discard` ⇒ returns
  ## `nil`).
  result = Json()
  # `loads(json)` (json.py:31) → `parseJson` (raises on invalid JSON, faithful
  # to `JSONDecodeError`); the rest (`dumps`/highlight/field set) is shared with
  # `fromData` via `buildJsonText`.
  result.text = buildJsonText(parseJson(json), indent, highlight)

proc fromData*(T: typedesc[Json], data: JsonNode,
               indent: JsonIndent = JsonIndent(kind: jiInt, spaces: 2),
               highlight: bool = true, skipKeys: bool = false,
               ensureAscii: bool = false, checkCircular: bool = true,
               allowNan: bool = true,
               `default`: Option[JsonDefault] = none(JsonDefault),
               sortKeys: bool = false): Json =
  ## rich json.py:48-79 — `JSON.from_data(cls, data: Any, indent: …, highlight:
  ## bool = True, …, sort_keys: bool = False) -> "JSON"` (classmethod): encode
  ## arbitrary data via `dumps(...)` (json.py:76), highlight, store `self.text`
  ## (json.py:77-79). Classmethod → `typedesc[Json]` proc (like
  ## `grid(Table, …)`); `data: Any` → `data: JsonNode` (the `Any` handle); the
  ## remaining params mirror `initJson` exactly. Body needs `std/json`
  ## (`pretty`/`compact`) + `highlighter` (json.py:77). (body
  ## `discard` ⇒ returns `nil`).
  result = Json()
  # `cls.__new__(cls)` (json.py:71) → `Json()`; `dumps(data, …)` (json.py:76) +
  # highlight + field set shared via `buildJsonText` (the `data: JsonNode` is
  # already parsed — no `parseJson`).
  result.text = buildJsonText(data, indent, highlight)

proc richCast*(self: Json): Text =
  ## rich json.py:65-66 — `JSON.__rich__(self) -> Text`: `return self.text`
  ## (json.py:66). `richCast` (the `__rich__`→`RichCast` bridge) returns the
  ## highlighted `Text`. (body `discard` ⇒ returns `nil`).
  result = self.text
