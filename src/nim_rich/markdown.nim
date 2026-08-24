## Nim port of `rich.markdown` (rich/markdown.py, 802 lines).
##
## `markdown` renders Markdown to the console: the `Markdown(JupyterMixin)`
## renderable (markdown.py:513-704) drives a markdown-it token stream through a
## tree of `MarkdownElement` subclasses (`Paragraph`/`Heading`/`CodeBlock`/
## `BlockQuote`/`HorizontalRule`/`TableElement`/…/`Link`/`ImageItem`,
## markdown.py:25-461), managed by a `MarkdownContext` (markdown.py:465-510).
##
## Import graph (rich/markdown.py:1-21): runtime stdlib imports are `sys`,
## `dataclasses.dataclass`, `typing.{ClassVar, Iterable, get_args}` (markdown.py:1-
## 5); the markdown-it import is `from markdown_it import MarkdownIt` +
## `from markdown_it.token import Token` (markdown.py:7-8); rich sibling imports
## are `from rich.table import Table` (markdown.py:10), `from . import box`
## (markdown.py:11), `from ._loop import loop_first` (markdown.py:12),
## `from ._stack import Stack` (markdown.py:13), `from .console import Console,
## ConsoleOptions, JustifyMethod, RenderResult` (markdown.py:14), `from
## .containers import Renderables` (markdown.py:15), `from .jupyter import
## JupyterMixin` (markdown.py:16, the base), `from .rule import Rule`
## (markdown.py:17), `from .segment import Segment` (markdown.py:18),
## `from .style import Style, StyleStack` (markdown.py:19), `from .syntax
## import Syntax` (markdown.py:20), `from .text import Text, TextType`
## (markdown.py:21).
##
## wiring (this file):
##   `import std/options` — `Option[JustifyMethod]`/`Option[string]`/
##                           `Option[TableHeaderElement]`/… field/param types.
##   `import std/sets`     — `HashSet[string]` (the `inlines` classvar set).
##   `import std/tables`   — `Table`/`initTable`/`toTable` (the `elements`
##                           classvar registry + `levelAlign`).
##   `import std/strutils` — `strip` (the `rstrip` of a code block's text,
##                           markdown.py:183). Body dep (used in ported bodies).
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                           `ConsoleOptions`, `RenderResult`, `JustifyMethod`,
##                           `RenderableBase`, `RenderableType`, …) + `Segment`
##                           (markdown.py:18) + `Style` (re-exported).
##   `import style`        — `Style`, `StyleType`, `StyleStack` (markdown.py:19).
##   `import text`         — `Text`, `TextType` (markdown.py:21) + `StyleValue`
##                           (the storable `Union[str, Style]` handle for the
##                           `Markdown.style` field).
##   `import jupyter`      — `JupyterMixin` (markdown.py:16, the `Markdown`
##                           base — now present, so `Markdown = ref object of
##                           JupyterMixin`, faithful to `class
##                           Markdown(JupyterMixin)`).
##   `import containers`   — `Renderables` (markdown.py:15; the
##                           `BlockQuote.elements`/`ListItem.elements` fields).
##   `import syntax`       — `Syntax` (markdown.py:20; the `MarkdownContext.
##                           syntaxField: Option[Syntax]` field — written this
##                           round, so `import syntax` resolves).
##   `import rule`         — `Rule` (markdown.py:17; used in
##                           `HorizontalRule.renderConsole` via `initRule`).
##   `import table`        — `Table` (markdown.py:10; used in
##                           `TableElement.renderConsole` via `initTable`).
##   `import box`          — `box.SIMPLE` (markdown.py:11; used in
##                           `TableElement.renderConsole` as the table box).
##
## `markdown_it` (`MarkdownIt`/`Token`) is an external library NOT ported; the
## `Token` type is a Nim-native port of the block-level subset of
## `markdown_it.token.Token` (`ref object of RootObj` with the full field set
## `type`/`tag`/`nesting`/`level`/`content`/`markup`/`info`/`hidden`/`attrs`/
## `children`); `parseMarkdownBlocks`/`parseInline` populate it and the element
## `create` classmethods / `Markdown.parsed` / `flattenTokens` consume it. The
## private `_*` helpers: the `_loop` module is NOT ported — `loop_first`
## (markdown.py:12) is a BODY-only dep (`ListItem.render_bullet`/`render_number`
## iterate `loop_first(lines)`, markdown.py:378,406), modelled inline by an index
## flag (no `_loop.nim`); `_stack.Stack` (markdown.py:13) IS ported as the
## generic `Stack*[T]` (a faithful port of `rich._stack.Stack` with
## `top`/`push`/`pop`/`len`/`[]`), the type of `MarkdownContext.stack:
## Stack[MarkdownElement]`. `Console`/`ConsoleOptions`/
## `JustifyMethod`/`RenderResult` (markdown.py:14) are supplied via richbase
## placeholders through `segment`; the console flows as `ConsoleHandle` (the
## renderConsole concept param), so `console.nim` is NOT imported (mirroring how
## `live_render`/`status`/`progress_bar` model rich's `Console` import).
## `dataclasses.dataclass` (markdown.py:4) is realised natively — the
## `@dataclass HeadingFormat` (markdown.py:127) is ported as the
## `HeadingFormat` value `object` (no decorator needed in Nim).
## `typing.get_args` (markdown.py:326, a runtime `JustifyMethod` assertion)
## is not needed (Nim's enum constrains the values at compile time); `sys`
## (markdown.py:3) is a `__main__`-only dep (`sys.stdin.read()` at
## markdown.py:775) — neither is ported.
##
## `MarkdownElement` (markdown.py:25-79) → `ref object of RenderableBase` (the
## elements are console renderables — yielded from `Markdown.__rich_console__`
## via `console.render(element, …)`, markdown.py:693; so they satisfy
## `ConsoleRenderable`). The `new_line: ClassVar[bool] = True` classvar → a
## per-instance `newLine*` field (overridden `False` by `HorizontalRule`/
## `ImageItem`). The element subclasses are `ref object of MarkdownElement` (or
## `of TextElement`); their classvar `style_name` → a `styleName*` field. The
## `create` classmethods → `proc create*(T: typedesc[<Element>], markdown:
## Markdown, token: Token): <Element>` (the classmethod `cls` → `typedesc`).
## `HeadingFormat` (markdown.py:128, `@dataclass`) → a value `object`.
## `MarkdownContext` (markdown.py:465) → `ref object of RootObj`. `Markdown(
## JupyterMixin)` (markdown.py:513) → `ref object of JupyterMixin`. The
## `Markdown.elements`/`inlines` ClassVars → module `let`s (a class attribute is
## a module-level value); `Heading.LEVEL_ALIGN` → `let levelAlign`. Naming:
## `__init__`→`init<Element>`; `on_enter`→`onEnter`; `on_text`→`onText`;
## `on_leave`→`onLeave`; `on_child_close`→`onChildClose`; `__rich_console__`→
## `renderConsole`; `create`→`create`; `_flatten_tokens`→`flattenTokens`;
## `current_style`→`currentStyle`; `enter_style`→`enterStyle`;
## `leave_style`→`leaveStyle`; `render_bullet`→`renderBullet`;
## `render_number`→`renderNumber`; the `_`-prefixed fields (`_syntax`) →
## `syntaxField`. Proc bodies are ported (the element methods + parser +
## `initMarkdown`/`flattenTokens` implement markdown.py).

import std/options
import std/sets
import std/tables
import std/strutils

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # JustifyMethod, RenderableBase, RenderableType, …) +
                    # Segment + Style.
import style        # Style, StyleType, StyleStack (markdown.py:19).
import text         # Text, TextType (markdown.py:21) + StyleValue (the
                    # Union[str, Style] field handle for Markdown.style).
import jupyter      # JupyterMixin (markdown.py:16, the Markdown base).
import containers   # Renderables (markdown.py:15; BlockQuote.elements /
                    # ListItem.elements fields).
import syntax       # Syntax (markdown.py:20; MarkdownContext.syntaxField).
import padding      # Padding (markdown.py:186 `Syntax(code, …, padding=1)` modelled
                    # as a real `Padding(rendered, (1,1,1,1))` wrapper around
                    # the plain `markdown.code_block`-styled `Text` in
                    # `CodeBlock.renderConsole`; rich padding.py:19-135).
import rule         # Rule (markdown.py:17; HorizontalRule.renderConsole body
                    # dep — graph faithfulness, accepts the unused warning).
import table        # Table (markdown.py:10; TableElement.renderConsole body
                    # dep — graph faithfulness, accepts the unused warning).
import box          # box.SIMPLE (markdown.py:11; TableElement.renderConsole
                    # body dep — graph faithfulness, accepts the unused warning).
import api_types    # RenderableValue + the `toRenderableValue` converters (string/
                    # RenderableBase → RenderableValue) — the dispatch loop's
                    # `console.render(toRenderableValue(element), …)` (markdown.py:693)
                    # + TableElement.renderConsole body dep (markdown.py:264
                    # `table.add_row(*[c.content …])`, modelled via direct
                    # `Column.rawCells.add`); accepts the unused warning.
import console_api  # the `{.base.}` dispatch methods on `ConsoleHandle` —
                    # `getStyle`/`render`/`renderLines`/`measure` (rich
                    # console.py:1294-1498). The Slice 5c renderers call
                    # `console.getStyle("markdown.{tag}", default="none")`
                    # (markdown.py:504/225) and `console.render(element,
                    # options)` (markdown.py:693) on the `ConsoleHandle` param;
                    # importing the leaf `console_api` makes those methods
                    # visible WITHOUT importing `console` (mirrors `table.nim`/
                    # `panel.nim`), and the real `Console` override drives the
                    # theme-style resolution + render pipeline. No cycle
                    # (`console_api` imports only richbase/style/segment/measure/
                    # api_types).

type
  Token* = ref object of RootObj
    ## Slice 5a — the nim-rich Markdown token model, a faithful port of the
    ## block-level subset of `markdown_it.token.Token` (markdown.py:8). The
    ## fields mirror `markdown_it.Token`: `type`/`tag`/`nesting`/`level`/`content`/
    ## `markup`/`info`/`hidden`/`attrs`/`children`. `parseMarkdownBlocks` populates
    ## the block-level tokens (ATX heading, fence, thematic break, paragraph,
    ## blank-line separation); inline `children` remain `@[]` (Slice 5b parses
    ## them). `attrs` is `Option[tables.Table[string, string]]` (qualified to avoid
    ## the `table.Table` clash) — `none` when absent (markdown_it's `attrs` is
    ## `None`). `type` is a Nim keyword, so the field is declared/accessed as
    ## `` `type` ``. `ref object of RootObj` (not a renderable) is retained for
    ## the existing element `create` classmethod / `Markdown.parsed` /
    ## `flattenTokens` signatures.
    `type`*: string
      ## markdown_it `Token.type` — the token type name (e.g. `"heading_open"`,
      ## `"inline"`, `"heading_close"`, `"paragraph_open"`/`"_close"`, `"fence"`,
      ## `"hr"`).
    tag*: string
      ## markdown_it `Token.tag` — the HTML tag (e.g. `"h1"`..`"h6"`, `"p"`,
      ## `"hr"`, `"code"` for fences, `""` for `inline`/self tokens).
    nesting*: int
      ## markdown_it `Token.nesting` — `+1` open, `-1` close, `0` self-closing
      ## (`inline`/`fence`/`hr`).
    level*: int
      ## markdown_it `Token.level` — `0` for top-level block tokens, `1` for the
      ## `inline` child of a block.
    content*: string
      ## markdown_it `Token.content` — `inline` text (heading/paragraph) or the
      ## fence code body; `""` for open/close/self tokens.
    markup*: string
      ## markdown_it `Token.markup` — the source markup (`"#"`×level for
      ## headings, the opening fence run, the thematic-break marker character,
      ## `""` for paragraphs/`inline`).
    info*: string
      ## markdown_it `Token.info` — the fence info string (rest of the opening
      ## fence line, verbatim/untrimmed); `""` otherwise.
    hidden*: bool
      ## markdown_it `Token.hidden` — whether the token is hidden; `false` for
      ## the Slice 5a subset.
    attrs*: Option[tables.Table[string, string]]
      ## markdown_it `Token.attrs` — token attributes; `none` for the Slice 5a
      ## subset (headings/paragraphs/fences/hr carry no attributes). Qualified
      ## `tables.Table` to avoid the `table.Table` clash.
    children*: seq[Token]
      ## markdown_it `Token.children` — inline sub-tokens of an `inline` token.
      ## Slice 5a leaves this `@[]` (Slice 5b parses `**bold**`/`code`/… into
      ## children and `flattenTokens` splices them).

  Stack*[T] = ref object of RootObj
    ## A faithful port of `rich._stack.Stack` (markdown.py:13, `_stack.Stack` —
    ## a `list` subclass). `Stack[MarkdownElement]` is the element `code_stack`
    ## driven by `Markdown.renderConsole` (markdown.py:679/687/692).
    ## `top`=`items[^1]` (rich `self[-1]`); `push`=`items.add` (rich `append`);
    ## `pop` returns the popped item (rich `list.pop()`); `len`/`[]` mirror the
    ## `not stack`/`stack and …` truthiness checks (markdown.py:688-689).
    items*: seq[T]
      ## rich `_stack.Stack` underlying `list` — the element stack.

  ElementFactory* = proc(markdown: Markdown, token: Token): MarkdownElement {.closure.}
    ## [Nim-only] the callable analogue of `ClassVar[dict[str, type[
    ## MarkdownElement]]]` (markdown.py:515-531, `Markdown.elements`): a
    ## token-type name → element-factory map. A `type[MarkdownElement]` (a
    ## class) is not storable in Nim; the factory `proc(markdown, token):
    ## MarkdownElement` is the faithful callable form (`element_class.create(
    ## self, token)`, markdown.py:683). The `elements` registry is an
    ## empty `Table[string, ElementFactory]` placeholder (body populates the
    ## 16 token-type→factory entries).

  MarkdownElement* = ref object of RenderableBase
    ## rich markdown.py:25-79 — `class MarkdownElement`: the base class for
    ## markdown elements. `ref object of RenderableBase` (the elements are
    ## console renderables — yielded from `Markdown.__rich_console__` via
    ## `console.render(element, …)`, markdown.py:693, so they satisfy
    ## `ConsoleRenderable`). The `new_line: ClassVar[bool] = True` classvar → a
    ## per-instance `newLine` field (overridden `False` by `HorizontalRule`/
    ## `ImageItem`).
    newLine*: bool
      ## rich markdown.py:26 — `new_line: ClassVar[bool] = True`: whether the
      ## element ends with a new line (markdown.py:702). A field so subclasses
      ## override it (`HorizontalRule`/`ImageItem` set `False`).

  UnknownElement* = ref object of MarkdownElement
    ## rich markdown.py:82-88 — `class UnknownElement(MarkdownElement)`: an
    ## unknown element (no methods — inherits the base `create`/`on_*`/
    ## `renderConsole`).

  TextElement* = ref object of MarkdownElement
    ## rich markdown.py:91-104 — `class TextElement(MarkdownElement)`: base
    ## class for elements that render text. The `style_name = "none"` classvar →
    ## a `styleName` field (overridden per subclass); `style`/`text` are set in
    ## `onEnter`.
    styleName*: string
      ## rich markdown.py:93 — `style_name = "none"` (classvar; overridden per subclass, e.g. `Paragraph`⇒`"markdown.paragraph"`).
    style*: Style
      ## rich markdown.py:97 — `self.style = context.enter_style(self.style_name)` (set in `onEnter`; the `Style` for the element).
    text*: Text
      ## rich markdown.py:98 — `self.text = Text(justify="left")` (set in `onEnter`; the rendered `Text`).

  Paragraph* = ref object of TextElement
    ## rich markdown.py:107-124 — `class Paragraph(TextElement)`: a paragraph.
    ## `style_name = "markdown.paragraph"`. Adds a `justify` field set from
    ## `markdown.justify or "left"` (markdown.py:114-118).
    justify*: JustifyMethod
      ## rich markdown.py:117 — `self.justify = justify` (`JustifyMethod`; from `markdown.justify or "left"`, markdown.py:115).

  HeadingFormat* = object
    ## rich markdown.py:127-130 — `@dataclass class HeadingFormat`: a heading's
    ## justify + style (`Heading.LEVEL_ALIGN` maps a tag to one). A value
    ## `object` (Python `@dataclass` ⇒ Nim `object`).
    justify*: JustifyMethod
      ## rich markdown.py:128 — `justify: JustifyMethod = "left"`.
    style*: string
      ## rich markdown.py:129 — `style: str = ""`.

  Heading* = ref object of TextElement
    ## rich markdown.py:133-164 — `class Heading(TextElement)`: a heading.
    ## `style_name = f"markdown.{tag}"` (set in `__init__`). Adds a `tag` field.
    tag*: string
      ## rich markdown.py:155 — `self.tag = tag` (the heading tag, e.g. `"h1"`).

  CodeBlock* = ref object of TextElement
    ## rich markdown.py:167-189 — `class CodeBlock(TextElement)`: a code block
    ## with syntax highlighting. `style_name = "markdown.code_block"`. Adds
    ## `lexerName`/`theme`.
    lexerName*: string
      ## rich markdown.py:179 — `self.lexer_name = lexer_name` (the fence info lexer, or `"text"`).
    theme*: string
      ## rich markdown.py:180 — `self.theme = theme` (the pygments code theme, from `markdown.code_theme`).

  BlockQuote* = ref object of TextElement
    ## rich markdown.py:192-215 — `class BlockQuote(TextElement)`: a block quote.
    ## `style_name = "markdown.block_quote"`. Holds nested `elements` (a
    ## `Renderables`).
    elements*: Renderables
      ## rich markdown.py:198 — `self.elements = Renderables()` (the nested child renderables; `Renderables` from `containers.nim`).

  HorizontalRule* = ref object of MarkdownElement
    ## rich markdown.py:218-228 — `class HorizontalRule(MarkdownElement)`: a
    ## horizontal rule. `new_line = False` (markdown.py:221). No fields.

  TableElement* = ref object of MarkdownElement
    ## rich markdown.py:231-269 — `class TableElement(MarkdownElement)`: a
    ## markdown table (`table_open`). Holds a `header` + `body`.
    header*: Option[TableHeaderElement]
      ## rich markdown.py:235 — `self.header: TableHeaderElement | None = None` (`Option[TableHeaderElement]`, default `none(TableHeaderElement)`).
    body*: Option[TableBodyElement]
      ## rich markdown.py:236 — `self.body: TableBodyElement | None = None` (`Option[TableBodyElement]`, default `none(TableBodyElement)`).

  TableHeaderElement* = ref object of MarkdownElement
    ## rich markdown.py:272-281 — `class TableHeaderElement(MarkdownElement)`:
    ## a table header (`thead_open`). Holds a single `row`.
    row*: Option[TableRowElement]
      ## rich markdown.py:276 — `self.row: TableRowElement | None = None` (`Option[TableRowElement]`).

  TableBodyElement* = ref object of MarkdownElement
    ## rich markdown.py:284-293 — `class TableBodyElement(MarkdownElement)`: a
    ## table body (`tbody_open`). Holds the `rows`.
    rows*: seq[TableRowElement]
      ## rich markdown.py:288 — `self.rows: list[TableRowElement] = []`.

  TableRowElement* = ref object of MarkdownElement
    ## rich markdown.py:296-305 — `class TableRowElement(MarkdownElement)`: a
    ## table row (`tr_open`). Holds the `cells`.
    cells*: seq[TableDataElement]
      ## rich markdown.py:300 — `self.cells: list[TableDataElement] = []`.

  TableDataElement* = ref object of MarkdownElement
    ## rich markdown.py:308-337 — `class TableDataElement(MarkdownElement)`: a
    ## table cell (`td_open`/`th_open`). Adds `content`/`justify`.
    content*: Text
      ## rich markdown.py:333 — `self.content = Text("", justify=justify)` (the cell's `Text`).
    justify*: JustifyMethod
      ## rich markdown.py:334 — `self.justify = justify` (the cell's text-align, from the `style` attr).

  ListElement* = ref object of MarkdownElement
    ## rich markdown.py:340-372 — `class ListElement(MarkdownElement)`: a list
    ## (`bullet_list_open`/`ordered_list_open`). Adds `items`/`listType`/
    ## `listStart`.
    items*: seq[ListItem]
      ## rich markdown.py:357 — `self.items: list[ListItem] = []`.
    listType*: string
      ## rich markdown.py:358 — `self.list_type = list_type` (e.g. `"bullet_list_open"`/`"ordered_list_open"`).
    listStart*: Option[int]
      ## rich markdown.py:359 — `self.list_start = list_start` (`Optional[int]`; the ordered-list start number, `None` ⇒ 1).

  ListItem* = ref object of TextElement
    ## rich markdown.py:375-449 — `class ListItem(TextElement)`: an item in a
    ## list. `style_name = "markdown.item"`. Holds nested `elements`.
    elements*: Renderables
      ## rich markdown.py:381 — `self.elements = Renderables()` (the nested child renderables).

  Link* = ref object of TextElement
    ## rich markdown.py:452-461 — `class Link(TextElement)`: a link. Adds `href`
    ## (the `text` field is inherited from `TextElement`).
    href*: string
      ## rich markdown.py:460 — `self.href = href` (the link URL).

  ImageItem* = ref object of TextElement
    ## rich markdown.py:464-494 — `class ImageItem(TextElement)`: a placeholder
    ## for an image. `new_line = False` (markdown.py:470). Adds `destination`/
    ## `hyperlinks`/`link`.
    destination*: string
      ## rich markdown.py:485 — `self.destination = destination` (the image src).
    hyperlinks*: bool
      ## rich markdown.py:486 — `self.hyperlinks = hyperlinks` (whether hyperlinks are enabled, from `markdown.hyperlinks`).
    link*: Option[string]
      ## rich markdown.py:487 — `self.link: str | None = None` (the current style's link, set in `onEnter`; `Option[string]`).

  MarkdownContext* = ref object of RootObj
    ## rich markdown.py:465-510 — `class MarkdownContext`: manages the console
    ## render state during a `Markdown.__rich_console__` render. `ref object of
    ## RootObj` (not a renderable). Fields mirror `__init__` (markdown.py:478-484).
    console*: ConsoleHandle
      ## rich markdown.py:478 — `self.console = console` (`Console`; flows as `ConsoleHandle` from `renderConsole`).
    options*: ConsoleOptions
      ## rich markdown.py:479 — `self.options = options` (`ConsoleOptions`).
    styleStack*: StyleStack
      ## rich markdown.py:480 — `self.style_stack = StyleStack(style)` (`StyleStack` from `style.nim`).
    stack*: Stack[MarkdownElement]
      ## rich markdown.py:481 — `self.stack = Stack()` (`Stack[MarkdownElement]`; the provisional `Stack` handle).
    syntaxField*: Option[Syntax]
      ## rich markdown.py:482-484 — `self._syntax: Syntax | None = None` (built if `inline_code_lexer` is set; `Option[Syntax]`; renamed `_syntax`→`syntaxField`).

  Markdown* = ref object of JupyterMixin
    ## rich markdown.py:513-704 — `class Markdown(JupyterMixin)`: a Markdown
    ## renderable. `ref object of JupyterMixin` (the base now present, faithful
    ## to `class Markdown(JupyterMixin)`). Fields mirror `__init__`
    ## (markdown.py:549-567); the `elements`/`inlines` ClassVars are module
    ## `let`s (not instance fields).
    markup*: string
      ## rich markdown.py:556 — `self.markup = markup` (`str`).
    parsed*: seq[Token]
      ## rich markdown.py:557 — `self.parsed = parser.parse(markup)` (`List[Token]`; `seq[Token]`; empty — the markdown-it parse is a Body).
    codeTheme*: string
      ## rich markdown.py:558 — `self.code_theme = code_theme` (`str`; default `"monokai"`).
    justify*: Option[JustifyMethod]
      ## rich markdown.py:559 — `self.justify: JustifyMethod | None = justify` (`Optional[JustifyMethod]`, default `none(JustifyMethod)`).
    style*: StyleValue
      ## rich markdown.py:560 — `self.style = style` (`Union[str, Style]`; the `StyleValue` field; the `__init__` param `style: str | Style = "none"` keeps the `StyleType` typeclass).
    hyperlinks*: bool
      ## rich markdown.py:561 — `self.hyperlinks = hyperlinks` (`bool`; default `True`).
    inlineCodeLexer*: Option[string]
      ## rich markdown.py:562 — `self.inline_code_lexer = inline_code_lexer` (`Optional[str]`; `Option[string]`).
    inlineCodeTheme*: Option[string]
      ## rich markdown.py:563 — `self.inline_code_theme = inline_code_theme or code_theme` (`Optional[str]`; `Option[string]`).

# ---------------------------------------------------------------------------
# Stack[T] ops — rich `_stack.Stack` (a `list` subclass)
# ---------------------------------------------------------------------------
## `Stack[T]` (declared above) is a faithful port of `rich._stack.Stack`
## (markdown.py:13) — a `list` subclass. These ops mirror the `list` API used
## by `Markdown.renderConsole` (markdown.py:679/687/688/692): `top` (`self[-1]`),
## `push` (`append`), `pop` (`list.pop()` — returns the popped item), `len`
## (`not stack`/`stack and …` truthiness). `initMarkdownContext` allocates the
## stack via `new(result.stack)` (a fresh `Stack[MarkdownElement]` with
## `items = @[]`).

proc push*[T](s: Stack[T], item: T) =
  ## rich `_stack.Stack.push` — `self.append(item)` (list `append`).
  s.items.add(item)

proc pop*[T](s: Stack[T]): T =
  ## rich `_stack.Stack.pop` — inherits `list.pop()`: return the last item and
  ## remove it (NOT the new current — cf. `StyleStack.pop`, which returns the
  ## new current; `Stack.pop` is the list-pop analogue).
  result = s.items[^1]
  s.items.setLen(s.items.len - 1)

proc top*[T](s: Stack[T]): T =
  ## rich `_stack.Stack.top` — `self[-1]` (the last item; the current element).
  result = s.items[^1]

proc len*[T](s: Stack[T]): int =
  ## rich `_stack.Stack.__len__` — the `not stack`/`stack and …` truthiness
  ## checks (markdown.py:688-689) test `len == 0`/`> 0`.
  result = s.items.len

let levelAlign* = [("h1", jmCenter), ("h2", jmLeft), ("h3", jmLeft),
                           ("h4", jmLeft), ("h5", jmLeft), ("h6", jmLeft)].toTable()
  ## rich markdown.py:136-142 — `Heading.LEVEL_ALIGN: ClassVar[dict[str,
  ## JustifyMethod]]`: tag → heading justify (`h1`⇒`"center"`, `h2`-`h6`⇒
  ## `"left"`). The `ClassVar` becomes a module `let` `Table[string,
  ## JustifyMethod]`.

# `let elements*` — the populated token-type → element-factory registry — is
# defined BELOW, after the element `create` procs (it calls
# `Paragraph.create`/`Heading.create`/`CodeBlock.create`/`HorizontalRule.create`,
# which must be in scope), right before `Markdown.renderConsole` (its sole
# consumer). rich markdown.py:515-531 — `Markdown.elements: ClassVar[dict[str,
# type[MarkdownElement]]]`; the `ClassVar[dict[str, type[…]]]` is a module `let`
# `Table[string, ElementFactory]` (a `type[MarkdownElement]` is not storable in
# Nim; the factory `proc(markdown, token): MarkdownElement` is the faithful
# callable form — `element_class.create(self, token)`, markdown.py:683).

let inlines* = ["em", "strong", "code", "s"].toHashSet()
  ## rich markdown.py:533 — `Markdown.inlines = {"em", "strong", "code", "s"}`:
  ## the inline style tags. The `ClassVar` set becomes a module `let`
  ## `HashSet[string]`. Verbatim 4-element set.

# ---------------------------------------------------------------------------
# Forward declarations — markdown.py initializers / context style helpers
# ---------------------------------------------------------------------------
# Nim (2.2.x) has no implicit module-level forward referencing: a proc used
# before its definition needs an explicit forward declaration. The element
# `initX` initializers and the `MarkdownContext` style-stack helpers
# (`currentStyle`/`enterStyle`/`leaveStyle`) are defined later in this file (next
# to their rich source sections) but called earlier — e.g. `TextElement.onEnter`
# calls `enterStyle`/`initText`, `Paragraph.create` calls `initParagraph`, …,
# `ImageItem.onEnter` calls `currentStyle`. These forward declarations are exact
# signatures matching the later definitions; they let the calls resolve with no
# behaviour change (the bodies remain unchanged below).

proc initParagraph*(justify: JustifyMethod): Paragraph
proc initHeading*(tag: string): Heading
proc initCodeBlock*(lexerName: string, theme: string): CodeBlock
proc initTableDataElement*(justify: JustifyMethod): TableDataElement
proc initListElement*(listType: string, listStart: Option[int]): ListElement
proc initLink*(text: string, href: string): Link
proc initImageItem*(destination: string, hyperlinks: bool): ImageItem
proc currentStyle*(self: MarkdownContext): Style
proc enterStyle*(self: MarkdownContext, styleName: StyleType): Style
proc leaveStyle*(self: MarkdownContext): Style

# ---------------------------------------------------------------------------
# MarkdownElement base — markdown.py:25-79
# ---------------------------------------------------------------------------

proc create*(T: typedesc[MarkdownElement], markdown: Markdown,
             token: Token): MarkdownElement =
  ## rich markdown.py:28-39 — `MarkdownElement.create(cls, markdown: Markdown,
  ## token: Token) -> MarkdownElement` (classmethod): the default factory —
  ## `return cls()` (markdown.py:38). `T: typedesc[MarkdownElement]` (the
  ## classmethod `cls`).
  # `return cls()` — allocate the subtype `T` with the `new_line = True`
  # classvar (markdown.py:26). [body deferral] `HorizontalRule`/
  # `ImageItem` override `new_line = False`, but neither declares a `create`
  # override in the frozen tree, so this base factory yields `newLine = true`
  # for them (the `False` override is reached only via their own `init*`, which
  # `cls()` cannot call); `renderConsole` — the sole `new_line` consumer — is
  # itself gated on `console.render`/`Stack` (deferred), so the divergence is
  # unobserved in body.
  result = T(newLine: true)

method onEnter*(self: MarkdownElement, context: MarkdownContext) {.base.} =
  ## rich markdown.py:41-46 — `MarkdownElement.on_enter(self, context:
  ## MarkdownContext) -> None`: called when the node is entered (empty by
  ## default). A `method` (not `proc`) so the dispatch loop's
  ## `element.onEnter(context)` (markdown.py:682) dispatches on the element's
  ## runtime subtype — the `Paragraph`/`Heading`/`CodeBlock` (`TextElement`)
  ## overrides run, not the base no-op.
  discard  # faithful no-op: rich `on_enter` body is empty (markdown.py:41-46); a hook overridden by subclasses (e.g. `TextElement.onEnter`).

method onText*(self: MarkdownElement, context: MarkdownContext, text: string) {.base.} =
  ## rich markdown.py:48-53 — `MarkdownElement.on_text(self, context:
  ## MarkdownContext, text: TextType) -> None`: called when text is parsed (empty
  ## by default). A `method` so `element.onText(context, text)` (markdown.py:690)
  ## dispatches on the runtime subtype — the `TextElement`/`TableDataElement`
  ## overrides run. `text: string` (the live str path; the `Text` highlight arm
  ## of `MarkdownContext.onText` is deferred with `Syntax` — Slice 6 — so
  ## `onText` takes the str variant only: a `string or Text` typeclass would
  ## break `method` dispatch, so the `Text` arm is deferred with `Syntax`).
  discard  # faithful no-op: rich `on_text` body is empty (markdown.py:48-53); a hook overridden by subclasses (e.g. `TextElement.onText`).

method onLeave*(self: MarkdownElement, context: MarkdownContext) {.base.} =
  ## rich markdown.py:55-60 — `MarkdownElement.on_leave(self, context:
  ## MarkdownContext) -> None`: called when the parser leaves the element (empty
  ## by default). A `method` so `element.onLeave(context)` (markdown.py:701)
  ## dispatches on the runtime subtype — the `TextElement.onLeave` override
  ## (pops the style stack) runs.
  discard  # faithful no-op: rich `on_leave` body is empty (markdown.py:55-60); a hook overridden by subclasses (e.g. `TextElement.onLeave`).

method onChildClose*(self: MarkdownElement, context: MarkdownContext,
                     child: MarkdownElement): bool {.base.} =
  ## rich markdown.py:62-74 — `MarkdownElement.on_child_close(self, context:
  ## MarkdownContext, child: MarkdownElement) -> bool`: called when a child
  ## element is closed; `return True` to render the child (markdown.py:73). A
  ## `method` so `context.stack.top.onChildClose(context, element)`
  ## (markdown.py:688) dispatches on the PARENT's runtime subtype — the
  ## `BlockQuote`/`ListElement`/`TableElement`/… overrides (which absorb the
  ## child & return `False`) run, not the base `True`.
  result = true

method renderConsole*(self: MarkdownElement, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:76-79 — `MarkdownElement.__rich_console__(self, console:
  ## Console, options: ConsoleOptions) -> RenderResult`: `return ()` (empty)
  ## (markdown.py:78). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `RenderResult` from richbase.
  # `return ()` (markdown.py:78) — the base element renders nothing.
  result = @[]

# ---------------------------------------------------------------------------
# TextElement — markdown.py:91-104
# ---------------------------------------------------------------------------

method onEnter*(self: TextElement, context: MarkdownContext) =
  ## rich markdown.py:96-98 — `TextElement.on_enter(self, context) -> None`:
  ## `self.style = context.enter_style(self.style_name);
  ## self.text = Text(justify="left")` (markdown.py:97-98). Overrides the base.
  self.style = context.enterStyle(self.styleName)
  self.text = initText(justify = some(jmLeft))

method onText*(self: TextElement, context: MarkdownContext, text: string) =
  ## rich markdown.py:100-101 — `TextElement.on_text(self, context, text:
  ## TextType) -> None`: `self.text.append(text, context.current_style if
  ## isinstance(text, str) else None)` (markdown.py:101). The live path is the
  ## `str` arm (`isinstance(text, str)` ⇒ `append(text, current_style)`); the
  ## `Text` arm (`append_text`) is the deferred `Syntax` highlight path (Slice 6),
  ## so `onText` takes the str variant only. Overrides the base.
  discard self.text.append(text, context.currentStyle())

method onLeave*(self: TextElement, context: MarkdownContext) =
  ## rich markdown.py:103-104 — `TextElement.on_leave(self, context) -> None`:
  ## `context.leave_style()` (markdown.py:104). Overrides the base.
  discard context.leaveStyle()

# ---------------------------------------------------------------------------
# Paragraph — markdown.py:107-124
# ---------------------------------------------------------------------------

proc create*(T: typedesc[Paragraph], markdown: Markdown,
             token: Token): Paragraph =
  ## rich markdown.py:113-115 — `Paragraph.create(cls, markdown, token) ->
  ## Paragraph` (classmethod): `return cls(justify=markdown.justify or "left")`
  ## (markdown.py:115). `T: typedesc[Paragraph]`.
  result = initParagraph(if markdown.justify.isSome: markdown.justify.get
                         else: jmLeft)

proc initParagraph*(justify: JustifyMethod): Paragraph =
  ## rich markdown.py:117-118 — `Paragraph.__init__(self, justify:
  ## JustifyMethod) -> None`: `self.justify = justify` (markdown.py:118). Phase
  ## 0 stub.
  new(result)
  result.justify = justify
  result.styleName = "markdown.paragraph"
  result.newLine = true

method renderConsole*(self: Paragraph, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:120-124 — `Paragraph.__rich_console__(self, console,
  ## options) -> RenderResult`: `self.text.justify = self.justify; yield
  ## self.text` (markdown.py:123-124). Overrides the base.
  self.text.justify = some(self.justify)
  # `yield self.text` (markdown.py:124) — append the paragraph `Text` as a
  # console renderable (richbase now exposes `addRenderable`).
  result = @[]
  addRenderable(result, self.text, rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# Heading — markdown.py:133-164
# ---------------------------------------------------------------------------

proc create*(T: typedesc[Heading], markdown: Markdown, token: Token): Heading =
  ## rich markdown.py:146-147 — `Heading.create(cls, markdown, token) ->
  ## Heading` (classmethod): `return cls(token.tag)` (markdown.py:147).
  ## `T: typedesc[Heading]`. Slice 5a gave `Token` its `tag` field, so the
  ## heading tag (`"h1"`..`"h6"`) is read faithfully.
  result = initHeading(token.tag)

proc initHeading*(tag: string): Heading =
  ## rich markdown.py:153-156 — `Heading.__init__(self, tag: str) -> None`:
  ## `self.tag = tag; self.style_name = f"markdown.{tag}"; super().__init__()`
  ## (markdown.py:155-156).
  new(result)
  result.tag = tag
  result.styleName = "markdown." & tag
  result.newLine = true

method onEnter*(self: Heading, context: MarkdownContext) =
  ## rich markdown.py:149-151 — `Heading.on_enter(self, context) -> None`:
  ## `self.text = Text(); context.enter_style(self.style_name)` (markdown.py:150).
  ## Overrides the base. A `method` so the dispatch loop's `element.onEnter` runs
  ## the `Heading` override (not the base no-op).
  self.text = initText()
  discard context.enterStyle(self.styleName)

method renderConsole*(self: Heading, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:158-164 — `Heading.__rich_console__(self, console,
  ## options) -> RenderResult`: copy `self.text`, apply `LEVEL_ALIGN[tag]`,
  ## yield it (markdown.py:160-163). Overrides the base. Body needs
  ## `levelAlign`.
  # `text = self.text.copy(); heading_justify = LEVEL_ALIGN.get(self.tag,
  # "left"); text.justify = heading_justify; yield text` (markdown.py:160-163).
  let text = self.text.copy()
  let headingJustify = levelAlign.getOrDefault(self.tag, jmLeft)
  text.justify = some(headingJustify)
  result = @[]
  addRenderable(result, text, rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# CodeBlock — markdown.py:167-189
# ---------------------------------------------------------------------------

proc create*(T: typedesc[CodeBlock], markdown: Markdown,
             token: Token): CodeBlock =
  ## rich markdown.py:173-176 — `CodeBlock.create(cls, markdown, token) ->
  ## CodeBlock` (classmethod): `node_info = token.info or "";
  ## lexer_name = node_info.partition(" ")[0]; return cls(lexer_name or "text",
  ## markdown.code_theme)` (markdown.py:174-175). `T: typedesc[CodeBlock]`.
  ## Slice 5a gave `Token` its `info` field (the fence info string), so the
  ## lexer name is read faithfully (first word of the info, `"text"` if empty).
  let nodeInfo = token.info
  let lexerName = if nodeInfo.len > 0: nodeInfo.split(' ')[0] else: ""
  result = initCodeBlock(if lexerName.len > 0: lexerName else: "text",
                         markdown.codeTheme)

proc initCodeBlock*(lexerName: string, theme: string): CodeBlock =
  ## rich markdown.py:178-180 — `CodeBlock.__init__(self, lexer_name: str,
  ## theme: str) -> None`: store `lexerName`/`theme` (markdown.py:179-180).
  new(result)
  result.lexerName = lexerName
  result.theme = theme
  result.styleName = "markdown.code_block"
  result.newLine = true

method renderConsole*(self: CodeBlock, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:182-189 — `CodeBlock.__rich_console__(self, console,
  ## options) -> RenderResult`: build a `Syntax(code, lexer_name, theme=theme,
  ## word_wrap=True, padding=1)` and yield it (markdown.py:186-188). Overrides
  ## the base.
  ##
  ## Slice 5c Option A — PLAIN render (NO `Syntax`/Pygments, deferred to Slice
  ## 6): render the code as a plain `Text` carrying the `markdown.code_block`
  ## style (cyan+black_bg). The `markdown.code_block` style was pushed onto the
  ## style stack by `TextElement.onEnter` (`enter_style("markdown.code_block")`)
  ## and stored in `self.style`; the code content (appended via `onText`) lives
  ## in `self.text`. Faithful to `code = str(self.text).rstrip()` (markdown.py:183):
  ## render a fresh `Text` from the rstripped plain with that style (single-style
  ## ⇒ the span structure is irrelevant; the spans already carry the same
  ## combined style). Although `Syntax`/Pygments highlighting is deferred to
  ## Slice 6, the `padding=1` of `Syntax(code, …, padding=1)` (markdown.py:186)
  ## is NOT Syntax-specific — it is ordinary rich padding. The plain render
  ## therefore wraps the styled `Text` in a real `Padding(rendered, (1, 1, 1, 1))`
  ## (padding.py:33-44; `expand=True` ⇒ full width, `style="none"` ⇒ unstyled
  ## pads), matching rich's all-four-sides padding of 1. Best-effort; NO golden
  ## case (the fenced-code golden is deferred to Slice 6/Syntax per the slice
  ## scope).
  let code = strip(self.text.plain, leading = false)   # str(self.text).rstrip()
  let rendered = initText(code, style = self.style, justify = some(jmLeft))
  let padded = initPadding(toRenderableValue(rendered), (1, 1, 1, 1))
  result = @[]
  addRenderable(result, padded, rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# BlockQuote — markdown.py:192-215
# ---------------------------------------------------------------------------

proc initBlockQuote*(): BlockQuote =
  ## rich markdown.py:197-198 — `BlockQuote.__init__(self) -> None`:
  ## `self.elements = Renderables()` (markdown.py:198).
  new(result)
  result.elements = initRenderables()
  result.styleName = "markdown.block_quote"
  result.newLine = true

method onChildClose*(self: BlockQuote, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:200-202 — `BlockQuote.on_child_close(self, context, child)
  ## -> bool`: `self.elements.append(child); return False` (markdown.py:201)
  ## — take over rendering of children. Overrides the base. A `method` so the
  ## dispatch loop's `context.stack.top.onChildClose(context, element)`
  ## (markdown.py:688) dispatches on the `BlockQuote` parent (absorbs the child
  ## & returns `False`), not the base `True`.
  self.elements.append(child)
  result = false

method renderConsole*(self: BlockQuote, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:204-215 — `BlockQuote.__rich_console__(self, console,
  ## options) -> RenderResult`: render `self.elements` at `width-4`, prefix each
  ## line with `▌ ` (markdown.py:208-214). Overrides the base.
  # `render_options = options.update(width=options.max_width - 4)`
  let renderOpts = options.update(width = setChange(options.maxWidth - 4))
  # `lines = console.render_lines(self.elements, render_options, style=self.style)`
  let lines = console.renderLines(toRenderableValue(self.elements),
                                  some(renderOpts), some(self.style))
  # `style = self.style; new_line = Segment("\n"); padding = Segment("▌ ", style)`
  let styleRef = some(StyleRef(self.style))
  let padding = initSegment("▌ ", styleRef)
  let newLine = line()
  # `for line in lines: yield padding; yield from line; yield new_line`
  result = @[]
  for ln in lines:
    addSegment(result, padding)
    for s in ln:
      addSegment(result, s)
    addSegment(result, newLine)

# ---------------------------------------------------------------------------
# HorizontalRule — markdown.py:218-228
# ---------------------------------------------------------------------------

proc create*(T: typedesc[HorizontalRule], markdown: Markdown,
            token: Token): HorizontalRule =
  ## rich markdown.py:218-228 — `HorizontalRule` inherits the base
  ## `MarkdownElement.create` (`return cls()`, markdown.py:38) but overrides the
  ## `new_line = False` classvar (markdown.py:221). The base `MarkdownElement.
  ## create` yields `newLine = true`, so this override constructs with
  ## `newLine = false` faithfully (the `hr` token is self-closing; the dispatch
  ## loop sets `new_line = element.new_line` after rendering, markdown.py:702).
  result = HorizontalRule(newLine: false)

method renderConsole*(self: HorizontalRule, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:223-228 — `HorizontalRule.__rich_console__(self, console,
  ## options) -> RenderResult`: `style = console.get_style("markdown.hr",
  ## default="none"); yield Rule(style=style, characters="-"); yield Text()`
  ## (markdown.py:225-227). Overrides the base. Slice 5c wires `console.getStyle`
  ## via `console_api` (the `markdown.hr` style is registered in `DEFAULT_STYLES`
  ## = `dim`); `Rule`/`Text` from the existing imports.
  let hrStyle = console.getStyle("markdown.hr", default = "none")
  result = @[]
  addRenderable(result, initRule(characters = "-", style = hrStyle),
               rrkConsoleRenderable)
  addRenderable(result, initText(), rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# TableElement — markdown.py:231-269
# ---------------------------------------------------------------------------

proc initTableElement*(): TableElement =
  ## rich markdown.py:234-236 — `TableElement.__init__(self) -> None`:
  ## `self.header = None; self.body = None` (markdown.py:235-236).
  new(result)
  result.header = none(TableHeaderElement)
  result.body = none(TableBodyElement)
  result.newLine = true

method onChildClose*(self: TableElement, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:238-245 — `TableElement.on_child_close(self, context,
  ## child) -> bool`: route the child to `self.header`/`self.body` (raising
  ## `RuntimeError` otherwise), `return False` (markdown.py:239-244).
  ## Overrides the base. A `method` so the dispatch loop's parent dispatch
  ## (markdown.py:688) routes the child into the `TableElement` (not the base
  ## `True`).
  if child of TableHeaderElement:
    self.header = some(TableHeaderElement(child))
  elif child of TableBodyElement:
    self.body = some(TableBodyElement(child))
  else:
    # rich raises `RuntimeError("Couldn't process markdown table.")`
    ## (markdown.py:243); no frozen `RuntimeError` exists in Nim's system
    ## exceptions, so the closest generic catchable (`ValueError`) is raised.
    raise newException(ValueError, "Couldn't process markdown table.")
  result = false

method renderConsole*(self: TableElement, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:247-269 — `TableElement.__rich_console__(self, console,
  ## options) -> RenderResult`: build a `Table(box=box.SIMPLE, …)` from the
  ## header/body and yield it (markdown.py:251-268). Overrides the base. body
  ## body needs `Table`, `box.SIMPLE`.
  # Build `Table(box=box.SIMPLE, pad_edge=False, style="markdown.table.border",
  # show_edge=True, collapse_padding=True)` from the header/body and
  # `yield table` (markdown.py:251-268). `Table.addRow` takes `varargs`, so a
  # dynamic seq cannot be spread into it in Nim; the body cells are therefore
  # appended to each `Column.rawCells` directly (the exact field `addRow`
  # writes), then a `Row` is appended — the resulting table structure is
  # identical to `add_row(*row_content)`.
  let table = initTable(box = some(SIMPLE), padEdge = false,
                        style = "markdown.table.border", showEdge = true,
                        collapsePadding = true)
  if self.header.isSome and self.header.get.row.isSome:
    for column in self.header.get.row.get.cells:
      let heading = column.content.copy()
      heading.stylize("markdown.table.header")
      table.addColumn(heading)
  if self.body.isSome:
    for row in self.body.get.rows:
      for index, cell in row.cells:
        if index < table.columns.len:
          table.columns[index].rawCells.add(cell.content)
        else:
          let col = initColumn(index = table.columns.len,
                               highlight = table.highlight)
          for _ in table.rows:
            col.rawCells.add(initText(""))
          col.rawCells.add(cell.content)
          table.columns.add(col)
      for index in row.cells.len ..< table.columns.len:
        table.columns[index].rawCells.add("")
      table.rows.add(initRow())
  result = @[]
  addRenderable(result, table, rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# TableHeaderElement / TableBodyElement / TableRowElement — markdown.py:272-305
# ---------------------------------------------------------------------------

proc initTableHeaderElement*(): TableHeaderElement =
  ## rich markdown.py:275-276 — `TableHeaderElement.__init__(self) -> None`:
  ## `self.row = None` (markdown.py:276).
  new(result)
  result.row = none(TableRowElement)
  result.newLine = true

method onChildClose*(self: TableHeaderElement, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:278-281 — `TableHeaderElement.on_child_close(self,
  ## context, child) -> bool`: `self.row = child; return False`
  ## (markdown.py:279-280). Overrides the base. A `method` for the dispatch
  ## loop's parent dispatch (markdown.py:688).
  assert child of TableRowElement
  self.row = some(TableRowElement(child))
  result = false

proc initTableBodyElement*(): TableBodyElement =
  ## rich markdown.py:287-288 — `TableBodyElement.__init__(self) -> None`:
  ## `self.rows = []` (markdown.py:288).
  new(result)
  result.rows = @[]
  result.newLine = true

method onChildClose*(self: TableBodyElement, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:290-293 — `TableBodyElement.on_child_close(self, context,
  ## child) -> bool`: `self.rows.append(child); return False` (markdown.py:291-
  ## 292). Overrides the base. A `method` for the dispatch loop's parent
  ## dispatch (markdown.py:688).
  assert child of TableRowElement
  self.rows.add(TableRowElement(child))
  result = false

proc initTableRowElement*(): TableRowElement =
  ## rich markdown.py:299-300 — `TableRowElement.__init__(self) -> None`:
  ## `self.cells = []` (markdown.py:300).
  new(result)
  result.cells = @[]
  result.newLine = true

method onChildClose*(self: TableRowElement, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:302-305 — `TableRowElement.on_child_close(self, context,
  ## child) -> bool`: `self.cells.append(child); return False` (markdown.py:303-
  ## 304). Overrides the base. A `method` for the dispatch loop's parent
  ## dispatch (markdown.py:688).
  assert child of TableDataElement
  self.cells.add(TableDataElement(child))
  result = false

# ---------------------------------------------------------------------------
# TableDataElement — markdown.py:308-337
# ---------------------------------------------------------------------------

proc create*(T: typedesc[TableDataElement], markdown: Markdown,
             token: Token): MarkdownElement =
  ## rich markdown.py:313-327 — `TableDataElement.create(cls, markdown, token)
  ## -> MarkdownElement` (classmethod): parse the cell's `text-align` style into
  ## a `JustifyMethod`, `return cls(justify=justify)` (markdown.py:315-326).
  ## `T: typedesc[TableDataElement]`; returns `MarkdownElement` (faithful to the
  ## rich return type).
  # [body deferral] the `text-align` style is read from `token.attrs.get(
  ## "style", "")` (markdown.py:315) — `Token` is a field-less frozen
  ## placeholder. With no style available the parser's else-branch yields
  ## `justify = "default"` (markdown.py:325); the real text-align is parsed
  ## when `Token` gains fields.
  result = initTableDataElement(jmDefault)

proc initTableDataElement*(justify: JustifyMethod): TableDataElement =
  ## rich markdown.py:333-334 — `TableDataElement.__init__(self, justify:
  ## JustifyMethod) -> None`: `self.content = Text("", justify=justify);
  ## self.justify = justify` (markdown.py:333-334).
  new(result)
  result.content = initText("", justify = some(justify))
  result.justify = justify
  result.newLine = true

method onText*(self: TableDataElement, context: MarkdownContext, text: string) =
  ## rich markdown.py:336-337 — `TableDataElement.on_text(self, context, text:
  ## TextType) -> None`: `if isinstance(text, str): self.content.append(text,
  ## context.current_style) else: self.content.append_text(text)`
  ## (markdown.py:336). The live path is the `str` arm; the `Text` arm
  ## (`append_text`) is the deferred `Syntax` highlight path (Slice 6), so
  ## `onText` takes the str variant only. A `method` so the dispatch loop's
  ## `element.onText` (markdown.py:690) runs the `TableDataElement` override.
  ## Overrides the base.
  discard self.content.append(text, context.currentStyle())

# ---------------------------------------------------------------------------
# ListElement — markdown.py:340-372
# ---------------------------------------------------------------------------

proc create*(T: typedesc[ListElement], markdown: Markdown,
             token: Token): ListElement =
  ## rich markdown.py:346-347 — `ListElement.create(cls, markdown, token) ->
  ## ListElement` (classmethod): `return cls(token.type, int(token.attrs.get(
  ## "start", 1)))` (markdown.py:347). `T: typedesc[ListElement]`. Slice 5a
  ## gave `Token` its `type` field, so the list type (`"bullet_list_open"`/
  ## `"ordered_list_open"`) is read faithfully. `token.attrs` is `None` for
  ## the bullet/ordered lists the Slice 5a+list parser emits (no `start`
  ## attribute → default `1`, matching `int(token.attrs.get("start", 1))`).
  let listStart = if token.attrs.isSome and token.attrs.get.hasKey("start"):
                    parseInt(token.attrs.get["start"]) else: 1
  result = initListElement(token.`type`, some(listStart))

proc initListElement*(listType: string, listStart: Option[int]): ListElement =
  ## rich markdown.py:357-359 — `ListElement.__init__(self, list_type: str,
  ## list_start: int | None) -> None`: store `items=[]`/`listType`/`listStart`
  ## (markdown.py:357-359). `list_start: int | None` → `Option[int]`.
  new(result)
  result.items = @[]
  result.listType = listType
  result.listStart = listStart
  result.newLine = true

method onChildClose*(self: ListElement, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:361-362 — `ListElement.on_child_close(self, context, child)
  ## -> bool`: `self.items.append(child); return False` (markdown.py:361).
  ## Overrides the base. A `method` for the dispatch loop's parent dispatch
  ## (markdown.py:688).
  assert child of ListItem
  self.items.add(ListItem(child))
  result = false

# Forward declarations — `ListItem.renderBullet`/`renderNumber` are defined
# in the ListItem section below (after `ListElement.renderConsole`), but
# `ListElement.renderConsole` calls `item.renderBullet`/`item.renderNumber`,
# so the signatures must be in scope first (Nim requires declaration before
# use; the bodies land in the ListItem section).
proc renderBullet*(self: ListItem, console: ConsoleHandle,
                   options: ConsoleOptions): RenderResult
proc renderNumber*(self: ListItem, console: ConsoleHandle,
                   options: ConsoleOptions, number: int,
                   lastNumber: int): RenderResult

method renderConsole*(self: ListElement, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:364-372 — `ListElement.__rich_console__(self, console,
  ## options) -> RenderResult`: for a bullet list yield each
  ## `item.render_bullet`; else yield `item.render_number(number, last_number)`
  ## (markdown.py:366-371). Overrides the base.
  result = @[]
  if self.listType == "bullet_list_open":
    for item in self.items:
      result.add(item.renderBullet(console, options))
  else:
    # ordered_list_open — `number = 1 if self.list_start is None else
    # self.list_start; last_number = number + len(self.items)`; for each
    # index/item yield `item.render_number(console, options, number+index,
    # last_number)` (markdown.py:368-371). Only the bullet-list branch is
    # exercised by the golden cases; the ordered branch is faithful for
    # completeness.
    let number = if self.listStart.isSome: self.listStart.get else: 1
    let lastNumber = number + len(self.items)
    for index, item in self.items:
      result.add(item.renderNumber(console, options, number + index,
                                   lastNumber))

# ---------------------------------------------------------------------------
# ListItem — markdown.py:375-449
# ---------------------------------------------------------------------------

proc initListItem*(): ListItem =
  ## rich markdown.py:380-381 — `ListItem.__init__(self) -> None`:
  ## `self.elements = Renderables()` (markdown.py:381).
  new(result)
  result.elements = initRenderables()
  result.styleName = "markdown.item"
  result.newLine = true

method onChildClose*(self: ListItem, context: MarkdownContext,
                   child: MarkdownElement): bool =
  ## rich markdown.py:383-384 — `ListItem.on_child_close(self, context, child)
  ## -> bool`: `self.elements.append(child); return False` (markdown.py:383).
  ## Overrides the base. A `method` for the dispatch loop's parent dispatch
  ## (markdown.py:688).
  self.elements.append(child)
  result = false

proc renderBullet*(self: ListItem, console: ConsoleHandle,
                   options: ConsoleOptions): RenderResult =
  ## rich markdown.py:386-401 — `ListItem.render_bullet(self, console, options)
  ## -> RenderResult`: render `self.elements` at `width-3`, prefix the first
  ## line with ` • ` (markdown.py:392-400). `bullet_style =
  ## console.get_style("markdown.item.bullet", default="none")` (bold via
  ## DEFAULT_STYLES); `bullet = Segment(" • ", bullet_style)`; `padding =
  ## Segment(" " * 3, bullet_style)`; `new_line = Segment("\n")`; for first,
  ## line in loop_first(lines): yield bullet if first else padding; yield from
  ## line; yield new_line. `loop_first` is modelled by an index flag.
  let renderOpts = options.update(width = setChange(options.maxWidth - 3))
  let lines = console.renderLines(toRenderableValue(self.elements),
                                  some(renderOpts), some(self.style))
  let bulletStyle = console.getStyle("markdown.item.bullet", default = "none")
  let bulletStyleRef = some(StyleRef(bulletStyle))
  let bullet = initSegment(" • ", bulletStyleRef)
  let padding = initSegment(repeat(" ", 3), bulletStyleRef)
  let newLine = line()
  result = @[]
  var first = true
  for ln in lines:
    addSegment(result, if first: bullet else: padding)
    first = false
    for s in ln:
      addSegment(result, s)
    addSegment(result, newLine)

proc renderNumber*(self: ListItem, console: ConsoleHandle,
                   options: ConsoleOptions, number: int,
                   lastNumber: int): RenderResult =
  ## rich markdown.py:403-427 — `ListItem.render_number(self, console, options,
  ## number: int, last_number: int) -> RenderResult`: render `self.elements` at
  ## `width-number_width`, prefix the first line with the right-justified
  ## number (markdown.py:409-426). `number_width = len(str(last_number)) + 2`;
  ## `number_style = console.get_style("markdown.item.number", default="none")`
  ## (cyan via DEFAULT_STYLES); `numeral = Segment(f"{number}".rjust(
  ## number_width - 1) + " ", number_style)`; `padding = Segment(" " *
  ## number_width, number_style)`; `new_line = Segment("\n")`; for first, line
  ## in loop_first(lines): yield numeral if first else padding; yield from
  ## line; yield new_line. Only the bullet-list branch is exercised by the
  ## golden cases; the ordered branch is faithful for completeness.
  let numberWidth = len($lastNumber) + 2
  let renderOpts = options.update(width = setChange(options.maxWidth -
                                                    numberWidth))
  let lines = console.renderLines(toRenderableValue(self.elements),
                                  some(renderOpts), some(self.style))
  let numberStyle = console.getStyle("markdown.item.number", default = "none")
  let numberStyleRef = some(StyleRef(numberStyle))
  let numeral = initSegment(($number).align(numberWidth - 1) & " ",
                           numberStyleRef)
  let padding = initSegment(repeat(" ", numberWidth), numberStyleRef)
  let newLine = line()
  result = @[]
  var first = true
  for ln in lines:
    addSegment(result, if first: numeral else: padding)
    first = false
    for s in ln:
      addSegment(result, s)
    addSegment(result, newLine)

# ---------------------------------------------------------------------------
# Link — markdown.py:452-461
# ---------------------------------------------------------------------------

proc create*(T: typedesc[Link], markdown: Markdown,
             token: Token): MarkdownElement =
  ## rich markdown.py:455-458 — `Link.create(cls, markdown, token) ->
  ## MarkdownElement` (classmethod): `url = token.attrs.get("href", "#");
  ## return cls(token.content, str(url))` (markdown.py:456-457). `T:
  ## typedesc[Link]`; returns `MarkdownElement`.
  # [body deferral] `token.attrs.get("href", "#")` and `token.content`
  ## (markdown.py:456-457) are inaccessible — `Token` is a field-less frozen
  ## placeholder. Use the `href` default `"#"` and an empty text; the real
  ## values are read when `Token` gains fields.
  result = initLink("", "#")

proc initLink*(text: string, href: string): Link =
  ## rich markdown.py:460-461 — `Link.__init__(self, text: str, href: str) ->
  ## None`: `self.text = Text(text); self.href = href` (markdown.py:460). Phase
  ## 0 stub.
  new(result)
  result.text = initText(text)
  result.href = href
  result.styleName = "none"
  result.newLine = true

# ---------------------------------------------------------------------------
# ImageItem — markdown.py:464-494
# ---------------------------------------------------------------------------

proc create*(T: typedesc[ImageItem], markdown: Markdown,
             token: Token): MarkdownElement =
  ## rich markdown.py:470-477 — `ImageItem.create(cls, markdown, token) ->
  ## MarkdownElement` (classmethod): `return cls(str(token.attrs.get("src",
  ## "")), markdown.hyperlinks)` (markdown.py:476). `T: typedesc[ImageItem]`;
  ## returns `MarkdownElement`.
  # [body deferral] `token.attrs.get("src", "")` (markdown.py:476) is
  ## inaccessible — `Token` is a field-less frozen placeholder. Use the `src`
  ## default `""`; `markdown.hyperlinks` is reachable. The real `src` is read
  ## when `Token` gains fields.
  result = initImageItem("", markdown.hyperlinks)

proc initImageItem*(destination: string, hyperlinks: bool): ImageItem =
  ## rich markdown.py:485-487 — `ImageItem.__init__(self, destination: str,
  ## hyperlinks: bool) -> None`: store `destination`/`hyperlinks`, `self.link =
  ## None`, `super().__init__()` (markdown.py:485-487).
  new(result)
  result.destination = destination
  result.hyperlinks = hyperlinks
  result.link = none(string)
  result.styleName = "none"
  result.newLine = false

method onEnter*(self: ImageItem, context: MarkdownContext) =
  ## rich markdown.py:489-492 — `ImageItem.on_enter(self, context) -> None`:
  ## `self.link = context.current_style.link; self.text = Text(justify="left");
  ## super().on_enter(context)` (markdown.py:490-491). `super().on_enter` is
  ## `TextElement.on_enter` (`self.style = enter_style(style_name);
  ## self.text = Text(justify="left")`, markdown.py:97-98); inlined here because
  ## a Nim `method` call would dispatch on the runtime `ImageItem` type and
  ## recurse — the parent body is inlined faithfully (same net effect: `link`
  ## is read off the CURRENT style before `enter_style` pushes `styleName`, then
  ## `style`/`text` are set). Overrides the base.
  self.link = context.currentStyle().link
  self.style = context.enterStyle(self.styleName)
  self.text = initText(justify = some(jmLeft))

method renderConsole*(self: ImageItem, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:494-498 — `ImageItem.__rich_console__(self, console,
  ## options) -> RenderResult`: build `Text.assemble("🌆 ", title, " ", end="")`
  ## (stylising the title as a link if `hyperlinks`) and yield it
  ## (markdown.py:494-498). Overrides the base. Body needs `Text`,
  ## `Style`.
  # `link_style = Style(link=self.link or self.destination or None); title =
  # self.text or Text(self.destination.strip("/").rsplit("/", 1)[-1]);
  # title.stylize(link_style) if hyperlinks; text = Text.assemble("🌆 ", title,
  # " ", end=""); yield text` (markdown.py:494-498). `Text.assemble` returns a
  # `Text` whose `end` is then set to `""` (ImageItem has `new_line=False`);
  # the template's parts spread handles the heterogeneous str/Text parts.
  var linkOpt = none(string)
  if self.link.isSome and self.link.get.len > 0:
    linkOpt = some(self.link.get)
  elif self.destination.len > 0:
    linkOpt = some(self.destination)
  let linkStyle = initStyle(link = linkOpt)
  var title: Text
  if not self.text.isNil and self.text.length > 0:
    title = self.text
  else:
    let stripped = self.destination.strip(chars = {'/'})
    let idx = stripped.rfind('/')
    let name = if idx >= 0: stripped[idx+1 ..< stripped.len] else: stripped
    title = initText(name)
  if self.hyperlinks:
    title.stylize(linkStyle)
  let assembled = Text.assemble("🌆 ", title, " ")
  assembled.`end` = ""
  result = @[]
  addRenderable(result, assembled, rrkConsoleRenderable)

# ---------------------------------------------------------------------------
# MarkdownContext — markdown.py:465-510
# ---------------------------------------------------------------------------

proc initMarkdownContext*(console: ConsoleHandle, options: ConsoleOptions,
                         style: Style,
                         inlineCodeLexer: Option[string] = none(string),
                         inlineCodeTheme: string = "monokai"): MarkdownContext =
  ## rich markdown.py:478-484 — `MarkdownContext.__init__(self, console:
  ## Console, options: ConsoleOptions, style: Style, inline_code_lexer: str |
  ## None = None, inline_code_theme: str = "monokai") -> None`: store
  ## `console`/`options`/`styleStack=StyleStack(style)`/`stack=Stack()`, build
  ## `_syntax = Syntax("", inline_code_lexer, theme=inline_code_theme)` if
  ## `inline_code_lexer` is set (markdown.py:478-484). `console: Console` →
  ## `ConsoleHandle`; `inline_code_lexer: str | None` → `Option[string]`. Phase
  ## 1 body needs `StyleStack`, `Stack`, `Syntax`.
  new(result)
  result.console = console
  result.options = options
  result.styleStack = initStyleStack(style)
  new(result.stack)
  if inlineCodeLexer.isSome:
    result.syntaxField = some(initSyntax(
        "", LexerOrStr(kind: losStr, s: inlineCodeLexer.get),
        SyntaxThemeArg(kind: staStr, s: inlineCodeTheme)))
  else:
    result.syntaxField = none(Syntax)

proc currentStyle*(self: MarkdownContext): Style =
  ## rich markdown.py:494 — `MarkdownContext.current_style` (property):
  ## `return self.style_stack.current` (markdown.py:494; the current top of the
  ## style stack). Body needs `StyleStack.current`.
  result = self.styleStack.current()

proc onText*(self: MarkdownContext, text: string, nodeType: string) =
  ## rich markdown.py:496-501 — `MarkdownContext.on_text(self, text: str,
  ## node_type: str) -> None`: `self.stack.top.on_text(self, text)` (markdown.py:
  ## 500) — dispatch the text to the current top element's `onText`. A `proc`
  ## (not a `method` — it is dispatched explicitly via `stack.top`, which is
  ## itself a `method`-dispatched element). The `node_type in {"fence",
  ## "code_inline"} and self._syntax is not None` highlight branch (markdown.py:
  ## 496-498) builds a `Syntax`-highlighted `Text` and dispatches it via
  ## `stack.top.on_text(self, Text)`; `self.syntaxField` is `none` unless
  ## `inline_code_lexer` is set (default `none`), so the branch is dead in this
  ## slice and the plain str path runs. The `Text` highlight path is deferred
  ## with `Syntax` (Slice 6); the dead arm falls back to the plain str dispatch
  ## so inline/fence content is not lost.
  if (nodeType == "fence" or nodeType == "code_inline") and
      self.syntaxField.isSome:
    # Slice 6 deferred — `Syntax.highlight(text)` → `stack.top.onText(self, Text)`
    # would replace this; until then the plain str path preserves the content.
    self.stack.top.onText(self, text)
  else:
    self.stack.top.onText(self, text)

proc enterStyle*(self: MarkdownContext, styleName: StyleType): Style =
  ## rich markdown.py:503-506 — `MarkdownContext.enter_style(self, style_name:
  ## str | Style) -> Style`: `style = self.console.get_style(style_name,
  ## default="none"); self.style_stack.push(style); return self.current_style`
  ## (markdown.py:504-506). `style_name: str | Style` keeps the `StyleType`
  ## typeclass. A `str` name resolves through the Console theme (the registered
  ## `markdown.*` styles in `DEFAULT_STYLES`); a `Style` is pushed as-is. Slice
  ## 5c wires `console.getStyle` via `console_api` (the `default="none"` fallback
  ## resolves an unregistered name to `Style.null()`).
  when typeof(styleName) is Style:
    self.styleStack.push(styleName)
  else:
    self.styleStack.push(self.console.getStyle(styleName, default = "none"))
  result = self.styleStack.current()

proc leaveStyle*(self: MarkdownContext): Style =
  ## rich markdown.py:508-510 — `MarkdownContext.leave_style(self) -> Style`:
  ## `style = self.style_stack.pop(); return style` (markdown.py:509-510).
  ## Body needs `StyleStack.pop`.
  result = self.styleStack.pop()

# ---------------------------------------------------------------------------
# Markdown — markdown.py:513-704
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Slice 5a — block-level token model + parser (markdown_it subset)
# ---------------------------------------------------------------------------
# Slice 5a implements the `Token` data model and a block-level parser for the
# CommonMark subset used by rich's `Markdown`: ATX headings 1-6, backtick/tilde
# fences, thematic breaks, joined consecutive paragraph lines, and blank-line
# separation. It is a direct port of the relevant `markdown_it` block rules
# (`heading`/`fence`/`hr`/`paragraph`), producing `markdown_it`-shaped `Token`s
# (verified field-by-field against `markdown-it-py 4.2.0`). Inline parsing
# (`**bold**`/`code`/… → `children`) and `flattenTokens` splicing remain Slice
# 5b; rendering and golden cases remain Slice 5c. Unsupported blocks (lists,
# blockquotes, indented code) and inline syntax fall back to paragraph/
# raw-inline content, per the Slice 5a scope.

proc initToken*(ttype: string, tag: string = "", nesting: int = 0,
                level: int = 0, content: string = "", markup: string = "",
                info: string = "", hidden: bool = false,
                attrs: Option[tables.Table[string, string]] =
                  none(tables.Table[string, string]),
                children: seq[Token] = @[]): Token =
  ## Slice 5a — construct a `Token` with `markdown_it`-shaped fields. Defaults
  ## mirror an absent/empty `markdown_it.Token`: empty `tag`/`content`/`markup`/
  ## `info`, `nesting`/`level` `0`, `hidden` `false`, no `attrs`, no `children`.
  ## `ttype` is required (every `Token` has a `type`).
  new(result)
  result.`type` = ttype
  result.tag = tag
  result.nesting = nesting
  result.level = level
  result.content = content
  result.markup = markup
  result.info = info
  result.hidden = hidden
  result.attrs = attrs
  result.children = children

proc parseInline*(content: string): seq[Token] =
  ## Slice 5b — the inline-level parser: a simplified port of the
  ## markdown-it commonmark inline-rule subset that populates the `children`
  ## of an `inline` block token (markdown.py:557 leaves inline parsing to
  ## markdown-it). Scans `content` linearly and emits only `text`,
  ## `strong_open`/`strong_close` (markup `**`), `em_open`/`em_close`
  ## (markup `*`) and `code_inline` (markup `` ` ``, `content` = inner span).
  ## Backtick `code_inline` has priority over `*`/`**` (markup inside a code
  ## span is not scanned). Unmatched delimiter runs are emitted verbatim as
  ## `text` (CommonMark: an unmatched delimiter is literal). Links (`[text](url)`)
  ## and strikethrough (`~~text~~`) are parsed into `link_open`/`link_close`/
  ## `s_open`/`s_close` tokens. The `strong`/`em` inner is a single `text` token
  ## (no nested re-parse); a longer opening run keeps its surplus `*` as
  ## literal `text` (no character loss; `***` does not fold away a `*`).
  result = @[]
  let n = content.len
  var i = 0
  var textStart = -1          # start of the current literal-text run; -1 = none
  while i < n:
    let c = content[i]
    if c == '[':
      # link: [text](url) — scan for ']' followed by '(' ... ')'.
      var j = i + 1
      while j < n and content[j] != ']': j.inc
      if j < n and j + 1 < n and content[j + 1] == '(':
        var k = j + 2
        while k < n and content[k] != ')': k.inc
        if k < n:
          let linkText = content[i + 1 ..< j]
          let linkUrl = content[j + 2 ..< k]
          if textStart >= 0:
            result.add initToken("text", content = content[textStart ..< i],
                                nesting = 0)
            textStart = -1
          var attrsTab = initTable[string, string]()
          attrsTab["href"] = linkUrl
          result.add initToken("link_open", tag = "link", nesting = 1,
                              attrs = some(attrsTab))
          result.add initToken("text", content = linkText, nesting = 0)
          result.add initToken("link_close", tag = "link", nesting = -1)
          i = k + 1
          continue
      if textStart < 0: textStart = i
      i.inc
    elif c == '~' and i + 1 < n and content[i + 1] == '~':
      # strikethrough: ~~text~~ — scan for a matching ~~.
      var j = i + 2
      while j < n:
        if content[j] == '~' and j + 1 < n and content[j + 1] == '~':
          break
        j.inc
      if j < n:
        if textStart >= 0:
          result.add initToken("text", content = content[textStart ..< i],
                              nesting = 0)
          textStart = -1
        result.add initToken("s_open", tag = "s", nesting = 1, markup = "~~")
        result.add initToken("text", content = content[i + 2 ..< j],
                            nesting = 0)
        result.add initToken("s_close", tag = "s", nesting = -1, markup = "~~")
        i = j + 2
        continue
      if textStart < 0: textStart = i
      i.inc
    elif c == '`':
      # code_inline: scan to the next backtick (single-backtick span).
      var j = i + 1
      while j < n and content[j] != '`': j.inc
      if j < n:               # found a closing backtick
        if textStart >= 0:
          result.add initToken("text", content = content[textStart ..< i],
                              nesting = 0)
          textStart = -1
        result.add initToken("code_inline", content = content[i + 1 ..< j],
                            markup = "`", nesting = 0)
        i = j + 1
      else:                   # no close: the backtick is literal text
        if textStart < 0: textStart = i
        i.inc
    elif c == '*':
      let runStart = i
      while i < n and content[i] == '*': i.inc
      let runLen = i - runStart
      if runLen >= 2:
        # strong ('**'): scan ahead for a matching run of >= 2 '*'. Complete
        # `...` code spans are skipped so '*' inside code cannot close strong;
        # an unmatched backtick is a literal char (no protection of the rest).
        var j = i
        var closeStart = -1
        while j < n:
          if content[j] == '`':
            var bk = j + 1
            while bk < n and content[bk] != '`': bk.inc
            if bk < n:        # complete code span: jump past it
              j = bk + 1
            else:             # unmatched backtick: literal, keep scanning
              j.inc
          elif content[j] == '*':
            var k = j
            while k < n and content[k] == '*': k.inc
            if k - j >= 2:
              closeStart = j
              break
            j = k
          else:
            j.inc
        if closeStart >= 0:
          if textStart >= 0:
            result.add initToken("text", content = content[textStart ..< runStart],
                                nesting = 0)
            textStart = -1
          # The opener consumes exactly 2 '*'; any surplus '*' of a longer
          # opening run (e.g. `***`) stay as literal text (no char loss).
          if runLen > 2:
            result.add initToken("text",
                                content = content[runStart ..< runStart + (runLen - 2)],
                                nesting = 0)
          result.add initToken("strong_open", markup = "**", nesting = 1)
          result.add initToken("text", content = content[i ..< closeStart],
                              nesting = 0)
          result.add initToken("strong_close", markup = "**", nesting = -1)
          i = closeStart + 2
        else:                  # unmatched: keep the whole run as literal text
          if textStart < 0: textStart = runStart
      else:                   # runLen == 1: em ('*'): scan for a single '*',
                              # skipping complete `...` code spans.
        var j = i
        var closeIdx = -1
        while j < n:
          if content[j] == '`':
            var bk = j + 1
            while bk < n and content[bk] != '`': bk.inc
            if bk < n:
              j = bk + 1
            else:
              j.inc
          elif content[j] == '*':
            var k = j
            while k < n and content[k] == '*': k.inc
            if k - j == 1:
              closeIdx = j
              break
            j = k
          else:
            j.inc
        if closeIdx >= 0:
          if textStart >= 0:
            result.add initToken("text", content = content[textStart ..< runStart],
                                nesting = 0)
            textStart = -1
          result.add initToken("em_open", markup = "*", nesting = 1)
          result.add initToken("text", content = content[i ..< closeIdx],
                              nesting = 0)
          result.add initToken("em_close", markup = "*", nesting = -1)
          i = closeIdx + 1
        else:                  # unmatched: keep the '*' as literal text
          if textStart < 0: textStart = runStart
    else:
      if textStart < 0: textStart = i
      i.inc
  if textStart >= 0:
    result.add initToken("text", content = content[textStart ..< i], nesting = 0)

proc mdCountLeadingSpaces(line: string): int =
  ## Number of leading U+0020 space characters (the CommonMark indentation
  ## count; tabs are not expanded — a tab in column 0 stops the count, matching
  ## the Slice 5a column-0 / 0-3-space subset).
  result = 0
  while result < line.len and line[result] == ' ': result.inc

proc mdIsBlankLine(line: string): bool =
  ## CommonMark blank line — only spaces/tabs (or empty).
  for c in line:
    if c != ' ' and c != '\t': return false
  result = true

proc mdTryHeading(line: string; level: var int; markup: var string;
                  content: var string): bool =
  ## Port of `markdown_it.rules_block.heading` for the column-0..3 subset. On
  ## success sets `level` (1-6), `markup` (`"#"`×level) and `content` (the
  ## heading inline text, trailing-space + closing-`#` stripped per CommonMark).
  var indent = mdCountLeadingSpaces(line)
  if indent > 3: return false
  var i = indent
  var lvl = 0
  while i < line.len and line[i] == '#' and lvl < 6:
    lvl.inc
    i.inc
  if lvl < 1: return false
  # After the `#`s: end-of-line or a space/tab (CommonMark opening rule). The
  # `lvl < 6` cap leaves `i` on a 7th `#` (not a space) → rejected.
  if i < line.len and line[i] != ' ' and line[i] != '\t': return false
  # markdown_it: `maximum = skipSpacesBack(line.len, i)`; `tmp =
  # skipCharsStrBack(maximum, '#', i)`; if `tmp > i` and `src[tmp-1]` is a space
  # then `maximum = tmp`; then `content = src[i:maximum].strip()`.
  var maximum = line.len
  while maximum > i and (line[maximum - 1] == ' ' or line[maximum - 1] == '\t'):
    maximum.dec
  var tmp = maximum
  while tmp > i and line[tmp - 1] == '#': tmp.dec
  if tmp > i and (line[tmp - 1] == ' ' or line[tmp - 1] == '\t'):
    maximum = tmp
  level = lvl
  markup = repeat('#', lvl)
  content = line[i ..< maximum].strip()
  result = true

proc mdTryFence(line: string; marker: var char; fenceLen: var int;
                info: var string; indent: var int): bool =
  ## Port of `markdown_it.rules_block.fence` opening-fence detection. On
  ## success sets `marker` (`` '`' `` or `'~'`), `fenceLen` (>= 3), `info` (the
  ## rest of the opening line, verbatim/untrimmed) and `indent` (0-3). Backtick
  ## fences reject an info string containing a backtick (CommonMark).
  var ind = mdCountLeadingSpaces(line)
  if ind > 3: return false
  var i = ind
  if i >= line.len: return false
  var m = line[i]
  if m != '`' and m != '~': return false
  var length = 0
  while i < line.len and line[i] == m:
    length.inc
    i.inc
  if length < 3: return false
  var infoStr = line[i ..< line.len]
  if m == '`' and infoStr.find('`') >= 0: return false
  marker = m
  fenceLen = length
  info = infoStr
  indent = ind
  result = true

proc mdIsFenceClose(line: string; marker: char; openLen: int): bool =
  ## A closing fence: 0-3 leading spaces, then `marker` repeated >= `openLen`,
  ## then only spaces/tabs. Port of the `fence` rule's closing scan.
  var indent = mdCountLeadingSpaces(line)
  if indent > 3: return false
  var i = indent
  var length = 0
  while i < line.len and line[i] == marker:
    length.inc
    i.inc
  if length < openLen: return false
  while i < line.len:
    if line[i] != ' ' and line[i] != '\t': return false
    i.inc
  result = true

proc mdTryHr(line: string; markup: var string): bool =
  ## Port of `markdown_it.rules_block.hr`. On success sets `markup` to the
  ## single matched delimiter character (`-`/`*`/`_`, markdown_it hr `token.markup`).
  var indent = mdCountLeadingSpaces(line)
  if indent > 3: return false
  var i = indent
  if i >= line.len: return false
  var m = line[i]
  if m != '*' and m != '-' and m != '_': return false
  var cnt = 1
  i.inc
  while i < line.len:
    var ch = line[i]
    if ch != m and ch != ' ' and ch != '\t': return false
    if ch == m: cnt.inc
    i.inc
  if cnt < 3: return false
  markup = $m
  result = true

proc mdTryBullet(line: string; marker: var char; content: var string): bool =
  ## Port of `markdown_it.rules_block.list` bullet detection (the unordered
  ## subset), sufficient for the tight-list golden case (`- item1\n- item2`).
  ## On success sets `marker` (the bullet char `-`/`*`/`+`) and `content` (the
  ## item text after the marker and one space, trailing whitespace stripped).
  ## Requires 0-3 leading spaces, a bullet char, then a space/tab (or
  ## end-of-line for an empty item). Distinct from `mdTryHr` (which requires
  ## the whole line to be 3+ markers + spaces) — hr is checked BEFORE the
  ## bullet block in `parseMarkdownBlocks`, so `* * *`/`- - -` are consumed as
  ## hr and never reach this helper; a bullet line (`- item1`) fails the hr
  ## check (its text has non-marker chars) and falls through to the bullet
  ## block. A `*`/`+` bullet followed by non-space text (`*item`) is rejected
  ## (no mandatory space) and falls through to paragraph, matching commonmark.
  var indent = mdCountLeadingSpaces(line)
  if indent > 3: return false
  var i = indent
  if i >= line.len: return false
  var m = line[i]
  if m != '-' and m != '*' and m != '+': return false
  i.inc
  if i < line.len and line[i] != ' ' and line[i] != '\t': return false
  marker = m
  if i < line.len and (line[i] == ' ' or line[i] == '\t'): i.inc
  content = line[i ..< line.len].strip(leading = false, trailing = true)
  result = true

proc mdFlushParagraph(tokens: var seq[Token]; paraLines: var seq[string]) =
  ## Emit a `paragraph_open`/`inline`/`paragraph_close` triple for any accumulated
  ## paragraph lines and clear the accumulator. A no-op when nothing is pending.
  if paraLines.len > 0:
    tokens.add initToken("paragraph_open", tag = "p", nesting = 1, level = 0)
    let inlineContent = paraLines.join("\n")
    tokens.add initToken("inline", content = inlineContent, nesting = 0,
                        level = 1, children = parseInline(inlineContent))
    tokens.add initToken("paragraph_close", tag = "p", nesting = -1, level = 0)
    paraLines = @[]

proc parseMarkdownBlocks*(markup: string): seq[Token] =
  ## Slice 5a — the block-level Markdown parser, a port of
  ## `MarkdownIt('commonmark').parse` for the heading/fence/hr/paragraph subset.
  ## Returns `markdown_it`-shaped block tokens (top-level `level 0` open/close/
  ## self tokens, with the `inline` child at `level 1`). Line endings are
  ## normalized (`\r\n`/`\r` → `\n`). Unsupported blocks (lists/blockquotes/
  ## indented code) and inline syntax fall back to paragraph/raw-inline
  ## content. Inline `children` stay `@[]` (Slice 5b).
  result = @[]
  var src = markup.replace("\r\n", "\n").replace("\r", "\n")
  if src.len == 0: return
  let lines = src.split('\n')
  var paraLines: seq[string] = @[]
  var i = 0
  while i < lines.len:
    let line = lines[i]
    if mdIsBlankLine(line):
      mdFlushParagraph(result, paraLines)
      i.inc
      continue
    var hLevel = 0
    var hMarkup = ""
    var hContent = ""
    if mdTryHeading(line, hLevel, hMarkup, hContent):
      mdFlushParagraph(result, paraLines)
      let tagName = "h" & $hLevel
      result.add initToken("heading_open", tag = tagName, nesting = 1, level = 0,
                          markup = hMarkup)
      result.add initToken("inline", content = hContent, nesting = 0, level = 1,
                          children = parseInline(hContent))
      result.add initToken("heading_close", tag = tagName, nesting = -1,
                          level = 0, markup = hMarkup)
      i.inc
      continue
    # Blockquote: lines starting with '>' (after 0-3 leading spaces). Collect
    # consecutive '>'-prefixed lines, strip the '>' and one optional space, and
    # emit blockquote_open / paragraph(s) / blockquote_close. Lazy continuation
    # (non-'>' line after a paragraph inside the quote) is not supported; the
    # blockquote ends at the first non-'>' non-blank line (sufficient for the
    # single-line blockquote golden case).
    block bqBlock:
      var bqIndent = mdCountLeadingSpaces(line)
      if bqIndent <= 3 and bqIndent < line.len and line[bqIndent] == '>':
        mdFlushParagraph(result, paraLines)
        var bqLines: seq[string] = @[]
        var j = i
        while j < lines.len:
          let l = lines[j]
          var bi = mdCountLeadingSpaces(l)
          if bi <= 3 and bi < l.len and l[bi] == '>':
            var content = l[bi + 1 ..< l.len]
            if content.len > 0 and content[0] == ' ':
              content = content[1 ..< content.len]
            bqLines.add content
            j.inc
          elif mdIsBlankLine(l):
            break
          else:
            break
        result.add initToken("blockquote_open", tag = "blockquote", nesting = 1,
                            level = 0)
        var bqParaLines: seq[string] = @[]
        for bqLine in bqLines:
          if mdIsBlankLine(bqLine):
            mdFlushParagraph(result, bqParaLines)
          else:
            bqParaLines.add bqLine
        mdFlushParagraph(result, bqParaLines)
        result.add initToken("blockquote_close", tag = "blockquote", nesting = -1,
                            level = 0)
        i = j
        continue
    var hrMarkup = ""
    if mdTryHr(line, hrMarkup):
      mdFlushParagraph(result, paraLines)
      result.add initToken("hr", tag = "hr", nesting = 0, level = 0,
                          markup = hrMarkup)
      i.inc
      continue
    # Bullet list: lines starting with `- `/`* `/`+ ` (after 0-3 leading
    # spaces). `mdTryHr` is checked FIRST, so hr lines (`* * *`/`- - -`) are
    # consumed before this block. Collect consecutive bullet lines, emit
    # `bullet_list_open`/per-item (`list_item_open`+paragraph triple+
    # `list_item_close`)/`bullet_list_close`. The list ends at the first
    # non-bullet line (blank or otherwise). Sufficient for the single-
    # paragraph-per-item tight-list golden case (`- item1\n- item2`); loose
    # lists (blank-line-separated items) and nested/ordered lists are not
    # exercised and fall back to paragraph (the parser's existing scope).
    block bulletBlock:
      var bMarker: char = '\0'
      var bContent = ""
      if mdTryBullet(line, bMarker, bContent):
        mdFlushParagraph(result, paraLines)
        let bMarkup = $bMarker
        result.add initToken("bullet_list_open", tag = "ul", nesting = 1,
                            level = 0, markup = bMarkup)
        var j = i
        while j < lines.len:
          var lm: char = '\0'
          var lc = ""
          if not mdTryBullet(lines[j], lm, lc): break
          result.add initToken("list_item_open", tag = "li", nesting = 1,
                              level = 1, markup = $lm)
          # Each item is a single paragraph (tight list, no blank lines).
          result.add initToken("paragraph_open", tag = "p", nesting = 1,
                              level = 2)
          result.add initToken("inline", content = lc, nesting = 0,
                              level = 3, children = parseInline(lc))
          result.add initToken("paragraph_close", tag = "p", nesting = -1,
                              level = 2)
          result.add initToken("list_item_close", tag = "li", nesting = -1,
                              level = 1, markup = $lm)
          j.inc
        result.add initToken("bullet_list_close", tag = "ul", nesting = -1,
                            level = 0, markup = bMarkup)
        i = j
        continue
    var fMarker: char = '\0'
    var fLen = 0
    var fInfo = ""
    var fIndent = 0
    if mdTryFence(line, fMarker, fLen, fInfo, fIndent):
      mdFlushParagraph(result, paraLines)
      # Collect content lines until a closing fence (or EOF), stripping the
      # opening fence's indent (0-3) from each line (markdown_it `getLines`).
      var contentLines: seq[string] = @[]
      var closed = false
      var j = i + 1
      while j < lines.len:
        if mdIsFenceClose(lines[j], fMarker, fLen):
          closed = true
          break
        contentLines.add lines[j]
        j.inc
      var stripped: seq[string] = @[]
      for cl in contentLines:
        var n = mdCountLeadingSpaces(cl)
        if n > fIndent: n = fIndent
        stripped.add cl[n ..< cl.len]
      var content: string
      if closed:
        if stripped.len == 0: content = ""
        else: content = stripped.join("\n") & "\n"
      else:
        content = stripped.join("\n")
      result.add initToken("fence", tag = "code", nesting = 0, level = 0,
                          content = content, markup = repeat(fMarker, fLen),
                          info = fInfo)
      if closed: i = j + 1
      else: i = lines.len  # unclosed: consume the rest of the document
      continue
    # Paragraph line: strip up to 3 leading spaces from the first line of a
    # paragraph (CommonMark paragraph indent); continuation lines are verbatim.
    if paraLines.len == 0:
      var n = mdCountLeadingSpaces(line)
      if n > 3: n = 3
      paraLines.add line[n ..< line.len]
    else:
      paraLines.add line
    i.inc
  mdFlushParagraph(result, paraLines)

proc initMarkdown*(markup: string, codeTheme: string = "monokai",
                   justify: Option[JustifyMethod] = none(JustifyMethod),
                   style: StyleType = "none", hyperlinks: bool = true,
                   inlineCodeLexer: Option[string] = none(string),
                   inlineCodeTheme: Option[string] = none(string)): Markdown =
  ## rich markdown.py:549-567 — `Markdown.__init__(self, markup: str,
  ## code_theme: str = "monokai", justify: JustifyMethod | None = None, style:
  ## str | Style = "none", hyperlinks: bool = True, inline_code_lexer:
  ## Optional[str] = None, inline_code_theme: Optional[str] = None) -> None`:
  ## build a `MarkdownIt` parser, `self.parsed = parser.parse(markup)`, store
  ## the fields (markdown.py:556-567). `justify: JustifyMethod | None` →
  ## `Option[JustifyMethod]`; `style: str | Style` keeps the `StyleType`
  ## typeclass (the field is `StyleValue`); `inline_code_*: Optional[str]` →
  ## `Option[string]`. Body needs `markdown_it.MarkdownIt`; stub.
  # Slice 5a: `parseMarkdownBlocks` ports `MarkdownIt('commonmark').parse` for
  ## the block-level subset (markdown.py:554-555); inline parsing (`children`)
  ## is Slice 5b, rendering Slice 5c. All other fields are stored verbatim.
  new(result)
  result.markup = markup
  result.parsed = parseMarkdownBlocks(markup)
  result.codeTheme = codeTheme
  result.justify = justify
  result.style = style
  result.hyperlinks = hyperlinks
  result.inlineCodeLexer = inlineCodeLexer
  result.inlineCodeTheme = if inlineCodeTheme.isSome: inlineCodeTheme
                           else: some(codeTheme)

proc flattenTokens*(self: Markdown, tokens: openArray[Token]): seq[Token] =
  ## rich markdown.py:569-591 — `Markdown._flatten_tokens(self, tokens:
  ## Iterable[Token]) -> Iterable[Token]`: un-nest a token stream (insert inline
  ## children into the top level, markdown.py:573-589). `Iterable[Token]` →
  ## `openArray[Token]` (input) / `seq[Token]` (output). Renamed `_flatten_tokens`
  ## → `flattenTokens`. Slice 5b body: the un-nest (markdown.py:573-589) reads
  ## token.children / token.tag / token.type to splice inline children into the
  ## top level (guarded by token.type == "fence" / token.tag == "img"): a token
  ## that carries children AND is not a fence/image recurses and splices its
  ## children; otherwise it is yielded verbatim. Fences and images keep their
  ## own children intact (markdown.py:575-577).
  for token in tokens:
    let isFence = token.`type` == "fence"
    let isImage = token.tag == "img"
    if token.children.len > 0 and not (isImage or isFence):
      result.add(self.flattenTokens(token.children))
    else:
      result.add(token)

# ---------------------------------------------------------------------------
# Markdown.elements registry — markdown.py:515-531
# ---------------------------------------------------------------------------
## rich `Markdown.elements: ClassVar[dict[str, type[MarkdownElement]]]`
## (markdown.py:515-531): the token-type → element-class registry. A
## `type[MarkdownElement]` (a class) is not storable in Nim, so each entry is a
## factory `proc(markdown, token): MarkdownElement` — the callable analogue of
## `element_class.create(self, token)` (markdown.py:683). Defined here (after
## the element `create` procs) because the lambdas call `Paragraph.create`/
## `Heading.create`/`CodeBlock.create`/`HorizontalRule.create`, which must be in
## scope; `renderConsole` (below) is its sole consumer.
##
## Only the token types the Slice 5a parser emits are registered
## (`paragraph_open`/`heading_open`/`fence`/`hr`) plus `code_block` (the
## indented-code variant — harmless; the parser emits `fence`). The other rich
## entries (`blockquote_open`/`bullet_list_open`/`ordered_list_open`/
## `list_item_open`/`image`/`table_open`/`tbody_open`/`thead_open`/`tr_open`/
## `td_open`/`th_open`) stay unregistered: their `create`/inits are partial
## (e.g. `TableElement`/`BlockQuote`/`ListItem` use `initX`, not a `create`, and
## would construct partially-initialised objects), and the Slice 5a parser
## never emits those tokens (lists/blockquotes/tables fall back to paragraphs),
## so an unregistered token-type falls back to the `UnknownElement` path (a base
## `MarkdownElement` that renders empty) — safe and matching the slice scope.
## Registering the partial factories would risk crashing on the partially-
## initialised objects if a stray token ever hit them.
let elements* = block:
  var t = initTable[string, ElementFactory]()
  t["paragraph_open"] = proc(md: Markdown, tk: Token): MarkdownElement =
    Paragraph.create(md, tk)
  t["heading_open"] = proc(md: Markdown, tk: Token): MarkdownElement =
    Heading.create(md, tk)
  t["fence"] = proc(md: Markdown, tk: Token): MarkdownElement =
    CodeBlock.create(md, tk)
  t["code_block"] = proc(md: Markdown, tk: Token): MarkdownElement =
    CodeBlock.create(md, tk)
  t["hr"] = proc(md: Markdown, tk: Token): MarkdownElement =
    HorizontalRule.create(md, tk)
  t["blockquote_open"] = proc(md: Markdown, tk: Token): MarkdownElement =
    initBlockQuote()
  # bullet_list_open / list_item_open — rich markdown.py:515-531 element
  # registry. The list block parser (parseMarkdownBlocks) emits
  # `bullet_list_open`/`list_item_open`/`paragraph_open`/`inline`/
  # `paragraph_close`/`list_item_close`/`bullet_list_close` tokens for
  # `- `-prefixed lines. `ListElement.create` reads `token.type` to set
  # `listType` (the `bullet_list_open` string); `ListItem` uses `initListItem`
  # (no `create`). The close tokens fall through to `UnknownElement` (popped
  # by the dispatch loop). `ordered_list_open` is not registered (the parser
  # does not emit it; ordered lists are not exercised by the golden cases).
  t["bullet_list_open"] = proc(md: Markdown, tk: Token): MarkdownElement =
    ListElement.create(md, tk)
  t["list_item_open"] = proc(md: Markdown, tk: Token): MarkdownElement =
    initListItem()
  t

proc inlineTagOf(nodeType: string): string =
  ## [Nim-only] derive the inline-style tag from a token `type`. rich's
  ## `markdown_it` sets `token.tag` (`"strong"`/`"em"`/`"code"`/`"s"`) on inline
  ## tokens, and the dispatch loop mirrors rich's `tag in inlines` check
  ## (markdown.py:642). The Slice 5b `parseInline` parser emits inline tokens
  ## with `tag=""` (the tag is encoded in the `type`), so this recovers the tag
  ## from `type`: `strong_open`/`strong_close`→`"strong"`, `em_open`/`em_close`
  ## →`"em"`, `code_inline`→`"code"`, `s_open`/`s_close`→`"s"`. The recovered
  ## tag drives the identical `enter_style("markdown.{tag}")`/`leave_style`
  ## behaviour as rich's tagged tokens (behaviour-faithful despite the parser's
  ## tag-less token shape — the parser is Slice 5b-frozen, not edited here).
  if nodeType.endsWith("_open"):
    result = nodeType[0 ..< nodeType.len - 5]    # strip "_open" (5 chars)
  elif nodeType.endsWith("_close"):
    result = nodeType[0 ..< nodeType.len - 6]    # strip "_close" (6 chars)
  elif nodeType == "code_inline":
    result = "code"
  else:
    result = ""

method renderConsole*(self: Markdown, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich markdown.py:579-704 — `Markdown.__rich_console__(self, console:
  ## Console, options: ConsoleOptions) -> RenderResult`: build a
  ## `MarkdownContext`, iterate `self.flattenTokens(self.parsed)`, drive the
  ## element stack (`onEnter`/`onText`/`onChildClose`/`onLeave`) and yield the
  ## rendered elements via `console.render(element, options)` (markdown.py:695-
  ## 703). A faithful port of the rich dispatch loop. Slice 5c wires the last
  ## gating deps: `console.getStyle`/`console.render` via `console_api`, the
  ## `Stack` push/pop/top/len ops, the populated `elements` registry, and the
  ## `Token` fields (`type`/`tag`/`nesting`/`content` from Slice 5a).
  ##
  ## Scope: the loop handles the inline tokens the Slice 5a/5b parser emits
  ## (`text`/`hardbreak`/`softbreak` + the inline-style tags `strong`/`em`/
  ## `code`/`s` + `link_open`/`link_close`) and the block tokens
  ## (`paragraph_open`/`heading_open`/`fence`/`code_block`/`hr`/
  ## `blockquote_open`/`blockquote_close`). The `link_open`/`link_close` branches
  ## (markdown.py:608-640) apply `markdown.link_url` + `Style(link=href)` when
  ## `self.hyperlinks` is true (the default); the `html_inline`/`<kbd>` paths
  ## remain deferred.
  # `style = console.get_style(self.style, default="none")` (markdown.py:695).
  # `Markdown.style` is a `StyleValue` (`Union[str, Style]`): a `str` arm
  # resolves through the Console theme; a `Style` arm is the style itself.
  let baseStyle = case self.style.kind
    of svkStr: console.getStyle(self.style.strv, default = "none")
    of svkStyle: self.style.stv
  # `options = options.update(height=None)` (markdown.py:696) — unbounded
  # height so every block renders.
  let opts = options.update(height = setChange(none(int)))
  let context = initMarkdownContext(console, opts, baseStyle,
      self.inlineCodeLexer,
      if self.inlineCodeTheme.isSome: self.inlineCodeTheme.get else: "monokai")
  let tokens = self.flattenTokens(self.parsed)
  result = @[]
  var newLine = false
  for token in tokens:
    let nodeType = token.`type`
    let tag = token.tag
    # The Slice 5b parser emits inline tokens (`strong_open`/`em_open`/
    # `code_inline`/…) with `tag=""` (the tag is encoded in `type`); rich's
    # markdown_it sets `token.tag`. Derive the effective inline tag from `type`
    # when `tag` is empty, so the inline-style dispatch matches rich's `tag in
    # inlines` check (markdown.py:642) behaviour-faithfully.
    let effTag = if tag.len > 0: tag else: inlineTagOf(nodeType)
    let entering = token.nesting == 1
    let exiting = token.nesting == -1
    let selfClosing = token.nesting == 0
    if nodeType == "text":
      context.onText(token.content, "text")
    elif nodeType == "hardbreak":
      context.onText("\n", "hardbreak")
    elif nodeType == "softbreak":
      context.onText(" ", "softbreak")
    elif effTag in inlines and nodeType != "fence" and nodeType != "code_block":
      # Inline style tags (markdown.py:642-661): `strong`/`em`/`code`/`s`.
      # entering (nesting +1) → `enter_style("markdown.{effTag}")`; exiting
      # (nesting -1) → `leave_style`; self-closing (code_inline, nesting 0) →
      # enter_style + on_text(content) + leave_style.
      if entering:
        discard context.enterStyle("markdown." & effTag)
      elif exiting:
        discard context.leaveStyle()
      else:
        discard context.enterStyle("markdown." & effTag)
        if token.content.len > 0:
          context.onText(token.content, nodeType)
        discard context.leaveStyle()
    elif nodeType == "link_open":
      # markdown.py:608-616 — `link_open`: if `self.hyperlinks`, create
      # `link_style = console.get_style("markdown.link_url", default="none") +
      # Style(link=href)` and `enter_style`; else push a `Link` element.
      let href = if token.attrs.isSome and token.attrs.get.hasKey("href"):
                   token.attrs.get["href"] else: ""
      if self.hyperlinks:
        let baseStyle = console.getStyle("markdown.link_url", default = "none")
        let linkStyle = baseStyle + some(initStyle(link = some(href)))
        discard context.enterStyle(linkStyle)
      else:
        var linkEl = initLink("", href)
        context.stack.push(linkEl)
        linkEl.onEnter(context)
    elif nodeType == "link_close":
      # markdown.py:628-640 — `link_close`: if `self.hyperlinks`, `leave_style`;
      # else pop the `Link` element, render its text as `markdown.link`-styled
      # text followed by ` (href)`.
      if self.hyperlinks:
        discard context.leaveStyle()
      else:
        let element = context.stack.pop()
        discard context.enterStyle("markdown.link")
        context.onText(Link(element).text.plain, "link_close")
        discard context.leaveStyle()
        context.onText(" (", "link_close")
        discard context.enterStyle("markdown.link_url")
        context.onText(Link(element).href, "link_close")
        discard context.leaveStyle()
        context.onText(")", "link_close")
    else:
      # Block element (markdown.py:663-702): `element_class = elements.get(
      # token.type) or UnknownElement`; `element = element_class.create(...)`.
      var element: MarkdownElement
      if elements.hasKey(nodeType):
        element = elements[nodeType](self, token)
      else:
        # `UnknownElement` fallback — rich `elements.get(token.type) or
        # UnknownElement` (markdown.py:665); a close token (`heading_close`/…)
        # is unregistered → a base `MarkdownElement` (discarded on `exiting` by
        # the stack pop). Renders empty (base `renderConsole`).
        element = MarkdownElement.create(self, token)
      if entering or selfClosing:
        context.stack.push(element)
        element.onEnter(context)
      if exiting:
        # CLOSING tag (markdown.py:679-693): pop the OPEN element; the parent
        # (`stack.top`) decides via `onChildClose` whether to render it.
        element = context.stack.pop()
        let shouldRender = context.stack.len == 0 or
            context.stack.top.onChildClose(context, element)
        if shouldRender:
          if newLine:
            addSegment(result, line())
          result.add(console.render(toRenderableValue(element),
                                    some(context.options)))
      elif selfClosing:
        # SELF-CLOSING tag (markdown.py:685-699): pop; `text = token.content`;
        # `if text is not None: element.on_text(...)`; render.
        discard context.stack.pop()
        element.onText(context, token.content)
        let shouldRender = context.stack.len == 0 or
            context.stack.top.onChildClose(context, element)
        if shouldRender:
          if newLine and nodeType != "inline":
            addSegment(result, line())
          result.add(console.render(toRenderableValue(element),
                                    some(context.options)))
      if exiting or selfClosing:
        element.onLeave(context)
        newLine = element.newLine
