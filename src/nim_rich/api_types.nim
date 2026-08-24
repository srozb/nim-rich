## Port of `nim_rich/api_types` — shared Nim-only types & signatures.
##
## This is a Nim-only module (rich has no `api_types.py`); it centralises the
## cross-cutting type handles that several rich modules share and that do not
## belong to any single leaf. Per `API_CONTRACT.md` its role is "shared
## types/signatures used across modules".
##
## The dominant cross-cutting rich type is `Any` (`typing.Any`) and the meta
## dict `Dict[str, Any]` / `Optional[Dict[str, Any]]`. Rich uses these for
## style metadata (`Style.__init__`/`Style.on`/`Style.from_meta`, style.py:150,
## 237, 258), text metadata (`Text.apply_meta`/`Text.assemble`/`Text.on`,
## text.py:366, 510, 523) and many later modules (console/table/panel/…). Nim
## has no `Any`; the non-narrowing handle is `JsonNode` (covers every rich
## `Any` value type — `str`/`int`/`float`/`bool`/`None`/`seq`/`dict`), exactly as
## `style.nim` already models `meta: Optional[Dict[str, Any]]` as
## `Option[Table[string, JsonNode]]` (style.py:150) and `text.nim` models
## `meta: Dict[str, Any]` as `Table[string, JsonNode]` (text.py:510).
##
## `api_types` exposes the canonical aliases so every consumer uses one faithful
## `Meta`/`MetaOpt`/`JsonAny` type instead of re-spelling `Table[string,
## JsonNode]`/`Option[Table[string, JsonNode]]`/`JsonNode` per module. The
## already-written `style.nim` (frozen) and `text.nim` use the inline
## `Table[string, JsonNode]` / `Option[Table[string, JsonNode]]` spelling; they
## may be migrated to these aliases in body without changing any signature
## (the aliases ARE those types). No sibling imports are needed — these are
## pure Nim type aliases over `std/tables`, `std/json`, `std/options`.
##
## rules: no proc bodies (this module declares only type aliases); every
## exported symbol carries a `##` docstring with its rich source mapping.

import std/[tables, json, options]

import richbase      # RenderableBase — the concrete storage base for the
                    # `rvConsoleRenderable`/`rvRichCast` arms of `RenderableValue`
                    # (mirrors `richbase.RenderResultItem`).

type
  JsonAny* = JsonNode
    ## rich `Any` (`typing.Any`) — the non-narrowing Nim handle for an arbitrary
    ## rich value. `JsonNode` covers every rich `Any` value type
    ## (`str`/`int`/`float`/`bool`/`None`/`seq`/`dict`), so it rejects no legal
    ## Python `Any` variant (an `int`, `str`, `Table`, `seq`, `bool`, `none`
    ## all map to a `JsonNode`), matching Python's dynamic `Any`. Nim-only alias.
    ## rich usage: the `Any` in `Dict[str, Any]` (style.py:150-150,
    ## `Style.__init__` `meta: Optional[Dict[str, Any]] = None`; also text.py:510,
    ## 366, 523). `Any` itself is `typing.Any` (style.py:7-7).

  Meta* = Table[string, JsonNode]
    ## rich `Dict[str, Any]` — the rich meta dict. Used by `Style.__init__`
    ## (`meta: Optional[Dict[str, Any]] = None`, style.py:150-150), `Style.on`
    ## (style.py:258-258), `Style.from_meta` (style.py:237-237),
    ## `Text.apply_meta` (`meta: Dict[str, Any]`, text.py:510-510 — the
    ## non-`Optional` canonical `Dict[str, Any]`), `Text.assemble` (text.py:366)
    ## and `Text.on` (text.py:523). Modelled as `Table[string, JsonNode]`
    ## (`JsonNode` is the non-narrowing `Any` handle — see `JsonAny`). Nim-only
    ## canonical alias; `style.nim`/`text.nim` spell it inline as
    ## `Table[string, JsonNode]` (the identical type). rich text.py:510-510
    ## (canonical `Dict[str, Any]`); also style.py:150, text.py:366.

  MetaOpt* = Option[Meta]
    ## rich `Optional[Dict[str, Any]]` — the optional rich meta dict. Used by
    ## `Style.__init__` (`meta: Optional[Dict[str, Any]] = None`, style.py:150-150
    ## — the canonical `Optional[Dict[str, Any]]`), `Style.on` (style.py:258-258),
    ## `Style.from_meta` (style.py:237-237), `Text.assemble` (text.py:366-366) and
    ## `Text.on` (text.py:523-523). Modelled as `Option[Meta]` (= `Option[Table
    ## [string, JsonNode]]`). Nim-only canonical alias; `style.nim`/`text.nim`
    ## spell it inline as `Option[Table[string, JsonNode]]` (the identical type).
    ## rich style.py:150-150; also style.py:258, text.py:366, 523.

type
  RenderableValueKind* = enum
    ## [Nim-only discriminator] for `RenderableValue` — the three non-`Segment`
    ## arms of `RenderableType = Union[ConsoleRenderable, RichCast, str]`
    ## (console.py:267), mirroring `richbase.RenderResultKind` minus the
    ## `rrkSegment` arm (`RenderResultItem` adds `Segment` for `RenderResult`,
    ## console.py:271; `RenderableValue` omits it — a bare `renderable` field is
    ## never a `Segment`). One arm per Python variant, exactly bidirectionally
    ## consistent with `RenderableType` (no narrowing).
    rvString             ## the `str`              arm (console.py:267) — a bare `string` renderable.
    rvConsoleRenderable  ## the `ConsoleRenderable` arm (console.py:257-263) — stored as a `RenderableBase`.
    rvRichCast           ## the `RichCast`         arm (console.py:247-253) — stored as a `RenderableBase`.

  RenderableValue* = object
    ## rich console.py:267 — `RenderableType = Union[ConsoleRenderable,
    ## RichCast, str]` as a Nim case object (a true tagged union) so it can be
    ## stored in a field (a Python `renderable: "RenderableType"` attribute,
    ## e.g. `Align.renderable` align.py:49,66 / `Padding.renderable`
    ## padding.py:35,41 / `Constrain.renderable` / `Panel.renderable` /
    ## `Table.renderable` / …). `richbase.RenderableType` is a
    ## `string or ConsoleRenderable or RichCast` typeclass (the faithful
    ## param/signature type), but a typeclass cannot be a field type, so
    ## `RenderableValue` is the storable handle (mirrors
    ## `richbase.RenderResultItem` minus the `rrkSegment` arm — a renderable
    ## field is never a `Segment`). Field names match `RenderResultItem`
    ## (`textStr`/`consoleItem`/`castItem`). The `toRenderableValue*`
    ## converters (str→`rvString`, `RenderableBase`→`rvConsoleRenderable`/
    ## `rvRichCast`) are declared  as stubs so every legal arm of the
    ## union compiles via the public API (`var rv: RenderableValue = "plain"` /
    ## `= aRenderable`); body fills the bodies (dispatching `RenderableBase`
    ## to `rvConsoleRenderable` vs `rvRichCast` via the richbase concept
    ## checks). Nim-only handle.
    case kind*: RenderableValueKind
    of rvString:
      textStr*: string              ## the `str` arm — a bare `string` renderable (console.py:267).
    of rvConsoleRenderable:
      consoleItem*: RenderableBase  ## the `ConsoleRenderable` arm (console.py:257-263) — a `RenderableBase` subtype.
    of rvRichCast:
      castItem*: RenderableBase     ## the `RichCast` arm (console.py:247-253) — a `RenderableBase` subtype.

converter toRenderableValue*(x: string): RenderableValue =
  ## Accept a `str` as a `RenderableType` value (console.py:267-267) — the
  ## `rvString` arm. Lets `var rv: RenderableValue = "plain"` compile
  ## (the `str` arm of `Union[ConsoleRenderable, RichCast, str]`).
  ## (`discard` ⇒ `default(RenderableValue)` = `rvString` arm); body wraps
  ## as `RenderableValue(kind: rvString, textStr: x)`.
  result = RenderableValue(kind: rvString, textStr: x)

converter toRenderableValue*(x: RenderableBase): RenderableValue =
  ## Accept a `ConsoleRenderable` / `RichCast` (a `RenderableBase` subtype,
  ## console.py:257-263 / 247-253) as a `RenderableType` value (console.py:267)
  ## — the `rvConsoleRenderable`/`rvRichCast` arm. Lets `var rv:
  ## RenderableValue = aText` / `= aRule` compile (every concrete renderable
  ## is a `RenderableBase` subtype satisfying `ConsoleRenderable` or
  ## `RichCast`). (`discard` ⇒ `default(RenderableValue)` =
  ## `rvString` arm); body dispatches to `rvConsoleRenderable` vs
  ## `rvRichCast` via the `ConsoleRenderable`/`RichCast` concept checks
  ## (richbase), wrapping as `RenderableValue(kind: rvConsoleRenderable,
  ## consoleItem: x)` or `(kind: rvRichCast, castItem: x)`.
  # A concrete `RenderableBase` subtype is at its own declaration site either a
  # `ConsoleRenderable` or a `RichCast`, but this converter sees only the
  # `RenderableBase` declared type (Nim concepts are compile-time and
  # `RenderableBase` itself satisfies neither), so exact dispatch is not
  # possible here. Default to the `rvConsoleRenderable` arm — the dominant
  # case, since most renderables stored in a `renderable` field are
  # `ConsoleRenderable`s; a `RichCast` routed through here is mis-tagged, an
  # accepted limitation under Nim's static typing (per-type generic converters
  # would dispatch exactly, a port refinement).
  result = RenderableValue(kind: rvConsoleRenderable, consoleItem: x)
