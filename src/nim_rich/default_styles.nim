## Port of `rich.default_styles` (rich/default_styles.py).
##
## `DEFAULT_STYLES: Dict[str, Style]` (default_styles.py:5): the canonical
## table of named styles used across rich — every `Console`/`Theme`/`Style`
## lookup (`"bold"`, `"rule.line"`, `"json.key"`, `"repr.number"`,
## `"markdown.h1"`, `"traceback.border"`, …) resolves through it. It is a
## module-level dict literal of ~130 entries (default_styles.py:9-173),
## consumed by `Theme.__init__` (theme.py:30-36 — `DEFAULT_STYLES` is the
## default `styles` base) and `Style.parse` (style.py:357-374).
##
## Import graph (rich/default_styles.py:1-3): runtime imports are
## `from typing import Dict` (default_styles.py:1) and `from .style import
## Style` (default_styles.py:3). One rich sibling import → `style`.
##
## wiring (this file):
##   `import std/tables` — `OrderedTable[string, Style]` (the `Dict[str,
##                       Style]` storage; `OrderedTable` preserves the Python
##                       dict insertion order, which matters — `Theme` iterates
##                       `DEFAULT_STYLES` and byte-identical output depends on
##                       that order).
##   `import style`      — `Style` (the value type; `ref object of StyleRef`,
##                       style.nim).
##
## `DEFAULT_STYLES` (default_styles.py:5, `Dict[str, Style]`) is a Python
## module-level dict (insertion-ordered since 3.7). The Nim handle is
## `let DEFAULT_STYLES*: OrderedTable[string, Style]` — `let` (module-global,
## treated as constant; `Style` construction is runtime so it cannot be a Nim
## `const`), `OrderedTable` to preserve insertion order for faithful
## iteration. stub: empty table (mirrors `color.nim`'s
## `let ansiColorNames* = initTable[string, int]()` — the
## `{.used.}` pragma suppresses the unused warning until body wires the
## entries). body populates all ~130 entries verbatim from
## default_styles.py:9-173 (e.g. `"none": Style.null()`, `"bold":
## Style(bold=True)`, `"rule.line": Style(color="bright_green")`, …).

import std/tables
import std/options

import style       # Style — the value type of the DEFAULT_STYLES dict.

## rich default_styles.py:5-173 — `DEFAULT_STYLES: Dict[str, Style]`: the
## canonical named-style table (~130 entries, `DEFAULT_STYLES = {` @5 / @9,
## closes `}` @173). `OrderedTable[string, Style]` preserves the Python dict
## insertion order (matters for `Theme` iteration / byte-identical output).
##
## port (Table) populates ONLY the `table.*` family
## (default_styles.py:120-124) required by `Table`, in Python dict order:
##   "table.header":  Style(bold=True)
##   "table.footer":  Style(bold=True)
##   "table.cell":    Style.null()
##   "table.title":   Style(italic=True)
##   "table.caption": Style(italic=True, dim=True)
## The remaining ~125 entries (none/reset/bold/rule.*/json.*/repr.*/
## markdown.*/traceback.*/bar.*/progress.*/…) stay deferred to a later phase —
## only the `table.*` family is wired here (no unrelated style families).
##
## Used by `Theme.__init__` (theme.py:30-36 — the default `styles` base; Nim
## `initTheme(inherit=true)` sets `result.styles = DEFAULT_STYLES`, and
## `themes.DEFAULT = initTheme()` seeds every production `Console`'s
## `ThemeStack`, so `table.title`/`table.caption` resolve through the normal
## production Console theme with NO custom-theme injection) and `Style.parse`
## (style.py:357-374). `let` (module-global constant; `Style` construction is
## runtime, so not a Nim `const`); `{.used.}` suppresses the unused warning
## until the remaining entries land.
##
## NOTE: the Nim symbol keeps the Python SCREAMING name `DEFAULT_STYLES`
## (NOT camelCased to `defaultStyles`, unlike `color.nim`'s `ANSI_COLOR_NAMES`
## -> `ansiColorNames`): Nim is case-insensitive after the first character
## and ignores underscores, so a camelCase `defaultStyles` would normalize
## to the SAME identifier as the module name `default_styles` — and the
## umbrella's `export default_styles` would then make `defaultStyles`
## ambiguous-unusable for consumers. The first char `D` (vs the module's
## `d`) breaks that collision (Nim's first char is case-sensitive) while
## preserving the exact Python name.
let
  DEFAULT_STYLES* = block:
    var t = initOrderedTable[string, Style]()
    # default_styles.py:120-124 — the `table.*` family, in Python dict order.
    t["table.header"] = initStyle(bold = some(true))   # "table.header":  Style(bold=True)
    t["table.footer"] = initStyle(bold = some(true))   # "table.footer":  Style(bold=True)
    t["table.cell"] = Style.null()                      # "table.cell":    Style.null()
    t["table.title"] = initStyle(italic = some(true))  # "table.title":   Style(italic=True)
    t["table.caption"] = initStyle(italic = some(true),
                                    dim = some(true))    # "table.caption": Style(italic=True, dim=True)
    # default_styles.py:142-161 — the `markdown.*` family, in Python dict
    # order (port). Consumed by `Markdown` rendering: the block/inline
    # element callbacks (`TextElement.onEnter` → `enter_style("markdown.{tag}")`)
    # and `HorizontalRule.renderConsole` (`get_style("markdown.hr")`) resolve
    # these via the production `Console` theme (seeded with `DEFAULT_STYLES`).
    t["markdown.paragraph"] = initStyle()                     # "markdown.paragraph": Style()
    t["markdown.text"] = initStyle()                          # "markdown.text":      Style()
    t["markdown.em"] = initStyle(italic = some(true))         # "markdown.em":        Style(italic=True)
    t["markdown.strong"] = initStyle(bold = some(true))       # "markdown.strong":    Style(bold=True)
    t["markdown.code"] = initStyle(bold = some(true),
                                    color = "cyan",
                                    bgcolor = "black")        # "markdown.code":      Style(bold=True, color="cyan", bgcolor="black")
    t["markdown.code_block"] = initStyle(color = "cyan",
                                         bgcolor = "black")    # "markdown.code_block":Style(color="cyan", bgcolor="black")
    t["markdown.h1"] = initStyle(bold = some(true),
                                 underline = some(true))      # "markdown.h1":        Style(bold=True, underline=True)
    t["markdown.h2"] = initStyle(color = "magenta",
                                 underline = some(true))      # "markdown.h2":        Style(color="magenta", underline=True)
    t["markdown.h3"] = initStyle(color = "magenta",
                                 bold = some(true))           # "markdown.h3":        Style(color="magenta", bold=True)
    t["markdown.h4"] = initStyle(color = "magenta",
                                 italic = some(true))        # "markdown.h4":        Style(color="magenta", italic=True)
    t["markdown.h5"] = initStyle(italic = some(true))         # "markdown.h5":        Style(italic=True)
    t["markdown.h6"] = initStyle(dim = some(true))            # "markdown.h6":        Style(dim=True)
    t["markdown.hr"] = initStyle(dim = some(true))            # "markdown.hr":        Style(dim=True)
    t["markdown.block_quote"] = initStyle(color = "magenta")  # "markdown.block_quote":Style(color="magenta")
    t["markdown.list"] = initStyle(color = "cyan")           # "markdown.list":      Style(color="cyan")
    t["markdown.item"] = initStyle()                          # "markdown.item":      Style()
    t["markdown.item.bullet"] = initStyle(bold = some(true)) # "markdown.item.bullet":Style(bold=True)
    t["markdown.item.number"] = initStyle(color = "cyan")    # "markdown.item.number":Style(color="cyan")
    t["markdown.link"] = initStyle(color = "bright_blue")     # "markdown.link":      Style(color="bright_blue")
    t["markdown.link_url"] = initStyle(color = "blue",       # "markdown.link_url":  Style(color="blue", underline=True)
                                       underline = some(true))
    t["markdown.s"] = initStyle(strike = some(true))          # "markdown.s":         Style(strike=True)
    t["markdown.emph"] = initStyle(italic = some(true))       # "markdown.emph":      Style(italic=True)
    t["markdown.h7"] = initStyle(italic = some(true),         # "markdown.h7":        Style(italic=True, dim=True)
                                 dim = some(true))
    # default_styles.py:64-90 — the `repr.*` family, in Python dict order
    # (port / Pretty). Consumed by `ReprHighlighter`
    # (highlighter.nim `reprHighlighterHighlights`) via `Style.parse` style
    # names of the form `"repr.<group>"`, resolved through the production
    # `Console` theme (seeded with `DEFAULT_STYLES`). Python explicit `False`
    # attributes (e.g. `italic=False`, `bold=False`) are modelled with
    # `some(false)` so the Nim `setAttributes` bit matches Python's
    # `_set_attributes` exactly — the attribute stays OFF (`attributes` bit
    # unset) and `makeAnsiCodes` (style.nim `_make_ansi_codes`) emits no reset
    # SGR for it, matching Rich 15.0.0 byte-for-byte.
    t["repr.ellipsis"] = initStyle(color = "yellow")         # "repr.ellipsis": Style(color="yellow")
    t["repr.indent"] = initStyle(color = "green",
                                 dim = some(true))          # "repr.indent": Style(color="green", dim=True)
    t["repr.error"] = initStyle(color = "red",
                                bold = some(true))         # "repr.error": Style(color="red", bold=True)
    t["repr.str"] = initStyle(color = "green",
                              italic = some(false),
                              bold = some(false))          # "repr.str": Style(color="green", italic=False, bold=False)
    t["repr.brace"] = initStyle(bold = some(true))         # "repr.brace": Style(bold=True)
    t["repr.comma"] = initStyle(bold = some(true))         # "repr.comma": Style(bold=True)
    t["repr.ipv4"] = initStyle(bold = some(true),
                               color = "bright_green")    # "repr.ipv4": Style(bold=True, color="bright_green")
    t["repr.ipv6"] = initStyle(bold = some(true),
                               color = "bright_green")    # "repr.ipv6": Style(bold=True, color="bright_green")
    t["repr.eui48"] = initStyle(bold = some(true),
                                color = "bright_green")   # "repr.eui48": Style(bold=True, color="bright_green")
    t["repr.eui64"] = initStyle(bold = some(true),
                                color = "bright_green")   # "repr.eui64": Style(bold=True, color="bright_green")
    t["repr.tag_start"] = initStyle(bold = some(true))     # "repr.tag_start": Style(bold=True)
    t["repr.tag_name"] = initStyle(color = "bright_magenta",
                                   bold = some(true))      # "repr.tag_name": Style(color="bright_magenta", bold=True)
    t["repr.tag_contents"] = initStyle(color = "default")  # "repr.tag_contents": Style(color="default")
    t["repr.tag_end"] = initStyle(bold = some(true))       # "repr.tag_end": Style(bold=True)
    t["repr.attrib_name"] = initStyle(color = "yellow",
                                      italic = some(false)) # "repr.attrib_name": Style(color="yellow", italic=False)
    t["repr.attrib_equal"] = initStyle(bold = some(true))  # "repr.attrib_equal": Style(bold=True)
    t["repr.attrib_value"] = initStyle(color = "magenta",
                                       italic = some(false)) # "repr.attrib_value": Style(color="magenta", italic=False)
    t["repr.number"] = initStyle(color = "cyan",
                                 bold = some(true),
                                 italic = some(false))     # "repr.number": Style(color="cyan", bold=True, italic=False)
    t["repr.number_complex"] = initStyle(color = "cyan",
                                         bold = some(true),
                                         italic = some(false)) # "repr.number_complex": Style(color="cyan", bold=True, italic=False)
    t["repr.bool_true"] = initStyle(color = "bright_green",
                                    italic = some(true))    # "repr.bool_true": Style(color="bright_green", italic=True)
    t["repr.bool_false"] = initStyle(color = "bright_red",
                                     italic = some(true))   # "repr.bool_false": Style(color="bright_red", italic=True)
    t["repr.none"] = initStyle(color = "magenta",
                               italic = some(true))         # "repr.none": Style(color="magenta", italic=True)
    t["repr.url"] = initStyle(underline = some(true),
                              color = "bright_blue",
                              italic = some(false),
                              bold = some(false))          # "repr.url": Style(underline=True, color="bright_blue", italic=False, bold=False)
    t["repr.uuid"] = initStyle(color = "bright_yellow",
                               bold = some(false))         # "repr.uuid": Style(color="bright_yellow", bold=False)
    t["repr.call"] = initStyle(color = "magenta",
                               bold = some(true))          # "repr.call": Style(color="magenta", bold=True)
    t["repr.path"] = initStyle(color = "magenta")         # "repr.path": Style(color="magenta")
    t["repr.filename"] = initStyle(color = "bright_magenta") # "repr.filename": Style(color="bright_magenta")
    # default_styles.py:126-135 — the `bar.*`/`progress.*` family (port
    # Slice 12 / Progress). Consumed by `ProgressBar`/`BarColumn`/
    # `TaskProgressColumn` (progress.nim): the bar's back/complete/finished
    # styles (`bar.back`/`bar.complete`/`bar.finished`, progress_bar.nim:97-100
    # / progress.nim:847-850) and the percentage column style
    # (`progress.percentage`, progress.nim:941/979/994) resolve these via the
    # production `Console` theme (seeded with `DEFAULT_STYLES`). rich's
    # `default_styles.py` defines the bar colors as truecolor `rgb(...)` strings
    # (NOT the named "red"/"green" — `bar.complete`=color="rgb(249,38,114)",
    # `bar.finished`=color="rgb(114,156,31)"), `bar.back` as the 256-palette
    # `grey23` (index 237), and `progress.percentage` as the standard `magenta`
    # (number 5). `Color.parse` (color.nim:509) routes these to
    # `ColorType.truecolor`/`ColorType.eightBit`/`ColorType.standard`, and
    # `Color.getAnsiCodes` under the truecolor console emits `38;2;249;38;114`
    # / `38;5;237` / `35` — matching the golden Python reference
    # byte-for-byte.
    t["bar.back"] = initStyle(color = "grey23")               # "bar.back": Style(color="grey23") -> 256-color 237
    t["bar.complete"] = initStyle(color = "rgb(249,38,114)")  # "bar.complete": Style(color="rgb(249,38,114)") -> truecolor
    t["bar.finished"] = initStyle(color = "rgb(114,156,31)")  # "bar.finished": Style(color="rgb(114,156,31)") -> truecolor
    t["progress.percentage"] = initStyle(color = "magenta")   # "progress.percentage": Style(color="magenta") -> standard 5
    # progress_advanced — the remaining `progress.*` column-text styles
    # (default_styles.py:126-135) consumed by `TimeElapsedColumn`/
    # `MofNCompleteColumn`/`FileSizeColumn` (progress.nim:691-695/854-862/
    # 823-826): `progress.elapsed`=yellow (standard 3, `\x1b[33m`),
    # `progress.download`=green (standard 2, `\x1b[32m`), `progress.filesize`=
    # green (standard 2, `\x1b[32m`). Resolved via the production `Console`
    # theme (seeded with `DEFAULT_STYLES`) through `Console.getStyle` — no
    # custom Theme push needed (faithful to rich 15.0.0's `DEFAULT_STYLES`).
    t["progress.elapsed"] = initStyle(color = "yellow")       # "progress.elapsed": Style(color="yellow") -> standard 3
    t["progress.download"] = initStyle(color = "green")       # "progress.download": Style(color="green") -> standard 2
    t["progress.filesize"] = initStyle(color = "green")       # "progress.filesize": Style(color="green") -> standard 2
    t

discard
