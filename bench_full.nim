# bench_full.nim — exact benchmark of nim-rich vs Python rich 15.0.0
#
# Build: nim c -d:release --path:src --path:../nimgments/src -o:./bench_full bench_full.nim
# Run:   ./bench_full
#
# Benchmark measures rendering of various renderables (1000 iter, warm).
# Python comparison is run separately via bench_python.py.

import std/[times, strutils, os, strformat, options]
import nim_rich/[richbase, segment, style, measure, color, color_triplet,
                 cells, errors, ratio, text, tree, rule, control, filesize,
                 table, panel, box, api_types, console_api, console, emoji,
                 markdown, bar, align, columns, padding, syntax, spinner,
                 status, logging, traceback, json, theme, highlighter, pretty,
                 progress, progress_bar, prompt, styled, layout, ansi,
                 constrain, scope, region, screen, repr, terminal_theme,
                 file_proxy, live_render]

const ITER = 1000

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
      result &= renderToAnsi(item.consoleItem.renderConsole(handle, opts),
                             handle, opts)
    of rrkRichCast:
      result &= renderToAnsi(item.castItem.renderConsole(handle, opts),
                             handle, opts)

proc makeConsole(): Console =
  initConsole(colorSystem = some("truecolor"),
              forceTerminal = some(true),
              softWrap = false,
              width = some(80),
              height = some(24),
              legacyWindows = some(false),
              record = false,
              noColor = some(false))

proc makeOpts(): ConsoleOptions =
  ConsoleOptions(size: (width: 80, height: 24), legacyWindows: false,
                 minWidth: 0, maxWidth: 80, isTerminal: true,
                 encoding: "utf-8", maxHeight: 24)

proc renderAnsiT(t: Text): string =
  let handle = default(ConsoleHandle)
  renderToAnsi(t.render(handle, ""), handle, default(ConsoleOptions))

proc renderAnsiConsole[T: RenderableBase](r: T): string =
  let console = makeConsole()
  let opts = makeOpts()
  renderToAnsi(r.renderConsole(console, opts), console, opts)

proc renderJsonAnsi(dataStr: string): string =
  let j = initJson(dataStr)
  let console = makeConsole()
  let opts = makeOpts()
  renderToAnsi(j.text.render(console, ""), console, opts)

proc bench(label: string, body: proc()) =
  for i in 0..<10: body()
  var t0 = cpuTime()
  for i in 0..<ITER: body()
  let elapsed = (cpuTime() - t0) * 1000.0 / ITER.float
  echo &"  {label:42s} {elapsed:8.4f} ms/render"

proc main() =
  echo "================================================================"
  echo " nim-rich vs Python rich 15.0.0 — BENCHMARK"
  echo "================================================================"
  echo &"Iterations per benchmark: {ITER}"
  echo &"Nim version: {NimVersion}"
  echo ""

  let txtPlain = initText("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque in metus sed sapien ultricies pretium a at justo.")
  let txtStyled = initText("Hello bold red on blue", style = "bold red on blue")

  echo "--- NIM (in-process, warm) ---"

  bench("Text (plain, 100 chars)", proc() = discard renderAnsiT(txtPlain))
  bench("Text (styled, single)", proc() = discard renderAnsiT(txtStyled))

  bench("Table (3 cols, 4 rows)", proc() =
    var t = initTable()
    t.addColumn("Date", style = "green")
    t.addColumn("Title", style = "blue")
    t.addColumn("Budget", style = "cyan")
    t.addRow("Dec 20, 2019", "Star Wars: Rise of Skywalker", "$275,000,000", style = default(StyleOpt), endSection = false)
    t.addRow("May 25, 2018", "Solo: A Star Wars Story", "$275,000,000", style = default(StyleOpt), endSection = false)
    t.addRow("Dec 15, 2017", "Star Wars: Last Jedi", "$262,000,000", style = default(StyleOpt), endSection = false)
    t.addRow("May 19, 1999", "Star Wars Ep I: Phantom Menace", "$115,000,000", style = default(StyleOpt), endSection = false)
    discard renderAnsiConsole(t))

  bench("Panel (simple)", proc() =
    discard renderAnsiConsole(initPanel(initText("Panel content"), borderStyle = "green")))

  bench("Panel (styled, title)", proc() =
    discard renderAnsiConsole(initPanel(initText("Styled panel"), box = ROUNDED,
                                  borderStyle = "cyan",
                                  title = toPanelTextOpt("My Panel"))))

  bench("Tree (3 levels, 5 nodes)", proc() =
    var root = initTree("Root")
    var child1 = root.add("Child 1")
    discard child1.add("Grandchild 1")
    discard child1.add("Grandchild 2")
    discard root.add("Child 2")
    discard root.add("Child 3")
    discard renderAnsiConsole(root))

  bench("Rule (80 chars)", proc() =
    discard renderAnsiConsole(initRule(characters = "─")))

  bench("Markdown (20 lines)", proc() =
    discard renderAnsiConsole(initMarkdown("# Heading\n\n- item1\n- item2\n\n*italic* **bold** `code`\n\n> quote\n\n1. first\n2. second\n")))

  bench("JSON (nested, 10 keys)", proc() =
    discard renderJsonAnsi("""{"name":"test","items":[1,2,3],"nested":{"a":true,"b":null,"c":[1.5,2.5]}}"""))

  bench("Bar (50%)", proc() =
    discard renderAnsiConsole(initBar(100.0, 0.0, 50.0)))

  bench("Align (center, width 80)", proc() =
    discard renderAnsiConsole(initAlign(initText("centered"), amCenter, pad = true, width = some(80))))

  echo ""
  echo "--- Python rich 15.0.0 ---"
  echo "Uruchom osobno: /home/slawek/src/rich-rewrite-nim/golden-venv/bin/python bench_python.py"

main()
