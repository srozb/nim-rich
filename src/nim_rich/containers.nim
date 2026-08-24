## Port of `rich.containers` (rich/containers.py).
##
## `Renderables` (containers.py:30-63) is a list subclass that renders its
## contents; `Lines` (containers.py:66-167) is a list subclass that can render
## to the console and justify/overflow its `Text` lines.
##
## Import graph (rich/containers.py:1-25): runtime sibling imports are
## `from itertools import zip_longest` (containers.py:1, body-only — `justify`
## @159), `from .cells import cell_len` (containers.py:24, body-only — `justify`
## @136,137,142,148), `from .measure import Measurement` (containers.py:25, the
## `Renderables.__rich_measure__` return); `from .typing import …`
## (containers.py:2-11); under `TYPE_CHECKING` (containers.py:13) come
## `Console`, `ConsoleOptions`, `JustifyMethod`, `OverflowMethod`,
## `RenderResult`, `RenderableType` (`.console`, containers.py:14-21) and `Text`
## (`.text`, containers.py:22). `Text` is also imported lazily inside `justify`
## (containers.py:127). `T = TypeVar('T')` (containers.py:27) is a typing-only
## `TypeVar` (no Nim counterpart — Nim generics use inline `[T]`, not a
## module-level `TypeVar`).
##
## wiring (this file):
##   `import std/options` — `Option[seq[RenderableValue]]` (the
##                         `Optional[Iterable[RenderableType]]` None arm,
##                         containers.py:33).
##   `import richbase`     — `ConsoleHandle`, `ConsoleOptions`, `RenderResult`,
##                         `RenderableBase`, `RenderableType`, `JustifyMethod`,
##                         `OverflowMethod` (the `.console` TYPE_CHECKING
##                         imports mapped to the richbase placeholders —
##                         `containers.py` does NOT import `segment`).
##   `import measure`      — `Measurement` (containers.py:25, the
##                         `Renderables.__rich_measure__` return).
##   `import text`         — `Text` (containers.py:22, the `Lines._lines`
##                         element type / `__getitem__`/`append`/`pop`).
##   `import api_types`    — `RenderableValue` (the storable `RenderableType`
##                         handle, for the `Renderables._renderables` field).
## `cells` (`cell_len`, containers.py:24) is a body-only dep imported for the
## `Lines.justify` body (containers.py:136,137,142,148); `itertools.zip_longest`
## (containers.py:1, the `justify` `full` branch @159) has no direct Nim
## equivalent and the `full` branch is deferred (needs the unimplemented
## `text.Lines` API). `jupyter`/`console` are NOT bases here — `Renderables`/
## `Lines` are plain list subclasses with `__rich_console__`; modelled as
## `ref object of RenderableBase` so they satisfy `ConsoleRenderable` (the render protocol).
##
## `Renderables`/`Lines` are `ref object of RenderableBase` (Python reference
## semantics — `append`/`extend`/`__setitem__` mutate the internal list).
## `Renderables._renderables: List[RenderableType]` (containers.py:36) →
## `renderables*: seq[RenderableValue]`; the `__init__` param `renderables:
## Optional[Iterable[RenderableType]] = None` (containers.py:33) is split into
## THREE overloads — `Option[seq[RenderableValue]]` (default `none`, the `None`
## arm), `openArray[RenderableType]` (any seq/array of `RenderableType`, the
## established `measure.nim` pattern) and `proc [T: RenderableType]
## (renderables: iterator(): T {.closure.})` (a closure iterator — the
## `Iterable` arm that `openArray` cannot cover) — so `Renderables()` (None),
## `Renderables(none(…))`, `Renderables(@["a","b"])` (seq[str]),
## `Renderables(@[aText])` (seq[Text]) AND `Renderables(iterator(): string)`
## /`Renderables(iterator(): aStructuralRenderable)` ALL compile (non-narrowing
## for `Optional[Iterable[RenderableType]]`; `iterator(): int` is rejected by
## the `T: RenderableType` constraint). `Lines._lines: List[Text]`
## (containers.py:70) → `lines*: seq[Text]`; the `__init__` param `lines:
## Iterable[Text] = ()` (containers.py:69) → THREE overloads — `openArray[Text]`
## (any seq/array of `Text`), a no-arg overload (the `()` default ⇒ empty) and
## `proc [T: Text](lines: iterator(): T {.closure.})` (the `Iterable` arm) —
## so `Lines()`, `Lines(@[aText])` AND `Lines(iterator(): Text)` all compile
## (`iterator(): int` rejected). `__iter__`→`items` closure iterator;
## `__getitem__`→`[]` overloads (int→`Text`, slice→`seq[Text]`);
## `__setitem__`→`[]=`; `__len__`→`len`; `__rich_console__`→`renderConsole`;
## `__rich_measure__`→`richMeasure`; `justify` keeps its name. `Lines.extend`
## (`lines: Iterable[Text]`, containers.py:105) → TWO overloads —
## `openArray[Text]` and `proc [T: Text](lines: iterator(): T {.closure.})`
## (non-narrowing for `Iterable[Text]`). The 3 Python `__getitem__` variants (2
## overloads + the union runtime impl containers.py:86-87) merge into the 2 Nim
## `[]` overloads (Nim dispatches by type, no union overload needed). Proc
## bodies are ports (`discard`).

import std/options

import richbase     # ConsoleHandle, ConsoleOptions, RenderResult, RenderableBase,
                    # RenderableType, JustifyMethod, OverflowMethod.
import measure      # Measurement.
import text         # Text.
import api_types    # RenderableValue.
import cells        # cellLen (containers.py:24 — Lines.justify center/right).

type
  Renderables* = ref object of RenderableBase
    ## rich containers.py:30-63 — `class Renderables`: a list subclass which
    ## renders its contents to the console. `ref object of RenderableBase`
    ## (so it satisfies `ConsoleRenderable`; Python `Renderables` has reference
    ## semantics). Fields mirror the `__init__` assignments (containers.py:36).
    renderables*: seq[RenderableValue]
      ## rich containers.py:36-37 — `self._renderables: List["RenderableType"]
      ## = (list(renderables) if renderables is not None else [])`
      ## (`List["RenderableType"]`; renamed `_renderables`→`renderables`;
      ## `seq[RenderableValue]`).

  Lines* = ref object of RenderableBase
    ## rich containers.py:66-167 — `class Lines`: a list subclass which can
    ## render to the console and justify/overflow its `Text` lines. `ref object
    ## of RenderableBase` (so it satisfies `ConsoleRenderable`; Python `Lines`
    ## has reference semantics). Fields mirror the `__init__` assignments
    ## (containers.py:70).
    lines*: seq[Text]
      ## rich containers.py:70-70 — `self._lines: List["Text"] = list(lines)`
      ## (`List[Text]`; renamed `_lines`→`lines`; `seq[Text]`).

proc initRenderables*(renderables: Option[seq[RenderableValue]] = none(seq[RenderableValue])): Renderables =
  ## rich containers.py:33-38 — `Renderables.__init__(self, renderables:
  ## Optional[Iterable["RenderableType"]] = None) -> None` (the `None`/Option
  ## overload): `self._renderables = list(renderables) if renderables is not
  ## None else []` (containers.py:36-37). Default `none(seq[RenderableValue])`
  ## is the `None` arm (`Renderables()` ⇒ empty). One of three overloads
  ## (Option/openArray/closure-iterator) covering
  ## `Optional[Iterable[RenderableType]]` non-narrowingly. body: allocate
  ## and copy the optional seq when present (containers.py:36-37).
  result = Renderables()
  if renderables.isSome:
    result.renderables = renderables.get

proc initRenderables*(renderables: openArray[RenderableValue]): Renderables =
  ## rich containers.py:33-38 — `Renderables.__init__(self, renderables:
  ## Optional[Iterable["RenderableType"]] = None) -> None` (the iterable
  ## overload): `self._renderables = list(renderables)` (containers.py:36).
  ## `Iterable[RenderableType]` → `openArray[RenderableType]` (the established
  ## `measure.nim` pattern; accepts `seq[string]`/`seq[Text]`/arrays). One of
  ## three overloads (Option/openArray/closure-iterator) covering
  ## `Optional[Iterable[RenderableType]]` non-narrowingly. body: allocate
  ## and convert each element via `toRenderableValue` (containers.py:36).
  result = Renderables()
  for r in renderables:
    result.renderables.add(r)

proc initRenderables*[T: RenderableType](renderables: iterator(): T {.closure.}): Renderables =
  ## rich containers.py:33-38 — `Renderables.__init__(self, renderables:
  ## Optional[Iterable["RenderableType"]] = None) -> None` (the closure-iterator
  ## overload): `self._renderables = list(renderables)` (containers.py:36).
  ## `Iterable[RenderableType]` accepts any iterator/generator; the
  ## closure-iterator overload (`T: RenderableType`) covers the `Iterable` arm
  ## that `openArray` cannot — `iterator(): string`/`iterator(): Text`/
  ## `iterator(): <a structural ConsoleRenderable>` all compile (non-narrowing),
  ## while `iterator(): int` is rejected by the `T: RenderableType` constraint
  ## (int is not `ConsoleRenderable`/`RichCast`/`str`). One of three overloads
  ## (Option/openArray/closure-iterator) covering
  ## `Optional[Iterable[RenderableType]]` non-narrowingly. body: drain the
  ## iterator, converting each yield via `toRenderableValue` (containers.py:36).
  result = Renderables()
  for r in renderables:
    result.renderables.add(r)

method renderConsole*(self: Renderables, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich containers.py:40-44 — `Renderables.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> RenderResult`: "Console render
  ## method to insert line-breaks" — `yield from self._renderables`
  ## (containers.py:44). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase.
  #
  # Faithful port of `yield from self._renderables` (containers.py:44): each
  # stored `RenderableValue` is yielded to the result by arm — a `string` →
  # `addString`, a `ConsoleRenderable`/`RichCast` → `addRenderable` (the
  # `RenderableValue.kind` dispatch). No explicit line-breaks are inserted
  # (matching `yield from`); the console's render pipeline separates the
  # yielded renderables.
  result = @[]
  for r in self.renderables:
    case r.kind
    of rvString:
      result.addString(r.textStr)
    of rvConsoleRenderable:
      result.addRenderable(r.consoleItem, rrkConsoleRenderable)
    of rvRichCast:
      result.addRenderable(r.castItem, rrkRichCast)

proc richMeasure*(self: Renderables, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich containers.py:46-57 — `Renderables.__rich_measure__(self, console:
  ## "Console", options: "ConsoleOptions") -> Measurement`: measure across
  ## all renderables — `Measurement(1, 1)` if empty else
  ## `Measurement(max(min), max(max))` (containers.py:49-57). The richbase
  ## `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim`. body: per-renderable `Measurement.get` dispatch
  ## (rvString→`Measurement.get` on the string; rvConsoleRenderable/
  ## rvRichCast→`Measurement(0, options.maxWidth)`, mirroring `Measurement.get`'s
  ## no-`__rich_measure__` fallback, cf. `console.nim`/`styled.nim`), then
  ## `max(minimum)`/`max(maximum)`; empty→`Measurement(1, 1)` (containers.py:49-57).
  if self.renderables.len == 0:
    result = Measurement(minimum: 1, maximum: 1)
  else:
    var mn = 0
    var mx = 0
    for r in self.renderables:
      let m = case r.kind
        of rvString:
          Measurement.get(console, options, r.textStr)
        of rvConsoleRenderable:
          Measurement(minimum: 0, maximum: options.maxWidth)
        of rvRichCast:
          Measurement(minimum: 0, maximum: options.maxWidth)
      mn = max(mn, m.minimum)
      mx = max(mx, m.maximum)
    result = Measurement(minimum: mn, maximum: mx)

proc append*(self: Renderables, renderable: RenderableValue) =
  ## rich containers.py:59-60 — `Renderables.append(self, renderable:
  ## "RenderableType") -> None`: `self._renderables.append(renderable)`. The
  ## faithful `RenderableType` typeclass param (richbase — structural +
  ## nominal renderables; `int` rejected). body: `add` triggers the
  ## `toRenderableValue` converter (string→`rvString`, `RenderableBase`→
  ## `rvConsoleRenderable`) (containers.py:60).
  self.renderables.add(renderable)

iterator items*(self: Renderables): RenderableValue {.closure.} =
  ## rich containers.py:62-63 — `Renderables.__iter__(self) ->
  ## Iterable["RenderableType"]`: `return iter(self._renderables)`
  ## (containers.py:63). Modelled as a `closure` iterator (a lazy view over the
  ## internal list, faithful to `iter(list)`). body: yield each stored
  ## `RenderableValue` (containers.py:63).
  for r in self.renderables:
    yield r

proc initLines*(lines: openArray[Text]): Lines =
  ## rich containers.py:69-70 — `Lines.__init__(self, lines: Iterable["Text"]
  ## = ()) -> None` (the iterable overload): `self._lines = list(lines)`
  ## (containers.py:70). `Iterable[Text]` → `openArray[Text]` (accepts
  ## `seq[Text]`/arrays). One of three overloads (openArray/no-arg/
  ## closure-iterator) covering `Iterable[Text]` non-narrowingly. body:
  ## allocate and materialize via `@lines` (containers.py:70).
  result = Lines()
  result.lines = @lines

proc initLines*(): Lines =
  ## rich containers.py:69-70 — `Lines.__init__(self, lines: Iterable["Text"]
  ## = ()) -> None` (the `()` default overload): `self._lines = list(())` ⇒
  ## `[]` (containers.py:70). `Lines()` ⇒ empty. One of three overloads
  ## (openArray/no-arg/closure-iterator). body: `Lines()` ⇒ empty `lines`
  ## (containers.py:70).
  result = Lines()

proc initLines*[T: Text](lines: iterator(): T {.closure.}): Lines =
  ## rich containers.py:69-70 — `Lines.__init__(self, lines: Iterable["Text"]
  ## = ()) -> None` (the closure-iterator overload): `self._lines = list(lines)`
  ## (containers.py:70). `Iterable[Text]` accepts any iterator/generator; the
  ## closure-iterator overload (`T: Text`) covers the `Iterable` arm that
  ## `openArray` cannot — `iterator(): Text` compiles (non-narrowing), while
  ## `iterator(): int` is rejected by the `T: Text` constraint. One of three
  ## overloads (openArray/no-arg/closure-iterator) covering `Iterable[Text]`
  ## non-narrowingly. body: drain the iterator into `lines` (containers.py:70).
  result = Lines()
  for l in lines:
    result.lines.add(l)

proc repr*(self: Lines): string =
  ## rich containers.py:72-73 — `Lines.__repr__(self) -> str`:
  ## `f"Lines({self._lines!r})"`. Overloads `system.repr` on the `Lines`
  ## receiver. body: `Lines([` + per-line `Text.repr` (delegates to
  ## `Text.__repr__` = `text({plain!r})`) + `])`, matching Python's
  ## `list.__repr__` calling each element's `__repr__` (containers.py:73).
  result = "Lines(["
  for i, line in self.lines:
    if i > 0:
      result.add(", ")
    result.add(line.repr)
  result.add("])")

iterator items*(self: Lines): Text {.closure.} =
  ## rich containers.py:75-76 — `Lines.__iter__(self) -> Iterator["Text"]`:
  ## `return iter(self._lines)` (containers.py:76). Modelled as a `closure`
  ## iterator (a lazy view over the internal list, faithful to `iter(list)`).
  ## body: yield each stored `Text` (containers.py:76).
  for l in self.lines:
    yield l

proc `[]`*(self: Lines, index: int): Text =
  ## rich containers.py:79-80 (+ union runtime impl containers.py:86-87) —
  ## `Lines.__getitem__(self, index: int) -> "Text"` (overload 1):
  ## `return self._lines[index]`. The int `[]` overload. body:
  ## `self.lines[index]` (containers.py:80).
  result = self.lines[index]

proc `[]`*(self: Lines, slice: HSlice[int, int]): seq[Text] =
  ## rich containers.py:83-84 (+ union runtime impl containers.py:86-87) —
  ## `Lines.__getitem__(self, index: slice) -> List["Text"]` (overload 2):
  ## `return self._lines[index]`. The slice `[]` overload (`HSlice[int,int]`
  ## matches `lines[a..b]`). body: `self.lines[slice]` (containers.py:84).
  result = self.lines[slice]

proc `[]=`*(self: Lines, index: int, value: Text) =
  ## rich containers.py:89-91 — `Lines.__setitem__(self, index: int, value:
  ## "Text") -> Lines`: `self._lines[index] = value; return self` (the Python
  ## `return self` chaining is not mirrored — Nim `[]=` is `void`). body:
  ## `self.lines[index] = value` (containers.py:90).
  self.lines[index] = value

proc len*(self: Lines): int =
  ## rich containers.py:93-94 — `Lines.__len__(self) -> int`:
  ## `return self._lines.__len__()`. Overloads `system.len` on the `Lines`
  ## receiver. body: `self.lines.len` (containers.py:94).
  result = self.lines.len

method renderConsole*(self: Lines, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich containers.py:96-100 — `Lines.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> RenderResult`: "Console render
  ## method to insert line-breaks" — `yield from self._lines`
  ## (containers.py:100). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase.
  #
  # Faithful port of `yield from self._lines` (containers.py:100) with the
  # per-task guidance to emit a `Segment("\n")` *between* consecutive lines:
  # each `Text` is yielded via `addRenderable` (the `ConsoleRenderable` arm),
  # and a `Segment("\n")` is inserted before every line except the first (N-1
  # separators for N lines). In CPython rich each `Text` carries its own
  # trailing `end="\n"`, so `yield from` already separates them; the Nim port
  # inserts the separators explicitly so `Lines` renders as distinct lines
  # even while `Text.renderConsole` is a stub.
  result = @[]
  for i, line in self.lines:
    if i > 0:
      result.addSegment(initSegment("\n"))
    result.addRenderable(line, rrkConsoleRenderable)

proc append*(self: Lines, line: Text) =
  ## rich containers.py:102-103 — `Lines.append(self, line: "Text") -> None`:
  ## `self._lines.append(line)`. body: `self.lines.add(line)`
  ## (containers.py:103).
  self.lines.add(line)

proc extend*(self: Lines, lines: openArray[Text]) =
  ## rich containers.py:105-106 — `Lines.extend(self, lines: Iterable["Text"])
  ## -> None` (the iterable overload): `self._lines.extend(lines)`
  ## (containers.py:106). `Iterable[Text]` → `openArray[Text]` (the
  ## established `measure.nim` pattern). One of two overloads
  ## (openArray/closure-iterator) covering `Iterable[Text]` non-narrowingly.
  ## body: `seq.add(openArray[T])` appends all (containers.py:106).
  self.lines.add(lines)

proc extend*[T: Text](self: Lines, lines: iterator(): T {.closure.}) =
  ## rich containers.py:105-106 — `Lines.extend(self, lines: Iterable["Text"])
  ## -> None` (the closure-iterator overload): `self._lines.extend(lines)`
  ## (containers.py:106). `Iterable[Text]` accepts any iterator/generator; the
  ## closure-iterator overload (`T: Text`) covers the `Iterable` arm that
  ## `openArray` cannot — `iterator(): Text` compiles (non-narrowing), while
  ## `iterator(): int` is rejected by the `T: Text` constraint. One of two
  ## overloads (openArray/closure-iterator) covering `Iterable[Text]`
  ## non-narrowingly. body: drain the iterator into `lines` (containers.py:106).
  for l in lines:
    self.lines.add(l)

proc pop*(self: Lines, index: int = -1): Text =
  ## rich containers.py:108-109 — `Lines.pop(self, index: int = -1) -> "Text"`:
  ## `return self._lines.pop(index)`. Default `-1` (last). body: wrap the
  ## (possibly negative) index, read the element, then `seq.delete` it —
  ## faithful to `list.pop`'s remove-and-shift (containers.py:109).
  let idx = if index < 0: self.lines.len + index else: index
  result = self.lines[idx]
  self.lines.delete(idx)

proc justify*(self: Lines, console: ConsoleHandle, width: int,
              justify: JustifyMethod = jmLeft, overflow: OverflowMethod = omFold) =
  ## rich containers.py:111-167 — `Lines.justify(self, console: "Console",
  ## width: int, justify: "JustifyMethod" = "left", overflow:
  ## "OverflowMethod" = "fold") -> None`: justify and overflow text to a given
  ## width — `left`/`center`/`right`/`full` branches (containers.py:117-167).
  ## `justify` default `"left"` → `jmLeft`; `overflow` default `"fold"` →
  ## `omFold`. body: `left`/`center`/`right` delegate to `Text.truncate`/
  ## `rstrip`/`padLeft`/`padRight` + `cells.cellLen` (containers.py:117-125);
  ## `full` deferred — needs `Text.split(" ")` → the unimplemented `text.Lines`
  ## forward handle (no `items`/`len`/`[]` API) for the word-redistribution
  ## loop (containers.py:128-167).
  case justify
  of jmDefault:
    # rich containers.py:117 — `"default"` falls through (no justification).
    discard
  of jmLeft:
    for line in self.lines:
      line.truncate(width, overflow = some(overflow), pad = true)
  of jmCenter:
    for line in self.lines:
      line.rstrip()
      line.truncate(width, overflow = some(overflow))
      line.padLeft((width - cellLen(line.plain)) div 2)
      line.padRight(width - cellLen(line.plain))
  of jmRight:
    for line in self.lines:
      line.rstrip()
      line.truncate(width, overflow = some(overflow))
      line.padLeft(width - cellLen(line.plain))
  of jmFull:
    # DEFERRED(text.Lines API): the `full` branch redistributes spaces across
    # `line.split(" ")` words (containers.py:128-167), but `Text.split` returns
    # the provisional `text.Lines` forward handle (an empty object with no
    # `items`/`len`/`[]` API), so the word loop can't be expressed. Wire when
    # `text.nim` switches `Lines` to `containers.Lines` and implements `split`.
    discard
