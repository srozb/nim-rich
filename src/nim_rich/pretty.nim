## Port of `rich.pretty` (rich/pretty.py).
##
## `Pretty` is a renderable that pretty-prints any object (containers,
## dataclasses, namedtuples, attrs objects, `__rich_repr__` results) into a
## multi-line `Text`. The free procs `traverse`/`pretty_repr`/`pprint`/`install`
## drive the same machinery.
##
## Import graph (pretty.py:1-48): stdlib (`builtins`/`collections`/`dataclasses`/
## `inspect`/`os`/`reprlib`/`sys`/`array`/`types`, pretty.py:1-17) are body-only
## body concerns. `from rich.repr import RichReprResult` (pretty.py:30) →
## `repr` (body-only in `traverse`). `from . import get_console` (pretty.py:28)
## → `rich` package root, body-only (body). `from ._loop import loop_last`
## (pretty.py:29) → `_loop` not present (body). `from ._pick import
## pick_bool` (pretty.py:30) → `_pick` not present (body). `from .abc
## import RichRenderable` (pretty.py:31) → `abc` (body-only in
## `install`/`_ipy_display_hook`). `from .cells import cell_len` (pretty.py:32)
## → `cells` (body-only). `from .highlighter import ReprHighlighter`
## (pretty.py:34) → `highlighter` (the default highlighter + `Highlighter`
## base). `from .jupyter import JupyterMixin, JupyterRenderable` (pretty.py:36)
## → `JupyterMixin` modelled via `RenderableBase` (segment); `JupyterRenderable`
## body-only. `from .measure import Measurement` (pretty.py:37) → `measure`.
## `from .text import Text` (pretty.py:38) → `text` (body-only in
## `__rich_console__`). Nim-only: `import segment` for `RenderableBase`/
## `ConsoleHandle`/`ConsoleOptions`/`RenderResult`/`OverflowMethod`/
## `JustifyMethod`.
##
## Private helpers (pretty.py:51-130, 309-380) — `_is_attr_object`,
## `_get_attr_fields`, `_is_dataclass_repr`, `_has_default_namedtuple_repr`,
## `_ipy_display_hook`, `_safe_isinstance`, `_is_namedtuple`,
## `_get_braces_for_defaultdict`/`_get_braces_for_deque`/`_get_braces_for_array`,
## and the `_BRACES`/`_CONTAINERS`/`_MAPPING_CONTAINERS` type-keyed dispatch
## tables — are Python-reflection machinery with no Nim analogue ;
## they are documented here and implemented in body (via concept/generic
## dispatch). Only the PUBLIC API is stubbed below.
##
## Faithfulness: `Pretty(JupyterMixin)` (pretty.py:170-261) → `Pretty[T] = ref
## object of RenderableBase` (generic over the payload type `T`, since Python
## `_object: Any` is type-erased but the render dispatch needs the concrete
## type; `JupyterMixin` via `RenderableBase`). `highlighter: Optional[
## HighlighterType] = None` → `Option[Highlighter] = none(Highlighter)` (the
## `progress.nim` pattern; `HighlighterType = Union[Highlighter, ReprHighlighter]`
## collapses to the `Highlighter` base since `ReprHighlighter` is a subclass).
## `justify: Optional[JustifyMethod] = None` / `overflow: Optional[
## OverflowMethod] = None` → `Option[...] = none(...)` (enum members `jm*`/`om*`
## from richbase). `no_wrap: Optional[bool] = False` → `Option[bool] =
## some(false)` (a present `False`, distinct from `none(bool)` = None). `Node`
## (pretty.py:226-296, `@dataclass`) → `ref object of RootObj` + an `initNode`
## with the 12 dataclass defaults; `_Line` (pretty.py:299-380, private
## `@dataclass`) → private `Line`. `traverse`/`pretty_repr`/`pprint`/
## `is_expandable` take `_object: Any` → generic `[T]`.
##
## Naming: `__init__`→`initPretty`/`initNode`, `__rich_console__`→`renderConsole`,
## `__rich_measure__`→`richMeasure`, `__str__`→`str`, `iter_tokens`→`iterTokens`,
## `check_length`→`checkLength`, `is_expandable`→`isExpandable`, `pretty_repr`→
## `prettyRepr`; `_object`→`obj` (param)/`objectVal`→`obj` (field), `key_repr`→
## `keyRepr`, `open_brace`→`openBrace`, `is_tuple`→`isTuple`,
## `is_namedtuple`→`isNamedtuple`, `key_separator`→`keySeparator`. Proc bodies
## are `discard` (port)` / nil ref / empty seq / "").

import std/[options, strutils, tables, json]

import cells           # cellLen — Node/Line check_length + Pretty rich_measure.
import highlighter     # Highlighter (field), ReprHighlighter (default, body).
import measure         # Measurement — the richMeasure return type.
import segment         # richbase (RenderableBase, ConsoleHandle, ConsoleOptions,
                       # RenderResult, JustifyMethod, OverflowMethod) — re-exported.
from text import Text, fromAnsi, withIndentGuides, initText
                       # the `__rich_console__` pipeline (Text.from_ansi →
                       # highlighter → optional with_indent_guides → yield).
                       # Selective `from … import` (not `import text`) so text's
                       # `bool*` (`Text.__bool__`/`Span` overload) does NOT enter
                       # scope and clash with `system.bool` in the existing
                       # `Option[bool]` fields. text does not import pretty →
                       # no cycle.

type
  Pretty*[T] = ref object of RenderableBase
    ## rich pretty.py:170-261 — `class Pretty(JupyterMixin)`: a rich renderable
    ## that pretty-prints an object. Generic over the payload type `T` (Python
    ## `_object: Any`); `ref object of RenderableBase` (`JupyterMixin` via
    ## `RenderableBase`). Fields mirror the `__init__` assignments
    ## (pretty.py:213-227).
    obj: T
      ## pretty.py:214 — `self._object = _object` (private; `_object`→`obj`).
      ## The payload to pretty-print.
    highlighter*: Option[Highlighter]
      ## pretty.py:215 — `self.highlighter = highlighter or ReprHighlighter()`
      ## (`Optional[HighlighterType]`; the `progress.nim` `Option[Highlighter]`
      ## pattern — body resolves `or ReprHighlighter()`).
    indentSize*: int
      ## pretty.py:216 — `self.indent_size = indent_size` (`int`, default 4).
    justify*: Option[JustifyMethod]
      ## pretty.py:217 — `self.justify: Optional[JustifyMethod] = justify`.
    overflow*: Option[OverflowMethod]
      ## pretty.py:218 — `self.overflow: Optional[OverflowMethod] = overflow`.
    noWrap*: Option[bool]
      ## pretty.py:219 — `self.no_wrap = no_wrap` (`Optional[bool]`; default
      ## `False` → `some(false)`, distinct from `none(bool)`).
    indentGuides*: bool
      ## pretty.py:220 — `self.indent_guides = indent_guides` (`bool`).
    maxLength*: Option[int]
      ## pretty.py:221 — `self.max_length = max_length` (`Optional[int]`).
    maxString*: Option[int]
      ## pretty.py:222 — `self.max_string = max_string` (`Optional[int]`).
    maxDepth*: Option[int]
      ## pretty.py:223 — `self.max_depth = max_depth` (`Optional[int]`).
    expandAll*: bool
      ## pretty.py:224 — `self.expand_all = expand_all` (`bool`).
    margin*: int
      ## pretty.py:225 — `self.margin = margin` (`int`, default 0).
    insertLine*: bool
      ## pretty.py:226 — `self.insert_line = insert_line` (`bool`).

  Node* = ref object of RootObj
    ## rich pretty.py:228-296 — `@dataclass class Node`: a node in the repr tree
    ## (atomic or container). `ref object of RootObj` (Python dataclass =
    ## reference). Fields mirror the dataclass fields (pretty.py:230-237);
    ## defaults are provided by `initNode`.
    keyRepr*: string
      ## pretty.py:230 — `key_repr: str = ""`.
    valueRepr*: string
      ## pretty.py:231 — `value_repr: str = ""`.
    openBrace*: string
      ## pretty.py:232 — `open_brace: str = ""`.
    closeBrace*: string
      ## pretty.py:233 — `close_brace: str = ""`.
    empty*: string
      ## pretty.py:234 — `empty: str = ""`.
    last*: bool
      ## pretty.py:235 — `last: bool = False`.
    isTuple*: bool
      ## pretty.py:236 — `is_tuple: bool = False`.
    isNamedtuple*: bool
      ## pretty.py:237 — `is_namedtuple: bool = False`.
    children*: Option[seq[Node]]
      ## pretty.py:238 — `children: Optional[List["Node"]] = None`.
    keySeparator*: string
      ## pretty.py:239 — `key_separator: str = ": "`.
    separator*: string
      ## pretty.py:240 — `separator: str = ", "`.

  Line = ref object of RootObj
    ## rich pretty.py:299-380 — `@dataclass class _Line` (private): a line in
    ## the repr output. `ref object of RootObj` (Python dataclass). Private
    ## (Python `_Line` underscore) — no `*`. Fields mirror the dataclass fields
    ## (pretty.py:301-308); defaults provided in body's `initLine`.
    parent: Option[Line]
      ## pretty.py:301 — `parent: Optional["_Line"] = None`.
    isRoot: bool
      ## pretty.py:302 — `is_root: bool = False`.
    node: Option[Node]
      ## pretty.py:303 — `node: Optional[Node] = None`.
    text: string
      ## pretty.py:304 — `text: str = ""`.
    suffix: string
      ## pretty.py:305 — `suffix: str = ""`.
    whitespace: string
      ## pretty.py:306 — `whitespace: str = ""`.
    expanded: bool
      ## pretty.py:307 — `expanded: bool = False`.
    last: bool
      ## pretty.py:308 — `last: bool = False`.

# ---------------------------------------------------------------------------
# Private helpers — `_Line` construction (pretty.py:299-308) and the `traverse`
# reflection (pretty.py:395-553). The Python reflection paths
# (`__rich_repr__`/dataclass/attrs/namedtuple, pretty.py:413-532) have no
# static-generic Nim analogue; `buildNode` is a faithful best-effort for the
# standard Nim collections (`string`/`seq`/`array`/`Table`/atomic-via-`$`),
# respecting `max_length`/`max_string`/`max_depth`.
# ---------------------------------------------------------------------------

# Forward declarations — `render`/`renderConsole` use procs defined later
# (Nim method-call syntax `line.expandable` needs the proc visible to avoid
# being parsed as a field access; generics need an explicit forward sig).
proc prettyRepr*[T](obj: T, maxWidth: int = 80, indentSize: int = 4,
                    maxLength: Option[int] = none(int),
                    maxString: Option[int] = none(int),
                    maxDepth: Option[int] = none(int),
                    expandAll: bool = false): string
proc initNode*(keyRepr: string = "", valueRepr: string = "",
               openBrace: string = "", closeBrace: string = "",
               empty: string = "", last: bool = false,
               isTuple: bool = false, isNamedtuple: bool = false,
               children: Option[seq[Node]] = none(seq[Node]),
               keySeparator: string = ": ", separator: string = ", "): Node
proc expandable*(self: Line): bool
proc checkLength*(self: Line, maxLength: int): bool
proc expand*(self: Line, indentSize: int): seq[Line]
proc str*(self: Line): string

proc initLine(parent: Option[Line] = none(Line), isRoot: bool = false,
              node: Option[Node] = none(Node), text: string = "",
              suffix: string = "", whitespace: string = "",
              expanded: bool = false, last: bool = false): Line =
  new(result)
  result.parent = parent
  result.isRoot = isRoot
  result.node = node
  result.text = text
  result.suffix = suffix
  result.whitespace = whitespace
  result.expanded = expanded
  result.last = last

proc toReprStr(s: string, maxString: Option[int]): string =
  ## `traverse.to_repr` for a `str` value (pretty.py:437-446): a Python-`repr`-ish
  ## quote-wrap with `max_string` truncation (`f"{obj[:max]!r}+{truncated}"`).
  ## Best-effort: wraps in single quotes (no escape expansion); the byte slice
  ## `s[0 ..< m]` is ASCII-correct (wide-char slicing is a body refinement).
  if maxString.isSome and s.len > maxString.get:
    let m = maxString.get
    result = "'" & s[0 ..< m] & "'+" & $(s.len - m)
  else:
    result = "'" & s & "'"

proc keyReprOf[K](k: K, maxString: Option[int]): string =
  ## `traverse.to_repr(key)` (pretty.py:497): type-aware — a `string` key is
  ## quote-wrapped (Python `repr`); any other key uses its Nim `$` (Python
  ## `repr(int)`/`repr(float)` … are unquoted), matching the per-type `repr`.
  when K is string:
    result = toReprStr(k, maxString)
  else:
    when compiles($k):
      result = $k
    else:
      result = "..."

proc buildJsonNode(obj: JsonNode, depth: int, maxLen: Option[int],
                   maxStr: Option[int], maxDepth: Option[int]): Node =
  ## Traverse a `JsonNode` as Python-compatible dynamic data. This supplies a
  ## practical `Any` representation for heterogeneous lists and mappings.
  let reachedMaxDepth {.used.} = maxDepth.isSome and depth >= maxDepth.get
  case obj.kind
  of JNull:
    result = initNode(valueRepr = "None", last = true)
  of JBool:
    result = initNode(valueRepr = if obj.getBool: "True" else: "False",
                      last = true)
  of JInt:
    result = initNode(valueRepr = $obj.getInt, last = true)
  of JFloat:
    result = initNode(valueRepr = $obj.getFloat, last = true)
  of JString:
    result = initNode(valueRepr = toReprStr(obj.getStr, maxStr), last = true)
  of JArray:
    if reachedMaxDepth:
      result = initNode(valueRepr = "[...]", last = true)
    else:
      var children: seq[Node] = @[]
      var count = 0
      for value in obj.elems:
        inc count
        var child = buildJsonNode(value, depth + 1, maxLen, maxStr, maxDepth)
        child.last = count == obj.len
        children.add(child)
        if maxLen.isSome and count >= maxLen.get:
          break
      if maxLen.isSome and obj.len > maxLen.get:
        children.add(initNode(valueRepr = "... +" & $(obj.len - maxLen.get),
                              last = true))
      result = initNode(openBrace = "[", closeBrace = "]", empty = "[]",
                        children = some(children), last = true)
  of JObject:
    if reachedMaxDepth:
      result = initNode(valueRepr = "{...}", last = true)
    else:
      var children: seq[Node] = @[]
      var count = 0
      for key, value in obj.pairs:
        inc count
        var child = buildJsonNode(value, depth + 1, maxLen, maxStr, maxDepth)
        child.keyRepr = toReprStr(key, maxStr)
        child.keySeparator = ": "
        child.last = count == obj.len
        children.add(child)
        if maxLen.isSome and count >= maxLen.get:
          break
      if maxLen.isSome and obj.len > maxLen.get:
        children.add(initNode(valueRepr = "... +" & $(obj.len - maxLen.get),
                              last = true))
      result = initNode(openBrace = "{", closeBrace = "}", empty = "{}",
                        children = some(children), last = true)

proc buildNode[T](obj: T, depth: int, maxLen: Option[int],
                  maxStr: Option[int], maxDepth: Option[int]): Node =
  ## `traverse._traverse` (pretty.py:409-551), best-effort for the standard Nim
  ## collections. `max_length`/`max_depth` are respected; `max_string` truncates
  ## `str` values. The `__rich_repr__`/dataclass/attrs/namedtuple reflection
  ## (pretty.py:413-532) and `id()`-based recursion detection (pretty.py:411)
  ## have no static-generic Nim analogue and are deferred. The returned node's
  ## `last` defaults to `true` (the root); a parent overrides `last` per child.
  let reachedMaxDepth {.used.} = maxDepth.isSome and depth >= maxDepth.get
  when T is string:
    result = initNode(valueRepr = toReprStr(obj, maxStr), last = true)
  elif T is JsonNode:
    result = buildJsonNode(obj, depth, maxLen, maxStr, maxDepth)
  elif T is tuple:
    if reachedMaxDepth:
      result = initNode(valueRepr = "(...)", last = true)
    else:
      var children: seq[Node] = @[]
      for _, value in fieldPairs(obj):
        children.add(buildNode(value, depth + 1, maxLen, maxStr, maxDepth))
      if maxLen.isSome and children.len > maxLen.get:
        let omitted = children.len - maxLen.get
        children.setLen(maxLen.get)
        children.add(initNode(valueRepr = "... +" & $omitted, last = true))
      for i, child in children:
        child.last = i == children.high
      result = initNode(openBrace = "(", closeBrace = ")", empty = "()",
                        isTuple = true, children = some(children), last = true)
  elif T is seq or T is array:
    if reachedMaxDepth:
      result = initNode(valueRepr = "[...]", last = true)
    else:
      let n = obj.len
      var children: seq[Node] = @[]
      var count = 0
      for e in obj:
        inc count
        var cn = buildNode(e, depth + 1, maxLen, maxStr, maxDepth)
        cn.last = (count == n)
        children.add(cn)
        if maxLen.isSome and count >= maxLen.get:
          break
      if maxLen.isSome and n > maxLen.get:
        children.add(initNode(valueRepr = "... +" & $(n - maxLen.get), last = true))
      if n == 0:
        result = initNode(openBrace = "[", closeBrace = "]",
                          empty = "[]", children = some(newSeq[Node](0)),
                          last = true)
      else:
        result = initNode(openBrace = "[", closeBrace = "]",
                          children = some(children), last = true)
  elif T is Table or T is OrderedTable:
    ## `dict` (Python `dict`/`OrderedDict`) → `{`/`}` braces (pretty.py:451-471).
    ## Both Nim `Table` (hash, unordered) and `OrderedTable` (insertion-ordered)
    ## share the `pairs`/`len`/`{}`-brace repr, so one arm covers both; the golden
    ## dict cases use `OrderedTable` for deterministic insertion order (Python
    ## `dict` is ordered since 3.7), matching `{'a': 1, 'b': 2}` byte-exact.
    if reachedMaxDepth:
      result = initNode(valueRepr = "{...}", last = true)
    else:
      let n = obj.len
      var children: seq[Node] = @[]
      var count = 0
      for k, v in obj:
        inc count
        var cn = buildNode(v, depth + 1, maxLen, maxStr, maxDepth)
        cn.last = (count == n)
        cn.keyRepr = keyReprOf(k, maxStr)
        cn.keySeparator = ": "
        children.add(cn)
        if maxLen.isSome and count >= maxLen.get:
          break
      if maxLen.isSome and n > maxLen.get:
        children.add(initNode(valueRepr = "... +" & $(n - maxLen.get), last = true))
      if n == 0:
        result = initNode(openBrace = "{", closeBrace = "}",
                          empty = "{}", children = some(newSeq[Node](0)),
                          last = true)
      else:
        result = initNode(openBrace = "{", closeBrace = "}",
                          children = some(children), last = true)
  elif T is bool:
    ## `bool` → Python `repr(True)`/`repr(False)` = `"True"`/`"False"` (capital
    ## first letter). Nim's `$true`/`$false` are lowercase, so the atomic `else`
    ## arm's `$obj` would yield `"true"` (wrong); emit the Python-faithful literal.
    result = initNode(valueRepr = if obj: "True" else: "False", last = true)
  elif T is Option:
    ## `Option`/`None` → Python `None` (pretty.py:467 `to_repr(None)` = `repr(None)`
    ## = `"None"`). Nim's `$none(T)` = `"none(T)"` (wrong), so handle `Option`
    ## explicitly: `none` renders the atomic `"None"` (matches Python `None`);
    ## `some(x)` unwraps and traverses the inner value (Python has no `Option`, so
    ## this is the faithful best-effort — the only golden case is `none` → None).
    ## At `max_depth` `some(x)` renders atomically via `$obj` (the inner value
    ## can't be expanded further); `none` is atomic regardless of depth.
    if obj.isNone:
      result = initNode(valueRepr = "None", last = true)
    elif reachedMaxDepth:
      result = initNode(valueRepr = $obj, last = true)
    else:
      result = buildNode(obj.get, depth + 1, maxLen, maxStr, maxDepth)
  else:
    when compiles($obj):
      result = initNode(valueRepr = $obj, last = true)
    else:
      result = initNode(valueRepr = "...", last = true)

proc initPretty*[T](
    obj: T,
    highlighter: Option[Highlighter] = none(Highlighter),
    indentSize: int = 4,
    justify: Option[JustifyMethod] = none(JustifyMethod),
    overflow: Option[OverflowMethod] = none(OverflowMethod),
    noWrap: Option[bool] = some(false),
    indentGuides: bool = false,
    maxLength: Option[int] = none(int),
    maxString: Option[int] = none(int),
    maxDepth: Option[int] = none(int),
    expandAll: bool = false,
    margin: int = 0,
    insertLine: bool = false,
): Pretty[T] =
  ## rich pretty.py:186-227 — `Pretty.__init__(self, _object: Any, highlighter:
  ## Optional[HighlighterType] = None, *, indent_size: int = 4, justify:
  ## Optional[JustifyMethod] = None, overflow: Optional[OverflowMethod] = None,
  ## no_wrap: Optional[bool] = False, indent_guides: bool = False, max_length:
  ## Optional[int] = None, max_string: Optional[int] = None, max_depth:
  ## Optional[int] = None, expand_all: bool = False, margin: int = 0,
  ## insert_line: bool = False) -> None`. `_object`→`obj` (the generic payload
  ## `T`); `highlighter` default `None` → `none(Highlighter)` (body resolves
  ## `or ReprHighlighter()`); `no_wrap` default `False` → `some(false)`. The
  ## keyword-only group (Python `*`) keeps its order but is not enforced in Nim.
  new(result)
  result.obj = obj
  # `highlighter or ReprHighlighter()` (pretty.py:215): a present highlighter
  # wins; otherwise a fresh `ReprHighlighter` upcast to the `Highlighter` base
  # (the `some[Highlighter](ReprHighlighter())` idiom used in `console.nim`/
  # `scope.nim`).
  result.highlighter = if highlighter.isSome: highlighter
                       else: some[Highlighter](ReprHighlighter())
  result.indentSize = indentSize
  result.justify = justify
  result.overflow = overflow
  result.noWrap = noWrap
  result.indentGuides = indentGuides
  result.maxLength = maxLength
  result.maxString = maxString
  result.maxDepth = maxDepth
  result.expandAll = expandAll
  result.margin = margin
  result.insertLine = insertLine

method renderConsole*[T](self: Pretty[T], console: ConsoleHandle,
                       options: ConsoleOptions): RenderResult =
  ## rich pretty.py:229-258 — `Pretty.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: build `pretty_repr(self._object,
  ## ...)`, wrap as `Text.from_ansi(...)`, apply `self.highlighter`, optional
  ## indent-guides, and yield (pretty.py:231-257). `__rich_console__`→
  ## `renderConsole`.
  #
  # Faithful port of pretty.py:231-257. The pipeline is `pretty_repr` →
  ## `Text.from_ansi(pretty_str, justify=self.justify or options.justify,
  ## overflow=self.overflow or options.overflow, no_wrap=pick_bool(
  ## self.no_wrap, options.no_wrap), style="pretty")` → `self.highlighter(
  ## pretty_text)` (or a dim-italic `Text` if the repr is empty) → optional
  ## `with_indent_guides(self.indent_size, style="repr.indent")` when
  ## `self.indent_guides and not options.ascii_only` → optional leading `""`
  ## when `self.insert_line and "\n" in pretty_text` → `yield pretty_text`.
  # `console` is unused (the pipeline reads `options` only) — no `import
  ## console` needed (and that would cycle: console→traceback→pretty). The repr
  # infrastructure (`prettyRepr`/`Node`/`traverse`/`render`) is already
  # implemented above; `Text.fromAnsi` (text.nim) and `Highlighter.call`
  # (highlighter.nim) are wired, so the render is assembled and the `Text` is
  # yielded via `addRenderable` (the `ConsoleRenderable` arm). `pick_bool(a, b)`
  # returns the first non-`None` arg; both `self.noWrap`/`options.noWrap` are
  # `Option[bool]`, so it is `if self.noWrap.isSome: self.noWrap else:
  # options.noWrap` (a present `False` wins, matching Python's `no_wrap=False`
  # default). `self.justify or options.justify` / `self.overflow or
  # options.overflow` mirror Python's `or` (None → fallback). The empty-repr
  # branch uses a static `"object"` type-name placeholder (Nim generics cannot
  # recover Python's `type(self._object).__name__` at runtime) — a minor
  # deviation in a rare diagnostic path.
  result = @[]
  let maxWidth = max(0, options.maxWidth - self.margin)
  let prettyStr = prettyRepr(self.obj, maxWidth = maxWidth,
                            indentSize = self.indentSize,
                            maxLength = self.maxLength,
                            maxString = self.maxString,
                            maxDepth = self.maxDepth,
                            expandAll = self.expandAll)
  let justify = if self.justify.isSome: self.justify else: options.justify
  let overflow = if self.overflow.isSome: self.overflow else: options.overflow
  let noWrap = if self.noWrap.isSome: self.noWrap else: options.noWrap
  var prettyText = Text.fromAnsi(prettyStr, style = "pretty", justify = justify,
                                 overflow = overflow, noWrap = noWrap)
  if prettyText.len > 0:
    if self.highlighter.isSome:
      # Apply the highlighter in place. `Highlighter.call` (highlighter.nim)
      # resolves `cast[RegexHighlighter](self).highlight(...)` to the base
      # `Highlighter.highlight` no-op: the concrete `RegexHighlighter.highlight`
      # /`JSONHighlighter.highlight` overloads are defined after `call` and are
      # not forward-declared, so they are not overload candidates at the `call`
      # site — `call` therefore appends no spans (the `call` dispatch defect).
      # `pretty.nim` `import highlighter`s the full exported overload set, so the
      # `of`-guarded downcast here resolves to the concrete subclass `highlight`
      # (mirroring Python `self.highlighter(pretty_text)`, highlighter.py:20-39).
      # Python `__call__` copies the Text before highlighting; `prettyText` is a
      # fresh local from `Text.fromAnsi` (no external alias), so in-place
      # highlighting is observably equivalent to that copy.
      let hl = self.highlighter.get
      if hl of JSONHighlighter:
        cast[JSONHighlighter](hl).highlight(prettyText)
      elif hl of RegexHighlighter:
        cast[RegexHighlighter](hl).highlight(prettyText)
      else:
        hl.highlight(prettyText)
  else:
    prettyText = initText("object.__repr__ returned empty string",
                          style = "dim italic")
  if self.indentGuides and not options.asciiOnly:
    prettyText = prettyText.withIndentGuides(some(self.indentSize),
                                            style = "repr.indent")
  if self.insertLine and ("\n" in prettyText.plain):
    result.addString("")
  result.addRenderable(prettyText, rrkConsoleRenderable)

proc richMeasure*[T](self: Pretty[T], console: ConsoleHandle,
                     options: ConsoleOptions): Measurement =
  ## rich pretty.py:260-275 — `Pretty.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: return `Measurement(text_width,
  ## text_width)` over the longest cell-line of `pretty_repr(self._object, ...)`
  ## (pretty.py:262-274). `__rich_measure__`→`richMeasure`.
  let prettyStr = prettyRepr(self.obj, maxWidth = options.maxWidth,
                            indentSize = self.indentSize,
                            maxLength = self.maxLength,
                            maxString = self.maxString,
                            maxDepth = self.maxDepth,
                            expandAll = self.expandAll)
  var textWidth = 0
  if prettyStr.len > 0:
    for line in prettyStr.splitLines():
      let w = cellLen(line)
      if w > textWidth:
        textWidth = w
  result = Measurement(minimum: textWidth, maximum: textWidth)

proc initNode*(
    keyRepr: string,
    valueRepr: string,
    openBrace: string,
    closeBrace: string,
    empty: string,
    last: bool,
    isTuple: bool,
    isNamedtuple: bool,
    children: Option[seq[Node]],
    keySeparator: string,
    separator: string,
): Node =
  ## rich pretty.py:226-296 — `Node` dataclass `__init__` (auto-generated): the
  ## 11 fields with their dataclass defaults (pretty.py:230-240). `children`
  ## default `None` → `none(seq[Node])`; `key_separator`/`separator` defaults
  ## `": "`/`", "`. Returns a new `Node`.
  new(result)
  result.keyRepr = keyRepr
  result.valueRepr = valueRepr
  result.openBrace = openBrace
  result.closeBrace = closeBrace
  result.empty = empty
  result.last = last
  result.isTuple = isTuple
  result.isNamedtuple = isNamedtuple
  result.children = children
  result.keySeparator = keySeparator
  result.separator = separator

proc iterTokens*(self: Node): seq[string] =
  ## rich pretty.py:243-267 — `Node.iter_tokens(self) -> Iterable[str]`:
  ## generate the tokens for this node (key_repr + key_separator, then
  ## value_repr or the children braces, with separators between children,
  ## pretty.py:245-266). A generator in Python → `seq[string]` for the stub.
  result = @[]
  if self.keyRepr.len > 0:
    result.add(self.keyRepr)
    result.add(self.keySeparator)
  if self.valueRepr.len > 0:
    result.add(self.valueRepr)
  elif self.children.isSome:
    let children = self.children.get
    if children.len > 0:
      result.add(self.openBrace)
      if self.isTuple and not self.isNamedtuple and children.len == 1:
        for t in children[0].iterTokens():
          result.add(t)
        result.add(",")
      else:
        for child in children:
          for t in child.iterTokens():
            result.add(t)
          if not child.last:
            result.add(self.separator)
      result.add(self.closeBrace)
    else:
      result.add(self.empty)

proc checkLength*(self: Node, startLength: int, maxLength: int): bool =
  ## rich pretty.py:269-283 — `Node.check_length(self, start_length: int,
  ## max_length: int) -> bool`: sum `cell_len(token)` from `iter_tokens` and
  ## return whether it fits within `max_length` (pretty.py:274-282).
  var total = startLength
  for token in self.iterTokens():
    total += cellLen(token)
    if total > maxLength:
      return false
  result = true

proc str*(self: Node): string =
  ## rich pretty.py:285-288 — `Node.__str__(self) -> str`: `"".join(self.iter_tokens())`.
  ## `__str__`→`str`.
  for t in self.iterTokens():
    result.add(t)

proc render*(self: Node, maxWidth: int = 80, indentSize: int = 4,
             expandAll: bool = false): string =
  ## rich pretty.py:290-296 — `Node.render(self, max_width: int = 80,
  ## indent_size: int = 4, expand_all: bool = False) -> str`: expand the node
  ## into a pretty multi-line repr via `_Line` (pretty.py:292-296).
  var lines: seq[Line] = @[initLine(node = some(self), isRoot = true)]
  var lineNo = 0
  while lineNo < lines.len:
    let line = lines[lineNo]
    if line.expandable and not line.expanded:
      if expandAll or not line.checkLength(maxWidth):
        let expanded = line.expand(indentSize)
        lines.delete(lineNo)
        var idx = lineNo
        for l in expanded:
          lines.insert(l, idx)
          inc idx
    inc lineNo
  result = ""
  for i, line in lines:
    if i > 0:
      result.add("\n")
    result.add(line.str())

proc expandable*(self: Line): bool =
  ## rich pretty.py:311-313 — `_Line.expandable` (`@property`): `bool(self.node
  ## is not None and self.node.children)` (pretty.py:313). Private.
  result = self.node.isSome and self.node.get.children.isSome and self.node.get.children.get.len > 0

proc checkLength*(self: Line, maxLength: int): bool =
  ## rich pretty.py:315-323 — `_Line.check_length(self, max_length: int) ->
  ## bool`: check this line fits within `max_length` cells (pretty.py:317-322).
  ## Private.
  if self.node.isNone:
    return true
  let startLength = self.whitespace.len + cellLen(self.text) + cellLen(self.suffix)
  result = self.node.get.checkLength(startLength, maxLength)

proc expand*(self: Line, indentSize: int): seq[Line] =
  ## rich pretty.py:325-358 — `_Line.expand(self, indent_size: int) ->
  ## Iterable["_Line"]`: yield the child lines (indented) plus the closing
  ## brace line (pretty.py:329-357). A generator → `seq[Line]` for the stub.
  ## Private.
  result = @[]
  let node = self.node.get
  let whitespace = self.whitespace
  let children = node.children.get
  var newLine: Option[Line]
  if node.keyRepr.len > 0:
    let l = initLine(text = node.keyRepr & node.keySeparator & node.openBrace,
                    whitespace = whitespace)
    newLine = some(l)
    result.add(l)
  else:
    let l = initLine(text = node.openBrace, whitespace = whitespace)
    newLine = some(l)
    result.add(l)
  let childWhitespace = whitespace & spaces(indentSize)
  let tupleOfOne = node.isTuple and children.len == 1
  let n = children.len
  for i, child in children:
    let isLast = (i == n - 1)
    let sep = if tupleOfOne: "," else: node.separator
    let l = initLine(parent = newLine, node = some(child),
                    whitespace = childWhitespace, suffix = sep,
                    last = isLast and not tupleOfOne)
    result.add(l)
  let closeLine = initLine(text = node.closeBrace, whitespace = whitespace,
                           suffix = self.suffix, last = self.last)
  result.add(closeLine)

proc str*(self: Line): string =
  ## rich pretty.py:360-368 — `_Line.__str__(self) -> str`: format the line
  ## (`whitespace` + `text` + `node`/`suffix`, pretty.py:362-367). `__str__`→
  ## `str`. Private.
  let nodeStr = if self.node.isSome: self.node.get.str() else: ""
  if self.last:
    result = self.whitespace & self.text & nodeStr
  else:
    result = self.whitespace & self.text & nodeStr & self.suffix.strip(leading = false)

proc isExpandable*[T](obj: T): bool =
  ## rich pretty.py:285-296 → pretty.py:383-393 — `is_expandable(obj: Any) ->
  ## bool`: check if `obj` may be expanded by pretty print (a container,
  ## dataclass, `__rich_repr__`, or attrs object, and not a class,
  ## pretty.py:385-392). Generic `[T]` (Python `Any`).
  # Python: `_safe_isinstance(obj, _CONTAINERS) or is_dataclass(obj) or
  # hasattr(obj, "__rich_repr__") or _is_attr_object(obj)` (pretty.py:400-405),
  # and not a class. In Nim's static generics the container check maps to
  # `when T is seq|array|tuple|Table|JsonNode` — the `_BRACES` containers
  # `buildNode` actually expands; `set`/`frozenset`/
  # `deque`/… have no Nim-collection arm in `buildNode` (atomic via `$`), so they
  # return `false` here (consistent with `buildNode`, unlike Python where they
  # expand). dataclass/`__rich_repr__`/attrs are runtime reflection with no
  # static-generic analogue — deferred. Nim has no Python "class object" (a
  # type is not a value passed to a proc), so the `not isclass(obj)` guard is
  # vacuous here.
  when T is seq or T is array or T is tuple or T is Table or
       T is OrderedTable or T is JsonNode:
    result = true
  else:
    result = false

proc traverse*[T](obj: T, maxLength: Option[int] = none(int),
                  maxString: Option[int] = none(int),
                  maxDepth: Option[int] = none(int)): Node =
  ## rich pretty.py:395-553 — `traverse(_object: Any, max_length: Optional[int]
  ## = None, max_string: Optional[int] = None, max_depth: Optional[int] = None)
  ## -> Node`: walk the object depth-first and build a `Node` tree (handling
  ## `__rich_repr__`, attrs, dataclasses, namedtuples, containers, recursion
  ## via a visited-id set, pretty.py:397-551). Generic `[T]` (Python `Any`);
  ## `_object`→`obj`. Returns the root `Node`.
  result = buildNode(obj, 0, maxLength, maxString, maxDepth)

proc prettyRepr*[T](obj: T, maxWidth: int = 80, indentSize: int = 4,
                    maxLength: Option[int] = none(int),
                    maxString: Option[int] = none(int),
                    maxDepth: Option[int] = none(int),
                    expandAll: bool = false): string =
  ## rich pretty.py:555-587 — `pretty_repr(_object: Any, *, max_width: int =
  ## 80, indent_size: int = 4, max_length: Optional[int] = None, max_string:
  ## Optional[int] = None, max_depth: Optional[int] = None, expand_all: bool =
  ## False) -> str`: prettify an object's repr, expanding onto new lines to fit
  ## `max_width` (pretty.py:560-586). Accepts a `Node` directly (`T = Node`,
  ## pretty.py:562-563) or traverses first (pretty.py:564-566). Generic `[T]`;
  ## `_object`→`obj`. The keyword-only group (Python `*`) keeps its order.
  var node: Node
  when T is Node:
    node = obj
  else:
    node = traverse(obj, maxLength, maxString, maxDepth)
  result = node.render(maxWidth, indentSize, expandAll)

proc pprint*[T](obj: T, console: Option[ConsoleHandle] = none(ConsoleHandle),
                indentGuides: bool = true, maxLength: Option[int] = none(int),
                maxString: Option[int] = none(int),
                maxDepth: Option[int] = none(int),
                expandAll: bool = false) =
  ## rich pretty.py:590-619 — `pprint(_object: Any, *, console: Optional[
  ## Console] = None, indent_guides: bool = True, max_length: Optional[int] =
  ## None, max_string: Optional[int] = None, max_depth: Optional[int] = None,
  ## expand_all: bool = False) -> None`: convenience pretty-print to `console`
  ## (or `get_console()`) via `Pretty(..., overflow="ignore")` with
  ## `soft_wrap=True` (pretty.py:605-618). Generic `[T]`; `_object`→`obj`;
  ## `console: Optional[Console]` → `Option[ConsoleHandle]`.
  # `_console = get_console() if console is None else console` (pretty.py:605):
  # `get_console` is absent and `Console.print` is unreachable from here (the
  # `console`↔`traceback`↔`pretty` cycle pins the `console` param to the
  # `ConsoleHandle` base, which has no `print` method). Faithful best-effort:
  # `_console.print(Pretty(_object, overflow="ignore"), soft_wrap=True)`
  # (pretty.py:605-618) whose `Pretty.__rich_console__` render IS `pretty_repr`
  # — render the pretty repr and write it to stdout (the default-console
  # target) with no trailing newline (`soft_wrap=True`). `indentGuides` needs
  # the console's indent-guide rendering (deferred); `max_width` is 80 (rich's
  # non-terminal fallback). The `console` param's non-stdout target is not
  # honoured (no `ConsoleHandle.print`); styling is absent (default console
  # is unstyled).
  stdout.write(prettyRepr(obj, 80, 4, maxLength, maxString, maxDepth, expandAll))

proc install*(console: Option[ConsoleHandle] = none(ConsoleHandle),
              overflow: OverflowMethod = omIgnore, crop: bool = false,
              indentGuides: bool = false, maxLength: Option[int] = none(int),
              maxString: Option[int] = none(int),
              maxDepth: Option[int] = none(int),
              expandAll: bool = false) =
  ## rich pretty.py:120-167 — `install(console: Optional[Console] = None,
  ## overflow: OverflowMethod = "ignore", crop: bool = False, indent_guides:
  ## bool = False, max_length: Optional[int] = None, max_string: Optional[int]
  ## = None, max_depth: Optional[int] = None, expand_all: bool = False) -> None`:
  ## install automatic pretty printing in the Python REPL / IPython
  ## (pretty.py:122-165). `console: Optional[Console]` → `Option[ConsoleHandle]`;
  ## `overflow: OverflowMethod = "ignore"` (non-Optional) → `omIgnore`.
  # DEFERRED (pretty.py:122-165): installs `sys.displayhook` (CPython REPL) or an
  # IPython `RichFormatter`. Nim has no `sys.displayhook`/IPython equivalent to
  # replace, so the installation has no target — a genuine no-op in the port (the
  # parameters are captured only by the `ExcepthookCallable`-returning
  # `traceback.install`, not here). Faithful as a no-op until a Nim REPL hook
  # exists.
  discard
