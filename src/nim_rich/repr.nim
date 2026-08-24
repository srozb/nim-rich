## Nim port of `rich.repr` (rich/repr.py).
##
## The `rich_repr`/`auto` class-decorator machinery that builds a `__repr__`
## from a `__rich_repr__` generator (repr.py:25-104), plus the `Result`/
## `RichReprResult` type aliases (repr.py:18-19) and the `ReprError` exception
## (repr.py:22). `rich.pretty` imports `RichReprResult` (pretty.py:30) and the
## `ReprHighlighter` consumes `__rich_repr__` results.
##
## Import graph (rich/repr.py:1-13): runtime imports are `from functools import
## partial` (repr.py:1) and `from typing import Any, Callable, Iterable, List,
## Optional, Tuple, Type, TypeVar, Union, overload` (repr.py:2-13) — ZERO rich
## sibling imports (`from rich.console import Console` @ repr.py:134 is
## `__main__`-only). So this is a pure leaf; the Nim port mirrors that with
## ZERO sibling imports.
##
## wiring (this file): `import std/json` only.
##   `std/json`    — `JsonNode` is the non-narrowing Nim handle for rich `Any`
##                   (`typing.Any`), exactly as `api_types.JsonAny = JsonNode`
##                   (the inline `JsonNode` spelling IS that identical type —
##                   see api_types.nim); it covers every rich `Any` value type
##                   (`str`/`int`/`float`/`bool`/`None`/`seq`/`dict`), so the
##                   `Any` slots in `Result` reject no legal Python variant.
##
## `Result = Iterable[Union[Any, Tuple[Any], Tuple[str, Any], Tuple[str, Any,
## Any]]]` (repr.py:18): a `__rich_repr__` generator yields one of — a bare
## value (`Any`), a 1-tuple `(Any,)`, a pair `(str, Any)`, or a triple `(str,
## Any, Any)` (repr.py:60-69 consume these). Modelled as a closure-iterator
## type `iterator(): ReprArg {.closure.}` over the tagged `ReprArg` union (one
## arm per Python variant); `RichReprResult = Result` (repr.py:19). Python
## generators → Nim closure iterators (the established port form —
## `containers.nim` already uses `iterator(): T {.closure.}`).
##
## `auto`/`rich_repr` are Python class decorators that mutate `cls.__repr__`/
## `cls.__rich_repr__` at RUNTIME (repr.py:42-104); Nim has no runtime class
## decoration, so the faithful Nim port is a compile-time `template`/`macro`
## (body); they are NOT ported as `proc`s (the decorator overload shapes
## have no Nim equivalent). The current replacement is the explicit-call
## `autoRepr*` proc (callers do `autoRepr("Style", self.richRepr(), angular =
## false)` instead of `repr(self)`). `T` (repr.py:15, `TypeVar("T")`) is
## modelled by the generic parameter `[T]` (no separate symbol — Nim generics
## are reified per call). Proc bodies are ported (autoRepr + the
## toHexByte/pyStrRepr/jsonRepr helpers implement repr.py:43-67).

import std/[json]

type
  ReprArgKind* = enum
    ## [Nim-only discriminator] for `ReprArg` — the four arms of rich `Result`
    ## = `Iterable[Union[Any, Tuple[Any], Tuple[str, Any], Tuple[str, Any,
    ## Any]]]` (repr.py:18). One arm per Python variant, exactly
    ## bidirectionally consistent with `Result` (no narrowing).
    rakValue    ## the bare `Any`            arm (repr.py:18 `Union[Any, …]`).
    rakTuple1   ## the `Tuple[Any]`          arm (repr.py:18) — a 1-tuple.
    rakPair     ## the `Tuple[str, Any]`    arm (repr.py:18) — `(key, value)`.
    rakTriple   ## the `Tuple[str, Any, Any]` arm (repr.py:18) — `(key, value, default)`.

  ReprArg* = object
    ## rich repr.py:18 — one element of `Result` = `Union[Any, Tuple[Any],
    ## Tuple[str, Any], Tuple[str, Any, Any]]` as a Nim case object (a true
    ## tagged union). The `__rich_repr__` generator yields one `ReprArg` per
    ## `yield` (repr.py:60-69); `auto_repr` (repr.py:43-67) discriminates the
    ## arms by `isinstance(arg, tuple)` + `len(arg)`. The `Any` slots are
    ## `JsonNode` (the non-narrowing `Any` handle — see file header). Nim-only
    ## handle.
    case kind*: ReprArgKind
    of rakValue:
      value*: JsonNode          ## the bare value (`Any`).
    of rakTuple1:
      only*: JsonNode           ## the single element of the 1-tuple (`Tuple[Any]`).
    of rakPair:
      key*: string              ## the `str` key (`Tuple[str, Any]`; `auto_repr` prints `f"{key}={value!r}"`, repr.py:66 — when non-`None`).
      pairValue*: JsonNode      ## the value (`Any`).
    of rakTriple:
      tripleKey*: string        ## the `str` key (`Tuple[str, Any, Any]`).
      tripleValue*: JsonNode    ## the value (`Any`).
      tripleDefault*: JsonNode  ## the default (`Any`; skipped if `== value`, repr.py:63-64).

  Result* = iterator(): ReprArg {.closure.}
    ## rich repr.py:18 — `Result = Iterable[Union[Any, Tuple[Any], Tuple[str,
    ## Any], Tuple[str, Any, Any]]]`: the return type of a `__rich_repr__`
    ## generator. Modelled as a Nim closure-iterator over `ReprArg` (the tagged
    ## union, one arm per Python variant) — the established port form for a
    ## Python generator-returning iterable (`containers.nim` uses the same
    ## `iterator(): T {.closure.}` shape). `{.closure.}` makes it a first-class
    ## iterator value that can be returned and iterated with `for`.

  RichReprResult* = Result
    ## rich repr.py:19 — `RichReprResult = Result`: a public alias for `Result`
    ## (the canonical name `rich.pretty` imports, pretty.py:30). A Nim type
    ## alias to `Result`.

  ReprError* = object of CatchableError
    ## rich repr.py:22-23 — `class ReprError(Exception)`: "An error occurred
    ## when attempting to build a repr." Raised by `auto_rich_repr` on signature
    ## introspection failure (repr.py:96-98). `object of CatchableError` (the
    ## Nim mirror of `Exception` for a recoverable error).

proc toHexByte(b: uint8): string =
  ## [Nim-only helper] Two lowercase hex digits for `b` (the `\xHH` escape in
  ## `pyStrRepr`). Hand-rolled to avoid `std/strutils.toHex`, keeping the
  ## module's import list at `std/[options, json]` only — the contract's
  ## pure-leaf wiring (repr.py:1-13 imports ZERO rich siblings; the only
  ## stdlib rich pulls here is `functools.partial`/`typing`, mirrored by
  ## `options`/`json`).
  const hexDigits = "0123456789abcdef"
  result.add(hexDigits[int(b shr 4)])
  result.add(hexDigits[int(b and 0xF)])

proc pyStrRepr(s: string): string =
  ## [Nim-only helper] CPython `repr(str)` — the `repr(value)` /
  ## `f"{key}={value!r}"` rendering of a `str` in rich's `auto_repr`
  ## (repr.py:60,66). Quote selection: single-quote `'` by default,
  ## double-quote `"` when `s` contains a `'` and no `"` (CPython's rule);
  ## escapes `\\`, the chosen quote, `\n`, `\r`, `\t`, and other control
  ## bytes (`\xHH` for `< 0x20` or `0x7F`). Printable bytes (incl. UTF-8
  ## continuations `>= 0x80`) are emitted as-is, matching CPython keeping
  ## printable non-ASCII untouched. Byte-wise (Nim `string` is UTF-8), so a
  ## multibyte printable char flows through verbatim.
  var hasSingle = false
  var hasDouble = false
  for c in s:
    if c == '\'': hasSingle = true
    elif c == '"': hasDouble = true
  let quote = if hasSingle and not hasDouble: '"' else: '\''
  result.add(quote)
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if c == quote:
        result.add('\\')
        result.add(c)
      elif c.uint8 < 32 or c.uint8 == 127:
        result.add("\\x")
        result.add(toHexByte(c.uint8))
      else:
        result.add(c)
  result.add(quote)

proc jsonRepr(n: JsonNode): string =
  ## [Nim-only helper] CPython `repr()`-style rendering of a `JsonNode` (the
  ## non-narrowing `Any` handle — see file header) — the `repr(arg)` /
  ## `repr(arg[0])` / `repr(value)` calls in rich's `auto_repr` (repr.py:60,61,
  ## 66). Mirrors CPython's `repr` for the JsonNode subset: `null` -> `None`,
  ## `bool` -> `True`/`False` (capitalised, not Nim `true`/`false`), `int` ->
  ## decimal, `float` -> `$`, `string` -> `pyStrRepr`, `array` -> `[a, b]`,
  ## `object` -> `{k: v}`. `JsonNode` has no tuple/set/fraction arm, so Python
  ## `tuple`/`set`/`frozenset`/etc. values are unrepresentable — consistent
  ## with the `Any` -> `JsonNode` handle (covers every rich `Any` *primitive*
  ## value; rich's `__rich_repr__` tuples are modelled as `ReprArg` arms, not
  ## as `Any` values, so this never loses a real repr piece).
  if n.isNil or n.kind == JNull:
    result = "None"
  elif n.kind == JBool:
    result = if n.getBool: "True" else: "False"
  elif n.kind == JInt:
    result = $n.getInt
  elif n.kind == JFloat:
    result = $n.getFloat
  elif n.kind == JString:
    result = pyStrRepr(n.getStr)
  elif n.kind == JArray:
    result = "["
    var i = 0
    for e in n.items:
      if i > 0: result.add(", ")
      result.add(jsonRepr(e))
      i += 1
    result.add("]")
  elif n.kind == JObject:
    result = "{"
    var first = true
    for k, v in n.pairs:
      if not first: result.add(", ")
      first = false
      result.add(pyStrRepr(k))
      result.add(": ")
      result.add(jsonRepr(v))
    result.add("}")

proc autoRepr*(className: string; resultIter: Result; angular: bool = false): string =
  ## rich repr.py:43-67 — `auto_repr(self) -> str` (the inner function `auto`
  ## installs as `cls.__repr__`, repr.py:42-67): build the repr string from a
  ## `__rich_repr__` result iterator. Faithful Phase-1 port, DECOMPOSED for
  ## Nim — Python reads `self.__class__.__name__`, `self.__rich_repr__()`,
  ## and `getattr(self.__rich_repr__, "angular", False)`, none of which a
  ## Nim value exposes (no `__class__`/`__rich_repr__`/method-attribute);
  ## this proc takes them explicitly: `className` (the class name),
  ## `resultIter` (the `__rich_repr__`/`richRepr` `Result`), and `angular`
  ## (the `<...>` vs `(...)` shape). Callers do
  ## `autoRepr("Style", self.richRepr(), angular = false)` — the callable
  ## replacement for the Python-installed `__repr__`: the frozen `auto`/
  ## `rich_repr` procs above CANNOT attach methods to a Nim type (Nim has no
  ## runtime class decoration — see their bodies), so the repr is built by an
  ## explicit call instead of `repr(self)`. This is the symbol
  ## `segment.nim`/`style.nim` reference as `repr.auto_repr` ("the exact
  ## `Style(...)` repr-fidelity is revisited when `repr.auto_repr` lands",
  ## segment.nim:152-153; the triple-skip `auto_repr` semantics,
  ## style.nim:788,825,829).
  ##
  ## Discrimination mirrors repr.py:60-69 over the `ReprArg` arms (the
  ## tagged union is bidirectionally consistent with `Result`, so every arm
  ## maps one Python variant):
  ##   `rakValue`  -> bare value      -> `jsonRepr(value)`    (repr.py:69 `else`).
  ##   `rakTuple1` -> 1-tuple         -> `jsonRepr(only)`     (repr.py:61 `len==1`).
  ##   `rakPair`   -> `(key, value)`  -> `f"{key}={value!r}"` (repr.py:66).
  ##   `rakTriple` -> `(key,val,def)` -> skip if `def==value` (repr.py:63-64),
  ##                                else `f"{key}={value!r}"` (repr.py:66).
  ## The `if key is None: append(repr(value))` branch (repr.py:64-65) is
  ## UNREACHABLE here: `ReprArg.key` is `string` (faithful to Python's
  ## `Tuple[str, Any]` annotation, repr.py:18), never `None`, so a `None` key
  ## has no `ReprArg` representation (dropped, consistent with the annotation;
  ## rich's own `__rich_repr__` generators never yield a `None` key). The
  ## empty-parts angular form keeps Python's trailing space
  ## (`f"<{name} {' '.join([])}>"` -> `"<Foo >"`). The result iterator is
  ## consumed via the call-form `for arg in resultIter()` (the only way to
  ## iterate a closure-iterator-typed VALUE in Nim 2.2.10 — the bare form
  ## `for arg in resultIter` resolves to `items(resultIter)` and fails; see
  ## `layout.nim:340`).
  var parts: seq[string] = @[]
  for arg in resultIter():
    case arg.kind
    of rakValue:
      parts.add(jsonRepr(arg.value))
    of rakTuple1:
      parts.add(jsonRepr(arg.only))
    of rakPair:
      parts.add(arg.key & "=" & jsonRepr(arg.pairValue))
    of rakTriple:
      if arg.tripleDefault == arg.tripleValue:
        discard "skip: value == default (repr.py:63-64)"
      else:
        parts.add(arg.tripleKey & "=" & jsonRepr(arg.tripleValue))
  if angular:
    var body = ""
    for i, p in parts:
      if i > 0: body.add(" ")
      body.add(p)
    result = "<" & className & " " & body & ">"
  else:
    var body = ""
    for i, p in parts:
      if i > 0: body.add(", ")
      body.add(p)
    result = className & "(" & body & ")"

discard
