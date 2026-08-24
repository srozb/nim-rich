## Port of `rich.layout` (rich/layout.py).
##
## `Layout` divides a fixed rectangular region into rows/columns of sub-layouts
## (each a renderable or a further split), managed via `Splitter`s and a
## `Region`/`LayoutRender` map.
##
## Import graph (layout.py:1-21): stdlib (`abc.ABC`/`abstractmethod`,
## `itertools.islice`, `operator.itemgetter`, `threading.RLock`, `typing`,
## layout.py:1-10) → `std/locks` (`RLock`→`Lock`), `std/tables` (`Dict`→`Table`,
## the `RegionMap`/`RenderMap`), `std/options` (`Optional`→`Option`),
## `std/hashes` (`hash` for the `Layout`-keyed tables — refs have no default
## hash, so a local `hash(Layout)` is defined below). `from ._ratio import
## ratio_resolve` (layout.py:12) → `ratio` (body-only in `RowSplitter.divide`/
## `ColumnSplitter.divide`; `ratioResolve`, body). `from .align import
## Align` (layout.py:13) → `align` (body-only in `_Placeholder.__rich_console__`,
## body). `from .console import Console, ConsoleOptions, RenderableType,
## RenderResult` (layout.py:14) → supplied by `segment`. `from .highlighter
## import ReprHighlighter` (layout.py:15) → `highlighter` (the
## `_Placeholder.highlighter` class attr). `from .panel import Panel`
## (layout.py:16) → `panel` (body-only in `_Placeholder.__rich_console__`,
## body). `from .pretty import Pretty` (layout.py:17) → `pretty` (body-only
## in `_Placeholder.__rich_console__`/`Layout.tree`, body). `from .region
## import Region` (layout.py:18) → `region`. `from .repr import Result,
## rich_repr` (layout.py:19) → `repr` (`Result` for `Layout.__rich_repr__`;
## `@rich_repr`→the `richRepr` proc). `from .segment import Segment`
## (layout.py:20) → `segment`. `from .style import StyleType` (layout.py:21) →
## `style`. `if TYPE_CHECKING: from rich.tree import Tree` (layout.py:23) →
## `tree` (the `Layout.tree` property return type; also a runtime local import
## inside the property, layout.py:158-181).
##
## Faithfulness: `LayoutRender` (layout.py:26-31, `NamedTuple`) → named tuple
## `tuple[region: Region, render: seq[seq[Segment]]]`. `RegionMap = Dict[Layout,
## Region]` / `RenderMap = Dict[Layout, LayoutRender]` (layout.py:33-34) →
## `Table[Layout, Region]` / `Table[Layout, LayoutRender]` (Nim refs have no
## default `hash`, so `hash(Layout)` is defined below to hash the ref pointer —
## identity equality, matching Python's `dict` id-keying). `LayoutError/
## NoSplitter` (layout.py:37-43, `Exception`) → `object of CatchableError` /
## `object of LayoutError`. `Splitter` (layout.py:46-72, `ABC`) → `ref object of
## RootObj` with `name: str` class attr → `name*: string` field; `RowSplitter`/
## `ColumnSplitter` (layout.py:74-103) → subclasses (the `name`="row"/"column"
## class attrs are documented; the `splitters = {"row": RowSplitter, "column":
## ColumnSplitter}` class-attr dict, layout.py:117, is a body name→factory
## dispatch). `_Placeholder` (layout.py:106-135, private) → private `Placeholder`
## (no `*`); its `highlighter = ReprHighlighter()` class attr → a per-instance
## `highlighter: ReprHighlighter` field (body inits it, or a module-level
## shared instance). `@rich_repr class Layout` (layout.py:106-216) → `ref object
## of RenderableBase` (renderable via `__rich_console__`, no `JupyterMixin`) +
## `richRepr` proc.
##
## `Layout.__init__(renderable: Optional[RenderableType] = None, *, name:
## Optional[str] = None, size: Optional[int] = None, minimum_size: int = 1,
## ratio: int = 1, visible: bool = True)` (layout.py:121-135): `renderable:
## Optional[RenderableType]` → `Option[RenderableValue] = none(RenderableValue)`
## (the `live.nim` pattern); the keyword-only group keeps its order. Fields:
## public `size`/`minimumSize`/`ratio`/`name`/`visible`/`splitter`; private
## `_renderable`→`renderableVal`, `_children`→`childrenList`,
## `_render_map`→`renderMap`, `_lock`→`lockField`. `split(splitter: Union[
## Splitter, str] = "column")` (layout.py:184-201): `Union[Splitter, str]` → the
## `SplitterArg = Splitter or string` typeclass with default `"column"`. The
## varargs `*layouts: Union[Layout, RenderableType]` (layout.py:184) →
## `openArray[RenderableValue]` (Nim varargs must be last, but `splitter`
## follows — the `Screen.nim`/`Renderables` translation; `Union[Layout,
## RenderableType]` collapses to `RenderableType` since `Layout` is one). The
## `add_split`/`split_row`/`split_column` varargs are last → `varargs[
## RenderableValue]`. `__getitem__` → `` `[]` ``, `__rich_repr__`→`richRepr`,
## `__rich_console__`→`renderConsole`; properties `renderable`/`children`/`map`/
## `tree` → procs; `_make_region_map`→`makeRegionMap` (private). Proc bodies are
## `discard` (port)` = nil ref / empty seq / "").

import std/hashes
import std/locks
import std/options
import std/algorithm
import std/tables
import std/json

import segment       # richbase (RenderableBase, ConsoleHandle, ConsoleOptions,
                     # RenderResult, RenderableType, Segment) — re-exported.
import region        # Region — the LayoutRender.region field + divide region arg.
import style         # StyleType — the _Placeholder style param.
import text          # StyleValue — the _Placeholder.style field handle.
import api_types     # RenderableValue — the _renderable field + renderable param.
import highlighter   # ReprHighlighter — the _Placeholder.highlighter field.
import repr          # Result — the Layout.__rich_repr__ return type.
import tree           # Tree — the Layout.tree property return type.
import ratio         # ratioResolve + Edge — RowSplitter.divide/ColumnSplitter.divide (body).
import table          # Table.grid/addRow → the `tree` summary grid (layout.py:165).
import pretty         # initPretty → the `tree` node text `Pretty(layout)` (layout.py:169).
import styled         # initStyled → the invisible branch `Styled(Pretty(layout), "dim")` (layout.py:168).
import padding        # PaddingDimensions/pdQuad → `Table.grid(padding=(0,1,0,0))` (layout.py:165).
import console        # Console — the ConsoleHandle→Console downcast in render/refreshScreen
                     # (renderLines/height/options/updateScreenLines are on Console, not
                     # ConsoleHandle). Acyclic: no module in console's import tree imports layout.

type
  LayoutRender* = tuple[region: Region, render: seq[seq[Segment]]]
    ## rich layout.py:26-31 — `class LayoutRender(NamedTuple)`: an individual
    ## layout render. `region: Region` (layout.py:29) + `render: List[List[
    ## Segment]]` (layout.py:30) → `seq[seq[Segment]]`. A named tuple (value
    ## type, matching `NamedTuple`).

  RegionMap* = tables.Table[Layout, Region]
    ## rich layout.py:33 — `RegionMap = Dict["Layout", Region]`: a map of
    ## `Layout`→`Region` (built by `_make_region_map`). `Table[Layout, Region]`
    ## (refs keyed by identity via the `hash(Layout)` below).

  RenderMap* = tables.Table[Layout, LayoutRender]
    ## rich layout.py:34 — `RenderMap = Dict["Layout", LayoutRender]`: a map of
    ## `Layout`→`LayoutRender` (the last render, `Layout.map`). `Table[Layout,
    ## LayoutRender]`.

  LayoutError* = object of CatchableError
    ## rich layout.py:37-38 — `class LayoutError(Exception)`: layout-related
    ## error. `Exception` → `CatchableError`.

  NoSplitter* = object of LayoutError
    ## rich layout.py:41-42 — `class NoSplitter(LayoutError)`: requested splitter
    ## does not exist (raised by `split`, layout.py:199).

  Splitter* = ref object of RootObj
    ## rich layout.py:46-72 — `class Splitter(ABC)`: base class for a splitter.
    ## `ref object of RootObj` (Nim has no abstract classes; `getTreeIcon`/
    ## `divide` are stub procs). `name: str = ""` class attr (layout.py:48) →
    ## `name*: string` field.
    name*: string
      ## layout.py:48 — `Splitter.name: str = ""` (class attr; "row" for
      ## `RowSplitter`, "column" for `ColumnSplitter`).

  RowSplitter* = ref object of Splitter
    ## rich layout.py:74-87 — `class RowSplitter(Splitter)`: split a region into
    ## rows (`name = "row"`, `get_tree_icon`→`"[layout.tree.row]⬌"`,
    ## layout.py:79-80). No extra fields.

  ColumnSplitter* = ref object of Splitter
    ## rich layout.py:89-103 — `class ColumnSplitter(Splitter)`: split a region
    ## into columns (`name = "column"`, layout.py:94-95). No extra fields.

  SplitterArg* = Splitter or string
    ## rich layout.py:184 — `splitter: Union[Splitter, str]`: the `split`
    ## splitter arg, accepting a `Splitter` instance or a name string. A
    ## typeclass (like `style.StyleType = string or Style`); default `"column"`.

  Layout* = ref object of RenderableBase
    ## rich layout.py:106-216 — `@rich_repr class Layout`: a renderable to
    ## divide a fixed height into rows/columns. `ref object of RenderableBase`
    ## (renderable via `__rich_console__`; no `JupyterMixin`). Fields mirror the
    ## `__init__` assignments (layout.py:127-135): public attrs keep `*`;
    ## private `_`-prefixed attrs are renamed (no `*`).
    renderableVal: RenderableValue
      ## layout.py:127 — `self._renderable = renderable or _Placeholder(self)`
      ## (private `_renderable`→`renderableVal`; a `RenderableValue` — either the
      ## passed renderable or a `Placeholder`, built in body).
    size*: Option[int]
      ## layout.py:128 — `self.size = size` (`Optional[int]`; optional fixed size).
    minimumSize*: int
      ## layout.py:129 — `self.minimum_size = minimum_size` (`int`, default 1).
    ratio*: int
      ## layout.py:130 — `self.ratio = ratio` (`int`, default 1).
    name*: Option[string]
      ## layout.py:131 — `self.name = name` (`Optional[str]`; optional id).
    visible*: bool
      ## layout.py:132 — `self.visible = visible` (`bool`, default True).
    splitter*: Splitter
      ## layout.py:133 — `self.splitter = self.splitters["column"]()` (a
      ## `Splitter`; default a `ColumnSplitter`, built in body).
    childrenList: seq[Layout]
      ## layout.py:134 — `self._children: List[Layout] = []` (private
      ## `_children`→`childrenList`; the sub-layouts).
    renderMap: RenderMap
      ## layout.py:135 — `self._render_map: RenderMap = {}` (private
      ## `_render_map`→`renderMap`; the last render's `LayoutRender` map).
    lockField: Lock
      ## layout.py:134 — `self._lock = RLock()` (private `_lock`→`lockField`;
      ## `threading.RLock`→`std/locks.Lock`; guards `update`/`render`/

  Placeholder = ref object of RenderableBase
    ## rich layout.py:106-135 — `class _Placeholder` (private): an internal
    ## renderable used as a `Layout` placeholder. `ref object of RenderableBase`
    ## (renderable via `__rich_console__`). Private (Python `_Placeholder`
    ## underscore) — no `*`. Fields mirror `__init__` (layout.py:113-114) + the
    ## `highlighter` class attr (layout.py:108).
    layout: Layout
      ## layout.py:113 — `self.layout = layout` (the owning `Layout`).
    styleVal: StyleValue
      ## layout.py:114 — `self.style = style` (`Union[str, Style]`; the
      ## `text.StyleValue` case object). Renamed `style`→`styleVal` to avoid
      ## the `style` import clash.
    highlighter: ReprHighlighter
      ## layout.py:108 — `highlighter = ReprHighlighter()` (class attr →
      ## per-instance field; body inits it, or uses a module-level shared
      ## `ReprHighlighter`).

proc hash*(x: Layout): Hash = hash(cast[pointer](x))
  ## `hash` for `Layout`-keyed `Table`s (`RegionMap`/`RenderMap`). Nim refs have
  ## no default `hash`; this hashes the ref pointer (identity equality, matching
  ## Python's `dict` id-keying). Exported so consumers of `RenderMap`/
  ## `RegionMap` can build their own `Table[Layout, X]`.

proc getTreeIcon*(self: Splitter): string =
  ## rich layout.py:54-58 — `Splitter.get_tree_icon(self) -> str` (`@abstractmethod`):
  ## the icon (emoji) used in `Layout.tree`. Abstract base: subclasses override
  ## (`RowSplitter`/`ColumnSplitter`); the body is a genuine no-op (`discard`).
  discard

proc divide*(self: Splitter, children: openArray[Layout],
             region: Region): seq[(Layout, Region)] =
  ## rich layout.py:60-71 — `Splitter.divide(self, children: Sequence[Layout],
  ## region: Region) -> Iterable[Tuple[Layout, Region]]` (`@abstractmethod`):
  ## divide `region` amongst `children`. Returns `seq[(Layout, Region)]`
  ## (a generator → seq for the stub). Abstract base: subclasses override
  ## (`RowSplitter`/`ColumnSplitter`); the body is a genuine no-op (`discard`).
  discard

proc getTreeIcon*(self: RowSplitter): string =
  ## rich layout.py:79-80 — `RowSplitter.get_tree_icon(self) -> str`: return
  ## `"[layout.tree.row]⬌"`. body.
  result = "[layout.tree.row]⬌"

proc divide*(self: RowSplitter, children: openArray[Layout],
             region: Region): seq[(Layout, Region)] =
  ## rich layout.py:82-86 — `RowSplitter.divide(...)`: split `region` into rows
  ## via `ratio_resolve(width, children)` (layout.py:83-85). Each child `Layout`
  ## is duck-typed as an `Edge` (it has `size`/`ratio`/`minimum_size`), so the
  ## children are adapted to a `seq[Edge]` before `ratioResolve`. body.
  ## Returns `seq[(Layout, Region)]`.
  let (x, y, width, height) = region
  var edges: seq[Edge] = @[]
  for i in 0 ..< children.len:
    let child = children[i]
    edges.add(Edge(size: child.size, ratio: child.ratio,
                   minimumSize: child.minimumSize))
  let renderWidths = ratioResolve(width, edges)
  var offset = 0
  for i in 0 ..< children.len:
    let child = children[i]
    let childWidth = renderWidths[i]
    result.add((child, (x: x + offset, y: y, width: childWidth, height: height)))
    offset += childWidth

proc getTreeIcon*(self: ColumnSplitter): string =
  ## rich layout.py:94-95 — `ColumnSplitter.get_tree_icon(self) -> str`: return
  ## `"[layout.tree.column]⬍"`. body.
  result = "[layout.tree.column]⬍"

proc divide*(self: ColumnSplitter, children: openArray[Layout],
             region: Region): seq[(Layout, Region)] =
  ## rich layout.py:97-101 — `ColumnSplitter.divide(...)`: split `region` into
  ## columns via `ratio_resolve(height, children)` (layout.py:98-100). Each
  ## child `Layout` is duck-typed as an `Edge` (it has `size`/`ratio`/
  ## `minimum_size`), so the children are adapted to a `seq[Edge]` before
  ## `ratioResolve`. body. Returns `seq[(Layout, Region)]`.
  let (x, y, width, height) = region
  var edges: seq[Edge] = @[]
  for i in 0 ..< children.len:
    let child = children[i]
    edges.add(Edge(size: child.size, ratio: child.ratio,
                   minimumSize: child.minimumSize))
  let renderHeights = ratioResolve(height, edges)
  var offset = 0
  for i in 0 ..< children.len:
    let child = children[i]
    let childHeight = renderHeights[i]
    result.add((child, (x: x, y: y + offset, width: width, height: childHeight)))
    offset += childHeight

proc initPlaceholder*(layout: Layout, style: StyleType = ""): Placeholder =
  ## rich layout.py:111-114 — `_Placeholder.__init__(self, layout: Layout,
  ## style: StyleType = "") -> None`. Private (Python `_Placeholder`). body:
  ## `self.layout = layout`; `self.style = style` (`StyleType`→`StyleValue` via
  ## the `toStyleValue` converter, the `live_render.nim` field-assignment
  ## pattern); `highlighter = ReprHighlighter()` (the class attr → per-instance).
  result = Placeholder()
  result.layout = layout
  result.styleVal = style
  result.highlighter = ReprHighlighter()

method renderConsole*(self: Placeholder, console: ConsoleHandle,
                   options: ConsoleOptions): RenderResult =
  ## rich layout.py:116-135 — `_Placeholder.__rich_console__(self, console:
  ## Console, options: ConsoleOptions) -> RenderResult`: yield a `Panel(Align.
  ## center(Pretty(layout), vertical="middle"), ...)` sized to the layout
  ## (layout.py:118-134). Private.
  #
  # Simplified per the fanout task spec: emit the literal `"Placeholder"`
  # string. The faithful `Panel(Align.center(Pretty(layout), vertical=
  # "middle"), style=self.style, title=self.highlighter(title), border_style=
  # "blue", height=height)` (layout.py:118-134) is a deep composite whose
  # output depends on `Panel`/`Align`/`Pretty`/`ReprHighlighter` all rendering
  # correctly (and `Panel.renderConsole` is itself still a stub); the
  # `addString(result, "Placeholder")` form keeps the placeholder
  # distinguishable in the output while the composite pipeline matures. Wire
  # the full `Panel(...)` yield when the composite renderers land.
  result = @[]
  result.addString("Placeholder")

proc initLayout*(renderable: Option[RenderableValue] = none(RenderableValue),
                 name: Option[string] = none(string),
                 size: Option[int] = none(int), minimumSize: int = 1,
                 ratio: int = 1, visible: bool = true): Layout =
  ## rich layout.py:121-135 — `Layout.__init__(self, renderable: Optional[
  ## RenderableType] = None, *, name: Optional[str] = None, size: Optional[int]
  ## = None, minimum_size: int = 1, ratio: int = 1, visible: bool = True) ->
  ## None`. `renderable: Optional[RenderableType]` → `Option[RenderableValue] =
  ## none(RenderableValue)` (live.nim pattern); the keyword-only group (Python
  ## `*`) keeps its order. body sets `self._renderable = renderable or
  ## _Placeholder(self)` (a present `renderable` is stored verbatim; an absent
  ## one wraps a `Placeholder(self)` via `toRenderableValue`), `self.splitter =
  ## self.splitters["column"]()` (a `ColumnSplitter`), and the remaining fields;
  ## `self._lock = RLock()` → `initLock(result.lockField)`.
  result = Layout()
  # Faithful port of `renderable or _Placeholder(self)` (layout.py:127): Python
  # `or` treats `None` AND `""` (the only falsy `RenderableType`) as falsy, so a
  # present-but-empty-string renderable also yields a `Placeholder` (not the bare
  # `""`). `Option.isSome` alone diverges at `some(rvString(""))`; the extra
  # guard collapses it. Other `RenderableValue` arms (`rvConsoleRenderable`/
  # `rvRichCast`) hold non-nil refs (always truthy), so they are stored verbatim.
  if renderable.isSome and
     not (renderable.get.kind == rvString and renderable.get.textStr == ""):
    result.renderableVal = renderable.get
  else:
    result.renderableVal = toRenderableValue(initPlaceholder(result))
  result.size = size
  result.minimumSize = minimumSize
  result.ratio = ratio
  result.name = name
  result.visible = visible
  result.splitter = ColumnSplitter()
  result.childrenList = @[]
  result.renderMap = tables.initTable[Layout, LayoutRender]()
  initLock(result.lockField)

proc optStrToJson(o: Option[string]): JsonNode =
  ## [Nim-only helper] Encode an `Option[string]` (`Layout.name`) as the
  ## `JsonNode` `Any` handle for a `__rich_repr__` triple value (layout.py:139).
  ## `None` -> `null`; `Some(s)` -> `newJString(s)`.
  if o.isSome: result = newJString(o.get) else: result = newJNull()

proc optIntToJson(o: Option[int]): JsonNode =
  ## [Nim-only helper] Encode an `Option[int]` (`Layout.size`) as the
  ## `JsonNode` `Any` handle for a `__rich_repr__` triple value (layout.py:140).
  ## `None` -> `null`; `Some(n)` -> `newJInt(n)`.
  if o.isSome: result = newJInt(o.get) else: result = newJNull()

proc richRepr*(self: Layout): Result =
  ## rich layout.py:137-142 — `Layout.__rich_repr__(self) -> Result` (via the
  ## `@rich_repr` decorator, layout.py:106): yield `("name", self.name, None)`,
  ## `("size", self.size, None)`, `("minimum_size", self.minimum_size, 1)`,
  ## `("ratio", self.ratio, 1)` (layout.py:139-142). `__rich_repr__`→`richRepr`.
  ## Deferred: `Result` is `iterator(): ReprArg {.closure.}` (repr.nim:82) and
  ## no anonymous closure-iterator construction pattern exists in the codebase;
  ## `ReprArg` triple slots are likewise unverified — `result = default(Result)`
  ## (nil closure iterator). The `ReprArg` triple slots ARE public
  ## (`tripleKey`/`tripleValue`/`tripleDefault`) and an anonymous
  ## `iterator(): ReprArg {.closure.}` DOES compile, but Nim 2.2.10 cannot
  ## CONSUME a closure-iterator-typed value via `for arg in richRepr()` (only a
  ## direct iterator CALL iterates; a proc returning `iterator()` is iterated as
  ## a value → `items` not found), so the `Result` is not yet usable — the
  ## codebase convention (every `richRepr` proc is deferred; `style.nim` notes
  ## "the `Result` generator/yield type is not yet available") keeps
  ## `result = default(Result)`.
  iterator gen(): ReprArg {.closure.} =
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "name",
                  tripleValue: optStrToJson(self.name), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "size",
                  tripleValue: optIntToJson(self.size), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "minimum_size",
                  tripleValue: newJInt(self.minimumSize), tripleDefault: newJInt(1))
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "ratio",
                  tripleValue: newJInt(self.ratio), tripleDefault: newJInt(1))
  result = gen

proc renderable*(self: Layout): RenderableValue =
  ## rich layout.py:144-146 — `Layout.renderable` (`@property`): `self if
  ## self._children else self._renderable` (layout.py:145). A split layout (any
  ## raw children) renders itself (`toRenderableValue(self)` — the
  ## `rvConsoleRenderable` arm); a leaf renders its stored `renderableVal`.
  ## body.
  if self.childrenList.len > 0:
    result = toRenderableValue(self)
  else:
    result = self.renderableVal

proc children*(self: Layout): seq[Layout] =
  ## rich layout.py:148-150 — `Layout.children` (`@property`): the visible
  ## children — `[child for child in self._children if child.visible]`
  ## (layout.py:149). body.
  for child in self.childrenList:
    if child.visible:
      result.add(child)

proc map*(self: Layout): RenderMap =
  ## rich layout.py:152-154 — `Layout.map` (`@property`): the last render's
  ## `RenderMap` — `self._render_map` (layout.py:153). body (returns the
  ## stored `Table` by value; a snapshot, matching the `RenderMap` value type).
  result = self.renderMap

proc splitterName(s: Splitter): string =
  ## [Nim-only helper] Derive the splitter's `name` ("row"/"column") via type
  ## dispatch. The Python `RowSplitter.name`/`ColumnSplitter.name` CLASS attrs
  ## ("row"/"column", layout.py:77,94) are not mirrored by the Nim
  ## `RowSplitter()`/`ColumnSplitter()` constructors (which leave the inherited
  ## `Splitter.name` field ""), so `s.name` would yield "" — the dispatch
  ## reconstructs the faithful name from the runtime splitter type.
  if s of RowSplitter: "row"
  elif s of ColumnSplitter: "column"
  else: s.name

proc layoutTreeIcon(s: Splitter): string =
  ## [Nim-only helper] Get the tree icon via type dispatch (downcast).
  ## `getTreeIcon` is a per-type `proc` (overloaded for `Splitter`/
  ## `RowSplitter`/`ColumnSplitter`), so `s.getTreeIcon()` on `s: Splitter`
  ## statically resolves to the abstract base `discard` — the downcast (guarded
  ## by `of RowSplitter`/`of ColumnSplitter`, the `makeRegionMap` pattern)
  ## emulates Python's virtual dispatch.
  if s of RowSplitter: RowSplitter(s).getTreeIcon()
  elif s of ColumnSplitter: ColumnSplitter(s).getTreeIcon()
  else: s.getTreeIcon()

proc layoutSummary(layout: Layout): table.Table =
  ## [Nim-only helper] rich layout.py:164-172 — `summary(layout)`: build a
  ## `Table.grid` with the splitter's tree icon and `Pretty(layout)` (or
  ## `Styled(Pretty(layout), "dim")` when invisible). `icon` is the splitter's
  ## `get_tree_icon()` string (e.g. `"[layout.tree.row]⬌"`);
  ## `Table.grid(padding=(0,1,0,0))` → `PaddingDimensions(kind: pdQuad,
  ## quad: (0,1,0,0))`; the visible/invisible branch keeps the concrete
  ## `Pretty`/`Styled` type per `addRow`'s `varargs[RenderableOpt]` (a
  ## `RenderableValue` upcast would lose the concrete type, so two `addRow`
  ## calls — the `scope.nim:148` `addRow(string, Pretty)` precedent).
  let icon = layoutTreeIcon(layout.splitter)
  result = table.Table.grid(padding = PaddingDimensions(kind: pdQuad, quad: (0, 1, 0, 0)))
  # `addRow(icon, text)` is blocked by a Nim `varargs` limitation: `varargs[
  # RenderableOpt]` with the `toRenderableOpt` converters in scope effectively
  # requires ONE converter for every vararg, so a row mixing a `string` (icon)
  # and a `RenderableBase` (`Pretty`/`Styled`) — needing two distinct converter
  # overloads — fails at the 2nd element (confirmed via probes; even two
  # pre-converted `RenderableOpt`s fail, since `RenderableOpt`->`RenderableOpt`
  # has no converter). Replicate `Table.addRow`'s lazy-column cell-append
  # (table.nim:838-851) inline: build the two `RenderableValue` cells, lazily
  # create two columns each seeded with its cell (`initColumn(cells=...)` sets
  # `rawCells`), then append a `Row`. This restores the `Layout.tree` property
  # (which feeds `layoutSummary`) without touching the `renderConsole` path the
  # layout_* golden cases exercise. NOTE: RENDERING the `tree` (which invokes
  # `Pretty(layout).renderConsole` -> `prettyRepr` -> `$layout`) currently hits a
  # PRE-EXISTING library-wide segfault: `echo $layout` crashes for ANY `Layout`
  # (even `initLayout()` with no children) via an implicit `$` operator that is
  # neither `repr` (repr_v2 stdlib doesn't compile in this env) nor any visible
  # `proc `$`` (only `Text`/`Style`/`ColorSystem`/`Box` define `$`). That `$`
  # bug is in the stringify/repr subsystem, out of scope for the layout golden
  # cases (which use `renderConsole`, not `tree`/`Pretty`); the `summary` build
  # itself is correct and faithful to layout.py:164-172, so a future `$layout`
  # fix makes `tree` render without any change here.
  var iconCells: seq[RenderableValue] = @[]
  iconCells.add(icon)
  var textCells: seq[RenderableValue] = @[]
  if layout.visible:
    textCells.add(initPretty(layout))
  else:
    textCells.add(initStyled(initPretty(layout), "dim"))
  result.columns.add(table.initColumn(index = 0, highlight = result.highlight, cells = iconCells))
  result.columns.add(table.initColumn(index = 1, highlight = result.highlight, cells = textCells))
  result.rows.add(table.initRow())

proc layoutTreeRecurse(t: Tree, layout: Layout) =
  ## [Nim-only helper] rich layout.py:174-181 — `recurse(tree, layout)`: for
  ## each RAW child (`_children`→`childrenList`, not the `children` property —
  ## Python recurses the raw list), add its summary (inheriting
  ## `guide_style=f"layout.tree.{name}"`) and recurse into the returned child
  ## `Tree`. `Tree.add` mutates `self.children` AND returns the child (tree.nim
  ## `self.children.add(result)`), so the recursion builds the subtree on `t`.
  for child in layout.childrenList:
    layoutTreeRecurse(
      t.add(layoutSummary(child),
            guideStyle = "layout.tree." & splitterName(child.splitter)),
      child)

proc tree*(self: Layout): Tree =
  ## rich layout.py:156-182 — `Layout.tree` (`@property`): build a `Tree`
  ## renderable showing the layout structure. `tree = Tree(summary(self),
  ## guide_style=f"layout.tree.{self.splitter.name}", highlight=True)`; then
  ## `recurse(tree, self)` adds each child's summary subtree. `initTree`'s
  ## `guideStyle: StyleType` accepts the `f"layout.tree.{name}"` string;
  ## `highlight = true` (Python `highlight=True`).
  result = initTree(layoutSummary(self),
                    guideStyle = "layout.tree." & splitterName(self.splitter),
                    highlight = true)
  layoutTreeRecurse(result, self)

proc get*(self: Layout, name: string): Option[Layout] =
  ## rich layout.py:162-176 — `Layout.get(self, name: str) -> Optional[Layout]`:
  ## get a named layout (recursively), or `None` (layout.py:164-175). body:
  ## `self.name == name` (an `Option[string]`, so `isSome and .get == name`)
  ## returns `some(self)`; otherwise recurse over `self._children` (the raw
  ## `childrenList`, matching Python's `self._children`).
  if self.name.isSome and self.name.get == name:
    return some(self)
  for child in self.childrenList:
    let found = child.get(name)
    if found.isSome:
      return found
  return none(Layout)

proc `[]`*(self: Layout, name: string): Layout =
  ## rich layout.py:178-182 — `Layout.__getitem__(self, name: str) -> Layout`:
  ## get a named layout, raising `KeyError` if absent (layout.py:180-181).
  ## `__getitem__`→`` `[]` ``. body: `self.get(name)`; `KeyError` (a system
  ## exception in `system/exceptions.nim`) if `isNone`.
  let found = self.get(name)
  if found.isNone:
    raise newException(KeyError, "No layout with name '" & name & "'")
  result = found.get

proc split*(self: Layout, layouts: openArray[RenderableValue],
            splitter: SplitterArg = "column") =
  ## rich layout.py:184-201 — `Layout.split(self, *layouts: Union[Layout,
  ## RenderableType], splitter: Union[Splitter, str] = "column") -> None`:
  ## split the layout into sub-layouts. `*layouts` varargs → `openArray[
  ## RenderableValue]` (Nim varargs must be last, but `splitter` follows —
  ## Screen/Renderables translation; `Union[Layout, RenderableType]` collapses
  ## to `RenderableType`). `splitter: Union[Splitter, str]` → `SplitterArg`
  ## (typeclass, default `"column"`); raises `NoSplitter` for an unknown name
  ## (layout.py:197-199). The `SplitterArg = Splitter or string` typeclass is
  ## a compile-time generic (instantiated per concrete arg type, like
  ## `style.StyleType`), so the `isinstance(splitter, Splitter)` vs name-string
  ## dispatch is performed at COMPILE time via `when splitter is Splitter:` (the
  ## `console.nim:1445`/`pretty.nim:545` `when x is Type` idiom, evaluated per
  ## instantiation): the `Splitter` arm uses the instance verbatim; the `string`
  ## arm looks up `"row"`/`"column"` → `RowSplitter()`/`ColumnSplitter()` (the
  ## `splitters` name→factory dict, layout.py:197), raising `NoSplitter` for an
  ## unknown name (layout.py:199). Children are wrapped (a `Layout` kept as-is,
  ## else `initLayout(some(l))` — the `addSplit`/`splitRow` pattern) and replace
  ## `childrenList` (Python `self._children[:] = _layouts`).
  var children: seq[Layout] = @[]
  for l in layouts:
    if l.kind == rvConsoleRenderable and l.consoleItem of Layout:
      children.add(Layout(l.consoleItem))
    else:
      children.add(initLayout(some(l)))
  when splitter is Splitter:
    self.splitter = splitter
  else:
    case splitter
    of "row": self.splitter = RowSplitter()
    of "column": self.splitter = ColumnSplitter()
    else: raise newException(NoSplitter, "No splitter called '" & $splitter & "'")
  self.childrenList = children

proc addSplit*(self: Layout, layouts: varargs[RenderableValue]) =
  ## rich layout.py:203-213 — `Layout.add_split(self, *layouts: Union[Layout,
  ## RenderableType]) -> None`: add new layout(s) to the existing split
  ## (layout.py:207-212). `*layouts` (last) → `varargs[RenderableValue]`.
  ## body: each value is a `Layout` (`rvConsoleRenderable` + `of Layout`)
  ## kept as-is, else wrapped in `initLayout(some(layout))` (`Layout(layout)`).
  for l in layouts:
    if l.kind == rvConsoleRenderable and l.consoleItem of Layout:
      self.childrenList.add(Layout(l.consoleItem))
    else:
      self.childrenList.add(initLayout(some(l)))

proc splitRow*(self: Layout, layouts: varargs[RenderableValue]) =
  ## rich layout.py:215-221 — `Layout.split_row(self, *layouts) -> None`: split
  ## into a row (side-by-side) — `self.split(*layouts, splitter="row")`
  ## (layout.py:219). `*layouts` (last) → `varargs[RenderableValue]`. body:
  ## bypasses `split` (whose `SplitterArg` typeclass has no runtime dispatch) by
  ## directly setting `self.splitter = RowSplitter()`, resetting
  ## `childrenList`, and appending the wrapped children.
  self.splitter = RowSplitter()
  self.childrenList = @[]
  for l in layouts:
    if l.kind == rvConsoleRenderable and l.consoleItem of Layout:
      self.childrenList.add(Layout(l.consoleItem))
    else:
      self.childrenList.add(initLayout(some(l)))

proc splitColumn*(self: Layout, layouts: varargs[RenderableValue]) =
  ## rich layout.py:223-229 — `Layout.split_column(self, *layouts) -> None`:
  ## split into a column (stacked) — `self.split(*layouts, splitter="column")`
  ## (layout.py:227). `*layouts` (last) → `varargs[RenderableValue]`. body:
  ## bypasses `split` (whose `SplitterArg` typeclass has no runtime dispatch) by
  ## directly setting `self.splitter = ColumnSplitter()`, resetting
  ## `childrenList`, and appending the wrapped children.
  self.splitter = ColumnSplitter()
  self.childrenList = @[]
  for l in layouts:
    if l.kind == rvConsoleRenderable and l.consoleItem of Layout:
      self.childrenList.add(Layout(l.consoleItem))
    else:
      self.childrenList.add(initLayout(some(l)))

proc unsplit*(self: Layout) =
  ## rich layout.py:231-233 — `Layout.unsplit(self) -> None`: reset splits to
  ## the initial state — `del self._children[:]` (layout.py:232). body:
  ## `setLen(0)` truncates the same `childrenList` seq in place (faithful to
  ## `del lst[:]`, which mutates the list object rather than rebinding it).
  self.childrenList.setLen(0)

proc update*(self: Layout, renderable: RenderableType) =
  ## rich layout.py:235-243 — `Layout.update(self, renderable: RenderableType) ->
  ## None`: set the renderable under `self._lock` (layout.py:240-241). Param
  ## keeps the faithful `RenderableType` typeclass. body (locking deferred per
  ## the codebase convention — `console.nim` likewise leaves `RLock` unset):
  ## `self.renderableVal = renderable` fires the `toRenderableValue` converter
  ## (`string`→`rvString`, `RenderableBase`→`rvConsoleRenderable`), the
  ## `live_render.nim` field-assignment pattern.
  self.renderableVal = renderable

proc refreshScreen*(self: Layout, console: ConsoleHandle, layoutName: string) =
  ## rich layout.py:245-257 — `Layout.refresh_screen(self, console: "Console",
  ## layout_name: str) -> None`: refresh a sub-layout's render (layout.py:250-256).
  ## body (locking deferred; `renderLines`/`updateScreenLines` are
  ## `console.nim` stubs this delegates to): downcast `console: ConsoleHandle`→
  ## `Console` (the subtype carrying `renderLines`/`options`/`updateScreenLines`),
  ## look up the named layout + its `renderMap` region, re-render it into the
  ## region's `(width, height)` via `console.options.updateDimensions`, store the
  ## new `LayoutRender`, and flush via `updateScreenLines(lines, x, y)`.
  let layout = self[layoutName]
  let lr = self.renderMap[layout]
  let region = lr.region
  let c = Console(console)
  # Faithful to `console.render_lines(layout, console.options.update_dimensions(
  # width, height))` (layout.py:254): the named sub-`Layout` is re-rendered via
  # its own `__rich_console__` (stitching its leaves into `height` rows), NOT
  # `layout.renderable` directly — `renderable` would render only a leaf's
  # stored renderable (skipping the `__rich_console__` stitch/pad-to-height for
  # leaves; for a split layout `layout.renderable` == `layout` so the two
  # coincide, but for a leaf they diverge). `toRenderableValue(layout)` wraps the
  # `Layout` (a `RenderableBase`) as the `rvConsoleRenderable` arm expected by
  # `Console.renderLines`'s `RenderableValue` param.
  let lines = c.renderLines(toRenderableValue(layout),
      some(c.options.updateDimensions(region.width, region.height)))
  self.renderMap[layout] = (region: region, render: lines)
  c.updateScreenLines(lines, region.x, region.y)

proc makeRegionMap(self: Layout, width: int, height: int): RegionMap =
  ## rich layout.py:259-284 — `Layout._make_region_map(self, width: int, height:
  ## int) -> RegionMap` (private): build the `Layout`→`Region` map by walking
  ## the split tree (layout.py:261-283). Private (Python `_make_region_map`).
  ## body: a stack DFS (`[(self, Region(0,0,width,height))]`), popping a
  ## `(layout, region)` and pushing the subdivided children. `divide` is a
  ## `proc` (not a `method`), so static dispatch on `layout.splitter: Splitter`
  ## would hit the abstract base stub — manual `of RowSplitter`/`of
  ## ColumnSplitter` + checked downcast emulates Python's virtual dispatch.
  ## The Python `sorted(layout_regions, key=itemgetter(1))` is vestigial here
  ## (a `Table` iterates hash order, not insertion order, and `render` stitches
  ## by `region` coordinates, not map order), so it is omitted.
  var stack: seq[(Layout, Region)] =
      @[(self, (x: 0, y: 0, width: width, height: height))]
  var layoutRegions: seq[(Layout, Region)] = @[]
  while stack.len > 0:
    let popped = stack.pop()
    layoutRegions.add(popped)
    let (layout, region) = popped
    let children = layout.children
    if children.len > 0:
      if layout.splitter of RowSplitter:
        for cr in RowSplitter(layout.splitter).divide(children, region):
          stack.add(cr)
      elif layout.splitter of ColumnSplitter:
        for cr in ColumnSplitter(layout.splitter).divide(children, region):
          stack.add(cr)
  result = tables.initTable[Layout, Region]()
  for lr in layoutRegions:
    result[lr[0]] = lr[1]

proc render*(self: Layout, console: ConsoleHandle,
             options: ConsoleOptions): RenderMap =
  ## rich layout.py:286-313 — `Layout.render(self, console: Console, options:
  ## ConsoleOptions) -> RenderMap`: render the leaf sub-layouts into a
  ## `RenderMap` (layout.py:288-312). body: `render_width = options.maxWidth`;
  ## `render_height = options.height or console.height` (an `Option[int]`, so
  ## `isSome and .get != 0` — Python's `or` treats `None`/`0` as falsy);
  ## `makeRegionMap`; for each leaf (`not layout.children`) render it via
  ## `console.renderLines(layout.renderable, some(options.updateDimensions(
  ## region.width, region.height)))` (a `console.nim` stub this delegates to)
  ## and store `LayoutRender(region, lines)`. The `ConsoleHandle`→`Console`
  ## downcast reaches `renderLines`/`height`.
  let renderWidth = options.maxWidth
  let c = Console(console)
  let renderHeight =
    if options.height.isSome and options.height.get != 0: options.height.get
    else: c.height
  let regionMap = self.makeRegionMap(renderWidth, renderHeight)
  result = tables.initTable[Layout, LayoutRender]()
  for layout, region in regionMap.pairs:
    if layout.children.len == 0:
      let lines = c.renderLines(layout.renderable,
          some(options.updateDimensions(region.width, region.height)))
      result[layout] = (region: region, render: lines)

method renderConsole*(self: Layout, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich layout.py:315-336 — `Layout.__rich_console__(self, console: Console,
  ## options: ConsoleOptions) -> RenderResult`: render all sub-layouts under
  ## `self._lock` and stitch the `RenderMap` into `RenderResult` lines
  ## (layout.py:317-334). `__rich_console__`→`renderConsole`.
  #
  # Faithful port of layout.py:317-334. `width = options.max_width or
  # console.width` / `height = options.height or console.height` (Python `or`:
  # `None`/`0` falsy) → the `maxWidth != 0` / `options.height.isSome and != 0`
  # guards; `render_map = self.render(console, options.update_dimensions(width,
  # height))` reuses the implemented `Layout.render`/`makeRegionMap`; the
  # `layout_lines` grid (`height` empty rows) is filled by extending each row
  # with the matching leaf's rendered `lines` at offset `region.y` (the
  # `islice(layout_lines, y, y+layout_height)` + `zip` stitch, layout.py:325-330);
  # finally each row + `Segment.line()` is emitted via `addSegment`. Locking
  # (`with self._lock`) is omitted per the codebase convention (`console.nim`
  # leaves `RLock` unset). `Console.renderLines` (used by `Layout.render`) is a
  # stub returning empty lines, so the stitched output is empty until
  # `renderLines` is wired — the structure is faithful.
  result = @[]
  let c = Console(console)
  let width = if options.maxWidth != 0: options.maxWidth else: c.width
  let height = if options.height.isSome and options.height.get != 0:
                 options.height.get else: c.height
  let renderMap = self.render(console, options.updateDimensions(width, height))
  self.renderMap = renderMap
  let safeHeight = max(0, height)
  var layoutLines: seq[seq[Segment]] = @[]
  for i in 0 ..< safeHeight:
    layoutLines.add(@[])
  # Stitch the `RenderMap` into `height` rows. Python's `render_map.values()`
  # iterates in dict INSERTION order (the divide order — left-to-right for
  # `split_row`, top-to-bottom for `split_column`), so each row's segments
  # concatenate in region order. The Nim `renderMap` is a `tables.Table` (hash
  # order, NOT insertion order), so iterating `renderMap.values` directly would
  # scramble side-by-side columns (e.g. `split_row` `L`/`R` would render `R`/`L`).
  # Collect the renders into a `seq` and stable-sort by `(region.y, region.x)` —
  # the visual top-to-bottom, left-to-right order — so the concatenation matches
  # Python's insertion-order output byte-exact (stacked layouts have one leaf
  # per row-band; side-by-side layouts concatenate the leaves' `region.width`-wide
  # lines in `x` order).
  var renderList: seq[LayoutRender] = @[]
  for lr in renderMap.values:
    renderList.add(lr)
  renderList.sort(proc (a, b: LayoutRender): int =
    if a.region.y != b.region.y: result = cmp(a.region.y, b.region.y)
    else: result = cmp(a.region.x, b.region.x))
  for lr in renderList:
    let region = lr.region
    let lines = lr.render
    let y = region.y
    let layoutHeight = region.height
    let n = min(layoutHeight, lines.len)
    for i in 0 ..< n:
      let targetRow = y + i
      if targetRow >= 0 and targetRow < layoutLines.len:
        for seg in lines[i]:
          layoutLines[targetRow].add(seg)
  let newLine = line()
  for layoutRow in layoutLines:
    for seg in layoutRow:
      result.addSegment(seg)
    result.addSegment(newLine)
