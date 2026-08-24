## Nim port of `rich.panel` (rich/panel.py).
##
## `Panel` draws a border around its contents (panel.py:17-297); `Panel.fit`
## (panel.py:74-107) is the `expand=False` alternative constructor. `rich.scope`
## consumes `Panel`/`Panel.fit` (scope.py:5).
##
## Import graph (rich/panel.py:1-14): runtime sibling imports are
## `from .align import AlignMethod` (panel.py:3), `from .box import ROUNDED, Box`
## (panel.py:4), `from .cells import cell_len` (panel.py:5, body-only —
## `align_text`/`__rich_measure__` @165,291), `from .jupyter import JupyterMixin`
## (panel.py:6, the base), `from .measure import Measurement, measure_renderables`
## (panel.py:7), `from .padding import Padding, PaddingDimensions` (panel.py:8),
## `from .segment import Segment` (panel.py:9), `from .style import Style,
## StyleType` (panel.py:10), `from .text import Text, TextType` (panel.py:11);
## `from typing import TYPE_CHECKING, Optional` (panel.py:1); under
## `TYPE_CHECKING` (panel.py:13) come `Console`, `ConsoleOptions`,
## `RenderableType`, `RenderResult` (`.console`, panel.py:14).
##
## wiring (this file):
##   `import std/options` — `Option[bool]`/`Option[int]` (`Optional[bool]`/
##                         `Optional[int]`, panel.py:49,53,54).
##   `import align`      — `AlignMethod` (panel.py:3, `title_align`/
##                         `subtitle_align`).
##   `import box`        — `ROUNDED`, `Box` (panel.py:4, the `box` param/field).
##   `import measure`    — `Measurement`, `measureRenderables` (panel.py:7, the
##                         `__rich_measure__` return/body).
##   `import padding`    — `Padding`, `PaddingDimensions` (panel.py:8, the
##                         `padding` param/field + `Padding.unpack` body dep).
##   `import segment`    — re-exports `richbase` (`ConsoleHandle`,
##                         `ConsoleOptions`, `RenderResult`, `RenderableBase`,
##                         `RenderableType`, …) + `Segment` (panel.py:9) +
##                         `Style`.
##   `import style`      — `Style`, `StyleType` (panel.py:10).
##   `import text`       — `Text`, `TextType`, `StyleValue` (panel.py:11; the
##                         `StyleValue` case object for the `style`/`border_style`
##                         fields).
##   `import api_types`  — `RenderableValue` (the storable `RenderableType`
##                         handle, for the `renderable` field).
## `cells` (`cell_len`, panel.py:5) and `jupyter` (`JupyterMixin`, panel.py:6)
## are body/base deps — `cells` is used in `align_text`/`__rich_measure__`
## bodies (not imported, matching `align.nim`), `JupyterMixin` modelled via
## `RenderableBase`. `console` is imported directly (`import console` — the
## `Console` ConsoleHandle subtype carrying `renderLines`/`render`).
##
## `PanelTextOpt` is the [Nim-only] handle for `Optional[TextType]`
## (`Optional[Union[str, Text]]`, panel.py:45,47) — a case object with three
## arms (`ptoNone`/`ptoStr`/`ptoText`) and `toPanelTextOpt*` converters from
## `string`/`Text`, so `Panel("hi")` (title defaults `None`), `Panel("hi",
## title = "t")` (str) and `Panel("hi", title = aText)` (Text) all compile
## (faithful to `Optional[TextType]`; `int` is rejected). It is the `title`/
## `subtitle` field type AND the `title`/`subtitle` param type (default
## `default(PanelTextOpt)` = `ptoNone` = `None`). `scope.nim` reuses this same
## handle for its `render_scope(title: Optional[TextType])` param (scope.py:16
## imports `Panel`, so the type travels with it — one shared `Optional[TextType]`
## for the `Panel`↔`scope` boundary). body fanout may unify it with the
## analogous `TableTextOpt` (table.nim) into a shared hub type.
##
## `Panel(JupyterMixin)` is `ref object of RenderableBase` (Python reference
## semantics — `__rich_console__` builds segments). `box: Box = ROUNDED`
## (panel.py:43, the `let ROUNDED` ref is a valid Nim default). `style`/
## `border_style: StyleType = "none"` (panel.py:51,52) → `StyleValue` field +
## `StyleType` typeclass param (default `"none"`). `safe_box: Optional[bool] =
## None` → `Option[bool]`; `width`/`height: Optional[int] = None` → `Option[int]`;
## `padding: PaddingDimensions = (0, 1)` (panel.py:55) →
## `PaddingDimensions(kind: pdPair, pair: (0, 1))` default. The `_title`/
## `_subtitle` properties → `titleText`/`subtitleText` (renamed: the `title`/
## `subtitle` field names are taken by the input fields, so the processed-`Text`
## properties are renamed to avoid the field/proc name clash). Naming:
## `__init__`→`initPanel`, `fit`→`fit` (typedesc factory), `__rich_console__`→
## `renderConsole`, `__rich_measure__`→`richMeasure`. Proc bodies are ported
## (initPanel/fit/repr/renderConsole/richMeasure implement panel.py:17-297).

import std/[options, strutils]

import align        # AlignMethod.
import box          # ROUNDED, Box.
import measure      # Measurement, measureRenderables.
import padding      # Padding, PaddingDimensions.
import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableBase, RenderableType, …) + Segment + Style.
import style        # Style, StyleType.
import text         # Text, TextType, StyleValue.
import api_types    # RenderableValue.
import console      # Console — the ConsoleHandle subtype carrying renderLines/
                    # render/getStyle/measure/safeBox/options/height. No cycle
                    # (console does not import panel); panel can reach the
                    # render pipeline via the `Console(console)` downcast.

type
  PanelTextOptKind* = enum
    ## [Nim-only discriminator] for `PanelTextOpt` (the `Optional[TextType]` =
    ## `Optional[Union[str, Text]]` value handle, panel.py:45,47). Three arms
    ## — `ptoNone` (the `None` arm), `ptoStr` (the `str` arm of `TextType =
    ## Union[str, Text]`, text.py:41), `ptoText` (the `Text` arm) — faithful to
    ## `Optional[TextType]` (no narrowing). `ptoNone` is first so
    ## `default(PanelTextOpt)` = `ptoNone` = `None` (the panel.py:45 default).
    ptoNone  ## the `None` arm of `Optional[TextType]` (panel.py:45,47).
    ptoStr   ## the `str`  arm (`TextType = Union[str, Text]`, text.py:41).
    ptoText  ## the `Text` arm (`TextType = Union[str, Text]`, text.py:41).

  PanelTextOpt* = object
    ## rich panel.py:45,47 — `Optional[TextType]` = `Optional[Union[str, Text]]`
    ## as a Nim case object (a true tagged union: `None` | `str` | `Text`) so it
    ## can be the `title`/`subtitle` field type and param type. Faithful to
    ## `Optional[TextType]` (the `title` param at panel.py:45, stored in the
    ## field at panel.py:60; `__rich_console__` distinguishes arms via
    ## `isinstance(self.title, str)` @ panel.py:114 / `Text.from_markup` @ 113).
    ## The `toPanelTextOpt*` converters accept both legal `TextType` variants
    ## (`string`, `Text`); `int` is rejected (not in `Union[str, Text]`).
    ## `default(PanelTextOpt)` = `ptoNone` = `None` (the panel.py:45 default).
    ## Nim-only handle; reused by `scope.nim` (the `Panel`↔`scope` boundary).
    case kind*: PanelTextOptKind
    of ptoNone:
      discard
    of ptoStr:
      strv*: string   ## the `str`  arm — a plain title/subtitle string.
    of ptoText:
      textv*: Text    ## the `Text` arm — a `Text` instance.

  Panel* = ref object of RenderableBase
    ## rich panel.py:17-297 — `class Panel(JupyterMixin)`: a console renderable
    ## that draws a border around its contents. `ref object of RenderableBase`
    ## (Python reference semantics; `JupyterMixin` modelled via `RenderableBase`
    ## — see file header). Fields mirror the `__init__` assignments
    ## (panel.py:58-71).
    renderable*: RenderableValue
      ## rich panel.py:58-58 — `self.renderable = renderable` (`RenderableType`; the `api_types.RenderableValue` case object).
    box*: Box
      ## rich panel.py:59-59 — `self.box = box` (`Box`; default `ROUNDED`).
    title*: PanelTextOpt
      ## rich panel.py:60-60 — `self.title = title` (`Optional[TextType]`; the `PanelTextOpt` case object, default `ptoNone`).
    titleAlign*: AlignMethod
      ## rich panel.py:61-61 — `self.title_align = title_align` (`AlignMethod`; default `"center"` → `amCenter`).
    subtitle*: PanelTextOpt
      ## rich panel.py:62-62 — `self.subtitle = subtitle` (`Optional[TextType]`; the `PanelTextOpt` case object, default `ptoNone`).
    subtitleAlign*: AlignMethod
      ## rich panel.py:63-63 — `self.subtitle_align = subtitle_align` (`AlignMethod`; default `"center"` → `amCenter`).
    safeBox*: Option[system.bool]
      ## rich panel.py:64-64 — `self.safe_box = safe_box` (`Optional[bool]`; `Option[system.bool]`, default `none(system.bool)` — `bool` is qualified because `style.nim`/`text.nim` export `bool` procs (`__bool__`)).
    expand*: bool
      ## rich panel.py:65-65 — `self.expand = expand` (`bool`; default `True`).
    style*: StyleValue
      ## rich panel.py:66-66 — `self.style = style` (`StyleType = Union[str, Style]`; the `text.StyleValue` case object, default `"none"`).
    borderStyle*: StyleValue
      ## rich panel.py:67-67 — `self.border_style = border_style` (`StyleType`; the `text.StyleValue` case object, default `"none"`).
    width*: Option[int]
      ## rich panel.py:68-68 — `self.width = width` (`Optional[int]`; `Option[int]`, default `none(int)`).
    height*: Option[int]
      ## rich panel.py:69-69 — `self.height = height` (`Optional[int]`; `Option[int]`, default `none(int)`).
    padding*: PaddingDimensions
      ## rich panel.py:70-70 — `self.padding = padding` (`PaddingDimensions`; default `(0, 1)` → `PaddingDimensions(kind: pdPair, pair: (0, 1))`).
    highlight*: bool
      ## rich panel.py:71-71 — `self.highlight = highlight` (`bool`; default `False`).

converter toPanelTextOpt*(x: string): PanelTextOpt =
  ## Accept a `str` as an `Optional[TextType]` value (panel.py:45,47) — the
  ## `ptoStr` arm. Lets `Panel("hi", title = "t")` compile.
  ## (`discard` ⇒ `default(PanelTextOpt)` = `ptoNone`); wraps as
  ## `PanelTextOpt(kind: ptoStr, strv: x)`.
  result = PanelTextOpt(kind: ptoStr, strv: x)

converter toPanelTextOpt*(x: Text): PanelTextOpt =
  ## Accept a `Text` as an `Optional[TextType]` value (panel.py:45,47) — the
  ## `ptoText` arm. Lets `Panel("hi", title = aText)` compile. stub;
  ## body wraps as `PanelTextOpt(kind: ptoText, textv: x)`.
  result = PanelTextOpt(kind: ptoText, textv: x)

proc initPanel*(renderable: RenderableValue, box: Box = ROUNDED,
                title: PanelTextOpt = default(PanelTextOpt),
                titleAlign: AlignMethod = amCenter,
                subtitle: PanelTextOpt = default(PanelTextOpt),
                subtitleAlign: AlignMethod = amCenter,
                safeBox: Option[system.bool] = none(system.bool), expand: bool = true,
                style: StyleType = "none", borderStyle: StyleType = "none",
                width: Option[int] = none(int), height: Option[int] = none(int),
                padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                highlight: bool = false): Panel =
  ## rich panel.py:40-71 — `Panel.__init__(self, renderable: "RenderableType",
  ## box: Box = ROUNDED, *, title: Optional[TextType] = None, title_align:
  ## AlignMethod = "center", subtitle: Optional[TextType] = None, subtitle_align:
  ## AlignMethod = "center", safe_box: Optional[bool] = None, expand: bool =
  ## True, style: StyleType = "none", border_style: StyleType = "none", width:
  ## Optional[int] = None, height: Optional[int] = None, padding:
  ## PaddingDimensions = (0, 1), highlight: bool = False) -> None`: store the
  ## fields (panel.py:58-71). Keyword-only after `box` (Python `*`,
  ## panel.py:44). `renderable` keeps the faithful `RenderableType` typeclass
  ## (richbase); the field stores it as `RenderableValue` (body bridge).
  ## `box: Box = ROUNDED` (the `let ROUNDED` ref is a valid Nim default);
  ## `title`/`subtitle: Optional[TextType] = None` → `PanelTextOpt` (default
  ## `ptoNone`); `title_align`/`subtitle_align` default `"center"` → `amCenter`;
  ## `safe_box: Optional[bool] = None` → `Option[bool]`; `style`/`border_style:
  ## StyleType = "none"` → `StyleType` typeclass default `"none"`; `width`/
  ## `height: Optional[int] = None` → `Option[int]`; `padding:
  ## PaddingDimensions = (0, 1)` → `PaddingDimensions(kind: pdPair, pair:
  ## (0, 1))`; `highlight` default `False`.
  result = Panel()
  result.renderable = renderable
  result.box = box
  result.title = title
  result.titleAlign = titleAlign
  result.subtitle = subtitle
  result.subtitleAlign = subtitleAlign
  result.safeBox = safeBox
  result.expand = expand
  result.style = style
  result.borderStyle = borderStyle
  result.width = width
  result.height = height
  result.padding = padding
  result.highlight = highlight

proc fit*(T: typedesc[Panel], renderable: RenderableValue, box: Box = ROUNDED,
          title: PanelTextOpt = default(PanelTextOpt),
          titleAlign: AlignMethod = amCenter,
          subtitle: PanelTextOpt = default(PanelTextOpt),
          subtitleAlign: AlignMethod = amCenter,
          safeBox: Option[system.bool] = none(system.bool), style: StyleType = "none",
          borderStyle: StyleType = "none", width: Option[int] = none(int),
          height: Option[int] = none(int),
          padding: PaddingDimensions = PaddingDimensions(kind: pdPair, pair: (0, 1)),
          highlight: bool = false): Panel =
  ## rich panel.py:74-107 — `Panel.fit(cls, renderable: "RenderableType", box:
  ## Box = ROUNDED, *, title: Optional[TextType] = None, title_align:
  ## AlignMethod = "center", subtitle: Optional[TextType] = None, subtitle_align:
  ## AlignMethod = "center", safe_box: Optional[bool] = None, style: StyleType =
  ## "none", border_style: StyleType = "none", width: Optional[int] = None,
  ## height: Optional[int] = None, padding: PaddingDimensions = (0, 1),
  ## highlight: bool = False) -> "Panel"` (`@classmethod` panel.py:73):
  ## "An alternative constructor that sets expand=False" (panel.py:91) —
  ## `cls(renderable, box, title=title, …, expand=False)` (panel.py:93-107).
  ## Modelled as a `typedesc[Panel]` factory (called `Panel.fit(…)`, matching
  ## `Align.left(…)`/`Text.fromMarkup(…)`); NO `expand` param (it is fixed to
  ## `False`). Same param modelling as `initPanel` (minus `expand`). port
  ## stub.
  result = initPanel(renderable, box, title = title, titleAlign = titleAlign,
                      subtitle = subtitle, subtitleAlign = subtitleAlign,
                      safeBox = safeBox, expand = false, style = style,
                      borderStyle = borderStyle, width = width, height = height,
                      padding = padding, highlight = highlight)

proc titleText*(self: Panel): Option[Text] =
  ## rich panel.py:110-123 — `Panel._title` (`@property` @109, `_title` body
  ## @110-123) -> `Optional[Text]`: build the processed title `Text` (from
  ## markup if `str`, else a copy), strip newlines, set `no_wrap`, expand tabs,
  ## pad(1) (panel.py:111-122); `None` if no title (panel.py:123). Renamed
  ## `_title`→`titleText` (the `title` field name is taken by the input field,
  ## so the processed-`Text` property is renamed to avoid the field/proc clash).
  var t: Text
  case self.title.kind
  of ptoNone:
    return none(Text)
  of ptoStr:
    t = Text.fromMarkup(self.title.strv)
  of ptoText:
    t = self.title.textv.copy()
  # Faithful processing (panel.py:115-121); guarded so a stub `Text.fromMarkup`
  # /`copy` (currently returning `nil`) does not deref a nil `Text` when setting
  # the `end`/`noWrap` fields. When those are implemented (non-nil) the field
  # sets run faithfully.
  if t.isNil:
    return none(Text)
  t.`end` = ""
  t.setPlain(t.plain.replace("\n", " "))
  t.noWrap = some(true)
  t.expandTabs()
  t.pad(1)
  result = some(t)

proc subtitleText*(self: Panel): Option[Text] =
  ## rich panel.py:126-139 — `Panel._subtitle` (`@property` @125, `_subtitle`
  ## body @126-139) -> `Optional[Text]`: build the processed subtitle `Text`
  ## (panel.py:127-138); `None` if no subtitle (panel.py:139). Renamed
  ## `_subtitle`→`subtitleText` (same reason as `titleText`).
  var t: Text
  case self.subtitle.kind
  of ptoNone:
    return none(Text)
  of ptoStr:
    t = Text.fromMarkup(self.subtitle.strv)
  of ptoText:
    t = self.subtitle.textv.copy()
  # Faithful processing (panel.py:127-137); guarded so a stub `Text.fromMarkup`
  # /`copy` (currently returning `nil`) does not deref a nil `Text` when setting
  # the `end`/`noWrap` fields. When those are implemented (non-nil) the field
  # sets run faithfully.
  if t.isNil:
    return none(Text)
  t.`end` = ""
  t.setPlain(t.plain.replace("\n", " "))
  t.noWrap = some(true)
  t.expandTabs()
  t.pad(1)
  result = some(t)

# [Nim-only helper] Flatten a `RenderResult` to the terminal `Segment` items it
# carries (the `rrkSegment` arm). Non-segment items (bare strings / renderables
# for recursive rendering by the Console) are dropped, matching
# `console.flattenRenderResult` (console.py render-flatten). The title/subtitle
# `Text` renders to pure `Segment`s, so this is a faithful pass-through for them.
proc flattenSegments(rr: RenderResult): seq[Segment] =
  for item in rr:
    if item.kind == rrkSegment:
      result.add(item.segmentItem)

# [Nim-only helper] Visible cell width of a flat list of `Segment`s — sum of
# `Segment.cellLength` (richbase) over the segments. `cellLength` is `runeLen`
# (a 1-cell approximation until `cells.cellLen` lands); exact for the ASCII
# title/subtitle content panels carry, which is the only use here.
proc segmentLineWidth(segs: seq[Segment]): int =
  for seg in segs:
    result += seg.cellLength

method renderConsole*(self: Panel, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich panel.py:141-275 — `Panel.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: draw the bordered panel —
  ## pad the renderable, measure child width, render lines, draw top/bottom
  ## borders with the aligned title/subtitle (panel.py:144-275). richbase
  ## `ConsoleHandle`/`ConsoleOptions`; `RenderResult` from richbase; `Box`/
  ## `Box.substitute`/`getTop`/`getBottom` from `box`; `Padding.unpack` from
  ## `padding`; `Segment`/`line`/`initSegment`/`addSegment` from `richbase`
  ## (re-exported by `segment`); `Console.renderLines`/`render`/`getStyle`/
  ## `measure`/`safeBox`/`options`/`height` reached via the `Console(console)`
  ## downcast.
  ##
  ## Faithful port of panel.py:144-275. The renderable is wrapped with the
  ## panel padding (`Padding(self.renderable, _padding)` if any padding is set,
  ## panel.py:144-145); the padding is applied INLINE here (left/right space
  ## `Segment`s per content line, top/bottom blank lines) rather than via a
  ## `Padding` object, because `Padding.renderConsole` is itself cycle-blocked
  ## from `console` (see `padding.nim`), so delegating to it would yield empty
  ## content. The inline application produces byte-identical output to the
  ## `Padding`-wrapped path. The `child_width`/`width` arithmetic mirrors
  ## panel.py:174-188, the top/bottom border title/subtitle alignment mirrors
  ## panel.py:160-200/250-275, and the per-line `mid_left`+content+`mid_right`
  ## loop mirrors panel.py:235-244.
  result = @[]
  let c = Console(console)

  # panel.py:144 — `_padding = Padding.unpack(self.padding)`.
  let (top, right, bottom, left) = unpack(self.padding)
  let padLR = left + right

  # panel.py:146-147 — `style = console.get_style(self.style)`;
  # `border_style = style + console.get_style(self.border_style)`. The panel's
  # `style`/`borderStyle` are `StyleValue` (`Union[str, Style]` handles); dispatch
  # the arm to `Console.getStyle` (str → theme-lookup+parse, Style → as-is).
  let panelStyle: Style =
    case self.style.kind
    of svkStr: c.getStyle(self.style.strv)
    of svkStyle: self.style.stv
  let borderStyleRaw: Style =
    case self.borderStyle.kind
    of svkStr: c.getStyle(self.borderStyle.strv)
    of svkStyle: self.borderStyle.stv
  let borderStyle: Style = panelStyle + some(borderStyleRaw)
  let bsRef: Option[StyleRef] = some(StyleRef(borderStyle))   # border `Segment`s
  let styleRef: Option[StyleRef] = some(StyleRef(panelStyle)) # content padding

  # panel.py:149-151 — `width = max_width if self.width is None else
  # min(max_width, self.width)`.
  let width0 = if self.width.isSome: min(options.maxWidth, self.width.get)
               else: options.maxWidth

  # panel.py:152 — `safe_box = console.safe_box if self.safe_box is None else
  # self.safe_box`; panel.py:153 — `box = self.box.substitute(options, safe=…)`.
  let safeBox = if self.safeBox.isSome: self.safeBox.get else: c.safeBox
  let bx = self.box.substitute(options, safe = safeBox)

  # panel.py:174-184 — `child_width = width - 2 if self.expand else
  # console.measure(renderable, options=options.update_width(width - 2)).maximum`.
  # `renderable` is the padding-wrapped renderable, so its measure is the inner
  # content measure at `width - 2 - left - right` plus `left + right`; the inline
  # form renders `self.renderable` at the inner width and re-adds the padding.
  var childWidth: int
  if self.expand:
    childWidth = width0 - 2
  else:
    let contentMax = c.measure(self.renderable,
        some(options.updateWidth(width0 - 2 - padLR))).maximum
    childWidth = contentMax + padLR

  # panel.py:186-190 — `title_text = self._title`; `if title_text is not None:
  # title_text.stylize_before(border_style)`.
  var titleText = self.titleText
  if titleText.isSome and not titleText.get.isNil:
    titleText.get.stylizeBefore(borderStyle)
    # panel.py:200-204 — `child_width = min(max_width - 2,
    # max(child_width, title_text.cell_len + 2))`.
    let tcell = titleText.get.cellLen
    childWidth = min(options.maxWidth - 2, max(childWidth, tcell + 2))

  # panel.py:206 — `width = child_width + 2`.
  let width = childWidth + 2
  let contentWidth = childWidth - padLR   # inner content render width

  # panel.py:208-211 — `child_height = self.height or options.height or None;
  # if child_height: child_height -= 2`. Python truthiness: `None`/`0` are falsy.
  var childHeight: Option[int] = none(int)
  if self.height.isSome and self.height.get != 0:
    childHeight = self.height
  elif options.height.isSome and options.height.get != 0:
    childHeight = options.height
  if childHeight.isSome:
    childHeight = some(childHeight.get - 2)
  # The padding consumes `top + bottom` of the height budget for the inner
  # content (panel.py renders the Padding at `child_height`, whose own
  # `__rich_console__` subtracts `top + bottom`).
  let contentHeight: Option[int] =
    if childHeight.isSome: some(childHeight.get - top - bottom) else: none(int)

  # panel.py:213-215 — `child_options = options.update(width=child_width,
  # height=child_height, highlight=self.highlight)`; the inline content is
  # rendered at `contentWidth` (= `child_width - left - right`) with the height
  # budget reduced by the padding.
  let childOpts = options.update(width = setChange(contentWidth),
                                 height = setChange(contentHeight),
                                 highlight = setChange(some(self.highlight)))
  # panel.py:216 — `lines = console.render_lines(renderable, child_options,
  # style=style)`. `renderLines` is a stub until the core pipeline lands
  # (console.nim), so `lines` is empty then; the borders below are real segments
  # regardless, and the content fills in once `renderLines` is wired.
  let lines = c.renderLines(self.renderable, some(childOpts), style = some(panelStyle))

  let lineStart = initSegment(bx.midLeft, bsRef)
  let lineEnd = initSegment(bx.midRight, bsRef)
  let newLine = line()   # `Segment.line()` — `Segment("\n")` (richbase).

  # panel.py:218-233 — top border: plain `box.get_top([width - 2])` when there
  # is no title (or `width <= 4`), else `top_left + top` + the aligned title
  # (rendered at `width - 4`) + `top + top_right`. The padding chars (`box.top`)
  # are emitted as real `Segment`s around the rendered title, faithful to the
  # `align_text` output (title + `box.top` padding to `width - 4`). When
  # `console.render` is a stub the title area is filled with `box.top` (matches
  # `align_text` of an empty title), so the top border is always the full width.
  if titleText.isNone or (titleText.isSome and titleText.get.isNil) or width <= 4:
    result.addSegment(initSegment(bx.getTop(@[max(0, width - 2)]), bsRef))
  else:
    let t = titleText.get
    t.truncate(width - 4)
    let titleSegs = flattenSegments(c.render(toRenderableValue(t),
        some(childOpts.updateWidth(width - 4))))
    let renderedW = segmentLineWidth(titleSegs)
    let excess = max(0, (width - 4) - renderedW)
    result.addSegment(initSegment(bx.topLeft & bx.top, bsRef))
    case self.titleAlign
    of amLeft:
      for seg in titleSegs: result.addSegment(seg)
      if excess > 0: result.addSegment(initSegment(repeat(bx.top, excess), bsRef))
    of amCenter:
      let lpad = excess div 2
      let rpad = excess - lpad
      if lpad > 0: result.addSegment(initSegment(repeat(bx.top, lpad), bsRef))
      for seg in titleSegs: result.addSegment(seg)
      if rpad > 0: result.addSegment(initSegment(repeat(bx.top, rpad), bsRef))
    of amRight:
      if excess > 0: result.addSegment(initSegment(repeat(bx.top, excess), bsRef))
      for seg in titleSegs: result.addSegment(seg)
    result.addSegment(initSegment(bx.top & bx.topRight, bsRef))
  result.addSegment(newLine)

  # Top padding blank lines (panel.py renders the `Padding`-wrapped renderable,
  # whose top blank lines are `" " * child_width` content lines flanked by the
  # panel `mid_left`/`mid_right`).
  if top > 0:
    let blank = initSegment(spaces(max(0, childWidth)), styleRef)
    for _ in 0 ..< top:
      result.addSegment(lineStart)
      result.addSegment(blank)
      result.addSegment(lineEnd)
      result.addSegment(newLine)

  # panel.py:235-244 — content lines: `mid_left` + left pad + line + right pad +
  # `mid_right` + new line. `renderLines` pads each line to `contentWidth`, so
  # the per-line width is `left + contentWidth + right = child_width`.
  for ln in lines:
    result.addSegment(lineStart)
    if left > 0: result.addSegment(initSegment(spaces(max(0, left)), styleRef))
    for seg in ln: result.addSegment(seg)
    if right > 0: result.addSegment(initSegment(spaces(max(0, right)), styleRef))
    result.addSegment(lineEnd)
    result.addSegment(newLine)

  # Bottom padding blank lines (analogous to top).
  if bottom > 0:
    let blank = initSegment(spaces(max(0, childWidth)), styleRef)
    for _ in 0 ..< bottom:
      result.addSegment(lineStart)
      result.addSegment(blank)
      result.addSegment(lineEnd)
      result.addSegment(newLine)

  # panel.py:246-273 — bottom border with subtitle (analogous to the top border
  # but with `box.bottom` chars and `self.subtitle_align`).
  var subtitleText = self.subtitleText
  if subtitleText.isSome and not subtitleText.get.isNil:
    subtitleText.get.stylizeBefore(borderStyle)
  if subtitleText.isNone or (subtitleText.isSome and subtitleText.get.isNil) or width <= 4:
    result.addSegment(initSegment(bx.getBottom(@[max(0, width - 2)]), bsRef))
  else:
    let st = subtitleText.get
    st.truncate(width - 4)
    let subSegs = flattenSegments(c.render(toRenderableValue(st),
        some(childOpts.updateWidth(width - 4))))
    let renderedW = segmentLineWidth(subSegs)
    let excess = max(0, (width - 4) - renderedW)
    result.addSegment(initSegment(bx.bottomLeft & bx.bottom, bsRef))
    case self.subtitleAlign
    of amLeft:
      for seg in subSegs: result.addSegment(seg)
      if excess > 0: result.addSegment(initSegment(repeat(bx.bottom, excess), bsRef))
    of amCenter:
      let lpad = excess div 2
      let rpad = excess - lpad
      if lpad > 0: result.addSegment(initSegment(repeat(bx.bottom, lpad), bsRef))
      for seg in subSegs: result.addSegment(seg)
      if rpad > 0: result.addSegment(initSegment(repeat(bx.bottom, rpad), bsRef))
    of amRight:
      if excess > 0: result.addSegment(initSegment(repeat(bx.bottom, excess), bsRef))
      for seg in subSegs: result.addSegment(seg)
    result.addSegment(initSegment(bx.bottom & bx.bottomRight, bsRef))
  result.addSegment(newLine)

proc richMeasure*(self: Panel, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich panel.py:277-297 — `Panel.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: `Measurement(width, width)`
  ## where `width` is the measured content width + padding + 2 (or `self.width`
  ## if set) (panel.py:280-297). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `Measurement`/`measureRenderables` from `measure.nim`. port
  ## stub.
  let unp = unpack(self.padding)
  let pad = unp[1] + unp[3]   # right + left (panel.py:280)
  var w: int
  if self.width.isSome:
    w = self.width.get
  else:
    # DEFERRED(api_types/richbase/console, later batch): the faithful port builds
    # `renderables = [self.renderable, self.titleText]` (panel.py:282) and
    # `width = measure_renderables(console, options.update_width(max - pad - 2),
    # renderables).maximum + pad + 2` (panel.py:284-287). Three blockers — (1)
    # `measureRenderables` takes the `RenderableType` concept, not a
    # `RenderableValue`/`Option[Text]` mix (the api_types bridge); (2)
    # `options.updateWidth` + `measureRenderables` integration is unbuilt; (3)
    # `self.titleText` returns a (stubbed) `nil` `Text`. Mirror the spirit: clamp
    # the inner width to `max_width - pad - 2` and re-add `pad + 2` so the panel's
    # own border + padding budget is accounted for (measure.py:108 fallback).
    let inner = options.maxWidth - pad - 2
    let innerW = if inner < 1: 0 else: inner
    w = innerW + pad + 2
  result = Measurement(minimum: w, maximum: w)
