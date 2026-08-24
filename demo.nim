# demo.nim — nim-rich demo (port of Python rich `python -m rich`)
#
# Build: nim c -d:release --path:src --path:../nimgments/src -o:./demo demo.nim
# Run:   ./demo
# Compare: /home/slawek/src/rich-rewrite-nim/golden-venv/bin/python -m rich

import std/[times, strutils, strformat, math, options, os, sequtils]
import nim_rich/[richbase, segment, style, measure, color, color_triplet,
                 cells, errors, ratio, text, tree, rule, control, filesize,
                 table, panel, box, api_types, console_api, console, emoji,
                 markdown, bar, align, columns, padding, syntax, spinner,
                 status, logging, traceback, json, theme, highlighter, pretty,
                 progress, progress_bar, prompt, styled, layout, ansi,
                 constrain, scope, region, screen, repr, terminal_theme,
                 file_proxy, live_render]

proc makeConsole(width: Option[int]): Console =
  initConsole(colorSystem = some("truecolor"),
              forceTerminal = some(true),
              softWrap = false,
              width = width,
              height = some(24),
              legacyWindows = some(false),
              record = false,
              noColor = some(false))

# ColorBox — custom renderable z renderConsole (jak Python __rich_console__)
type
  ColorBox = ref object of RenderableBase

proc hlsToRgb(h, l, s: float): (float, float, float) =
  let c = (1.0 - abs(2.0 * l - 1.0)) * s
  let hp = h * 6.0
  let xChroma = c * (1.0 - abs((hp mod 2.0) - 1.0))
  var (r1, g1, b1) = (0.0, 0.0, 0.0)
  if hp < 1.0: (r1, g1, b1) = (c, xChroma, 0.0)
  elif hp < 2.0: (r1, g1, b1) = (xChroma, c, 0.0)
  elif hp < 3.0: (r1, g1, b1) = (0.0, c, xChroma)
  elif hp < 4.0: (r1, g1, b1) = (0.0, xChroma, c)
  elif hp < 5.0: (r1, g1, b1) = (xChroma, 0.0, c)
  else: (r1, g1, b1) = (c, 0.0, xChroma)
  let m = l - c / 2.0
  (r1 + m, g1 + m, b1 + m)

method renderConsole*(self: ColorBox, console: ConsoleHandle,
                      options: ConsoleOptions): RenderResult =
  let width = options.maxWidth
  for y in 0..<5:
    var lineSegs: seq[Segment] = @[]
    for x in 0..<width:
      let h = x.float / width.float
      let l = 0.1 + (y.float / 5.0) * 0.7
      let (r1, g1, b1) = hlsToRgb(h, l, 1.0)
      let bgcolor = Color.fromRgb(r1 * 255, g1 * 255, b1 * 255)
      let l2 = l + 0.7 / 10.0
      let (r2, g2, b2) = hlsToRgb(h, l2, 1.0)
      let color = Color.fromRgb(r2 * 255, g2 * 255, b2 * 255)
      let st = initStyle(color = some(color), bgcolor = some(bgcolor))
      lineSegs.add(Segment(text: "▄", style: some[StyleRef](st)))
    for seg in lineSegs:
      result.add(initRenderResultItem(seg))
    # newline
    result.add(initRenderResultItem(line()))

proc initColorBox(): ColorBox = ColorBox()

method richMeasure*(self: ColorBox, console: ConsoleHandle,
                    options: ConsoleOptions): Measurement =
  Measurement(minimum: 1, maximum: options.maxWidth)

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

proc renderViaConsole(c: Console, renderable: RenderableValue): string =
  c.beginCapture()
  c.print([renderable], emoji = some(true), markup = some(true))
  result = c.endCapture()

proc main() =
  # width auto-detect in makeConsole (COLUMNS env → 80); optionally --width N
  discard  # placeholder — makeConsole(none(int)) will auto-detect
  let t0 = cpuTime()

  var table = Table.grid(padding = 1, padEdge = true)
  table.title = toTableTextOpt("Rich features")
  table.addColumn("Feature", noWrap = true, justify = jmCenter, style = "bold red")
  table.addColumn("Demonstration")

  # Colors row — ColorBox + labels
  var colorTable = initTable(box = none(Box), expand = false,
                              showHeader = false, showEdge = false, padEdge = false)
  let colorsText = Text.fromMarkup(
    "✓ [bold green]4-bit color[/]\n" &
    "✓ [bold blue]8-bit color[/]\n" &
    "✓ [bold magenta]Truecolor (16.7 million)[/]\n" &
    "✓ [bold yellow]Dumb terminals[/]\n" &
    "✓ [bold cyan]Automatic color conversion")
  colorTable.addRow(colorsText, initColorBox(), style = default(StyleOpt), endSection = false)
  table.addRow("Colors", colorTable, style = default(StyleOpt), endSection = false)

  # Styles row
  table.addRow("Styles",
    Text.fromMarkup("All ansi styles: [bold]bold[/], [dim]dim[/], [italic]italic[/], [underline]underline[/], [strike]strikethrough[/], [reverse]reverse[/], and even [blink]blink[/]."),
    style = default(StyleOpt), endSection = false)

  # Text row
  let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque in metus sed sapien ultricies pretium a at justo. Maecenas luctus velit et auctor maximus."
  var loremTable = Table.grid(padding = 1, collapsePadding = true)
  loremTable.padEdge = false
  loremTable.addRow(initText(lorem, justify = some(jmLeft), style = "green"),
                    initText(lorem, justify = some(jmCenter), style = "yellow"),
                    initText(lorem, justify = some(jmRight), style = "blue"),
                    initText(lorem, justify = some(jmFull), style = "red"),
                    style = default(StyleOpt), endSection = false)
  table.addRow("Text",
    initGroup([toRenderableValue(Text.fromMarkup("Word wrap text. Justify [green]left[/], [yellow]center[/], [blue]right[/] or [red]full[/].\n")),
               toRenderableValue(loremTable)]),
    style = default(StyleOpt), endSection = false)

  # Asian language support
  table.addRow("Asian\nlanguage\nsupport",
    Text.fromMarkup(emojiReplace(":flag_for_china:  该库支持中文，日文和韩文文本！\n:flag_for_japan:  ライブラリは中国語、日本語、韓国語のテキストをサポートしています\n:flag_for_south_korea:  이 라이브러리는 중국어, 일본어 및 한국어 텍스트를 지원합니다")),
    style = default(StyleOpt), endSection = false)

  # Markup row
  table.addRow("Markup",
    Text.fromMarkup(emojiReplace("[bold magenta]Rich[/] supports a simple [i]bbcode[/i]-like [b]markup[/b] for [yellow]color[/], [underline]style[/], and emoji! :+1: :apple: :ant: :bear: :baguette_bread: :bus: ")),
    style = default(StyleOpt), endSection = false)

  # Tables row
  var exampleTable = initTable(showEdge = false, showHeader = true, expand = false,
                                box = some(SIMPLE))
  exampleTable.addColumn("[green]Date", style = "green", noWrap = true)
  exampleTable.addColumn("[blue]Title", style = "blue")
  exampleTable.addColumn("[cyan]Production Budget", style = "cyan", justify = jmRight, noWrap = true)
  exampleTable.addColumn("[magenta]Box Office", style = "magenta", justify = jmRight, noWrap = true)
  exampleTable.addRow("Dec 20, 2019", "Star Wars: The Rise of Skywalker", "$275,000,000", "$375,126,118",
                      style = default(StyleOpt), endSection = false)
  exampleTable.addRow("May 25, 2018", "[b]Solo[/]: A Star Wars Story", "$275,000,000", "$393,151,347",
                      style = default(StyleOpt), endSection = false)
  exampleTable.addRow("Dec 15, 2017", "Star Wars Ep. VIII: The Last Jedi", "$262,000,000", "[bold]$1,332,539,889[/bold]",
                      style = default(StyleOpt), endSection = false)
  exampleTable.addRow("May 19, 1999", "Star Wars Ep. [b]I[/b]: [i]The phantom Menace", "$115,000,000", "$1,027,044,677",
                      style = default(StyleOpt), endSection = false)
  table.addRow("Tables", exampleTable, style = default(StyleOpt), endSection = false)

  # Syntax row
  let code = """def iter_last(values: Iterable[T]) -> Iterable[Tuple[bool, T]]:
    \"\"\"Iterate and generate a tuple with a flag for last value.\"\"\"
    iter_values = iter(values)
    try:
        previous_value = next(iter_values)
    except StopIteration:
        return
    for value in iter_values:
        yield False, previous_value
        previous_value = value
    yield True, previous_value"""
  let syntax = initSyntax(code, LexerOrStr(kind: losStr, s: "python3"),
                          SyntaxThemeArg(kind: staStr, s: "monokai"),
                          lineNumbers = true, indentGuides = true)
  table.addRow("Syntax\nhighlighting\n&\npretty\nprinting",
    syntax, style = default(StyleOpt), endSection = false)

  # Markdown row
  let mdExample = "# Markdown\n\nSupports much of the *markdown* __syntax__!\n\n- Headers\n- Basic formatting: **bold**, *italic*, `code`\n- Block quotes\n- Lists, and more...\n    "
  table.addRow("Markdown", initMarkdown(mdExample), style = default(StyleOpt), endSection = false)

  table.addRow("+more!",
    initText("Progress bars, columns, styled logging handler, tracebacks, etc..."),
    style = default(StyleOpt), endSection = false)

  let taken = round((cpuTime() - t0) * 1000.0, 1)

  let console = makeConsole(none(int))  # auto-detect z COLUMNS (jak Python)

  # Render przez Console.print (emoji replace + markup)
  console.beginCapture()
  console.print([toRenderableValue(Text.fromMarkup(&"rendered in [not dim]{taken}ms[/] (cold cache)", style = "dim"))],
                emoji = some(true), markup = some(true))
  stdout.write(console.endCapture())

  console.beginCapture()
  console.print([toRenderableValue(table)], emoji = some(true), markup = some(true))
  stdout.write(console.endCapture())

  # Panel
  let panel = initPanel(
    Text.fromMarkup("[b magenta]Hope you enjoy using Rich![/]\n\nConsider sponsoring to ensure this project is maintained.\n\n[cyan]https://github.com/sponsors/willmcgugan[/cyan]"),
    borderStyle = "green", title = "Help ensure Rich is maintained", padding = (1, 2))
  console.beginCapture()
  console.print([toRenderableValue(panel)], emoji = some(true), markup = some(true))
  stdout.write(console.endCapture())

main()
