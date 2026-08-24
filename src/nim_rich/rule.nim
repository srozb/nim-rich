## Port of `rich.rule` (rich/rule.py).
##
## `Rule` is a console renderable that draws a horizontal rule (line), with an
## optional title (rule.py:12-114). `rich.console`/`rich.panel`/`rich.table`
## consume it.
##
## Import graph (rich/rule.py:1-9): runtime sibling imports are
## `from .align import AlignMethod` (rule.py:3), `from .cells import cell_len,
## set_cell_size` (rule.py:4), `from .console import Console, ConsoleOptions,
## RenderResult` (rule.py:5), `from .jupyter import JupyterMixin` (rule.py:6),
## `from .measure import Measurement` (rule.py:7), `from .style import Style`
## (rule.py:8), `from .text import Text` (rule.py:9); `from typing import Union`
## (rule.py:1).
##
## wiring (this file):
##   `import segment`  -- re-exports `richbase` (`ConsoleOptions`, `ConsoleHandle`,
##                       `RenderResult`, `RenderableBase`, `JustifyMethod`,
##                       `OverflowMethod`, `RenderableType`, `NO_CHANGE`, …) and
##                       `Style` (segment.py:9, 10-11).
##   `import style`    -- `Style`, `StyleType` (`string or Style`, rule.py:28's
##                       `style: Union[str, Style]` param).
##   `import measure`  -- `Measurement` (rule.py:7, the `__rich_measure__` return).
##   `import text`     -- `Text`, `TextType`, `AlignMethod` (hosted here from
##                       `align`, see text.nim), `StyleValue` (the `Union[str,
##                       Style]` case object, for the `Rule.style` field).
## `cells` (`cell_len`/`set_cell_size`, rule.py:4) and `jupyter` (`JupyterMixin`,
## rule.py:6) are body-only/base deps — `cells` is used in `__init__`/
## `__rich_console__`/`_rule_line` bodies, `JupyterMixin` is the base (modelled
## via `RenderableBase`, since `jupyter.nim` is not yet written, matching how
## `segment.nim` models `Segments`/`SegmentLines`).
##
## `Rule(JupyterMixin)` is `ref object of RenderableBase` (Python `Rule` has
## reference semantics — mutating `__rich_console__` builds `Text` — so a Nim
## `ref` is the faithful mirror). `Rule.title: Union[str, Text]` (rule.py:25-25
## param / rule.py:40-40 field) needs a concrete Nim storage type; `RuleTitle` is a Nim-only case object
## (`rtStr` | `rtText`) with `toRuleTitle*` converters from `string`/`Text`, so
## `initRule("hi")` (str) / `initRule(aText)` (Text) / `initRule()` (default
## `""`) all compile (faithful to `Union[str, Text]`). `Rule.style: Union[str,
## Style]` (rule.py:28,42) uses `text.StyleValue` (the `Union[str, Style]` case
## object); the `style` PARAM is `StyleType = string or Style` (typeclass,
## default `"rule.line"`). Naming: `__init__`->`initRule`, `__repr__`->`repr`,
## `__rich_console__`->`renderConsole`, `__rich_measure__`->`richMeasure`,
## `_rule_line`->`ruleLine`; `end` is backtick-quoted (Nim keyword); `characters`
## keeps its name. Proc bodies mirror the Python source.

import std/[strutils, options]

import segment      # richbase (ConsoleOptions, ConsoleHandle, RenderResult,
                    # RenderableBase, …) + Style.
import style        # Style, StyleType (string or Style).
import measure      # Measurement.
import text         # Text, TextType, AlignMethod, StyleValue.
import cells        # `cellLen` (rule.py:33) + `setCellSize` (rule.py:108) body deps.

type
  RuleTitleKind* = enum
    ## [Nim-only discriminator] for `RuleTitle` (the `Union[str, Text]` value
    ## handle), mirroring `StyleValueKind` but for `Union[str, "Text"]`
    ## (rule.py:25-25, the `title` param annotation). Faithful to
    ## `Union[str, Text]` (no `None` arm).
    rtStr   ## the `str`  arm (`Union[str, Text]`, rule.py:25-25).
    rtText  ## the `Text` arm (`Union[str, Text]`, rule.py:25-25).

  RuleTitle* = object
    ## rich rule.py:25-25 — `Union[str, Text]` (the `title` param annotation)
    ## as a Nim case object (a true tagged union) so it can be stored in the
    ## `Rule.title` field (rule.py:40-40). Faithful to `Union[str, Text]` (the
    ## `title` param at rule.py:25, stored in the field at rule.py:40);
    ## `__rich_console__` distinguishes the arms via `isinstance(self.title,
    ## Text)` (rule.py:65). The `toRuleTitle*` converters accept both legal
    ## variants (`string`, `Text`); `int` is rejected (not in `Union[str, Text]`).
    ## Nim-only handle.
    case kind*: RuleTitleKind
    of rtStr:
      strv*: string   ## the `str`  arm — a plain title string.
    of rtText:
      textv*: Text    ## the `Text` arm — a `Text` instance.

  Rule* = ref object of RenderableBase
    ## rich rule.py:12-114 — `class Rule(JupyterMixin)`: a console renderable to
    ## draw a horizontal rule. `ref object of RenderableBase` (Python `Rule` has
    ## reference semantics; `JupyterMixin` modelled via `RenderableBase` — see
    ## file header). Fields mirror the `__init__` assignments (rule.py:40-44).
    title*: RuleTitle       ## rich rule.py:40-40 — `self.title = title` (`Union[str, Text]`; the `RuleTitle` case object).
    characters*: string     ## rich rule.py:41-41 — `self.characters = characters` (`str`).
    style*: StyleValue      ## rich rule.py:42-42 — `self.style = style` (`Union[str, Style]`; the `text.StyleValue` case object).
    `end`*: string          ## rich rule.py:43-43 — `self.end = end` (`str`). Backtick-quoted (`end` is a Nim keyword).
    align*: AlignMethod     ## rich rule.py:44-44 — `self.align = align` (`AlignMethod`).

converter toRuleTitle*(x: string): RuleTitle =
  ## Accept a `str` as a `Union[str, Text]` value (rule.py:25-25) — the `str` arm.
  ## Lets `initRule("hi")` compile. (`discard` -> `default(RuleTitle)`
  ## = `rtStr` arm); wraps as `RuleTitle(kind: rtStr, strv: x)`.
  result = RuleTitle(kind: rtStr, strv: x)

converter toRuleTitle*(x: Text): RuleTitle =
  ## Accept a `Text` as a `Union[str, Text]` value (rule.py:25-25) — the `Text`
  ## arm. Lets `initRule(aText)` compile. stub; wraps as
  ## `RuleTitle(kind: rtText, textv: x)`.
  result = RuleTitle(kind: rtText, textv: x)

proc initRule*(title: RuleTitle = default(RuleTitle),
               characters: string = "─", style: StyleType = "rule.line",
               `end`: string = "\n", align: AlignMethod = amCenter): Rule =
  ## rich rule.py:23-44 — `Rule.__init__(self, title: Union[str, Text] = "", *,
  ## characters: str = "─", style: Union[str, Style] = "rule.line", end: str =
  ## "\n", align: AlignMethod = "center") -> None`: validate `characters`
  ## (cell_len >= 1) and `align`, then store the fields (rule.py:32-44).
  ## Keyword-only after `title` (Python `*`, rule.py:26). `title: Union[str,
  ## Text] = ""` -> `RuleTitle` (default `default(RuleTitle)` = `rtStr`/`""`,
  ## with `toRuleTitle*` converters so a `str`/`Text` arg compiles);
  ## `style: Union[str, Style] = "rule.line"` -> `StyleType` (typeclass default);
  ## `align: AlignMethod = "center"` -> `amCenter`; `characters` defaults to
  ## `"─"` (U+2500); `end` backtick-quoted. Body needs `cells.cellLen`
  ## (rule.py:33).
  if cellLen(characters) < 1:
    raise newException(ValueError,
      "'characters' argument must have a cell width of at least 1")
  # `align` is the `AlignMethod` enum `{amLeft, amCenter, amRight}` — the Python
  # `align not in ("left","center","right")` guard (rule.py:31-32) is
  # structurally guaranteed (no invalid enum value exists), so it is elided.
  result = Rule()
  result.title = title
  result.characters = characters
  result.style = style
  result.`end` = `end`
  result.align = align

proc repr*(self: Rule): string =
  ## rich rule.py:46-47 — `Rule.__repr__(self) -> str`:
  ## `f"Rule({self.title!r}, {self.characters!r})"`. Overloads `system.repr` on
  ## the `Rule` receiver.
  var titleRepr: string
  case self.title.kind
  of rtStr:
    titleRepr = "'" & self.title.strv & "'"
  of rtText:
    titleRepr = text.repr(self.title.textv)
  result = "Rule(" & titleRepr & ", '" & self.characters & "')"

# Forward declaration: `ruleLine` (rule.py:105-109) is defined below but
# `renderConsole` (rule.py:49-103) calls it for the no-title case (rule.py:62).
proc ruleLine*(self: Rule, charsLen: int, width: int): Text

# Nim-only helpers for `renderConsole` (rule.py:49-103).
proc ruleTitleEmpty(t: RuleTitle): bool =
  ## `not self.title` (rule.py:54): a `str` title is empty iff `""`, a `Text`
  ## title iff `__bool__` (`length == 0`).
  case t.kind
  of rtStr: result = t.strv.len == 0
  of rtText: result = t.textv.length == 0

proc isAllAscii(s: string): bool =
  ## `self.characters.isascii()` (rule.py:52) — every byte < 128 (ASCII).
  for c in s:
    if ord(c) >= 128: return false
  result = true

proc styleValueToOpt(sv: StyleValue): StyleOpt =
  ## `Union[str, Style]` → `Optional[StyleType]` for `Text.append`'s `style`
  ## param (rule.py:80,83,99). `StyleValue` has no `None` arm; map to the
  ## matching `StyleOpt` arm.
  case sv.kind
  of svkStr: result = StyleOpt(kind: sokStr, strv: sv.strv)
  of svkStyle: result = StyleOpt(kind: sokStyle, stv: sv.stv)

method renderConsole*(self: Rule, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich rule.py:49-103 — `Rule.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> RenderResult`: render the rule — a plain
  ## line when no title, else a centered/left/right title flanked by the rule
  ## character (rule.py:52-103). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase. Yields `Text` renderables
  ## (rule.py:62,101) — `self.ruleLine(...)` for the no-title case, a built
  ## `rule_text` for the title case — which the console renders recursively.
  result = @[]
  let width = options.maxWidth
  # rule.py:51-53: ASCII fallback for the rule character + its cell length.
  let characters = if options.asciiOnly() and not isAllAscii(self.characters): "-"
                   else: self.characters
  let charsLen = cellLen(characters)
  # rule.py:54-56: no title → yield the plain rule line.
  if ruleTitleEmpty(self.title):
    result.addRenderable(self.ruleLine(charsLen, width), rrkConsoleRenderable)
    return
  # rule.py:58-63: resolve the title `Text`. `isinstance(self.title, Text)`
  # (rule.py:65) → the `rtText` arm; else `console.render_str(self.title,
  # style="rule.text")` (rule.py:67) — `console.render_str` is on `Console`
  # (unavailable via `ConsoleHandle`), so the `rtStr` arm is approximated by
  # `initText(str, style="rule.text")` (markup/emoji unparsed; the theme style
  # "rule.text" resolves to null at render time, the documented
  # `console.get_style` approximation).
  var titleText: Text
  case self.title.kind
  of rtText:
    titleText = self.title.textv
  of rtStr:
    titleText = initText(self.title.strv, style = "rule.text")
  # rule.py:69-70: flatten newlines and expand tabs (mutates the title `Text`,
  # faithfully mirroring Python's `title_text = self.title` reference alias).
  titleText.setPlain(titleText.plain.replace("\n", " "))
  titleText.expandTabs()
  # rule.py:71-74: truncate-width guard.
  let requiredSpace = if self.align == amCenter: 4 else: 2
  let truncateWidth = max(0, width - requiredSpace)
  if truncateWidth == 0:
    result.addRenderable(self.ruleLine(charsLen, width), rrkConsoleRenderable)
    return
  # rule.py:76-101: build `rule_text` per `self.align`.
  var ruleText = initText("", `end` = self.`end`)
  if self.align == amCenter:
    titleText.truncate(truncateWidth, some(omEllipsis))
    let sideWidth = (width - cellLen(titleText.plain)) div 2
    let left = initText(characters.repeat(max(0, sideWidth div charsLen + 1)))
    left.truncate(max(0, sideWidth - 1))
    let rightLength = width - cellLen(left.plain) - cellLen(titleText.plain)
    let right = initText(characters.repeat(max(0, sideWidth div charsLen + 1)))
    right.truncate(max(0, rightLength))
    discard ruleText.append(left.plain & " ", styleValueToOpt(self.style))
    discard ruleText.append(titleText)
    discard ruleText.append(" " & right.plain, styleValueToOpt(self.style))
  elif self.align == amLeft:
    titleText.truncate(truncateWidth, some(omEllipsis))
    discard ruleText.append(titleText)
    discard ruleText.append(" ")
    discard ruleText.append(characters.repeat(max(0, width - ruleText.cellLen())),
                             styleValueToOpt(self.style))
  elif self.align == amRight:
    titleText.truncate(truncateWidth, some(omEllipsis))
    discard ruleText.append(characters.repeat(max(0, width - titleText.cellLen() - 1)),
                             styleValueToOpt(self.style))
    discard ruleText.append(" ")
    discard ruleText.append(titleText)
  # rule.py:102-103: force the rule text to exactly `width` cells, then yield.
  ruleText.setPlain(setCellSize(ruleText.plain, width))
  result.addRenderable(ruleText, rrkConsoleRenderable)

proc ruleLine*(self: Rule, charsLen: int, width: int): Text =
  ## rich rule.py:105-109 — `Rule._rule_line(self, chars_len: int, width: int)
  ## -> Text`: build a plain rule line `Text` of `characters` repeated to `width`
  ## (rule.py:106-109). Mirrors the private `_rule_line` (exported as `ruleLine`,
  ## like `segment.nim`/`text.nim` export former-`_` helpers). Body needs
  ## `cells.setCellSize` (rule.py:108).
  let repeated = self.characters.repeat((width div charsLen) + 1)
  var t: Text
  case self.style.kind
  of svkStr:
    t = initText(repeated, self.style.strv)
  of svkStyle:
    t = initText(repeated, self.style.stv)
  t.truncate(width)
  t.setPlain(setCellSize(t.plain, width))
  result = t

proc richMeasure*(self: Rule, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich rule.py:111-114 — `Rule.__rich_measure__(self, console: "Console",
  ## options: "ConsoleOptions") -> Measurement`: `return Measurement(1, 1)`
  ## (rule.py:114) — a rule always measures 1 cell. The richbase `ConsoleHandle`/
  ## `ConsoleOptions` placeholders; `Measurement` from `measure.nim`. port
  ## stub.
  result = Measurement(minimum: 1, maximum: 1)
