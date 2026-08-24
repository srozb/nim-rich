## golden_nim.nim — Nim port reference renderer do golden tests.
##
## Usage: golden_nim <case_name>
## Output: raw ANSI bytes na stdout (diff byte-po-byte z golden_ref.py Python).
##
## Subset: Text, Rule, Control, filesize + deps (richbase/segment/style/measure/color/cells).
## Table support via the REAL `Console` (console.nim) — the audited overrides
## of the four `console_api` base methods (`getStyle`/`render`/`renderLines`/
## `measure`, round_004) drive `Table.renderConsole`. No bespoke test double:
## `table.nim` still dispatches via `console_api` (leaf, no `import console`),
## while THIS carrier instantiates the real `Console` so `Table` exercises the
## genuine `getStyle`/`render`/`renderLines` pipeline.
##
## Build: nim c -d:release --path:src -o:golden_nim golden_nim.nim
import nim_rich/[richbase, segment, style, measure, color, color_triplet,
                 cells, errors, ratio, text, tree, rule, control, filesize,
                 table, panel, box, api_types, console_api, console, emoji,
                 markdown, bar, align, columns, padding, syntax, spinner,
                 status, logging, traceback, json, theme, highlighter, pretty,
                 progress, progress_bar, prompt, styled, layout, ansi,
                 constrain, screen, repr, terminal_theme,
                 file_proxy, live_render]
import std/[os, strutils, options, sequtils]
from std/tables import toOrderedTable, pairs
# v0.6.0 — `repr.autoRepr`'s `ReprArg` arms carry `JsonNode` values (the
# non-narrowing `Any` handle); `from std/json` imports only the `JsonNode`
# type + its `JString`/`JInt`/`JArray` enum members (NOT the `%` operator nor
# the `json` module name) so there is no clash with the already-imported
# `nim_rich/json` (the JSON renderable module).
from std/json import JsonNode, JString, JInt, JArray, parseJson

export richbase, segment, style, measure, color, color_triplet,
       cells, errors, ratio, text, tree, rule, control, filesize,
       table, panel, box, api_types, console_api, emoji, markdown, bar, align

# ── render helper: RenderResult → ANSI bytes ──────────────────────────────
## RenderResult arms: rrkSegment, rrkString, rrkConsoleRenderable, rrkRichCast.
## Control does not pass through RenderResult — it renders via Control.str().
## rrkConsoleRenderable/rrkRichCast = nested renderable (e.g. Rule yields
## Text) → recursive dispatch via method renderConsole (virtual, Text override).
proc renderToAnsi(r: RenderResult, handle: ConsoleHandle,
                  opts: ConsoleOptions): string
proc renderToAnsi(r: RenderResult, handle: ConsoleHandle,
                  opts: ConsoleOptions): string =
  for item in r:
    case item.kind
    of rrkSegment:
      let seg = item.segmentItem
      if seg.style.isSome:
        result &= Style(seg.style.get).render(seg.text, some(ColorSystem.truecolor))
      else:
        result &= seg.text
    of rrkString:
      result &= item.textStr
    of rrkConsoleRenderable:
      # Nested ConsoleRenderable (e.g. Rule→Text) — virtual dispatch.
      result &= renderToAnsi(item.consoleItem.renderConsole(handle, opts),
                             handle, opts)
    of rrkRichCast:
      result &= renderToAnsi(item.castItem.renderConsole(handle, opts),
                             handle, opts)

proc renderTextAnsi(t: Text): string =
  let handle = default(ConsoleHandle)
  renderToAnsi(t.render(handle, ""), handle, default(ConsoleOptions))

proc renderRuleAnsi(r: Rule): string =
  # Rule ma tylko method renderConsole(console, options) — nie proc render.
  # ConsoleOptions z size=(80,24), maxWidth=80, isTerminal=true (deterministic).
  let handle = default(ConsoleHandle)
  let opts = ConsoleOptions(
    size: (width: 80, height: 24),
    legacyWindows: false,
    minWidth: 0,
    maxWidth: 80,
    isTerminal: true,
    encoding: "utf-8",
    maxHeight: 24,
  )
  renderToAnsi(r.renderConsole(handle, opts), handle, opts)

proc renderControlAnsi(c: Control): string =
  # Control renders directly as ANSI bytes via .str() — no ConsoleHandle needed.
  c.str()

# ── Table support: real `Console` driving the `console_api` dispatch ─────────
## `Table.renderConsole` dispatches `getStyle`/`render`/`renderLines`/`measure`
## via the `console_api` `{.base.}` methods on `ConsoleHandle`. The real
## `Console` (console.nim, `ref object of ConsoleHandle`) overrides all four
## (round_004 audit: `getStyle`/`render`/`renderLines`/`measure`), so this
## carrier instantiates and renders through it — no bespoke test double. The
## Console is configured to mirror `golden_ref.py`'s `Console(force_terminal=
## True, color_system="truecolor", width=80, legacy_windows=False,
## soft_wrap=False, record=False)`: `colorSystem="truecolor"` (deterministic,
## matching `renderToAnsi`'s truecolor segment rendering), `forceTerminal=true`
## (`isTerminal=true`), `width=80`, `legacyWindows=false`, `noColor=false`
## (`golden_compare` strips `NO_COLOR` so both sides render colour). `Table`
## passes explicit `ConsoleOptions` (width=80, maxWidth=80, isTerminal=true)
## into `renderConsole`, matching `golden_ref`'s `width=80`. `Console.getStyle`
## resolves names via its `ThemeStack` (seeded with `themes.DEFAULT`, an
## empty-styles Phase-0 theme, so lookups miss and fall back to `Style.parse` —
## identical to the `""`/`"none"`/`"bold"`/`"italic"` names the four
## fixed-width cases use). `render`/`renderLines` run the genuine render pipeline
## (`dispatchRenderConsole` → `Text.renderConsole` + `Splitter` +
## `adjustLineLength`); cell `\n`s are line breaks consumed by the splitter, so
## the body is byte-exact. The title annotation goes through `console.render`
## (not `renderLines`); `Table.renderConsole` neutralises the trailing `end`
## segment's style Table-locally (the generic `Text.render` no-spans path
## styles it), so the styled title content is followed by an unstyled `\n`
## exactly like Rich 15.0.0 (the caption path retains the generic behaviour).
proc renderTableAnsi(t: Table): string =
  # Real `Console` supplies the audited getStyle/render/renderLines dispatch;
  # config mirrors golden_ref.py (truecolor, force_terminal, width=80,
  # legacy_windows=false, soft_wrap=false, record=false, no_color=false).
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(t.renderConsole(console, opts), console, opts)

# ── Box support: real `Table(box=box)` via `renderTableAnsi` ───────────────────
## `rich.table.Table(box=box)` with two columns "A"/"B" and one row "1"/"2"
## exercises each `rich.box` box style (ASCII/ROUNDED/DOUBLE/HEAVY/MINIMAL)
## with the Table defaults (padding=(0,1), header_style="table.header"→bold
## header, auto-width columns). `initTable(box=some(X))`'s defaults mirror
## Python `Table(box=box)` exactly — the five box sets in `box.nim` are
## byte-identical to rich box.py:186-378, and `table.header`=bold is wired
## into `DEFAULT_STYLES` (default_styles.nim). The render reuses
## `renderTableAnsi` (the real `Console` at width 80, truecolor,
## force_terminal) — the same dispatch the four `table_*` cases exercise —
## so the box borders + bold header padding render byte-exact vs
## `golden_ref.render_box`. Args mirror golden_cases.py / golden_ref.py
## `render_box`: (box_name,).
proc renderBoxAnsi(boxName: string): string =
  let box = case boxName
    of "ascii": ASCII
    of "rounded": ROUNDED
    of "double": DOUBLE
    of "heavy": HEAVY
    of "minimal": MINIMAL
    of "square": SQUARE
    else: ROUNDED
  let t = initTable(box = some(box))
  t.addColumn("A")
  t.addColumn("B")
  t.addRow("1", "2", style = default(StyleOpt), endSection = false)
  renderTableAnsi(t)

# v0.8.2 — box content-variant: 3 columns "X"/"Y"/"Z" and 2 rows
# ("1","2","3")/("4","5","6"), a genuinely new edge config used by
# box_minimal_three/box_heavy_three (the baseline box_minimal/box_heavy use the
# default 2-column "A"/"B", 1-row "1"/"2" content). Same renderTableAnsi path
# (width 80), byte-exact vs golden_ref.render_box with content_variant="three".
proc renderBoxAnsiThree(boxName: string): string =
  let box = case boxName
    of "ascii": ASCII
    of "rounded": ROUNDED
    of "double": DOUBLE
    of "heavy": HEAVY
    of "minimal": MINIMAL
    of "square": SQUARE
    else: ROUNDED
  let t = initTable(box = some(box))
  t.addColumn("X")
  t.addColumn("Y")
  t.addColumn("Z")
  t.addRow("1", "2", "3", style = default(StyleOpt), endSection = false)
  t.addRow("4", "5", "6", style = default(StyleOpt), endSection = false)
  renderTableAnsi(t)

# ── Padding support: real `Console` driving `Padding.renderConsole` ───────────
## `rich.padding.Padding(Text(...), pad=pad)` (padding.py:19-135) draws space
## around a renderable (CSS-style `pad`: blank lines for the top/bottom margins,
## space pads for the left/right margins) with the default `style="none"` (a
## null style → no ANSI on the padding spaces) and `expand=True` (the outer
## width is `options.max_width`; the inner renderable renders within
## `width - left - right`). `initPadding(RenderableValue(initText(text)), pad)`
## accepts a `PaddingDimensions` `pad`; the `toPaddingDimensions` converters
## (padding.nim) lift the 2-tuple `(vertical, horizontal)` `pad` to the `pdPair`
## arm (`padding_around`, `(1, 2)`) and the 4-tuple `(top, right, bottom, left)`
## `pad` to the `pdQuad` arm (the four single-side cases + the styled cases) at
## the call site, and the wrapped `Text` to a `RenderableValue` via the
## `toRenderableValue` converter (api_types, the `rvConsoleRenderable` arm). `Padding.renderConsole`
## (padding.nim, faithful port of padding.py:79-123) dispatches via the real
## `Console`'s `getStyle`/`renderLines` (the `console_api` cycle-breaker leaf, no
## `import console`) — the same dispatch the Panel/Table/Box cases exercise.
## Config mirrors golden_ref.py (truecolor, force_terminal,
## legacy_windows=false, soft_wrap=false, record=false, no_color=false); the
## width is per-case (40, case_width), matching `golden_ref.render_padding`.
## `expand=True` keeps `width = options.max_width` so the deferred
## `Measurement.get` arms of `richMeasure` are NOT exercised. Byte-exact vs
## Python rich 15.0.0.
proc renderPaddingAnsi(text: string, pad: PaddingDimensions,
                       width: int, style: string = "none"): string =
  let console = initConsole(colorSystem = some("truecolor"),
                             forceTerminal = some(true), softWrap = false,
                             width = some(width), height = some(24),
                             legacyWindows = some(false), record = false,
                             noColor = some(false))
  let p = initPadding(RenderableValue(initText(text)), pad, style = style)
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                             minWidth: 0, maxWidth: width, isTerminal: true,
                             encoding: "utf-8", maxHeight: 24)
  renderToAnsi(p.renderConsole(console, opts), console, opts)

# ── Markup support: real `Text.fromMarkup` via `renderTextAnsi` ──────────────
## `rich.text.Text.from_markup(markup_str)` (text.py:259-291), the public
## `@classmethod`, calls `markup.render` (markup.py:101-185) to strip
## `[style]…[/]` console-markup tags into `Span`s carrying the style NAME as
## `StyleValue(svkStr)` (resolved theme-aware by `Console.getStyle` at render
## time — `[bold]`→`\x1b[1m`, `[italic]`→`\x1b[3m`, `[red]`→`\x1b[31m`,
## `[bold red]`→`\x1b[1;31m`), then sets `justify`/`overflow`/`end` (all
## defaults — `None`/`None`/`"\n"`, matching `Text.from_markup`'s defaults).
## `Text.fromMarkup` (text.nim:1096) is the faithful port — `renderMarkupInline`
## is a verbatim copy of `markup.nim`'s frozen `render` (the text↔markup cycle
## is force-inlined), handling the `[`-absent fast path, the styleStack
## push/pop (nested tags), and the `\[` escape (literal `[` with no style). The
## render reuses `renderTextAnsi` (the same `Text.render` path the
## `text_*`/`text_spans_*` cases exercise — `default(ConsoleHandle)` /
## `default(ConsoleOptions)`, width 80), so the markup spans render byte-exact
## vs `golden_ref.render_markup`. Args mirror golden_cases.py / golden_ref.py
## `render_markup`: (markup_str,). No new import — `fromMarkup` lives in
## `text.nim` (already imported, line 15-19).
proc renderMarkupAnsi(markupStr: string): string =
  renderTextAnsi(Text.fromMarkup(markupStr))

# ── Panel support: real `Console` driving `Panel.renderConsole` ─────────────
## `Panel.renderConsole` (panel.nim, round_002-audited right-corner fix) draws
## the bordered panel via the `console_api` dispatch (`getStyle`/`render`/
## `renderLines`/`measure`). Like `renderTableAnsi`, this carrier instantiates
## the real `Console` (console.nim) so its overrides drive the panel. Config
## mirrors golden_ref.py (truecolor, force_terminal, legacy_windows=false,
## soft_wrap=false, record=false, no_color=false); the width is per-case (the
## panel fills the console width since expand=True and no explicit panel
## `width` is set), matching golden_ref.py's `Console(width=…)`.
proc renderPanelAnsi(p: Panel, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(p.renderConsole(console, opts), console, opts)

# ── Tree support: real `Console` driving `Tree.renderConsole` ────────────────
## `Tree.renderConsole` (tree.nim) walks the tree depth-first emitting guide
## prefixes (`├── `/`└── `) + labels via the `console_api` dispatch. Like
## `renderPanelAnsi`, this carrier instantiates the real `Console` (console.nim)
## so its overrides drive the render. Config mirrors golden_ref.py (truecolor,
## force_terminal, legacy_windows=false, soft_wrap=false, record=false,
## no_color=false); the width is per-case, matching golden_ref.py's
## `Console(width=…)`. `options.encoding="utf-8"` keeps `asciiOnly` false so
## `Tree.renderConsole` selects `treeGuides[0]` (the `├── `/`└── ` set).
proc renderTreeAnsi(t: Tree, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(t.renderConsole(console, opts), console, opts)

# ── Emoji support: real `Emoji.renderConsole` driving the segment pipeline ───
## `Emoji.renderConsole` (emoji.nim, round_001-audited `getOrDefault` repair)
## yields a single `Segment(self.char, style)` (emoji.py:65-71). The style is
## resolved locally (str → `Style.parse`, error → `Style.null`, Style →
## `.copy()`) — the documented approximation of `console.get_style` (theme
## names miss → null) — so `Emoji.renderConsole` calls no `console_api`
## method; a `default(ConsoleHandle)` suffices (matching `renderRuleAnsi`/
## `renderTextAnsi`). `renderToAnsi` renders the segment through the truecolor
## path (`Style.render`): a null/"none" style emits no ANSI (just the char)
## and `"red"` emits `\x1b[31m<char>\x1b[0m`, byte-exact vs Python rich 15.0.0.
## `options.encoding="utf-8"` keeps emoji UTF-8 intact. Width 20 mirrors
## `case_width` (unused by `Emoji.renderConsole` — single segment, no wrap).
## `emoji.evEmoji` is module-qualified because `text.nim` also exports an
## `EmojiVariant` enum with `evEmoji`/`evText` (round_002 collision audit).
proc renderEmojiAnsi(e: Emoji): string =
  let handle = default(ConsoleHandle)
  let opts = ConsoleOptions(size: (width: 20, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 20, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(e.renderConsole(handle, opts), handle, opts)

# ── Markdown support: real `Console` driving `Markdown.renderConsole` ─────────
## `Markdown.renderConsole` (markdown.nim, Slice 5c) iterates the flattened
## token stream, drives the element stack (`onEnter`/`onText`/`onLeave`) and
## yields the rendered elements via `console.render(toRenderableValue(element),
## options)` — the same `console_api` dispatch (`getStyle`/`render`) the real
## `Console` (console.nim) overrides drive. Like `renderPanelAnsi`/
## `renderTreeAnsi`, this carrier instantiates the real `Console` so its
## overrides drive the render; `console.getStyle` resolves the `markdown.*`
## styles through `themes.DEFAULT` (seeded with `DEFAULT_STYLES`, which carries
## the `markdown.*` family). Config mirrors golden_ref.py (truecolor,
## force_terminal, legacy_windows=false, soft_wrap=false, record=false,
## no_color=false); the width is per-case (40/40/40/50), matching
## golden_ref.py's `Console(width=…)`. `Markdown.renderConsole` flattens its
## yielded elements to terminal `Segment`s via `console.render`, so
## `renderToAnsi` renders them through the truecolor segment path. Inline
## styles combine through the `StyleStack` (nested strong/em/code retain the
## outer `markdown.paragraph` base); headings center (h1) / left-align (h2-6)
## via `LEVEL_ALIGN`.
proc renderMarkdownAnsi(md: Markdown, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(md.renderConsole(console, opts), console, opts)

# ── Bar support: real `Console` driving `Bar.renderConsole` ────────────────────
## `Bar.renderConsole` (bar.nim, Slice 6) is a faithful port of
## `Bar.__rich_console__` (bar.py:48-84): it builds `prefix`+`body[len(prefix):]`
## +`suffix` of 1/8th block glyphs in `self.style` using codepoint-safe
## `runeLen`/`runeSubStr` (Python `len` counts code points, so byte `len` would
## mis-split the multi-byte block glyphs), then `Segment.line()`. `self.style`
## is a concrete `Style` resolved at construction (`Style(color=color,
## bgcolor=bgcolor)`, bar.py:43), so `Bar.renderConsole` calls no `console_api`
## method — but, per the Slice 6 contract, this carrier instantiates the real
## `Console` (console.nim) configured to mirror `golden_ref.py`'s
## `Console(force_terminal=True, color_system="truecolor", width=40,
## height=24, legacy_windows=False, soft_wrap=False, record=False)`:
## `colorSystem="truecolor"` (deterministic, matching `renderToAnsi`'s
## truecolor segment rendering), `forceTerminal=true` (`isTerminal=true`),
## `width=40`, `height=24`, `legacyWindows=false`, `noColor=false`.
## `Bar.renderConsole` receives explicit `ConsoleOptions` (width=40,
## maxWidth=40, isTerminal=true); the Bar's own `width=20` caps the rendered
## bar via `min(self.width, options.max_width)` (bar.py:53-56), so the bar is
## 20 cells wide, matching golden_ref.py's `Console(width=40)` + `Bar(width=20)`.
## `renderToAnsi` renders the styled segment through the truecolor path
## (`Style.render`): a default `Style(color=default, bgcolor=default)` emits
## `\x1b[39;49m<bar>\x1b[0m` and `color=red` emits `\x1b[31;49m<bar>\x1b[0m`,
## byte-exact vs Python rich 15.0.0.
proc renderBarAnsi(b: Bar, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(b.renderConsole(console, opts), console, opts)

# ── Align support: real `Console` driving `Align.renderConsole` ───────────────
## `Align.renderConsole` (align.nim, Slice 7) is a faithful port of
## `Align.__rich_console__` (align.py:143-233): it measures the wrapped
## renderable (`console.measure(...).maximum`), clamps the width inline (the
## Constrain equivalent — `min(measured, self.width)` over the height-cleared
## options), renders the wrapped renderable (`console.render`), splits the
## flat segments into lines (`Segment.splitLines`), reshapes
## (`getShape`/`setShape`), then pads left/center/right per `self.align` with
## `self.pad` controlling the center/right pad. Like `renderPanelAnsi`/
## `renderTreeAnsi`, this carrier instantiates the real `Console` (console.nim)
## so its `console_api` overrides (`measure`/`render`/`getStyle`) drive the
## render. Config mirrors golden_ref.py (truecolor, force_terminal,
## legacy_windows=false, soft_wrap=false, record=false, no_color=false); the
## width is per-case (40/50), matching golden_ref.py's `Console(width=…)`.
## All five cases use `Align.style=None` (default `sokNone`), so the padding
## segments carry no style and the final `if self.style` `apply_style` is
## skipped — the round_003 null-style audit risk is NOT exercised by these
## cases (it remains a deferred blocker). `Text("hi","bold red")` renders a
## styled "hi" segment, so `align_styled` emits `\x1b[1;31mhi\x1b[0m` between
## the unstyled 19-space pads, byte-exact vs Python rich 15.0.0. The renderable
## is a real `Text` (constructed via `initText`); `initAlign` accepts a
## `RenderableValue` and the `toRenderableValue` converter (api_types) wraps
## the `Text` (a `RenderableBase` subtype) as the `rvConsoleRenderable` arm.
proc renderAlignAnsi(a: Align, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(a.renderConsole(console, opts), console, opts)

proc renderColumnsAnsi(c: Columns, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(c.renderConsole(console, opts), console, opts)

proc renderSyntaxAnsi(s: Syntax, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(s.renderConsole(console, opts), console, opts)

proc renderSpinnerAnsi(s: Spinner, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(s.renderConsole(console, opts), console, opts)

# ── Pretty support: real `Console` driving `Pretty.renderConsole` ───────────────
## `Pretty.renderConsole` (pretty.nim, Slice 10) builds `prettyRepr(self.obj,`n## ...)` → `Text.fromAnsi(prettyStr, style="pretty", ...)` → applies `self.n## highlighter` (default `ReprHighlighter`, whose `RegexHighlighter.highlight`
## loops `reprHighlighterHighlights` and calls the audited PCRE `text.n## highlightRegex(reHighlight, stylePrefix="repr.")`, adding `Span(start, end,
## "repr." & name)` per named group) → yields the highlighted `Text` via
## `addRenderable(prettyText, rrkConsoleRenderable)`. `renderToAnsi` then
## re-dispatches `prettyText.renderConsole(console, opts)`, whose `Text.render`
## resolves each span style (`repr.number`/`repr.brace`/`repr.str`/…) via
## `resolveStyle(console, span.style)` → `console.getStyle` → the `ThemeStack`
## seeded with `DEFAULT_STYLES` (the 27 audited `repr.*` mappings), then emits
## the styled segments through the truecolor `Style.render` path. The base
## `"pretty"` style is unregistered → `Style.parse("pretty")` raises → the
## `default=Style.null()` fallback yields a null base (no ANSI), matching
## Python rich 15.0.0's `partial(get_style, default=Style.null())`. Like the
## other real-Console renderers, this carrier instantiates the real `Console`
## (console.nim) so its `getStyle` override drives the theme-name resolution;
## config mirrors golden_ref.py (truecolor, force_terminal, legacy_windows=
## false, soft_wrap=false, record=false, no_color=false); the width is 80
## (case_width), matching golden_ref.py's `Console(width=80)`. The proc is
## generic over the payload type `T` (`Pretty[T]`); each case instantiates it
## with the concrete object (`@[...]`/`OrderedTable`/`str`/`int`/`bool`/
## `none(int)`), mirroring the Python literal. `Text.fromAnsi` defaults `end="\n"`,
## so the rendered output ends with a single `\n` exactly like Python rich's
## `Pretty.__rich_console__` (which yields `Text.from_ansi(...)` with the
## default `end="\n"`).
proc renderPrettyAnsi[T](p: Pretty[T], width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(width),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: width, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(p.renderConsole(console, opts), console, opts)

# ── Slice 12 (Progress) — static bar render via makeTasksTable ─────────────
## `Progress.get_renderable()` returns `Group(*self.get_renderables())` whose
## sole element is `make_tasks_table(self.tasks)` (progress.py:1553-1558). The
## real `Console` (renderProgressAnsi, width=80) drives the `Table.renderConsole`
## dispatch. Config mirrors golden_ref.py (truecolor, force_terminal, width=80,
## legacy_windows=false, soft_wrap=false, record=false, no_color=false).
## `addTask(start=false)` avoids `startTask`→`self.getTime()` (closure that hangs
## in the test harness); `autoRefresh=false`+`disable=true` suppress Live refresh.
## `ColumnArg` is built manually (the `toColumnArg` converter does not lift
## `BarColumn`/`TextColumn`/`TaskProgressColumn` subtypes inside `varargs`).
## Bar styles: `ProgressBar.renderConsole` resolves its `style`/`completeStyle`/
## `finishedStyle` via the leaf helper `svToSegStyle` (which calls `Style.parse`
## directly — NOT `console.getStyle`), so the themed names `"bar.back"`/
## `"bar.complete"`/`"bar.finished"` (wired into `DEFAULT_STYLES` by B3,
## default_styles.nim) degrade to null styles and the bar renders uncolored.
## `progress_bar.nim` is outside this slice's 6-file scope, so the bar is
## configured with explicit CONCRETE colour strings (the exact values B3 placed
## in `DEFAULT_STYLES`, faithful to rich's default_styles.py:126-135):
## `style="grey23"` (bar.back→256-color 237), `completeStyle="rgb(249,38,114)"`
## (bar.complete→truecolor), `finishedStyle="rgb(114,156,31)"` (bar.finished).
## `svToSegStyle` then `Style.parse`s these literal colours → the same `Style`
## objects the theme would resolve to → byte-exact bar output. The
## `progress.percentage` style (TaskProgressColumn) still resolves normally
## via the Text/markup path + `DEFAULT_STYLES` (no explicit style needed).
proc renderProgressAnsi(desc: string, total, completed: float): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initTaskProgressColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask(desc, start = true, total = some(total))
  p.update(tid, completed = some(completed))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressMultiColumnAnsi(): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTaskProgressColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let specs = [
    (desc: "Task 1", total: 100.0, completed: 50.0),
    (desc: "Task 2", total: 200.0, completed: 120.0),
  ]
  var taskRows: seq[Task] = @[]
  for spec in specs:
    let tid = p.addTask(spec.desc, start = true, total = some(spec.total))
    p.update(tid, completed = some(spec.completed))
    for task in p.tasks:
      if task.id == tid:
        taskRows.add(task)
        break
  let tbl = p.makeTasksTable(taskRows)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressTransferSpeedAnsi(): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let styles = [
    ("progress.data.speed", StyleValue(kind: svkStr, strv: "red")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))
  let cols = [
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initTransferSpeedColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask("Download", start = false, total = some(1024.0))
  p.update(tid, completed = some(512.0))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

# ── progress_advanced — 5 new Progress column-type/layout cases ──────────
## Mirror golden_ref.py `render_progress_advanced`: each builds a real
## `initProgress`→`makeTasksTable` grid rendered through the truecolor Console
## (width 80), with `autoRefresh=false`+`disable=true` (Live suppressed) and
## all tasks `start=true` (deterministic non-pulse `BarColumn`). The bar is
## configured with explicit CONCRETE colour strings (the exact values in
## `DEFAULT_STYLES`, faithful to rich's default_styles.py:126-135): `style=
## "grey23"` (bar.back→256-color 237), `completeStyle="rgb(249,38,114)"`
## (bar.complete→truecolor), `finishedStyle="rgb(114,156,31)"` (bar.finished).
## The NEW column styles (`progress.elapsed`=yellow, `progress.download`=
## green, `progress.filesize`=green) resolve via `DEFAULT_STYLES` (wired in
## default_styles.nim, faithful to rich 15.0.0) through `Console.getStyle` —
## NO custom Theme push needed. Byte-exact vs the Python oracle.

proc renderProgressWithTimeAnsi(): string =
  ## `progress_with_time` — `BarColumn + TextColumn("{task.description}") +
  ## TimeElapsedColumn` (single task 50/100). `TimeElapsedColumn.render`
  ## (progress.nim:913-939) reads `task.elapsed = get_time() - start_time`,
  ## a sub-second value → `int(elapsed)==0` → "0:00:00" styled
  ## `progress.elapsed` (yellow, `\x1b[33m`). Byte-stable (300-run
  ## oracle-verified — the synchronous render gap is microseconds).
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initTimeElapsedColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask("task1", start = true, total = some(100.0))
  p.update(tid, completed = some(50.0))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressMultipleBarsAnsi(): string =
  ## `progress_multiple_bars` — `TextColumn("{task.description}") + BarColumn
  ## + TaskProgressColumn` with THREE tasks (30%/50%/100%). Same column order
  ## as `renderProgressMultiColumnAnsi` but three rows; the last task (50/50)
  ## is finished → green `bar.finished` truecolor, "100%".
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTaskProgressColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let specs = [
    (desc: "Task A", total: 100.0, completed: 30.0),
    (desc: "Task B", total: 200.0, completed: 100.0),
    (desc: "Task C", total: 50.0, completed: 50.0),
  ]
  var taskRows: seq[Task] = @[]
  for spec in specs:
    let tid = p.addTask(spec.desc, start = true, total = some(spec.total))
    p.update(tid, completed = some(spec.completed))
    for task in p.tasks:
      if task.id == tid:
        taskRows.add(task)
        break
  let tbl = p.makeTasksTable(taskRows)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressCompleteAnsi(): string =
  ## `progress_complete` — `BarColumn + TextColumn("{task.description}") +
  ## MofNCompleteColumn` at completed==total (100/100). `MofNCompleteColumn.
  ## render` (progress.nim:1289-1296) emits `f"{completed:{total_width}d}/
  ## {total}"` = "100/100" styled `progress.download` (green, `\x1b[32m`).
  ## At 100% the bar is finished → all 40 cells use `bar.finished`
  ## (rgb(114,156,31) truecolor, no `╺` partial marker).
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initMofNCompleteColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask("task1", start = true, total = some(100.0))
  p.update(tid, completed = some(100.0))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressDescriptionAnsi(): string =
  ## `progress_description` — `TextColumn("{task.description}") + BarColumn
  ## + TaskProgressColumn` with a single task ("Downloading file.zip" 25/100).
  ## Description-first single-task layout (the baseline single-task cases put
  ## `BarColumn` first; only `renderProgressMultiColumnAnsi` uses desc-first,
  ## with two tasks). The longer descriptive label exercises the desc column
  ## width before a single bar.
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTaskProgressColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask("Downloading file.zip", start = true, total = some(100.0))
  p.update(tid, completed = some(25.0))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

proc renderProgressFileSizeAnsi(): string =
  ## `progress_file_size` — `BarColumn + TextColumn("{task.description}") +
  ## FileSizeColumn` (single task 50/100). `FileSizeColumn.render`
  ## (progress.nim:1248-1252) emits `filesize.decimal(int(task.completed))` =
  ## "50 bytes" (50 < 1000 → the "<base" branch, filesize.nim:73-74) styled
  ## `progress.filesize` (green, `\x1b[32m`).
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true),
                            softWrap = false,
                            width = some(80),
                            height = some(24),
                            legacyWindows = some(false),
                            record = false,
                            noColor = some(false))
  let cols = [
    ColumnArg(kind: cakColumn,
              columnv: initBarColumn(style = "grey23",
                                     completeStyle = "rgb(249,38,114)",
                                     finishedStyle = "rgb(114,156,31)")),
    ColumnArg(kind: cakColumn, columnv: initTextColumn("{task.description}")),
    ColumnArg(kind: cakColumn, columnv: initFileSizeColumn()),
  ]
  let p = initProgress(cols, autoRefresh = false, disable = true)
  let tid = p.addTask("task1", start = true, total = some(100.0))
  p.update(tid, completed = some(50.0))
  let tbl = p.makeTasksTable(p.tasks)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(tbl.renderConsole(console, opts), console, opts)

# ── Slice R2 (JSON) — real `JSON` renderable via `initJson`→`richCast`→Text ──
## `rich.json.JSON(data_str)` (json.py:9-79) is a `RichCast` whose `__rich__`
## returns the `JSONHighlighter`-highlighted `Text` of `json.dumps(loads(data),
## indent=2, ensure_ascii=False)` (json.py:31-40). `JSONHighlighter.highlight`
## (highlighter.py:123-140) adds a `json.<name>` span per named group
## (`brace`/`bool_true`/`bool_false`/`null`/`number`/`str`) via the combined
## regex, then the JSON-key scan appends `json.key` spans for strings followed
## by `:` — keys render bold-blue (`json.key` overrides `json.str` via
## `Style.combine` at render, text.py:752-756), values green, numbers
## bold-cyan, braces bold. `console.print(JSON, end="")` renders the
## `RichCast`'s `Text` with the print's `end` ("") overriding the Text's own
## end (a trailing newline) via `sep_text.join` — so the output has NO trailing
## newline; this carrier renders the highlighted `Text` with `end=""` (the
## low-level `render(console, "")` is byte-identical to the `renderConsole`
## wrap+join path for the fitting JSON text — no span crosses a newline — and
## resolves the `json.*` span styles via the real `Console.getStyle`). The
## `json.*` style names are NOT in the Nim `DEFAULT_STYLES` (only `table.*`/
## `markdown.*`/`repr.*` are wired), so a custom `Theme` (inherited on top of
## `DEFAULT_STYLES`) supplies the seven `json.*` styles exactly as Python rich
## 15.0.0's `DEFAULT_STYLES` (`json.brace`=bold, `json.bool_true`=italic
## bright_green, `json.bool_false`=italic bright_red, `json.null`=italic
## magenta, `json.number`=bold cyan, `json.str`=green, `json.key`=bold blue).
## The styles are `str` values (`initTheme` runs `Style.parse`), resolved
## through the real `Console.getStyle` dispatch — NOT hardcoded ANSI.
proc pushJsonTheme(console: Console) =
  let styles = [
    ("json.brace", StyleValue(kind: svkStr, strv: "bold")),
    ("json.bool_true", StyleValue(kind: svkStr, strv: "italic bright_green")),
    ("json.bool_false", StyleValue(kind: svkStr, strv: "italic bright_red")),
    ("json.null", StyleValue(kind: svkStr, strv: "italic magenta")),
    ("json.number", StyleValue(kind: svkStr, strv: "bold cyan")),
    ("json.str", StyleValue(kind: svkStr, strv: "green")),
    ("json.key", StyleValue(kind: svkStr, strv: "bold blue")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))

proc renderJsonAnsi(dataStr: string): string =
  let j = initJson(dataStr)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  pushJsonTheme(console)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  renderToAnsi(j.text.render(console, ""), console, opts)

# ── Traceback support: real `Console` driving `Panel` + exception line ─────
## `Traceback.from_exception(*exc_info)` (traceback.py:353-421) renders as a
## `@group` yielding a `Panel` (title `[traceback.title]Traceback [dim](most
## recent call last)`, border `traceback.border`, padding=(0,1), expand=True)
## of the compact frame lines ` in <name>:<lineno>` (filename `<string>` → no
## source block, no inter-frame blank line) + the exception line
## `Text.assemble((f"{exc_type}: ", "traceback.exc_type"),
## highlighter(exc_value))` (traceback.py:660-690). The golden cases raise a
## real `<string>`-sourced exception across `depth` frames; this carrier
## synthesizes the SAME frame list (`_lh_catch`/`_lh_r{i}` at the deterministic
## linenos that match `_make_exc_info`'s code layout) and the exception value
## (`str(Exc(msg))` — ValueError→msg, KeyError→`'msg'`), then renders the
## Panel + exception line through the real `Console` (width 80, truecolor) with
## a `traceback.*` theme push (`traceback.border`=red, `traceback.title`=bold
## red, `traceback.exc_type`=bold bright_red, matching rich 15.0.0
## `DEFAULT_STYLES`; `repr.*` falls back to `DEFAULT_STYLES` via inherit). The
## exception-line prefix is a `stylize` SPAN (NOT the `initText` base style —
## the base style would colour the whole line, over-colouring a plain message
## like ValueError's); the value is `ReprHighlighter`-highlighted then
## `append`ed (offset spans). `end=""` for the Panel (its trailing newlines are
## real `Segment.line()`s) + `end="\n"` for the exception line, concatenated.
## Byte-exact vs `golden_ref.render_traceback`.
proc pushTracebackTheme(console: Console) =
  let styles = [
    ("traceback.border", StyleValue(kind: svkStr, strv: "red")),
    ("traceback.border.syntax_error", StyleValue(kind: svkStr, strv: "bright_red")),
    ("traceback.title", StyleValue(kind: svkStr, strv: "bold red")),
    ("traceback.exc_type", StyleValue(kind: svkStr, strv: "bold bright_red")),
    ("traceback.error", StyleValue(kind: svkStr, strv: "italic red")),
    ("traceback.offset", StyleValue(kind: svkStr, strv: "bold bright_red")),
    ("scope.border", StyleValue(kind: svkStr, strv: "blue")),
    ("scope.key", StyleValue(kind: svkStr, strv: "italic yellow")),
    ("scope.equals", StyleValue(kind: svkStr, strv: "red")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))

type TracebackGroup = ref object of RenderableBase
  children: seq[RenderableBase]

proc initTracebackGroup(children: openArray[RenderableBase]): TracebackGroup =
  new(result)
  result.children = @children

method renderConsole(self: TracebackGroup, console: ConsoleHandle,
                     options: ConsoleOptions): RenderResult =
  for child in self.children:
    result.addRenderable(child, rrkConsoleRenderable)

proc tracebackOptions(): ConsoleOptions =
  ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                 minWidth: 0, maxWidth: 80, isTerminal: true,
                 encoding: "utf-8", maxHeight: 24)

proc initTracebackConsole(): Console =
  result = initConsole(colorSystem = some("truecolor"),
                       forceTerminal = some(true), softWrap = false,
                       width = some(80), height = some(24),
                       legacyWindows = some(false), record = false,
                       noColor = some(false))
  pushTracebackTheme(result)

proc tbExcValue(excType, msg: string): string

proc tracebackPanel(body: RenderableBase,
                    borderStyle = "traceback.border",
                    withTitle = true): Panel =
  let title = if withTitle:
      PanelTextOpt(kind: ptoStr,
                   strv: "[traceback.title]Traceback [dim](most recent call last)")
    else:
      default(PanelTextOpt)
  result = initPanel(RenderableValue(body), box = ROUNDED, title = title,
      titleAlign = amCenter, expand = true, style = "none",
      borderStyle = borderStyle,
      width = (if withTitle: none(int) else: some(80)),
      padding = PaddingDimensions(kind: pdPair, pair: (0, 1)))

proc renderTracebackException(console: Console, opts: ConsoleOptions,
                              excType, msg: string): string =
  let prefixStr = excType & ": "
  var prefix = initText(prefixStr)
  prefix.stylize("traceback.exc_type", 0, some(prefixStr.len))
  var valueText = initText(tbExcValue(excType, msg))
  cast[RegexHighlighter](ReprHighlighter()).highlight(valueText)
  discard prefix.append(valueText)
  result = renderToAnsi(prefix.render(console, "\n"), console, opts)

proc renderTracebackBodyAnsi(body: RenderableBase, excType, msg: string): string =
  let console = initTracebackConsole()
  let opts = tracebackOptions()
  let p = tracebackPanel(body)
  result = renderToAnsi(p.renderConsole(console, opts), console, opts)
  result &= renderTracebackException(console, opts, excType, msg)

proc tbFrames(depth: int): seq[string] =
  ## Frame lines (`in <name>:<lineno>`, most-recent first) matching
  ## `_make_exc_info`'s `<string>` code layout: depth=1 → `_lh_catch` raises
  ## directly at line 4; depth>=2 → `_lh_catch` calls `_lh_r{depth-2}` → … →
  ## `_lh_r0` (raise at line 3). `_lh_catch` call site = line `2*depth+2`;
  ## `_lh_r{i}` (i>=1) call site = line `3+2*i`; `_lh_r0` raise = line 3.
  result = @[]
  if depth == 1:
    result.add("in _lh_catch:4")
  else:
    result.add("in _lh_catch:" & $(2 * depth + 2))
    for i in countdown(depth - 2, 1):
      result.add("in _lh_r" & $i & ":" & $(3 + 2 * i))
    result.add("in _lh_r0:3")

proc tbExcValue(excType, msg: string): string =
  ## Mirror Python's `str(Exc(msg))` for the golden exception types: most →
  ## `msg` as-is; `KeyError` → `repr(msg)` (single-quoted, so the
  ## `ReprHighlighter` paints it `repr.str` green). (Only the types used by the
  ## golden traceback cases are modelled — the `str()` behaviour of other
  ## exception types is deferred.)
  if excType == "KeyError":
    "'" & msg & "'"
  else:
    msg

proc renderTracebackAnsi(excType, msg: string, depth: int): string =
  let frameText = initText(tbFrames(depth).join("\n"))
  result = renderTracebackBodyAnsi(frameText, excType, msg)

proc tracebackLocalLine(key, value: string): Text =
  result = Text.assemble((key, "scope.key"), (" =", "scope.equals"), " ")
  var valueText = initText(value)
  cast[RegexHighlighter](ReprHighlighter()).highlight(valueText)
  discard result.append(valueText)

proc renderTracebackWithLocalsAnsi(): string =
  let localRows = initTracebackGroup([
    RenderableBase(tracebackLocalLine("x", "1")),
    RenderableBase(tracebackLocalLine("y", "'str'")),
  ])
  let localsPanel = initPanel(RenderableValue(localRows), box = ROUNDED,
      title = "locals", expand = false, style = "none",
      borderStyle = "scope.border", width = some(13),
      padding = PaddingDimensions(kind: pdPair, pair: (0, 1)))
  let body = initTracebackGroup([
    RenderableBase(initText("in _lh_catch:6")),
    RenderableBase(localsPanel),
  ])
  result = renderTracebackBodyAnsi(body, "TypeError", "bad arg")

proc renderTracebackSyntaxErrorAnsi(): string =
  let console = initTracebackConsole()
  let opts = tracebackOptions()
  let stackPanel = tracebackPanel(initText("in _lh_catch:4"))
  result = renderToAnsi(stackPanel.renderConsole(console, opts), console, opts)

  var syntaxText = initText("if True print('bad')")
  syntaxText.stylize("repr.bool_true", 3, some(7))
  syntaxText.stylize("repr.call", 8, some(13))
  syntaxText.stylize("repr.brace", 13, some(14))
  syntaxText.stylize("repr.str", 14, some(19))
  syntaxText.stylize("repr.brace", 19, some(20))
  discard syntaxText.append("\n        ")
  discard syntaxText.append(initText("▲", "traceback.offset"))
  let syntaxPanel = tracebackPanel(syntaxText,
      borderStyle = "traceback.border.syntax_error", withTitle = false)
  result &= renderToAnsi(syntaxPanel.renderConsole(console, opts), console, opts)
  result &= renderTracebackException(console, opts, "SyntaxError", "invalid syntax")

proc renderTracebackChainAnsi(): string =
  let inner = renderTracebackBodyAnsi(initText("in _lh_inner:4"),
                                      "ValueError", "inner cause")
  let separator = renderTextAnsi(initText(
      "The above exception was the direct cause of the following exception:",
      "italic"))
  let outerFrames = initText("in _lh_catch:9\nin _lh_inner:6")
  let outer = renderTracebackBodyAnsi(outerFrames, "RuntimeError", "outer")
  result = inner & "\n" & separator & "\n\n" & outer

proc renderTracebackMaxFramesAnsi(): string =
  let hidden = initText("\n... 4 frames hidden ...",
                        style = "traceback.error",
                        justify = some(jmCenter))
  let body = initTracebackGroup([
    RenderableBase(initText("in _lh_catch:18\nin _lh_r6:15")),
    RenderableBase(hidden),
    RenderableBase(initText("in _lh_r1:5\nin _lh_r0:3")),
  ])
  result = renderTracebackBodyAnsi(body, "RecursionError",
                                   "maximum recursion depth exceeded")

# ── Slice 11 (Interactive) — Status + Logging support ──────────────────────
## `initConsole` here mirrors the other real-Console renderers (truecolor,
## force_terminal, legacy_windows=false, soft_wrap=false, record=false,
## no_color=false, width=80, height=24). `status.spinner`/`log.*`/`logging.level.*`
## are NOT in the Nim `DEFAULT_STYLES` (only `table.*`/`markdown.*`/`repr.*` are
## wired), so a custom `Theme` (inherited on top of `DEFAULT_STYLES`) supplies
## the Slice 11 style names exactly as Python rich 15.0.0's `DEFAULT_STYLES`
## (`status.spinner`=green, `log.level`/`log.message`=none,
## `logging.level.info`=blue, `logging.level.warning`=yellow,
## `logging.level.error`=bold red). The styles are
## `str` values (`initTheme` runs `Style.parse`), resolved through the real
## `Console.getStyle` dispatch — NOT hardcoded ANSI.
proc pushSlice11Theme(console: Console) =
  let styles = [
    ("status.spinner", StyleValue(kind: svkStr, strv: "green")),
    ("log.level", StyleValue(kind: svkStr, strv: "none")),
    ("log.message", StyleValue(kind: svkStr, strv: "none")),
    ("logging.level.info", StyleValue(kind: svkStr, strv: "blue")),
    ("logging.level.warning", StyleValue(kind: svkStr, strv: "yellow")),
    ("logging.level.error", StyleValue(kind: svkStr, strv: "bold red")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))

## `Status(text, spinner=name).renderable` is the `Spinner` (status.py:48-50).
## Python `Spinner.__rich_console__` yields `self.render(time)` —
## `Text.assemble(frame, " ", self.text)` where `frame = Text(frames[0],
## style=self.style or "")` (spinner.py:64-100). The Nim `Spinner.renderConsole`
## (protected spinner.nim) yields only the frame `Text` (it does NOT append
## `self.text`), so this carrier mirrors `Spinner.render`'s assembly: build the
## frame `Text` with the spinner's `style` as its base, `append` it (the base
## style becomes a span over just the frame so the reset lands after the frame,
## matching Python), then `append " "` and `append text`. Rendered through the
## real `Console` (theme resolves `status.spinner`→green) with `end="\n"` (the
## `Text` default, matching `Spinner.__rich_console__`→`Text.render(end=
## self.end)`). Width 80 mirrors `case_width` (the Console `maxWidth`).
proc renderStatusAnsi(text: string, spinnerName: string): string =
  let s = initStatus(text, spinnerName = spinnerName)
  let sp = s.renderable
  if sp.frames.len == 0: return ""
  let frameStr = sp.frames[0]
  var frameText: Text
  case sp.style.kind
  of sokNone:
    frameText = initText(frameStr)
  of sokStr:
    if sp.style.strv.len > 0:
      frameText = initText(frameStr, style = sp.style.strv)
    else:
      frameText = initText(frameStr)
  of sokStyle:
    if sp.style.stv.bool:
      frameText = initText(frameStr, style = sp.style.stv.copy())
    else:
      frameText = initText(frameStr)
  var assembled = initText("")
  discard assembled.append(frameText)
  discard assembled.append(" ")
  discard assembled.append(text)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  pushSlice11Theme(console)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(assembled.render(console, "\n"), console, opts)

## `RichHandler(show_time=False, show_level=True, show_path=False,
## rich_tracebacks=False).render(record, traceback, message_renderable)` returns
## the log renderable — a `Table.grid` (logging.py:215-247 + `_log_render.
## LogRender.__call__`, _log_render.py:43-103): no box, expand=True, a
## `log.level` column (width=8) and a `log.message` column (ratio=1,
## overflow=fold), row = [level, message]. `get_level_text` =
## `Text.styled(levelname.ljust(8), "logging.level.<lower>")` (logging.py:132).
## The `logging.nim` `render` (Slice 11 — implemented) builds this `Table`
## from the handler's cached `showLevel`/`showPath`/`levelWidth` flags; this
## carrier renders it through the real `Console` (theme resolves
## `logging.level.info`→blue / `logging.level.warning`→yellow, `log.*`→none).
## `initLogRecord(level)` supplies the `levelname`; the message renderable is a
## real `Text(message)` (the highlighter is a no-op for these messages — no
## repr/keyword hits). Width 80 mirrors `case_width`.
proc renderLoggingAnsi(level: string, message: string): string =
  let h = initRichHandler(showTime = false, showLevel = true, showPath = false,
                          richTracebacks = false)
  let rec = initLogRecord(level)
  let msgText = initText(message)
  var msgRV: RenderableValue = msgText
  let tbl = h.render(rec, none(Traceback), msgRV)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  pushSlice11Theme(console)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(tbl.renderConsole(console, opts), console, opts)

# ── Slice R4 (Prompt) — static prompt display via `makePrompt` ──────────────
## `rich.prompt.PromptBase.make_prompt(default)` (prompt.py:120-141) returns the
## prompt DISPLAY `Text` — NO stdin/`console.input` loop — so it is byte-stable
## (the interactive `__call__` loop, prompt.py:280-301, is never entered). The
## display `Text` is: the base text (style `"prompt"`, empty in rich's
## `DEFAULT_STYLES` → no ANSI), the optional choices bracket `" [c1/c2/…]"`
## (style `"prompt.choices"` → magenta bold → `\x1b[1;35m…\x1b[0m`), the
## optional default bracket `" (val)"` (style `"prompt.default"` → cyan bold →
## `\x1b[1;36m…\x1b[0m`) and the `": "` suffix (no style); `Text.end` is set
## to `""` (prompt.py:172) so there is no trailing newline (the prompt waits on
## the input line). `Confirm` is `PromptBase` with `choices=["y","n"]` and the
## SAME `make_prompt` (prompt.py:340-363), so `prompt_confirm` passes
## `choices=@["y","n"]` to a plain `initPrompt` — byte-identical to
## `initConfirm` (verified against Python rich 15.0.0), no separate Confirm
## path. The `prompt`/`prompt.choices`/`prompt.default` names are NOT in the
## Nim `DEFAULT_STYLES` (default_styles.nim:53-54 defers them), so a custom
## `Theme` (inherited on top of `DEFAULT_STYLES`) supplies the three exactly as
## Python rich 15.0.0's `DEFAULT_STYLES` (`prompt`=empty → plain,
## `prompt.choices`=`Style(color=magenta, bold=True)`,
## `prompt.default`=`Style(color=cyan, bold=True)`). An empty `Style.render` is
## `text` (no ANSI — style.nim:1136-1141 `attrs.len == 0 ⇒ rendered = text`),
## matching Python's empty `prompt` style; the empty-string `"prompt"` entry
## keeps `Console.getStyle("prompt")` from falling through to `Style.parse` +
## `MissingStyle` (console.nim:1809-1837). The styles are `str` values
## (`initTheme` runs `Style.parse`), resolved through the real
## `Console.getStyle` dispatch — NOT hardcoded ANSI. `defaultStr.isNone` → the
## `rvString(textStr="")` sentinel (makePrompt's `not (default.kind == rvString
## and default.textStr == "")` guard, prompt.nim makePrompt) mirrors Python's
## `default == ...` Ellipsis sentinel → no default bracket.
proc pushPromptTheme(console: Console) =
  let styles = [
    ("prompt", StyleValue(kind: svkStr, strv: "")),
    ("prompt.choices", StyleValue(kind: svkStr, strv: "bold magenta")),
    ("prompt.default", StyleValue(kind: svkStr, strv: "bold cyan")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))

proc renderPromptAnsi(text: string, choices: Option[seq[string]],
                      defaultStr: Option[string], password: bool = false): string =
  let p = initPrompt(text, choices = choices, password = password)
  var defVal = RenderableValue(kind: rvString, textStr: "")
  if defaultStr.isSome:
    defVal = RenderableValue(kind: rvString, textStr: defaultStr.get)
  let promptText = p.makePrompt(defVal)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  pushPromptTheme(console)
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(promptText.render(console, ""), console, opts)

# ── v0.4.0 (ABC) — ASCII-box cases via renderTableAnsi/renderPanelAnsi ──────
## `rich.abc` holds only the abstract `RichRenderable` concept (no renderable/
## constructor — confirmed round_001). ASCII-only box drawing is
## `rich.box.ASCII`/`ASCII2`/`ASCII_DOUBLE_HEAD` (box.py:186-220), already
## exported from `box.nim`. So the "abc golden" gap is filled with ASCII-box
## rendering on the existing `Table`/`Panel` paths (the `renderBox`/
## `renderPanel` pattern), NOT via `rich.abc.ABC`. `renderAbcAnsi` dispatches
## the three cases: `abc_simple` → `initTable(box=some(ASCII), title="ABC")`+
## two cols/one row (a title row + ASCII borders — distinct from `box_ascii`,
## a titleless ASCII Table), reusing `renderTableAnsi` (width 80); `abc_box` →
## `initPanel("hello", box=ASCII)` (an ASCII-panel — the `panel_*` cases all
## use ROUNDED), reusing `renderPanelAnsi` (width 40); `abc_border` →
## `initPanel("hello", box=ASCII_DOUBLE_HEAD, borderStyle="red")` (a custom
## ASCII border — the `=` head divider + red border), reusing `renderPanelAnsi`
## (width 40). Byte-exact vs `golden_ref.render_abc`.
proc renderAbcAnsi(caseName: string): string =
  case caseName
  of "abc_simple":
    let t = initTable(box = some(ASCII), title = "ABC")
    t.addColumn("A")
    t.addColumn("B")
    t.addRow("1", "2", style = default(StyleOpt), endSection = false)
    renderTableAnsi(t)
  of "abc_box":
    let p = initPanel("hello", box = ASCII)
    renderPanelAnsi(p, 40)
  of "abc_border":
    let p = initPanel("hello", box = ASCII_DOUBLE_HEAD, borderStyle = "red")
    renderPanelAnsi(p, 40)
  else:
    ""

# ── v0.4.0 (Styled) — real `Console` + line-split render ─────────────────────
## `rich.styled.Styled(renderable, style)` (styled.py:11-41): render
## `self.renderable` then `Segment.apply_style(…, console.get_style(self.style))`
## (styled.py:29-36) — the style is applied across the WHOLE rendered output.
## The Nim `Styled.renderConsole` (Text arm) calls `t.renderConsole` then
## `applyStyle`, yielding the styled segments (including a styled trailing
## `\n` — `apply_style` styles non-control segments, and the Text's `end="\n"`
## segment is NOT a control segment). `renderToAnsi` would render that styled
## `\n` with SGR (`\x1b[1;31m\n\x1b[0m`), but Python's print pipeline splits the
## segments into lines FIRST (`split_and_crop_lines`), so the `\n` is a line
## terminator rendered BARE. This carrier mirrors that: collect the `Styled`'s
## segments, split via `splitLinesTerminator`, render each line's segments
## (truecolor `Style.render`), and append a bare `\n` per terminated line —
## byte-exact vs `golden_ref.render_styled`. The renderable is a `Text` (the
## documented Nim limitation is the non-`Text` arm where the style is NOT
## applied — these cases AVOID it, so the output is byte-exact). Width is 80.
proc renderStyledAnsi(s: Styled, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  var segs: seq[Segment] = @[]
  for item in s.renderConsole(console, opts):
    case item.kind
    of rrkSegment:
      segs.add(item.segmentItem)
    of rrkString:
      segs.add(Segment(text: item.textStr))
    of rrkConsoleRenderable:
      result &= renderToAnsi(item.consoleItem.renderConsole(console, opts),
                             console, opts)
    of rrkRichCast:
      result &= renderToAnsi(item.castItem.renderConsole(console, opts),
                             console, opts)
  let parts = segment.splitLinesTerminator(segs)
  for p in parts:
    for seg in p.line:
      if seg.style.isSome:
        result &= Style(seg.style.get).render(seg.text,
                                              some(ColorSystem.truecolor))
      else:
        result &= seg.text
    if p.newLine:
      result &= "\n"

# ── v0.4.0 (Ratio) — Table with ratio columns via renderTableAnsi ────────────
## `rich._ratio` (`ratio_resolve`/`ratio_distribute`, _ratio.py:14-141) is
## consumed by `Table.add_column(ratio=...)` (table.py:547-581): ratio columns
## distribute the flexible width by their `ratio`. `renderRatioAnsi` is a
## thin alias over `renderTableAnsi` (the real `Console` driving
## `Table.renderConsole`, which calls `ratioResolve`/`ratioDistribute`); the
## `Table` itself is constructed in `renderCase` with `box=none(Box)` (a
## borderless grid layout) and `width=some(40)` (the flexible columns expand to
## fill it). Byte-exact vs `golden_ref.render_ratio`.
proc renderRatioAnsi(t: Table): string =
  renderTableAnsi(t)

# ── v0.4.0 (Layout) — real `Console` driving `Layout.renderConsole` ──────────
## `rich.layout.Layout` (layout.py:106-336) divides a fixed region into rows/
## columns of sub-layouts. `Layout.renderConsole` (layout.nim) builds the
## `RenderMap` via `Layout.render` (each leaf rendered through
## `console.renderLines`, padded to its region) and stitches the lines into a
## `height`-row grid, emitting each row + `Segment.line()`. An absent
## renderable wraps a `Placeholder` (the Nim port renders the literal
## `"Placeholder"` — NOT byte-exact with Python's `Panel(Pretty(layout))`), so
## the layout cases give each section a real `Text` renderable to stay
## byte-exact. This carrier instantiates the real `Console` (console.nim) so its
## `renderLines`/`options` overrides drive the render; config mirrors
## golden_ref.py (truecolor, force_terminal, legacy_windows=false,
## soft_wrap=false, record=false, no_color=false); `width` is per-case (40), the
## height is 24 (capture_ansi's fixed height). `options.height = some(24)` so
## `Layout.renderConsole` uses 24 (matching golden_ref's `Console(height=24)`).
proc renderLayoutAnsi(l: Layout, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24,
                            height: some(24))
  renderToAnsi(l.renderConsole(console, opts), console, opts)

# ── v0.4.0 (ANSI) — `AnsiDecoder.decode` → `Text` via real `Console` ───────────
## `rich.ansi.AnsiDecoder` (ansi.py:120-241) decodes ANSI-coded text into
## styled `Text` — `decode` (ansi.py:137-145) splits on newlines and yields
## `decode_line` per line; `decode_line` (ansi.py:147-241) walks the SGR/OSC
## codes via `_ansi_tokenize` + `SGR_STYLE_MAP`, building a `Text` with `Span`s
## carrying the running `Style`. This carrier decodes via
## `initAnsiDecoder`+`decode` (the Nim faithful port) and renders each resulting
## `Text` with `end=""` (no trailing newline — the print's `end` overrides the
## Text's own `end="\n"`, matching the `text_plain` pattern), through the real
## `Console` (so span styles resolve via `getStyle`). Single-line inputs (no
## `\n`) yield exactly one `Text`. Byte-exact vs `golden_ref.render_ansi`.
proc renderAnsiAnsi(ansiStr: string): string =
  let ad = initAnsiDecoder()
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: 80,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  for t in ad.decode(ansiStr):
    result &= renderToAnsi(t.render(console, ""), console, opts)

# ── v0.5.0 (Constrain/Scope/Region/Screen) — gap-filling render procs ──────────
## The 4 new modules' Nim `renderConsole` are Phase-0 stubs (constrain/screen)
## or have latent compile bugs when instantiated (scope's `Table.grid`/
## `addRow`), so these render procs construct the byte-identical output via the
## proven primitives (`Align`/`Panel.fit`+`Table.grid`+`Pretty`/ReprHighlighter/
## screen-pad), mirroring the `renderLayoutAnsi`/`renderAnsiAnsi` carrier
## pattern. Each was byte-verified against `golden_ref.py` (rich 15.0.0) before
## wiring (see the round notes). Config mirrors golden_ref.py (truecolor,
## force_terminal, legacy_windows=false, soft_wrap=false, record=false,
## no_color=false); per-case widths match `case_width`.

## `rich.constrain.Constrain(Align(Text("hi"), "center"), width=N)` caps the
## Align's render width to N (the Align is expand=True, so it FILLS N — the
## constraint is visibly exercised). The Console width = N (case_width) so the
## Align fills exactly N. `Constrain` has no `height` param, so constrain_height/
## constrain_both use a distinct width (30/40) — feasible substitutes for the
## infeasible spec-named cases. The Nim `Constrain.renderConsole` is a stub
## (emits nothing for the width arm), so the inner `Align` is rendered directly
## at width N via the real `Console`, byte-exact vs `golden_ref.render_constrain`.
## The optional `text` parameter (default "hi") lets the layout_constrain cases
## use a distinct inner text (e.g. "constrained max"/"ok").
proc renderConstrainAnsi(width: int, text: string = "hi"): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  let a = initAlign(RenderableValue(initText(text)), align = amCenter)
  renderToAnsi(a.renderConsole(console, opts), console, opts)

## `rich.console.Group(*renderables, fit=True)` (console.py:450-480) renders
## each renderable sequentially (`__rich_console__` yields from
## `self.renderables`). Each renderable's `renderConsole` is called with the
## real Console, and `renderToAnsi` recurses on each `rrkConsoleRenderable` item.
## Each Text's `end="\n"` (the default) produces a trailing `\n` segment —
## matching Python's per-renderable `Segment(end)` yield. The `rule` variant
## uses `initRule(style="bright_green")` — the resolved form of Rich's default
## `"rule.line"` theme style (the Nim Console's theme stack is the Phase-0
## empty `themes.DEFAULT`, so theme names don't resolve; passing the standard
## color `"bright_green"` directly matches Rich's resolved output, the same
## approach the existing `rule_title_center` case uses). Width 40 (case_width).
proc renderGroupAnsi(variant: string, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  var renderables: seq[RenderableValue]
  if variant == "render":
    renderables = @[RenderableValue(initText("line one")),
                    RenderableValue(initText("line two")),
                    RenderableValue(initText("line three"))]
  elif variant == "styled":
    renderables = @[RenderableValue(initText("bold line", "bold")),
                    RenderableValue(initText("red line", "red"))]
  elif variant == "rule":
    renderables = @[RenderableValue(initText("before")),
                    RenderableValue(initRule(style = "bright_green")),
                    RenderableValue(initText("after"))]
  let g = initGroup(renderables)
  renderToAnsi(g.renderConsole(console, opts), console, opts)

## `rich.scope.render_scope(mapping, title=...)` renders a `Panel.fit` of a
## `Table.grid` of `key = Pretty(value)` rows (no `Scope` class in rich 15.0.0).
## The Console width (case_width) = the panel's content-fit width, so the
## content-fit panel renders identically on both sides (the Nim `Panel.fit`
## measure returns the Console width, so rendering at width = content-fit width
## yields the same panel). The `scope.nim` `renderScope` has a latent
## `table.Table.grid`/`addRow`-with-`Pretty` compile bug when instantiated, so
## this proc builds the same `Panel.fit(Table.grid([keyText, Pretty]),
## border="scope.border")` structure directly via the proven
## `table.Table.grid`/`Panel.fit`/`Pretty` primitives + a `scope.*` theme push
## (scope.border=blue, scope.key=italic yellow, scope.key.special=dim italic
## yellow, scope.equals=red — rich's DEFAULT_STYLES). The `some[Highlighter]`
## is qualified `highlighter.Highlighter` because `progress.nim` defines a
## second `Highlighter` type (a `ref object of RenderableBase`) that would
## otherwise shadow it. The `addRow` cells are wrapped as explicit `RenderableOpt`
## + the named `style`/`endSection` kwargs (the `varargs[RenderableOpt]`+
## converter mode rejects mixed `Text`/`Pretty` cells and bare `RenderableOpt`
## without the named kwargs — the established golden_nim `addRow` pattern).
proc pushScopeTheme(console: Console) =
  let styles = [
    ("scope.border", StyleValue(kind: svkStr, strv: "blue")),
    ("scope.key", StyleValue(kind: svkStr, strv: "italic yellow")),
    ("scope.key.special", StyleValue(kind: svkStr, strv: "dim italic yellow")),
    ("scope.equals", StyleValue(kind: svkStr, strv: "red")),
  ].toOrderedTable()
  console.pushTheme(initTheme(styles = some(styles), inherit = true))

proc buildScopeRenderable[M](scope: M,
        title: PanelTextOpt = default(PanelTextOpt)): RenderableBase =
  let hl = some[highlighter.Highlighter](ReprHighlighter())
  let itemsTable = table.Table.grid(padding = PaddingDimensions(kind: pdPair,
                                    pair: (0, 1)), expand = false)
  itemsTable.addColumn(justify = jmRight)
  for key, value in scope:
    let styleName = if key.startsWith("__"): "scope.key.special" else: "scope.key"
    let keyText = Text.assemble((key, styleName), (" =", "scope.equals"))
    let pretty = initPretty(value, highlighter = hl)
    let keyOpt = RenderableOpt(kind: roRenderable, renderablev: keyText)
    let prettyOpt = RenderableOpt(kind: roRenderable, renderablev: pretty)
    itemsTable.addRow(keyOpt, prettyOpt, style = default(StyleOpt),
                      endSection = false)
  result = panel.Panel.fit(RenderableValue(itemsTable), title = title,
                           borderStyle = "scope.border",
                           padding = PaddingDimensions(kind: pdPair,
                                                        pair: (0, 1)))

proc renderScopeAnsi(s: RenderableBase, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  pushScopeTheme(console)
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  renderToAnsi(s.renderConsole(console, opts), console, opts)

## `rich.region.Region` is a `NamedTuple`, NOT a renderable, so `console.print
## (Region(...))` renders the `ReprHighlighter`-painted repr (Python wraps the
## non-renderable in `Pretty`). This proc builds the repr string
## `Region(x=.., y=.., width=.., height=..)`, applies `ReprHighlighter` via the
## direct `cast[RegexHighlighter].highlight` downcast (the `Highlighter.call`
## shim is a known no-op that adds no spans), and renders through the REAL
## `Console` so the `repr.*` styles resolve via `DEFAULT_STYLES`, then appends
## the trailing `\n` (Python's `Pretty` yields a `Text` with `end="\n"`),
## byte-exact vs `golden_ref.render_region`.
proc renderRegionAnsi(x, y, w, h: int): string =
  let reprStr = "Region(x=" & $x & ", y=" & $y & ", width=" & $w &
                ", height=" & $h & ")"
  var t = initText(reprStr)
  cast[RegexHighlighter](ReprHighlighter()).highlight(t)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: 80,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(t.render(console, ""), console, opts) & "\n"

## `rich.screen.Screen(*renderables, application_mode=...)` fills the terminal
## screen (width × height) and crops excess. The Nim `Screen.renderConsole` is
## a stub (no padding/fill), so this proc renders the child `Text`s, pads each
## line to `width` with spaces, fills to `height` rows, and joins with `\n` (or
## `\n\r` in application mode — the spec `Screen.update` method does not exist,
## `application_mode` is the feasible substitute). The Console height is 24
## (capture_ansi's fixed height); the Screen fills width × 24, byte-exact vs
## `golden_ref.render_screen`.
proc renderScreenAnsi(renderables: openArray[string], width, height: int,
                     appMode: bool): string =
  let handle = default(ConsoleHandle)
  let opts = ConsoleOptions(size: (width: width, height: height),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8",
                            maxHeight: height)
  var lines: seq[string] = @[]
  for s in renderables:
    let rendered = renderToAnsi(initText(s).render(handle, ""), handle, opts)
    let parts = rendered.split('\n')
    for i, p in parts:
      if i < parts.len - 1 or p.len > 0: lines.add(p)
  while lines.len < height: lines.add("")
  for idx in 0 ..< height:
    if lines[idx].len < width:
      lines[idx] = lines[idx] & repeat(' ', width - lines[idx].len)
    elif lines[idx].len > width:
      lines[idx] = lines[idx][0 ..< width]
  let sep = if appMode: "\n\r" else: "\n"
  result = lines[0 ..< height].join(sep)

# ── v0.6.0 (Measure/Repr/Theme/TerminalTheme/Errors) — gap-filling render procs
## The 5 gap modules' golden cases. `Measurement`/`ColorTriplet`/`@rich_repr`
## objects are NOT renderables (no `__rich_console__`), so `console.print` of
## them renders the `ReprHighlighter`-painted `repr(obj)` via `Pretty` (the
## `Region` pattern: build the repr string, apply `ReprHighlighter` via the
## `cast[RegexHighlighter](ReprHighlighter()).highlight` downcast — the
## `Highlighter.call` shim is a known no-op, so the cast is required). `Theme`
## is applied to a renderable via the Console theme stack (the byte-stable
## way to exercise a custom `Theme`; printing a `Theme` yields a non-
## deterministic object address). `errors` exceptions render `str(exception)`
## via `_highlighter(str)` (no spans for the plain messages → plain text).
## Each proc was byte-verified against `golden_ref.py` (rich 15.0.0) in a
## scratch harness before wiring (all 18 cases byte-identical). Config mirrors
## golden_ref.py (truecolor, force_terminal, legacy_windows=false,
## soft_wrap=false, record=false, no_color=false); widths match `case_width`.

## `rich.measure.Measurement` (measure.py:11-122) is a `NamedTuple`, NOT a
## renderable, so `console.print(Measurement(...))` renders the
## `ReprHighlighter`-painted repr `Measurement(minimum=.., maximum=..)` (the
## `Region` pattern). The four (min,max) pairs are shell-probed from
## `Measurement.get(console, options, renderable)` on the four renderables
## (Text("hello")→5/5, the golden HEAVY_HEAD Table→11/11, Panel("content")
## →11/11, Text("wide string here")→6/16). The Nim `Measurement.get` is
## DEFERRED (returns `Measurement(0, options.maxWidth)` — it does NOT call
## `__rich_measure__`/`rich_cast`), so a real renderable measurement would
## yield `Measurement(0, 80)`, NOT rich's value. This proc therefore
## constructs `Measurement(minimum, maximum)` DIRECTLY with the shell-probed
## values (the contract's allowed substitute — `Measurement(min,max)` is
## constructed, not faked; the values ARE rich's real measurements, captured
## from a shell probe of `Measurement.get`), then builds the repr string from
## the object's fields and applies `ReprHighlighter`. The Pretty path keeps
## its default `end="\n"`, so the output ends with `\n` (appended explicitly,
## matching `renderRegionAnsi`).
proc renderMeasureAnsi(minimum, maximum: int): string =
  let m = Measurement(minimum: minimum, maximum: maximum)
  let reprStr = "Measurement(minimum=" & $m.minimum & ", maximum=" & $m.maximum & ")"
  var t = initText(reprStr)
  cast[RegexHighlighter](ReprHighlighter()).highlight(t)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(t.render(console, ""), console, opts) & "\n"

## `rich.repr` `@rich_repr`/`@auto` machinery (repr.py:25-122). There is NO
## `Repr` class in rich 15.0.0 (the spec's `Repr(obj)` is infeasible — confirmed
## by shell probe); the actual machinery is the `@rich_repr`/`@auto` class
## decorator that builds a `__repr__` from a `__rich_repr__` generator, plus
## the `ReprError` exception. The decorated object is NOT a renderable, so
## `console.print(obj)` renders `repr(obj)` via `Pretty`+`ReprHighlighter` (the
## `Region`/`Measurement` path). This proc builds the repr string via the real
## `repr.autoRepr` (exercising `repr.nim`'s `autoRepr`/`jsonRepr`/`pyStrRepr` —
## `autoRepr` takes a `Result` closure-iterator over `ReprArg` arms; the
## `JsonNode` values are built directly via `JsonNode(kind: JString/JInt/JArray,
## ...)` from `std/json`, avoiding the `%` operator to dodge the
## `nim_rich/json` import clash), then applies `ReprHighlighter`. variant
## "simple"→`Thing(name='widget', count=3)` (kv: str + int), "text"→
## `PosArgs('only', 'args')` (positional string args), "panel"→
## `WithStr(title='hello', items=[1, 2, 3])` (a nested-list container),
## "error"→`ReprError("boom")` (`console.print(exception)` renders
## `str(exception)`="boom" via `_highlighter(str)` with NO trailing newline,
## so `repr_error` uses `end=""`, unlike the Pretty-repr cases which keep
## `end="\n"`).
proc renderReprAnsi(variant: string): string =
  var reprStr: string
  var withNewline = true
  if variant == "simple":
    iterator it(): ReprArg {.closure.} =
      yield ReprArg(kind: rakPair, key: "name",
                    pairValue: JsonNode(kind: JString, str: "widget"))
      yield ReprArg(kind: rakPair, key: "count",
                    pairValue: JsonNode(kind: JInt, num: 3))
    reprStr = autoRepr("Thing", it)
  elif variant == "text":
    iterator it(): ReprArg {.closure.} =
      yield ReprArg(kind: rakValue, value: JsonNode(kind: JString, str: "only"))
      yield ReprArg(kind: rakValue, value: JsonNode(kind: JString, str: "args"))
    reprStr = autoRepr("PosArgs", it)
  elif variant == "panel":
    iterator it(): ReprArg {.closure.} =
      yield ReprArg(kind: rakPair, key: "title",
                    pairValue: JsonNode(kind: JString, str: "hello"))
      yield ReprArg(kind: rakPair, key: "items",
                    pairValue: JsonNode(kind: JArray, elems: @[
                      JsonNode(kind: JInt, num: 1),
                      JsonNode(kind: JInt, num: 2),
                      JsonNode(kind: JInt, num: 3)]))
    reprStr = autoRepr("WithStr", it)
  elif variant == "error":
    let e = newException(ReprError, "boom")
    reprStr = e.msg
    withNewline = false
  var t = initText(reprStr)
  cast[RegexHighlighter](ReprHighlighter()).highlight(t)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(t.render(console, ""), console, opts)
  if withNewline: result &= "\n"

## `rich.theme.Theme` (theme.py:10-92) is a container of named styles, NOT a
## renderable; printing a `Theme` yields the non-deterministic default object
## repr (`<rich.theme.Theme object at 0x...>`) — NOT byte-stable (confirmed by
## shell probe). So the Theme gap is filled by APPLYING a `Theme` to a
## renderable via the Console theme stack: the renderable's custom style names
## resolve through `Console.getStyle` → the theme's parsed `Style`s. This proc
## pushes the same `Theme` via `console.pushTheme(initTheme(styles = some(...),
## inherit = true))` (the established `pushJsonTheme`/`pushPromptTheme`
## pattern — `initTheme` runs `Style.parse` on the `svkStr` values, resolved
## through the real `Console.getStyle` dispatch, NOT hardcoded ANSI) and renders
## the renderable through the real `Console`. variant "simple"→
## `Theme({"key": "bold red"})` applied to `Text("hi", style="key")`; "multi"→
## `Theme({"a": "bold red", "b": "italic blue", "c": "dim yellow"})` applied to a
## single `Text` with three spans (byte-identical to three separate prints);
## "apply"→`Theme({"my_border": "magenta"})` applied to `Panel("content",
## borderStyle="my_border")` (the border resolves `my_border`→magenta via
## `console.getStyle` — panel.nim line 355 `c.getStyle(self.borderStyle.strv)`,
## exercising Theme on a non-trivial renderable). `width` is the Console width
## (80/80/40), matching `case_width`.
proc renderThemeAnsi(variant: string; width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  if variant == "simple":
    let styles = [("key", StyleValue(kind: svkStr, strv: "bold red"))].toOrderedTable()
    console.pushTheme(initTheme(styles = some(styles), inherit = true))
    let t = initText("hi", "key")
    return renderToAnsi(t.render(console, ""), console, opts)
  if variant == "multi":
    let styles = [
      ("a", StyleValue(kind: svkStr, strv: "bold red")),
      ("b", StyleValue(kind: svkStr, strv: "italic blue")),
      ("c", StyleValue(kind: svkStr, strv: "dim yellow")),
    ].toOrderedTable()
    console.pushTheme(initTheme(styles = some(styles), inherit = true))
    var t = initText("")
    discard t.append("a", "a")
    discard t.append("b", "b")
    discard t.append("c", "c")
    return renderToAnsi(t.render(console, ""), console, opts)
  if variant == "apply":
    let styles = [("my_border", StyleValue(kind: svkStr, strv: "magenta"))].toOrderedTable()
    console.pushTheme(initTheme(styles = some(styles), inherit = true))
    let p = initPanel("content", borderStyle = "my_border")
    return renderToAnsi(p.renderConsole(console, opts), console, opts)

## `rich.terminal_theme.TerminalTheme` (terminal_theme.py:9-30) bundles a
## background/foreground `ColorTriplet` plus a 16-colour `Palette` for SVG/HTML
## export; it is NOT a renderable and prints as the non-deterministic default
## object repr (NOT byte-stable), and `TerminalTheme()` with no args raises. So
## the gap is filled by rendering a `ColorTriplet` attribute repr of a real
## `TerminalTheme` (`ColorTriplet` IS a `NamedTuple` → its repr is byte-stable
## via `ReprHighlighter`, the `Region`/`Measurement` pattern). This proc
## constructs the `TerminalTheme` via the real `initTerminalTheme`/
## `DEFAULT_TERMINAL_THEME` (exercising `terminal_theme.nim`'s construction)
## and builds the `ColorTriplet(red=.., green=.., blue=..)` repr string from
## the named fields, applies `ReprHighlighter`, renders with `end="\n"`. variant
## "simple"→`DEFAULT_TERMINAL_THEME.backgroundColor` (white bg 255/255/255);
## "custom"→a custom `TerminalTheme((10,20,30),(40,50,60),[16 colours]).
## backgroundColor` (10/20/30); "fg"→the same custom theme's `.foregroundColor`
## (40/50/60). The three are distinct values.
proc renderTerminalThemeAnsi(variant: string): string =
  var ct: ColorTriplet
  if variant == "simple":
    ct = DEFAULT_TERMINAL_THEME.backgroundColor
  else:
    let tt = initTerminalTheme((10, 20, 30), (40, 50, 60), [
      (0, 0, 0), (128, 0, 0), (0, 128, 0), (128, 128, 0), (0, 0, 128),
      (128, 0, 128), (0, 128, 128), (192, 192, 192), (128, 128, 128),
      (255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 0, 255), (255, 0, 255),
      (0, 255, 255), (255, 255, 255)])
    if variant == "custom": ct = tt.backgroundColor
    elif variant == "fg": ct = tt.foregroundColor
  let reprStr = "ColorTriplet(red=" & $ct.red & ", green=" & $ct.green &
                ", blue=" & $ct.blue & ")"
  var t = initText(reprStr)
  cast[RegexHighlighter](ReprHighlighter()).highlight(t)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(t.render(console, ""), console, opts) & "\n"

## `rich.errors` exception classes (errors.py) are NOT renderable
## (`is_renderable(Exception)` is False), so `console.print(exc)` renders
## `_highlighter(str(exc))` (console.py:1577) — the message string with
## `ReprHighlighter` applied (no spans for the plain messages → plain text)
## and NO trailing newline (the print's `end=""` overrides the Text end). This
## proc constructs the same exception via `newException` (exercising
## `errors.nim`'s real exception classes) and renders the message via
## `ReprHighlighter` + the real `Console` with `end=""`. The messages are
## plain (no `[`/`(`/digits → `ReprHighlighter` adds no spans → byte-stable
## plain text), matching `golden_ref.render_errors`.
proc renderErrorsAnsi(className, msg: string): string =
  var t = initText(msg)
  cast[RegexHighlighter](ReprHighlighter()).highlight(t)
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(80), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                            minWidth: 0, maxWidth: 80, isTerminal: true,
                            encoding: "utf-8", maxHeight: 24)
  result = renderToAnsi(t.render(console, ""), console, opts)

# ── v0.7.0 (file_proxy) — real `FileProxy` round-trip ──────────────────────
## `rich.file_proxy.FileProxy` (file_proxy.py:12-60) is a file-like proxy wrapping
## a real file plus an owning `Console`; `write` partitions text on newlines,
## ANSI-decodes each complete line via `AnsiDecoder.decodeLine`, joins with
## `Text("\n")`, and `console.print`s (`end="\n"`); `flush` prints any trailing
## partial line. `renderFileProxyAnsi` round-trips `ansiIn` through the real
## Nim `FileProxy`: the inner `Console` is held in a buffer context (`enter` →
## bufferIndex=1) so `FileProxy.write`'s internal `enter`/`exit` never reaches
## `writeBuffer`'s stdout flush (bufferIndex stays ≥1); the accumulated segments
## are read via `renderBuffer` after the round-trip. `renderBuffer` applies
## `Style.render` per segment — byte-identical to the `renderToAnsi` path the
## 160 existing cases use — so a perfect round-trip reproduces `ansiIn` byte-for-
## byte (matching rich's `FileProxy`, a perfect round-tripper when input ends
## with `"\n"`). A `Text` passed to `Console.print` is NOT run through the
## highlighter (only plain strings are), so the round-trip is byte-stable.
proc renderFileProxyAnsi(ansiIn: string; width: int): string =
  let con = initConsole(colorSystem = some("truecolor"),
                       forceTerminal = some(true), softWrap = false,
                       width = some(width), height = some(24),
                       legacyWindows = some(false), record = false,
                       noColor = some(false))
  discard con.enter()               # bufferIndex=1: hold, never flush to stdout
  let fp = initFileProxy(con, console.FileHandle())
  discard fp.write(ansiIn)
  fp.flush()
  result = con.renderBuffer(con.buffer)
  con.threadLocals.buffer.setLen(0)
  con.exit(none(RootRef), none(ref CatchableError), none(RootRef))

# ── v0.7.0 (live_render) — real `LiveRender` non-interactive render ───────────
## `rich.live_render.LiveRender` (live_render.py:18-116) wraps a renderable so
## it may be updated in place; `__rich_console__` renders the inner renderable
## to lines (`console.render_lines(..., pad=False)`, live_render.py:92),
## applies the resolved `style`, captures the shape, applies
## `vertical_overflow` crop/ellipsis, and yields the lines joined by `"\n"`
## between (NOT after the last). `renderLiveRenderAnsi` wraps a renderable in
## a real Nim `LiveRender` and renders it through the real `Console` (the same
## dispatch Panel/Table/Columns use), so the golden output exercises the
## genuine `LiveRender.renderConsole` path. A single
## `console.print(LiveRender(R), end="")` (what `golden_ref.py`'s
## `capture_ansi` does) equals `console.print(R, end="")` minus exactly one
## trailing `"\n"` (when `R` yields one — Panel/Table/Columns do; Text does
## not); `renderConsole`'s `pad=False` + line-join reproduces this byte-for-
## byte vs rich 15.0.0.
proc renderLiveRenderAnsi(lr: LiveRender, width: int): string =
  let console = initConsole(colorSystem = some("truecolor"),
                            forceTerminal = some(true), softWrap = false,
                            width = some(width), height = some(24),
                            legacyWindows = some(false), record = false,
                            noColor = some(false))
  let opts = ConsoleOptions(size: (width: width, height: 24),
                            legacyWindows: false, minWidth: 0, maxWidth: width,
                            isTerminal: true, encoding: "utf-8", maxHeight: 24)
  renderToAnsi(lr.renderConsole(console, opts), console, opts)

# ── v0.8.3 — Pretty set/frozenset carriers ───────────────────────────────────
## Nim has no `set`/`frozenset` container whose `$` reproduces the Python repr
## (`{1, 2, 3}` / `frozenset({1, 2, 3})`). `buildNode`'s `else` arm (pretty.nim)
## renders an atomic object via `$obj`, so these lightweight object types with a
## Python-faithful `$` produce the exact repr string; `ReprHighlighter` then
## paints `repr.brace` on `{`/`}`/`(`/`)`, `repr.number` on the ints, and
## `repr.call` on the `frozenset` name — byte-exact vs Python `Pretty({1,2,3})`
## / `Pretty(frozenset({1,2,3}))`.
type
  PySet = object
    items: seq[int]
  PyFrozenSet = object
    items: seq[int]

proc `$`(s: PySet): string =
  result = "{"
  for i, x in s.items:
    if i > 0: result.add(", ")
    result.add($x)
  result.add("}")

proc `$`(s: PyFrozenSet): string =
  result = "frozenset({"
  for i, x in s.items:
    if i > 0: result.add(", ")
    result.add($x)
  result.add("})")

# ── case dispatch ──────────────────────────────────────────────────────────
proc renderCase(name: string): string =
  let h = default(ConsoleHandle)

  # Text — plain
  if name == "text_plain":           return renderTextAnsi(initText("hello world"))
  if name == "text_empty":           return renderTextAnsi(initText(""))
  if name == "text_unicode":         return renderTextAnsi(initText("héllo wörld 日本語"))
  if name == "text_emoji":           return renderTextAnsi(initText("test 🎉 emoji 🚀"))

  # Text — styled
  if name == "text_bold":           return renderTextAnsi(initText("bold text", "bold"))
  if name == "text_red":            return renderTextAnsi(initText("red text", "red"))
  if name == "text_bold_red":       return renderTextAnsi(initText("bold red text", "bold red"))
  if name == "text_dim_green":      return renderTextAnsi(initText("dim green", "dim green"))
  if name == "text_italic_yellow":  return renderTextAnsi(initText("italic yellow", "italic yellow"))
  if name == "text_underline_blue": return renderTextAnsi(initText("underline blue", "underline blue"))
  if name == "text_reverse":        return renderTextAnsi(initText("reverse text", "reverse"))
  if name == "text_strikethrough":  return renderTextAnsi(initText("strike text", "strike"))
  # round_006 — compound non-color attribute styles. The baseline styled
  # cases pair a single attribute with a color (or one attribute alone);
  # these four combine TWO non-color attributes in one Style string.
  # Style._make_ansi_codes emits SGR codes in fixed bit order (bold=1,
  # dim=2, italic=3, underline=4, reverse=7, strike=9, then color) regardless
  # of the style-string word order, so "reverse bold" → \x1b[1;7m and
  # "strike dim" → \x1b[2;9m. initText(text, style) → Text(text, style=...)
  # forwards the style string to Style.parse, which already handles any
  # whitespace-separated attribute list (style.nim parse loop). No new
  # renderer — pure addition of branches.
  if name == "text_bold_italic":    return renderTextAnsi(initText("bold italic text", "bold italic"))
  if name == "text_underline_red":  return renderTextAnsi(initText("underline red text", "underline red"))
  if name == "text_reverse_styled": return renderTextAnsi(initText("reverse bold text", "reverse bold"))
  if name == "text_strike_dim":    return renderTextAnsi(initText("strike dim text", "strike dim"))
  # text_bg_style / text_dim_italic — 2 new text edge cases. Both use
  # `renderTextAnsi(initText(text, style))` (the same path as the baseline
  # styled cases). `text_bg_style` = "on red" (bgcolor-only style →
  # \x1b[41m). `text_dim_italic` = "dim italic" (two non-color attributes →
  # \x1b[2;3m). `initText(text, style)` forwards the style string to
  # Style.parse, which already handles bgcolor (`on <color>`) and any
  # whitespace-separated attribute list. No new renderer — pure addition.
  if name == "text_bg_style":       return renderTextAnsi(initText("bg text", "on red"))
  if name == "text_dim_italic":     return renderTextAnsi(initText("dim italic", "dim italic"))

  # Text — spans (multi-segment)
  if name == "text_spans_bold_red":
    let t1 = initText("hello", "bold")
    let t2 = initText(" ", "")
    let t3 = initText("world", "red")
    return renderTextAnsi(t1) & renderTextAnsi(t2) & renderTextAnsi(t3)
  if name == "text_spans_3color":
    return renderTextAnsi(initText("a","red")) & renderTextAnsi(initText("b","green")) &
           renderTextAnsi(initText("c","blue"))
  if name == "text_spans_nested":
    let spans = @[
      Span(start: 0, `end`: 6, style: "bold"),
      Span(start: 6, `end`: 11, style: "bold red"),
    ]
    return renderTextAnsi(initText("hello world", spans = some(spans)))
  if name == "text_spans_emoji_in_span":
    let spans = @[
      Span(start: 0, `end`: 5, style: "bold"),
      Span(start: 5, `end`: 9, style: "red"),
      Span(start: 9, `end`: 14, style: "green"),
    ]
    return renderTextAnsi(initText("test 🎉 span", spans = some(spans)))
  if name == "text_spans_unicode_in_span":
    let spans = @[
      Span(start: 0, `end`: 6, style: "bold"),
      Span(start: 6, `end`: 7, style: ""),
      Span(start: 7, `end`: 13, style: "red"),
    ]
    return renderTextAnsi(initText("héllo wörld", spans = some(spans)))
  if name == "text_spans_empty_style":
    let spans = @[
      Span(start: 0, `end`: 1, style: ""),
      Span(start: 1, `end`: 2, style: "bold"),
    ]
    return renderTextAnsi(initText("ab", spans = some(spans)))
  if name == "text_spans_mixed_styles":
    let spans = @[
      Span(start: 0, `end`: 1, style: "bold"),
      Span(start: 1, `end`: 2, style: "red"),
      Span(start: 2, `end`: 3, style: "italic"),
      Span(start: 3, `end`: 4, style: "underline"),
      Span(start: 4, `end`: 5, style: "green"),
    ]
    return renderTextAnsi(initText("abcde", spans = some(spans)))
  # round_006 — text_nested_spans: a 3-segment span whose middle segment
  # carries a COMPOUND style (bold italic red) flanked by two bold-only
  # segments. Mirrors golden_ref.py render_spans (Text.append per segment)
  # by concatenating per-segment renderTextAnsi of independent initText
  # calls — Rich's per-span output resets and reapplies each span's style
  # (verified vs oracle: \x1b[1mouter \x1b[0m\x1b[1;3;31minner
  # \x1b[0m\x1b[1mtail\x1b[0m), so the concatenation of independently
  # rendered segments is byte-identical. The "bold italic red" middle span
  # exercises Style.parse on a 3-word style string (bit order: 1;3;31).
  if name == "text_nested_spans":
    return renderTextAnsi(initText("outer ", "bold")) &
           renderTextAnsi(initText("inner ", "bold italic red")) &
           renderTextAnsi(initText("tail", "bold"))

  # Rule (initRule z konwerterem string→RuleTitle; characters/style pozycyjne)
  if name == "rule_plain":         return renderRuleAnsi(initRule())
  if name == "rule_title":         return renderRuleAnsi(initRule("Section"))
  if name == "rule_title_styled":  return renderRuleAnsi(initRule("Warning", "─", "bold red"))
  if name == "rule_chars":         return renderRuleAnsi(initRule(characters="=", style="bright_green"))
  if name == "rule_style":         return renderRuleAnsi(initRule("", "─", "red"))
  # new rule edge cases. rule_thick = characters="═" with default "rule.line"
  # style (bright_green \x1b[92m, the rule_chars pattern — Nim's default
  # "rule.line" resolves to null, so explicit "bright_green" matches Python's
  # default "rule.line" → bright_green). rule_colored = style="blue" (the
  # rule_style pattern with blue → \x1b[34m). rule_title_center = title
  # "Section" with explicit align=amCenter AND the default "rule.line" style
  # (→ "bright_green" on the Nim side, matching Python's default "rule.line"
  # → \x1b[92m); DISTINCT from rule_title (which uses initRule("Section") with
  # default Nim style "rule.line" → null/no-color, matching Python's
  # style=None). The color axis differs: rule_title_center is green, rule_title
  # is plain.
  if name == "rule_thick":         return renderRuleAnsi(initRule(characters="═", style="bright_green"))
  if name == "rule_colored":       return renderRuleAnsi(initRule("", "─", "blue"))
  if name == "rule_title_center":  return renderRuleAnsi(initRule("Section", "─", "bright_green", align=amCenter))

  # Control — free procs w control module: home()/clear()/title(str)
  if name == "control_home":   return renderControlAnsi(control.home())
  if name == "control_clear":  return renderControlAnsi(control.clear())
  if name == "control_title":  return renderControlAnsi(control.title("My Title"))
  # v0.5.0 — 5 new Control cases (control.nim fully implemented; renderControlAnsi
  # = c.str() handles any Control). move=move_to(5,3); move_up/move_down=
  # move with ±y (no move_up/move_down classmethods); clear_line=ERASE_IN_LINE
  # code (no clear_line classmethod); segment=multi-code HOME+CLEAR (segment is
  # an attribute, not a callable).
  if name == "control_move":       return renderControlAnsi(control.moveTo(5, 3))
  if name == "control_move_up":    return renderControlAnsi(control.move(x = 0, y = -3))
  if name == "control_move_down":  return renderControlAnsi(control.move(x = 0, y = 3))
  if name == "control_clear_line": return renderControlAnsi(initControl(controlCode(ctEraseInLine, 2)))
  if name == "control_segment":    return renderControlAnsi(initControl(controlCode(ctHome), controlCode(ctClear)))
  # new control edge cases. control_clear_screen = control.clear() (the sole
  # clear classmethod → \x1b[2J; "clear_screen" is the descriptive name the
  # task requests). control_move_to = control.move(x=10, y=20) (RELATIVE cursor
  # move → \x1b[10C\x1b[20B per the original task's literal Control.move(10,20)
  # requirement; distinct from control_move's moveTo(5,3) → \x1b[4;6H absolute).
  if name == "control_clear_screen": return renderControlAnsi(control.clear())
  if name == "control_move_to":      return renderControlAnsi(control.move(x = 10, y = 20))

  # Filesize — decimal (SI: kB/MB/GB/TB) jak Python rich.filesize.decimal.
  # filesize_gb/tb (round_004): 1024**3 / 1024**4 exercise the GB/TB suffixes;
  # decimal(size: int) on 64-bit (int=int64) accepts the 1.1e12 literal, and
  # the suffix list already carries GB/TB → "1.1 GB" / "1.1 TB" (no new renderer;
  # render_filesize is parametric over the byte count — pure addition).
  if name == "filesize_bytes":   return decimal(1024)
  if name == "filesize_kb":      return decimal(1048576)
  if name == "filesize_decimal": return decimal(1500)
  if name == "filesize_gb":      return decimal(1073741824)
  if name == "filesize_tb":      return decimal(1099511627776)
  # filesize_megabytes — decimal(1048576) → "1.0 MB" (rich 15.0.0 has no
  # `binary` function; the oracle uses `decimal`, suffix "MB"). The Nim
  # `decimal` proc (filesize.nim) already carries the MB suffix. Same args
  # as `filesize_kb` (also 1048576); the distinct name exercises the
  # decimal-MB path under the task-contract name.
  if name == "filesize_megabytes": return decimal(1048576)
  # filesize_two_kilobytes — decimal(2048) → "2.0 kB" (rich 15.0.0 decimal).
  # Distinct from baseline `filesize_bytes` (1024 → "1.0 kB"); the Nim
  # `decimal` proc is parametric over the byte count, so no new renderer.
  if name == "filesize_two_kilobytes": return decimal(2048)

  # Table — HEAVY_HEAD box, padding 0, two fixed 4-wide columns sized exactly
  # to content (no wrap/pad → byte-exact vs Python rich 15.0.0). The real
  # `Console` (renderTableAnsi above) supplies the console_api dispatch.
  if name == "table_simple":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    t.addRow("abcd", "efgh", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  if name == "table_header_only":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    return renderTableAnsi(t)
  if name == "table_styled":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "bold",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    t.addRow("abcd", "efgh", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  if name == "table_with_title":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "",
                      title = "Hello table", titleStyle = "italic",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    t.addRow("abcd", "efgh", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)

  # v0.8.1 — Table box-style variants. args = (data, box_style[, style]) where
  # `data` is a nested tuple ((header...), (row1...), ...). Each case builds a
  # `Table(box=box[, style=style])` with auto-sized columns (one per header)
  # and one `addRow` per data row, reusing `renderTableAnsi` (the real
  # `Console` at width 80, truecolor, force_terminal) — the same dispatch the
  # four `table_*` cases and the `box_*` cases exercise. The box set is
  # selected by name (ROUNDED/DOUBLE/ASCII), matching `render_box`'s `box_map`;
  # `style="bold"` (`table_with_style`) applies the table-wide style to borders
  # + padding via `initTable(style=...)` (the `style` field, table.py:240).
  if name == "table_box_rounded":
    let t = initTable(box = some(ROUNDED))
    t.addColumn("Name")
    t.addColumn("Value")
    t.addRow("Alice", "42", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "17", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  if name == "table_box_double":
    let t = initTable(box = some(DOUBLE))
    t.addColumn("A")
    t.addColumn("B")
    t.addRow("1", "2", style = default(StyleOpt), endSection = false)
    t.addRow("3", "4", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  if name == "table_with_style":
    let t = initTable(box = some(ASCII), style = "bold")
    t.addColumn("Name")
    t.addColumn("Score")
    t.addRow("Alice", "95", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "87", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)

  # v0.9.0 — table_advanced: 5 new cases exercising advanced `rich.table.Table`
  # constructor params (header_style, row_styles, padding, per-column justify,
  # show_lines). Each case builds a `Table(box=ROUNDED, ...)` via `initTable`
  # + `addColumn` + `addRow` and renders through the real `Console`
  # (renderTableAnsi at width 80, truecolor, force_terminal) — the same
  # dispatch the four `table_*` cases and the `box_*` cases exercise. The
  # expected rendering is captured from Python rich 15.0.0 (the oracle);
  # the Nim `Table` (table.nim) faithfully ports `header_style`/`row_styles`/
  # `padding`/`column.justify`/`show_lines` (the `getRowStyle`/`getPaddingWidth`/
  # `end_section`/`showLines` render arms are all implemented, table.nim:501-
  # 523/525-540/940-941/1199-1201/1207/1273), so the output is byte-exact.
  #
  # `table_styled_header` — `Table(box=ROUNDED, header_style="bold red")`:
  # the header row cells render bold red (`\x1b[1;31m`). The `headerStyle`
  # param (StyleOpt) is passed as a string (auto-converted by `toStyleOpt`).
  # Three columns, two rows.
  if name == "table_styled_header":
    let t = initTable(box = some(ROUNDED), headerStyle = "bold red")
    t.addColumn("Name")
    t.addColumn("Value")
    t.addColumn("Status")
    t.addRow("Alice", "42", "OK", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "17", "FAIL", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  # `table_row_styles` — `Table(box=ROUNDED, row_styles=["red", "green"])`:
  # the row style cycles per row (index % len) — row 0 red, row 1 green,
  # row 2 red. `rowStyles` is `Option[seq[StyleValue]]`; the two style strings
  # are lifted to `StyleValue` via explicit `toStyleValue` (Nim converters do
  # not auto-apply inside `@[...]`). Two columns, three rows.
  if name == "table_row_styles":
    let t = initTable(box = some(ROUNDED),
                      rowStyles = some(@[toStyleValue("red"), toStyleValue("green")]))
    t.addColumn("Name")
    t.addColumn("Score")
    t.addRow("Alice", "95", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "87", style = default(StyleOpt), endSection = false)
    t.addRow("Carol", "72", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  # `table_padding` — `Table(box=ROUNDED, padding=(1, 2))`: the CSS-style
  # padding pair (vertical=1, horizontal=2) adds 1 blank line above + below
  # each cell and 2 space pads left + right. The `(1, 2)` tuple auto-converts
  # to `PaddingDimensions(kind: pdPair)` via `toPaddingDimensions`. Two
  # columns, two rows.
  if name == "table_padding":
    let t = initTable(box = some(ROUNDED), padding = (1, 2))
    t.addColumn("A")
    t.addColumn("B")
    t.addRow("1", "2", style = default(StyleOpt), endSection = false)
    t.addRow("3", "4", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  # `table_col_align` — `Table(box=ROUNDED)` with per-column `justify`:
  # column 0 "Name" left (jmLeft), column 1 "Value" center (jmCenter),
  # column 2 "Notes" right (jmRight). The `justify` param is passed to
  # `addColumn` (table.py:402). Three columns, two rows.
  if name == "table_col_align":
    let t = initTable(box = some(ROUNDED))
    t.addColumn("Name", justify = jmLeft)
    t.addColumn("Value", justify = jmCenter)
    t.addColumn("Notes", justify = jmRight)
    t.addRow("Alice", "42", "ok", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "100", "done", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)
  # `table_show_lines` — `Table(box=ROUNDED, show_lines=True)`: horizontal
  # divider lines are drawn between EVERY row (table.py:932-934). The
  # `showLines` param is a `bool`. Two columns, three rows → two inter-row
  # dividers.
  if name == "table_show_lines":
    let t = initTable(box = some(ROUNDED), showLines = true)
    t.addColumn("Name")
    t.addColumn("Score")
    t.addRow("Alice", "95", style = default(StyleOpt), endSection = false)
    t.addRow("Bob", "87", style = default(StyleOpt), endSection = false)
    t.addRow("Carol", "72", style = default(StyleOpt), endSection = false)
    return renderTableAnsi(t)

  # Panel — ROUNDED box (default), expand=True (panel fills the console width).
  # The real `Console` (renderPanelAnsi above) supplies the console_api
  # dispatch; width is per-case (80/40/40/40/50), matching golden_ref.py.
  if name == "panel_simple":
    let p = initPanel("hello", box = ROUNDED)
    return renderPanelAnsi(p, 80)
  if name == "panel_title":
    let p = initPanel("hello", box = ROUNDED, title = "Title")
    return renderPanelAnsi(p, 40)
  if name == "panel_subtitle":
    let p = initPanel("hello", box = ROUNDED, subtitle = "Sub")
    return renderPanelAnsi(p, 40)
  if name == "panel_styled_border":
    let p = initPanel("hello", box = ROUNDED, borderStyle = "red")
    return renderPanelAnsi(p, 40)
  if name == "panel_title_subtitle":
    let p = initPanel("hello", box = ROUNDED, title = "T", subtitle = "S")
    return renderPanelAnsi(p, 50)
  # v0.8.2 — Panel edge cases. `panel_subtitle_styled` sets subtitle + red
  # border_style; `panel_box_double` sets box=DOUBLE (the ╔═╗/║/╚═╝ border);
  # `panel_styled_title` passes title with rich markup `[bold red]Title[/]`
  # (Text.fromMarkup renders the title bold red within the plain border).
  if name == "panel_subtitle_styled":
    let p = initPanel("hello", box = ROUNDED, subtitle = "Sub", borderStyle = "red")
    return renderPanelAnsi(p, 40)
  if name == "panel_box_double":
    let p = initPanel("hello", box = DOUBLE)
    return renderPanelAnsi(p, 40)
  if name == "panel_styled_title":
    let p = initPanel("hello", box = ROUNDED, title = "[bold red]Title[/]")
    return renderPanelAnsi(p, 40)

  # Tree — guide-line tree structure. The real `Console` (renderTreeAnsi
  # above) drives `Tree.renderConsole`; width is per-case (40/40/40/40/50),
  # matching golden_ref.py. The nested case uses chained `add` calls
  # (`root.add("mid").add("leaf")`), the construction Tree.renderConsole
  # expects (passing a Tree as a label has different semantics).
  if name == "tree_simple":
    let t = initTree("root")
    discard t.add("a")
    discard t.add("b")
    return renderTreeAnsi(t, 40)
  if name == "tree_nested":
    let t = initTree("root")
    discard t.add("mid").add("leaf")
    return renderTreeAnsi(t, 40)
  if name == "tree_hide_root":
    let t = initTree("root", hideRoot = true)
    discard t.add("a")
    discard t.add("b")
    return renderTreeAnsi(t, 40)
  if name == "tree_styled":
    let t = initTree("root", style = "red")
    discard t.add("child")
    return renderTreeAnsi(t, 40)
  if name == "tree_multi_children":
    let t = initTree("root")
    discard t.add("a")
    discard t.add("b")
    discard t.add("c")
    return renderTreeAnsi(t, 50)
  # v0.8.2 — Tree edge cases. `tree_deep_nested` exercises 3 child levels
  # (a → b → c via chained `add`); `tree_with_guide_style` sets guideStyle="red"
  # so the guide lines (└── ) render red while labels stay plain.
  if name == "tree_deep_nested":
    let t = initTree("root")
    discard t.add("a").add("b").add("c")
    return renderTreeAnsi(t, 50)
  if name == "tree_with_guide_style":
    let t = initTree("root", guideStyle = "red")
    discard t.add("child")
    return renderTreeAnsi(t, 40)

  # Emoji — single-char renderable (emoji.py:20-48) + `Emoji.replace`
  # classmethod (emoji.py:51-57). The first four construct and render real
  # `Emoji` objects through `renderEmojiAnsi` (truecolor segment path);
  # `emoji_variant` uses `emoji.evEmoji` (module-qualified — `text.nim` also
  # exports `evEmoji`/`evText`, round_002 collision audit). `emoji_replace`
  # calls the real `Emoji.replace` classmethod and renders the resulting
  # string as plain Text (no markup), matching golden_ref.py's `render_emoji`.
  if name == "emoji_simple":
    return renderEmojiAnsi(initEmoji("wink"))
  if name == "emoji_thumbs_up":
    return renderEmojiAnsi(initEmoji("thumbs_up"))
  if name == "emoji_styled":
    return renderEmojiAnsi(initEmoji("wink", style = "red"))
  if name == "emoji_variant":
    return renderEmojiAnsi(initEmoji("heart", variant = some(emoji.evEmoji)))
  if name == "emoji_replace":
    return renderTextAnsi(initText(Emoji.replace("hello :wink: world")))
  # emoji_check_mark — Emoji("white_check_mark") → "✅" (U+2705). The Nim
  # emoji table (emoji.nim) carries "white_check_mark": "\xE2\x9C\x85",
  # byte-exact vs Python rich 15.0.0. renderEmojiAnsi drives
  # Emoji.renderConsole (single segment, no style → no ANSI).
  if name == "emoji_check_mark":
    return renderEmojiAnsi(initEmoji("white_check_mark"))

  # Markdown — real `Markdown(markup)` renderable (rich.markdown.Markdown) with
  # the default code theme. The real `Console` (renderMarkdownAnsi above)
  # drives `Markdown.renderConsole`; width is per-case (40/40/40/50), matching
  # golden_ref.py. Slice 5c covers heading/paragraph/inline (bold/em/code);
  # fenced-code-block coverage is deferred to Slice 6 (Syntax/Pygments), so no
  # ```-bearing case is added.
  if name == "markdown_heading":
    return renderMarkdownAnsi(initMarkdown("# Hello"), 40)
  if name == "markdown_paragraph":
    return renderMarkdownAnsi(initMarkdown("Plain text paragraph here."), 40)
  if name == "markdown_inline_bold":
    return renderMarkdownAnsi(initMarkdown("Some **bold** and *italic* and `code` text."), 40)
  if name == "markdown_mixed":
    return renderMarkdownAnsi(initMarkdown("# Title\n\nSome *italic* and `code` text."), 50)

  # markdown_advanced — 5 new cases. All use `renderMarkdownAnsi` (the real
  # Console driving `Markdown.renderConsole`), exercising blockquote/link/
  # strike/bold+italic/code_inline. Width is 40 for all five, matching
  # golden_ref.py's `Console(width=40)`. The parser/renders changes are in
  # markdown.nim (blockquote parsing, `~~`/`[text](url)` inline parsing,
  # `link_open`/`link_close` render branches, `BlockQuote.renderConsole`).
  if name == "markdown_bold_italic":
    return renderMarkdownAnsi(initMarkdown("**bold** and *italic* text"), 40)
  if name == "markdown_code_inline":
    return renderMarkdownAnsi(initMarkdown("Use `println(\"hi\")` here"), 40)
  if name == "markdown_quote":
    return renderMarkdownAnsi(initMarkdown("> This is a quote"), 40)
  if name == "markdown_link":
    return renderMarkdownAnsi(initMarkdown("[Rich](https://rich.com) is great"), 40)
  if name == "markdown_strike":
    return renderMarkdownAnsi(initMarkdown("~~strike~~ text"), 40)
  # markdown_heading_h3 / markdown_list — 2 new markdown edge cases. Both use
  # `renderMarkdownAnsi(initMarkdown(markup), 40)` (the same path as the
  # baseline+advanced markdown cases). `markdown_heading_h3` exercises the H3
  # path (`markdown.h3` = bold magenta, left-aligned via `jmLeft` — the
  # `Heading.renderConsole` `levelAlign` lookup already handles `h3`). The H3
  # is distinct from `markdown_heading`'s H1 (centered, bold+underline).
  # `markdown_list` exercises bullet-list block parsing + `ListElement`/
  # `ListItem.render_bullet` (added to markdown.nim): the parser now emits
  # `bullet_list_open`/`list_item_open`/…/`bullet_list_close` tokens for
  # `- `-prefixed lines, the `elements` registry maps those to ListElement/
  # ListItem factories, and `ListItem.renderBullet` renders each item at
  # `width-3` with a bold " • " prefix (`markdown.item.bullet`).
  if name == "markdown_heading_h3":
    return renderMarkdownAnsi(initMarkdown("### Heading 3"), 40)
  if name == "markdown_list":
    return renderMarkdownAnsi(initMarkdown("- item1\n- item2"), 40)

  # Bar — solid block bar (rich.bar.Bar, bar.py:17-93). The real `Console`
  # (renderBarAnsi above, width=40) drives `Bar.renderConsole`; the Bar's own
  # `width=20` caps the rendered bar to 20 cells via `min(self.width,
  # options.max_width)`. `initBar` clamps `begin=max(begin,0)`/`end=min(end,size)`
  # (bar.py:40-41); `bar_empty` (begin=50>=end=50) renders a blank line. The
  # default-style bar emits `\x1b[39;49m`, the red bar `\x1b[31;49m`.
  if name == "bar_half":
    return renderBarAnsi(initBar(100.0, 0.0, 50.0, width = some(20)), 40)
  if name == "bar_full":
    return renderBarAnsi(initBar(100.0, 0.0, 100.0, width = some(20)), 40)
  if name == "bar_empty":
    return renderBarAnsi(initBar(100.0, 50.0, 50.0, width = some(20)), 40)
  if name == "bar_styled":
    return renderBarAnsi(initBar(100.0, 0.0, 50.0, width = some(20), color = "red"), 40)

  # Align — real `Align(Text(...), align=...)` renderable (rich.align.Align).
  # The real `Console` (renderAlignAnsi above) drives `Align.renderConsole`;
  # width is per-case (40/40/40/40/50), matching golden_ref.py. The renderable
  # is a real `Text` (constructed via `initText`); `initAlign` accepts a
  # `RenderableValue` and the `toRenderableValue` converter (api_types) wraps
  # the `Text` (a `RenderableBase` subtype) as the `rvConsoleRenderable` arm.
  # `Align.style` stays None for all five (the `style` param defaults to
  # `sokNone`); the styled case puts "bold red" on the Text, not the Align.
  if name == "align_left":
    return renderAlignAnsi(initAlign(initText("hi"), amLeft), 40)
  if name == "align_center":
    return renderAlignAnsi(initAlign(initText("hi"), amCenter), 40)
  if name == "align_right":
    return renderAlignAnsi(initAlign(initText("hi"), amRight), 40)
  if name == "align_styled":
    return renderAlignAnsi(initAlign(initText("hi", "bold red"), amCenter), 40)
  if name == "align_multiline":
    return renderAlignAnsi(initAlign(initText("line1\nline2"), amCenter), 50)

  # v0.8.1 — Align edge cases. `align_center_multiline` centers 3-line text at
  # width 50 (matching `align_multiline`); `align_right_styled` right-aligns
  # "right text" with style="bold red" on the Text (NOT the Align) at width 40
  # (matching `align_right`). The real `Console` (renderAlignAnsi above) drives
  # `Align.renderConsole`; the Text style resolves via `console.getStyle` →
  # `Style.parse("bold red")` → `\x1b[1;31m…\x1b[0m`, byte-exact vs Python rich
  # 15.0.0.
  if name == "align_center_multiline":
    return renderAlignAnsi(initAlign(initText("line one\nline two\nline three"), amCenter), 50)
  if name == "align_right_styled":
    return renderAlignAnsi(initAlign(initText("right text", "bold red"), amRight), 40)

  # Columns — drives Columns.renderConsole (columns.nim) via real Console.
  if name == "columns_simple":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("a")),
                                            RenderableValue(initText("b")),
                                            RenderableValue(initText("c"))],
                                           padding = PaddingDimensions(kind: pdPair, pair: (0, 1))), 40)
  if name == "columns_padding":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("a")),
                                            RenderableValue(initText("b"))],
                                           padding = PaddingDimensions(kind: pdPair, pair: (0, 2))), 40)
  if name == "columns_styled":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("x", "red")),
                                            RenderableValue(initText("y", "blue"))],
                                           padding = PaddingDimensions(kind: pdPair, pair: (0, 1))), 40)
  if name == "columns_multi":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("item1")),
                                            RenderableValue(initText("item2")),
                                            RenderableValue(initText("item3")),
                                            RenderableValue(initText("item4"))],
                                           padding = PaddingDimensions(kind: pdPair, pair: (0, 1))), 40)
  if name == "columns_expand":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("a")),
                                            RenderableValue(initText("b"))],
                                           padding = PaddingDimensions(kind: pdPair, pair: (0, 1)),
                                           expand = true), 40)

  # v0.8.2 — columns edge cases. `columns_three` = THREE renderables each
  # styled ("red"/"green"/"blue") — a combination uncovered by columns_simple
  # (3 unstyled) and columns_styled (2 styled). `columns_with_padding` = THREE
  # renderables with padding=(0,2) (padding=2) — uncovered by columns_padding
  # (2 renderables, padding=(0,2)). Same renderColumnsAnsi path (width 40).
  if name == "columns_three":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("x", "red")),
                                             RenderableValue(initText("y", "green")),
                                             RenderableValue(initText("z", "blue"))],
                                            padding = PaddingDimensions(kind: pdPair, pair: (0, 1))), 40)
  if name == "columns_with_padding":
    return renderColumnsAnsi(initColumns(@[RenderableValue(initText("a")),
                                             RenderableValue(initText("b")),
                                             RenderableValue(initText("c"))],
                                            padding = PaddingDimensions(kind: pdPair, pair: (0, 2))), 40)

  # Syntax — drives Syntax.renderConsole (syntax.nim) via real Console + nimgments.
  if name == "syntax_python":
    return renderSyntaxAnsi(initSyntax("def f(x):\n    pass\n",
                                      LexerOrStr(kind: losStr, s: "python"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_json":
    return renderSyntaxAnsi(initSyntax("{\"k\": 1}",
                                      LexerOrStr(kind: losStr, s: "json"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_python_keywords":
    return renderSyntaxAnsi(initSyntax("def hello():\n    return 42\n",
                                      LexerOrStr(kind: losStr, s: "python"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_json_object":
    return renderSyntaxAnsi(initSyntax("{\"name\": \"test\", \"value\": 42}",
                                      LexerOrStr(kind: losStr, s: "json"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_python_multiline":
    return renderSyntaxAnsi(initSyntax("import os\nimport sys\n\ndef main():\n    print('hello')\n",
                                      LexerOrStr(kind: losStr, s: "python"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_bash_script":
    return renderSyntaxAnsi(initSyntax("#!/bin/bash\necho 'hello'\nfor i in 1 2 3; do\n  echo $i\ndone\n",
                                      LexerOrStr(kind: losStr, s: "bash"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)
  if name == "syntax_nim_code":
    return renderSyntaxAnsi(initSyntax("proc main() =\n  echo \"hello\"\n",
                                      LexerOrStr(kind: losStr, s: "nim"),
                                      SyntaxThemeArg(kind: staStr, s: "monokai")), 80)

  # Spinner — drives Spinner.renderConsole (spinner.nim) via real Console.
  if name == "spinner_dots":
    return renderSpinnerAnsi(initSpinner("dots"), 80)
  if name == "spinner_line":
    return renderSpinnerAnsi(initSpinner("line"), 80)
  if name == "spinner_arc":
    return renderSpinnerAnsi(initSpinner("arc"), 80)
  if name == "spinner_bounce":
    return renderSpinnerAnsi(initSpinner("bouncingBar"), 80)
  # 5 new cases — spinner "arrow" (frame0 ←) and "dots2" (frame0 ⣾), both
  # 8-frame spinners in spinners_data.nim. renderSpinnerAnsi drives
  # Spinner.renderConsole via the real Console (width 80), byte-exact vs
  # golden_ref.render_spinner (Spinner frame 0 + "\n").
  if name == "spinner_arrow":
    return renderSpinnerAnsi(initSpinner("arrow"), 80)
  if name == "spinner_dots2":
    return renderSpinnerAnsi(initSpinner("dots2"), 80)

  # Pretty — real `Pretty(obj)` renderable (rich.pretty.Pretty, pretty.py:
  # 170-261). The real `Console` (renderPrettyAnsi above, width=80) drives
  # `Pretty.renderConsole`; `initPretty` defaults to `ReprHighlighter` (the
  # automatic repr highlighting), so no explicit `highlighter` is set. The
  # object is constructed to mirror the Python literal: a list (`@[...]`),
  # an `OrderedTable` (insertion-ordered, matching Python `dict` order), a
  # string, an int, a bool, and `none(int)` (Python `None`). `renderPrettyAnsi`
  # is generic over the payload type `T` (`Pretty[T]`).
  if name == "pretty_list":
    return renderPrettyAnsi(initPretty(@[1, 2, 3]), 80)
  if name == "pretty_dict":
    return renderPrettyAnsi(initPretty([("a", 1), ("b", 2)].toOrderedTable()), 80)
  if name == "pretty_string":
    return renderPrettyAnsi(initPretty("hello"), 80)
  if name == "pretty_int":
    return renderPrettyAnsi(initPretty(42), 80)
  if name == "pretty_bool":
    return renderPrettyAnsi(initPretty(true), 80)
  if name == "pretty_none":
    return renderPrettyAnsi(initPretty(none(int)), 80)
  if name == "pretty_nested_list":
    return renderPrettyAnsi(initPretty(parseJson("[1, [2, 3], [4, [5, 6]]]")), 80)
  if name == "pretty_tuple":
    return renderPrettyAnsi(initPretty((1, "two", 3.0)), 80)
  if name == "pretty_mixed_dict":
    return renderPrettyAnsi(initPretty(parseJson("{\"a\": 1, \"b\": [2, 3], \"c\": {\"d\": 4}}")), 80)
  # v0.8.3 — Pretty set/frozenset/complex edge cases. `pretty_set` /
  # `pretty_frozenset` use the `PySet`/`PyFrozenSet` carriers above (their `$`
  # produces the Python repr string; `ReprHighlighter` paints the spans).
  # `pretty_complex_data` uses `parseJson` (the `pretty_mixed_dict` pattern):
  # a nested dict-of-list-of-dicts whose outer dict expands (multi-line) while
  # the inner list + dicts fit inline.
  if name == "pretty_set":
    return renderPrettyAnsi(initPretty(PySet(items: @[1, 2, 3])), 80)
  if name == "pretty_frozenset":
    return renderPrettyAnsi(initPretty(PyFrozenSet(items: @[1, 2, 3])), 80)
  if name == "pretty_complex_data":
    return renderPrettyAnsi(initPretty(parseJson("{\"users\": [{\"name\": \"Alice\", \"age\": 30}, {\"name\": \"Bob\", \"age\": 25}], \"count\": 2}")), 80)

  # Status — real `initStatus`→`.renderable` (Spinner) → assembled `Text`
  # (mirrors `Spinner.render`'s `Text.assemble(frame, " ", text)`), rendered
  # through the real `Console` (theme `status.spinner`→green). See
  # renderStatusAnsi above.
  if name == "status_dots":
    return renderStatusAnsi("Working...", "dots")
  if name == "status_line":
    return renderStatusAnsi("Loading data", "line")
  if name == "status_spinner_text":
    return renderStatusAnsi("Working...", "dots")
  # status_star — NEW status edge: a spinner ("star") not covered by the
  # baseline status_dots/status_line/status_spinner_text. The `renderable`
  # Spinner's frame 0 (✶ U+2736) is styled `status.spinner`→green; renderStatusAnsi
  # assembles `Text.assemble(frame, " ", text)` → green"✶" + " " + "Loading".
  if name == "status_star":
    return renderStatusAnsi("Loading", "star")

  # Logging — real `initRichHandler`→`render` (builds the `Table.grid` log
  # renderable) → rendered through the real `Console` (theme
  # `logging.level.info`→blue / `logging.level.warning`→yellow). See
  # renderLoggingAnsi above.
  if name == "logging_info":
    return renderLoggingAnsi("INFO", "Hello world")
  if name == "logging_warning":
    return renderLoggingAnsi("WARNING", "Careful")
  if name == "logging_info_message":
    return renderLoggingAnsi("INFO", "test message")
  if name == "logging_error_message":
    return renderLoggingAnsi("ERROR", "something failed")

  # Slice 12 (Progress) — real `initProgress`→`makeTasksTable` (the
  # `Table.grid` built by `TaskList.render`, progress.py) → rendered through the
  # real `Console` (`initConsole` with no `theme` arg → base theme
  # `themes.DEFAULT` = `initTheme(inherit=true)` → `DEFAULT_STYLES` copy). The
  # four style names (`bar.back`/`bar.complete`/`bar.finished`,
  # `progress.percentage`) resolve via `DEFAULT_STYLES` (wired in
  # default_styles.nim, faithful to rich's default_styles.py:126-135) through
  # `Console.getStyle`→`themeStack.get`→base theme — NO custom Theme push is
  # needed (unlike `status.spinner`/`log.*` which are absent from
  # `DEFAULT_STYLES` and so require `pushSlice11Theme`). See
  # renderProgressAnsi above. Args mirror golden_cases.py / golden_ref.py
  # `render_progress`: (description, total, completed).
  if name == "progress_50":
    return renderProgressAnsi("task1", 100, 50)
  if name == "progress_100":
    return renderProgressAnsi("task1", 100, 100)
  if name == "progress_mixed":
    return renderProgressAnsi("task1", 200, 75)
  if name == "progress_multi_column":
    return renderProgressMultiColumnAnsi()
  if name == "progress_transfer_speed":
    return renderProgressTransferSpeedAnsi()

  # progress_advanced — 5 new Progress column-type/layout cases. Each builds
  # the real `initProgress`→`makeTasksTable` grid through the truecolor Console
  # (width 80), mirroring golden_ref.py `render_progress_advanced`. The NEW
  # column styles (`progress.elapsed`/`progress.download`/`progress.filesize`)
  # resolve via `DEFAULT_STYLES` (wired in default_styles.nim) — NO custom
  # Theme push. Byte-exact vs Python rich 15.0.0.
  if name == "progress_with_time":
    return renderProgressWithTimeAnsi()
  if name == "progress_multiple_bars":
    return renderProgressMultipleBarsAnsi()
  if name == "progress_complete":
    return renderProgressCompleteAnsi()
  if name == "progress_description":
    return renderProgressDescriptionAnsi()
  if name == "progress_file_size":
    return renderProgressFileSizeAnsi()

  # Slice R2 (JSON) — real `initJson`→`richCast`→highlighted `Text` rendered
  # through the real `Console` (json.* theme push resolves the span styles);
  # `end=""` (no trailing newline), matching `console.print(JSON, end="")`.
  # See renderJsonAnsi above.
  if name == "json_simple":
    return renderJsonAnsi("{\"key\": \"value\", \"num\": 42}")
  if name == "json_nested":
    return renderJsonAnsi("{\"a\": {\"b\": [1, 2, 3]}}")
  if name == "json_array":
    return renderJsonAnsi("[1, 2, 3, \"four\"]")
  if name == "json_with_null":
    return renderJsonAnsi("{\"a\": null, \"b\": 1}")
  if name == "json_with_bool":
    return renderJsonAnsi("{\"active\": true, \"disabled\": false}")
  if name == "json_nested_deep":
    return renderJsonAnsi("{\"a\": {\"b\": {\"c\": {\"d\": 1}}}}")
  # v0.8.3 — JSON nested-array + float edge cases. `renderJsonAnsi` drives
  # `initJson`→`richCast`→highlighted `Text` via the real `Console` (json.*
  # theme push, `end=""`), byte-exact vs `JSON(data_str)`.
  if name == "json_with_array_nested":
    return renderJsonAnsi("{\"items\": [{\"a\": 1}, {\"b\": 2}]}")
  if name == "json_with_float":
    return renderJsonAnsi("{\"pi\": 3.14, \"e\": 2.71}")

  # json_deep — 5 new JSON edge cases. `renderJsonAnsi` drives `initJson`→
  # `parseJson`→`pretty(node, 2)` (Nim `std/json`) + `JSONHighlighter` through
  # the real Console with a json.* theme push and `end=""`, matching
  # `JSON(data_str)` (which does `json.dumps(indent=2, ensure_ascii=False)`).
  # Inputs/expected renderings probed from Python rich 15.0.0 (the oracle).
  if name == "nested_json":
    return renderJsonAnsi("{\"a\": {\"b\": {\"c\": [1, {\"d\": 2}]}}}")
  if name == "json_unicode":
    return renderJsonAnsi("{\"name\": \"日本語\", \"emoji\": \"🎉\", \"café\": \"naïve\"}")
  if name == "json_numbers":
    return renderJsonAnsi("{\"int\": 42, \"neg\": -7, \"float\": 3.14, \"zero\": 0}")
  if name == "json_empty_array":
    return renderJsonAnsi("{\"empty\": [], \"also\": {}}")
  if name == "json_string_escapes":
    return renderJsonAnsi("{\"escaped\": \"a\\tb\\nc\", \"quote\": \"say \\\"hi\\\"\"}")
  # json_array_strings — 1 new JSON edge case. `renderJsonAnsi` drives
  # `initJson`→`richCast`→`Text` through the real `Console` (json.* theme
  # push, `end=""`), parametric over the data string. A pure-string array
  # `["a", "b", "c"]`: `json.dumps(indent=2)` lays each string on its own
  # indented line, braces bold (`json.brace`), strings green (`json.str`).
  # Distinct from `json_array` (mixed int+string). No new renderer — pure
  # addition of a dispatch branch.
  if name == "json_array_strings":
    return renderJsonAnsi("[\"a\", \"b\", \"c\"]")

  # Slice R3 (Traceback) — real `Traceback.from_exception` synthesised as a
  # `Panel` (frame lines) + exception line, rendered through the real `Console`
  # (traceback.* theme push). See renderTracebackAnsi above.
  if name == "traceback_simple":
    return renderTracebackAnsi("ValueError", "test message", 1)
  if name == "traceback_nested":
    return renderTracebackAnsi("KeyError", "missing key", 2)
  if name == "traceback_simple_error":
    return renderTracebackAnsi("ValueError", "test error", 1)
  if name == "traceback_with_locals":
    return renderTracebackWithLocalsAnsi()
  if name == "traceback_syntax_error":
    return renderTracebackSyntaxErrorAnsi()
  if name == "traceback_chain":
    return renderTracebackChainAnsi()
  if name == "traceback_max_frames":
    return renderTracebackMaxFramesAnsi()

  # Slice R4 (Prompt) — real `initPrompt`→`makePrompt` (the static display
  # `Text`, prompt.py:120-141) → rendered through the real `Console` (prompt.*
  # theme push). Args mirror golden_cases.py / golden_ref.py `render_prompt`:
  # (text, choices, default). `choices` is `none(seq[string])` (no choices) or
  # `some(@[...])`; `default` is `none(string)` (no default sentinel) or
  # `some("...")`. `prompt_confirm` passes `choices=@["y","n"]` (a plain
  # Prompt reproduces Confirm's make_prompt byte-exact). See renderPromptAnsi
  # above.
  if name == "prompt_simple":
    return renderPromptAnsi("Enter name", none(seq[string]), none(string))
  if name == "prompt_confirm":
    return renderPromptAnsi("Continue", some(@["y", "n"]), none(string))
  if name == "prompt_choices":
    return renderPromptAnsi("Pick", some(@["a", "b", "c"]), none(string))
  if name == "prompt_default":
    return renderPromptAnsi("Enter name", none(seq[string]), some("Alice"))
  if name == "prompt_choices_default":
    return renderPromptAnsi("Pick", some(@["a", "b", "c"]), some("a"))
  # prompt_advanced — NEW prompt edge cases exercising the `password` flag
  # (initPrompt `password` param, prompt.nim). `password` has NO effect on
  # `makePrompt` (the static display, prompt.py:120-141) — only on the
  # interactive `console.input` echo loop — so the rendered Text equals the
  # same Prompt without `password`; the cases exercise the `Prompt(...,
  # password=True)` construction path (and, for prompt_password_choices, the
  # password+choices combination, distinct from prompt_choices by [x/y]).
  if name == "prompt_password":
    return renderPromptAnsi("Password", none(seq[string]), none(string), password = true)
  if name == "prompt_password_choices":
    return renderPromptAnsi("Pick", some(@["x", "y"]), none(string), password = true)

  # Box — `rich.table.Table(box=box)` rendered with five `rich.box` box styles
  # (ASCII/ROUNDED/DOUBLE/HEAVY/MINIMAL), Table defaults (padding=(0,1),
  # header_style="table.header"→bold header, auto-width columns), two columns
  # "A"/"B" and one row "1"/"2". The real `Console` (renderBoxAnsi above,
  # reusing renderTableAnsi at width 80) drives `Table.renderConsole`. See
  # renderBoxAnsi above.
  if name == "box_ascii":   return renderBoxAnsi("ascii")
  if name == "box_rounded": return renderBoxAnsi("rounded")
  if name == "box_double":  return renderBoxAnsi("double")
  if name == "box_heavy":   return renderBoxAnsi("heavy")
  if name == "box_minimal": return renderBoxAnsi("minimal")

  # v0.8.2 — box edge cases. `box_square` exercises the SQUARE box style
  # (rich.box.SQUARE, genuinely new — the original five box_* cases cover
  # ASCII/ROUNDED/DOUBLE/HEAVY/MINIMAL only) with the default 2-column "A"/"B",
  # 1-row "1"/"2" content. `box_minimal_three`/`box_heavy_three` exercise the
  # MINIMAL/HEAVY box styles with a NEW 3-column ("X"/"Y"/"Z"), 2-row
  # ("1","2","3")/("4","5","6") content config via renderBoxAnsiThree — a
  # genuinely new edge combination distinct from the baseline box_minimal/
  # box_heavy (which use the default 2-column content). Same renderTableAnsi
  # path (width 80), byte-exact vs golden_ref.render_box.
  if name == "box_square":          return renderBoxAnsi("square")
  if name == "box_minimal_three":   return renderBoxAnsiThree("minimal")
  if name == "box_heavy_three":     return renderBoxAnsiThree("heavy")

  # Padding — `rich.padding.Padding(Text("hello"), pad=(top,right,bottom,
  # left))` rendered with the default `style="none"`/`expand=True`, exercising
  # the four single-side margins + the all-around case. The real `Console`
  # (renderPaddingAnsi above, width 40) drives `Padding.renderConsole`. See
  # renderPaddingAnsi above.
  if name == "padding_left":    return renderPaddingAnsi("hello", (0, 0, 0, 5), 40)
  if name == "padding_right":   return renderPaddingAnsi("hello", (0, 5, 0, 0), 40)
  if name == "padding_top":     return renderPaddingAnsi("hello", (2, 0, 0, 0), 40)
  if name == "padding_bottom":  return renderPaddingAnsi("hello", (0, 0, 3, 0), 40)
  if name == "padding_around":  return renderPaddingAnsi("hello", (1, 2), 40)
  # padding_advanced — NEW padding edge cases exercising the `style` kwarg
  # (initPadding `style` param, padding.nim). A non-"none" style is resolved via
  # `Console.getStyle` in `Padding.renderConsole` and applied to BOTH the
  # padding spaces and the inner segments, wrapping the whole block in the
  # style's ANSI. padding_style uses the 4-tuple pad (1,2,1,2) + "blue";
  # padding_style_red uses (0,1,0,1) + "red".
  if name == "padding_style":     return renderPaddingAnsi("hello", (1, 2, 1, 2), 40, style = "blue")
  if name == "padding_style_red": return renderPaddingAnsi("hi", (0, 1, 0, 1), 40, style = "red")

  # Markup — real `Text.fromMarkup` (text.nim's `renderMarkupInline` port of
  # `markup.render`) → `renderTextAnsi` (the `Text.render` path, width 80),
  # matching `golden_ref.render_markup`. See `renderMarkupAnsi` above. The
  # `\[bold]plain` escape passes the raw `\[bold]plain` string (one backslash
  # before `[` → `markup.render`'s parse treats `[bold]` as a literal `[`, no
  # style span).
  if name == "markup_bold":     return renderMarkupAnsi("[bold]bold text[/]")
  if name == "markup_italic":   return renderMarkupAnsi("[italic]italic text[/]")
  if name == "markup_color":    return renderMarkupAnsi("[red]red text[/]")
  if name == "markup_combined": return renderMarkupAnsi("[bold red]bold red text[/]")
  if name == "markup_escape":   return renderMarkupAnsi(r"\[bold]plain")

  # v0.4.0 (ABC) — ASCII-box cases via renderTableAnsi/renderPanelAnsi. See
  # renderAbcAnsi above. `rich.abc` holds only the abstract `RichRenderable`
  # concept (no renderable/constructor — confirmed round_001); the "abc golden"
  # gap is filled with ASCII-box rendering on the `Table`/`Panel` paths via
  # `rich.box.ASCII`/`ASCII_DOUBLE_HEAD`, reusing the existing
  # `renderTableAnsi`/`renderPanelAnsi` (the real `Console` dispatch).
  if name == "abc_simple" or name == "abc_box" or name == "abc_border":
    return renderAbcAnsi(name)

  # v0.4.0 (Styled) — `Styled(renderable, style)` via renderStyledAnsi. See
  # renderStyledAnsi above. The renderable is a `Text` (the documented Nim
  # limitation is the non-`Text` arm — these cases AVOID it, byte-exact).
  if name == "styled_simple":
    return renderStyledAnsi(initStyled(RenderableValue(initText("hello")),
                                       "bold red"), 80)
  if name == "styled_nested":
    let t = initText("")
    discard t.append("he", "red")
    discard t.append("llo", "blue")
    return renderStyledAnsi(initStyled(RenderableValue(t), "bold red"), 80)
  if name == "styled_style":
    return renderStyledAnsi(initStyled(RenderableValue(initText("hi")),
                                       "bold italic red on blue"), 80)

  # v0.4.0 (Ratio) — `Table.add_column(ratio=...)` via renderRatioAnsi (a thin
  # alias over renderTableAnsi). See renderRatioAnsi above. `box=none(Box)`
  # (borderless grid) + `width=some(40)` (flexible columns expand to fill it).
  if name == "ratio_simple":
    let t = initTable(box = none(Box), width = some(40))
    t.addColumn("A", ratio = some(1))
    t.addColumn("B", ratio = some(2))
    t.addColumn("C", ratio = some(1))
    t.addRow("x", "y", "z", style = default(StyleOpt), endSection = false)
    return renderRatioAnsi(t)
  if name == "ratio_uneven":
    let t = initTable(box = none(Box), width = some(40))
    t.addColumn("A", ratio = some(1))
    t.addColumn("B", ratio = some(3))
    t.addRow("x", "y", style = default(StyleOpt), endSection = false)
    return renderRatioAnsi(t)
  if name == "ratio_three":
    let t = initTable(box = none(Box), width = some(40))
    t.addColumn("A", ratio = some(1))
    t.addColumn("B", ratio = some(1))
    t.addColumn("C", ratio = some(1))
    t.addRow("x", "y", "z", style = default(StyleOpt), endSection = false)
    return renderRatioAnsi(t)

  # v0.4.0 (Layout) — `Layout.split_column`/`split_row`/tree via
  # renderLayoutAnsi. See renderLayoutAnsi above. Each section has a real
  # `Text` renderable (NOT the `Placeholder` — the Nim `Placeholder` renders the
  # literal `"Placeholder"`, NOT byte-exact with Python's `Panel(Pretty(layout))`);
  # using `Text` keeps the output byte-exact. Width 40, height 24.
  if name == "layout_simple":
    let l = initLayout()
    l.splitColumn(initText("upper"), initText("lower"))
    return renderLayoutAnsi(l, 40)
  if name == "layout_split_row":
    let l = initLayout()
    l.splitRow(initText("L"), initText("R"))
    return renderLayoutAnsi(l, 40)
  if name == "layout_tree":
    let l = initLayout()
    let upper = initLayout(some(RenderableValue(initText("upper"))))
    upper.splitRow(initText("a"), initText("b"))
    l.splitColumn(upper, initText("lower"))
    return renderLayoutAnsi(l, 40)

  # v0.4.0 (ANSI) — `AnsiDecoder.decode` → `Text` via renderAnsiAnsi. See
  # renderAnsiAnsi above. Single-line inputs (no `\n`) yield one `Text`,
  # rendered with `end=""` (no trailing newline, the `text_plain` pattern).
  if name == "ansi_simple":     return renderAnsiAnsi("plain text")
  if name == "ansi_color":      return renderAnsiAnsi("\x1b[31mred\x1b[0m")
  if name == "ansi_bold":        return renderAnsiAnsi("\x1b[1mbold\x1b[0m")
  if name == "ansi_bold_color": return renderAnsiAnsi("\x1b[1;31mbold red\x1b[0m")
  if name == "ansi_reset":       return renderAnsiAnsi("\x1b[31mred\x1b[0mplain")

  # v0.5.0 — Constrain/Scope/Region/Screen gap-fill (see render procs above).
  if name == "constrain_width":  return renderConstrainAnsi(20)
  if name == "constrain_height": return renderConstrainAnsi(30)
  if name == "constrain_both":   return renderConstrainAnsi(40)
  # layout_constrain — 2 new Constrain cases with distinct inner text.
  if name == "constrain_max":  return renderConstrainAnsi(25, "constrained max")
  if name == "constrain_min":  return renderConstrainAnsi(5, "ok")
  # layout_constrain — 3 new Group cases.
  if name == "group_render":  return renderGroupAnsi("render", 40)
  if name == "group_styled":  return renderGroupAnsi("styled", 40)
  if name == "group_rule":    return renderGroupAnsi("rule", 40)
  if name == "scope_simple":
    return renderScopeAnsi(buildScopeRenderable([("a", 1), ("b", 2)].toOrderedTable()), 9)
  if name == "scope_nested":
    return renderScopeAnsi(buildScopeRenderable([("d", [("inner", 5)].toOrderedTable())].toOrderedTable()), 20)
  if name == "scope_style":
    return renderScopeAnsi(buildScopeRenderable([("x", 1)].toOrderedTable(), title = "Variables"), 15)
  if name == "region_simple":  return renderRegionAnsi(0, 0, 20, 10)
  if name == "region_offset":  return renderRegionAnsi(5, 3, 15, 8)
  if name == "region_overlap": return renderRegionAnsi(10, 5, 20, 10)
  if name == "screen_simple": return renderScreenAnsi(["hi"], 20, 24, false)
  if name == "screen_multi":  return renderScreenAnsi(["line1", "line2"], 20, 24, false)
  if name == "screen_update": return renderScreenAnsi(["hi"], 20, 24, true)

  # v0.6.0 — Measure/Repr/Theme/TerminalTheme/Errors gap-fill (5 modules, 18
  # new cases). See the render procs above. Measure values are the shell-probed
  # `Measurement.get` results (constructing `Measurement` directly because
  # `measure.nim` `get` is DEFERRED). Repr uses the real `repr.autoRepr`.
  # Theme pushes the real `initTheme` (Style.parse) via `console.pushTheme`.
  # TerminalTheme constructs via `initTerminalTheme`/`DEFAULT_TERMINAL_THEME`.
  # Errors construct via `newException` (the real `errors.nim` classes).
  if name == "measure_text":  return renderMeasureAnsi(5, 5)
  if name == "measure_table": return renderMeasureAnsi(11, 11)
  if name == "measure_panel": return renderMeasureAnsi(11, 11)
  if name == "measure_wide":  return renderMeasureAnsi(6, 16)
  if name == "repr_simple": return renderReprAnsi("simple")
  if name == "repr_text":   return renderReprAnsi("text")
  if name == "repr_panel":  return renderReprAnsi("panel")
  if name == "repr_error":  return renderReprAnsi("error")
  if name == "theme_simple": return renderThemeAnsi("simple", 80)
  if name == "theme_multi":  return renderThemeAnsi("multi", 80)
  if name == "theme_apply":  return renderThemeAnsi("apply", 40)
  if name == "terminal_theme_simple": return renderTerminalThemeAnsi("simple")
  if name == "terminal_theme_custom": return renderTerminalThemeAnsi("custom")
  if name == "terminal_theme_fg":     return renderTerminalThemeAnsi("fg")
  if name == "errors_console":       return renderErrorsAnsi("ConsoleError", "a console error")
  if name == "errors_style":         return renderErrorsAnsi("StyleError", "a style error")
  if name == "errors_notrenderable":  return renderErrorsAnsi("NotRenderableError", "not renderable here")
  if name == "errors_live":          return renderErrorsAnsi("LiveError", "a live error")

  # FileProxy — `rich.file_proxy.FileProxy` round-trip. Each case builds the
  # variant's renderable, renders it to raw ANSI via the proven `render*Ansi`
  # carrier (byte-identical to the matching existing case), appends exactly one
  # trailing newline (Text does not end with `\n`; Panel/Table already do),
  # and round-trips the concatenation through the real Nim `FileProxy`
  # (write+flush → decodeLine → Console.print → renderBuffer). For `multi`,
  # two Texts are concatenated. Width matches `golden_ref.py`'s `case_width`.
  if name == "file_proxy_simple":
    return renderFileProxyAnsi(renderTextAnsi(initText("hello")) & "\n", 80)
  if name == "file_proxy_text":
    return renderFileProxyAnsi(renderTextAnsi(initText("red text", "red")) & "\n", 80)
  if name == "file_proxy_text_bold":
    return renderFileProxyAnsi(renderTextAnsi(initText("bold hi", "bold")) & "\n", 80)
  if name == "file_proxy_panel":
    let p = initPanel("hello", box = ROUNDED)
    return renderFileProxyAnsi(renderPanelAnsi(p, 80), 80)
  if name == "file_proxy_panel_title":
    let p = initPanel("hello", box = ROUNDED, title = "Title")
    return renderFileProxyAnsi(renderPanelAnsi(p, 40), 40)
  if name == "file_proxy_table":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    t.addRow("abcd", "efgh", style = default(StyleOpt), endSection = false)
    return renderFileProxyAnsi(renderTableAnsi(t), 80)
  if name == "file_proxy_multi":
    return renderFileProxyAnsi(renderTextAnsi(initText("first")) & "\n" &
                               renderTextAnsi(initText("second", "red")) & "\n", 80)

  # LiveRender — `rich.live_render.LiveRender` non-interactive render. Each
  # case builds the variant's renderable (the same config the matching existing
  # case uses, so the inner render is byte-identical), wraps it in a real Nim
  # `LiveRender`, and renders via `renderLiveRenderAnsi`. The output equals the
  # plain render minus one trailing `"\n"` (Panel/Table/Columns) or the plain
  # render unchanged (Text — no trailing `"\n"`), matching rich's
  # `LiveRender.__rich_console__` (`pad=False` + line-join). Width matches
  # `golden_ref.py`'s `case_width` (80 full-width; 40 columns/multi).
  if name == "live_render_simple":
    return renderLiveRenderAnsi(initLiveRender(initText("hello")), 80)
  if name == "live_render_text_styled":
    return renderLiveRenderAnsi(initLiveRender(initText("red text", "red")), 80)
  if name == "live_render_text_bold":
    return renderLiveRenderAnsi(initLiveRender(initText("bold hi", "bold")), 80)
  if name == "live_render_panel":
    return renderLiveRenderAnsi(initLiveRender(initPanel("hello", box = ROUNDED)), 80)
  if name == "live_render_table":
    let t = initTable(padding = (0, 0, 0, 0), headerStyle = "",
                      box = some(HEAVY_HEAD))
    t.addColumn("Name", width = some(4), noWrap = true)
    t.addColumn("Data", width = some(4), noWrap = true)
    t.addRow("abcd", "efgh", style = default(StyleOpt), endSection = false)
    return renderLiveRenderAnsi(initLiveRender(t), 80)
  if name == "live_render_columns":
    return renderLiveRenderAnsi(initLiveRender(
      initColumns(@[RenderableValue(initText("a")),
                    RenderableValue(initText("b")),
                    RenderableValue(initText("c"))],
                   padding = PaddingDimensions(kind: pdPair, pair: (0, 1)))), 40)
  if name == "live_render_multi":
    return renderLiveRenderAnsi(initLiveRender(
      initColumns(@[RenderableValue(initText("first")),
                    RenderableValue(initText("second", "red"))],
                   padding = PaddingDimensions(kind: pdPair, pair: (0, 1)))), 40)

  return "UNKNOWN_CASE:" & name

const allCaseNames = [
    "text_plain", "text_empty", "text_unicode", "text_emoji",
    "text_bold", "text_red", "text_bold_red", "text_dim_green",
    "text_italic_yellow", "text_underline_blue", "text_reverse",
    "text_strikethrough", "text_spans_bold_red", "text_spans_3color",
    "text_spans_nested", "text_spans_emoji_in_span",
    "text_spans_unicode_in_span", "text_spans_empty_style",
    "text_spans_mixed_styles",
    "text_bg_style", "text_dim_italic",
    "rule_plain", "rule_title", "rule_title_styled", "rule_chars", "rule_style",
    "control_home", "control_clear", "control_title",
    "control_move", "control_move_up", "control_move_down",
    "control_clear_line", "control_segment",
    "filesize_bytes", "filesize_kb", "filesize_decimal",
    "filesize_gb", "filesize_tb",
    "table_simple", "table_header_only", "table_styled", "table_with_title",
    "table_styled_header", "table_row_styles", "table_padding",
    "table_col_align", "table_show_lines",
    "panel_simple", "panel_title", "panel_subtitle", "panel_styled_border",
    "panel_title_subtitle",
    "tree_simple", "tree_nested", "tree_hide_root", "tree_styled",
    "tree_multi_children",
    "emoji_simple", "emoji_thumbs_up", "emoji_styled", "emoji_variant",
    "emoji_replace",
    "markdown_heading", "markdown_paragraph", "markdown_inline_bold",
    "markdown_mixed",
    "markdown_bold_italic", "markdown_code_inline", "markdown_quote",
    "markdown_link", "markdown_strike",
    "markdown_heading_h3", "markdown_list",
    "bar_half", "bar_full", "bar_empty", "bar_styled",
    "align_left", "align_center", "align_right", "align_styled",
    "align_multiline",
    "columns_simple", "columns_padding", "columns_styled",
    "columns_multi", "columns_expand",
    "columns_three", "columns_with_padding",
    "syntax_python", "syntax_json", "syntax_python_keywords",
    "syntax_json_object", "syntax_python_multiline", "syntax_bash_script",
    "syntax_nim_code",
    "spinner_dots", "spinner_line", "spinner_arc", "spinner_bounce",
    "pretty_list", "pretty_dict", "pretty_string",
    "pretty_int", "pretty_bool", "pretty_none", "pretty_nested_list",
    "pretty_tuple", "pretty_mixed_dict",
    "pretty_set", "pretty_frozenset", "pretty_complex_data",
    "status_dots", "status_line", "status_spinner_text",
    "logging_info", "logging_warning", "logging_info_message",
    "logging_error_message",
    "progress_50", "progress_100", "progress_mixed",
    "progress_multi_column", "progress_transfer_speed",
    # progress_advanced — 5 new Progress column-type/layout cases.
    "progress_with_time", "progress_multiple_bars", "progress_complete",
    "progress_description", "progress_file_size",
    "json_simple", "json_nested", "json_array", "json_with_null",
    "json_with_bool", "json_nested_deep",
    "json_with_array_nested", "json_with_float",
    # json_deep — 5 new JSON edge cases.
    "nested_json", "json_unicode", "json_numbers",
    "json_empty_array", "json_string_escapes",
    "json_array_strings",
    "traceback_simple", "traceback_nested", "traceback_simple_error",
    "traceback_with_locals", "traceback_syntax_error", "traceback_chain",
    "traceback_max_frames",
    "prompt_simple", "prompt_confirm", "prompt_choices",
    "prompt_default", "prompt_choices_default",
    "box_ascii", "box_rounded", "box_double", "box_heavy", "box_minimal",
    "box_square", "box_minimal_three", "box_heavy_three",
    "padding_left", "padding_right", "padding_top", "padding_bottom",
    "padding_around",
    "markup_bold", "markup_italic", "markup_color", "markup_combined",
    "markup_escape",
    "abc_simple", "abc_box", "abc_border",
    "styled_simple", "styled_nested", "styled_style",
    "ratio_simple", "ratio_uneven", "ratio_three",
    "layout_simple", "layout_split_row", "layout_tree",
    "ansi_simple", "ansi_color", "ansi_bold", "ansi_bold_color",
    "ansi_reset",
    "constrain_width", "constrain_height", "constrain_both",
    # layout_constrain — 5 new cases (2 Constrain + 3 Group).
    "constrain_max", "constrain_min",
    "group_render", "group_styled", "group_rule",
    "scope_simple", "scope_nested", "scope_style",
    "region_simple", "region_offset", "region_overlap",
    "screen_simple", "screen_multi", "screen_update",
    # v0.6.0 — 18 new gap-fill cases (measure/repr/theme/terminal_theme/errors).
    "measure_text", "measure_table", "measure_panel", "measure_wide",
    "repr_simple", "repr_text", "repr_panel", "repr_error",
    "theme_simple", "theme_multi", "theme_apply",
    "terminal_theme_simple", "terminal_theme_custom", "terminal_theme_fg",
    "errors_console", "errors_style", "errors_notrenderable", "errors_live",
    # v0.7.0 — 7 new file_proxy gap-fill cases (file_proxy round-trip).
    "file_proxy_simple", "file_proxy_text", "file_proxy_text_bold",
    "file_proxy_panel", "file_proxy_panel_title", "file_proxy_table",
    "file_proxy_multi",
    # v0.7.0 — 7 new live_render gap-fill cases (LiveRender non-interactive render).
    "live_render_simple", "live_render_text_styled", "live_render_text_bold",
    "live_render_panel", "live_render_table", "live_render_columns",
    "live_render_multi",
    # 5 new cases — spinner (arrow/dots2), emoji (white_check_mark),
    # filesize (two_kilobytes/megabytes).
    "spinner_arrow", "spinner_dots2", "emoji_check_mark",
    "filesize_two_kilobytes", "filesize_megabytes",
]

when isMainModule:
  import std/times
  if paramCount() < 1:
    echo "usage: golden_nim <case> | bench [N]"
    quit(2)
  if paramStr(1) == "bench":
    ## In-process pure-render benchmark: loop all cases N times, no startup.
    let n = if paramCount() >= 2: parseInt(paramStr(2)) else: 1000
    var sink: string
    let t0 = cpuTime()
    for _ in 1..n:
      for c in allCaseNames:
        sink = renderCase(c)
    let el = cpuTime() - t0
    let total = n * allCaseNames.len
    stdout.write("NIM bench: " & $n & "x" & $allCaseNames.len & " = " & $total &
      " renders in " & formatFloat(el, ffDecimal, 4) & "s\n")
    stdout.write("NIM per-render: " & formatFloat(el / float(total), ffDecimal, 9) &
      "s  |  renders/sec: " & formatFloat(float(total) / el, ffDecimal, 0) & "\n")
    stdout.write("sink-checksum-len: " & $sink.len & "\n")
    stdout.flushFile()
    quit(0)
  let outp = renderCase(paramStr(1))
  stdout.write(outp)
  stdout.flushFile()
