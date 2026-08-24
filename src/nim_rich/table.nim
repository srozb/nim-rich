## body of `rich.table` (rich/table.py).
##
## `Table` draws a grid of renderables (table.py:153-935); `Column`/`Row`
## (dataclasses, table.py:39-139) describe columns/rows; `_Cell` (NamedTuple,
## table.py:142-150) a single padded cell. `rich.columns`/`rich.scope` consume
## `Table` (columns.py:11, scope.py:7).
##
## Import graph (rich/table.py:1-35): runtime sibling imports are `from . import
## box, errors` (table.py:14), `from ._loop import loop_first_last, loop_last`
## (table.py:15), `from ._pick import pick_bool` (table.py:16), `from ._ratio
## import ratio_distribute, ratio_reduce` (table.py:17), `from .align import
## VerticalAlignMethod` (table.py:18), `from .jupyter import JupyterMixin`
## (table.py:19), `from .measure import Measurement` (table.py:20), `from
## .padding import Padding, PaddingDimensions` (table.py:21), `from .protocol
## import is_renderable` (table.py:22), `from .segment import Segment`
## (table.py:23), `from .style import Style, StyleType` (table.py:24), `from
## .text import Text, TextType` (table.py:25); under `TYPE_CHECKING`
## (table.py:27) come `Console`, `ConsoleOptions`, `JustifyMethod`,
## `OverflowMethod`, `RenderableType`, `RenderResult` (`.console`,
## table.py:28-35).
##
## body wiring (this file): `import std/options`; `import std/math` (`sum`,
## table.py:531,533,553,583,…); `import box` (Box, HEAVY_HEAD); `import align`
## (VerticalAlignMethod); `import measure` (Measurement); `import padding`
## (Padding, PaddingDimensions, `unpack`); `import segment` (richbase:
## ConsoleHandle, ConsoleOptions, RenderResult, RenderableBase, RenderableType,
## JustifyMethod, OverflowMethod, ConsoleRenderable, RichCast, … + Segment +
## Style); `import style` (Style, StyleType, StyleOpt, StyleValue, the
## `toStyleValue`/`toStyleOpt` converters); `import text` (Text, TextType,
## StyleValue, `initText`); `import api_types` (RenderableValue, the
## `toRenderableValue` converters); `import ratio` (`ratioDistribute`/
## `ratioReduce`, table.py:547,559,581,616). `_loop`/`_pick` (table.py:15-16)
## are body-only deps used only in the deferred `render`/`getCells`/
## `renderConsole` bodies (not exercised this round); `protocol.is_renderable`
## (table.py:457) and `errors.NotRenderableError` (table.py:461) are NOT
## imported — the `toRenderableOpt` converter accepts only `string`/
## `ConsoleRenderable or RichCast`/`Option[T: RenderableBase]`, so
## non-renderables are rejected at the call site (compile time) and the runtime
## `NotRenderableError` path is unreachable under static typing (the faithful
## translation of `is_renderable`). `jupyter` (`JupyterMixin`, table.py:19) is
## the base — modelled via `RenderableBase`. `console` types are
## `TYPE_CHECKING`-only — supplied via richbase placeholders (through
## `segment`); `console.nim` itself is unreachable (the
## console→terminal_theme→palette→table import cycle), so `console.get_style`/
## `console.render`/`console.render_lines`/`console.render_str` cannot be called
## here — procs needing them use the sanctioned DEFERRED pattern.
##
## Three [Nim-only] union handles (the `StyleOpt`/`RuleTitle` pattern):
## `TableHeader` — `Union[Column, str]` (the `*headers` varargs element,
## table.py:188) as a case object (`thStr`|`thColumn`) with `toTableHeader*`
## converters, so `initTable("a","b")`/`initTable(aColumn)`/`initTable("a",
## aColumn)` compile (`varargs` needs a uniform element). `TableTextOpt` —
## `Optional[TextType]`=`Optional[Union[str,Text]]` (table.py:189-190) as
## `ttoNone`|`ttoStr`|`ttoText` with converters, so `initTable(title="t")`/
## `initTable(title=aText)`/`initTable()` compile; reused by `columns.nim`
## (columns.py:11 imports `Table`); body may unify with `panel.PanelTextOpt`.
## `RenderableOpt` — `Optional[RenderableType]` (the `*renderables` varargs
## element of `add_row`, table.py:423) as `roNone`|`roStr`|`roRenderable` with
## `toRenderableOpt*` converters from `string`, the structural
## `ConsoleRenderable or RichCast` concept (so BOTH nominal `RenderableBase`
## subclasses AND structural renderables — any type with a `renderConsole` or
## `richCast` — compile, not just `RenderableBase`), and a generic
## `Option[T: RenderableBase]` (so `none(RenderableBase)`⇒`roNone`,
## `some(aText)`/`some(aRenderableBase)`⇒`roRenderable`; `Option[int]` is
## rejected by the `T: RenderableBase` constraint). So
## `addRow("a")`/`addRow(aText)`/`addRow(aStructuralRenderable)`/
## `addRow(none(RenderableBase),"b")`/`addRow(some(aText))` all compile; `int`
## is rejected (not `ConsoleRenderable`/`RichCast`/`str`).
##
## `row_styles: Optional[Iterable[StyleType]] = None` (table.py:197) is the
## other non-narrowing param: the `Table.rowStyles` FIELD is materialized
## (`list(row_styles or [])`, table.py:243 ⇒ `seq[StyleValue]`), but the PARAM
## must accept any `Iterable[StyleType]` — `seq[string]`/`seq[Style]`/a closure
## iterator/generator — not just `Option[seq[StyleValue]]`. So `initTable` is
## generic `[R: RowStylesArg]` with `rowStyles: R = none(seq[StyleValue])`,
## where `RowStylesArg` is a concept accepting `None` (`isNone`), any iterable
## yielding `StyleType` (`for y in x: rsAccept(y)`), or a closure iterator
## yielding `StyleType` (`var z = x(); rsAccept(z)`); `seq[int]`,
## `iterator(): int` and bare `int` are rejected. The `rsAccept(s: StyleType)`
## helper is the element-type predicate (a bare `y is StyleType` always
## compiles, so it does not reject — routing `y` through a real
## `proc rsAccept(s: StyleType)` forces a genuine type check, the same trick
## `scope.ScopeMapping` uses with `rsAcceptKey`).
##
## `Column`/`Row` are `ref object` (Python dataclasses — reference semantics).
## `Table(JupyterMixin)` is `ref object of RenderableBase`. `_Cell`→`Cell`
## (named tuple; `_` dropped, like `ruleLine`). Dataclass `__init__`s become
## explicit `initColumn*`/`initRow*`. RENAMES (to free names for properties):
## `_index`→`index`; `_cells`→`rawCells` (the `cells` property keeps `cells`);
## `_expand`→`expandField` (the `expand` property is separate);
## `_padding`→`cellPadding` (the `padding` property is separate);
## `_extra_width`→`extraWidth`; `_calculate_column_widths`→
## `calculateColumnWidths`; `_collapse_widths`→`collapseWidths` (classmethod→
## `typedesc[Table]`); `_get_cells`→`getCells`; `_get_padding_width`→
## `getPaddingWidth`; `_measure_column`→`measureColumn`; `_render`→`render`;
## `get_row_style`→`getRowStyle` (returns `Style` — it always builds
## `Style.null()+…` table.py:312-316, which also feeds
## `console.get_style(:StyleType)` in `_render`). `box: Optional[box.Box]=
## box.HEAVY_HEAD` (table.py:195, can be `None` — `grid` sets `box=None`) →
## `Option[Box]`, default `some(HEAVY_HEAD)`. `header_style`/`footer_style:
## Optional[StyleType]="table.header"`/`"table.footer"` (table.py:215-216) →
## `StyleOpt` defaults `StyleOpt(kind: sokStr, strv:…)`; other `*_style:
## Optional[StyleType]=None` → `StyleOpt` default `sokNone`; `style:
## StyleType="none"` → `StyleValue` field + `StyleType` typeclass param. `safe_box:
## Optional[bool]=None` → `Option[system.bool]` (`bool` qualified —
## `style.nim`/`text.nim` export `bool` procs). `padding: PaddingDimensions=(0,1)`
## → `PaddingDimensions(kind: pdPair, pair:(0,1))`. The `expand`/`padding`
## setters return `self` in Python (chaining); Nim `=` setters are `void`.

import std/options
import std/math
import std/strutils   # `strip` (divider check), `repeat` (leading section line).

import box          # Box, HEAVY_HEAD.
import align        # VerticalAlignMethod.
import measure      # Measurement.
import padding      # Padding, PaddingDimensions, unpack.
import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableBase, RenderableType, ConsoleRenderable,
                    # RichCast, JustifyMethod, OverflowMethod, …) + Segment +
                    # Style.
import style        # Style, StyleType, StyleOpt, StyleValue.
import text         # Text, TextType, StyleValue, initText.
import api_types    # RenderableValue.
import ratio        # ratioDistribute, ratioReduce.
import console_api  # Console dispatch (getStyle/renderLines/render/measure/
                    # getSafeBox) — breaks the console→terminal_theme→palette→
                    # table cycle: table calls console.getStyle(...)/renderLines(...)/
                    # getSafeBox() via virtual methods on ConsoleHandle instead of
                    # importing console.nim.

type
  TableHeaderKind* = enum
    ## [Nim-only discriminator] for `TableHeader` (the `Union[Column, str]`
    ## handle, table.py:188 — the `*headers` varargs element). `varargs` needs a
    ## uniform element, so `*headers: Union[Column, str]` → `varargs[TableHeader]`
    ## (the `Style.pickFirst`/`varargs[StyleOpt]` pattern, style.py:405).
    thStr     ## the `str`    arm (`Union[Column, str]`, table.py:188).
    thColumn  ## the `Column` arm (`Union[Column, str]`, table.py:188).

  TableHeader* = object
    ## rich table.py:188 — `Union[Column, str]` (the `*headers` varargs element)
    ## as a Nim case object so `varargs[TableHeader]` carries both `str` and
    ## `Column` headers. `toTableHeader*` converters accept `string`/`Column`;
    ## `int` is rejected. Nim-only handle.
    case kind*: TableHeaderKind
    of thStr:
      strv*: string       ## the `str` arm — a plain header string.
    of thColumn:
      columnv*: Column   ## the `Column` arm — a `Column` instance.

  TableTextOptKind* = enum
    ## [Nim-only discriminator] for `TableTextOpt` (the `Optional[TextType]`=
    ## `Optional[Union[str,Text]]` handle, table.py:189-190). `ttoNone` first so
    ## `default(TableTextOpt)`=`ttoNone`=`None` (the table.py:189 default).
    ttoNone  ## the `None` arm of `Optional[TextType]` (table.py:189-190).
    ttoStr   ## the `str`  arm (`TextType=Union[str,Text]`, text.py:41).
    ttoText  ## the `Text` arm (`TextType=Union[str,Text]`, text.py:41).

  TableTextOpt* = object
    ## rich table.py:189-190 — `Optional[TextType]`=`Optional[Union[str,Text]]`
    ## as a Nim case object (`None`|`str`|`Text`) — the `title`/`caption` field
    ## and param type. `toTableTextOpt*` converters accept `string`/`Text`;
    ## `int` rejected. `default`=`ttoNone`=`None`. Reused by `columns.nim`.
    case kind*: TableTextOptKind
    of ttoNone:
      discard
    of ttoStr:
      strv*: string   ## the `str`  arm — a plain title/caption string.
    of ttoText:
      textv*: Text    ## the `Text` arm — a `Text` instance.

  RenderableOptKind* = enum
    ## [Nim-only discriminator] for `RenderableOpt` (the `Optional[RenderableType]`
    ## handle, table.py:423 — the `*renderables` varargs element of `add_row`).
    ## `roNone` first so `default(RenderableOpt)`=`roNone`=`None`.
    roNone        ## the `None` arm (`Optional[RenderableType]`, table.py:423) — a blank cell.
    roStr         ## the `str` arm (`RenderableType`, console.py:267).
    roRenderable  ## the `ConsoleRenderable`/`RichCast` arm (console.py:257-263) — stored as a `RenderableBase`.

  RenderableOpt* = object
    ## rich table.py:423 — `Optional[RenderableType]` (the `*renderables` varargs
    ## element of `add_row`) as a Nim case object (`None`|`str`|`RenderableBase`).
    ## `toRenderableOpt*` converters accept `string`, any
    ## `ConsoleRenderable or RichCast` (structural + nominal renderables) and
    ## `Option[T: RenderableBase]` (`none(RenderableBase)`⇒`roNone`,
    ## `some(aText)`⇒`roRenderable`); `int` rejected (not
    ## `ConsoleRenderable`/`RichCast`/`str`), and `Option[int]` rejected (the
    ## `T: RenderableBase` constraint). `default`=`roNone`=`None`. Nim-only
    ## handle.
    case kind*: RenderableOptKind
    of roNone:
      discard
    of roStr:
      strv*: string                  ## the `str` arm — a string cell.
    of roRenderable:
      renderablev*: RenderableBase   ## the renderable arm — a `RenderableBase`.

  Column* = ref object
    ## rich table.py:39-128 — `@dataclass class Column`: a column within a
    ## `Table`. `ref object` (reference semantics; `_cells` mutated in place).
    header*: RenderableValue        ## rich table.py:69 — `header: RenderableType=""`.
    footer*: RenderableValue        ## rich table.py:72 — `footer: RenderableType=""`.
    headerStyle*: StyleValue        ## rich table.py:75 — `header_style: StyleType=""`.
    footerStyle*: StyleValue       ## rich table.py:78 — `footer_style: StyleType=""`.
    style*: StyleValue              ## rich table.py:81 — `style: StyleType=""`.
    justify*: JustifyMethod         ## rich table.py:84 — `justify="left"`→`jmLeft`.
    vertical*: VerticalAlignMethod  ## rich table.py:87 — `vertical="top"`→`vamTop`.
    overflow*: OverflowMethod       ## rich table.py:90 — `overflow="ellipsis"`→`omEllipsis`.
    width*: Option[int]             ## rich table.py:93 — `width: Optional[int]=None`.
    minWidth*: Option[int]          ## rich table.py:96 — `min_width: Optional[int]=None`.
    maxWidth*: Option[int]          ## rich table.py:99 — `max_width: Optional[int]=None`.
    ratio*: Option[int]             ## rich table.py:102 — `ratio: Optional[int]=None`.
    noWrap*: bool                   ## rich table.py:105 — `no_wrap: bool=False`.
    highlight*: bool                ## rich table.py:108 — `highlight: bool=False`.
    index*: int                     ## rich table.py:111 — `_index: int=0` (renamed `_index`→`index`).
    rawCells*: seq[RenderableValue] ## rich table.py:114 — `_cells: List[RenderableType]` (renamed `_cells`→`rawCells`; frees `cells` for the property).

  Row* = ref object
    ## rich table.py:132-139 — `@dataclass class Row`: information regarding a
    ## row. `ref object` (reference semantics).
    style*: StyleOpt        ## rich table.py:135 — `style: Optional[StyleType]=None` (default `sokNone`).
    endSection*: bool       ## rich table.py:138 — `end_section: bool=False`.

  Cell* = tuple[style: StyleValue, renderable: RenderableValue, vertical: VerticalAlignMethod]
    ## rich table.py:142-150 — `class _Cell(NamedTuple)`: a single cell. A named
    ## tuple (value type, named fields), as `color_triplet.nim` models
    ## `ColorTriplet`. `_Cell`→`Cell` (exported; `_` dropped, like `ruleLine`).
    ## `style: StyleType` (table.py:144)→`StyleValue`; `renderable:
    ## RenderableType` (table.py:146)→`RenderableValue`; `vertical:
    ## VerticalAlignMethod` (table.py:148).

  Table* = ref object of RenderableBase
    ## rich table.py:153-935 — `class Table(JupyterMixin)`: a console renderable
    ## to draw a table. `ref object of RenderableBase` (reference semantics;
    ## `JupyterMixin` modelled via `RenderableBase`). Fields mirror `__init__`
    ## (table.py:217-243).
    columns*: seq[Column]            ## rich table.py:217 — `self.columns: List[Column]=[]`.
    rows*: seq[Row]                  ## rich table.py:218 — `self.rows: List[Row]=[]`.
    title*: TableTextOpt             ## rich table.py:219 — `self.title` (`Optional[TextType]`).
    caption*: TableTextOpt           ## rich table.py:220 — `self.caption` (`Optional[TextType]`).
    width*: Option[int]              ## rich table.py:221 — `self.width` (`Optional[int]`).
    minWidth*: Option[int]           ## rich table.py:222 — `self.min_width` (`Optional[int]`).
    box*: Option[Box]                ## rich table.py:223 — `self.box` (`Optional[box.Box]`; default `some(HEAVY_HEAD)`; `None`⇒no box).
    safeBox*: Option[system.bool]    ## rich table.py:224 — `self.safe_box` (`Optional[bool]`; `system.bool` — `style`/`text` export `bool` procs).
    cellPadding*: (int, int, int, int) ## rich table.py:225 — `self._padding=Padding.unpack(padding)` (renamed `_padding`→`cellPadding`).
    padEdge*: bool                   ## rich table.py:226 — `self.pad_edge` (default `True`).
    expandField*: bool               ## rich table.py:227 — `self._expand` (renamed `_expand`→`expandField`; default `False`).
    showHeader*: bool                ## rich table.py:228 — `self.show_header` (default `True`).
    showFooter*: bool                ## rich table.py:229 — `self.show_footer` (default `False`).
    showEdge*: bool                  ## rich table.py:230 — `self.show_edge` (default `True`).
    showLines*: bool                 ## rich table.py:231 — `self.show_lines` (default `False`).
    leading*: int                    ## rich table.py:232 — `self.leading` (default `0`).
    collapsePadding*: bool           ## rich table.py:233 — `self.collapse_padding` (default `False`).
    style*: StyleValue                ## rich table.py:234 — `self.style` (`StyleType`; default `"none"`).
    headerStyle*: StyleOpt            ## rich table.py:235 — `self.header_style = header_style or ""` (`Optional[StyleType]`).
    footerStyle*: StyleOpt            ## rich table.py:236 — `self.footer_style = footer_style or ""` (`Optional[StyleType]`).
    borderStyle*: StyleOpt            ## rich table.py:237 — `self.border_style` (`Optional[StyleType]`; default `sokNone`).
    titleStyle*: StyleOpt             ## rich table.py:238 — `self.title_style` (`Optional[StyleType]`; default `sokNone`).
    captionStyle*: StyleOpt            ## rich table.py:239 — `self.caption_style` (`Optional[StyleType]`; default `sokNone`).
    titleJustify*: JustifyMethod      ## rich table.py:240 — `self.title_justify` (default `jmCenter`).
    captionJustify*: JustifyMethod    ## rich table.py:241 — `self.caption_justify` (default `jmCenter`).
    highlight*: bool                  ## rich table.py:242 — `self.highlight` (default `False`).
    rowStyles*: seq[StyleValue]       ## rich table.py:243 — `self.row_styles: Sequence[StyleType]=list(row_styles or [])` (materialized from the `row_styles: Optional[Iterable[StyleType]]` param).

converter toTableHeader*(x: string): TableHeader =
  ## Accept a `str` as a `Union[Column, str]` header (table.py:188) — `thStr`.
  ## Lets `initTable("a","b")` compile.
  result = TableHeader(kind: thStr, strv: x)

converter toTableHeader*(x: Column): TableHeader =
  ## Accept a `Column` as a `Union[Column, str]` header (table.py:188) —
  ## `thColumn`. Lets `initTable(aColumn)` compile.
  result = TableHeader(kind: thColumn, columnv: x)

converter toTableTextOpt*(x: string): TableTextOpt =
  ## Accept a `str` as `Optional[TextType]` (table.py:189-190) — `ttoStr`. Lets
  ## `initTable(title="t")` compile.
  result = TableTextOpt(kind: ttoStr, strv: x)

converter toTableTextOpt*(x: Text): TableTextOpt =
  ## Accept a `Text` as `Optional[TextType]` (table.py:189-190) — `ttoText`.
  ## Lets `initTable(title=aText)` compile.
  result = TableTextOpt(kind: ttoText, textv: x)

converter toRenderableOpt*(x: string): RenderableOpt =
  ## Accept a `str` as `Optional[RenderableType]` (table.py:423) — `roStr`. Lets
  ## `addRow("a","b")` compile.
  result = RenderableOpt(kind: roStr, strv: x)

converter toRenderableOpt*(x: RenderableBase): RenderableOpt =
  ## Accept any `RenderableBase` subclass (Text/Rule/Table/Panel/…) as
  ## `Optional[RenderableType]` (table.py:423) — `roRenderable`. All concrete
  ## Nim renderables inherit `RenderableBase` (the ref-object base), so this is
  ## a normal OO subtype assignment with NO concept check (the former
  ## `ConsoleRenderable or RichCast` compound-concept param triggered an
  ## exponential overload-resolution blowup in `nim c`; `RenderableBase` is
  ## the concrete narrowing that matches every renderable actually used).
  ## `int` is rejected (not a `RenderableBase`).
  result = RenderableOpt(kind: roRenderable, renderablev: x)

converter toRenderableOpt*[T: RenderableBase](x: Option[T]): RenderableOpt =
  ## Accept `Option[T]` (where `T` is a `RenderableBase` subclass) as
  ## `Optional[RenderableType]` (table.py:423) — `none(RenderableBase)`⇒`roNone`
  ## (blank cell), `some(aText)`/`some(aRenderableBase)`⇒`roRenderable`. The
  ## generic `T: RenderableBase` constraint accepts `Option[Text]`/
  ## `Option[RenderableBase]`/… (Nim `Option` is invariant, so a non-generic
  ## `Option[RenderableBase]` converter rejected `some(aText)` =
  ## `Option[Text]`); `Option[int]` is rejected (`int` is not `RenderableBase`).
  ## Lets `addRow(none(RenderableBase),"b")` and `addRow(some(aText))` compile.
  if x.isNone:
    result = RenderableOpt(kind: roNone)
  else:
    result = RenderableOpt(kind: roRenderable, renderablev: x.get)

# [Nim-only] `row_styles: Optional[Iterable[StyleType]]` (table.py:197). The
# `Table.rowStyles` FIELD is materialized (`list(row_styles or [])`, table.py:243
# ⇒ `seq[StyleValue]`). The PARAM is typed concrete `Option[seq[StyleValue]]`
# (defaults to `none`): a Nim `concept` over iterables + closure iterators was
# used previously to mirror Python `Iterable[StyleType]`, but Nim concept
# resolution with `compiles()` + iterator predicates triggers an exponential
# type-check blowup that makes `nim c` of `table.nim` never terminate (the
# concept was also unused — every call site relies on the `none` default). The
# concrete `Option[seq[StyleValue]]` restores instant compilation; pass a
# materialized `seq` of `StyleValue`/`string` (via `toStyleValue` converters) for
# explicit row styles. See `materializeRowStyles` below.

proc optOr*(v: Option[int], default: int): int =
  ## [Nim-only] faithful port of Python `v or default` for an `Optional[int]`
  ## (modelled as `Option[int]`): Python treats `None` AND `0` as falsy, so
  ## `0 or default == default`. `Option.get(default)` instead returns `0` for
  ## `some(0)`, diverging at zero — used wherever table.py writes
  ## `column.width or 1` (table.py:556) / `col.ratio or 0` (table.py:548).
  if v.isSome and v.get != 0:
    result = v.get
  else:
    result = default

proc styleOptOrEmpty*(x: StyleOpt): StyleValue =
  ## [Nim-only] faithful port of Python `style or ""` (table.py:407,411,413) for
  ## the `add_column` `*_style: Optional[StyleType]=None` params: collapse the
  ## `StyleOpt` (`Optional[StyleType]`) to the `StyleValue` (`StyleType`, no
  ## `None`) — `None`→`""`, a `str`→that `str` (empty stays `""`), a `Style`→that
  ## `Style`. The `str`/`Style` arms delegate to the frozen `toStyleValue*`
  ## converters (the `None`→`""` arm has no converter — it is handled here).
  case x.kind
  of sokNone:
    result = ""
  of sokStr:
    result = x.strv
  of sokStyle:
    result = x.stv

proc materializeRowStyles*(rs: Option[seq[StyleValue]]): seq[StyleValue] =
  ## [Nim-only] faithful port of `list(row_styles or [])` (table.py:243):
  ## materialize the `rowStyles` field/param (`Optional[Iterable[StyleType]]`)
  ## to a `seq[StyleValue]` — `None`/empty → `@[]`; otherwise copy the
  ## materialized `seq[StyleValue]` (each element already a `StyleValue` via
  ## the `toStyleValue*` converters at the call site). Concrete `Option` (not a
  ## `RowStylesArg` concept): see the note above — the concept's
  ## `compiles()`+iterator predicates caused an exponential type-check blowup.
  if rs.isSome:
    result = rs.get
  else:
    result = @[]

proc initColumn*(header: RenderableValue = "", footer: RenderableValue = "",
                 headerStyle: StyleType = "", footerStyle: StyleType = "",
                 style: StyleType = "", justify: JustifyMethod = jmLeft,
                 vertical: VerticalAlignMethod = vamTop,
                 overflow: OverflowMethod = omEllipsis,
                 width: Option[int] = none(int), minWidth: Option[int] = none(int),
                 maxWidth: Option[int] = none(int), ratio: Option[int] = none(int),
                 noWrap: bool = false, highlight: bool = false, index: int = 0,
                 cells: seq[RenderableValue] = @[]): Column =
  ## rich table.py:39-128 — the `Column` dataclass `__init__` (auto-generated,
  ## fields table.py:69-114): construct a `Column`. Nim `ref object` needs an
  ## explicit constructor (the dataclass `__init__` is implicit). `header`/
  ## `footer: RenderableType=""`→typeclass (default `""`); `*_style:
  ## StyleType=""`→`StyleType`; `justify`→`jmLeft`; `vertical`→`vamTop`;
  ## `overflow`→`omEllipsis`; `width`/`minWidth`/`maxWidth`/`ratio`→`Option[int]`;
  ## `noWrap`/`highlight` default `False`; `index`(`=_index`) default `0`;
  ## `cells`(`=_cells`) default `@[]`. The `StyleType`/`RenderableType` typeclass
  ## params convert to their storable handles (`StyleValue`/`RenderableValue`)
  ## via the frozen `toStyleValue`/`toRenderableValue` converters.
  new(result)
  result.header = header
  result.footer = footer
  result.headerStyle = headerStyle
  result.footerStyle = footerStyle
  result.style = style
  result.justify = justify
  result.vertical = vertical
  result.overflow = overflow
  result.width = width
  result.minWidth = minWidth
  result.maxWidth = maxWidth
  result.ratio = ratio
  result.noWrap = noWrap
  result.highlight = highlight
  result.index = index
  result.rawCells = cells

proc copy*(self: Column): Column =
  ## rich table.py:116-118 — `Column.copy(self)->Column`: "Return a copy of
  ## this Column" — `replace(self, _cells=[])` (table.py:117). Copies every
  ## field except `rawCells` (the renamed `_cells`), which is reset to `@[]`.
  new(result)
  result.header = self.header
  result.footer = self.footer
  result.headerStyle = self.headerStyle
  result.footerStyle = self.footerStyle
  result.style = self.style
  result.justify = self.justify
  result.vertical = self.vertical
  result.overflow = self.overflow
  result.width = self.width
  result.minWidth = self.minWidth
  result.maxWidth = self.maxWidth
  result.ratio = self.ratio
  result.noWrap = self.noWrap
  result.highlight = self.highlight
  result.index = self.index
  result.rawCells = @[]

proc cells*(self: Column): seq[RenderableValue] =
  ## rich table.py:121-123 — `Column.cells` (`@property` @120, body @121-123)->
  ## `Iterable[RenderableType]`: "Get all cells in the column, not including
  ## header" — `yield from self._cells` (table.py:123). `seq[RenderableValue]`
  ## return (the `_cells` list is finite & materialized; matches `RenderResult
  ## = seq[RenderResultItem]`).
  result = self.rawCells

proc flexible*(self: Column): bool =
  ## rich table.py:126-128 — `Column.flexible` (`@property` @125, body
  ## @126-128)->`bool`: "Check if this column is flexible" —
  ## `return self.ratio is not None` (table.py:128).
  result = self.ratio.isSome

proc initRow*(style: StyleOpt = default(StyleOpt), endSection: bool = false): Row =
  ## rich table.py:132-139 — the `Row` dataclass `__init__` (auto-generated,
  ## table.py:135-138): `style: Optional[StyleType]=None`→`StyleOpt` (default
  ## `sokNone`); `end_section: bool=False`→`endSection`.
  new(result)
  result.style = style
  result.endSection = endSection

proc padding*(self: Table): (int, int, int, int) =
  ## rich table.py:354-356 — `Table.padding` (`@property` @353, getter @354-356)->
  ## `Tuple[int,int,int,int]`: "Get cell padding" — `return self._padding`
  ## (table.py:356). Returns the `cellPadding` field (renamed `_padding`).
  result = self.cellPadding

proc `padding=`*(self: Table, padding: PaddingDimensions) =
  ## rich table.py:359-362 — `Table.padding` setter (`@padding.setter` @358, body
  ## @359-362): `self._padding = Padding.unpack(padding); return self`
  ## (table.py:360-361). Nim `=` setter is `void` (chaining not mirrored).
  ## Delegates to `padding.unpack` (the faithful `Padding.unpack` staticmethod).
  self.cellPadding = unpack(padding)

proc extraWidth*(self: Table): int =
  ## rich table.py:296-303 — `Table._extra_width` (`@property` @295, body
  ## @296-303)->`int`: "Get extra width to add to cell content" — `+2` if box &
  ## show_edge, `+len(columns)-1` if box (table.py:297-302). Renamed
  ## `_extra_width`→`extraWidth`.
  result = 0
  if self.box.isSome and self.showEdge:
    result += 2
  if self.box.isSome:
    result += self.columns.len - 1

proc rowCount*(self: Table): int =
  ## rich table.py:306-308 — `Table.row_count` (`@property` @305, body @306-308)->
  ## `int`: "Get the current number of rows" — `return len(self.rows)`
  ## (table.py:308). Renamed `row_count`→`rowCount`.
  result = self.rows.len

proc expand*(self: Table): bool =
  ## rich table.py:286-288 — `Table.expand` (`@property` @285, getter @286-288)->
  ## `bool`: "Setting a non-None self.width implies expand" —
  ## `return self._expand or self.width is not None` (table.py:288). Reads the
  ## `expandField` field (renamed `_expand`) — NOT `self.expand` (which would
  ## recurse on this getter).
  result = self.expandField or self.width.isSome

proc `expand=`*(self: Table, expand: bool) =
  ## rich table.py:291-293 — `Table.expand` setter (`@expand.setter` @290, body
  ## @291-293): `self._expand = expand` (table.py:292). Nim `=` setter is
  ## `void` (Python `return self` chaining not mirrored). Assigns to the
  ## `expandField` field (renamed `_expand`), not the getter.
  self.expandField = expand

# Forward declarations (ordering fix) — `styleValueToStyle`/
# `styleOptToStyle` are defined later (table.nim:819/825) but `getRowStyle`
# (below) calls them; Nim resolves symbols top-to-bottom, so the signatures
# are forward-declared here to unblock the call sites (table.nim:510,514). The
# bodies retain their later definitions.
proc styleValueToStyle(console: ConsoleHandle, sv: StyleValue): Style
proc styleOptToStyle(console: ConsoleHandle, so: StyleOpt): Style

proc getRowStyle*(self: Table, console: ConsoleHandle, index: int): Style =
  ## rich table.py:310-318 — `Table.get_row_style(self, console, index)->
  ## StyleType`: "Get the current row style" — `Style.null()`+row_styles
  ## cycle+row.style (table.py:312-316). Returns `Style` (always builds
  ## `Style.null()+…`, which feeds `console.get_style(:StyleType)` in `_render`).
  ## Renamed `get_row_style`→`getRowStyle`. richbase `ConsoleHandle`.
  #
  # NOW UN-DEFERRED: `console.get_style` is reachable via the `console_api`
  # dispatch interface (the cycle-breaker leaf). Faithfully accumulates the
  # `Style.null()` base (table.py:312) with `console.get_style(
  # self.row_styles[index % len(self.row_styles)])` (table.py:314, guarded by
  # `if self.row_styles`) and `console.get_style(self.rows[index].style)`
  # (table.py:316, guarded by `if row_style is not None`) via `Style +
  # Option[Style]` (Python `+=`). `styleValueToStyle`/`styleOptToStyle` dispatch
  # a `StyleValue`/`StyleOpt` to `console.get_style(:StyleType)`.
  result = Style.null()
  if self.rowStyles.len > 0:
    result = result +
      some(styleValueToStyle(console,
        self.rowStyles[index mod self.rowStyles.len]))
  let rowStyle = self.rows[index].style
  if rowStyle.kind != sokNone:
    result = result + some(styleOptToStyle(console, rowStyle))

proc getPaddingWidth*(self: Table, columnIndex: int): int =
  ## rich table.py:700-714 — `Table._get_padding_width(self, column_index)->
  ## int`: "Get extra width from padding" (table.py:701). Renamed
  ## `_get_padding_width`→`getPaddingWidth`; `column_index`→`columnIndex`.
  let (_, padRight0, _, padLeft0) = self.padding
  var padLeft = padLeft0
  var padRight = padRight0
  if self.collapsePadding:
    padLeft = 0
    padRight = abs(padLeft - padRight)
  if not self.padEdge:
    if columnIndex == 0:
      padLeft = 0
    if columnIndex == self.columns.len - 1:
      padRight = 0
  result = padLeft + padRight

# Forward declaration — `getCells` is defined later (table.nim:911) but
# `measureColumn` (below) measures the `Padding`-wrapped cells it returns
# (table.py:730-752); Nim resolves symbols top-to-bottom, so the signature is
# forward-declared here to unblock the call site. The body retains its later
# definition.
proc getCells*(self: Table, console: ConsoleHandle, columnIndex: int,
               column: Column): seq[Cell]

proc measureColumn*(self: Table, console: ConsoleHandle,
                    options: ConsoleOptions, column: Column): Measurement =
  ## rich table.py:716-753 — `Table._measure_column(self, console, options,
  ## column)->Measurement`: "Get the minimum and maximum width of the column"
  ## (table.py:717). Renamed `_measure_column`→`measureColumn`. The fixed-width
  ## case (table.py:725-728) is fully portable (no `console.*`/`getCells`); the
  ## flexible case (table.py:730-752) measures each cell via `getCells` +
  ## `Measurement.get`.
  let maxWidth = options.maxWidth
  if maxWidth < 1:
    return Measurement(minimum: 0, maximum: 0)
  let paddingWidth = self.getPaddingWidth(column.index)
  if column.width.isSome:
    # Fixed width column (table.py:725-728).
    let w = column.width.get + paddingWidth
    return Measurement(minimum: w, maximum: w).withMaximum(maxWidth)
  # Flexible column — measure the `Padding`-wrapped cells returned by `getCells`
  # (table.py:730-752), faithfully to Python's `Measurement.get(cell.renderable)`
  # where `cell.renderable` is the `Padding` wrap. For a `Padding`-wrapped cell,
  # measure the inner renderable and add the actual `Padding.left +
  # Padding.right` — the real per-cell padding. This differs from the
  # column-level `getPaddingWidth` under `collapsePadding` + `padEdge`: for the
  # first column `getPaddingWidth` collapses `left` to 0 (yielding `0 + right`),
  # but the actual `Padding` wrap from `getCells` keeps `left` (yielding
  # `left + right`), so the column is measured wide enough not to truncate the
  # content (the grid `Colors`→`Colo…` bug). Nim's `Measurement.get`/
  # `Padding.richMeasure` are ports that do NOT dispatch to
  # `__rich_measure__`, so the inner content is measured directly: `Text` via
  # its own `richMeasure` (reads `self.plain`, immune to justify-padding to
  # `maxWidth`); other renderables (strings, `ProgressBar`, …) via
  # `renderLines(..., pad=false)` + `getShape` (natural width). A raw cell (no
  # `anyPadding`) carries no `Padding` wrap, so nothing is added. The
  # column-level `paddingWidth` (`getPaddingWidth`) is still used for the
  # fixed-width case and the `min_width`/`max_width` clamps below, matching
  # Python (table.py:726,751).
  var minWidths: seq[int] = @[]
  var maxWidths: seq[int] = @[]
  let measureOpts = options.resetHeight()
  proc measureInner(con: ConsoleHandle, mopts: ConsoleOptions,
                    rv: RenderableValue): int =
    let it = if rv.kind == rvConsoleRenderable: rv.consoleItem
             elif rv.kind == rvRichCast: rv.castItem
             else: nil
    if not it.isNil and it of Text:
      result = Text(it).richMeasure(con, mopts).maximum
    else:
      result = getShape(con.renderLines(rv, some(mopts), none(Style),
                         pad = false)).columns
  proc cellWidth(con: ConsoleHandle, mopts: ConsoleOptions,
                 rv: RenderableValue): int =
    let it = if rv.kind == rvConsoleRenderable: rv.consoleItem
             elif rv.kind == rvRichCast: rv.castItem
             else: nil
    if not it.isNil and it of Padding:
      let pad = Padding(it)
      result = measureInner(con, mopts, pad.renderable) + pad.left + pad.right
    else:
      result = measureInner(con, mopts, rv)
  for cell in self.getCells(console, column.index, column):
    let w = cellWidth(console, measureOpts, cell.renderable)
    minWidths.add(w); maxWidths.add(w)
  let minimumWidth = if minWidths.len == 0: 1 else: max(minWidths)
  let maximumWidth = if maxWidths.len == 0: maxWidth else: max(maxWidths)
  var measurement = Measurement(minimum: minimumWidth,
                                maximum: maximumWidth).withMaximum(maxWidth)
  measurement = measurement.clamp(
    if column.minWidth.isNone: none(int) else: some(column.minWidth.get + paddingWidth),
    if column.maxWidth.isNone: none(int) else: some(column.maxWidth.get + paddingWidth))
  result = measurement

proc collapseWidths*(T: typedesc[Table], widths: seq[int],
                     wrapable: seq[system.bool], maxWidth: int): seq[int] =
  ## rich table.py:589-625 — `Table._collapse_widths(cls, widths: List[int],
  ## wrapable: List[bool], max_width: int)->List[int]` (`@classmethod`
  ## table.py:589): "Reduce widths so that the total is under max_width"
  ## (table.py:591). `typedesc[Table]` factory; `List[int]`→`seq[int]`,
  ## `List[bool]`→`seq[system.bool]` (`bool` qualified), `max_width`→`maxWidth`.
  ## Renamed `_collapse_widths`→`collapseWidths`. Delegates to
  ## `ratio.ratioReduce` (table.py:616).
  var widths = widths
  var totalWidth = sum(widths)
  var excessWidth = totalWidth - maxWidth
  var anyWrapable = false
  for w in wrapable:
    if w:
      anyWrapable = true
      break
  if anyWrapable:
    while totalWidth != 0 and excessWidth > 0:
      var maxColumn = 0
      var found = false
      for i, w in widths:
        if i < wrapable.len and wrapable[i]:
          if not found or w > maxColumn:
            maxColumn = w
            found = true
      var secondMaxColumn = 0
      for i, w in widths:
        if i < wrapable.len and wrapable[i] and w != maxColumn:
          if w > secondMaxColumn:
            secondMaxColumn = w
      let columnDifference = maxColumn - secondMaxColumn
      var ratios = newSeq[int](widths.len)
      for i, w in widths:
        ratios[i] = if (i < wrapable.len and w == maxColumn and wrapable[i]): 1 else: 0
      var anyRatios = false
      for r in ratios:
        if r != 0:
          anyRatios = true
          break
      if not anyRatios or columnDifference == 0:
        break
      var maxReduce = newSeq[int](widths.len)
      for i in 0 ..< widths.len:
        maxReduce[i] = min(excessWidth, columnDifference)
      widths = ratioReduce(excessWidth, ratios, maxReduce, widths)
      totalWidth = sum(widths)
      excessWidth = totalWidth - maxWidth
  result = widths

proc calculateColumnWidths*(self: Table, console: ConsoleHandle,
                            options: ConsoleOptions): seq[int] =
  ## rich table.py:523-586 — `Table._calculate_column_widths(self, console,
  ## options)->List[int]`: "Calculate the widths of each column, including
  ## padding, not including borders" (table.py:525). `List[int]`→`seq[int]`.
  ## Renamed `_calculate_column_widths`→`calculateColumnWidths`. Delegates to
  ## `measureColumn` + `collapseWidths` + `ratio.ratioDistribute`/
  ## `ratio.ratioReduce` (table.py:547,559,581,616) + `getPaddingWidth` +
  ## `extraWidth`; no direct `console.*` call.
  let maxWidth = options.maxWidth
  let columns = self.columns
  var widthRanges: seq[Measurement] = @[]
  for column in columns:
    widthRanges.add(self.measureColumn(console, options, column))
  var widths: seq[int] = @[]
  for r in widthRanges:
    widths.add(if r.maximum == 0: 1 else: r.maximum)   # `_range.maximum or 1`

  let extraWidth = self.extraWidth
  if self.expand:
    var ratios: seq[int] = @[]
    for col in columns:
      if col.flexible:
        ratios.add(optOr(col.ratio, 0))   # `col.ratio or 0`
    var anyRatio = false
    for r in ratios:
      if r != 0:
        anyRatio = true
        break
    if anyRatio:
      var fixedWidths: seq[int] = @[]
      for i, col in pairs(columns):
        fixedWidths.add(if col.flexible: 0 else: widthRanges[i].maximum)
      var flexMinimum: seq[int] = @[]
      for col in columns:
        if col.flexible:
          flexMinimum.add(optOr(col.width, 1) + self.getPaddingWidth(col.index))
      let flexibleWidth = maxWidth - sum(fixedWidths)
      let flexWidths = ratioDistribute(flexibleWidth, ratios, some(flexMinimum))
      var iterIdx = 0
      for index, column in pairs(columns):
        if column.flexible:
          widths[index] = fixedWidths[index] + flexWidths[iterIdx]
          iterIdx += 1
  var tableWidth = sum(widths)

  if tableWidth > maxWidth:
    var wrapable: seq[system.bool] = @[]
    for column in columns:
      wrapable.add(column.width.isNone and not column.noWrap)
    widths = Table.collapseWidths(widths, wrapable, maxWidth)
    tableWidth = sum(widths)
    if tableWidth > maxWidth:
      let excessWidth = tableWidth - maxWidth
      var ones = newSeq[int](widths.len)
      for i in 0 ..< widths.len:
        ones[i] = 1
      widths = ratioReduce(excessWidth, ones, widths, widths)
      tableWidth = sum(widths)
    widthRanges = @[]
    for i, column in pairs(columns):
      widthRanges.add(self.measureColumn(console,
                                          options.updateWidth(widths[i]), column))
    widths = @[]
    for r in widthRanges:
      widths.add(r.maximum)   # `_range.maximum or 0` == r.maximum
  if (tableWidth < maxWidth and self.expand) or
     (self.minWidth.isSome and tableWidth < (self.minWidth.get - extraWidth)):
    let m = if self.minWidth.isNone: maxWidth
            else: min(self.minWidth.get - extraWidth, maxWidth)
    let padWidths = ratioDistribute(m - tableWidth, widths)
    var newWidths: seq[int] = @[]
    for i, w in widths:
      newWidths.add(w + padWidths[i])
    widths = newWidths

  result = widths

proc richMeasure*(self: Table, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich table.py:320-351 — `Table.__rich_measure__(self, console, options)->
  ## Measurement`: sum calculated column widths + extra width, clamp to
  ## `min_width` (table.py:321-350). richbase `ConsoleHandle`/`ConsoleOptions`;
  ## `Measurement` from `measure.nim`. Delegates to `calculateColumnWidths` +
  ## `measureColumn` + `extraWidth` (all below); no direct `console.*` call.
  var maxWidth = options.maxWidth
  if self.width.isSome:
    maxWidth = self.width.get
  if maxWidth < 0:
    return Measurement(minimum: 0, maximum: 0)
  let extraWidth = self.extraWidth
  maxWidth = sum(self.calculateColumnWidths(console,
              options.updateWidth(maxWidth - extraWidth)))
  var measurements: seq[Measurement] = @[]
  for column in self.columns:
    measurements.add(self.measureColumn(console, options.updateWidth(maxWidth),
                                         column))
  var totalMin = 0
  var totalMax = 0
  for m in measurements:
    totalMin += m.minimum
    totalMax += m.maximum
  let minimumWidth = totalMin + extraWidth
  let maximumWidth = if self.width.isNone: totalMax + extraWidth else: self.width.get
  var measurement = Measurement(minimum: minimumWidth, maximum: maximumWidth)
  measurement = measurement.clamp(self.minWidth)
  result = measurement

proc addColumn*(self: Table, header: RenderableValue = "",
                footer: RenderableValue = "",
                headerStyle: StyleOpt = default(StyleOpt),
                highlight: Option[system.bool] = none(system.bool),
                footerStyle: StyleOpt = default(StyleOpt),
                style: StyleOpt = default(StyleOpt),
                justify: JustifyMethod = jmLeft,
                vertical: VerticalAlignMethod = vamTop,
                overflow: OverflowMethod = omEllipsis,
                width: Option[int] = none(int), minWidth: Option[int] = none(int),
                maxWidth: Option[int] = none(int), ratio: Option[int] = none(int),
                noWrap: bool = false) =
  ## rich table.py:364-420 — `Table.add_column(self, header="", footer="", *,
  ## header_style=None, highlight=None, footer_style=None, style=None,
  ## justify="left", vertical="top", overflow="ellipsis", width=None,
  ## min_width=None, max_width=None, ratio=None, no_wrap=False) -> None`: build
  ## a `Column` and append it (table.py:402-419). Keyword-only after
  ## `header`/`footer` (Python `*`, table.py:366). `header`/`footer:
  ## RenderableType=""`→typeclass (structural + nominal renderables; `int`
  ## rejected); `header_style`/`footer_style`/`style:
  ## Optional[StyleType]=None`→`StyleOpt` (default `sokNone`); `highlight:
  ## Optional[bool]=None`→`Option[system.bool]`; `justify`→`jmLeft`;
  ## `vertical`→`vamTop`; `overflow`→`omEllipsis`; `width`/`minWidth`/`maxWidth`/
  ## `ratio`→`Option[int]`; `noWrap: bool=False`. Renamed `add_column`→
  ## `addColumn`. Delegates to `initColumn` for the non-style fields (styles
  ## default `""`), then overrides the three style fields with the `*_style or
  ## ""` collapse (`styleOptOrEmpty`), matching `Column(header_style=… or "",
  ## footer_style=… or "", style=… or "")` (table.py:407,411,413).
  let highlightVal = if highlight.isSome: highlight.get else: self.highlight
  let column = initColumn(index = self.columns.len, header = header,
                          footer = footer, highlight = highlightVal,
                          justify = justify, vertical = vertical,
                          overflow = overflow, width = width, minWidth = minWidth,
                          maxWidth = maxWidth, ratio = ratio, noWrap = noWrap)
  column.headerStyle = styleOptOrEmpty(headerStyle)
  column.footerStyle = styleOptOrEmpty(footerStyle)
  column.style = styleOptOrEmpty(style)
  self.columns.add(column)

proc addRow*(self: Table, renderables: varargs[RenderableOpt],
             style: StyleOpt = default(StyleOpt), endSection: bool = false) =
  ## rich table.py:422-467 — `Table.add_row(self, *renderables:
  ## Optional[RenderableType], style: Optional[StyleType]=None, end_section:
  ## bool=False) -> None`: "Add a row of renderables" — pad `None` cells to `""`,
  ## append renderables to each column's `_cells`, append a `Row`, raise
  ## `errors.NotRenderableError` for non-renderables (table.py:425-466).
  ## `*renderables: Optional[RenderableType]`→`varargs[RenderableOpt]` (first;
  ## Nim allows `varargs` then defaulted params); the `toRenderableOpt*`
  ## converters accept `string`, any `ConsoleRenderable or RichCast` (structural
  ## + nominal renderables) and `Option[T: RenderableBase]`, so
  ## `addRow("a")`/`addRow(aText)`/`addRow(aStructuralRenderable)`/
  ## `addRow(none(RenderableBase))`/`addRow(some(aText))` all compile and `int`/
  ## `Option[int]` are rejected; `style`→`StyleOpt` (default `sokNone`);
  ## `end_section`→`endSection`. Renamed `add_row`→`addRow`. The `is_renderable`
  ## check (table.py:457) is enforced at compile time by the `toRenderableOpt`
  ## converter (`ConsoleRenderable or RichCast` concept), so the runtime
  ## `NotRenderableError` (table.py:461) is unreachable under static typing.
  var cellRenderables = @renderables
  if cellRenderables.len < self.columns.len:
    for _ in 0 ..< (self.columns.len - cellRenderables.len):
      cellRenderables.add(default(RenderableOpt))
  for index, r in cellRenderables:
    var column: Column
    if index == self.columns.len:
      column = initColumn(index = index, highlight = self.highlight)
      for _ in self.rows:
        column.rawCells.add(initText(""))
      self.columns.add(column)
    else:
      column = self.columns[index]
    case r.kind
    of roNone:
      column.rawCells.add("")
    of roStr:
      column.rawCells.add(r.strv)
    of roRenderable:
      column.rawCells.add(r.renderablev)
  self.rows.add(initRow(style = style, endSection = endSection))

proc addSection*(self: Table) =
  ## rich table.py:469-473 — `Table.add_section(self)->None`: "Add a new section
  ## (draw a line after current row)" — `if self.rows:
  ## self.rows[-1].end_section=True` (table.py:471-472). Renamed
  ## `add_section`→`addSection`.
  if self.rows.len > 0:
    self.rows[self.rows.len - 1].endSection = true

# ---------------------------------------------------------------------------
# port helpers — un-blocking `_get_cells`/`_render` now that the
# `console_api` dispatch (console.getStyle/renderLines/render/measure/
# getSafeBox) reaches table without the console→terminal_theme→palette→table
# import cycle.
# `styleValueToStyle`/`styleOptToStyle` dispatch the `StyleValue`/`StyleOpt`
# tagged unions to `getStyle(StyleType)` (the concept accepts `string`/`Style`).
# `loopFirstLast`/`loopLast` inline rich `_loop.loop_first_last`/`loop_last`.
# `pickBool` inlines rich `_pick.pick_bool` (first non-`None`).
# ---------------------------------------------------------------------------

proc styleValueToStyle(console: ConsoleHandle, sv: StyleValue): Style =
  ## Resolve a `StyleValue` (str|Style) to a `Style` via `console.getStyle`.
  case sv.kind
  of svkStr: result = console.getStyle(sv.strv)
  of svkStyle: result = console.getStyle(sv.stv)

proc styleOptToStyle(console: ConsoleHandle, so: StyleOpt): Style =
  ## Resolve a `StyleOpt` (None|str|Style) to a `Style` via `console.getStyle`.
  ## `None` (sokNone) resolves to the empty-name style (faithful to `or ""`).
  case so.kind
  of sokNone: result = console.getStyle("")
  of sokStr: result = console.getStyle(so.strv)
  of sokStyle: result = console.getStyle(so.stv)

proc pickBool(a, b: Option[system.bool]): bool =
  ## rich `_pick.pick_bool(a, b)` — first non-`None` (else `False`).
  if a.isSome: result = a.get
  elif b.isSome: result = b.get
  else: result = false

proc loopFirstLast[T](s: seq[T]): seq[(bool, bool, T)] =
  ## rich `_loop.loop_first_last(iterable)` → `(first, last, item)` triples.
  result = @[]
  let n = s.len
  for i, item in s:
    result.add((i == 0, i == n - 1, item))

proc loopLast[T](s: seq[T]): seq[(bool, T)] =
  ## rich `_loop.loop_last(iterable)` → `(last, item)` pairs.
  result = @[]
  let n = s.len
  for i, item in s:
    result.add((i == n - 1, item))

proc getCells*(self: Table, console: ConsoleHandle, columnIndex: int,
               column: Column): seq[Cell] =
  ## rich table.py:627-698 — `Table._get_cells(self, console, column_index,
  ## column)->Iterable[_Cell]`: "Get all the cells with padding and optional
  ## header" (table.py:629). Yields finite `_Cell`s → `seq[Cell]`. Renamed
  ## `_get_cells`→`getCells`; `column_index`→`columnIndex`. NOW UN-DEFERRED:
  ## `console.get_style` reachable via the `console_api` dispatch interface.
  let collapsePadding = self.collapsePadding
  let padEdge = self.padEdge
  let padding = self.padding  # (top, right, bottom, left) via table.padding proc
  let anyPadding = padding[0] != 0 or padding[1] != 0 or
                    padding[2] != 0 or padding[3] != 0
  let firstColumn = columnIndex == 0
  let lastColumn = columnIndex == self.columns.len - 1

  proc getPadding(firstRow, lastRow: bool): (int, int, int, int) =
    var (top, right, bottom, left) = padding
    if collapsePadding:
      if not firstColumn: left = max(0, left - right)
      if not lastRow: bottom = max(0, top - bottom)
    if not padEdge:
      if firstColumn: left = 0
      if lastColumn: right = 0
      if firstRow: top = 0
      if lastRow: bottom = 0
    result = (top, right, bottom, left)

  var rawCells: seq[(Style, RenderableValue)] = @[]
  if self.showHeader:
    let headerStyle = styleOptToStyle(console, self.headerStyle) +
                      some(styleValueToStyle(console, column.headerStyle))
    rawCells.add((headerStyle, column.header))
  let cellStyle = styleValueToStyle(console, column.style)
  for cell in column.cells:
    rawCells.add((cellStyle, cell))
  if self.showFooter:
    let footerStyle = styleOptToStyle(console, self.footerStyle) +
                      some(styleValueToStyle(console, column.footerStyle))
    rawCells.add((footerStyle, column.footer))

  result = @[]
  if anyPadding:
    for tup in loopFirstLast(rawCells):
      let (first, last, inner) = tup
      let (style, renderable) = inner
      let pad = getPadding(first, last)
      let padded = initPadding(renderable, pad)
      let paddedRv: RenderableValue = padded
      result.add((toStyleValue(style), paddedRv, column.vertical))
  else:
    for tup in rawCells:
      let (style, renderable) = tup
      result.add((toStyleValue(style), renderable, column.vertical))

# Forward declaration (ordering fix) — `render` is defined later
# (table.nim:975) but `renderConsole` (below) calls `self.render(console,
# renderOptions, widths)` (table.py:510); Nim resolves symbols top-to-bottom,
# so the signature is forward-declared here to unblock the call site
# (table.nim:967). The body retains its later definition.
proc render*(self: Table, console: ConsoleHandle, options: ConsoleOptions,
             widths: seq[int]): RenderResult

method renderConsole*(self: Table, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich table.py:475-521 — `Table.__rich_console__(self, console, options)->
  ## RenderResult`: render title, table body, caption (table.py:476-520).
  ## richbase `ConsoleHandle`/`ConsoleOptions`; `RenderResult` from richbase;
  ## `Segment.line`/`addSegment` from richbase (re-exported by `segment`).
  ##
  ## The empty-table fast path (table.py:477-479: `if not self.columns: yield
  ## Segment("\n"); return`) needs no `Console` and is implemented below — it
  ## emits the faithful newline `Segment`.
  ##
  ## NOW UN-DEFERRED: `console.get_style`/`render_lines`/`render` are reachable
  ## via the `console_api` dispatch interface (cycle-breaker leaf), so the
  ## faithful `__rich_console__` (table.py:476-520) is ported below. Computes
  ## `max_width`/`extra_width`/`widths`/`table_width`/`render_options`
  ## (table.py:481-493), renders the title (table.py:505-508) and caption
  ## (table.py:511-514) annotations via `console.render`, and the body via
  ## `self.render` (table.py:510). `console.render_str` (table.py:501) is
  ## approximated by `initText(text, style)` — `render_str` is deliberately
  ## omitted from `console_api`; it only re-applies markup/highlight, and
  ## `highlight=False` (table.py:501) plus `options.highlight` already govern it.
  result = @[]
  if self.columns.len == 0:
    # rich table.py:477-479 — `if not self.columns: yield Segment("\n"); return`.
    result.addSegment(line())
    return
  let maxWidth = if self.width.isSome: self.width.get else: options.maxWidth
  let extraWidth = self.extraWidth
  let widths = self.calculateColumnWidths(
    console, options.updateWidth(maxWidth - extraWidth))
  let tableWidth = sum(widths) + extraWidth
  let renderOptions = options.update(width = setChange(tableWidth),
                                    highlight = setChange(some(self.highlight)),
                                    height = setChange(none(int)))
  proc renderAnnotation(c: ConsoleHandle, rOpts: ConsoleOptions,
                        text: TableTextOpt, style: StyleOpt,
                        justify: JustifyMethod): RenderResult =
    ## rich table.py:496-503 — `render_annotation(text, style, justify)`: build
    ## the render text then `console.render(render_text, options=
    ## rOpts.update(justify=justify))` via the `console_api` dispatch (NOT
    ## `import console` — the cycle-breaker leaf). The `ttoStr` arm faithfully
    ## ports `console.render_str(text, style=style, highlight=False)`
    ## (table.py:501) via `console_api.renderStrValue` — the real `Console`
    ## override runs the genuine `render_str` (markup parse, console-default
    ## emoji, theme-style as the `Text` base style, `highlight=False`), then
    ## `console.render` renders the wrapped `Text` through
    ## `Text.renderConsole`, which resolves the base style via the real
    ## `Console.getStyle` (theme-aware — e.g. `table.title`->italic) and
    ## justifies it to the table width. The `ttoText` arm passes the `Text`
    ## straight through as a `RenderableValue` (via the `toRenderableValue`
    ## converter — `rvConsoleRenderable`), so it is rendered by the genuine
    ## `Text.renderConsole` pipeline with NO lossy `$` string conversion; a
    ## `Text` title/caption keeps its own spans/style/justify/`end`.
    ##
    ## Trailing-`end` neutralisation (Table-local, the /007
    ## root-cause workaround, now applied uniformly to title AND caption):
    ## Rich's `Text.render` yields the trailing `end` UNSTYLED
    ## (`_Segment(end)`, text.py:734/776). The Nim `Text.render` no-spans fast
    ## path now also emits the `end` UNSTYLED (faithful text.py:734 fix), so a
    ## styled annotation's trailing newline no longer carries the annotation
    ## style; this neutralisation is therefore a confirmatory no-op (it still
    ## re-asserts an unstyled `end` for any future Text path that styles it, and
    ## is kept for defence-in-depth and continuity). The
    ## `console.render` pipeline flattens render results to segments, so the
    ## final `end` reaches here as an `rrkSegment`; neutralise that single
    ## trailing segment's style (segment level, not byte level) so the
    ## annotation emits the styled content then an unstyled `end` exactly like
    ## Rich 15.0.0. Rich's `render_annotation` is shared by both title and
    ## caption (table.py:505-514), so the same neutralisation applies to both.
    ## A `Text` WITH spans already yields an unstyled `end` (spans path,
    ## text.py:776 `yield _Segment(end)`), so the neutralisation is a no-op
    ## there too.
    var renderText: RenderableValue
    case text.kind
    of ttoNone:
      return @[]
    of ttoStr:
      # rich table.py:501 — `console.render_str(text, style=style,
      # highlight=False)` for the string arm: build a `Text` with
      # Rich-equivalent markup/emoji/theme-style resolution via the real
      # `Console`'s `renderStr` (dispatched through `console_api.renderStrValue`),
      # wrapped as a `RenderableValue` for `console_api.render`. `highlight=
      # some(false)` matches `render_annotation`'s explicit `highlight=False`
      # (table.py:501); `emoji`/`markup` default to the Console setting (None),
      # as in Rich. The resolved `Text` (base style = `style`, e.g.
      # `table.title`) is rendered by `console.render` -> `Text.renderConsole`,
      # which resolves the base style via the real `Console.getStyle` and
      # justifies it to the table width.
      renderText = console_api.renderStrValue(c, text.strv, style,
                                               highlight = some(false))
    of ttoText:
      renderText = text.textv
    let opts = rOpts.update(justify = setChange(some(justify)))
    # `c: ConsoleHandle` — call the `Console` override via the `console_api`
    # base method (virtual dispatch), qualified so it is not resolved against
    # the local `Table.render` that the forward declaration above makes visible.
    result = console_api.render(c, renderText, some(opts))
    # Trailing-`end` neutralisation (see proc doc). The `end` for a `ttoStr`
    # is the default `"\n"` of `initText`; for a `ttoText` it is the Text's own
    # `end` attribute (the render path uses `self.end`). Only the final
    # `end`-matching segment is touched — embedded text is left intact.
    let annEnd = case text.kind
                 of ttoNone: ""
                 of ttoStr: "\n"
                 of ttoText: text.textv.`end`
    if annEnd.len > 0 and result.len > 0:
      let lastIdx = result.high
      let lastItem = result[lastIdx]
      if lastItem.kind == rrkSegment and lastItem.segmentItem.text == annEnd:
        result[lastIdx] =
          initRenderResultItem(initSegment(lastItem.segmentItem.text,
                                           none(StyleRef)))
  proc tableTextTruthy(t: TableTextOpt): bool =
    case t.kind
    of ttoNone: false
    of ttoStr: t.strv.len > 0
    of ttoText: t.textv.length > 0
  if tableTextTruthy(self.title):
    let titleStyle = Style.pickFirst(self.titleStyle, "table.title")
    for it in renderAnnotation(console, renderOptions, self.title,
                               titleStyle, self.titleJustify):
      result.add(it)
  for it in self.render(console, renderOptions, widths):
    result.add(it)
  if tableTextTruthy(self.caption):
    let captionStyle = Style.pickFirst(self.captionStyle, "table.caption")
    for it in renderAnnotation(console, renderOptions, self.caption,
                               captionStyle, self.captionJustify):
      result.add(it)

proc render*(self: Table, console: ConsoleHandle, options: ConsoleOptions,
             widths: seq[int]): RenderResult =
  ## rich table.py:755-935 — `Table._render(self, console, options, widths)->
  ## RenderResult`: render the table body — head/row/foot borders, cells
  ## aligned/`set_shape`-d per column, section lines (table.py:756-934).
  ## Renamed `_render`→`render`. richbase `ConsoleHandle`/`ConsoleOptions`;
  ## `RenderResult` from richbase. Body needs `Segment`
  ## (table.py:766-783) + `Box.substitute`/`get_row`/`get_top`/`get_bottom`
  ## (table.py:762,770,933) + `_loop.loop_first_last`/`loop_last`
  ## (table.py:836,852) + `_pick.pick_bool` (table.py:761) + `getRowStyle`/
  ## `getCells`/`measureColumn`.
  #
  # NOW UN-DEFERRED: `console.get_style`/`render_lines` are reachable via the
  # `console_api` dispatch interface; `Box.substitute`/`get_top`/`get_row`/
  # `get_bottom`/`getPlainHeadedBox` (box.nim) and `Segment.line`/`align_top`/
  # `align_middle`/`align_bottom`/`set_shape` (segment.nim) are available, so the
  # faithful `_render` (table.py:756-934) is ported below. `pick_bool` uses the
  # real Console `safe_box` preference via `console_api.getSafeBox` (the
  # cycle-breaking dispatch interface), so an explicit Table `safe_box` takes
  # precedence and otherwise the real Console value decides box substitution
  # (rich 15.0.0 `pick_bool(self.safe_box, console.safe_box)`).
  result = @[]
  let tableStyle = styleValueToStyle(console, self.style)
  let borderStyle = tableStyle + some(styleOptToStyle(console, self.borderStyle))
  # `_column_cells = (self._get_cells(console, i, column) for i, column in
  # enumerate(self.columns)); row_cells = list(zip(*_column_cells))`
  # (table.py:762-766): transpose per-column cells into per-row cell tuples.
  var columnCells: seq[seq[Cell]] = @[]
  for columnIndex, column in self.columns:
    columnCells.add(self.getCells(console, columnIndex, column))
  var rowCells: seq[seq[Cell]] = @[]
  if columnCells.len > 0:
    var nRows = columnCells[0].len
    for col in columnCells:
      if col.len < nRows: nRows = col.len
    for r in 0..<nRows:
      var row: seq[Cell] = @[]
      for col in columnCells:
        row.add(col[r])
      rowCells.add(row)
  # `_box` (table.py:768-774): substitute then `get_plain_headed_box` if no
  # header. `pick_bool(self.safe_box, console.safe_box)` — the real Console
  # `safe_box` is resolved via the `console_api.getSafeBox` dispatch method
  # (rich 15.0.0: explicit Table `safe_box` takes precedence, else Console value).
  var boxOpt: Option[Box] = none(Box)
  if self.box.isSome:
    boxOpt = some(self.box.get.substitute(options,
                                           pickBool(self.safeBox,
                                                   some(console.getSafeBox()))))
  if boxOpt.isSome and not self.showHeader:
    boxOpt = some(boxOpt.get.getPlainHeadedBox())
  let newLine = line()
  let hasBox = boxOpt.isSome
  var boxSegments: seq[(Segment, Segment, Segment)] = @[]
  if hasBox:
    let b = boxOpt.get
    boxSegments = @[
      (Segment(text: b.headLeft, style: some(StyleRef(borderStyle))),
       Segment(text: b.headRight, style: some(StyleRef(borderStyle))),
       Segment(text: b.headVertical, style: some(StyleRef(borderStyle)))),
      (Segment(text: b.midLeft, style: some(StyleRef(borderStyle))),
       Segment(text: b.midRight, style: some(StyleRef(borderStyle))),
       Segment(text: b.midVertical, style: some(StyleRef(borderStyle)))),
      (Segment(text: b.footLeft, style: some(StyleRef(borderStyle))),
       Segment(text: b.footRight, style: some(StyleRef(borderStyle))),
       Segment(text: b.footVertical, style: some(StyleRef(borderStyle)))),
    ]
    if self.showEdge:
      result.addSegment(Segment(text: b.getTop(widths),
                                style: some(StyleRef(borderStyle))))
      result.addSegment(newLine)
  # `align_cell` (table.py:829-843): override vertical alignment for header
  # (bottom) / footer (top) rows, then delegate to `Segment.align_*`.
  proc alignCell(cellLines: seq[seq[Segment]], vertical: VerticalAlignMethod,
                 width: int, style: Style, hr: bool, fr: bool,
                 rh: int): seq[seq[Segment]] =
    var v = vertical
    if hr: v = vamBottom
    elif fr: v = vamTop
    if v == vamTop:
      result = alignTop(cellLines, width, rh, style)
    elif v == vamMiddle:
      result = alignMiddle(cellLines, width, rh, style)
    else:
      result = alignBottom(cellLines, width, rh, style)
  # Main loop over `row_cells` (table.py:845-934).
  for index, tup in loopFirstLast(rowCells):
    let (first, last, rowCell) = tup
    let headerRow = first and self.showHeader
    let footerRow = last and self.showFooter
    let rowIdx = if self.showHeader: index - 1 else: index
    let rowOpt =
      if not headerRow and not footerRow: some(self.rows[rowIdx])
      else: none(Row)
    var maxHeight = 1
    var cells: seq[seq[seq[Segment]]] = @[]
    let rowStyle =
      if headerRow or footerRow: Style.null()
      else: self.getRowStyle(console, rowIdx)
    for i in 0..<rowCell.len:
      let w = widths[i]
      let cell = rowCell[i]
      let column = self.columns[i]
      let cellOptions = options.update(width = setChange(w),
                                       justify = setChange(some(column.justify)),
                                       no_wrap = setChange(some(column.noWrap)),
                                       overflow = setChange(some(column.overflow)),
                                       height = setChange(none(int)),
                                       highlight = setChange(some(column.highlight)))
      let lines = console.renderLines(cell.renderable, some(cellOptions),
        style = some(styleValueToStyle(console, cell.style) + some(rowStyle)))
      if lines.len > maxHeight: maxHeight = lines.len
      cells.add(lines)
    var rowHeight = 0
    for c in cells:
      if c.len > rowHeight: rowHeight = c.len
    # `cells[:] = [set_shape(align_cell(...), width, max_height) ...]`
    # (table.py:857-866).
    for i in 0..<cells.len:
      let w = widths[i]
      let cellOrig = rowCell[i]
      let colStyle = styleValueToStyle(console, cellOrig.style) + some(rowStyle)
      let aligned = alignCell(cells[i], cellOrig.vertical, w, colStyle,
                              headerRow, footerRow, rowHeight)
      cells[i] = setShape(aligned, w, some(maxHeight))
    if hasBox:
      let b = boxOpt.get
      if last and self.showFooter:
        result.addSegment(Segment(text: b.getRow(widths, blFoot,
                                                 edge = self.showEdge),
                                  style: some(StyleRef(borderStyle))))
        result.addSegment(newLine)
      let segs =
        if first: boxSegments[0]
        elif last: boxSegments[2]
        else: boxSegments[1]
      let (left, right, divider0) = segs
      # Whitespace divider gets the row background style (table.py:877-883).
      let bg = rowStyle.backgroundStyle
      let divStyle = bg +
        (if divider0.style.isSome: some(Style(divider0.style.get))
         else: none(Style))
      let divider =
        if strip(divider0.text).len > 0: divider0
        else: Segment(text: divider0.text, style: some(StyleRef(divStyle)))
      for lineNo in 0..<maxHeight:
        if self.showEdge:
          result.addSegment(left)
        for tup2 in loopLast(cells):
          let (lastCell, renderedCell) = tup2
          for seg in renderedCell[lineNo]:
            result.addSegment(seg)
          if not lastCell:
            result.addSegment(divider)
        if self.showEdge:
          result.addSegment(right)
        result.addSegment(newLine)
    else:
      for lineNo in 0..<maxHeight:
        for renderedCell in cells:
          for seg in renderedCell[lineNo]:
            result.addSegment(seg)
        result.addSegment(newLine)
    if hasBox and first and self.showHeader:
      let b = boxOpt.get
      result.addSegment(Segment(text: b.getRow(widths, blHead,
                                               edge = self.showEdge),
                                style: some(StyleRef(borderStyle))))
      result.addSegment(newLine)
    let endSection = rowOpt.isSome and rowOpt.get.endSection
    if hasBox and (self.showLines or self.leading > 0 or endSection):
      let b = boxOpt.get
      if not last and not (self.showFooter and index >= rowCells.len - 2) and
         not (self.showHeader and headerRow):
        if self.leading > 0:
          result.addSegment(Segment(
            text: repeat(b.getRow(widths, blMid, edge = self.showEdge),
                          self.leading),
            style: some(StyleRef(borderStyle))))
        else:
          result.addSegment(Segment(text: b.getRow(widths, blRow,
                                                    edge = self.showEdge),
                                    style: some(StyleRef(borderStyle))))
        result.addSegment(newLine)
  if hasBox and self.showEdge:
    let b = boxOpt.get
    result.addSegment(Segment(text: b.getBottom(widths),
                              style: some(StyleRef(borderStyle))))
    result.addSegment(newLine)
proc initTable*(headers: varargs[TableHeader],
                title: TableTextOpt = default(TableTextOpt),
                caption: TableTextOpt = default(TableTextOpt),
                width: Option[int] = none(int), minWidth: Option[int] = none(int),
                box: Option[Box] = some(HEAVY_HEAD),
                safeBox: Option[system.bool] = none(system.bool),
                padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                collapsePadding: bool = false, padEdge: bool = true,
                expand: bool = false, showHeader: bool = true,
                showFooter: bool = false, showEdge: bool = true,
                showLines: bool = false, leading: int = 0,
                style: StyleType = "none",
                rowStyles: Option[seq[StyleValue]] = none(seq[StyleValue]),
                headerStyle: StyleOpt = StyleOpt(kind: sokStr, strv: "table.header"),
                footerStyle: StyleOpt = StyleOpt(kind: sokStr, strv: "table.footer"),
                borderStyle: StyleOpt = default(StyleOpt),
                titleStyle: StyleOpt = default(StyleOpt),
                captionStyle: StyleOpt = default(StyleOpt),
                titleJustify: JustifyMethod = jmCenter,
                captionJustify: JustifyMethod = jmCenter,
                highlight: bool = false): Table =
  ## rich table.py:188-250 — `Table.__init__(self, *headers: Union[Column,str],
  ## title: Optional[TextType]=None, caption: Optional[TextType]=None, width:
  ## Optional[int]=None, min_width: Optional[int]=None, box:
  ## Optional[box.Box]=box.HEAVY_HEAD, safe_box: Optional[bool]=None, padding:
  ## PaddingDimensions=(0,1), collapse_padding: bool=False, pad_edge: bool=True,
  ## expand: bool=False, show_header: bool=True, show_footer: bool=False,
  ## show_edge: bool=True, show_lines: bool=False, leading: int=0, style:
  ## StyleType="none", row_styles: Optional[Iterable[StyleType]]=None,
  ## header_style: Optional[StyleType]="table.header", footer_style:
  ## Optional[StyleType]="table.footer", border_style: Optional[StyleType]=None,
  ## title_style: Optional[StyleType]=None, caption_style: Optional[StyleType]
  ## =None, title_justify: JustifyMethod="center", caption_justify:
  ## JustifyMethod="center", highlight: bool=False) -> None`: store fields
  ## (table.py:217-243) + add `*headers` (str→`add_column`, else a `Column`,
  ## table.py:244-249). `*headers: Union[Column,str]`→`varargs[TableHeader]`
  ## (first; Nim allows `varargs` then defaulted params, matching Python's
  ## `*headers, …`); `title`/`caption`→`TableTextOpt` (default `ttoNone`);
  ## `box`→`Option[Box]` (default `some(HEAVY_HEAD)`, can be `None`);
  ## `safe_box`→`Option[system.bool]`; `padding`→`PaddingDimensions(kind:
  ## pdPair, pair:(0,1))`; `row_styles: Optional[Iterable[StyleType]]`→
  ## `R: RowStylesArg` (the non-narrowing concept — accepts `None`,
  ## `seq[string]`/`seq[Style]`, or a closure iterator yielding `StyleType`;
  ## rejects `seq[int]`/`iterator(): int`/`int`; the FIELD materializes to
  ## `seq[StyleValue]` via `list(row_styles or [])`, table.py:243), default
  ## `none(seq[StyleValue])` (the `None` arm — `R` inferred from the default
  ## when `rowStyles` is omitted); `header_style`/`footer_style` defaults
  ## `"table.header"`/`"table.footer"`→`StyleOpt(kind: sokStr, strv:…)`;
  ## other `*_style`→`StyleOpt` default `sokNone`; `style: StyleType="none"`→
  ## `StyleType` typeclass default `"none"`; `title_justify`/`caption_justify`
  ## →`jmCenter`. The `*_style or ""` collapse (table.py:233-235) maps
  ## `sokNone`→`StyleOpt(kind: sokStr, strv: "")`, else keeps the value; the
  ## `style` typeclass param converts to the `StyleValue` field via
  ## `toStyleValue`.
  new(result)
  result.columns = @[]
  result.rows = @[]
  result.title = title
  result.caption = caption
  result.width = width
  result.minWidth = minWidth
  result.box = box
  result.safeBox = safeBox
  result.cellPadding = unpack(padding)
  result.padEdge = padEdge
  result.expandField = expand
  result.showHeader = showHeader
  result.showFooter = showFooter
  result.showEdge = showEdge
  result.showLines = showLines
  result.leading = leading
  result.collapsePadding = collapsePadding
  result.style = style
  result.headerStyle = if headerStyle.kind == sokNone: StyleOpt(kind: sokStr, strv: "") else: headerStyle
  result.footerStyle = if footerStyle.kind == sokNone: StyleOpt(kind: sokStr, strv: "") else: footerStyle
  result.borderStyle = borderStyle
  result.titleStyle = titleStyle
  result.captionStyle = captionStyle
  result.titleJustify = titleJustify
  result.captionJustify = captionJustify
  result.highlight = highlight
  result.rowStyles = materializeRowStyles(rowStyles)
  for header in headers:
    case header.kind
    of thStr:
      result.addColumn(header = header.strv)
    of thColumn:
      let col = header.columnv
      col.index = result.columns.len
      result.columns.add(col)

proc grid*(T: typedesc[Table], headers: varargs[TableHeader],
           padding: PaddingDimensions = default(PaddingDimensions),
           collapsePadding: bool = true, padEdge: bool = false,
           expand: bool = false): Table =
  ## rich table.py:253-283 — `Table.grid(cls, *headers, padding=0,
  ## collapse_padding=True, pad_edge=False, expand=False)->Table`
  ## (`@classmethod` table.py:252): "Get a table with no lines, headers, or
  ## footer" — `cls(*headers, box=None, …, show_header=False, show_footer=False,
  ## show_edge=False, pad_edge=pad_edge, expand=expand)` (table.py:278-283).
  ## `typedesc[Table]` factory (`Table.grid(…)`); `box`/`show_*` fixed in body.
  ## `padding=0`→`default(PaddingDimensions)`(=`pdInt(0)`). The varargs
  ## `*headers` cannot be forwarded into `initTable`'s varargs param from a
  ## seq, so the table is built with no headers (the fixed `box=None`/`show_*`
  ## args) and the headers are then appended exactly as `initTable` does
  ## (str→`addColumn`, `Column`→ set `index` + append).
  result = initTable(box = none(Box), padding = padding,
                     collapsePadding = collapsePadding, showHeader = false,
                     showFooter = false, showEdge = false, padEdge = padEdge,
                     expand = expand)
  for header in headers:
    case header.kind
    of thStr:
      result.addColumn(header = header.strv)
    of thColumn:
      let col = header.columnv
      col.index = result.columns.len
      result.columns.add(col)

