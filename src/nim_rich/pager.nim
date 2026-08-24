## Nim port of `rich.pager` (rich/pager.py, 34 lines).
##
## `Pager` is the abstract base for "pagers" (rich/pager.py:5-15). Python's
## `SystemPager(Pager)` (pager.py:17-26) — the concrete pager that delegates to
## the system pager via `pydoc.pager` (pager.py:20-25) — is NOT ported (removed
## in N1: zero callers); the Nim keeps only the abstract `Pager` base.
## `Console.pager` (console.py:1113) wraps a `PagerContext` around a `Pager`;
## `PagerContext.__exit__` calls `pager.show(content)` (console.py:396). The
## `Pager` ABC is consumed only as a value held by `console.PagerContext.pager`
## (console.py:373) — it is NOT itself a console renderable (no
## `__rich_console__`), so it is modelled as a plain `ref object of RootObj`,
## not a `RenderableBase`.
##
## Import graph (rich/pager.py:1-2): runtime sibling imports are `from abc
## import ABC, abstractmethod` (pager.py:1) and `from typing import Any`
## (pager.py:2). BOTH are Python stdlib — `abc.ABC`/`abstractmethod` model the
## abstract base/method (Nim has no `ABC` base; the abstract `show` is a
## documented base proc that subclasses override) and `Any` is the return of the
## private `_pager` helper. ZERO rich sibling imports at runtime. The
## `from .__main__ import make_test_card` / `from .console import Console`
## (pager.py:29-30) are `__main__`-only (demo) — not ported.
##
## NOTE on the dual `Pager` export: `console.nim` (frozen,) already
## declares a PROVISIONAL `Pager* = ref object of RootObj` placeholder
## (console.nim:206) for its `PagerContext.pager: Pager` field, because
## `pager.nim` had not yet been written. THIS module now declares the REAL
## `Pager` (the faithful port of `rich.pager.Pager`). Both are public (`*`)
## and the umbrella `export`s both `console` and `pager`, so `Pager` is
## reachable via two module paths — a lazy ambiguous re-export, exactly like
## the dual `EmojiVariant` (text.nim vs emoji.nim) that already compiles green
##: Nim resolves the ambiguity only at a bare `Pager` use site,
## and neither the umbrella nor the `nim_rich` binary references bare `Pager`.
## body reconciles by dropping `console.nim`'s placeholder and importing the
## real `pager.Pager` (the contract-sanctioned removal by name), exactly as
## `live_render.nim`'s `Control` placeholder will yield to `control.Control`.
##
## `Pager(ABC)` → `ref object of RootObj` (the `ABC` base is modelled by a
## documented base `show` proc subclasses override; Nim has no `ABC`). `show`
## (pager.py:9-14, `@abstractmethod`) → a base proc `show*` (subclasses
## override). `SystemPager(Pager)` (pager.py:17-26), `_pager(self, content) ->
## Any` (pager.py:20-21, the `pydoc.pager` delegation) and the overriding
## `show(self, content)` (pager.py:23-25) are NOT ported — `SystemPager`/
## `privatePager`/`initSystemPager` were removed in N1 (zero callers). The base
## `show` body is a genuine no-op (faithful to Python's `@abstractmethod` body =
## docstring); subclasses override it.


type
  Pager* = ref object of RootObj
    ## rich pager.py:5-15 — `class Pager(ABC)`: the abstract base for pagers.
    ## `ref object of RootObj` (the `ABC` base is modelled by a documented base
    ## `show` proc that subclasses override — Nim has no `ABC`/`abstractmethod`;
    ## the abstract contract is enforced by documentation, not the type
    ## system). NOT a `RenderableBase` — a `Pager` is never rendered to the
    ## console; it is only held by `console.PagerContext.pager` (console.py:373)
    ## and invoked via `show(content)` in `PagerContext.__exit__` (console.py:396).

proc show*(self: Pager, content: string) =
  ## rich pager.py:9-14 — `Pager.show(self, content: str) -> None`
  ## (`@abstractmethod` pager.py:8): show `content` in the pager. The base
  ## declaration; `SystemPager` overrides it. Nim has no `abstractmethod`, so
  ## the abstract contract is documented (a base `Pager` should not be
  ## instantiated directly). The base body is a genuine no-op (Python
  ## `@abstractmethod` body is just the docstring).
  discard "abstract base method; subclasses override"
