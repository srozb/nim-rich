## Port of `rich.scope` (rich/scope.py).
##
## `render_scope` renders python variables in a given scope as a `Panel`-ed
## `Table` of `key = Pretty(value)` rows (scope.py:14-73). It is a top-level
## function (the module's only public binding).
##
## Import graph (rich/scope.py:1-11): runtime sibling imports are
## `from collections.abc import Mapping` (scope.py:1, the `scope` param type),
## `from .highlighter import ReprHighlighter` (scope.py:4, body-only — @24),
## `from .panel import Panel` (scope.py:5, body-only — @56), `from .pretty
## import Pretty` (scope.py:6, body-only — @47), `from .table import Table`
## (scope.py:7, body-only — @26,28), `from .text import Text, TextType`
## (scope.py:8, body-only — `Text.assemble` @40 + the `title` type); `from
## typing import TYPE_CHECKING, Any, Optional, Tuple` (scope.py:2); under
## `TYPE_CHECKING` (scope.py:10) come `ConsoleRenderable`, `OverflowMethod`
## (`.console`, scope.py:11).
##
## wiring: `import std/[tables, options]` (`tables` for the
## `ScopeMapping` concept — its `pairs` iterator must be visible so the
## concept's `for k, v in m` resolves for `std/tables.Table`; `Option` for the
## `Optional[int]`/`Optional[OverflowMethod]` params); `import richbase`
## (`RenderableBase` — the `ConsoleRenderable` return; `OverflowMethod` — the
## `.console` TYPE_CHECKING import mapped to the richbase placeholder; `scope.py`
## does NOT import `segment`); `import panel` (`Panel`, `PanelTextOpt` — the
## `Optional[TextType]` handle for the `title` param, carried from `panel.nim`
## so the `Panel`↔`scope` boundary shares one `Optional[TextType]`); `import
## table` (`Table`); `import text` (`Text`, `TextType`). `ReprHighlighter`
## (scope.py:4) and `Pretty` (scope.py:6) are body-only deps;
## `highlighter.nim`/`pretty.nim` are not yet written (not in the 56 public
## modules written so far) and no signature needs them, so they are not imported
## (matching how `align.nim` treats body deps). `Panel`/`Table`/`Text` are body
## usages too but are imported (they are real scope.py imports and `PanelTextOpt`
## is needed for the `title` param). `console` types are `TYPE_CHECKING`-only —
## supplied via richbase placeholders.
##
## `scope: "Mapping[str, Any]"` (scope.py:14) → generic `M: ScopeMapping` (a
## [Nim-only] concept — see below). `Mapping` is STRUCTURAL in Python
## (`collections.abc.Mapping`: any object with `__getitem__`/`keys`/`__iter__`),
## and `Any` is the fully-unconstrained value type, so the Nim port must NOT
## freeze either the map type (to `std/tables.Table`) or the value type (to a
## single handle). `ScopeMapping` is the non-narrowing concept: any object `m`
## for which `for k, v in m` iterates with `string` keys (the value type `v` is
## unconstrained — the Python `Any`). This accepts `Table[string, int]`,
## `Table[string, JsonNode]`, `Table[string, MyCustomObject]`, a custom mapping
## with a `pairs` iterator, … — and rejects non-mappings (`string`, `int`) and
## non-`string`-keyed maps (`Table[int, int]`). The `rsAcceptKey(k: string)`
## helper is the key-type predicate (a bare `k is string` always compiles, so it
## does not reject — the helper proc forces a real `string`-vs-`k` type check;
## this is the same trick `table.RowStylesArg` uses with `rsAccept`). The former
## concrete `Table[string, JsonAny]` (which froze the value type to `JsonNode`
## AND the map type to `std/tables.Table`) is removed — no narrowing. `title:
## Optional[TextType] = None` (scope.py:16) → `PanelTextOpt` (from `panel.nim`,
## default `ptoNone` = `None`). `sort_keys: bool = True` → `sortKeys: bool =
## true`; `indent_guides: bool = False` → `indentGuides: bool = false`;
## `max_length`/`max_string`/`max_depth: Optional[int] = None` → `Option[int]`
## (`maxLen`/`maxStr`/`maxDepth`); `overflow: Optional["OverflowMethod"] = None`
## → `Option[OverflowMethod]`. Returns `"ConsoleRenderable"` → `RenderableBase`.
## Keyword-only after `scope` (Python `*`, scope.py:15). The proc body is a
##.

import std/[tables, options, strutils]

import richbase     # RenderableBase (ConsoleRenderable), OverflowMethod.
import panel        # Panel, PanelTextOpt (the Optional[TextType] handle).
import table        # Table.
import text         # Text, TextType.
import padding      # PaddingDimensions, pdPair (Panel.fit/Table.grid padding).
import highlighter  # Highlighter, ReprHighlighter (scope.py:24).
import pretty       # Pretty/initPretty (scope.py:47).

# [Nim-only] non-narrowing handle for `Mapping[str, Any]` (scope.py:14). The
# `scope` param is `Mapping[str, Any]` — structural map, unconstrained value.
# `ScopeMapping` is a concept: any `m` whose `for k, v in m` loop yields keys
# accepted by `rsAcceptKey(k: string)` (the value `v` is ignored, i.e. `Any`).
# The `rsAcceptKey` helper is essential — a bare `k is string` in the concept
# always compiles (so it never rejects); routing `k` through a real
# `proc rsAcceptKey(k: string): int` forces a genuine `string`-vs-key type
# check, so `Table[int, int]` is rejected while `Table[string, <anything>]`
# and custom string-keyed mappings are accepted. `tables` is imported above so
# `Table`'s `pairs` iterator is visible to the concept.
proc rsAcceptKey*(k: string): int =
  ## [Nim-only] key-type predicate for `ScopeMapping` — accepts a `string` key
  ## (the `Mapping[str, Any]` key type, scope.py:14). Routing the loop key
  ## through this proc (rather than a bare `k is string` concept check) is what
  ## makes `ScopeMapping` actually reject non-`string`-keyed maps.
  # Intentional no-op: this proc exists only to force the compile-time key-type
  # check performed by the `ScopeMapping` concept (see its doc); its return is
  # unused. Python `scope.py` has no counterpart.
  result = 0

type ScopeMapping* = concept m
  ## [Nim-only] non-narrowing handle for `Mapping[str, Any]` (scope.py:14) — the
  ## `scope` param type. A concept satisfied by any iterable mapping whose keys
  ## are `string`; the value type is UNCONSTRAINED (the Python `Any`), so
  ## `Table[string, int]`, `Table[string, JsonNode]`, `Table[string, MyObj]`,
  ## … and any custom mapping with a `pairs` iterator all compile, and
  ## non-mappings (`string`, `int`) and non-`string`-keyed maps (`Table[int,
  ## int]`) are rejected. This replaces the former narrowing to the concrete
  ## `Table[string, JsonAny]` (which froze both the map type and the value
  ## type). `rsAcceptKey` is the key predicate (see its doc).
  compiles((for k, v in m: discard rsAcceptKey(k)))

proc renderScope*[M: ScopeMapping](scope: M,
                  title: PanelTextOpt = default(PanelTextOpt),
                  sortKeys: bool = true, indentGuides: bool = false,
                  maxLen: Option[int] = none(int),
                  maxStr: Option[int] = none(int),
                  maxDepth: Option[int] = none(int),
                  overflow: Option[OverflowMethod] = none(OverflowMethod)): RenderableBase =
  ## rich scope.py:14-73 — `render_scope(scope: "Mapping[str, Any]", *,
  ## title: Optional[TextType] = None, sort_keys: bool = True, indent_guides:
  ## bool = False, max_length: Optional[int] = None, max_string:
  ## Optional[int] = None, max_depth: Optional[int] = None, overflow:
  ## Optional["OverflowMethod"] = None) -> "ConsoleRenderable"`: render python
  ## variables in a given scope — sort keys (special vars first), build a
  ## `Table.grid` of `key = Pretty(value)` rows, wrap in `Panel.fit` (scope.py:17-72).
  ## `scope: Mapping[str, Any]` → `M: ScopeMapping` (the non-narrowing concept —
  ## any string-keyed mapping, unconstrained value type = `Any`; accepts
  ## `Table[string, int]`/`Table[string, JsonNode]`/custom maps, rejects
  ## non-mappings and non-`string`-keyed maps — see `ScopeMapping`); `title:
  ## Optional[TextType] = None` → `PanelTextOpt` (default `ptoNone`);
  ## `sort_keys: bool = True` → `sortKeys = true`; `indent_guides: bool = False`
  ## → `indentGuides = false`; `max_length`/`max_string`/`max_depth:
  ## Optional[int] = None` → `Option[int]`; `overflow: Optional[OverflowMethod]
  ## = None` → `Option[OverflowMethod]`. Returns `ConsoleRenderable` →
  ## `RenderableBase`. Keyword-only after `scope` (Python `*`, scope.py:15).
  ## Body needs `ReprHighlighter` (scope.py:24) + `Table.grid`/
  ## `add_column`/`add_row` (scope.py:26,28,52) + `Text.assemble` (scope.py:40)
  ## + `Pretty` (scope.py:47) + `Panel.fit` (scope.py:56).
  # Build the `Table.grid` of `key = Pretty(value)` rows and wrap in `Panel.fit`
  # (scope.py:17-72). The highlighter/indent/max*/overflow kwargs feed `Pretty`.
  let highlighter = some[Highlighter](ReprHighlighter())
  let itemsTable = Table.grid(padding = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                              expand = false)
  itemsTable.addColumn(justify = jmRight)
  # DEFERRED(scope, Batch N): `sortKeys` needs materialising the concept-typed
  # mapping into a `seq[(string, V)]` (V is the unconstrained `Any` value type of
  # `M: ScopeMapping`) to sort by `(not key.startswith("__"), key.lower())`
  # (scope.py:30-33); the `ScopeMapping` concept guarantees `for k, v in m` but
  # not `[]` lookup, so items are added in the mapping's natural order for now.
  for key, value in scope:
    let styleName = if key.startsWith("__"): "scope.key.special" else: "scope.key"
    let keyText = Text.assemble((key, styleName), (" =", "scope.equals"))
    let pretty = initPretty(value, highlighter = highlighter,
                           indentGuides = indentGuides, maxLength = maxLen,
                           maxString = maxStr, maxDepth = maxDepth,
                           overflow = overflow)
    itemsTable.addRow(keyText, pretty)
  return Panel.fit(itemsTable, title = title, borderStyle = "scope.border",
                   padding = PaddingDimensions(kind: pdPair, pair: (0, 1)))
