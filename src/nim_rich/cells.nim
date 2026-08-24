## Nim port of `rich.cells` (rich/cells.py).
##
## Low-level cell-width utilities: measuring how many terminal cells a
## character/string occupies, and splitting/chopping text by cell position.
## Imports `unicode_data` (the cell-table data carrier) so it can self-install
## the loader at module init; otherwise no `rich` siblings (only `std/sets` for
## the `HashSet` of narrow-to-wide characters). `CellTable`/`CellSpan` are
## owned here in `cells` (matching Python `rich.cells`); `unicode_data` is a
## pure data leaf (raw widths only, no `cells` import), so there is no
## import cycle.
## The `CellTable` loader is wired in: `rich._unicode_data.load` (bound as
## `load_cell_table`, cells.py:7) is ported as `loadCellTable*` and
## self-installed via `setCellTableLoader(loadCellTable)` at module init, so
## `cellLen`/`getCharacterCellSize` measure real widths. The `@cache` on
## `rich._unicode_data.load` (functools.cache, __init__.py:58; bound as
## `load_cell_table` at cells.py:7) is mirrored by the module-init
## `cellTable15_1` (built once from the imported raw data, so `loadCellTable`
## returns the pre-built table without per-call allocation). Python's
## `@lru_cache(maxsize=4096)` on `get_character_cell_size` (cells.py:46) and
## `@lru_cache(4096)` on `cached_cell_len` (cells.py:81) — both from the
## `functools.lru_cache` import at cells.py:3 — are NOT mirrored: the Nim
## `getCharacterCellSize`/`cachedCellLen` recompute per call (the
## `cellTable15_1` cache already amortises the table load, the dominant
## cost); `operator.itemgetter` (cells.py:4) → the `spanGetCellLen` proc.
##
## `CellSpan = Tuple[int, int, int]` is a positional tuple of `(start, end,
## cell length)`; modelled as a named tuple (`end` is a Nim keyword →
## `endIdx`). `_SINGLE_CELL_UNICODE_RANGES` is a small literal and is ported
## verbatim; `_SINGLE_CELLS` (a frozenset derived from those ranges) is
## derived as the `singleCells*` `let` at module load. Proc bodies are ported
## (cellLen/getCharacterCellSize/loadCellTable implement cells.py).

import std/[sets, unicode, strutils, sequtils, options, os, algorithm]
import unicode_data
# The Unicode cell-table data carrier (`rich._unicode_data`): a pure DATA
# module — it persists the Unicode 15.1 raw width table (`widths15_1` as
# anonymous `(int, int, int)` tuples), `narrowToWide15_1`, the version
# registry, and `parseVersion`, and does NOT import `cells`, so there is no
# cells<->unicode_data import cycle. `CellTable`/`CellSpan`/`loadCellTable`
# are OWNED here (matching Python `rich.cells`, where `CellSpan`/`CellTable`
# live in `rich/cells.py` and `cells.py:7` binds `_unicode_data.load` as
# `load_cell_table`). `cells` builds the `CellTable` from the imported raw
# data and self-installs it as `cellTableLoader` at module init (see
# `setCellTableLoader(loadCellTable)` below) -- the normal production
# initialization path: importing `cells` (the universal render leaf) makes
# `cellLen`/`getCharacterCellSize` measure real widths automatically.

# `CellSpan`/`CellTable` -- rich cells.py:9, 38-43. OWNED by `cells` (the
# public module, matching Python `rich.cells`); `unicode_data` is a pure
# data leaf and does NOT import `cells`, so there is no import cycle. `end`
# renamed `endIdx` (Nim keyword).
type
  CellSpan* = tuple[start: int, endIdx: int, cellSize: int]
    ## rich cells.py:9 -- `CellSpan = Tuple[int, int, int]`: a span of
    ## `(start, end, cell length)` -- string indices and the cell length of a
    ## single grapheme. `end` renamed `endIdx` (Nim keyword).

  CellTable* = object
    ## rich cells.py:38-43 -- `CellTable(NamedTuple)`: unicode data required to
    ## measure cell widths of glyphs.
    unicodeVersion*: string           ## rich cells.py:41 -- `unicode_version: str`.
    widths*: seq[CellSpan]            ## rich cells.py:42 -- `widths: Sequence[tuple[int,int,int]]`.
    narrowToWide*: HashSet[string]    ## rich cells.py:43 -- `narrow_to_wide: frozenset[str]`.

let
  singleCellUnicodeRanges* = @[
    (0x20, 0x7E),     ## rich cells.py:16 — Latin (excluding non-printable).
    (0xA0, 0xAC),     ## rich cells.py:17.
    (0xAE, 0x002FF),  ## rich cells.py:18.
    (0x00370, 0x00482), ## rich cells.py:19 — Greek / Cyrillic.
    (0x02500, 0x025FC), ## rich cells.py:20 — Box drawing, box elements, shapes.
    (0x02800, 0x028FF), ## rich cells.py:21 — Braille.
  ]
    ## rich cells.py:15-22 — `_SINGLE_CELL_UNICODE_RANGES: list[tuple[int, int]]`:
    ## ranges of unicode ordinals producing a 1-cell-wide character
    ## (verbatim port of cells.py:15-22; range entries @16-21).

## rich cells.py:25-31 — `_SINGLE_CELLS = frozenset(...)`: a frozen set of
## all 1-cell-wide characters (derived from `singleCellUnicodeRanges`
## via a comprehension, cells.py:25-31; `frozenset(` @25, closes `)` @31).
## placeholder (empty); the derivation is wired in body.
let singleCells* = block:
  var s = initHashSet[string]()
  for (a, b) in singleCellUnicodeRanges:
    for cp in a..b:
      s.incl toUTF8(Rune(int32(cp)))
  s

# Late-bound loader hook for the Unicode cell table (cells.py:7 binds
# `_unicode_data.load` as `load_cell_table`). `CellTable`/`CellSpan`/
# `loadCellTable` live in `cells` (this module); `unicode_data` is a pure
# data leaf (no `cells` import), so `cells` imports `unicode_data` with no
# cycle and self-installs the loader at module init via the statement below
# -- the normal production initialization path: importing `cells` (the
# universal render leaf) makes `cellLen` measure real widths automatically.
# If no loader were installed, `cellTableFor` would fall back to an empty
# `CellTable` (`widths` empty => `getCharacterCellSize` returns 1).
var cellTableLoader*: proc(unicodeVersion: string): CellTable = nil

proc setCellTableLoader*(loader: proc(unicodeVersion: string): CellTable) =
  ## Install the late-bound `CellTable` loader (invoked by `cellTableFor`).
  cellTableLoader = loader

# Cached Unicode 15.1 cell table (mirrors Python `@cache` on
# `_unicode_data.load`, __init__.py:58). Built ONCE at module init from the
# raw anonymous-tuple data carrier (`unicode_data.widths15_1` /
# `narrowToWide15_1`), converting `seq[(int, int, int)]` -> `seq[CellSpan]`
# once so `loadCellTable` does not allocate per call. `CellTable`/`CellSpan`
# are owned here; `unicode_data` is a pure data leaf (no `cells` import), so
# there is no import cycle.
let cellTable15_1: CellTable = block:
  var ws: seq[CellSpan] = newSeq[CellSpan](widths15_1.len)
  for i, e in widths15_1:
    ws[i] = (start: e[0], endIdx: e[1], cellSize: e[2])
  CellTable(unicodeVersion: unicodeVersion15_1,
            widths: ws,
            narrowToWide: toHashSet(narrowToWide15_1))

proc loadCellTable*(unicodeVersion: string = "auto"): CellTable =
  ## rich _unicode_data/__init__.py:59-93 — `load(unicode_version: str =
  ## "auto") -> CellTable` (`@cache` __init__.py:58): load the cell table for
  ## a Unicode version — `"auto"` reads `UNICODE_VERSION` env (fallback
  ## `"latest"`), `"latest"` -> `VERSIONS[-1]`, else parse and bisect
  ## `VERSION_ORDER` to the nearest lower available version, then load that
  ## version table module (init.py:66-93). Bound as `load_cell_table` by
  ## `rich.cells` (cells.py:7). Hosted here (not in `unicode_data`) because it
  ## returns the cells-owned `CellTable`; `unicode_data` is a data leaf.
  ## `@cache` (Python `functools.cache`) is mirrored by the module-init
  ## `cellTable15_1` cache above. Resolves the version (auto/latest/bisect,
  ## init.py:66-93) then returns the cached 15.1 table — only the Unicode
  ## 15.1.0 cell table is embedded in this port, so the resolved version
  ## selects the 15.1 data.
  var version = unicodeVersion
  if version == "auto":
    version = getEnv("UNICODE_VERSION")
    if version.len == 0:
      version = "latest"
    try:
      discard parseVersion(version)
    except ValueError:
      version = "latest"
  if version == "latest":
    version = versions[^1]
  else:
    var vn: tuple[major, minor, patch: int]
    try:
      vn = parseVersion(version)
    except ValueError:
      vn = parseVersion(versions[^1])
    version = $vn.major & "." & $vn.minor & "." & $vn.patch
    if not versionSet.contains(version):
      let insertPosition = lowerBound(versionOrder, vn)
      version = versions[max(0, insertPosition - 1)]
  result = cellTable15_1

# Self-install the persisted Unicode 15.1 cell-table loader at module init
# (cells.py:7 binds `_unicode_data.load` as `load_cell_table`). Runs once when
# `cells` is first imported -- the normal production initialization path -- so
# `cellLen`/`getCharacterCellSize` measure real widths without any
# caller-specific wiring.
setCellTableLoader(loadCellTable)

proc cellTableFor*(unicodeVersion: string): CellTable =
  ## Resolve a `CellTable` for `unicodeVersion` via the late-bound loader, or
  ## return an empty `CellTable` when no loader is installed (empty-table
  ## fallback). This body helper calls only the installed `cellTableLoader`
  ## proc (no `unicode_data` import here) — no import cycle.
  if cellTableLoader != nil:
    result = cellTableLoader(unicodeVersion)
  else:
    result = CellTable()

proc spanGetCellLen*(span: CellSpan): int =
  ## rich cells.py:11 — `_span_get_cell_len = itemgetter(2)`: a callable
  ## returning the cell length (3rd element) of a span. Mirrored as a proc.
  return span.cellSize

proc isSingleCellWidths*(text: string): bool =
  ## rich cells.py:35 — `_is_single_cell_widths: Callable[[str], bool] =
  ## _SINGLE_CELLS.issuperset`: returns True if all characters are
  ## single-cell-wide. Mirrored as a proc.
  for r in runes(text):
    if toUTF8(r) notin singleCells:
      return false
  return true

proc getCharacterCellSize*(character: string, unicodeVersion: string = "auto"): int =
  ## rich cells.py:47 — `get_character_cell_size(character, unicode_version=
  ## "auto") -> int` (`@lru_cache(maxsize=4096)` cells.py:46): the cell size
  ## (0, 1 or 2) of a single character.
  let rs = toSeq(runes(character))
  if rs.len == 0:
    return 0
  let codepoint = int(int32(rs[0]))
  if (codepoint != 0 and codepoint < 32) or (codepoint >= 0x7F and codepoint < 0xA0):
    return 0
  let widths = cellTableFor(unicodeVersion).widths
  if widths.len == 0:
    return 1
  let lastEntry = widths[^1]
  if codepoint > lastEntry.endIdx:
    return 1
  var lowerBound = 0
  var upperBound = widths.len - 1
  while lowerBound <= upperBound:
    let index = (lowerBound + upperBound) shr 1
    let sp = widths[index]
    if codepoint < sp.start:
      upperBound = index - 1
    elif codepoint > sp.endIdx:
      lowerBound = index + 1
    else:
      return sp.cellSize
  return 1

proc cellLenImpl*(text: string, unicodeVersion: string): int {.inline.} =
  ## rich cells.py:113 — `_cell_len(text, unicode_version) -> int` (no default
  ## for `unicode_version`): the internal cell-length implementation
  ## (`cellLenImpl` suffix mirrors the `_` private convention; exported since
  ## the inventory tracks it). Forward-declared above; implemented here.
  if isSingleCellWidths(text):
    return runeLen(text)
  if find(text, "\u200d") == -1 and find(text, "\ufe0f") == -1:
    # Simplest case with no ZWJ / variation-selector that changes the size
    # (cells.py:127-129): sum the per-character cell sizes.
    var total = 0
    for r in runes(text):
      total += getCharacterCellSize(toUTF8(r), unicodeVersion)
    return total
  # ZWJ ("\u200d") / variation-selector-16 ("\ufe0f") path (cells.py:130-158).
  let ct = cellTableFor(unicodeVersion)
  var total = 0
  var last: Option[string] = none(string)
  let special = ["\u200d", "\ufe0f"]
  for r in runes(text):
    let ch = toUTF8(r)
    if ch in special:
      if ch != "\u200d":  # variation selector 16 ("\ufe0f"): maybe widen the
        # last measured narrow character (cells.py:147-152). ZWJ ("\u200d")
        # is a no-op in this for-loop port (Python's while-loop `index += 1`
        # skip-next is not needed — the for-loop naturally advances one rune).
        if last.isSome:
          if last.get in ct.narrowToWide:
            total += 1
          last = none(string)
    else:
      let w = getCharacterCellSize(ch, unicodeVersion)
      if w != 0:
        last = some(ch)
      total += w
  return total

proc cachedCellLen*(text: string, unicodeVersion: string = "auto"): int =
  ## rich cells.py:82 — `cached_cell_len(text, unicode_version="auto") -> int`
  ## (`@lru_cache(4096)` cells.py:81): the cell length of text (always caches;
  ## prefer `cellLen`).
  return cellLenImpl(text, unicodeVersion)

proc cellLen*(text: string, unicodeVersion: string = "auto"): int =
  ## rich cells.py:98 — `cell_len(text, unicode_version="auto") -> int`: the
  ## cell length of a string as it appears in the terminal (delegates to
  ## `cached_cell_len` for short text, else `_cell_len`).
  if runeLen(text) < 512:
    return cachedCellLen(text, unicodeVersion)
  return cellLenImpl(text, unicodeVersion)
proc splitGraphemes*(text: string, unicodeVersion: string = "auto"):
    tuple[spans: seq[CellSpan], totalWidth: int] =
  ## rich cells.py:161 — `split_graphemes(text, unicode_version="auto") ->
  ## tuple[list[CellSpan], int]`: divide text into single-grapheme spans and
  ## return them plus the total cell length. `list[CellSpan]` modelled as
  ## `seq[CellSpan]`; the anonymous `Tuple[list, int]` return modelled as a
  ## named tuple `(spans, totalWidth)`.
  let ct = cellTableFor(unicodeVersion)
  var chars: seq[string] = @[]
  for r in runes(text):
    chars.add(toUTF8(r))
  let codepointCount = chars.len
  var index = 0
  var lastMeasured: Option[string] = none(string)
  var totalWidth = 0
  var spans: seq[CellSpan] = @[]
  let special = ["\u200d", "\ufe0f"]
  while index < codepointCount:
    let character = chars[index]
    if character in special:
      if spans.len == 0:
        spans.add((start: index, endIdx: index + 1, cellSize: 0))
        inc index
        continue
      if character == "\u200d":
        index = (if index < (codepointCount - 1): index + 2 else: index + 1)
        let prev = spans[^1]
        spans[^1] = (start: prev.start, endIdx: index, cellSize: prev.cellSize)
      else:  # variation selector 16 ("\ufe0f")
        inc index
        let prev = spans[^1]
        if lastMeasured.isSome and lastMeasured.get in ct.narrowToWide:
          lastMeasured = none(string)
          spans[^1] = (start: prev.start, endIdx: index, cellSize: prev.cellSize + 1)
          totalWidth += 1
        else:
          spans[^1] = (start: prev.start, endIdx: index, cellSize: prev.cellSize)
      continue
    let characterWidth = getCharacterCellSize(character, unicodeVersion)
    if characterWidth != 0:
      lastMeasured = some(character)
      spans.add((start: index, endIdx: index + 1, cellSize: characterWidth))
      totalWidth += characterWidth
      inc index
    else:
      if spans.len > 0:
        let prev = spans[^1]
        spans[^1] = (start: prev.start, endIdx: index + 1, cellSize: prev.cellSize)
      else:
        spans.add((start: index, endIdx: index + 1, cellSize: 0))
      inc index
  return (spans, totalWidth)

proc splitTextImpl*(text: string, cellPosition: int,
                    unicodeVersion: string = "auto"): tuple[left: string, right: string] =
  ## rich cells.py:235 — `_split_text(text, cell_position, unicode_version=
  ## "auto") -> tuple[str, str]`: split text by cell position (a position
  ## within a double-width character becomes two spaces). `tuple[str, str]`
  ## modelled as `(left, right)`.
  if cellPosition <= 0:
    return ("", text)
  let (spans, cellLength) = splitGraphemes(text, unicodeVersion)
  var chars: seq[string] = @[]
  for r in runes(text):
    chars.add(toUTF8(r))
  let n = spans.len
  if n == 0:
    return ("", text)
  var offset = (if cellLength == 0: 0 else: int((cellPosition.float / cellLength.float) * n.float))
  # Python's `spans[:offset]` slice clamps `offset` to `len(spans)`; Nim indexing
  # does not, so clamp explicitly (matches Python when `cellPosition >
  # cellLength`, where the guess can overshoot `n`).
  if offset > n:
    offset = n
  if offset < 0:
    offset = 0
  var leftSize = 0
  for i in 0 ..< offset:
    leftSize += spanGetCellLen(spans[i])
  while true:
    if leftSize == cellPosition:
      if offset >= n:
        return (text, "")
      let splitIndex = spans[offset].start
      return (join(chars[0 ..< splitIndex]), join(chars[splitIndex ..< chars.len]))
    if leftSize < cellPosition:
      if offset >= n:
        return (text, "")
      let sp = spans[offset]
      if leftSize + sp.cellSize > cellPosition:
        return (join(chars[0 ..< sp.start]) & " ", " " & join(chars[sp.endIdx ..< chars.len]))
      inc offset
      leftSize += sp.cellSize
    else:  # leftSize > cellPosition
      let sp = spans[offset - 1]
      if leftSize - sp.cellSize < cellPosition:
        return (join(chars[0 ..< sp.start]) & " ", " " & join(chars[sp.endIdx ..< chars.len]))
      dec offset
      leftSize -= sp.cellSize

proc setCellSize*(text: string, total: int, unicodeVersion: string = "auto"): string =
  ## rich cells.py:299 — `set_cell_size(text, total, unicode_version="auto") ->
  ## str`: crop or pad with spaces so the string fits `total` cells.
  if isSingleCellWidths(text):
    let size = runeLen(text)
    if size < total:
      return text & repeat(' ', total - size)
    let rs = toSeq(runes(text))
    return $(rs[0 ..< total])
  if total <= 0:
    return ""
  let cs = cellLen(text)
  if cs == total:
    return text
  if cs < total:
    return text & repeat(' ', total - cs)
  let (t, _) = splitTextImpl(text, total, unicodeVersion)
  return t

proc chopCells*(text: string, width: int, unicodeVersion: string = "auto"): seq[string] =
  ## rich cells.py:326 — `chop_cells(text, width, unicode_version="auto") ->
  ## list[str]`: split text into lines each fitting the available (cell) width.
  ## `list[str]` modelled as `seq[string]`.
  if isSingleCellWidths(text):
    if width <= 0:
      return @[]
    let rs = toSeq(runes(text))
    let n = rs.len
    var lines: seq[string] = @[]
    var i = 0
    while i < n:
      let j = min(i + width, n)
      lines.add($(rs[i ..< j]))
      i += width
    return lines
  let (spans, _) = splitGraphemes(text, unicodeVersion)
  var chars: seq[string] = @[]
  for r in runes(text):
    chars.add(toUTF8(r))
  var lineSize = 0
  var lines: seq[string] = @[]
  var lineOffset = 0
  let n = chars.len
  for sp in spans:
    if lineSize + sp.cellSize > width:
      lines.add(join(chars[lineOffset ..< sp.start]))
      lineOffset = sp.start
      lineSize = 0
    lineSize += sp.cellSize
  if lineSize > 0:
    lines.add(join(chars[lineOffset ..< n]))
  return lines
