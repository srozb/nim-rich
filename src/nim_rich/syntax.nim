## Port of `rich.syntax` (rich/syntax.py, 988 lines).
##
## `syntax` renders syntax-highlighted source code via Pygments: the
## `Syntax(JupyterMixin)` renderable (syntax.py:243-842) plus the
## `SyntaxTheme(ABC)` theme hierarchy (`PygmentsSyntaxTheme`/`ANSISyntaxTheme`,
## syntax.py:127-214), the ANSI theme tables (`ANSI_LIGHT`/`ANSI_DARK`/
## `RICH_SYNTAX_THEMES`, syntax.py:65-124), the `_SyntaxHighlightRange`
## NamedTuple (syntax.py:219-229) and the `PaddingProperty` descriptor
## (syntax.py:232-242).
##
## Import graph (rich/syntax.py:1-55): runtime stdlib imports are `os.path`,
## `re`, `sys`, `textwrap`, `abc.ABC`/`abstractmethod`, `pathlib.Path`,
## `typing.{…}` (syntax.py:3-22); Pygments imports are `Lexer`, `get_lexer_by_name`,
## `guess_lexer_for_filename`, `PygmentsStyle` (`pygments.style.Style as
## PygmentsStyle`), `get_style_by_name`, the `Comment`/`Error`/`Generic`/
## `Keyword`/`Name`/`Number`/`Operator`/`String`/`Token`/`Whitespace` token
## constants, and `ClassNotFound` (syntax.py:24-40); rich sibling imports are
## `from rich.containers import Lines` (syntax.py:45), `from rich.padding
## import Padding, PaddingDimensions` (syntax.py:46), `from ._loop import
## loop_first` (syntax.py:48), `from .cells import cell_len` (syntax.py:49),
## `from .color import Color, blend_rgb` (syntax.py:50), `from .jupyter
## import JupyterMixin` (syntax.py:51), `from .measure import Measurement`
## (syntax.py:52), `from .segment import Segment, Segments` (syntax.py:53),
## `from .style import Style, StyleType` (syntax.py:54), `from .text import
## Text` (syntax.py:55). TYPE_CHECKING-only (syntax.py:42): `Console`,
## `ConsoleOptions`, `JustifyMethod`, `RenderResult` (supplied via richbase
## placeholders through `segment`).
##
## wiring (this file):
##   `import std/options` — `Option[int]`/`Option[string]`/`Option[HashSet[int]]`/
##   `import std/sets`     — `HashSet[int]` (`highlight_lines: Set[int]`).
##   `import std/tables`   — `Table`/`initTable`/`toTable` (the ANSI theme tables
##                           `Dict[TokenType, Style]` and `RICH_SYNTAX_THEMES`).
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                           `ConsoleOptions`, `RenderResult`, `RenderableType`,
##                           `RenderableBase`, `JustifyMethod`, …) + `Segment` +
##                           `Segments` + `Style` (re-exported).
##   `import style`        — `Style`, `StyleType` (syntax.py:54).
##   `import text`         — `Text` (syntax.py:55) + `StyleValue` (the storable
##                           `Union[str, Style]` handle for the
##                           `SyntaxHighlightRange.style` field).
##   `import cells`        — `cellLen` (syntax.py:49; `__rich_measure__` body
##                           dep — graph faithfulness, accepts the Phase-0
##                           unused warning).
##   `import color`        — `Color`, `blendRgb` (syntax.py:50; the
##                           `_get_token_color`/`_get_line_numbers_color`
##                           returns/body — `Color` is a signature dep via
##                           `_get_token_color -> Optional[Color]`).
##   `import jupyter`      — `JupyterMixin` (syntax.py:51, the `Syntax` base —
##                           now present post-, so `Syntax = ref object
##                           of JupyterMixin`, faithful to `class
##                           Syntax(JupyterMixin)`).
##   `import measure`      — `Measurement` (syntax.py:52, the `richMeasure`
##                           return).
##   `import padding`      — `Padding`, `PaddingDimensions` (syntax.py:46).
##   `import containers`   — `Lines` (syntax.py:45; the `_get_syntax` body
##                           local `lines: Union[List[Text], Lines]` — body dep,
##                           graph faithfulness, accepts the unused warning).
##
## Pygments is NOT ported (an external C-extension-backed library); its types
## (`Lexer`, `PygmentsStyle`-as-class, the token constants,
## `get_lexer_by_name`/`guess_lexer_for_filename`/`get_style_by_name`,
## `ClassNotFound`) are modelled as [NON-NARROWING PROVISIONAL FORWARD HANDLES]:
## `Lexer*`/`PygmentsStyleClass*` are `ref object of RootObj` placeholders, and
## the token constants are not needed for signatures (the ANSI theme tables
## use `TokenType* = string` — the dotted pygments token name, e.g.
## `"Comment.Preproc"`; pygments `Token` tuples map to these dotted strings,
## which are hashable as `Table` keys — pygments `Token` tuples are not).
## `_loop.loop_first` (syntax.py:48) is a BODY-only dep (`_get_syntax` iterates
## `loop_first(wrapped_lines)`, syntax.py:759) — deferred to body.
## `os.path`/`re`/`sys`/`textwrap`/`abc`/`pathlib` are stdlib — used only in
## bodies, deferred to body. `Console`/`ConsoleOptions`/`JustifyMethod`/
## `RenderResult` are TYPE_CHECKING-only in rich (syntax.py:42) — supplied via
## richbase placeholders; the `_get_number_styles`/`_get_syntax` helpers take a
## `ConsoleHandle` (the console flows from `renderConsole`/`richMeasure` which
## receive `ConsoleHandle`), so `console.nim` is NOT imported here (mirroring
## rich's TYPE_CHECKING-only `Console` import).
##
## `WINDOWS` (syntax.py:59) is NOT redeclared — `color.nim:81` exports
## `WINDOWS* = defined(windows)` (same value); re-exporting both via the
## umbrella would make `WINDOWS` ambiguous (Nim `let`/`const` symbols don't
## overload across modules — the convention `console.nim`/`traceback.nim`
## follow), so the shared `color.WINDOWS` is used. `DEFAULT_THEME`/`ANSI_LIGHT`/
## `ANSI_DARK`/`RICH_SYNTAX_THEMES`/`NUMBERS_COLUMN_DEFAULT_PADDING` are
## module-level values (consts verbatim; the theme tables are empty
## `` placeholders, populated in body — mirroring
## `default_styles.nim`'s `DEFAULT_STYLES*` pattern).
##
## `SyntaxPosition = Tuple[int, int]` (syntax.py:216) → `tuple[line: int,
## column: int]`. NOTE: `traceback.nim` (frozen,) already declares a
## PROVISIONAL `SyntaxPosition* = tuple[line: int, column: int]` for its
## `iterSyntaxLines` signature (documented "replace with `import syntax` when
## landed"); THIS module declares the real `SyntaxPosition`. Both are public
## and the umbrella exports both → a lazy ambiguous re-export (like the dual
## `EmojiVariant`/`Control`/`Pager`), which compiles (Nim resolves the
## ambiguity only at a bare use site, which the umbrella/binary never do).
## body reconciles by dropping `traceback.nim`'s provisional and importing
## this `syntax.SyntaxPosition`.
##
## `SyntaxTheme(ABC)`/`PygmentsSyntaxTheme(SyntaxTheme)`/`ANSISyntaxTheme(
## SyntaxTheme)` (syntax.py:127-214) → `ref object of RootObj`/`ref object of
## SyntaxTheme` (the `ABC` base is modelled by documented abstract procs;
## `abstractmethod` → base procs subclasses override). `Syntax(JupyterMixin)`
## (syntax.py:243) → `ref object of JupyterMixin`. `_SyntaxHighlightRange(
## NamedTuple)` (syntax.py:219) → `SyntaxHighlightRange* = object` (drop the
## `_` private marker; `end`→`endPos` — `end` is a Nim keyword). `PaddingProperty`
## (syntax.py:232) is a Python descriptor → a placeholder `ref object of
## RootObj` (no Nim analogue; the `padding` get/set on `Syntax` is modelled by
## the `padding*` getter / `padding=` setter procs, storage `paddingField*`).
## Naming: `__init__`→`initSyntax`; `from_path`→`fromPath` (classmethod,
## `T: typedesc[Syntax]`); `guess_lexer`→`guessLexer`; `get_theme`→`getTheme`;
## `__rich_console__`→`renderConsole`; `__rich_measure__`→`richMeasure`;
## `_get_base_style`→`getBaseStyle`; `_get_token_color`→`getTokenColor`;
## `_get_line_numbers_color`→`getLineNumbersColor`; `_numbers_column_width`→
## `numbersColumnWidth`; `_get_number_styles`→`getNumberStyles`;
## `_get_syntax`→`getSyntax`; `_apply_stylized_ranges`→`applyStylizedRanges`;
## `_process_code`→`processCode`; `stylize_range`→`stylizeRange`;
## `_get_code_index_for_syntax_position`→`getCodeIndex`; the `_`-prefixed fields
## (`_lexer`/`_theme`/`_padding`/`_stylized_ranges`/`_pygments_style_class`/
## `_style_cache`/`_missing_style`/`_background_style`/`_background_color`) →
## `lexerField`/`themeField`/`paddingField`/`stylizedRanges`/
## `pygmentsStyleClass`/`styleCache`/`missingStyle`/`backgroundStyleField`/
## `backgroundColor`. Proc bodies mirror the Python source.

import std/options
import std/sets
import std/tables
import std/strutils  # count/endsWith/splitLines/rfind/strip -- processCode/richMeasure/getCodeIndex/ANSI walk.
import std/strmisc   # expandTabs -- processCode (textwrap.dedent via a local helper; expandtabs via strmisc).

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableType, RenderableBase, JustifyMethod, …) +
                    # Segment + Segments + Style.
import nim_rich/style as richstyle
import text as richtext   # Text (syntax.py:55) + StyleValue (the Union[str, Style]
                    # field handle for SyntaxHighlightRange.style).
import cells        # cellLen (syntax.py:49; __rich_measure__ body dep — graph
                    # faithfulness, accepts the Phase-0 unused warning).
import color        # Color, blendRgb (syntax.py:50; _get_token_color return +
                    # _get_line_numbers_color body).
import jupyter      # JupyterMixin (syntax.py:51, the Syntax base).
import measure      # Measurement (syntax.py:52, the richMeasure return).
import padding      # Padding, PaddingDimensions (syntax.py:46).
import containers   # Lines (syntax.py:45; _get_syntax body local — body dep,
                    # graph faithfulness, accepts the unused warning).
import nimgments except style   # Pygments-compatible lexer toolkit (Syntax highlighting).
                    # Replaces the DEFERRED(Pygments) stubs: lexer resolution,
                    # token stream, and style-for-token lookup. nimgments is an
                    # optional dep — Syntax degrades to plain text without it
                    # (mirrors rich when a lexer is missing).

type
  TokenType* = string
    ## rich syntax.py:57 — `TokenType = Tuple[str, ...]`: a Pygments token type
    ## (e.g. `("Comment", "Preproc")`). Modelled as `string` — the dotted
    ## pygments token name (`"Comment.Preproc"`, `""` for the root `Token`):
    ## faithful to the token identity AND hashable as a `Table` key (pygments
    ## tuples are not hashable in Nim). Non-narrowing (every pygments token maps
    ## to its dotted name).

  Lexer* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `pygments.lexer.Lexer`
    ## (syntax.py:24). Pygments is not ported; this `ref object of RootObj`
    ## placeholder lets the `_lexer` field, the `lexer`/`defaultLexer`
    ## properties and the `LexerOrStr` union declare their types now. Removed
    ## when a Pygments binding lands (body+). NOT a faithful port of `Lexer`.

  PygmentsStyleClass* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `pygments.style.Style` (as
    ## a class — `Type[PygmentsStyle]`, syntax.py:26,141). Pygments is not
    ## ported; a class object is not storable in Nim, so this `ref object of
    ## RootObj` placeholder stands in for the resolved style class held by
    ## `PygmentsSyntaxTheme.pygmentsStyleClass`. Removed when a Pygments binding
    ## lands. NOT a faithful port.

  LexerOrStrKind* = enum
    ## [Nim-only discriminator] for `LexerOrStr` — the two arms of
    ## `Union[Lexer, str]` (syntax.py:283, the `Syntax.__init__` `lexer` param
    ## and the `_lexer` field).
    losLexer  ## the `Lexer` arm — a Pygments lexer instance.
    losStr    ## the `str` arm — a lexer alias/name (`"python"`, `"text"`).

  LexerOrStr* = object
    ## rich syntax.py:243 — `lexer: Union[Lexer, str]` as a Nim case object
    ## (non-narrowing): either a Pygments `Lexer` instance or a lexer name
    ## string. Stored in the `lexerField` field; the `lexer` property resolves
    ## the str arm to a `Lexer`.
    case kind*: LexerOrStrKind
    of losLexer:
      lexer*: Lexer        ## the `Lexer` arm — a Pygments lexer instance.
    of losStr:
      s*: string           ## the `str` arm — a lexer alias/name.

  PygmentsThemeArgKind* = enum
    ## [Nim-only discriminator] for `PygmentsThemeArg` — the two arms of
    ## `Union[str, Type[PygmentsStyle]]` (syntax.py:143, the
    ## `PygmentsSyntaxTheme.__init__` `theme` param).
    ptaStr    ## the `str` arm — a pygments style name (`"monokai"`).
    ptaClass  ## the `Type[PygmentsStyle]` arm — a pygments style class.

  PygmentsThemeArg* = object
    ## rich syntax.py:143 — `theme: Union[str, Type[PygmentsStyle]]` as a Nim
    ## case object (non-narrowing): either a style name string or a pygments
    ## style class (the `PygmentsStyleClass` handle).
    case kind*: PygmentsThemeArgKind
    of ptaStr:
      s*: string                  ## the `str` arm — a style name.
    of ptaClass:
      c*: PygmentsStyleClass      ## the class arm — a pygments style class.

  SyntaxThemeArgKind* = enum
    ## [Nim-only discriminator] for `SyntaxThemeArg` — the two arms of
    ## `Union[str, SyntaxTheme]` (syntax.py:258, the `Syntax.__init__`/`getTheme`
    ## `theme` param).
    staStr    ## the `str` arm — a theme name (`"monokai"`, `"ansi_dark"`).
    staTheme  ## the `SyntaxTheme` arm — a pre-built theme instance.

  SyntaxThemeArg* = object
    ## rich syntax.py:258 — `theme: Union[str, SyntaxTheme] = DEFAULT_THEME` as
    ## a Nim case object (non-narrowing). Default `SyntaxThemeArg(kind: staStr,
    ## s: DEFAULT_THEME)` (the rich default `"monokai"`).
    case kind*: SyntaxThemeArgKind
    of staStr:
      s*: string            ## the `str` arm — a theme name.
    of staTheme:
      t*: SyntaxTheme       ## the `SyntaxTheme` arm — a theme instance.

  LineRange* = tuple[start: Option[int], endIdx: Option[int]]
    ## rich syntax.py:283 — `line_range: Optional[Tuple[Optional[int],
    ## Optional[int]]]`: the (start, end) line range to render, each `None` for
    ## an open end. `end`→`endIdx` (`end` is a Nim keyword). The `__init__` form
    ## (both `Optional[int]`).

  LineRangeInt* = tuple[start: int, endIdx: int]
    ## rich syntax.py:333 — `line_range: Optional[Tuple[int, int]]` (the
    ## `from_path` form — both concrete `int`). `end`→`endIdx`.

  SyntaxPosition* = tuple[line: int, column: int]
    ## rich syntax.py:216 — `SyntaxPosition = Tuple[int, int]`: a (line number
    ## (1-based), column index (0-based)) position. The real declaration;
    ## `traceback.nim`'s provisional `SyntaxPosition` is replaced by
    ## `import syntax` in body.

  SyntaxHighlightRange* = object
    ## rich syntax.py:219-229 — `_SyntaxHighlightRange(NamedTuple)`: a range to
    ## highlight in a `Syntax` (drop the `_` private marker). NamedTuple → a
    ## named-field object. `end`→`endPos` (`end` is a Nim keyword).
    style*: StyleValue
      ## rich syntax.py:222 — `style: StyleType` (the style to apply; the
      ## `Union[str, Style]` → `StyleValue` storable handle).
    start*: SyntaxPosition
      ## rich syntax.py:223 — `start: SyntaxPosition`.
    endPos*: SyntaxPosition
      ## rich syntax.py:224 — `end: SyntaxPosition` (renamed `end`→`endPos`).
    styleBefore*: bool
      ## rich syntax.py:225 — `style_before: bool = False` (apply the style
      ## before existing styles).

  PaddingProperty* = ref object of RootObj
    ## rich syntax.py:232-242 — `class PaddingProperty`: a Python descriptor
    ## (`__get__`→`obj._padding`, `__set__`→`obj._padding = Padding.unpack(
    ## padding)`) backing the `Syntax.padding` property. A descriptor has no
    ## direct Nim analogue; the `padding` get/set on `Syntax` is modelled by
    ## the `padding*` getter / `padding=` setter procs and the `paddingField`
    ## storage. This placeholder documents the rich class; NOT a faithful port.

  SyntaxTheme* = ref object of RootObj
    ## rich syntax.py:127-138 — `class SyntaxTheme(ABC)`: base class for a
    ## syntax theme. `ref object of RootObj` (the `ABC` base is modelled by
    ## documented abstract procs `getStyleForToken`/`getBackgroundStyle` that
    ## subclasses override; Nim has no `abstractmethod`).

  PygmentsSyntaxTheme* = ref object of SyntaxTheme
    ## rich syntax.py:141-178 — `class PygmentsSyntaxTheme(SyntaxTheme)`: a
    ## syntax theme delegating to a Pygments style. Fields mirror the
    ## `__init__` assignments (syntax.py:148-155).
    styleCache*: Table[TokenType, Style]
      ## rich syntax.py:148 — `self._style_cache: Dict[TokenType, Style] = {}` (renamed `_style_cache`→`styleCache`).
    pygmentsStyleClass*: PygmentsStyleClass
      ## rich syntax.py:149-152 — `self._pygments_style_class = get_style_by_name(theme) or get_style_by_name("default")` (the resolved pygments style class; renamed).
    backgroundColor*: string
      ## rich syntax.py:154 — `self._background_color = self._pygments_style_class.background_color` (the pygments bg color string; renamed `_background_color`→`backgroundColor`).
    styleName*: string
      ## [Nim-only] the resolved nimgments style name (e.g. "monokai", "default").
      ## Stashed so `getStyleForToken` can re-resolve via `nimgments.getStyleByName`.
      ## Replaces the `PygmentsStyleClass` class-object handle (Nim has no class objects).
    backgroundStyleField*: Style
      ## rich syntax.py:155 — `self._background_style = Style(bgcolor=self._background_color)` (the `Style` bg; renamed `_background_style`→`backgroundStyleField` to avoid clashing with the `getBackgroundStyle` proc).

  ANSISyntaxTheme* = ref object of SyntaxTheme
    ## rich syntax.py:183-214 — `class ANSISyntaxTheme(SyntaxTheme)`: a syntax
    ## theme using standard ANSI colors from a `Dict[TokenType, Style]` map.
    ## Fields mirror the `__init__` assignments (syntax.py:191-195).
    styleMap*: Table[TokenType, Style]
      ## rich syntax.py:191 — `self.style_map = style_map` (`Dict[TokenType, Style]`; `Table[TokenType, Style]`).
    missingStyle*: Style
      ## rich syntax.py:192 — `self._missing_style = Style.null()` (`Style`; renamed `_missing_style`→`missingStyle`).
    backgroundStyleField*: Style
      ## rich syntax.py:193 — `self._background_style = Style.null()` (`Style`; renamed to avoid clashing with the `getBackgroundStyle` proc).
    styleCache*: Table[TokenType, Style]
      ## rich syntax.py:194 — `self._style_cache: Dict[TokenType, Style] = {}` (renamed).

  Syntax* = ref object of JupyterMixin
    ## rich syntax.py:243-842 — `class Syntax(JupyterMixin)`: a syntax-highlighted
    ## code renderable. `ref object of JupyterMixin` (the base now present,
    ## faithful to `class Syntax(JupyterMixin)`). Fields mirror the `__init__`
    ## assignments (syntax.py:282-297).
    code*: string
      ## rich syntax.py:283 — `self.code = code` (`str`).
    lexerField*: LexerOrStr
      ## rich syntax.py:283 — `self._lexer = lexer` (`Union[Lexer, str]`; the `LexerOrStr` handle; renamed `_lexer`→`lexerField`).
    dedent*: bool
      ## rich syntax.py:284 — `self.dedent = dedent` (`bool`; default `False`).
    lineNumbers*: bool
      ## rich syntax.py:285 — `self.line_numbers = line_numbers` (`bool`; default `False`).
    startLine*: int
      ## rich syntax.py:286 — `self.start_line = start_line` (`int`; default `1`).
    lineRange*: Option[LineRange]
      ## rich syntax.py:287 — `self.line_range = line_range` (`Optional[Tuple[Optional[int], Optional[int]]]`; `Option[LineRange]`, default `none(LineRange)`).
    highlightLines*: HashSet[int]
      ## rich syntax.py:288 — `self.highlight_lines = highlight_lines or set()` (`Set[int]`; `HashSet[int]`, default empty).
    codeWidth*: Option[int]
      ## rich syntax.py:289 — `self.code_width = code_width` (`Optional[int]`; `Option[int]`, default `none(int)`).
    tabSize*: int
      ## rich syntax.py:290 — `self.tab_size = tab_size` (`int`; default `4`).
    wordWrap*: bool
      ## rich syntax.py:291 — `self.word_wrap = word_wrap` (`bool`; default `False`).
    backgroundColor*: Option[string]
      ## rich syntax.py:292 — `self.background_color = background_color` (`Optional[str]`; `Option[string]`, default `none(string)`).
    backgroundStyle*: Style
      ## rich syntax.py:293 — `self.background_style = Style(bgcolor=background_color) if background_color else Style()` (`Style`).
    indentGuides*: bool
      ## rich syntax.py:294 — `self.indent_guides = indent_guides` (`bool`; default `False`).
    paddingField*: PaddingDimensions
      ## rich syntax.py:295 — `self._padding = Padding.unpack(padding)` (`PaddingDimensions`; the `PaddingProperty` storage; renamed `_padding`→`paddingField`).
    themeField*: SyntaxTheme
      ## rich syntax.py:296 — `self._theme = self.get_theme(theme)` (`SyntaxTheme`; the resolved theme; renamed `_theme`→`themeField`).
    stylizedRanges*: seq[SyntaxHighlightRange]
      ## rich syntax.py:297 — `self._stylized_ranges: List[_SyntaxHighlightRange] = []` (renamed `_stylized_ranges`→`stylizedRanges`).

# ---------------------------------------------------------------------------
# Module-level values — syntax.py:57-124
# ---------------------------------------------------------------------------

const DEFAULT_THEME* = "monokai"
  ## rich syntax.py:60 — `DEFAULT_THEME = "monokai"`: the default Pygments theme.

const NUMBERS_COLUMN_DEFAULT_PADDING* = 2
  ## rich syntax.py:124 — `NUMBERS_COLUMN_DEFAULT_PADDING = 2`: chars of padding
  ## in the line-numbers column.

let ANSI_LIGHT*: Table[TokenType, Style] = {
  "": initStyle(),
  "Whitespace": initStyle(color = "white"),
  "Comment": initStyle(dim = some(true)),
  "Comment.Preproc": initStyle(color = "cyan"),
  "Keyword": initStyle(color = "blue"),
  "Keyword.Type": initStyle(color = "cyan"),
  "Operator.Word": initStyle(color = "magenta"),
  "Name.Builtin": initStyle(color = "cyan"),
  "Name.Function": initStyle(color = "green"),
  "Name.Namespace": initStyle(color = "cyan", underline = some(true)),
  "Name.Class": initStyle(color = "green", underline = some(true)),
  "Name.Exception": initStyle(color = "cyan"),
  "Name.Decorator": initStyle(color = "magenta", bold = some(true)),
  "Name.Variable": initStyle(color = "red"),
  "Name.Constant": initStyle(color = "red"),
  "Name.Attribute": initStyle(color = "cyan"),
  "Name.Tag": initStyle(color = "bright_blue"),
  "String": initStyle(color = "yellow"),
  "Number": initStyle(color = "blue"),
  "Generic.Deleted": initStyle(color = "bright_red"),
  "Generic.Inserted": initStyle(color = "green"),
  "Generic.Heading": initStyle(bold = some(true)),
  "Generic.Subheading": initStyle(color = "magenta", bold = some(true)),
  "Generic.Prompt": initStyle(bold = some(true)),
  "Generic.Error": initStyle(color = "bright_red"),
  "Error": initStyle(color = "red", underline = some(true)),
}.toTable()
  ## rich syntax.py:65-91 — `ANSI_LIGHT: Dict[TokenType, Style]`: the light ANSI
  ## theme map (Token→Style). placeholder (empty table, ``);
  ## body populates the 23 Token→Style entries (syntax.py:66-90).

let ANSI_DARK*: Table[TokenType, Style] = {
  "": initStyle(),
  "Whitespace": initStyle(color = "bright_black"),
  "Comment": initStyle(dim = some(true)),
  "Comment.Preproc": initStyle(color = "bright_cyan"),
  "Keyword": initStyle(color = "bright_blue"),
  "Keyword.Type": initStyle(color = "bright_cyan"),
  "Operator.Word": initStyle(color = "bright_magenta"),
  "Name.Builtin": initStyle(color = "bright_cyan"),
  "Name.Function": initStyle(color = "bright_green"),
  "Name.Namespace": initStyle(color = "bright_cyan", underline = some(true)),
  "Name.Class": initStyle(color = "bright_green", underline = some(true)),
  "Name.Exception": initStyle(color = "bright_cyan"),
  "Name.Decorator": initStyle(color = "bright_magenta", bold = some(true)),
  "Name.Variable": initStyle(color = "bright_red"),
  "Name.Constant": initStyle(color = "bright_red"),
  "Name.Attribute": initStyle(color = "bright_cyan"),
  "Name.Tag": initStyle(color = "bright_blue"),
  "String": initStyle(color = "yellow"),
  "Number": initStyle(color = "bright_blue"),
  "Generic.Deleted": initStyle(color = "bright_red"),
  "Generic.Inserted": initStyle(color = "bright_green"),
  "Generic.Heading": initStyle(bold = some(true)),
  "Generic.Subheading": initStyle(color = "bright_magenta", bold = some(true)),
  "Generic.Prompt": initStyle(bold = some(true)),
  "Generic.Error": initStyle(color = "bright_red"),
  "Error": initStyle(color = "red", underline = some(true)),
}.toTable()
  ## rich syntax.py:94-120 — `ANSI_DARK: Dict[TokenType, Style]`: the dark ANSI
  ## theme map. placeholder (empty table, ``); body
  ## populates the 23 entries (syntax.py:95-119).

let RICH_SYNTAX_THEMES* = {"ansi_light": ANSI_LIGHT,
                                   "ansi_dark": ANSI_DARK}.toTable()
  ## rich syntax.py:123 — `RICH_SYNTAX_THEMES = {"ansi_light": ANSI_LIGHT,
  ## "ansi_dark": ANSI_DARK}`: the built-in theme registry (name→theme map).
  ## placeholder (``); `toTable()` builds the
  ## `Table[string, Table[TokenType, Style]]` from the placeholder tables above.

# ---------------------------------------------------------------------------
# SyntaxTheme — syntax.py:127-214
# ---------------------------------------------------------------------------

proc getStyleForToken*(self: SyntaxTheme, tokenType: TokenType): Style =
  ## rich syntax.py:131-133 — `SyntaxTheme.get_style_for_token(self, token_type:
  ## TokenType) -> Style` (`@abstractmethod`): get a style for a Pygments token.
  ## The base abstract declaration; `PygmentsSyntaxTheme`/`ANSISyntaxTheme`
  ## override it.
  discard

proc getBackgroundStyle*(self: SyntaxTheme): Style =
  ## rich syntax.py:135-137 — `SyntaxTheme.get_background_style(self) -> Style`
  ## (`@abstractmethod`): get the background style. The base abstract
  ## declaration; subclasses override it.
  discard

proc initPygmentsSyntaxTheme*(theme: PygmentsThemeArg): PygmentsSyntaxTheme =
  ## rich syntax.py:143-155 — `PygmentsSyntaxTheme.__init__(self, theme:
  ## Union[str, Type[PygmentsStyle]]) -> None`: resolve the pygments style class
  ## (`get_style_by_name(theme)` or `"default"` on `ClassNotFound`), set the
  ## background color/style, init an empty style cache (syntax.py:148-155).
  ## `theme: Union[str, Type[PygmentsStyle]]` → `PygmentsThemeArg`
  ## (non-narrowing). body: wired to nimgments `getStyleByName`.
  result = PygmentsSyntaxTheme()
  result.styleCache = initTable[TokenType, Style]()
  case theme.kind
  of ptaStr:
    # nimgments: getStyleByName raises ValueError on unknown style — fallback
    # to "default" (mirrors rich's ClassNotFound handling, syntax.py:149-152).
    try:
      discard nimgments.getStyleByName(theme.s)
      result.pygmentsStyleClass = nil  # placeholder; we re-resolve by name below
      result.styleName = theme.s
    except ValueError:
      result.pygmentsStyleClass = nil
      result.styleName = "default"
  of ptaClass:
    result.pygmentsStyleClass = theme.c
    result.styleName = "default"
  # nimgments: background_color + highlight_color are fields on the style.
  let pgStyle = nimgments.getStyleByName(result.styleName)
  result.backgroundColor = pgStyle.backgroundColor
  result.backgroundStyleField = initStyle(bgcolor = result.backgroundColor)

proc getStyleForToken*(self: PygmentsSyntaxTheme, tokenType: TokenType): Style =
  ## rich syntax.py:157-171 — `PygmentsSyntaxTheme.get_style_for_token(self,
  ## token_type: TokenType) -> Style`: look up the cache, else build a `Style`
  ## from `pygments_style_class.style_for_token(token_type)` (syntax.py:159-170).
  ## Overrides the base. body: wired to nimgments `styleForToken`.
  if self.styleCache.hasKey(tokenType):
    return self.styleCache[tokenType]
  # nimgments: resolve the token-type string ("Comment.Preproc" / "" for root)
  # to a TokenType singleton, then look up the style. KeyError -> Style.null().
  let pgStyle = nimgments.getStyleByName(self.styleName)
  let tt = if tokenType == "": nimgments.Token else: nimgments.tt(tokenType)
  let attrs = pgStyle.styleForToken(tt)
  # rich syntax.py:164-170: color -> "#"+color or "#000000", bgcolor -> "#"+bgcolor
  # or background_color; bold/italic/underline from the pygments style.
  let color = if attrs.color.len > 0: "#" & attrs.color else: "#000000"
  let bgcolor = if attrs.bgcolor.len > 0: "#" & attrs.bgcolor else: self.backgroundColor
  result = initStyle(color = color, bgcolor = bgcolor,
                     bold = some(attrs.bold), italic = some(attrs.italic),
                     underline = some(attrs.underline))
  self.styleCache[tokenType] = result

proc getBackgroundStyle*(self: PygmentsSyntaxTheme): Style =
  ## rich syntax.py:173-174 — `PygmentsSyntaxTheme.get_background_style(self)
  ## -> Style`: `return self.backgroundStyleField` (syntax.py:174). Overrides
  ## the base.
  if self.backgroundStyleField.isNil:
    return Style.null()
  return self.backgroundStyleField

proc initAnsiSyntaxTheme*(styleMap: Table[TokenType, Style]): ANSISyntaxTheme =
  ## rich syntax.py:189-195 — `ANSISyntaxTheme.__init__(self, style_map:
  ## Dict[TokenType, Style]) -> None`: store `style_map`, set
  ## `_missing_style = Style.null()`, `_background_style = Style.null()`, init
  ## an empty style cache (syntax.py:191-195). `style_map: Dict[TokenType,
  ## Style]` → `Table[TokenType, Style]`.
  result = ANSISyntaxTheme()
  result.styleMap = styleMap
  result.missingStyle = Style.null()
  result.backgroundStyleField = Style.null()
  result.styleCache = initTable[TokenType, Style]()

proc getStyleForToken*(self: ANSISyntaxTheme, tokenType: TokenType): Style =
  ## rich syntax.py:197-211 — `ANSISyntaxTheme.get_style_for_token(self,
  ## token_type: TokenType) -> Style`: look up the cache, else walk the token
  ## hierarchy (`token[:-1]`) to find the most specific style in `styleMap`
  ## (syntax.py:199-210). Overrides the base.
  if self.styleCache.hasKey(tokenType):
    return self.styleCache[tokenType]
  # Styles form a hierarchy: walk most-specific to least-specific token
  # (e.g. "Comment.Preproc" -> "Comment" -> ""), returning the first style
  # found in styleMap. The root "" is NOT consulted (matches Python's
  # `while token:` which exits on the empty tuple before checking the root).
  var token = tokenType
  result = self.missingStyle
  while token.len > 0:
    if self.styleMap.hasKey(token):
      result = self.styleMap[token]
      break
    let i = token.rfind('.')
    if i < 0:
      token = ""
    else:
      token = token[0 ..< i]
  self.styleCache[tokenType] = result

proc getBackgroundStyle*(self: ANSISyntaxTheme): Style =
  ## rich syntax.py:213-214 — `ANSISyntaxTheme.get_background_style(self) ->
  ## Style`: `return self.backgroundStyleField` (syntax.py:214). Overrides the
  ## base.
  if self.backgroundStyleField.isNil:
    return Style.null()
  return self.backgroundStyleField

# ---------------------------------------------------------------------------
# Syntax — syntax.py:243-842
# ---------------------------------------------------------------------------

proc getTheme*(T: typedesc[Syntax], name: SyntaxThemeArg): SyntaxTheme =
  ## rich syntax.py:258-267 — `Syntax.get_theme(cls, name: Union[str,
  ## SyntaxTheme]) -> SyntaxTheme` (classmethod): return `name` if already a
  ## `SyntaxTheme`, else build `ANSISyntaxTheme(RICH_SYNTAX_THEMES[name])` for
  ## the built-in ANSI themes or `PygmentsSyntaxTheme(name)` otherwise
  ## (syntax.py:260-266). `T: typedesc[Syntax]` (the classmethod `cls`).
  ## `name: Union[str, SyntaxTheme]` → `SyntaxThemeArg`.
  case name.kind
  of staTheme:
    return name.t
  of staStr:
    if RICH_SYNTAX_THEMES.hasKey(name.s):
      return initAnsiSyntaxTheme(RICH_SYNTAX_THEMES[name.s])
    return initPygmentsSyntaxTheme(PygmentsThemeArg(kind: ptaStr, s: name.s))

proc initSyntax*(code: string, lexer: LexerOrStr,
                 theme: SyntaxThemeArg = SyntaxThemeArg(kind: staStr,
                     s: DEFAULT_THEME),
                 dedent: bool = false, lineNumbers: bool = false,
                 startLine: int = 1,
                 lineRange: Option[LineRange] = none(LineRange),
                 highlightLines: Option[HashSet[int]] = none(HashSet[int]),
                 codeWidth: Option[int] = none(int), tabSize: int = 4,
                 wordWrap: bool = false,
                 backgroundColor: Option[string] = none(string),
                 indentGuides: bool = false,
                 padding: PaddingDimensions = default(PaddingDimensions)): Syntax =
  ## rich syntax.py:282-297 — `Syntax.__init__(self, code: str, lexer: Lexer |
  ## str, *, theme: str | SyntaxTheme = DEFAULT_THEME, dedent: bool = False,
  ## line_numbers: bool = False, start_line: int = 1, line_range:
  ## Optional[Tuple[Optional[int], Optional[int]]] = None, highlight_lines:
  ## Optional[Set[int]] = None, code_width: Optional[int] = None, tab_size: int
  ## = 4, word_wrap: bool = False, background_color: Optional[str] = None,
  ## indent_guides: bool = False, padding: PaddingDimensions = 0) -> None`:
  ## store all fields, build `background_style`, `_theme = get_theme(theme)`,
  ## `_padding = Padding.unpack(padding)`, `_stylized_ranges = []`
  ## (syntax.py:282-297). Keyword-only after `lexer` (Python `*`, syntax.py:279).
  ## `lexer: Lexer | str` → `LexerOrStr` (required, no default);
  ## `theme: str | SyntaxTheme = DEFAULT_THEME` → `SyntaxThemeArg(kind: staStr,
  ## s: DEFAULT_THEME)`; `line_range` → `Option[LineRange]`;
  ## `highlight_lines: Optional[Set[int]] = None` → `Option[HashSet[int]]`;
  ## `padding: PaddingDimensions = 0` → `default(PaddingDimensions)`. port
  ## stub.
  result = Syntax()
  result.code = code
  result.lexerField = lexer
  result.dedent = dedent
  result.lineNumbers = lineNumbers
  result.startLine = startLine
  result.lineRange = lineRange
  result.highlightLines = if highlightLines.isSome: highlightLines.get
                          else: initHashSet[int]()
  result.codeWidth = codeWidth
  result.tabSize = tabSize
  result.wordWrap = wordWrap
  result.backgroundColor = backgroundColor
  if backgroundColor.isSome and backgroundColor.get.len > 0:
    result.backgroundStyle = initStyle(bgcolor = backgroundColor.get)
  else:
    result.backgroundStyle = initStyle()
  result.indentGuides = indentGuides
  let (t, r, b, l) = unpack(padding)
  result.paddingField = PaddingDimensions(kind: pdQuad, quad: (t, r, b, l))
  result.themeField = Syntax.getTheme(theme)
  result.stylizedRanges = @[]

proc guessLexer*(T: typedesc[Syntax], path: string,
                code: Option[string] = none(string)): string
  ## Forward declaration (rich syntax.py:357-393): `fromPath` calls this before
  ## its definition; the body is below.

proc fromPath*(T: typedesc[Syntax], path: string, encoding: string = "utf-8",
               lexer: Option[LexerOrStr] = none(LexerOrStr),
               theme: SyntaxThemeArg = SyntaxThemeArg(kind: staStr,
                   s: DEFAULT_THEME),
               dedent: bool = false, lineNumbers: bool = false,
               lineRange: Option[LineRangeInt] = none(LineRangeInt),
               startLine: int = 1,
               highlightLines: Option[HashSet[int]] = none(HashSet[int]),
               codeWidth: Option[int] = none(int), tabSize: int = 4,
               wordWrap: bool = false,
               backgroundColor: Option[string] = none(string),
               indentGuides: bool = false,
               padding: PaddingDimensions = default(PaddingDimensions)): Syntax =
  ## rich syntax.py:318-355 — `Syntax.from_path(cls, path, encoding="utf-8",
  ## lexer=None, theme=DEFAULT_THEME, …) -> Syntax` (classmethod): read the
  ## file, `guess_lexer` if `lexer` is None, construct `cls(...)` (syntax.py:318-
  ## 355). `T: typedesc[Syntax]` (classmethod); `lexer: Optional[Lexer | str]`
  ## → `Option[LexerOrStr]`; `line_range: Optional[Tuple[int, int]]` →
  ## `Option[LineRangeInt]` (the int form). Body needs `Path.read_text`,
  ## `guessLexer`.
  let code = readFile(path)
  var lex = lexer
  # Python `if not lexer:` (syntax.py:366) is truthy-false for both None and
  # the empty string; replicate by guessing when lex is None OR a "" str alias.
  let emptyLexer = lex.isSome and lex.get.kind == losStr and lex.get.s == ""
  if lex.isNone or emptyLexer:
    let guessed = Syntax.guessLexer(path, some(code))
    lex = some(LexerOrStr(kind: losStr, s: guessed))
  let lexVal = if lex.isSome: lex.get
               else: LexerOrStr(kind: losStr, s: "default")
  var lr = none(LineRange)
  if lineRange.isSome:
    var lrInt: LineRange
    lrInt.start = some(lineRange.get.start)
    lrInt.endIdx = some(lineRange.get.endIdx)
    lr = some(lrInt)
  return initSyntax(code, lexVal, theme, dedent, lineNumbers, startLine, lr,
                    highlightLines, codeWidth, tabSize, wordWrap, backgroundColor,
                    indentGuides, padding)

proc guessLexer*(T: typedesc[Syntax], path: string,
                code: Option[string] = none(string)): string =
  ## rich syntax.py:357-393 — `Syntax.guess_lexer(cls, path: AnyStr, code:
  ## Optional[str] = None) -> str` (classmethod): guess the pygments lexer alias
  ## from the path/extension and optional code (syntax.py:357-392).
  ## `T: typedesc[Syntax]` (classmethod); `code: Optional[str]` →
  ## `Option[string]`. Body needs `guess_lexer_for_filename`/
  ## `get_lexer_by_name`.
  # DEFERRED(Pygments): guess_lexer_for_filename / get_lexer_by_name are not
  # ported. With no Pygments, no lexer can be resolved from path/code/extension,
  # so return "default" -- the Python fallback when neither yields a lexer
  # (syntax.py:400,422).
  return "default"

proc getBaseStyle*(self: Syntax): Style =
  ## rich syntax.py:395-398 — `Syntax._get_base_style(self) -> Style`:
  ## `self.themeField.get_background_style() + self.backgroundStyle`
  ## (syntax.py:397). Renamed `_get_base_style`→`getBaseStyle`. Body
  ## needs `SyntaxTheme.getBackgroundStyle`.
  # Nim `proc`s on ref objects are statically dispatched, so dispatch on the
  # concrete theme subtype via `of` + downcast (the base SyntaxTheme proc is
  # the abstract no-op returning a nil Style).
  var bg: Style
  if self.themeField.isNil:
    bg = Style.null()
  elif self.themeField of ANSISyntaxTheme:
    bg = cast[ANSISyntaxTheme](self.themeField).getBackgroundStyle()
  elif self.themeField of PygmentsSyntaxTheme:
    bg = cast[PygmentsSyntaxTheme](self.themeField).getBackgroundStyle()
  else:
    bg = self.themeField.getBackgroundStyle()
  if bg.isNil:
    bg = Style.null()
  result = bg + some(self.backgroundStyle)

proc getTokenColor*(self: Syntax, tokenType: TokenType): Option[Color] =
  ## rich syntax.py:400-411 — `Syntax._get_token_color(self, token_type:
  ## TokenType) -> Optional[Color]`: `self.themeField.get_style_for_token(
  ## token_type).color` (syntax.py:407-411). Renamed `_get_token_color`→
  ## `getTokenColor`. Returns `Option[Color]` (the `Optional[Color]`). body
  ## body needs `SyntaxTheme.getStyleForToken`.
  var st: Style
  if self.themeField.isNil:
    return none(Color)
  elif self.themeField of ANSISyntaxTheme:
    st = cast[ANSISyntaxTheme](self.themeField).getStyleForToken(tokenType)
  elif self.themeField of PygmentsSyntaxTheme:
    st = cast[PygmentsSyntaxTheme](self.themeField).getStyleForToken(tokenType)
  else:
    st = self.themeField.getStyleForToken(tokenType)
  if st.isNil:
    return none(Color)
  return st.color

proc lexer*(self: Syntax): Option[Lexer] =
  ## rich syntax.py:413-432 — `Syntax.lexer` property (`@property`
  ## syntax.py:413): the lexer for this syntax, or None — return `self.lexerField`
  ## if a `Lexer`, else `get_lexer_by_name(self._lexer, …)` (resolving
  ## `ClassNotFound` to None) (syntax.py:418-431). Modelled as a no-arg proc
  ## (property getter); returns `Option[Lexer]` (the `Optional[Lexer]`).
  ## body: wired to nimgments `getLexerByName`.
  case self.lexerField.kind
  of losLexer:
    return some(self.lexerField.lexer)
  of losStr:
    # nimgments: getLexerByName raises ClassNotFoundError on unknown lexer.
    try:
      let lx = nimgments.getLexerByName(self.lexerField.s)
      # Wrap the nimgments Lexer in the rich Lexer placeholder. The Lexer
      # placeholder (`Lexer* = ref object of RootObj`) is empty; we stash the
      # nimgments lexer in a side table keyed by the Lexer ref identity, or —
      # simpler — store the name and re-resolve in `highlight`. Here we return
      # a non-nil placeholder so callers see "lexer present".
      result = some(Lexer())
    except nimgments.ClassNotFoundError:
      return none(Lexer)

proc defaultLexer*(self: Syntax): Lexer =
  ## rich syntax.py:434-441 — `Syntax.default_lexer` property (`@property`
  ## syntax.py:434): `get_lexer_by_name("text", stripnl=False, ensurenl=True,
  ## tabsize=self.tab_size)` — the fallback `text` lexer (syntax.py:436-440).
  ## Modelled as a no-arg proc (property getter); returns `Lexer`.
  ## body: nimgments has no "text" lexer (would be a no-op lexer emitting
  ## one Text token). Return nil — `highlight` handles nil by appending raw code
  ## (mirrors rich's `if lexer is None: text.append(code)`).
  result = nil

proc applyStylizedRanges*(self: Syntax, text: Text)
  ## Forward declaration (rich syntax.py:772-802): `highlight` calls this
  ## before its definition; the body is below.

proc highlight*(self: Syntax, code: string,
               lineRange: Option[LineRange] = none(LineRange)): Text =
  ## rich syntax.py:443-533 — `Syntax.highlight(self, code: str, line_range:
  ## Optional[Tuple[Optional[int], Optional[int]]] = None) -> Text`: highlight
  ## `code` via the lexer + theme into a `Text` (syntax.py:443-532).
  ## `line_range` → `Option[LineRange]`. Returns `Text`. Body needs
  ## `lexer`/`defaultLexer`/`getStyleForToken`/`applyStylizedRanges`. port
  ## stub.
  let baseStyle = self.getBaseStyle()
  let justify: JustifyMethod = if baseStyle.transparentBackground: jmDefault
                              else: jmLeft
  result = initText(style = baseStyle, tabSize = some(self.tabSize),
                    noWrap = some(not self.wordWrap), justify = some(justify))
  # syntax.py:470: `lexer = self.lexer or self.default_lexer`. body: resolve
  # the lexer name via nimgments. If `lexerField` is a string and nimgments has
  # a registered lexer by that name, use it; else fall back to plain code
  # (mirrors rich's `if lexer is None: text.append(code)`, syntax.py:472-473).
  var lexerName = ""
  case self.lexerField.kind
  of losLexer:
    lexerName = ""  # a Lexer instance — nimgments path uses names; skip
  of losStr:
    lexerName = self.lexerField.s
  var lx: nimgments.Lexer = nil
  if lexerName.len > 0:
    try: lx = nimgments.getLexerByName(lexerName)
    except nimgments.ClassNotFoundError: lx = nil
  if lx != nil:
    # Tokenize + map each (TokenType, text) to a rich Style via the theme.
    # rich syntax.py:474-508: `_tokenize` -> `tokens_to_spans` appends each
    # token text with `theme.get_style_for_token(ttype)`.
    let theme = self.themeField
    let tokens = lx.getTokens(code)
    # Dispatch getStyleForToken to the concrete theme subtype (proc, not method —
    # Nim needs an explicit `of` cast, like getBaseStyle does for getBackgroundStyle).
    proc styleFor(tt: TokenType): Style =
      if theme of PygmentsSyntaxTheme:
        cast[PygmentsSyntaxTheme](theme).getStyleForToken(tt)
      elif theme of ANSISyntaxTheme:
        cast[ANSISyntaxTheme](theme).getStyleForToken(tt)
      else:
        theme.getStyleForToken(tt)
    for (ttype, tokText) in tokens:
      let ttypeStr = if ttype == nil: "" else: ttype.fullname
      let norm = if ttypeStr == "Token": "" elif ttypeStr.startsWith("Token."): ttypeStr[6..^1] else: ttypeStr
      let st = styleFor(norm)
      discard result.append(tokText, st)
  else:
    result = result.append(code)
  if self.backgroundColor.isSome:
    result.stylize("on " & self.backgroundColor.get)
  if self.stylizedRanges.len > 0:
    self.applyStylizedRanges(result)

proc stylizeRange*(self: Syntax, style: StyleType, start: SyntaxPosition,
                  endPos: SyntaxPosition, styleBefore: bool = false) =
  ## rich syntax.py:535-554 — `Syntax.stylize_range(self, style: StyleType,
  ## start: SyntaxPosition, end: SyntaxPosition, style_before: bool = False) ->
  ## None`: append a `SyntaxHighlightRange` to `self.stylizedRanges`
  ## (syntax.py:552-553). `style: StyleType` keeps the typeclass (stored as
  ## `StyleValue` in the range); `end`→`endPos` (`end` is a Nim keyword). Phase
  ## 0 stub.
  # `style: StyleType` (string or Style) -> the storable `StyleValue` handle
  # via the toStyleValue converters (resolved at the generic instantiation's
  # concrete type).
  let sv: StyleValue = style
  self.stylizedRanges.add(SyntaxHighlightRange(style: sv, start: start,
      endPos: endPos, styleBefore: styleBefore))

proc getLineNumbersColor*(self: Syntax, blend: float = 0.3): Color =
  ## rich syntax.py:556-572 — `Syntax._get_line_numbers_color(self, blend: float
  ## = 0.3) -> Color`: blend the background + `Token.Text` foreground colors
  ## (`blend_rgb`, syntax.py:561-571). Renamed `_get_line_numbers_color`→
  ## `getLineNumbersColor`. Returns `Color`. Body needs `getBaseStyle`/
  ## `getTokenColor`/`blendRgb`.
  if self.themeField.isNil:
    return Color.default()
  let bgStyle = self.getBaseStyle()
  let bgColor = bgStyle.bgcolor
  if bgColor.isNone or bgColor.get.isSystemDefined:
    return Color.default()
  let fgColorOpt = self.getTokenColor("Text")
  if fgColorOpt.isNone or fgColorOpt.get.isSystemDefined:
    return if fgColorOpt.isSome: fgColorOpt.get else: Color.default()
  let newColor = blendRgb(bgColor.get.getTruecolor(),
                          fgColorOpt.get.getTruecolor(), crossFade = blend)
  return Color.fromTriplet(newColor)

proc numbersColumnWidth*(self: Syntax): int =
  ## rich syntax.py:574-582 — `Syntax._numbers_column_width` property
  ## (`@property` syntax.py:574): the number of chars for the line-numbers
  ## column — `0` if no line numbers, else `len(str(self.start_line +
  ## self.code.count("\\n"))) + NUMBERS_COLUMN_DEFAULT_PADDING` (syntax.py:579-
  ## 581). Modelled as a no-arg proc (property getter); renamed
  ## `_numbers_column_width`→`numbersColumnWidth`.
  result = 0
  if self.lineNumbers:
    let lastLine = self.startLine + self.code.count('\n')
    result = ($lastLine).len + NUMBERS_COLUMN_DEFAULT_PADDING

proc getNumberStyles*(self: Syntax, console: ConsoleHandle): tuple[a, b, c: Style] =
  ## rich syntax.py:584-606 — `Syntax._get_number_styles(self, console: Console)
  ## -> Tuple[Style, Style, Style]`: the background/number/highlight styles for
  ## the line-numbers column (syntax.py:586-605). Renamed `_get_number_styles`→
  ## `getNumberStyles`. `console: Console` → `ConsoleHandle` (the console flows
  ## from `getSyntax`; rich types it `Console` but it is TYPE_CHECKING-only,
  ## syntax.py:42 — `ConsoleHandle` avoids importing `console.nim`). Returns
  ## `tuple[a, b, c: Style]` (the `Tuple[Style, Style, Style]`).
  let bgStyle = self.getBaseStyle()
  if bgStyle.transparentBackground:
    return (a: Style.null(), b: initStyle(dim = some(true)), c: Style.null())
  # DEFERRED(console.color_system): ConsoleHandle is a placeholder with no
  # fields, so the ("256"/"truecolor") Style.chain branch (with
  # getLineNumbersColor) is not portable. Use the standard-color fallback
  # (background + dim / not-dim), matching the Python `else` arm
  # (syntax.py:621-622).
  let numberStyle = bgStyle + some(initStyle(dim = some(true)))
  let highlightNumberStyle = bgStyle + some(initStyle(dim = some(false)))
  return (a: bgStyle, b: numberStyle, c: highlightNumberStyle)

# Forward declaration — `renderConsole` (line ~809) calls `processCode`
# (defined at line ~914). Nim needs the proc declared before use.
proc processCode*(self: Syntax, code: string): tuple[endsOnNl: bool, processedCode: string]

method renderConsole*(self: Syntax, console: ConsoleHandle,
                   options: ConsoleOptions): RenderResult =
  ## rich syntax.py:608-616 — `Syntax.__rich_console__(self, console: Console,
  ## options: ConsoleOptions) -> RenderResult`: wrap `Segments(getSyntax(…))`
  ## in `Padding` if any padding, else yield the segments (syntax.py:610-615).
  ## body: wired to `highlight` (now uses nimgments for tokenization +
  ## style-for-token). The full `_get_syntax` path (line numbers, word wrap,
  ## padding wrap) is still partial — this implements the common case
  ## (no line_numbers, no word_wrap, no line_range, no padding) via
  ## `splitAndCropLines` (segment padding to code_width with bg style).
  ## Byte-exact parity with Python rich 15.0.0 for this common case.
  result = @[]
  let baseStyle = self.getBaseStyle()
  let (endsOnNl, processed) = self.processCode(self.code)
  # rich syntax.py:678-680 — strip the trailing '\n' when the original code did
  # NOT end with one (processCode always appends one; Python removes it here
  # so the render has no trailing empty line).
  var codeToHighlight = processed
  if not endsOnNl and codeToHighlight.endsWith("\n"):
    codeToHighlight = codeToHighlight[0 ..< ^1]
  let highlighted = self.highlight(codeToHighlight)
  # Render the highlighted Text to a segment list (extract rrkSegment items
  # from the RenderResult), then pad each line to code_width with the
  # background style via `splitAndCropLines` (mirrors rich's
  # `console.render_lines(..., style=background_style, pad=True, new_lines=True)`).
  let rendered = highlighted.render(console, "")
  var segs: seq[Segment] = @[]
  for item in rendered:
    if item.kind == rrkSegment:
      segs.add(item.segmentItem)
    elif item.kind == rrkString:
      segs.add(Segment(text: item.textStr, style: none(StyleRef)))
  let codeWidth = max(0, options.maxWidth)
  let padded = splitAndCropLines(segs, codeWidth,
                                 some(baseStyle), pad = true,
                                 includeNewLines = true)
  for lineSegs in padded:
    for seg in lineSegs:
      result.addSegment(initSegment(seg.text, seg.style))
  # rich `render_lines(new_lines=True)`: a trailing '\n' in the code creates
  # one more empty line (padded to code_width with bg). `splitAndCropLines` does
  # not emit this final empty line, so add it when the code ended on '\n'.
  if endsOnNl:
    result.addSegment(initSegment(repeat(" ", codeWidth),
                                   some(StyleRef(baseStyle))))
    result.addSegment(initSegment("\n", none(StyleRef)))

proc richMeasure*(self: Syntax, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich syntax.py:618-628 — `Syntax.__rich_measure__(self, console:
  ## ConsoleOptions, options: ConsoleOptions) -> Measurement`: the
  ## `code_width`-fixed or `cell_len`-measured width measurement
  ## (syntax.py:620-627). The richbase `ConsoleHandle`/`ConsoleOptions`
  ## placeholders; `Measurement` from `measure.nim`. Body needs
  ## `cellLen`, `numbersColumnWidth`.
  # `self.paddingField` (the stored PaddingDimensions) is equivalent to the
  # `padding` getter result and avoids a forward reference to the getter
  # (declared later in this module).
  let (_, right, _, left) = unpack(self.paddingField)
  let pad = left + right
  if self.codeWidth.isSome:
    let width = self.codeWidth.get + self.numbersColumnWidth() + pad + 1
    return Measurement(minimum: self.numbersColumnWidth(), maximum: width)
  let lines = self.code.splitLines()
  var maxCell = 0
  for line in lines:
    maxCell = max(maxCell, cellLen(line))
  var width = self.numbersColumnWidth() + pad + maxCell
  if self.lineNumbers:
    width += 1
  return Measurement(minimum: self.numbersColumnWidth(), maximum: width)

proc getSyntax*(self: Syntax, console: ConsoleHandle,
                options: ConsoleOptions): seq[Segment] =
  ## rich syntax.py:630-770 — `Syntax._get_syntax(self, console: Console,
  ## options: ConsoleOptions) -> Iterable[Segment]`: the full segment render
  ## — process the code, highlight, split into lines, render the line-numbers
  ## column + wrapped code (syntax.py:630-769). Renamed `_get_syntax`→
  ## `getSyntax`. `console: Console` → `ConsoleHandle`; `Iterable[Segment]` →
  ## `seq[Segment]`. Body needs `highlight`, `getNumberStyles`,
  ## `loop_first`, `Lines`, `Segment.adjustLineLength`.
  # DEFERRED: needs Text.split (returns the text.Lines placeholder, no
  # iteration API), Segment.adjustLineLength, loop_first, and getNumberStyles
  # (console.color_system dep). body wires the full line-numbered render.
  result = @[]

proc getCodeIndex*(newlinesOffsets: openArray[int],
                  position: SyntaxPosition): Option[int]
  ## Forward declaration (rich syntax.py:844-868): `applyStylizedRanges` calls
  ## this before its definition; the body is below.

proc applyStylizedRanges*(self: Syntax, text: Text) =
  ## rich syntax.py:772-802 — `Syntax._apply_stylized_ranges(self, text: Text) ->
  ## None`: apply each `SyntaxHighlightRange` in `self.stylizedRanges` to `text`
  ## via `text.stylize`/`stylize_before` (syntax.py:777-801). Renamed
  ## `_apply_stylized_ranges`→`applyStylizedRanges`. Body needs
  ## `getCodeIndex`, `Text.stylize`.
  if text.isNil:
    return
  let code = text.plain
  var newlinesOffsets: seq[int] = @[0]
  for i, ch in code:
    if ch == '\n':
      newlinesOffsets.add(i + 1)
  newlinesOffsets.add(code.len + 1)
  for r in self.stylizedRanges:
    let startIdx = getCodeIndex(newlinesOffsets, r.start)
    let endIdx = getCodeIndex(newlinesOffsets, r.endPos)
    if startIdx.isSome and endIdx.isSome:
      case r.style.kind
      of svkStr:
        if r.styleBefore:
          text.stylizeBefore(r.style.strv, startIdx.get, some(endIdx.get))
        else:
          text.stylize(r.style.strv, startIdx.get, some(endIdx.get))
      of svkStyle:
        if r.styleBefore:
          text.stylizeBefore(r.style.stv, startIdx.get, some(endIdx.get))
        else:
          text.stylize(r.style.stv, startIdx.get, some(endIdx.get))

proc processCode*(self: Syntax, code: string): tuple[endsOnNl: bool,
                processedCode: string] =
  ## rich syntax.py:804-820 — `Syntax._process_code(self, code: str) ->
  ## Tuple[bool, str]`: normalise `code` — append a trailing newline if absent,
  ## `textwrap.dedent` if `dedent`, `expandtabs(tab_size)` (syntax.py:808-819).
  ## Renamed `_process_code`→`processCode`. Returns `tuple[endsOnNl: bool,
  ## processedCode: string]` (the `Tuple[bool, str]`). Body needs
  ## `textwrap.dedent`/`expandtabs`.
  proc dedentStr(s: string): string =
    # Faithful port of CPython 3.14 `textwrap.dedent` (the split/min-max/isspace
    # variant): split on '\n', take the common leading whitespace of the
    # lexicographic min/max non-blank lines, strip it from non-blank lines, and
    # normalise whitespace-only lines to empty (verified byte-identical to
    # textwrap.dedent across mixed tab/space cases).
    proc isWsOnly(l: string): bool =
      # Python `str.isspace()`: True iff non-empty and all-whitespace. Lines are
      # already '\n'-split, so the relevant whitespace is ' \t\r\f\v'.
      if l.len == 0: return false
      for ch in l:
        if ch notin {' ', '\t', '\r', '\f', '\v'}: return false
      return true
    let lines = s.split('\n')
    var l1 = ""
    var l2 = ""
    var haveNonBlank = false
    for l in lines:
      # non-blank = non-empty AND not all-whitespace (Python `l and not
      # l.isspace()`).
      if l.len > 0 and not isWsOnly(l):
        if not haveNonBlank:
          l1 = l; l2 = l; haveNonBlank = true
        else:
          if l < l1: l1 = l
          if l > l2: l2 = l
    var margin = 0
    if haveNonBlank:
      # Common leading whitespace of the min/max non-blank lines, char-by-char
      # (so '  x' and '\tx' share no margin -- Python's note on tab vs space).
      for i, c in l1:
        margin = i
        if c notin {' ', '\t'}:
          break
        if i >= l2.len or c != l2[i]:
          break
    result = newStringOfCap(s.len)
    for idx, l in lines:
      if idx > 0: result.add('\n')
      # Python `[l[margin:] if not l.isspace() else '' for l in lines]`: empty
      # lines (not isspace, since ''.isspace() is False) take `l[margin:]`;
      # whitespace-only lines normalise to ''.
      if l.len == 0 or not isWsOnly(l):
        if margin < l.len: result.add(l[margin .. ^1])
  let endsOnNl = code.endsWith("\n")
  var processedCode = if endsOnNl: code else: code & "\n"
  if self.dedent:
    processedCode = dedentStr(processedCode)
  processedCode = processedCode.expandTabs(self.tabSize)
  result.endsOnNl = endsOnNl
  result.processedCode = processedCode

proc padding*(self: Syntax): PaddingDimensions =
  ## rich syntax.py:234-236 — `PaddingProperty.__get__(self, obj, objtype) ->
  ## Tuple[int, int, int, int]`: the space around the `Syntax` —
  ## `obj.paddingField` (the `PaddingProperty` descriptor getter; the
  ## `Syntax.padding` property reads it). Modelled as a no-arg proc (property
  ## getter); returns `PaddingDimensions`.
  result = self.paddingField

proc `padding=`*(self: Syntax, padding: PaddingDimensions) =
  ## rich syntax.py:238-240 — `PaddingProperty.__set__(self, obj, padding:
  ## PaddingDimensions) -> None`: `obj.paddingField = Padding.unpack(padding)`
  ## (the `PaddingProperty` descriptor setter; the `Syntax.padding = …`
  ## assignment invokes it). Modelled as a setter proc. Body needs
  ## `Padding.unpack`.
  let (t, r, b, l) = unpack(padding)
  self.paddingField = PaddingDimensions(kind: pdQuad, quad: (t, r, b, l))

# ---------------------------------------------------------------------------
# Module-level helper — syntax.py:844-868
# ---------------------------------------------------------------------------

proc getCodeIndex*(newlinesOffsets: openArray[int],
                  position: SyntaxPosition): Option[int] =
  ## rich syntax.py:844-868 — `_get_code_index_for_syntax_position(
  ## newlines_offsets: Sequence[int], position: SyntaxPosition) -> Optional[int]`:
  ## the flat index into the code string for `position`, clamping the column,
  ## returning `None` if the line is out of range (syntax.py:855-867). Renamed
  ## `_get_code_index_for_syntax_position`→`getCodeIndex` (private `_` dropped).
  ## `newlines_offsets: Sequence[int]` → `openArray[int]`; returns `Option[int]`
  ## (the `Optional[int]`).
  let linesCount = newlinesOffsets.len
  let lineNumber = position.line
  let columnIndex = position.column
  if lineNumber > linesCount or newlinesOffsets.len < (lineNumber + 1):
    return none(int)
  if lineNumber < 1:
    # Defensive: Python allows negative indexing into newlines_offsets (a
    # quirk for line_number < 1, which never occurs for 1-based positions);
    # Nim raises IndexDefect, so return None instead.
    return none(int)
  let lineIndex = lineNumber - 1
  let lineLength = newlinesOffsets[lineIndex + 1] - newlinesOffsets[lineIndex] - 1
  let col = min(lineLength, columnIndex)
  return some(newlinesOffsets[lineIndex] + col)
