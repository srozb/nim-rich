## Nim port of `rich.align` (rich/align.py).
##
## `Align` wraps a renderable and pads it left/center/right (align.py:17-239).
## Python's deprecated `VerticalCenter` (align.py:242-296) is NOT ported (removed
## in N1: zero callers).
##
## Import graph (rich/align.py:1-11): runtime sibling imports are
## `from itertools import chain` (align.py:1, body-only — `__rich_console__`
## @218,223,228), `from .constrain import Constrain` (align.py:4, body-only),
## `from .jupyter import JupyterMixin` (align.py:5, the base), `from .measure
## import Measurement` (align.py:6), `from .segment import Segment` (align.py:7,
## body-only), `from .style import StyleType` (align.py:8); `Console`,
## `ConsoleOptions`, `RenderableType`, `RenderResult` come from `.console`
## (align.py:11) under `TYPE_CHECKING`. NOTABLY align.py does **not** import
## `text` — no cycle (text imports align for `AlignMethod`, align never imports
## text).
##
## wiring (this file):
##   `import std/options` — `Option[VerticalAlignMethod]`/`Option[int]` (the
##                         `Optional[…]` params/fields, align.py:53,55,56,69,
##                         71,72).
##   `import segment`      — re-exports `richbase` (`ConsoleOptions`,
##                         `ConsoleHandle`, `RenderResult`, `RenderableBase`,
##                         `RenderableType`, `NO_CHANGE`, …) + `Style`.
##   `import style`        — `Style`, `StyleType`, `StyleOpt` (the
##                         `Optional[StyleType]` handle, align.py:49,68).
##   `import measure`      — `Measurement` (align.py:6, the `__rich_measure__`
##                         return).
##   `import text`         — `AlignMethod` (hosted there, see below).
##   `import api_types`    — `RenderableValue` (the storable `RenderableType`
##                         handle, for the `renderable` field).
##   `export AlignMethod`  — re-export `text.AlignMethod` so `from align import
##                         AlignMethod` (text.py:22) works. `AlignMethod` is
##                         rich's `align.AlignMethod` (align.py:13); Nim hosts it
##                         in `text.nim` (text.py:22 imports it from align, and
##                         text.nim was written before align.nim — see
##                         text.nim header). align.nim re-exports it so BOTH
##                         `from text import AlignMethod` and
##                         `from align import AlignMethod` resolve to one type.
## `cells`/`constrain`/`jupyter` are body/base deps — `constrain`/`cells` used in
## `__rich_console__` bodies, `JupyterMixin` modelled via `RenderableBase` (as
## `segment.nim`/`rule.nim` do).
##
## `Align` is `ref object of RenderableBase` (Python reference semantics —
## `__rich_console__` mutates `Text`/builds segments). The `renderable:
## "RenderableType"` field (align.py:50,66) needs a concrete Nim storage type →
## `api_types.RenderableValue` (the `Union[ConsoleRenderable, RichCast, str]`
## case object); the `renderable` PARAM keeps the faithful `RenderableType`
## typeclass (richbase). `style: Optional[StyleType] = None` → `StyleOpt`
## (style.nim, default `default(StyleOpt)` = `sokNone`); `vertical:
## Optional[VerticalAlignMethod] = None` → `Option[VerticalAlignMethod]`
## (default `none(VerticalAlignMethod)`); `pad: bool = True`; `width/height:
## Optional[int] = None` → `Option[int]`. Classmethods `left`/`center`/`right`
## (align.py:78/100/122) become `proc left/center/right*(T: typedesc[Align], …):
## Align` (called as `Align.left(…)`, matching `fromMarkup`/`join` in text.nim).
## Naming: `__init__`→`initAlign`, `__repr__`→`repr`, `__rich_console__`→
## `renderConsole`, `__rich_measure__`→`richMeasure`. Proc bodies are ported
## (initAlign/repr/renderConsole/left/center/right/richMeasure implement
## align.py:17-239).

import std/options
import std/strutils

import segment      # richbase (ConsoleOptions, ConsoleHandle, RenderResult,
                    # RenderableBase, RenderableType, NO_CHANGE, …) + Style.
import style        # Style, StyleType, StyleOpt.
import measure      # Measurement.
import text         # AlignMethod (hosted here; re-exported below).
import api_types    # RenderableValue.
import console_api  # Console.measure/render/getStyle dispatch on ConsoleHandle
                    # (leaf module — no `align`→`console` cycle).
                    # Supplies the `Console` methods `__rich_console__` calls,
                    # reached via dynamic dispatch WITHOUT `import console`.

export AlignMethod  # re-export `text.AlignMethod` (rich align.py:13) so
                    # `from align import AlignMethod` (text.py:22) resolves to
                    # the single hosted type (see text.nim header).

type
  VerticalAlignMethod* = enum
    ## rich align.py:14 — `VerticalAlignMethod = Literal["top", "middle",
    ## "bottom"]` as a Nim string-valued enum (faithful to the `Literal`).
    vamTop = "top"        ## the `"top"` literal.
    vamMiddle = "middle"  ## the `"middle"` literal.
    vamBottom = "bottom"  ## the `"bottom"` literal.

  Align* = ref object of RenderableBase
    ## rich align.py:17-239 — `class Align(JupyterMixin)`: wrap a renderable and
    ## pad it left/center/right (and optionally top/middle/bottom). `ref object
    ## of RenderableBase` (Python reference semantics; `JupyterMixin` modelled
    ## via `RenderableBase`). Fields mirror the `__init__` assignments
    ## (align.py:66-72).
    renderable*: RenderableValue                ## rich align.py:66-66 — `self.renderable = renderable` (`RenderableType`; the `api_types.RenderableValue` case object).
    align*: AlignMethod                          ## rich align.py:67-67 — `self.align = align` (`AlignMethod`, the hosted enum).
    style*: StyleOpt                             ## rich align.py:68-68 — `self.style = style` (`Optional[StyleType]`; the `style.StyleOpt` case object).
    vertical*: Option[VerticalAlignMethod]       ## rich align.py:69-69 — `self.vertical = vertical` (`Optional[VerticalAlignMethod]`; `Option[VerticalAlignMethod]`).
    pad*: bool                                   ## rich align.py:70-70 — `self.pad = pad` (`bool`; defaults `True`).
    width*: Option[int]                          ## rich align.py:71-71 — `self.width = width` (`Optional[int]`; `Option[int]`).
    height*: Option[int]                         ## rich align.py:72-72 — `self.height = height` (`Optional[int]`; `Option[int]`).

proc renderableRepr(rv: RenderableValue): string =
  ## [Nim-only helper] Best-effort `repr` of a `RenderableValue` (the
  ## `Union[ConsoleRenderable, RichCast, str]` storage handle) for the `Align`/
  ## `VerticalCenter` `__repr__` procs: a single-quoted `str` arm (mirrors
  ## `emoji.nim`'s `repr`), the system debug `repr` for the renderable arms.
  case rv.kind
  of rvString:
    result = "'" & rv.textStr & "'"
  of rvConsoleRenderable:
    result = repr(rv.consoleItem)
  of rvRichCast:
    result = repr(rv.castItem)

proc measureRenderable(console: ConsoleHandle, options: ConsoleOptions,
                       rv: RenderableValue): Measurement =
  ## [Nim-only helper] Faithful dispatch of `Measurement.get(console, options,
  ## renderable)` (align.py:238,295) over the `RenderableValue` arms: the `str`
  ## arm delegates to `Measurement.get` (a `string` satisfies `RenderableType`);
  ## the renderable arms cannot cross the `RenderableValue`→`RenderableType`
  ## bridge (a bare `RenderableBase` satisfies neither concept), so they mirror
  ## `measure.nim`'s no-`__rich_measure__` fallback (`Measurement(0, max_width)`,
  ## measure.py:108-110).
  case rv.kind
  of rvString:
    result = Measurement.get(console, options, rv.textStr)
  of rvConsoleRenderable, rvRichCast:
    if options.maxWidth < 1:
      result = Measurement(minimum: 0, maximum: 0)
    else:
      result = Measurement(minimum: 0, maximum: options.maxWidth)

proc initAlign*(renderable: RenderableValue, align: AlignMethod = amLeft,
                style: StyleOpt = default(StyleOpt),
                vertical: Option[VerticalAlignMethod] = none(VerticalAlignMethod),
                pad: bool = true, width: Option[int] = none(int),
                height: Option[int] = none(int)): Align =
  ## rich align.py:47-72 — `Align.__init__(self, renderable: "RenderableType",
  ## align: AlignMethod = "left", style: Optional[StyleType] = None, *,
  ## vertical: Optional[VerticalAlignMethod] = None, pad: bool = True, width:
  ## Optional[int] = None, height: Optional[int] = None) -> None`: validate
  ## `align` (align.py:62-64) then store the fields (align.py:66-72).
  ## Keyword-only after `style` (Python `*`, align.py:52). `renderable` keeps
  ## the faithful `RenderableType` typeclass (richbase); the field stores it as
  ## `RenderableValue` (body bridge). `style: Optional[StyleType] = None` →
  ## `StyleOpt` (default `default(StyleOpt)` = `sokNone`; the `toStyleOpt*`
  ## converters accept `string`/`Style`/`Option[Style]`); `align` default
  ## `"left"` → `amLeft`; `vertical` default `None` → `none(...)`; `pad` default
  ## `True`; `width`/`height` default `None` → `none(int)`. Body needs
  ## `errors.InvalidAlignMethod` (align.py:63).
  # `align`/`vertical` are enums (`{amLeft,amCenter,amRight}` /
  # `{vamTop,vamMiddle,vamBottom}`), so the Python `not in (...)` guards
  # (align.py:58-64) are structurally guaranteed (no invalid enum value
  # exists) and elided.
  result = Align()
  result.renderable = renderable
  result.align = align
  result.style = style
  result.vertical = vertical
  result.pad = pad
  result.width = width
  result.height = height

proc repr*(self: Align): string =
  ## rich align.py:74-75 — `Align.__repr__(self) -> str`:
  ## `f"Align({self.renderable!r}, {self.align!r})"`. Overloads `system.repr` on
  ## the `Align` receiver.
  result = "Align(" & renderableRepr(self.renderable) & ", '" & $self.align & "')"

proc left*(T: typedesc[Align], renderable: RenderableValue,
           style: StyleOpt = default(StyleOpt),
           vertical: Option[VerticalAlignMethod] = none(VerticalAlignMethod),
           pad: bool = true, width: Option[int] = none(int),
           height: Option[int] = none(int)): Align =
  ## rich align.py:78-97 — `Align.left(cls, renderable, style=None, *,
  ## vertical=None, pad=True, width=None, height=None) -> "Align"` (`@classmethod`
  ## align.py:77): `cls(renderable, "left", style, vertical=vertical, pad=pad,
  ## width=width, height=height)` (align.py:96). Modelled as a `typedesc[Align]`
  ## factory (called `Align.left(…)`, matching `fromMarkup`/`join` in text.nim);
  ## `align` is fixed to `amLeft`.
  result = initAlign(renderable, amLeft, style, vertical, pad, width, height)

proc center*(T: typedesc[Align], renderable: RenderableValue,
             style: StyleOpt = default(StyleOpt),
             vertical: Option[VerticalAlignMethod] = none(VerticalAlignMethod),
             pad: bool = true, width: Option[int] = none(int),
             height: Option[int] = none(int)): Align =
  ## rich align.py:100-119 — `Align.center(cls, renderable, style=None, *,
  ## vertical=None, pad=True, width=None, height=None) -> "Align"`
  ## (`@classmethod` align.py:99): `cls(renderable, "center", …)` (align.py:118).
  ## Modelled as a `typedesc[Align]` factory (`Align.center(…)`); `align` fixed
  ## to `amCenter`.
  result = initAlign(renderable, amCenter, style, vertical, pad, width, height)

proc right*(T: typedesc[Align], renderable: RenderableValue,
            style: StyleOpt = default(StyleOpt),
            vertical: Option[VerticalAlignMethod] = none(VerticalAlignMethod),
            pad: bool = true, width: Option[int] = none(int),
            height: Option[int] = none(int)): Align =
  ## rich align.py:122-141 — `Align.right(cls, renderable, style=None, *,
  ## vertical=None, pad=True, width=None, height=None) -> "Align"`
  ## (`@classmethod` align.py:121): `cls(renderable, "right", …)` (align.py:140).
  ## Modelled as a `typedesc[Align]` factory (`Align.right(…)`); `align` fixed to
  ## `amRight`.
  result = initAlign(renderable, amRight, style, vertical, pad, width, height)

method renderConsole*(self: Align, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich align.py:143-233 — `Align.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: render the wrapped renderable
  ## padded to `align` (and vertically per `vertical`), wrapped in a `Constrain`
  ## (align.py:148-150). Faithful port via the `console_api` dispatch
  ## (`measure`/`render`/`getStyle`) on the `ConsoleHandle` this proc receives;
  ## the real `Console` (console.nim) overrides all three, so a
  ## `Console` caller drives the genuine pipeline.
  let align = self.align
  # align.py:150 — `width = console.measure(self.renderable,
  # options=options).maximum`. The `console.measure` dispatch returns the
  # `Measurement`; `.maximum` is the renderable's desired max width.
  let measuredWidth = console.measure(self.renderable, some(options)).maximum
  # align.py:153-157 — `rendered = console.render(Constrain(self.renderable,
  # width if self.width is None else min(width, self.width)),
  # options.update(height=None))`. `Constrain.renderConsole`'s width-arm is still
  # a stub (constrain.nim), so the width clamp is applied inline (the task's
  # `opts.update(maxWidth=…)` Constrain equivalent): the child options keep
  # `height=None` and set `maxWidth = min(constrainWidth, options.maxWidth)` —
  # exactly what `Constrain` does internally (`min(self.width, options.max_width)`
  # over the height-cleared options, whose `max_width` is still `options.maxWidth`).
  let constrainWidth = if self.width.isNone: measuredWidth
                       else: min(measuredWidth, self.width.get)
  let heightNoneOpts = options.resetHeight  # `options.update(height=None)`.
  let childMaxWidth = min(constrainWidth, heightNoneOpts.maxWidth)
  let childOpts = heightNoneOpts.updateWidth(childMaxWidth)
  let rendered = console.render(self.renderable, some(childOpts))
  # align.py:158 — `lines = list(Segment.split_lines(rendered))`. `Console.render`
  # flattens the result to all `rrkSegment` items (console.py:1335-1343), so
  # extract the `Segment` from each item (the `flattenSegments` pattern from
  # panel.nim) before splitting into lines.
  var flat: seq[Segment] = @[]
  for it in rendered:
    if it.kind == rrkSegment:
      flat.add(it.segmentItem)
  var lines = segment.splitLines(flat)
  # align.py:159-160 — `width, height = Segment.get_shape(lines); lines =
  # Segment.set_shape(lines, width, height)`. `get_shape` returns `(columns,
  # rows)`; `set_shape` pads each line to `width` (and, since `rows ==
  # len(lines)` here, the blank-line padding is a no-op — only the per-line
  # `adjust_line_length` matters).
  let shape = segment.getShape(lines)
  let shapeW = shape.columns
  let shapeH = shape.rows
  lines = segment.setShape(lines, shapeW, some(shapeH))
  # align.py:161-163 — `new_line = Segment.line()`; `excess_space =
  # options.max_width - width`; `style = console.get_style(self.style) if
  # self.style is not None else None`. `paddingStyle` is this `style` (the
  # resolved `Style` for the padding/blank segments, or `None`). `StyleOpt`:
  # `sokNone` → None; `sokStr`/`sokStyle` → resolve via `console.getStyle`.
  let newLine = line()  # `Segment.line()` → `Segment("\n")`.
  let excessSpace = options.maxWidth - shapeW
  let paddingStyle: Option[Style] =
    case self.style.kind
    of sokNone: none(Style)
    of sokStr: some(console.getStyle(self.style.strv))
    of sokStyle:
      if self.style.stv.isNil: none(Style)
      else: some(console.getStyle(self.style.stv))
  # align.py:166-205 — `generate_segments`: pad the lines per `align`.
  var generated: seq[Segment] = @[]
  if excessSpace <= 0:
    # align.py:167-170 — exact fit: `yield from line; yield new_line` (no pad).
    for line in lines:
      for s in line: generated.add(s)
      generated.add(newLine)
  elif align == amLeft:
    # align.py:171-178 — pad on the right; `pad` only when `self.pad`.
    let padSeg =
      if self.pad:
        some(initSegment(spaces(excessSpace),
             if paddingStyle.isSome: some(StyleRef(paddingStyle.get))
             else: none(StyleRef)))
      else:
        none(Segment)
    for line in lines:
      for s in line: generated.add(s)
      if padSeg.isSome: generated.add(padSeg.get)
      generated.add(newLine)
  elif align == amCenter:
    # align.py:179-192 — pad both sides; left pad only when `left > 0`, right pad
    # only when `self.pad`.
    let leftN = excessSpace div 2
    let leftSeg =
      if leftN > 0:
        some(initSegment(spaces(leftN),
             if paddingStyle.isSome: some(StyleRef(paddingStyle.get))
             else: none(StyleRef)))
      else:
        none(Segment)
    let rightSeg =
      if self.pad:
        some(initSegment(spaces(excessSpace - leftN),
             if paddingStyle.isSome: some(StyleRef(paddingStyle.get))
             else: none(StyleRef)))
      else:
        none(Segment)
    for line in lines:
      if leftSeg.isSome: generated.add(leftSeg.get)
      for s in line: generated.add(s)
      if rightSeg.isSome: generated.add(rightSeg.get)
      generated.add(newLine)
  else:  # amRight — align.py:193-200: pad on the left (always, regardless of `self.pad`).
    let padSeg = initSegment(spaces(excessSpace),
        if paddingStyle.isSome: some(StyleRef(paddingStyle.get))
        else: none(StyleRef))
    for line in lines:
      generated.add(padSeg)
      for s in line: generated.add(s)
      generated.add(newLine)
  # align.py:202-228 — `blank_line`/`blank_lines`/vertical alignment. Only reached
  # when `self.vertical` is set AND `vertical_height` (= `self.height or
  # options.height`, Python truthiness) is not None. For all Slice 7 goldens
  # `vertical` is None, so `iter_segments = generate_segments()` (the `else`).
  let verticalHeight: Option[int] =
    if self.height.isSome and self.height.get != 0: self.height
    else: options.height
  var iterSegments: seq[Segment] = @[]
  if self.vertical.isSome and verticalHeight.isSome:
    let vh = verticalHeight.get
    let blankW = if self.width.isSome and self.width.get != 0: self.width.get
                 else: options.maxWidth
    let blankSeg =
      if self.pad:
        initSegment(spaces(blankW) & "\n",
             if paddingStyle.isSome: some(StyleRef(paddingStyle.get))
             else: none(StyleRef))
      else:
        initSegment("\n")
    var topBlanks: seq[Segment] = @[]
    var bottomBlanks: seq[Segment] = @[]
    case self.vertical.get
    of vamTop:
      let bottomSpace = vh - shapeH
      if bottomSpace > 0:
        for _ in 0 ..< bottomSpace: bottomBlanks.add(blankSeg)
    of vamMiddle:
      let topSpace = (vh - shapeH) div 2
      let bottomSpace = vh - topSpace - shapeH
      if topSpace > 0:
        for _ in 0 ..< topSpace: topBlanks.add(blankSeg)
      if bottomSpace > 0:
        for _ in 0 ..< bottomSpace: bottomBlanks.add(blankSeg)
    of vamBottom:
      let topSpace = vh - shapeH
      if topSpace > 0:
        for _ in 0 ..< topSpace: topBlanks.add(blankSeg)
    # `chain(top_blanks, generate_segments(), bottom_blanks)` — empty seqs
    # concatenate as no-ops, so this is faithful for all three arms.
    iterSegments = topBlanks & generated & bottomBlanks
  else:
    iterSegments = generated
  # align.py:230-233 — `if self.style: style = console.get_style(self.style);
  # iter_segments = Segment.apply_style(iter_segments, style)`. The decision to
  # apply the final style is based on the RESOLVED `paddingStyle` (the value of
  # `console.get_style(self.style)`), NOT the raw input string — faithful to
  # Rich 15.0.0, where `Segment.apply_style` checks the resolved style's
  # truthiness (`if style:` → `Style.__bool__` = `not self.isNull`,
  # segment.py/segment.nim): a style resolving to `Style.null()` is FALSY, so
  # the apply pass is skipped entirely and content/newline segments keep their
  # original (None) styles. In particular `"none"` resolves to `Style.null()`
  # (`Style.parse` maps `"none"`→`Style.null()`, style.py:498 / style.nim), so it
  # is correctly skipped here — fixing the /blocker where the
  # prior input-string guard `strv.len > 0` wrongly treated `"none"` as active.
  # `paddingStyle.isSome and not paddingStyle.get.isNull` reproduces that:
  # `sokNone` or a nil `Style` ref → `paddingStyle = none` → skip; a null
  # resolved style (`Style.null()`/`initStyle()`/`"none"`) → `isNull=true` →
  # skip; a non-null resolved style → apply (styles the whole stream — content +
  # padding + new lines — the `Align.style` semantics). NB: Nim's bare `Style()`
  # ref-constructor leaves `isNull=false` (a non-null empty style, unlike Rich's
  # `Style()` which is null, `_null=true`), so `Align(style=Style())` resolves
  # non-null and is applied here — a `style.nim` constructor discrepancy outside
  # this slice's `align.nim`-only scope; genuine null objects (`Style.null()`/
  # `initStyle()`) and the `"none"` name are skipped correctly.
  let styleIsSet = paddingStyle.isSome and not paddingStyle.get.isNull
  if styleIsSet:
    iterSegments = segment.applyStyle(iterSegments, paddingStyle)
  # `yield from iter_segments` → the `RenderResult` (console.py:271).
  for s in iterSegments:
    result.addSegment(s)

proc richMeasure*(self: Align, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich align.py:235-239 — `Align.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`:
  ## `Measurement.get(console, options, self.renderable)` (align.py:238). The
  ## richbase `ConsoleHandle`/`ConsoleOptions` placeholders; `Measurement` from
  ## `measure.nim`.
  result = measureRenderable(console, options, self.renderable)
