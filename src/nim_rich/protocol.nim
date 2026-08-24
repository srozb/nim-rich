## Nim port of `rich.protocol` (rich/protocol.py).
##
## The renderable protocol helpers: `is_renderable` (protocol.py:9) and
## `rich_cast` (protocol.py:18). `rich.console`/`rich.constrain`/`rich.table`
## consume `is_renderable`/`rich_cast` (e.g. constrain.py:8). `protocol.py` has
## no `__all__`, so both non-underscore top-level names are public; the
## underscore-prefixed `_GIBBERISH` (protocol.py:6) is private.
##
## Import graph (rich/protocol.py:1-4): `from typing import Any, cast, Set,
## TYPE_CHECKING` and `from rich.console import RenderableType` under
## `TYPE_CHECKING` (protocol.py:4). The only rich sibling dep is `RenderableType`
## (`ConsoleRenderable or RichCast or string`, the return of `rich_cast`), which
## lives in `richbase` (it was extracted there to break the `segment`↔`console`
## cycle). `Any`/`cast`/`Set` are typing-only and have no runtime Nim equivalent
## needed for the signatures (the non-narrowing `Any` is modelled as a generic
## `T`, see below).
##
## wiring (this file): `import richbase` for `RenderableType`. The two
## `Any`-typed params (`check_object: Any`, `renderable: object`) are modelled as
## generic `T` params — non-narrowing, so every legal Python variant compiles
## (`isRenderable("x")`, `isRenderable(5)`, `isRenderable(obj)`; `richCast(o)`),
## exactly as `style.nim` models `__eq__(self, other: Any)` as a generic
## `proc `==`*[T](a: Style, b: T): bool`. Proc bodies are ported (isRenderable/
## richCast implement protocol.py:9-41).

import richbase   # RenderableType — rich_cast return (console.py:267).

proc isRenderable*[T](checkObject: T): bool =
  ## rich protocol.py:9-15 — `is_renderable(check_object: Any) -> bool`: true if
  ## `check_object` is a `str` or has `__rich__`/`__rich_console__`
  ## (protocol.py:11-14). `check_object: Any` modelled as a generic `T`
  ## (non-narrowing — every Python variant compiles), matching how `style.nim`
  ## models `__eq__(other: Any)`. (body `discard` ⇒ returns `false`,
  ## the default `bool`).
  when T is string:
    result = true
  elif T is ConsoleRenderable:
    result = true
  elif T is RichCast:
    result = true
  else:
    result = false

proc richCast*[T](renderable: T): RenderableType =
  ## rich protocol.py:18-41 — `rich_cast(renderable: object) -> "RenderableType"`:
  ## recursively call `__rich__` (guarding against infinite loops via a visited
  ## `Set[type]`, protocol.py:28-31; objects claiming all attrs → `repr`,
  ## protocol.py:32-33). `renderable: object` (Python root) modelled as a generic
  ## `T` (non-narrowing); return `RenderableType` (richbase:
  ## `ConsoleRenderable or RichCast or string`, console.py:267).
  ## (body `discard` ⇒ returns `default(RenderableType)`).
  # Faithful port of protocol.py:18-41. Python dynamically loops `while
  # hasattr(renderable, "__rich__")` calling `__rich__` (here `richCast()`) and
  # guarding against cycles via a `Set[type]`. Nim is statically typed, so the
  # loop is resolved at compile time per instantiation: a `str` or
  # `ConsoleRenderable` (no `__rich__`) is returned as-is (the Python loop body
  # never runs); a `RichCast` is cast once via `richCast()` (the dominant case;
  # the concrete `richCast` recurses where the returned type is itself a
  # `RichCast`). Objects claiming all attrs (the `_GIBBERISH` guard,
  # protocol.py:32-33) have no Nim analogue under static typing.
  when T is string:
    result = renderable
  elif T is RichCast:
    result = renderable.richCast()
  else:
    result = renderable
