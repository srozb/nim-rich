## Port of `rich.tree` (rich/tree.py).
##
## `Tree` is a renderable for a recursively-nested tree structure with guide
## lines (`├──`, `└──`, …). Children are themselves `Tree` nodes added via `add`.
##
## Import graph (tree.py:1-10): `from typing import Iterator, List, Optional,
## Tuple` (tree.py:1) → `std/options` (`Option[bool]` for `add.highlight`).
## `from ._loop import loop_first, loop_last` (tree.py:3) → `_loop` does NOT
## exist yet (Body concern). `from .console import Console,
## ConsoleOptions, RenderableType, RenderResult` (tree.py:4) is supplied by
## `segment` (TYPE_CHECKING-only at the Python level too). `from .jupyter
## import JupyterMixin` (tree.py:5) → modelled via `RenderableBase` (the
## established convention; `segment` re-exports `RenderableBase`), so no
## `jupyter` import is needed here. `from .measure import Measurement`
## (tree.py:6) → `measure`. `from .segment import Segment` (tree.py:7) →
## `segment`. `from .style import Style, StyleStack, StyleType` (tree.py:8) →
## `style` (`Style`/`StyleStack` are body-only in `__rich_console__`).
## `from .styled import Styled` (tree.py:9) → `styled` exists but is a body
## body import (not needed for the stub signatures). Nim-only: `import text`
## for `StyleValue` (the `Union[str, Style]` field handle for `style`/
## `guide_style`); `import api_types` for `RenderableValue` (the storable
## `RenderableType` handle for `label`), mirroring `rule.nim`/`panel.nim`.
##
## Module-level data (tree.py:14-21): `GuideType = Tuple[str, str, str, str]`
## (tree.py:14) → `GuideType = array[4, string]`. `ASCII_GUIDES = ("    ", "|
## ", "+-- ", "`-- ")` (tree.py:16) → `const asciiGuides` (the guide set used
## when `Console.ascii_only`). `TREE_GUIDES = [...]` (tree.py:17-21, 3 guide
## sets for normal/bold/underline2) → `const treeGuides` (`array[3, GuideType]`).
## These are Python *class attributes*; as constants they are module-level here
## (Nim has no class attributes), faithful to the verbatim box-drawing strings.
##
## Faithfulness: `Tree(JupyterMixin)` (tree.py:23-185) → `ref object of
## RenderableBase` (Python reference semantics; `JupyterMixin` via
## `RenderableBase`). `__init__(self, label: RenderableType, *, style:
## StyleType = "tree", guide_style: StyleType = "tree.line", expanded: bool =
## True, highlight: bool = False, hide_root: bool = False)` (tree.py:45-59) →
## `initTree` (keyword-only after `label` is not enforceable in Nim but the
## order is preserved); `style`/`guide_style` keep the `StyleType` typeclass
## with string defaults (panel.nim pattern) and store as `StyleValue` fields
## (rule.nim pattern). `add(self, label, *, style: Optional[StyleType] = None,
## guide_style: Optional[StyleType] = None, expanded: bool = True, highlight:
## Optional[bool] = False) -> Tree` (tree.py:73-101) → `add`: `style`/
## `guideStyle` default `None` → `default(StyleOpt)` (inherit parent);
## `highlight: Optional[bool] = False` → `Option[bool] = some(false)` (`False`
## is a present bool, distinct from `none(bool)` = inherit). `label: List[Tree]`
## children (tree.py:53) → `seq[Tree]`.
##
## Naming: `__init__`→`initTree`, `guide_style`→`guideStyle`, `hide_root`→
## `hideRoot`, `__rich_console__`→`renderConsole`, `__rich_measure__`→
## `richMeasure`. Proc bodies are `discard` (port)` =
## nil ref / empty `RenderResult` / `default(Measurement)`).

import std/options

import measure        # Measurement — the richMeasure return type.
import segment        # richbase (RenderableType, ConsoleHandle, ConsoleOptions,
                     # RenderResult, RenderableBase, Segment) — re-exported.
import style          # Style, StyleType, StyleOpt — style param/field types.
import text           # StyleValue — Nim-only Union[str, Style] field handle.
import api_types      # RenderableValue — Nim-only storable RenderableType handle.

type
  GuideType* = array[4, string]
    ## rich tree.py:14 — `GuideType = Tuple[str, str, str, str]`: a 4-tuple of
    ## guide strings (space, continue, fork, end). A fixed-size positional
    ## tuple → `array[4, string]`.

const
  asciiGuides*: GuideType = ["    ", "|   ", "+-- ", "`-- "]
    ## rich tree.py:16 — `Tree.ASCII_GUIDES = ("    ", "|   ", "+-- ", "`-- ")`:
    ## the guide set used when `Console.ascii_only` is True (a class attribute
    ## → module-level `const`).

  treeGuides*: array[3, GuideType] = [
    ["    ", "│   ", "├── ", "└── "],
    ["    ", "┃   ", "┣━━ ", "┗━━ "],
    ["    ", "║   ", "╠══ ", "╚══ "],
  ]
    ## rich tree.py:17-21 — `Tree.TREE_GUIDES = [...]`: the three guide sets
    ## (normal / bold / underline2), selected by `style.bold`/`style.underline2`
    ## in `__rich_console__` (tree.py:140-143). A class attribute → module-level
    ## `const`; the box-drawing strings are verbatim UTF-8.

type
  Tree* = ref object of RenderableBase
    ## rich tree.py:23-185 — `class Tree(JupyterMixin)`: a renderable for a tree
    ## structure. `ref object of RenderableBase` (Python reference semantics;
    ## `JupyterMixin` modelled via `RenderableBase`). Fields mirror the
    ## `__init__` assignments (tree.py:58-64).
    label*: RenderableValue
      ## tree.py:58 — `self.label = label` (`RenderableType`; the
      ## `api_types.RenderableValue` handle).
    style*: StyleValue
      ## tree.py:59 — `self.style = style` (`Union[str, Style]`; the
      ## `text.StyleValue` case object — rule.nim pattern).
    guideStyle*: StyleValue
      ## tree.py:60 — `self.guide_style = guide_style` (`Union[str, Style]`;
      ## the `text.StyleValue` case object).
    children*: seq[Tree]
      ## tree.py:53 — `self.children: List[Tree] = []` (the child subtrees;
      ## appended by `add`).
    expanded*: bool
      ## tree.py:62 — `self.expanded = expanded` (`bool`; when true, also
      ## display children, tree.py:53/192).
    highlight*: bool
      ## tree.py:63 — `self.highlight = highlight` (`bool`; highlight the label
      ## renderable if it is a str, tree.py:161).
    hideRoot*: bool
      ## tree.py:64 — `self.hide_root = hide_root` (`bool`; hide the root node,
      ## tree.py:167/176).

proc initTree*(label: RenderableValue, style: StyleType = "tree",
               guideStyle: StyleType = "tree.line", expanded: bool = true,
               highlight: bool = false, hideRoot: bool = false): Tree =
  ## rich tree.py:45-66 — `Tree.__init__(self, label: RenderableType, *,
  ## style: StyleType = "tree", guide_style: StyleType = "tree.line",
  ## expanded: bool = True, highlight: bool = False, hide_root: bool = False) ->
  ## None`. Keyword-only after `label` (Python `*`) is not enforceable in Nim
  ## but the order is preserved. `style`/`guideStyle` keep the `StyleType`
  ## typeclass with string defaults (panel.nim pattern); body stores them as
  ## `StyleValue`. `label` keeps the faithful `RenderableType` typeclass (stored
  ## as `RenderableValue`).
  result = Tree()
  result.label = label
  result.style = style
  result.guideStyle = guideStyle
  result.children = @[]
  result.expanded = expanded
  result.highlight = highlight
  result.hideRoot = hideRoot

proc add*(self: Tree, label: RenderableValue, style: StyleOpt = default(StyleOpt),
          guideStyle: StyleOpt = default(StyleOpt), expanded: bool = true,
          highlight: Option[system.bool] = some(false)): Tree =
  ## rich tree.py:73-101 — `Tree.add(self, label: RenderableType, *, style:
  ## Optional[StyleType] = None, guide_style: Optional[StyleType] = None,
  ## expanded: bool = True, highlight: Optional[bool] = False) -> Tree`: add a
  ## child tree, inheriting `self.style`/`self.guide_style`/`self.highlight`
  ## when the respective arg is `None` (tree.py:93-99). `style`/`guideStyle`
  ## default `None` → `default(StyleOpt)` (= `sokNone`, inherit); `highlight:
  ## Optional[bool] = False` → `Option[bool] = some(false)` (`False` is a present
  ## bool, distinct from `none(bool)` = inherit). Returns the new child `Tree`.
  # Inherit `self.style`/`self.guideStyle` when the respective arg is `None`
  # (the `sokNone` arm of `StyleOpt`); otherwise build a `StyleValue` from the
  # supplied `str`/`Style`. `highlight` inherits `self.highlight` when `None`.
  let effStyle: StyleValue =
    case style.kind
    of sokNone: self.style
    of sokStr: StyleValue(kind: svkStr, strv: style.strv)
    of sokStyle: StyleValue(kind: svkStyle, stv: style.stv)
  let effGuideStyle: StyleValue =
    case guideStyle.kind
    of sokNone: self.guideStyle
    of sokStr: StyleValue(kind: svkStr, strv: guideStyle.strv)
    of sokStyle: StyleValue(kind: svkStyle, stv: guideStyle.stv)
  result = Tree()
  result.label = label
  result.style = effStyle
  result.guideStyle = effGuideStyle
  result.children = @[]
  result.expanded = expanded
  result.highlight = if highlight.isSome: highlight.get else: self.highlight
  result.hideRoot = false
  self.children.add(result)

proc svToSegStyle(sv: StyleValue): Option[StyleRef] =
  ## [Nim-only helper] Best-effort `StyleValue` → `Option[StyleRef]` for
  ## `renderConsole`. `Tree`'s `style`/`guideStyle` are `StyleType` defaults
  ## (`"tree"`/`"tree.line"`), theme names rich resolves via
  ## `console.get_style`; the opaque `ConsoleHandle` has no `get_style`, so a
  ## `str` style is resolved via `Style.parse` (themed names are unresolvable and
  ## fall back to `none`, the `text.getStyleLocal` pattern) and a `Style` is
  ## upcast (copied). Degraded for themed-name strings (null style → no color);
  ## the guide structure is unaffected.
  case sv.kind
  of svkStr:
    if sv.strv.len == 0: result = none(StyleRef)
    else:
      try: result = some(StyleRef(Style.parse(sv.strv)))
      except CatchableError: result = none(StyleRef)
  of svkStyle:
    result = some(StyleRef(sv.stv.copy()))

proc treeWalk(res: var RenderResult, node: Tree, prefix: string, isLast: bool,
              isRoot: bool, hideRoot: bool, effectiveRoot: bool, guides: GuideType,
              styleOpt: Option[StyleRef], guideStyleOpt: Option[StyleRef]) =
  ## [Nim-only helper] Recursive depth-first walk for `Tree.renderConsole` — a
  ## simplified, structural port of `Tree.__rich_console__` (tree.py:103-185).
  ## Emits the ancestor guide prefix (in `guideStyleOpt`) + the node's own guide
  ## (`├── `/`└── ` for a normal node, none for an effective root) + the node's label (a `str` label
  ## as a `Segment` in `styleOpt`; a renderable label via `addRenderable` — note:
  ## the multi-line guide-prefix application `console.render_lines`/`Styled` does
  ## is NOT replicated, so a non-`str` label renders without the guide prefix) +
  ## a newline, then recurses into expanded children. The full rich walk
  ## (`StyleStack`s, `loop_last`/`loop_first`, `console.render_lines`, bold/
  ## underline2 guide-set selection) is deferred; this yields the correct guide
  ## STRUCTURE for `str` labels. `guides[0]`=space, `[1]`=continue, `[2]`=fork,
  ## `[3]`=end (tree.py:98). `effectiveRoot` marks nodes that render bare (no
  ## own branch guide) and pass their prefix unchanged to children — the visible
  ## root (`hide_root=False`, rich's `levels[1:]` slice) and a hidden root's
  ## direct children (`hide_root=True`, rich's `levels[2:]` slice, tree.py:131).
  if not (isRoot and hideRoot):
    let guide = if effectiveRoot: "" elif isLast: guides[3] else: guides[2]
    let pre = prefix & guide
    if pre.len > 0:
      res.addSegment(initSegment(pre, guideStyleOpt))
    case node.label.kind
    of rvString:
      res.addSegment(initSegment(node.label.textStr, styleOpt))
    of rvConsoleRenderable:
      if not node.label.consoleItem.isNil:
        res.addRenderable(node.label.consoleItem, rrkConsoleRenderable)
    of rvRichCast:
      if not node.label.castItem.isNil:
        res.addRenderable(node.label.castItem, rrkRichCast)
    res.addSegment(line())
  if node.expanded:
    # Effective roots (the visible root, or a hidden root's direct children)
    # render bare and do NOT contribute a guide slot to their children's prefix
    # — mirroring rich's `prefix = levels[(2 if hide_root else 1):]` slice
    # (tree.py:131), which cuts the root's slot (and, when `hide_root`, the
    # first child's slot too). Non-effective-root nodes append their own
    # continue/space guide (`guides[1]`/`guides[0]`) for their children.
    let childPrefix =
      if effectiveRoot: prefix
      else: prefix & (if isLast: guides[0] else: guides[1])
    # A node's children are themselves effective roots only when this node is
    # the hidden root (`isRoot and hideRoot`): its slot is cut, so its children
    # render as bare roots (tree.py:131, `levels[2:]`).
    let childEffectiveRoot = isRoot and hideRoot
    for i in 0 ..< node.children.len:
      let childIsLast = (i == node.children.len - 1)
      treeWalk(res, node.children[i], childPrefix, childIsLast, false, hideRoot,
               childEffectiveRoot, guides, styleOpt, guideStyleOpt)

method renderConsole*(self: Tree, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich tree.py:103-185 — `Tree.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: walk the tree depth-first,
  ## emitting guide-line prefixes (`asciiGuides`/`treeGuides`), rendering each
  ## `Styled(node.label, style)` and managing `StyleStack`s for the guide/label
  ## styles (tree.py:107-184). Uses `loop_last`/`loop_first`/`Styled` (body).
  ## `__rich_console__`→`renderConsole`.
  # Simplified structural render of `Tree.__rich_console__` (tree.py:103-185):
  # a recursive depth-first walk emitting guide prefixes + labels. The full rich
  # port (`StyleStack`s, `loop_last`/`loop_first`, `console.render_lines` for
  # multi-line/styled labels, bold/underline2 guide-set selection via
  # `console.get_style`) is deferred — those APIs are stubs/blocked. `richbase`
  # now exposes `addSegment`/`addRenderable`/`initSegment`, so the guide structure
  # for `str` labels is rendered faithfully. Guide set: `asciiGuides` when
  # `options.ascii_only` else `treeGuides[0]` (the non-bold/non-underline2 set;
  # the bold/underline2 variant needs the resolved `guide_style.bold`/`underline2`,
  # blocked on `console.get_style`). See `treeWalk` for the per-node logic.
  result = @[]
  let guides = if options.asciiOnly: asciiGuides else: treeGuides[0]
  let styleOpt = svToSegStyle(self.style)
  let guideStyleOpt = svToSegStyle(self.guideStyle)
  # The actual root is an effective root: it renders bare (no own branch guide)
  # and passes its prefix unchanged to its children, matching rich's
  # `levels[1:]` slice for `hide_root=False` (tree.py:131). When `hideRoot` is
  # true the root is skipped (see `treeWalk`) and its children become the
  # effective roots (`levels[2:]`).
  treeWalk(result, self, "", true, true, self.hideRoot, true, guides, styleOpt,
           guideStyleOpt)

proc richMeasure*(self: Tree, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich tree.py:187-212 — `Tree.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: walk the tree and return
  ## `Measurement(minimum, maximum)` over the indented label widths
  ## (`level * 4` indent, tree.py:196-211). `__rich_measure__`→`richMeasure`.
  # Walk the tree depth-first (faithful to tree.py:187-212): for each visible
  # node measure its label, add a `level * 4` indent, and keep the running max.
  # `Measurement.get` (measure.nim) is the faithful `Measurement.get(console,
  # options, label)`; a `RenderableValue` label is deconstructed — the `str` arm
  # measures the string, the `RenderableBase` arms fall back to
  # `Measurement(0, options.maxWidth)` (the type-erased storage handle cannot
  # dispatch to the concrete renderable's `__rich_measure__`).
  var minimum = 0
  var maximum = 0
  proc walk(n: Tree, level: int) =
    let m: Measurement =
      case n.label.kind
      of rvString: Measurement.get(console, options, n.label.textStr)
      of rvConsoleRenderable: Measurement(minimum: 0, maximum: options.maxWidth)
      of rvRichCast: Measurement(minimum: 0, maximum: options.maxWidth)
    let indent = level * 4
    minimum = max(m.minimum + indent, minimum)
    maximum = max(m.maximum + indent, maximum)
    if n.expanded:
      for c in n.children:
        walk(c, level + 1)
  walk(self, 0)
  result = Measurement(minimum: minimum, maximum: maximum)
