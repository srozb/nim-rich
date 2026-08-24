## Port of `rich.columns` (rich/columns.py).
##
## `Columns` displays renderables in neat columns (columns.py:16-171).
##
## Import graph (rich/columns.py:1-13): runtime sibling imports are
## `from collections import defaultdict` (columns.py:1, body-only —
## `__rich_console__` @75), `from itertools import chain` (columns.py:2,
## body-only — @108), `from operator import itemgetter` (columns.py:3, body-only
## — @144), `from .align import Align, AlignMethod` (columns.py:6),
## `from .console import Console, ConsoleOptions, RenderableType, RenderResult`
## (columns.py:7), `from .constrain import Constrain` (columns.py:8, body-only
## — @153), `from .measure import Measurement` (columns.py:9, body-only —
## @78), `from .padding import Padding, PaddingDimensions` (columns.py:10,
## body-only — `Padding.unpack` @72), `from .table import Table` (columns.py:11,
## body-only — @119,126 + the `title` type), `from .text import TextType`
## (columns.py:12), `from .jupyter import JupyterMixin` (columns.py:13, the
## base); `from typing import Dict, Iterable, List, Optional, Tuple`
## (columns.py:4).
##
## wiring: `import std/options`; `import richbase` (ConsoleHandle,
## ConsoleOptions, RenderResult, RenderableBase, RenderableType — the
## `.console` runtime imports mapped to richbase placeholders; `columns.py`
## does NOT import `segment`); `import align` (Align, AlignMethod); `import
## constrain` (Constrain); `import measure` (Measurement); `import padding`
## (Padding, PaddingDimensions); `import table` (Table, `TableTextOpt` — the
## `Optional[TextType]` handle for the `title` field/param); `import text`
## (TextType); `import api_types` (RenderableValue — the storable
## `RenderableType` handle for the `renderables` field). `defaultdict`/
## `chain`/`itemgetter` (columns.py:1-3), `Constrain` (columns.py:8),
## `Measurement`/`Padding`/`Table` body usages (columns.py:9,10,11) and
## `jupyter` (columns.py:13) are body/base deps — `Measurement`/`Padding`/
## `Constrain`/`Table` are used in `__rich_console__` bodies; `Table` is also the
## `title` type carrier; `JupyterMixin` modelled via `RenderableBase`. `console`
## types are runtime in Python — supplied via richbase placeholders.
##
## `Columns(JupyterMixin)` is `ref object of RenderableBase` (reference
## semantics). `renderables: Optional[Iterable[RenderableType]] = None`
## (columns.py:33) → field `renderables*: seq[RenderableValue]` (materialized
## via `list(renderables or [])`, columns.py:44); the param is split into THREE
## overloads — `Option[seq[RenderableValue]]` (default `none`, the `None` arm),
## `openArray[RenderableType]` (any seq/array of `RenderableType`, the
## `measure.nim` pattern) and `proc [T: RenderableType](renderables:
## iterator(): T {.closure.})` (a closure iterator — the `Iterable` arm that
## `openArray` cannot cover) — so `Columns()`, `Columns(none(…))`,
## `Columns(@["a","b"])` (seq[str]), `Columns(@[aText])` (seq[Text]) AND
## `Columns(iterator(): string)`/`Columns(iterator(): aStructuralRenderable)`
## ALL compile (non-narrowing for `Optional[Iterable[RenderableType]]`;
## `iterator(): int` is rejected by the `T: RenderableType` constraint). The
## combined `Option[…] or openArray[…]` typeclass triggers concept-resolution
## issues, so three discrete overloads are used (the `containers.nim` pattern).
## `padding: PaddingDimensions = (0, 1)` (columns.py:34) →
## `PaddingDimensions(kind: pdPair, pair: (0, 1))`; `width: Optional[int] =
## None` → `Option[int]`; `expand`/`equal`/`column_first`/`right_to_left: bool =
## False` → bare `bool` (fields `expand*`/`equal*`/`columnFirst*`/`rightToLeft*`);
## `align: Optional[AlignMethod] = None` → `Option[AlignMethod]`; `title:
## Optional[TextType] = None` → `TableTextOpt` (from `table.nim`, default
## `ttoNone` — the shared `Optional[TextType]` for the `Table`↔`columns`
## boundary). `add_renderable` takes the faithful `RenderableType` typeclass
## (structural + nominal renderables; `int` rejected). Naming: `__init__`→
## `initColumns`, `add_renderable`→`addRenderable`, `__rich_console__`→
## `renderConsole`. Proc bodies mirror the Python source.

import std/options

import richbase     # ConsoleHandle, ConsoleOptions, RenderResult, RenderableBase,
                    # RenderableType.
import align        # Align, AlignMethod.
import constrain    # Constrain (body dep; imported for graph faithfulness).
import measure      # Measurement (body dep; imported for graph faithfulness).
import padding      # Padding, PaddingDimensions (Padding body dep).
import box          # Box (Nim-specific: the `initTable(box = none(Box), ...)`
                    # grid construction needs `Box` in scope; Nim imports are
                    # non-transitive — `table` imports `box` but does not
                    # re-export `Box`; `columns.py` itself does NOT import box).
import table        # Table, TableTextOpt (the Optional[TextType] handle).
import text         # TextType.
import api_types    # RenderableValue.
import console_api  # ConsoleHandle dispatch — renderLines/renderStrValue (body dep).
import segment      # getShape + Style (Nim measurement workaround: Nim's
                    # `Measurement.get` is a stub, so the bare content width is
                    # recovered from `renderLines(..., pad=false)` + `getShape`;
                    # `columns.py` itself does NOT import segment).

type
  Columns* = ref object of RenderableBase
    ## rich columns.py:16-171 — `class Columns(JupyterMixin)`: display
    ## renderables in neat columns. `ref object of RenderableBase` (reference
    ## semantics; `JupyterMixin` modelled via `RenderableBase`). Fields mirror
    ## the `__init__` assignments (columns.py:44-52).
    renderables*: seq[RenderableValue]
      ## rich columns.py:44-44 — `self.renderables = list(renderables or [])` (`Optional[Iterable[RenderableType]]`; materialized `seq[RenderableValue]`).
    width*: Option[int]
      ## rich columns.py:45-45 — `self.width = width` (`Optional[int]`; `Option[int]`).
    padding*: PaddingDimensions
      ## rich columns.py:46-46 — `self.padding = padding` (`PaddingDimensions`; default `(0, 1)`).
    expand*: bool
      ## rich columns.py:47-47 — `self.expand = expand` (`bool`; default `False`).
    equal*: bool
      ## rich columns.py:48-48 — `self.equal = equal` (`bool`; default `False`).
    columnFirst*: bool
      ## rich columns.py:49-49 — `self.column_first = column_first` (`bool`; default `False`).
    rightToLeft*: bool
      ## rich columns.py:50-50 — `self.right_to_left = right_to_left` (`bool`; default `False`).
    align*: Option[AlignMethod]
      ## rich columns.py:51-51 — `self.align: Optional[AlignMethod] = align` (`Optional[AlignMethod]`; `Option[AlignMethod]`, default `none`).
    title*: TableTextOpt
      ## rich columns.py:52-52 — `self.title = title` (`Optional[TextType]`; the `table.TableTextOpt` case object, default `ttoNone`).

proc initColumns*(renderables: Option[seq[RenderableValue]] = none(seq[RenderableValue]),
                  padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                  width: Option[int] = none(int), expand: bool = false,
                  equal: bool = false, columnFirst: bool = false,
                  rightToLeft: bool = false,
                  align: Option[AlignMethod] = none(AlignMethod),
                  title: TableTextOpt = default(TableTextOpt)): Columns =
  ## rich columns.py:31-52 — `Columns.__init__(self, renderables:
  ## Optional[Iterable[RenderableType]] = None, padding: PaddingDimensions =
  ## (0, 1), *, width: Optional[int] = None, expand: bool = False, equal: bool
  ## = False, column_first: bool = False, right_to_left: bool = False, align:
  ## Optional[AlignMethod] = None, title: Optional[TextType] = None) -> None`
  ## (the `None`/Option overload): store the fields (columns.py:44-52).
  ## `renderables` default `none(seq[RenderableValue])` is the `None` arm
  ## (`Columns()` ⇒ empty). `padding` default `(0, 1)` →
  ## `PaddingDimensions(kind: pdPair, pair: (0, 1))`; `width` default `None` →
  ## `none(int)`; `expand`/`equal`/`column_first`/`right_to_left` default
  ## `False`; `align` default `None` → `none(AlignMethod)`; `title` default
  ## `None` → `default(TableTextOpt)` (`ttoNone`). Keyword-only after `padding`
  ## (Python `*`, columns.py:34). One of three overloads (Option/openArray/
  ## closure-iterator) covering `Optional[Iterable[RenderableType]]`
  ## non-narrowingly.
  result = Columns()
  if renderables.isSome:
    result.renderables = renderables.get
  else:
    result.renderables = @[]
  result.width = width
  result.padding = padding
  result.expand = expand
  result.equal = equal
  result.columnFirst = columnFirst
  result.rightToLeft = rightToLeft
  result.align = align
  result.title = title

proc initColumns*(renderables: openArray[RenderableValue],
                  padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                  width: Option[int] = none(int), expand: bool = false,
                  equal: bool = false, columnFirst: bool = false,
                  rightToLeft: bool = false,
                  align: Option[AlignMethod] = none(AlignMethod),
                  title: TableTextOpt = default(TableTextOpt)): Columns =
  ## rich columns.py:31-52 — `Columns.__init__(…)` (the iterable overload):
  ## `self.renderables = list(renderables or [])` (columns.py:44).
  ## `Iterable[RenderableType]` → `openArray[RenderableType]` (the `measure.nim`
  ## pattern; accepts `seq[string]`/`seq[Text]`/arrays). One of three overloads
  ## (Option/openArray/closure-iterator) covering
  ## `Optional[Iterable[RenderableType]]` non-narrowingly. Same remaining params
  ## as the `Option` overload.
  # Materialise `list(renderables or [])` (columns.py:44) for the `openArray` arm —
  # element-wise `toRenderableValue` (a `RenderableType` element → a
  # `RenderableValue` slot), then delegate field storage to the `Option`
  # overload (Python `list(renderables)` → a non-`None` `Optional[Iterable]`).
  var rs = newSeq[RenderableValue](renderables.len)
  for i, r in renderables:
    rs[i] = r
  result = initColumns(some(rs), padding, width, expand, equal, columnFirst,
                       rightToLeft, align, title)

proc initColumns*[T: RenderableType](renderables: iterator(): T {.closure.},
                  padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                  width: Option[int] = none(int), expand: bool = false,
                  equal: bool = false, columnFirst: bool = false,
                  rightToLeft: bool = false,
                  align: Option[AlignMethod] = none(AlignMethod),
                  title: TableTextOpt = default(TableTextOpt)): Columns =
  ## rich columns.py:31-52 — `Columns.__init__(…)` (the closure-iterator
  ## overload): `self.renderables = list(renderables or [])` (columns.py:44).
  ## `Iterable[RenderableType]` accepts any iterator/generator; the
  ## closure-iterator overload (`T: RenderableType`) covers the `Iterable` arm
  ## that `openArray` cannot — `iterator(): string`/`iterator(): Text`/
  ## `iterator(): <a structural ConsoleRenderable>` all compile (non-narrowing),
  ## while `iterator(): int` is rejected by the `T: RenderableType` constraint
  ## (int is not `ConsoleRenderable`/`RichCast`/`str`). One of three overloads
  ## (Option/openArray/closure-iterator) covering
  ## `Optional[Iterable[RenderableType]]` non-narrowingly. Same remaining
  ## params as the `Option` overload.
  # Materialise `list(renderables or [])` (columns.py:44) for the closure-
  # iterator arm — drain the iterator, appending each `RenderableType` element as
  # a `RenderableValue` (via `toRenderableValue`), then delegate field storage
  # to the `Option` overload.
  var rs: seq[RenderableValue] = @[]
  for r in renderables:
    rs.add(r)
  result = initColumns(some(rs), padding, width, expand, equal, columnFirst,
                       rightToLeft, align, title)

proc addRenderable*(self: Columns, renderable: RenderableValue) =
  ## rich columns.py:54-60 — `Columns.add_renderable(self, renderable:
  ## RenderableType) -> None`: "Add a renderable to the columns" —
  ## `self.renderables.append(renderable)` (columns.py:60). The faithful
  ## `RenderableType` typeclass param (richbase — structural + nominal
  ## renderables; `int` rejected). Renamed `add_renderable`→`addRenderable`.
  self.renderables.add(renderable)

method renderConsole*(self: Columns, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich columns.py:62-171 — `Columns.__rich_console__(self, console,
  ## options) -> RenderResult`: arrange renderables into columns (auto-detect or
  ## fixed column count), build a `Table.grid` and yield it. Faithful port.
  ##
  ## Nim deviation (measurement): Python measures each renderable via
  ## `Measurement.get(console, options, renderable).maximum` (columns.py:78) and
  ## lets `Table` use FLEXIBLE columns (width=None) whose `measureColumn`
  ## measures the `Padding`-wrapped cells. Nim's `Measurement.get`/flexible
  ## `measureColumn` are stubs returning the `(1, max_width)` fallback, so the
  ## bare content width is recovered here from `console.renderLines(...,
  ## pad=false)` + `getShape` on a height-reset copy (`resetHeight` ⇒ no height
  ## padding ⇒ `getShape` = natural max line length), and the grid columns are
  ## given EXPLICIT widths = the per-column max content width. The fixed-width
  ## `measureColumn` returns `column.width + getPaddingWidth(col)` (content +
  ## per-column padding, including the `pad_edge=False` last-column right-strip),
  ## which is byte-identical to Python's flexible `measureColumn` (the
  ## `Padding`-wrapped cell measure), so `calculateColumnWidths`/
  ## `ratioDistribute` see exactly the widths Python would. `console.renderLines`/
  ## `renderStrValue` are reached via the `console_api` dispatch leaf (no
  ## `columns`→`console` cycle — `console_api` does not import `columns`).
  result = @[]
  # columns.py:65-69 — `render_str(renderable) if isinstance(renderable, str)`.
  var renderables: seq[RenderableValue] = @[]
  for r in self.renderables:
    case r.kind
    of rvString:
      renderables.add(console.renderStrValue(r.textStr))
    of rvConsoleRenderable, rvRichCast:
      renderables.add(r)
  if renderables.len == 0:
    return  # columns.py:71 — `if not renderables: return`.

  # columns.py:72-74 — `Padding.unpack`; `width_padding = max(left, right)`.
  let pad = unpack(self.padding)
  let padRight = pad[1]
  let padLeft = pad[3]
  let widthPadding = max(padLeft, padRight)
  let maxWidth = options.maxWidth

  # columns.py:77-79 — `renderable_widths` (Nim: via `renderLines`+`getShape`).
  let measureOpts = options.resetHeight()
  var widths0: seq[int] = @[]
  for r in renderables:
    let lines = console.renderLines(r, some(measureOpts), none(Style), pad = false)
    widths0.add(getShape(lines).columns)
  let renderableWidths: seq[int] =
    if self.equal:  # columns.py:81-82 — `[max(renderable_widths)] * len`.
      var mx = 0
      for w in widths0:
        if w > mx: mx = w
      var ws = newSeq[int](widths0.len)
      for i in 0 ..< widths0.len:
        ws[i] = mx
      ws
    else:
      widths0

  let itemCount = renderables.len

  # columns.py:84-116 — `iter_renderables(column_count)` generator. Returns the
  # ordered `(renderable_width, index | -1)` list (`-1` ⇒ `None` padding cell).
  proc iterRenderables(cc: int): seq[(int, int)] =
    result = @[]
    if self.columnFirst:
      # columns.py:88-108 — column-major fill of `cells`, then a row-major
      # (`chain.from_iterable`) traversal yielding until the first `-1` (break).
      var columnLengths = newSeq[int](cc)
      for col in 0 ..< cc:
        columnLengths[col] = itemCount div cc
      for col in 0 ..< (itemCount mod cc):
        columnLengths[col] += 1
      let rowCount = (itemCount + cc - 1) div cc
      var cells = newSeq[seq[int]](rowCount)
      for r in 0 ..< rowCount:
        cells[r] = newSeq[int](cc)
        for c in 0 ..< cc:
          cells[r][c] = -1
      var row = 0
      var col = 0
      for index in 0 ..< itemCount:
        cells[row][col] = index
        columnLengths[col] -= 1
        if columnLengths[col] > 0:  # Python `if column_lengths[col]:` (truthy).
          row += 1
        else:
          col += 1
          row = 0
      var broke = false
      for r in 0 ..< rowCount:
        for c in 0 ..< cc:
          let idx = cells[r][c]
          if idx == -1:
            broke = true
            break
          result.add((renderableWidths[idx], idx))
        if broke:
          break
    else:
      # columns.py:110 — `yield from zip(renderable_widths, renderables)`.
      for i in 0 ..< itemCount:
        result.add((renderableWidths[i], i))
    # columns.py:113-116 — pad odd elements with `(0, None)`. Runs for BOTH
    # branches (the column-first `break` only exits the inner traversal, not
    # the generator, so this is reached there too).
    if itemCount mod cc != 0:
      for _ in 0 ..< (cc - (itemCount mod cc)):
        result.add((0, -1))

  # columns.py:119-122 — the grid table. Built via the `initTable`
  # grid-equivalent construction (`Table.grid` is just a thin wrapper over
  # this — `box` imported explicitly because Nim imports are non-transitive).
  var table = initTable(box = none(Box), padding = self.padding,
                        collapsePadding = true, showHeader = false,
                        showFooter = false, showEdge = false, padEdge = false,
                        expand = self.expand)
  table.title = self.title

  var columnCount = itemCount
  if self.width.isSome:
    # columns.py:124-127 — fixed column count from the desired column width.
    columnCount = maxWidth div (self.width.get + widthPadding)
    for _ in 0 ..< columnCount:
      table.addColumn(width = self.width)
  else:
    # columns.py:128-141 — auto-detect: reduce `column_count` while the summed
    # per-column widths + inter-column `width_padding` overflow `max_width`.
    while columnCount > 1:
      var widthsArr = newSeq[int](columnCount)
      var touched = newSeq[system.bool](columnCount)
      var touchedCount = 0
      var columnNo = 0
      var overflowed = false
      for (renderableWidth, _) in iterRenderables(columnCount):
        if not touched[columnNo]:
          touched[columnNo] = true
          touchedCount += 1
        if renderableWidth > widthsArr[columnNo]:
          widthsArr[columnNo] = renderableWidth
        var total = 0
        for w in widthsArr:
          total += w
        total += widthPadding * (touchedCount - 1)
        if total > maxWidth:
          columnCount = touchedCount - 1
          overflowed = true
          break
        else:
          columnNo = (columnNo + 1) mod columnCount
      if not overflowed:
        break  # columns.py:140 — for-else: the layout fits ⇒ exit the while.
    # Explicit per-column widths = the per-column max NATURAL content width
    # (widths0[idx]), NOT the equal-clamped `renderableWidths[idx]`: the `equal`
    # Constrain caps the cell at the max but the cell still measures its natural
    # width (<= max), so the column width = per-column max natural + padding
    # (matching Python's flexible `measureColumn` of the Constrain'd cells).
    # The while-loop overflow check above still uses the clamped widths
    # (`renderableWidths`), matching Python's `iter_renderables`. Padding cells
    # (idx == -1) contribute width 0.
    var colWidths = newSeq[int](columnCount)
    var cn = 0
    for (_, idx) in iterRenderables(columnCount):
      if idx != -1 and widths0[idx] > colWidths[cn]:
        colWidths[cn] = widths0[idx]
      cn = (cn + 1) mod columnCount
    for j in 0 ..< columnCount:
      table.addColumn(width = some(colWidths[j]))

  # columns.py:143-161 — `_renderables` with `equal` (Constrain) / `align`
  # (Align) wrappers, preserving `None` padding cells (rendered as `""`).
  var ordered: seq[RenderableValue] = @[]
  for (_, idx) in iterRenderables(columnCount):
    if idx == -1:
      ordered.add("")  # `None` padding -> `""` (Python `add_row` pads `None`->`""`).
    else:
      var r = renderables[idx]
      # columns.py:148-153 — `equal` wraps each cell in
      # `Constrain(renderable, renderable_widths[0])`. Since
      # `renderable_widths[0]` is the MAX of the natural widths, every cell's
      # natural width is <= it, so the Constrain cap is a no-op (the cell still
      # measures/renders at its natural width) — the `equal` effect lives
      # entirely in the clamped-width column-count reduction (the while loop
      # above). Nim's `Constrain.renderConsole` width arm is a deferred stub
      # (returns empty), so wrapping would blank the cells; the no-op Constrain
      # is therefore elided here, matching Python's byte output.
      if self.align.isSome:
        let a = initAlign(r, self.align.get)
        r = RenderableValue(kind: rvConsoleRenderable, consoleItem: a)
      ordered.add(r)

  # columns.py:163-170 -- chunk into rows of `column_count`, reverse on
  # `right_to_left`, feed cells straight into each column's `rawCells` + a
  # fresh `Row`. Short trailing cells become `""` (Python's `add_row` padding).
  var startIdx = 0
  while startIdx < ordered.len:
    let endIdx = min(startIdx + columnCount, ordered.len)
    var row: seq[RenderableValue] = @[]
    for j in startIdx ..< endIdx:
      row.add(ordered[j])
    if self.rightToLeft:
      var rev: seq[RenderableValue] = @[]
      for j in countdown(row.len - 1, 0):
        rev.add(row[j])
      row = rev
    for colIdx in 0 ..< columnCount:
      let cell = if colIdx < row.len: row[colIdx] else: ""
      table.columns[colIdx].rawCells.add(cell)
    table.rows.add(initRow())
    startIdx += columnCount

  # columns.py:170 -- `yield table`.
  addRenderable(result, table, rrkConsoleRenderable)
