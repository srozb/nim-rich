## Port of `rich.segment` (rich/segment.py).
##
## A `Segment` is a piece of text with an optional `Style` and an optional
## sequence of control codes (rich `Segment` NamedTuple, segment.py:60-696).
## Segments are produced by the Console render process and are ultimately
## converted to strings written to the terminal.
##
## This module hosts the *extended* `Segment` operations — the classmethods
## beyond the core accessors — plus the two trivial renderables `Segments` and
## `SegmentLines`. The *core* `Segment` type itself and its core accessors live
## in `richbase` (where they break the `segment`↔`console` import cycle):
##
##   `ControlType`               → segment.py:32-50   (richbase; IntEnum)
##   `ControlCode`               → segment.py:53-57   (richbase; Union[…])
##   `Segment`                   → segment.py:60-184   (richbase; @rich_repr @60,
##                                  class @61; fields 74-76; core accessors
##                                  below; the full class spans 60-696, with the
##                                  extended classmethods at 186-696)
##     `cellLength`              → segment.py:78-86    (richbase; @property @78)
##     `hasText`                 → segment.py:97-99     (richbase, `__bool__`)
##     `isControl`               → segment.py:101-104  (richbase; @property @101)
##     `splitCellsImpl`          → segment.py:106-153  (richbase, `_split_cells`;
##                                  @classmethod @106, @lru_cache @107)
##     `splitCells`              → segment.py:155-179   (richbase)
##     `line`                    → segment.py:181-184   (richbase; @classmethod @181)
##
## Everything in this file is the remaining extended API:
##   `richRepr`                  → segment.py:88-95    (`__rich_repr__`)
##   `applyStyle`                → segment.py:186-225  (`apply_style`)
##   `filterControl`             → segment.py:227-244  (`filter_control`)
##   `splitLines`                → segment.py:246-273  (`split_lines`)
##   `splitLinesTerminator`      → segment.py:275-304  (`split_lines_terminator`)
##   `splitAndCropLines`         → segment.py:306-351  (`split_and_crop_lines`)
##   `adjustLineLength`         → segment.py:353-396  (`adjust_line_length`)
##   `getLineLength`             → segment.py:398-409  (`get_line_length`)
##   `getShape`                  → segment.py:411-423  (`get_shape`)
##   `setShape`                  → segment.py:425-459  (`set_shape`)
##   `alignTop`                  → segment.py:461-488  (`align_top`)
##   `alignBottom`              → segment.py:490-517  (`align_bottom`)
##   `alignMiddle`              → segment.py:519-548  (`align_middle`)
##   `simplify`                  → segment.py:550-575  (`simplify`)
##   `stripLinks`               → segment.py:577-592  (`strip_links`)
##   `stripStyles`              → segment.py:594-605  (`strip_styles`)
##   `removeColor`              → segment.py:607-627  (`remove_color`)
##   `divide`                    → segment.py:629-696  (`divide`)
##   `Segments`                  → segment.py:699-721  (renderable)
##   `SegmentLines`              → segment.py:724-746  (renderable)
##
## Sibling re-exports: `richbase` is *re-exported* (`export richbase`) so its
## public `Segment`, `ControlType`, `ControlCode`, `ConsoleHandle`,
## `ConsoleOptions`, `RenderResult`, `RenderableBase` and every Segment /
## ControlCode operation (`cellLength`/`isControl`/`hasText`/`line`/`splitCells`/
## `splitCellsImpl` and the `control`/`kind`/`single*`/`double*`/`controlCode`
## accessors/constructors) are visible to consumers of this module. This mirrors
## Python, where `rich/segment.py` natively *owns* `ControlType` (32-50),
## `ControlCode` (53-57) and `Segment` (60-696), so `from rich.segment import
## Segment, ControlType, ControlCode` works directly; they were extracted to
## `richbase` only to break the `segment`↔`console` import cycle (the Python
## `from .console import Console, ConsoleOptions, RenderResult` at
## segment.py:10-11 is TYPE_CHECKING-only and is modelled by the richbase
## cycle-breaking placeholders). `style` is imported and re-exported as the
## single name `Style` (`from style import Style; export Style`), mirroring
## Python's `from .style import Style` (segment.py:9), which binds *only* the
## `Style` name in segment's namespace (the rest of the `style` module is
## deliberately not re-exported).
## Deferred (body-only, not imported/wired): `rich.cells`
## (`cell_len`, `set_cell_size`, `cached_cell_len`, segment.py:6-7 — used in
## `getLineLength`/`adjustLineLength`/`splitLines*` bodies),
## `rich.repr` (`rich_repr` decorator, segment.py:8 — `__rich_repr__` body),
## `operator.attrgetter` (segment.py:5 — `filter_control` body). These are
## Body dependencies; the ports only need the signatures.
##
## Forward placeholder type (`Result`) is private and PROVISIONAL — it stands in
## for the not-yet-written `rich.repr` module and is NOT a frozen signature:
## when `repr.nim` is imported the placeholder is removed and the `richRepr`
## return type is revisited against the real `repr.Result` (repr.py:18). Bodies
## are ports (`discard`), relying on Nim's implicit `result =
## default(T)` initialisation (verified against `style.nim`/`richbase.nim`).
##
## Naming notes: rich `_`-private helper `split_cells`/`_split_cells` are in
## richbase (`splitCells`/`splitCellsImpl`); this module uses no private
## helpers. Python `Iterable[Segment]` is modelled as `openArray[Segment]` —
## a NON-NARROWING input handle that accepts any `seq`/`array`/`openArray` of
## segments (it rejects no legal Python iterable result), matching the
## `style.nim` pattern for `Iterable[Style]`. Python
## `Iterable[List[Segment]]` (lines) is modelled as `openArray[seq[Segment]]`;
## `Iterable[int]` (the `cuts` of `divide`) as `openArray[int]`. The Python
## *generator*-returning classmethods (`apply_style`/`filter_control`/
## `split_lines`/`split_lines_terminator`/`split_and_crop_lines`/`simplify`/
## `strip_links`/`strip_styles`/`remove_color`/`divide`, segment.py:186-696)
## yield lazily; on the Nim side they are materialised to `seq[…]` /
## `seq[seq[…]]`. This preserves every legal element (only laziness is dropped
## — an implementation detail, not a narrowing of legal results) and is
## PROVISIONAL/unfrozen: the iterable handle and the materialised return types
## may be revisited once the dependent `console`/`table` consumers are written
## in body. The `new_lines`/`include_new_lines` keyword params are renamed
## `newLines`/`includeNewLines` (Nim-idiomatic camelCase);
## `is_control`→`isControl`; `post_style`→`postStyle`; `cuts` keeps its name
## (the `cuts` parameter of `divide`, segment.py:633). `Segments`/
## `SegmentLines` are `ref object of RenderableBase` (the richbase concrete
## renderable base, richbase.nim:293) with a `renderConsole` proc modelling
## `__rich_console__` (console.py protocol), matching the richbase-documented
## renderable convention.

import std/options
import std/strutils
import std/json

# Import `richbase`, then re-export it so the core Segment API it holds —
# `Segment`, `ControlType`, `ControlCode` and all their public operations — is
# visible to any consumer of `import nim_rich/segment`, exactly as Python's
# segment.py natively owns these symbols (segment.py:32-57, 60-696). A
# contract-sanctioned re-export; see the file header for the full rationale.
import richbase
export richbase

# Python `from .style import Style` (segment.py:9) binds only the `Style` name
# in segment's namespace, so we import `style` but re-export only `Style` (not
# the rest of `style`). This lets a consumer of `nim_rich/segment` reference
# `Style` — needed to call `alignTop`/`alignBottom`/`alignMiddle`, whose
# `style: Style` parameter is required and non-`Option` — just as
# `from rich.segment import Style` works.
import style
export Style

# Body dependency (segment.py:6-7): `cell_len`/`set_cell_size`/
# `cached_cell_len` from `rich.cells` — wired now that `cells` is implemented
# (a pure std-only leaf, so no import cycle). Imported, not re-exported (Python
# uses these names internally, it does not re-export them from `segment`).
import cells

# body: the private `Result` placeholder (documented in the file header
# as PROVISIONAL and "removed when `repr.nim` is imported, at which point the
# `richRepr` return type is revisited against the real `repr.Result`") is removed
# and `richRepr`'s return type is wired to the real `repr.Result` (`repr.py:18`),
# mirroring `style.nim`'s `from repr import Result, ReprArg, ReprArgKind`. The
# closure-iterator `richRepr` body (below) yields `ReprArg`s over this `Result`.
from repr import Result, ReprArg, ReprArgKind

# ---------------------------------------------------------------------------
# Extended Segment operations — segment.py:88-696
# (Core type + accessors live in `richbase`; see file header.)
# ---------------------------------------------------------------------------

proc segStyleToJson(styleOpt: Option[StyleRef]): JsonNode =
  ## [Nim-only helper] Encode a `Segment.style` (`Option[StyleRef]`) as the
  ## `JsonNode` `Any` handle for `richRepr`'s bare `yield self.style`
  ## (segment.py:91,93). `None` -> `null` (faithful: `repr(None)` -> `None`);
  ## `Some(style)` -> the style's `__str__` form (`$style`, e.g. `"bold red"`)
  ## as a `newJString` — a best-effort present-marker, since the `JsonNode`
  ## `Any` handle cannot carry a `Style` object's `repr` (`Style(...)`, which
  ## rich's `auto_repr` would build from `Style.__rich_repr__`); the exact
  ## `Style(...)` repr-fidelity is revisited when `repr.auto_repr` lands.
  if styleOpt.isSome:
    result = newJString($(Style(styleOpt.get)))
  else:
    result = newJNull()

proc segControlCodeToJson(cc: ControlCode): JsonNode =
  ## [Nim-only helper] Encode one `ControlCode` (rich `Tuple[ControlType]` /
  ## `Tuple[ControlType, Union[int, str]]` / `Tuple[ControlType, int, int]`,
  ## segment.py:53-57) as a `JsonNode` array mirroring the tuple shape —
  ## `[controlInt]`, `[controlInt, payload]`, `[controlInt, i1, i2]`.
  ## `ControlType` is encoded by its enum ordinal (`int`); the
  ## `ControlType.HOME` *name* vs *int* distinction is a `repr.auto_repr`
  ## refinement (port).
  result = newJArray()
  result.add(newJInt(cc.control.int))
  case cc.kind
  of cckEmpty:
    discard
  of cckSingle:
    if cc.singleIsStr:
      result.add(newJString(cc.singleStr))
    else:
      result.add(newJInt(cc.singleInt))
  of cckDouble:
    result.add(newJInt(cc.doubleI1))
    result.add(newJInt(cc.doubleI2))

proc segControlToJson(controlOpt: Option[seq[ControlCode]]): JsonNode =
  ## [Nim-only helper] Encode a `Segment.control` (`Option[seq[ControlCode]]`)
  ## as the `JsonNode` `Any` handle for `richRepr`'s bare `yield self.control`
  ## (segment.py:93). `None` -> `null`; `Some` -> a `JsonNode` array of the
  ## per-code tuple-arrays (`segControlCodeToJson`), mirroring the Python
  ## `[(ControlType.HOME,)]` list-of-tuples shape.
  if controlOpt.isSome:
    result = newJArray()
    for cc in controlOpt.get:
      result.add(segControlCodeToJson(cc))
  else:
    result = newJNull()

proc richRepr*(self: Segment): Result =
  ## rich segment.py:88-95 — `Segment.__rich_repr__(self) -> Result`: yield
  ## `text`; if `control is None` yield `style` (only when not None), else
  ## yield `style` then `control` (segment.py:89-95). Decorated `@rich_repr`
  ## (segment.py:60).
  iterator gen(): ReprArg {.closure.} =
    yield ReprArg(kind: ReprArgKind.rakValue, value: newJString(self.text))
    if self.control.isNone:
      if self.style.isSome:
        yield ReprArg(kind: ReprArgKind.rakValue, value: segStyleToJson(self.style))
    else:
      yield ReprArg(kind: ReprArgKind.rakValue, value: segStyleToJson(self.style))
      yield ReprArg(kind: ReprArgKind.rakValue, value: segControlToJson(self.control))
  result = gen

proc applyStyle*(segments: openArray[Segment], style: Option[Style] = none(Style),
                 postStyle: Option[Style] = none(Style)): seq[Segment] =
  ## rich segment.py:186-225 — `Segment.apply_style(cls, segments: Iterable[Segment],
  ## style: Optional[Style] = None, post_style: Optional[Style] = None) ->
  ## Iterable[Segment]` (`@classmethod` segment.py:186): apply `style` and/or
  ## `post_style` to an iterable of segments, producing
  ## `style + segment.style + post_style` per segment (segment.py:210-225).
  ## `Iterable[Segment]` modelled as `openArray[Segment]`; returns
  ## `seq[Segment]` (Python yields a generator; Nim materialises a `seq`).
  #
  # Python chains two generator passes (`style`, then `post_style`) over the
  # stream (segment.py:210-225); materialised here as two `seq` passes. A
  # control segment keeps `control` and is restyled to `None` (Python `None if
  # control else …`); a non-control segment becomes `style + seg.style` then
  # `seg.style + post_style` (or just `post_style` when `seg.style` is `None`).
  # `seg.style` (`Option[StyleRef]`) is downcast to `Option[Style]` for the
  # `Style + Option[Style]` operator; the result is upcast back to
  # `some(StyleRef(…))` for storage (the richbase-documented convention).
  var phase1: seq[Segment] = @[]
  if style.isSome:
    let base = style.get
    for seg in segments:
      if seg.control.isSome:
        phase1.add(Segment(text: seg.text, style: none(StyleRef), control: seg.control))
      else:
        let segStyle: Option[Style] =
          if seg.style.isSome: some(Style(seg.style.get)) else: none(Style)
        phase1.add(Segment(text: seg.text, style: some(StyleRef(base + segStyle)),
                           control: seg.control))
  else:
    for seg in segments:
      phase1.add(seg)
  if postStyle.isSome:
    let post = postStyle.get
    for seg in phase1:
      if seg.control.isSome:
        result.add(Segment(text: seg.text, style: none(StyleRef), control: seg.control))
      elif seg.style.isSome:
        let st = Style(seg.style.get)
        result.add(Segment(text: seg.text, style: some(StyleRef(st + postStyle)),
                           control: seg.control))
      else:
        result.add(Segment(text: seg.text, style: some(StyleRef(post)),
                           control: seg.control))
  else:
    result = phase1

proc filterControl*(segments: openArray[Segment], isControl: bool = false): seq[Segment] =
  ## rich segment.py:227-244 — `Segment.filter_control(cls, segments:
  ## Iterable[Segment], is_control: bool = False) -> Iterable[Segment]`
  ## (`@classmethod` segment.py:227): keep only control (or non-control)
  ## segments via `filter`/`filterfalse(attrgetter("control"), segments)`
  ## (segment.py:243-244). `Iterable[Segment]` modelled as
  ## `openArray[Segment]`. Body needs `operator.attrgetter`
  ## (segment.py:5).
  #
  # `filter`/`filterfalse(attrgetter("control"), …)` (segment.py:243-244):
  # keep segments whose `control` truthiness matches `isControl`. Python
  # `attrgetter("control")` reads the field and applies `bool()`; rich never
  # produces an empty control sequence, so `control.isSome` is the faithful
  # truthiness (`bool(control)` ≡ `control is not None` in practice).
  result = @[]
  for seg in segments:
    if seg.control.isSome == isControl:
      result.add(seg)

proc splitLines*(segments: openArray[Segment]): seq[seq[Segment]] =
  ## rich segment.py:246-273 — `Segment.split_lines(cls, segments:
  ## Iterable[Segment]) -> Iterable[List[Segment]]` (`@classmethod`
  ## segment.py:246): split a sequence of segments into a list of lines at
  ## line feeds (segment.py:248-273). `Iterable[Segment]`/`List[Segment]`
  ## modelled as `openArray[Segment]`/`seq[Segment]`; returns
  ## `seq[seq[Segment]]`.
  #
  # Split at line feeds (segment.py:248-273). A segment whose `text` contains
  # `'\n'` and which is not a control segment is partitioned on each `'\n'`;
  # each newline ends the current line and starts a new one. Python
  # `text.partition('\n')` is reproduced with `strutils.find` (Nim has no
  # `partition`): `before`/`after` and a found flag. A trailing fragment with
  # no further newline is appended as the start of the next line.
  result = @[]
  var line: seq[Segment] = @[]
  for seg in segments:
    if "\n" in seg.text and not seg.control.isSome:
      var text = seg.text
      let segStyle = seg.style
      while text.len > 0:
        let idx = text.find("\n")
        var before, after: string
        var found: bool
        if idx >= 0:
          before = text[0 ..< idx]
          after = text[idx + 1 .. ^1]
          found = true
        else:
          before = text
          after = ""
          found = false
        if before.len > 0:
          line.add(Segment(text: before, style: segStyle))
        if found:
          result.add(line)
          line = @[]
        text = after
    else:
      line.add(seg)
  if line.len > 0:
    result.add(line)

proc splitLinesTerminator*(segments: openArray[Segment]): seq[tuple[line: seq[Segment], newLine: bool]] =
  ## rich segment.py:275-304 — `Segment.split_lines_terminator(cls, segments:
  ## Iterable[Segment]) -> Iterable[Tuple[List[Segment], bool]]`
  ## (`@classmethod` segment.py:275): like `split_lines` but each yielded line
  ## is paired with a `bool` indicating whether it terminated with a new line
  ## (segment.py:277-304). The Python `Tuple[List[Segment], bool]` is modelled
  ## as a named tuple `tuple[line: seq[Segment], newLine: bool]` (the second
  ## field carries the terminator flag, segment.py:301). Returns
  ## `seq[...]`.
  #
  # As `splitLines` but each yielded line is paired with `newLine: bool`
  # (segment.py:277-304): `true` when the line terminated with a line feed,
  # `false` for the final unterminated line. Same partition-via-`find` logic.
  result = @[]
  var line: seq[Segment] = @[]
  for seg in segments:
    if "\n" in seg.text and not seg.control.isSome:
      var text = seg.text
      let segStyle = seg.style
      while text.len > 0:
        let idx = text.find("\n")
        var before, after: string
        var found: bool
        if idx >= 0:
          before = text[0 ..< idx]
          after = text[idx + 1 .. ^1]
          found = true
        else:
          before = text
          after = ""
          found = false
        if before.len > 0:
          line.add(Segment(text: before, style: segStyle))
        if found:
          result.add((line, true))
          line = @[]
        text = after
    else:
      line.add(seg)
  if line.len > 0:
    result.add((line, false))

# [unblock] forward declaration — `splitAndCropLines` (below) calls
# `adjustLineLength` (defined further down); Nim 2.2.10 disallows forward refs
# by default, so this bodyless forward decl is required (defaults included so it
# is the SAME overload as the definition, not a second one — a no-default
# forward decl would create an ambiguous 4-arg-call overload pair). Additive &
# conflict-safe: valid whether or not the parallel worker reorders
# `adjustLineLength` above `splitAndCropLines`.
proc adjustLineLength*(line: openArray[Segment], length: int,
                       style: Option[Style] = none(Style), pad: bool = true): seq[Segment]

proc splitAndCropLines*(segments: openArray[Segment], length: int,
                        style: Option[Style] = none(Style), pad: bool = true,
                        includeNewLines: bool = true): seq[seq[Segment]] =
  ## rich segment.py:306-351 — `Segment.split_and_crop_lines(cls, segments:
  ## Iterable[Segment], length: int, style: Optional[Style] = None, pad: bool =
  ## True, include_new_lines: bool = True) -> Iterable[List[Segment]]`
  ## (`@classmethod` segment.py:306): split into lines and crop/pad each line
  ## to `length` via `adjust_line_length` (segment.py:308-351). `include_new_lines`
  ## renamed `includeNewLines`. Returns `seq[seq[Segment]]`. Body needs
  ## `adjust_line_length` + `cells.set_cell_size` (via `adjust_line_length`).
  #
  # Split into lines (as `splitLines`) and crop/pad each completed line to
  # `length` via `adjustLineLength` (segment.py:308-351); optionally append a
  # `'\n'` segment after each cropped line (`include_new_lines`). The final
  # line is also cropped. `new_line_segment = cls("\n")` → `Segment(text: "\n")`
  # (style/control default to `None`).
  result = @[]
  var line: seq[Segment] = @[]
  for seg in segments:
    if "\n" in seg.text and not seg.control.isSome:
      var text = seg.text
      let segStyle = seg.style
      while text.len > 0:
        let idx = text.find("\n")
        var before, after: string
        var found: bool
        if idx >= 0:
          before = text[0 ..< idx]
          after = text[idx + 1 .. ^1]
          found = true
        else:
          before = text
          after = ""
          found = false
        if before.len > 0:
          line.add(Segment(text: before, style: segStyle))
        if found:
          var cropped = adjustLineLength(line, length, style, pad)
          if includeNewLines:
            cropped.add(Segment(text: "\n"))
          result.add(cropped)
          line = @[]
        text = after
    else:
      line.add(seg)
  if line.len > 0:
    result.add(adjustLineLength(line, length, style, pad))

proc adjustLineLength*(line: openArray[Segment], length: int,
                       style: Option[Style] = none(Style), pad: bool = true): seq[Segment] =
  ## rich segment.py:353-396 — `Segment.adjust_line_length(cls, line: List[Segment],
  ## length: int, style: Optional[Style] = None, pad: bool = True) ->
  ## List[Segment]` (`@classmethod` segment.py:353): adjust a line to a given
  ## width, cropping segments that overflow or padding with spaces when short
  ## (segment.py:355-396). `List[Segment]` modelled as `openArray[Segment]` on
  ## input and `seq[Segment]` on output. Body needs `cell_len` +
  ## `set_cell_size` (segment.py:367,383).
  #
  # Adjust a line to `length` cells (segment.py:355-396). The line width is the
  # sum of `segment.cell_length` (the richbase property, delegating as Python
  # does); shorter lines are padded with spaces (when `pad`), longer lines are
  # cropped segment-by-segment with `cells.setCellSize`; exact-width lines are
  # returned unchanged. Control segments have `cell_length == 0` and are kept
  # in the crop pass (`segment.control` truthiness). The padding style is the
  # `Option[Style]` param upcast to `Option[StyleRef]`; the cropped segment
  # keeps its own `seg.style`.
  var lineLength = 0
  for seg in line:
    lineLength += seg.cellLength
  if lineLength < length:
    if pad:
      let padStyle: Option[StyleRef] =
        if style.isSome: some(StyleRef(style.get)) else: none(StyleRef)
      result = @line
      result.add(Segment(text: repeat(" ", length - lineLength), style: padStyle))
    else:
      result = @line
  elif lineLength > length:
    result = @[]
    var lineLength2 = 0
    for seg in line:
      let segLen = seg.cellLength
      if lineLength2 + segLen < length or seg.control.isSome:
        result.add(seg)
        lineLength2 += segLen
      else:
        let text = setCellSize(seg.text, length - lineLength2)
        result.add(Segment(text: text, style: seg.style))
        break
  else:
    result = @line

proc getLineLength*(line: openArray[Segment]): int =
  ## rich segment.py:398-409 — `Segment.get_line_length(cls, line: List[Segment])
  ## -> int` (`@classmethod` segment.py:398): sum of `cell_len(text)` over the
  ## non-control segments of a line (segment.py:400-409). `List[Segment]`
  ## modelled as `openArray[Segment]`. Body needs `cells.cellLen`
  ## (segment.py:407).
  #
  # `sum(cell_len(text) for text, style, control in line if not control)`
  # (segment.py:407): the module-level `cell_len` (`cells.cellLen`, NOT the
  # `cell_length` property) summed over the non-control segments. Control
  # segments are excluded (`not control` truthiness).
  for seg in line:
    if not seg.control.isSome:
      result += cellLen(seg.text)

proc getShape*(lines: openArray[seq[Segment]]): tuple[columns, rows: int] =
  ## rich segment.py:411-423 — `Segment.get_shape(cls, lines: List[List[Segment]])
  ## -> Tuple[int, int]` (`@classmethod` segment.py:411): the enclosing
  ## rectangle — max line width and line count (segment.py:413-423). The
  ## Python `Tuple[int, int]` is modelled as a named tuple
  ## `tuple[columns, rows: int]` (width then height, segment.py:422).
  ## `List[List[Segment]]` modelled as `openArray[seq[Segment]]`.
  #
  # `(max(get_line_length(line) for line in lines) if lines else 0, len(lines))`
  # (segment.py:413-423): the enclosing rectangle — widest line and line count.
  # Delegates to `getLineLength` (this module) per line; empty `lines` ⇒
  # `(0, 0)`.
  var maxW = 0
  for line in lines:
    let w = getLineLength(line)
    if w > maxW: maxW = w
  result.columns = maxW
  result.rows = lines.len

proc setShape*(lines: openArray[seq[Segment]], width: int,
               height: Option[int] = none(int), style: Option[Style] = none(Style),
               newLines: bool = false): seq[seq[Segment]] =
  ## rich segment.py:425-459 — `Segment.set_shape(cls, lines: List[List[Segment]],
  ## width: int, height: Optional[int] = None, style: Optional[Style] = None,
  ## new_lines: bool = False) -> List[List[Segment]]` (`@classmethod`
  ## segment.py:425): set the enclosing rectangle of a list of lines, padding
  ## each line to `width` and adding blank lines up to `height`
  ## (segment.py:427-459). `new_lines` renamed `newLines`; `height` modelled as
  ## `Option[int] = none(int)` (Python `Optional[int]`, segment.py:429).
  ## Returns `seq[seq[Segment]]`.
  #
  # Set the enclosing rectangle (segment.py:427-459). `_height = height or
  # len(lines)` (Python truthiness: `None`/`0` ⇒ `len(lines)`). NOTE: Python's
  # `shaped_lines = lines[:_height]` truncation is immediately overwritten by
  # `shaped_lines[:] = [adjust_line_length(line, …) for line in lines]`, so the
  # net effect is: adjust *every* line to `width`, then pad with blank lines up
  # to `_height` (the truncation is dead code — the net effect is ported).
  # `blank` is a one-segment line (`" "*width` plus `"\n"` when `newLines`);
  # its style is the `Option[Style]` param upcast to `Option[StyleRef]`.
  let h = if height.isSome and height.get != 0: height.get else: lines.len
  let blankStyle: Option[StyleRef] =
    if style.isSome: some(StyleRef(style.get)) else: none(StyleRef)
  let blankLine: seq[Segment] =
    if newLines: @[Segment(text: repeat(" ", width) & "\n", style: blankStyle)]
    else: @[Segment(text: repeat(" ", width), style: blankStyle)]
  result = @[]
  for line in lines:
    result.add(adjustLineLength(line, width, style, pad = true))
  while result.len < h:
    result.add(blankLine)

proc alignTop*(lines: openArray[seq[Segment]], width: int, height: int,
              style: Style, newLines: bool = false): seq[seq[Segment]] =
  ## rich segment.py:461-488 — `Segment.align_top(cls, lines: List[List[Segment]],
  ## width: int, height: int, style: Style, new_lines: bool = False) ->
  ## List[List[Segment]]` (`@classmethod` segment.py:461): align lines to the
  ## top, adding blank lines below (segment.py:463-488). Unlike `set_shape`,
  ## `style` is *required* (Python `style: Style`, segment.py:466 — no
  ## default). `new_lines` renamed `newLines`. Returns `seq[seq[Segment]]`.
  #
  # Align to top: add blank lines below (segment.py:463-488). `extra_lines =
  # height - len(lines)`; if zero, return a copy of `lines`. Otherwise truncate
  # to `height` (when taller) and append `extra_lines` blank lines (when
  # positive). `style: Style` is required (non-`Option`); `blank` is
  # `cls(" "*width + ("\n" if new_lines else ""), style)` upcast to
  # `some(StyleRef(style))`. `lines[:]`/`lines[:height]` → `@lines`/loop copy.
  let extraLines = height - lines.len
  if extraLines == 0:
    result = @lines
    return
  result = @[]
  let k = if lines.len < height: lines.len else: height
  for i in 0 ..< k:
    result.add(lines[i])
  if extraLines > 0:
    let blank: Segment =
      if newLines: Segment(text: repeat(" ", width) & "\n", style: some(StyleRef(style)))
      else: Segment(text: repeat(" ", width), style: some(StyleRef(style)))
    for i in 1 .. extraLines:
      result.add(@[blank])

proc alignBottom*(lines: openArray[seq[Segment]], width: int, height: int,
                  style: Style, newLines: bool = false): seq[seq[Segment]] =
  ## rich segment.py:490-517 — `Segment.align_bottom(cls, lines:
  ## List[List[Segment]], width: int, height: int, style: Style, new_lines:
  ## bool = False) -> List[List[Segment]]` (`@classmethod` segment.py:490):
  ## align lines to the bottom, adding blank lines above (segment.py:492-517).
  ## `style` is *required* (Python `style: Style`, segment.py:495). `new_lines`
  ## renamed `newLines`. Returns `seq[seq[Segment]]`.
  #
  # Align to bottom: add blank lines above (segment.py:492-517). Same
  # `extra_lines`/early-return/truncate logic as `alignTop`, but the blank lines
  # precede the (truncated) lines: `[[blank]] * extra_lines + lines`.
  let extraLines = height - lines.len
  if extraLines == 0:
    result = @lines
    return
  result = @[]
  if extraLines > 0:
    let blank: Segment =
      if newLines: Segment(text: repeat(" ", width) & "\n", style: some(StyleRef(style)))
      else: Segment(text: repeat(" ", width), style: some(StyleRef(style)))
    for i in 1 .. extraLines:
      result.add(@[blank])
  let k = if lines.len < height: lines.len else: height
  for i in 0 ..< k:
    result.add(lines[i])

proc alignMiddle*(lines: openArray[seq[Segment]], width: int, height: int,
                  style: Style, newLines: bool = false): seq[seq[Segment]] =
  ## rich segment.py:519-548 — `Segment.align_middle(cls, lines:
  ## List[List[Segment]], width: int, height: int, style: Style, new_lines:
  ## bool = False) -> List[List[Segment]]` (`@classmethod` segment.py:519):
  ## align lines to the middle, splitting extra blank lines above and below
  ## (segment.py:521-548). `style` is *required* (Python `style: Style`,
  ## segment.py:524). `new_lines` renamed `newLines`. Returns
  ## `seq[seq[Segment]]`.
  #
  # Align to middle: split extra blank lines above and below (segment.py:521-548).
  # `top_lines = extra_lines // 2`, `bottom_lines = extra_lines - top_lines`;
  # `[[blank]] * top_lines + lines + [[blank]] * bottom_lines`. For negative
  # `extra_lines` (height < len) no blanks are added (the `if > 0` guards mask
  # the Nim `div`-truncation vs Python `//`-floor difference, which only
  # matters for negative operands — and `[[blank]] * negative == []` in Python
  # regardless), so only the `lines[:height]` truncation takes effect.
  let extraLines = height - lines.len
  if extraLines == 0:
    result = @lines
    return
  result = @[]
  let blank: Segment =
    if newLines: Segment(text: repeat(" ", width) & "\n", style: some(StyleRef(style)))
    else: Segment(text: repeat(" ", width), style: some(StyleRef(style)))
  let topLines = extraLines div 2
  let bottomLines = extraLines - topLines
  let k = if lines.len < height: lines.len else: height
  if topLines > 0:
    for i in 1 .. topLines:
      result.add(@[blank])
  for i in 0 ..< k:
    result.add(lines[i])
  if bottomLines > 0:
    for i in 1 .. bottomLines:
      result.add(@[blank])

proc simplify*(segments: openArray[Segment]): seq[Segment] =
  ## rich segment.py:550-575 — `Segment.simplify(cls, segments: Iterable[Segment])
  ## -> Iterable[Segment]` (`@classmethod` segment.py:550): combine contiguous
  ## segments with the same style into one (segment.py:552-575).
  ## `Iterable[Segment]` modelled as `openArray[Segment]`; returns
  ## `seq[Segment]`.
  #
  # Combine contiguous segments with the same style (segment.py:552-575).
  # `last_segment.style == segment.style` is *value* equality (Python compares
  # `Optional[Style]` by `Style.__eq__`); both `Option[StyleRef]` are downcast
  # to `Style` for the `Style.==` comparison when both are `Some`, and
  # `Option[StyleRef]==` (ref/none equality) handles the none/mixed cases.
  # Combining requires the same style AND `not segment.control`; the merged
  # segment is `cls(last.text + seg.text, last.style)` (control defaults None).
  if segments.len == 0:
    return
  result = @[]
  var lastSeg = segments[0]
  for i in 1 ..< segments.len:
    let seg = segments[i]
    let sameStyle =
      if lastSeg.style.isSome and seg.style.isSome:
        Style(lastSeg.style.get) == Style(seg.style.get)
      else:
        lastSeg.style == seg.style
    if sameStyle and not seg.control.isSome:
      lastSeg = Segment(text: lastSeg.text & seg.text, style: lastSeg.style)
    else:
      result.add(lastSeg)
      lastSeg = seg
  result.add(lastSeg)

proc stripLinks*(segments: openArray[Segment]): seq[Segment] =
  ## rich segment.py:577-592 — `Segment.strip_links(cls, segments:
  ## Iterable[Segment]) -> Iterable[Segment]` (`@classmethod` segment.py:577):
  ## remove the link from each segment's style via `style.update_link(None)`
  ## (segment.py:579-592). `Iterable[Segment]` modelled as `openArray[Segment]`;
  ## returns `seq[Segment]`. Body needs `Style.updateLink`
  ## (style.py:671).
  #
  # Remove the link from each styled, non-control segment (segment.py:579-592):
  # `segment.control or segment.style is None` → keep as-is; else
  # `cls(text, style.update_link(None))` (control defaults None). `updateLink`
  # takes `Option[string] = none(string)` for Python `None`.
  result = @[]
  for seg in segments:
    if seg.control.isSome or seg.style.isNone:
      result.add(seg)
    else:
      let st = Style(seg.style.get)
      let ns = st.updateLink(none(string))
      result.add(Segment(text: seg.text, style: some(StyleRef(ns))))

proc stripStyles*(segments: openArray[Segment]): seq[Segment] =
  ## rich segment.py:594-605 — `Segment.strip_styles(cls, segments:
  ## Iterable[Segment]) -> Iterable[Segment]` (`@classmethod`
  ## segment.py:594): replace each segment's style with `None`
  ## (segment.py:596-605). `Iterable[Segment]` modelled as `openArray[Segment]`;
  ## returns `seq[Segment]`.
  #
  # Replace each segment's style with `None`, keeping `control`
  # (segment.py:596-605): `cls(text, None, control)`.
  result = @[]
  for seg in segments:
    result.add(Segment(text: seg.text, style: none(StyleRef), control: seg.control))

proc removeColor*(segments: openArray[Segment]): seq[Segment] =
  ## rich segment.py:607-627 — `Segment.remove_color(cls, segments:
  ## Iterable[Segment]) -> Iterable[Segment]` (`@classmethod`
  ## segment.py:607): remove color from each segment's style via
  ## `style.without_color` (segment.py:609-627). `Iterable[Segment]` modelled
  ## as `openArray[Segment]`; returns `seq[Segment]`. Body needs
  ## `Style.withoutColor` (style.py:478).
  #
  # Remove color from each segment's style (segment.py:609-627): for a styled
  # segment, `cls(text, style.without_color, control)`; for an unstyled one,
  # `cls(text, None, control)`. Python memoises `style.without_color` in a
  # `Dict[Style, Style]` cache — that is a perf-only optimisation with
  # identical outputs, so it is OMITTED here (every call still produces the
  # same colorless style).
  result = @[]
  for seg in segments:
    if seg.style.isSome:
      let st = Style(seg.style.get)
      let ns = st.withoutColor
      result.add(Segment(text: seg.text, style: some(StyleRef(ns)), control: seg.control))
    else:
      result.add(Segment(text: seg.text, style: none(StyleRef), control: seg.control))

proc divide*(segments: openArray[Segment], cuts: openArray[int]): seq[seq[Segment]] =
  ## rich segment.py:629-696 — `Segment.divide(cls, segments: Iterable[Segment],
  ## cuts: Iterable[int]) -> Iterable[List[Segment]]` (`@classmethod`
  ## segment.py:629): divide an iterable of segments into portions at the given
  ## cell positions, splitting segments at cut points via `split_cells`
  ## (segment.py:631-696). `Iterable[Segment]`/`Iterable[int]` modelled as
  ## `openArray[Segment]`/`openArray[int]`; returns `seq[seq[Segment]]`. body
  ## body needs `cells.cachedCellLen` (segment.py:672) + `splitCells` (richbase).
  #
  # Divide into portions at the given cell positions (segment.py:631-696).
  # `cuts` is consumed in order; each cut emits one portion (the segments up to
  # that cell position), splitting a segment straddling a cut via `splitCells`.
  # The module-level `cached_cell_len` (`cells.cachedCellLen`) sizes non-control
  # segments (control segments are zero-width: `end_pos = pos`). Python
  # `next(iter_cuts, -1)` (the exhaustion sentinel) is reproduced with an
  # index into `cuts`. Python `return` (after the final `yield`) → an early
  # `return` here (the already-accumulated portions stay in `result`); `yield` →
  # `result.add`. In Python the `if split_segments: yield …` before each
  # `return` is always a no-op (`split_segments` was just cleared), so it is
  # elided. Leading `cut == 0` values each emit an empty portion.
  result = @[]
  var splitSegments: seq[Segment] = @[]
  var cutIdx = 0
  var cut: int
  if cutIdx < cuts.len:
    cut = cuts[cutIdx]
    inc cutIdx
  else:
    cut = -1
  while cut != -1:
    if cut != 0: break
    result.add(@[])
    if cutIdx < cuts.len:
      cut = cuts[cutIdx]
      inc cutIdx
    else:
      cut = -1
  if cut == -1:
    return
  var pos = 0
  for seg in segments:
    var cur = seg
    var text = cur.text
    var control = cur.control
    while text.len > 0:
      let endPos = if control.isSome: pos else: pos + cachedCellLen(text)
      if endPos < cut:
        splitSegments.add(cur)
        pos = endPos
        break
      if endPos == cut:
        splitSegments.add(cur)
        result.add(splitSegments)
        splitSegments = @[]
        pos = endPos
        if cutIdx < cuts.len:
          cut = cuts[cutIdx]
          inc cutIdx
        else:
          cut = -1
        if cut == -1:
          return
        break
      else:  # endPos > cut
        let (before, remaining) = cur.splitCells(cut - pos)
        cur = remaining
        text = cur.text
        control = cur.control
        splitSegments.add(before)
        result.add(splitSegments)
        splitSegments = @[]
        pos = cut
        if cutIdx < cuts.len:
          cut = cuts[cutIdx]
          inc cutIdx
        else:
          cut = -1
        if cut == -1:
          return
  result.add(splitSegments)

# ---------------------------------------------------------------------------
# Renderables — segment.py:699-746
# ---------------------------------------------------------------------------

type
  Segments* = ref object of RenderableBase
    ## rich segment.py:699-721 — `class Segments`: a renderable that renders an
    ## iterable of segments, useful for printing segments outside a
    ## `__rich_console__` method (segment.py:699-721). `ref object of
    ## RenderableBase` (the richbase concrete renderable base, richbase.nim:293);
    ## Python uses structural Protocols with no shared base. Fields from
    ## `__init__` (segment.py:708-710): `segments` (the materialised list) and
    ## `new_lines`.
    segments*: seq[Segment]   ## rich segment.py:709 — `self.segments = list(segments)`.
    newLines*: bool            ## rich segment.py:710 — `self.new_lines = new_lines` (default False).

  SegmentLines* = ref object of RenderableBase
    ## rich segment.py:724-746 — `class SegmentLines`: a renderable containing a
    ## number of lines of segments, used as an intermediate in the rendering
    ## process (segment.py:724-746). `ref object of RenderableBase`. Fields
    ## from `__init__` (segment.py:725-734): `lines` and `new_lines`.
    lines*: seq[seq[Segment]]  ## rich segment.py:733 — `self.lines = list(lines)`.
    newLines*: bool            ## rich segment.py:734 — `self.new_lines = new_lines` (default False).

proc initSegments*(segments: openArray[Segment], newLines: bool = false): Segments =
  ## rich segment.py:708-710 — `Segments.__init__(self, segments: Iterable[Segment],
  ## new_lines: bool = False) -> None` (segment.py:708-710): store the
  ## materialised segments and the new-lines flag. `Iterable[Segment]` modelled
  ## as `openArray[Segment]`; `new_lines` renamed `newLines`.
  #
  # Store the materialised segments and the new-lines flag (segment.py:708-710):
  # `self.segments = list(segments)`; `self.new_lines = new_lines`. A ref
  # object, so `new(result)` allocates then the fields are set. `@segments`
  # materialises the `openArray` to a `seq`.
  new(result)
  result.segments = @segments
  result.newLines = newLines

method renderConsole*(self: Segments, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich segment.py:712-721 — `Segments.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> "RenderResult"` (segment.py:712-721): yield
  ## each segment, inserting a `Segment.line()` between segments when
  ## `new_lines` is set (segment.py:714-720). `Console`/`ConsoleOptions`/
  ## `RenderResult` are the richbase cycle-breaking placeholders (richbase.nim);
  ## the renderable convention (`renderConsole(self, console: ConsoleHandle,
  ## options: ConsoleOptions): RenderResult`) is documented in richbase.nim.
  # Faithful render of `Segments.__rich_console__` (segment.py:712-721): yield
  # each stored segment, inserting a `Segment.line()` (== `Segment("\n")`) after
  # each when `newLines` is set (segment.py:714-720), else yield the segments
  # as-is (segment.py:720). `richbase` now exposes `addSegment`/`initSegment`, so the
  # stored `Segment`s are wrapped directly into the `RenderResult`.
  result = @[]
  if self.newLines:
    let newLine = line()
    for seg in self.segments:
      result.addSegment(seg)
      result.addSegment(newLine)
  else:
    for seg in self.segments:
      result.addSegment(seg)

proc initSegmentLines*(lines: openArray[seq[Segment]], newLines: bool = false): SegmentLines =
  ## rich segment.py:725-734 — `SegmentLines.__init__(self, lines:
  ## Iterable[List[Segment]], new_lines: bool = False) -> None`
  ## (segment.py:725-734): store the materialised lines and the new-lines flag.
  ## `Iterable[List[Segment]]` modelled as `openArray[seq[Segment]]`; `new_lines`
  ## renamed `newLines`.
  #
  # Store the materialised lines and the new-lines flag (segment.py:725-734):
  # `self.lines = list(lines)`; `self.new_lines = new_lines`. `@lines`
  # materialises the `openArray[seq[Segment]]` to a `seq[seq[Segment]]`.
  new(result)
  result.lines = @lines
  result.newLines = newLines

method renderConsole*(self: SegmentLines, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich segment.py:736-746 — `SegmentLines.__rich_console__(self, console:
  ## "Console", options: "ConsoleOptions") -> "RenderResult"`
  ## (segment.py:736-746): yield each line's segments, inserting a
  ## `Segment.line()` after each line when `new_lines` is set
  ## (segment.py:738-745). Same richbase placeholder convention as
  ## `Segments.renderConsole`.
  # Faithful render of `SegmentLines.__rich_console__` (segment.py:736-746):
  # yield each line's segments, inserting a `Segment.line()` (== `Segment("\n")`)
  # after each line when `newLines` is set (segment.py:738-745), else yield the
  # lines as-is (segment.py:745). `richbase` now exposes `addSegment`, so each
  # line's `Segment`s and the inter-line newlines are wrapped directly into the
  # `RenderResult`.
  result = @[]
  if self.newLines:
    let newLine = line()
    for ln in self.lines:
      for seg in ln:
        result.addSegment(seg)
      result.addSegment(newLine)
  else:
    for ln in self.lines:
      for seg in ln:
        result.addSegment(seg)
