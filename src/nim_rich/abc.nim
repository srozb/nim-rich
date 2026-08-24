## Port of `rich.abc` (rich/abc.py).
##
## `RichRenderable(ABC)` (abc.py:4-19): an abstract base class checked
## *structurally* (not by inheritance) via `__subclasshook__` (abc.py:11-14),
## which returns `True` when the object has `__rich_console__` OR `__rich__`.
## `rich.pretty` imports it (`from .abc import RichRenderable`, pretty.py:42);
## its intended use is the `isinstance(my_object, RichRenderable)` guard
## (abc.py:1-9). Note there is no need to extend this class — it is a protocol
## check (abc.py:2-6).
##
## Import graph (rich/abc.py:1): runtime import is `from abc import ABC`
## (abc.py:1); `from rich.text import Text` @ abc.py:22 is `__main__`-only.
## ZERO rich sibling imports at runtime. The Nim stub needs `richbase` only to
## name the two arms of the `__subclasshook__` check: `__rich_console__` is
## `richbase.ConsoleRenderable` (richbase.py mirror of console.py:257-263) and
## `__rich__` is `richbase.RichCast` (mirror of console.py:247-253).
##
## `RichRenderable(ABC)` with a structural `__subclasshook__` has no Nim
## inheritance analogue (Nim's `isinstance` is the `x is T` concept check); it
## is mirrored as a structural `concept` that a type satisfies iff it is a
## `ConsoleRenderable` OR a `RichCast` — exactly `__rich_console__` OR
## `__rich__` (abc.py:13). Concepts compose with `or` (verified), so
## `RichRenderable = concept x: x is ConsoleRenderable or x is RichCast`
## compiles and accepts a type carrying either arm. This is the faithful
## non-narrowing mirror (every legal rich renderable — `Console`, `Text`,
## `Rule`, a bare `str`-with-`__rich__`, … — satisfies exactly one arm and so
## satisfies `RichRenderable`).

import richbase      # ConsoleRenderable, RichCast — the two __subclasshook__ arms.

type
  RichRenderable* = concept x
    ## rich abc.py:4-19 — `class RichRenderable(ABC)`: abstract base checked
    ## structurally via `__subclasshook__` (abc.py:11-14), which returns
    ## `hasattr(other, "__rich_console__") or hasattr(other, "__rich__")`.
    ## Mirrored as a Nim `concept` that a type satisfies iff it is a
    ## `ConsoleRenderable` (the `__rich_console__` arm, console.py:257-263) OR
    ## a `RichCast` (the `__rich__` arm, console.py:247-253) — exactly the OR
    ## in the Python `__subclasshook__`. A type carrying either arm is a
    ## `RichRenderable`; `isinstance(o, RichRenderable)` ↔ `o is RichRenderable`
    ## (Nim concept check). Non-narrowing: every legal rich renderable
    ## satisfies exactly one arm.
    x is ConsoleRenderable or x is RichCast

discard
