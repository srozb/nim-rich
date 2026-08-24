## Port of `rich.console` (rich/console.py).
##
## `Console` is rich's high-level terminal interface (console.py:581-2642): it
## renders `RenderableType` objects to a file (stdout by default) as styled
## `Segment`s, manages a `ThemeStack`, capture/pager/screen/theme context
## managers, recording + HTML/SVG/text export, logging, and exception printing.
## This module also hosts the small renderable/context-manager helper classes
## `NewLine`, `ScreenUpdate`, `Capture`, `ThemeContext`, `PagerContext`,
## `ScreenContext`, `Group`, the `ConsoleThreadLocals`/`RenderHook` support
## types, the `group` decorator factory, and the `detect_legacy_windows` /
## `get_windows_console_features` probes.
##
## Shared base types already live in `richbase` (the leaf that breaks the
## `segment`↔`console` cycle): `JustifyMethod`/`OverflowMethod` (console.py:69-70),
## `NoChange`/`NO_CHANGE` (console.py:73-77), `ConsoleDimensions` (console.py:103),
## `ConsoleOptions` (console.py:113-243), `RenderResult`/`RenderResultItem`/
## `RenderResultKind` (console.py:267,271), `ConsoleRenderable`/`RichCast`
## concepts (console.py:247-263), `RenderableType` (console.py:267), `Segment`
## (segment.py:60-184), `RenderableBase` (Nim storage base), and the
## `ConsoleHandle`/`StyleRef` opaque handles. `Console` is declared
## `ref object of ConsoleHandle` here (as `richbase` documents), so a renderable
## that takes `console: ConsoleHandle` receives a real `Console` at runtime; the
## `richbase` types above are NOT redefined here.
##
## Import graph (rich/console.py:1-57): only the runtime sibling imports whose
## symbols appear in *signatures* are ported below; body-only deps (the private
## modules `_emoji_replace`/`_export_format`/`_fileno`/`_log_render`/
## `_null_file`/`_windows`/`_win32_console`/`_windows_renderer`, plus `markup`,
## `styled`, `errors`, `pretty`, `scope`, `rule`, `json`, `traceback`,
## `jupyter`, `cells`) are NOT imported  (their names appear only in
## method bodies, which are `discard`) — mirroring `ansi.nim`/`text.nim`/
## `theme.nim`.
##
## Non-narrowing provisional forward handles (PUBLIC — removed by name when the
## owning module is ported, exactly as `text.nim`'s `Lines`/`EmojiVariant`/
## `RePattern` handles are): `Pager` (rich.pager.Pager, pager.nim NOT yet
## ported; console.py:367,1113), `FileHandle` (typing.IO[str]; console.py:627,
## 757; file_proxy.py:14; console.py:2156), `WindowsConsoleFeatures`
## (rich._windows, private/not ported; console.py:566), `LockHandle`
## (threading.RLock; console.py:737,753), `LogRender` (rich._log_render, private;
## console.py:741), `FrameHandle` (types.FrameType; console.py:1909).
##
## Real closure-proc type aliases (faithful direct ports): `FormatTimeCallable`
## (`Callable[[datetime], Text]`, console.py:619), `GetDatetimeCallable`
## (`Optional[Callable[[], datetime]]`, console.py:745), `GetTimeCallable`
## (`Optional[Callable[[], float]]`, console.py:746), `CallerFrameCallable`
## (`Optional[Callable[[], Optional[FrameType]]]`, console.py:1909),
## `JsonDefaultCallable` (`Optional[Callable[[Any], Any]]`, console.py:1776;
## `Any`→`JsonNode`), `HighlighterType` (`Callable[[Union[str,"Text"]],"Text"]`,
## console.py:68; narrowed to the `Highlighter` instance arm — the param/field is
## in practice always a `Highlighter` subclass; a bare-callable arm is body).
##
## Provisional module-level values (placeholders, mirroring `ansi.nim`'s
## `reAnsi*`/`sgrStyleMap*`): `CONSOLE_HTML_FORMAT`/`CONSOLE_SVG_FORMAT`
## (console.py:38; defaults of save_html/save_svg code_format, console.py:2335,
## 2609), `COLOR_SYSTEMS` (console.py:525-530).
##
## Naming: `__init__`→`initXxx`, `__repr__`→`repr`, `__enter__`→`enter`,
## `__exit__`→`exit` (with the `(excType, excVal, excTb)` triple, mirroring
## `live.nim`/`status.nim`), `__rich_console__`→`renderConsole`,
## `__rich_measure__`→`richMeasure`; snake_case keyword params camelCased
## (`soft_wrap`→`softWrap`, `no_color`→`noColor`, `tab_size`→`tabSize`,
## `color_system`→`colorSystem`, `force_terminal`→`forceTerminal`,
## `force_jupyter`→`forceJupyter`, `force_interactive`→`forceInteractive`,
## `legacy_windows`→`legacyWindows`, `safe_box`→`safeBox`, `log_time`→`logTime`,
## `log_path`→`logPath`, `log_time_format`→`logTimeFormat`, `get_datetime`→
## `getDatetime`, `get_time`→`getTime`, `emoji_variant`→`emojiVariant`,
## `extra_lines`→`extraLines`, `word_wrap`→`wordWrap`, `show_locals`→`showLocals`,
## `max_frames`→`maxFrames`, `new_lines`→`newLines`, `set_alt_screen`→
## `setAltScreen`, `is_alt_screen`→`isAltScreen`, `set_window_title`→
## `setWindowTitle`, `update_screen`→`updateScreen`, `update_screen_lines`→
## `updateScreenLines`, `print_exception`→`printException`, `print_json`→
## `printJson`, `export_html`/`save_html`/`export_svg`/`save_svg`→`exportHtml`/
## `saveHtml`/`exportSvg`/`saveSvg`, `render_str`→`renderStr`, `render_lines`→
## `renderLines`, `get_style`→`getStyle`, `push_theme`/`pop_theme`/`use_theme`→
## `pushTheme`/`popTheme`/`useTheme`, `push_render_hook`/`pop_render_hook`→
## `pushRenderHook`/`popRenderHook`, `begin_capture`/`end_capture`→
## `beginCapture`/`endCapture`, `set_live`/`clear_live`→`setLive`/`clearLive`,
## `show_cursor`→`showCursor`, `on_broken_pipe`→`onBrokenPipe`,
## `_caller_frame_info`→`callerFrameInfo`, `log_locals`→`logLocals`,
## `_stack_offset`→`stackOffset`, `code_format`→`codeFormat`,
## `inline_styles`→`inlineStyles`, `font_aspect_ratio`→`fontAspectRatio`,
## `unique_id`→`uniqueId`, `new_line_start`→`newLineStart`, `hide_cursor`→
## `hideCursor`, `refresh_per_second`→`refreshPerSecond`, `spinner_style`→
## `spinnerStyle`, `record_buffer`→`recordBuffer`, `render_hooks`→`renderHooks`,
## `live_stack`→`liveStack`, `thread_locals`→`threadLocals`, `theme_stack`→
## `themeStack`, `buffer_index`→`bufferIndex`; private `_`-fields renamed
## (`_width`/`_height`→`widthVal`/`heightVal`, `_file`→`fileVal`,
## `_force_terminal`→`forceTerminalVal`, `_color_system`→`colorSystemVal`,
## `_markup`/`_emoji`/`_highlight`→`markupFlag`/`emojiFlag`/`highlightFlag`,
## `_is_alt_screen`→`isAltScreenFlag`, `_renderables`→`renderablesData`,
## `_render`→`renderCache`, `_console`→`console`, `_lines`→`linesData`,
## `_result`→`captureResult`, `_changed`→`changed`, `highlighter` field→
## `highlighterField`, `_environ`→`environ`, `_lock`→`lockRef`,
## `_record_buffer_lock`→`recordBufferLock`). `out` is a Nim keyword →
## backtick-quoted `` `out`* ``; `end` params are backtick-quoted `` `end` ``.
## `EmojiVariant` is qualified as `emoji.EmojiVariant` (the real enum; `text.nim`
## also exports a provisional `EmojiVariant` to be dropped in body, so the
## qualified use picks the real one and avoids ambiguity). Proc bodies are
## `discard` (`default(T)` where a value is returned) — ports.

import std/[options, tables, times, json, strutils, streams, math, hashes]
from std/os import envPairs

import segment         # re-exports richbase (ConsoleOptions, JustifyMethod,
                       # OverflowMethod, NoChange/NO_CHANGE, ConsoleDimensions,
                       # RenderResult, RenderableType, ConsoleRenderable, RichCast,
                       # Segment, ConsoleHandle, RenderableBase, RenderResultItem)
                       # and Style (segment.py:9,10-11).
import style           # StyleType (string or Style), StyleOpt (Optional[StyleType]
                       # handle) + toStyleOpt* converters, Style.
import text            # Text, TextType (console.py:56), AlignMethod (hosted in
                       # text.nim, re-exported by align.nim — console.py:41).
import color           # ColorSystem (console.py:42; _color_system field +
                       # COLOR_SYSTEMS value type). blend_rgb is body-only.
import errors          # ConsoleError/NoAltScreen/MissingStyle/StyleSyntaxError/
                       # NotRenderableError (console.py:1-57; raised by
                       # get_style/update_screen/render). errors is a leaf → no cycle.
import control as ctrl # Control (console.py:43); module aliased `ctrl` to disambiguate from the `Console.control` method (module/proc name collision).
import emoji           # EmojiVariant (console.py:44; Console.__init__
                       # emoji_variant param) — qualified as `emoji.EmojiVariant`
                       # (the real enum; text.nim's provisional one is excluded by
                       # qualification, pending the body cleanup).
import highlighter     # Highlighter (base), ReprHighlighter, NullHighlighter
                       # (console.py:45; highlighter field/param + _null_highlighter).
import measure         # Measurement (console.py:47; Console.measure / Group.richMeasure
                       # return). measure_renderables is body-only.
import region          # Region (console.py:50; Console.update_screen region param).
import terminal_theme  # TerminalTheme (console.py:55; export_html/save_html/
                       # export_svg/save_svg theme param).
import theme           # Theme, ThemeStack (console.py:57; theme param/field,
                       # _theme_stack property, ConsoleThreadLocals.theme_stack).
import themes          # DEFAULT (themes.py:5; the Console.__init__ default theme,
                       # console.py:743). themes→theme (no console import) → no cycle.
import live            # Live (console.py:61, TYPE_CHECKING-only; Console.set_live
                       # param + _live_stack field). live.nim uses ConsoleHandle
                       # (no `import console`) → no cycle.
import status          # Status (console.py:62, TYPE_CHECKING-only; Console.status
                       # return). status.nim uses ConsoleHandle → no cycle.
import screen          # Screen (console.py:51; ScreenContext.screen field).
                       # screen.nim uses ConsoleHandle → no cycle.
import api_types       # RenderableValue + toRenderableValue converters (the
                       # storable RenderableType handle for Group/ScreenContext/
                       # print/out/log `*objects` varargs-as-openArray params).
import markup        # render (Console.renderStr markup branch; markup→text/style/
                     # emoji/errors — none import console → cycle-free).
import rule          # initRule (Console.rule; rule→segment/style/measure/text,
                     # no console import → cycle-free).
import json as richjson  # initJson/Json.fromData (Console.printJson; the
                     # sibling JSON renderable module, NOT std/json — aliased to
                     # avoid the std/json `json` name clash and the printJson
                     # `json` param shadow).
import cells         # cellLen (Console.exportSvg; cells is a std-only leaf →
                     # cycle-free).
import color_triplet # ColorTriplet.hex (Console.export_html/export_svg;
                     # color_triplet is a std-only leaf → cycle-free).
import traceback     # initTraceback (Console.printException; traceback already
                     # imports console for the `Console` type — the cycle is
                     # proc-level only, so Nim resolves it like rich's console↔
                     # traceback Python cycle).
import console_api  # Console dispatch interface (console_api.nim) — the four
                    # `{.base.}` virtual methods `getStyle`/`renderLines`/`render`/
                    # `measure` on `ConsoleHandle` that break the
                    # console→terminal_theme→palette→table import cycle. Imported
                    # here ONLY so `Console`'s matching `method` implementations
                    # below link as overrides (Nim needs the base visible in the
                    # module that defines the subtype override — the same pattern
                    # as the `richbase` `renderConsole` base reached via
                    # `segment`). `console_api` is a leaf (imports richbase/style/
                    # segment/measure/api_types — none import `console`) → no cycle.

# --- port renderConsole dispatch imports (cycle-free: none of these import
# `console`; they use `richbase.ConsoleHandle` for their `renderConsole`
# port: the renderConsole dispatch is now VIRTUAL (a `method` on
# `RenderableBase`, richbase `{.base.}`), so console.nim no longer imports the
# per-renderable modules (styled/padding/panel/table/align/columns/constrain/
# containers/bar/spinner/progress_bar/tree). That import set closed the
# console↔panel cycle and ballooned the umbrella type-check; each renderable's
# `method renderConsole` override is picked up when the umbrella compiles it.

# `emoji` (the module) is shadowed by `Console.__init__`'s `emoji: bool` param
# (console.py:737) within that proc, so `emoji.EmojiVariant` would resolve to
# the param's field there. This private module-scope alias (defined where `emoji`
# = the module, not shadowed) lets signatures reference the real
# `emoji.EmojiVariant` unqualified — sidestepping both the param shadow and the
# `text.EmojiVariant`/`emoji.EmojiVariant` ambiguity (`text.nim` exports a
# provisional `EmojiVariant` to be dropped in body; the umbrella comment
# documents the coexistence). body drops `text.nim`'s provisional handle and
# this alias may then be inlined.
type EmojiVariant = emoji.EmojiVariant

proc emojiReplaceForConsole(text: string, v: Option[EmojiVariant]): string =
  ## rich console.py:1451-1453 — `_emoji_replace(text, default_variant=
  ## self._emoji_variant)` for the markup-disabled `render_str` arm. Dispatches
  ## the ported `emoji.emojiReplace` (in `emoji.nim`). Defined at module scope
  ## so the `emoji` module symbol is not shadowed by `renderStr`'s `emoji:
  ## Option[bool]` param (console.py:1416) — `emoji.emojiReplace` would resolve
  ## to the param inside `renderStr`.
  emoji.emojiReplace(text, v)

# ---------------------------------------------------------------------------
# Non-narrowing provisional forward handles + closure-proc aliases
# ---------------------------------------------------------------------------

type
  Pager* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `pager.Pager` (pager.py; pager.nim NOT yet ported). Used in
    ## `PagerContext.__init__`'s `pager: Optional[Pager]` param (console.py:367)
    ## and `Console.pager`'s `pager: Optional[Pager]` param (console.py:1113).
    ## PUBLIC so the legal `none(Pager)` default compiles via the public API.
    ## PROVISIONAL: removed by name when `pager.nim` is written and the real
    ## `Pager` is imported. The placeholder is an empty `ref object of
    ## RootObj`; the real `Pager` has a `show(self, content: str)` method used in
    ## `PagerContext`'s exit body (console.py:396) — a Body concern.

  FileHandle* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `typing.IO[str]` (the file `Console` writes to, and the file `FileProxy`
    ## wraps). There is no ported Python `io` module, so this is the shared
    ## `IO[str]` handle used by `Console.__init__`'s `file` param / `file`
    ## property / `setFile` setter (console.py:627,757,766), by
    ## `FileProxy.__init__`'s `file` param (file_proxy.py:14) and `Console.input`'s
    ## `stream` param (console.py:2156). PUBLIC so `file_proxy.nim` and consumers
    ## can name and store a `FileHandle`. PROVISIONAL: revisited in body
    ## against a real `IO[str]` model once file I/O bodies are implemented.

  WindowsConsoleFeatures* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `_windows.WindowsConsoleFeatures` (private module, NOT ported — one of the
    ## 19 private modules outside the canonical 56). The return type of
    ## `get_windows_console_features` (console.py:566). PROVISIONAL placeholder;
    ## body wires the real attributes (`vt`, `truecolor`) if/when the Windows
    ## probe is ported (the function is `# pragma: no cover`, Windows-only).

  LockHandle* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `threading.RLock` — the `_lock` (console.py:737) and
    ## `_record_buffer_lock` (console.py:753) private fields of `Console`.
    ## `threading` is not ported. Used only in private fields (never in a public
    ## signature). PROVISIONAL; body wires a real (re-entrant) lock
    ## (e.g. `std/locks` or a custom `RLock`) for the buffer/capture sections.

  LogRender* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `_log_render.LogRender` (private module, NOT ported). The `_log_render`
    ## field of `Console` (console.py:741), constructed in `__init__` and called
    ## by `Console.log` (console.py:1947). PROVISIONAL placeholder; body wires
    ## the real `LogRender` (show_time/show_level/show_path/time_format knobs,
    ## _log_render.py:14-62) — likely inlined since the private module is outside
    ## the canonical 56.

  FrameHandle* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE — NOT FROZEN] rich
    ## `types.FrameType` (a Python frame object, not ported). The `currentframe`
    ## param of `_caller_frame_info` (console.py:1909). PROVISIONAL placeholder
    ## (the param is a test-injection seam defaulting to `None`); body wires a
    ## real frame model only if/when the caller-frame inspection is ported.

  FormatTimeCallable* = proc(dt: times.DateTime): Text {.closure.}
    ## rich _log_render.py:11 — `FormatTimeCallable = Callable[[datetime], Text]`
    ## (imported by console.py:40). A callable accepting a `datetime` and
    ## returning a `Text`. Faithful direct port as a Nim closure proc type
    ## (`datetime` → `std/times.DateTime`); used by `Console.__init__`'s
    ## `log_time_format: Union[str, FormatTimeCallable] = "[%X]"` (console.py:619).

  GetDatetimeCallable* = proc(): times.DateTime {.closure.}
    ## rich console.py:745 — `Optional[Callable[[], datetime]]`. Faithful direct
    ## port as a Nim closure proc type; the `Console.__init__` `get_datetime`
    ## param/`getDatetime` field (default `datetime.now`, console.py:742).

  GetTimeCallable* = proc(): float {.closure.}
    ## rich console.py:746 — `Optional[Callable[[], float]]`. Faithful direct
    ## port; the `Console.__init__` `get_time` param/`getTime` field (default
    ## `time.monotonic`, console.py:742).

  CallerFrameCallable* = proc(): Option[FrameHandle] {.closure.}
    ## rich console.py:1909 — `Optional[Callable[[], Optional[FrameType]]]`. The
    ## `currentframe` param of `_caller_frame_info` (a test seam defaulting to
    ## `None`). Faithful port as a Nim closure proc type over the provisional
    ## `FrameHandle`.

  JsonDefaultCallable* = proc(x: JsonNode): JsonNode {.closure.}
    ## rich console.py:1776 — `Optional[Callable[[Any], Any]]` (the `default`
    ## param of `print_json`, a fallback JSON encoder). `Any` → `JsonNode` (the
    ## non-narrowing `Any` handle used across `api_types`/`style.nim`). Faithful
    ## port as a Nim closure proc type.

  HighlighterType* = Highlighter
    ## rich console.py:68 — `HighlighterType = Callable[[Union[str, "Text"]],
    ## "Text"]`. Narrowed to the `Highlighter` instance arm: the `highlighter`
    ## param (console.py:619) and `Console.highlighter` field (console.py:742) are
    ## in practice always a `Highlighter` subclass (`ReprHighlighter` by default,
    ## `NullHighlighter` for the `_null_highlighter` fallback, console.py:274,
    ## 742), and `Highlighter` is the shared base ref exported by `highlighter.nim`.
    ## A bare-callable arm is rare in practice and is a body concern (modelled
    ## then via a concept); the narrowing lets the value be stored in a field and
    ## an `Option` .

# ---------------------------------------------------------------------------
# Renderable / context-manager / support types — console.py:280-560
# ---------------------------------------------------------------------------

type
  NewLine* = ref object of RenderableBase
    ## rich console.py:280-289 — `class NewLine`: a renderable that generates new
    ## line(s). `ref object of RenderableBase`. Field mirrors `__init__`
    ## (console.py:283-284).
    count*: int          ## rich console.py:284 — `self.count = count` (default `1`).

  ScreenUpdate* = ref object of RenderableBase
    ## rich console.py:292-307 — `class ScreenUpdate`: render a list of lines at a
    ## given offset. `ref object of RenderableBase`. Fields mirror `__init__`
    ## (console.py:295-298).
    linesData*: seq[seq[Segment]]
      ## rich console.py:296 — `self._lines = lines` (`List[List[Segment]]`;
      ## renamed `_lines`→`linesData`).
    x*: int              ## rich console.py:297 — `self.x = x`.
    y*: int              ## rich console.py:298 — `self.y = y`.

  Capture* = ref object of RootObj
    ## rich console.py:310-340 — `class Capture`: context manager to capture the
    ## result of printing to the console (see `Console.capture`, console.py:1096).
    ## `ref object of RootObj` (plain context manager, not a renderable). Fields
    ## mirror `__init__` (console.py:318-320).
    console*: Console    ## rich console.py:319 — `self._console = console`
                         ## (renamed `_console`→`console`).
    captureResult*: Option[string]
      ## rich console.py:320 — `self._result: Optional[str] = None` (filled on
      ## `__exit__`; renamed `_result`→`captureResult`).

  ThemeContext* = ref object of RootObj
    ## rich console.py:343-361 — `class ThemeContext`: a context manager to use a
    ## temporary theme (see `Console.use_theme`, console.py:896). Fields mirror
    ## `__init__` (console.py:346-349).
    console*: Console    ## rich console.py:347 — `self.console = console`.
    theme*: Theme        ## rich console.py:348 — `self.theme = theme`.
    inherit*: bool       ## rich console.py:349 — `self.inherit = inherit`.

  PagerContext* = ref object of RootObj
    ## rich console.py:364-400 — `class PagerContext`: a context manager that
    ## 'pages' content (see `Console.pager`, console.py:1113). Fields mirror
    ## `__init__` (console.py:367-377); the `pager` is resolved to `SystemPager()`
    ## when `None` in the body (console.py:373) — a Body concern.
    console*: Console    ## rich console.py:368 — `self._console = console`.
    pager*: Pager        ## rich console.py:373 — `self.pager = SystemPager() if
                         ## pager is None else pager` (resolved `Pager`; the
                         ## provisional handle).
    styles*: bool        ## rich console.py:374 — `self.styles = styles`.
    links*: bool         ## rich console.py:375 — `self.links = links`.

  ScreenContext* = ref object of RootObj
    ## rich console.py:403-447 — `class ScreenContext`: a context manager that
    ## enables an alternative screen (see `Console.screen`, console.py:1263).
    ## Fields mirror `__init__` (console.py:406-412).
    console*: Console    ## rich console.py:407 — `self.console = console`.
    hideCursor*: bool    ## rich console.py:408 — `self.hide_cursor = hide_cursor`.
    screen*: Screen      ## rich console.py:409 — `self.screen = Screen(style=style)`.
    changed*: bool       ## rich console.py:410 — `self._changed = False` (renamed
                         ## `_changed`→`changed`).

  Group* = ref object of RenderableBase
    ## rich console.py:450-480 — `class Group`: takes a group of renderables and
    ## returns a renderable that renders the group. `ref object of RenderableBase`.
    ## Fields mirror `__init__` (console.py:458-461).
    renderablesData*: seq[RenderableValue]
      ## rich console.py:459 — `self._renderables = renderables` (renamed
      ## `_renderables`→`renderablesData`).
    fit*: bool           ## rich console.py:460 — `self.fit = fit`.
    renderCache*: Option[seq[RenderableValue]]
      ## rich console.py:461 — `self._render: Optional[List[RenderableType]] =
      ## None` (lazy `renderables` cache; renamed `_render`→`renderCache`).

  ConsoleThreadLocals* = ref object of RootObj
    ## rich console.py:536-541 — `@dataclass class ConsoleThreadLocals
    ## (threading.local)`: thread-local values for Console context. `ref object
    ## of RootObj` (Nim thread-local storage is a body concern; the
    ## `threading.local` base is not ported). Fields mirror the dataclass
    ## (console.py:538-540).
    themeStack*: ThemeStack
      ## rich console.py:538 — `theme_stack: ThemeStack` (no default; seeded with
      ## `ThemeStack(themes.DEFAULT …)` in `Console.__init__`, console.py:743).
    buffer*: seq[Segment]
      ## rich console.py:539 — `buffer: List[Segment] = field(default_factory=list)`.
    bufferIndex*: int    ## rich console.py:540 — `buffer_index: int = 0`.

  RenderHook* = ref object of RootObj
    ## rich console.py:544-560 — `class RenderHook(ABC)`: provides hooks into the
    ## render process. `ABC` → `ref object of RootObj` (Nim has no abstract
    ## classes; `processRenderables` is the `@abstractmethod` stub proc). A hook
    ## instance is stored in `Console._render_hooks` (console.py:754).

  Console* = ref object of ConsoleHandle
    ## rich console.py:581-2642 — `class Console`: a high level console interface.
    ## `ref object of ConsoleHandle` (as `richbase` documents) so a renderable
    ## taking `console: ConsoleHandle` receives a real `Console`. Fields mirror
    ## the `__init__` assignments (console.py:619-751); private (`_`-prefixed in
    ## Python) fields are renamed (drop the underscore, disambiguate against the
    ## property getters/setters below).
    environ*: Table[string, string]
      ## rich console.py:623 — `self._environ = _environ` (`Mapping[str, str]` →
      ## `Table[string, string]`; renamed `_environ`→`environ`).
    isJupyter*: bool     ## rich console.py:627 — `self.is_jupyter = …`.
    tabSize*: int         ## rich console.py:633 — `self.tab_size = tab_size`.
    record*: bool         ## rich console.py:634 — `self.record = record`.
    markupFlag*: bool     ## rich console.py:635 — `self._markup = markup` (renamed).
    emojiFlag*: bool      ## rich console.py:636 — `self._emoji = emoji` (renamed).
    emojiVariant*: Option[EmojiVariant]
      ## rich console.py:637 — `self._emoji_variant: Optional[EmojiVariant] =
      ## emoji_variant` (renamed; qualified `emoji.EmojiVariant` — the real enum).
    highlightFlag*: bool  ## rich console.py:638 — `self._highlight = highlight`.
    legacyWindows*: bool  ## rich console.py:640-645 — `self.legacy_windows: bool`.
    softWrap*: bool       ## rich console.py:651 — `self.soft_wrap = soft_wrap`.
    widthVal*: Option[int]
      ## rich console.py:652 — `self._width = width` (renamed `_width`→`widthVal`,
      ## distinct from the `width` getter).
    heightVal*: Option[int]
      ## rich console.py:653 — `self._height = height` (renamed `_height`→
      ## `heightVal`, distinct from the `height` getter).
    colorSystemVal*: Option[ColorSystem]
      ## rich console.py:655-671 — `self._color_system: Optional[ColorSystem]`
      ## (renamed `_color_system`→`colorSystemVal`, distinct from the
      ## `colorSystem` getter).
    forceTerminalVal*: Option[system.bool]
      ## rich console.py:673-675 — `self._force_terminal` (renamed
      ## `_force_terminal`→`forceTerminalVal`).
    fileVal*: Option[FileHandle]
      ## rich console.py:677 — `self._file = file` (`Optional[IO[str]]` →
      ## `Option[FileHandle]`; renamed `_file`→`fileVal`, distinct from the
      ## `file` getter).
    quiet*: bool          ## rich console.py:678 — `self.quiet = quiet`.
    stderr*: bool         ## rich console.py:679 — `self.stderr = stderr`.
    lockRef*: LockHandle  ## rich console.py:737 — `self._lock = threading.RLock()`
                          ## (renamed `_lock`→`lockRef`; provisional `LockHandle`).
    logRender*: LogRender
      ## rich console.py:741 — `self._log_render = LogRender(…)` (renamed
      ## `_log_render`→`logRender`; provisional `LogRender`).
    highlighterField*: Highlighter
      ## rich console.py:742 — `self.highlighter: HighlighterType = highlighter or
      ## _null_highlighter` (renamed `highlighter`→`highlighterField` to avoid the
      ## clash with the `highlighter` *param* of `__init__`; the resolved
      ## `Highlighter` instance).
    safeBox*: bool        ## rich console.py:743 — `self.safe_box = safe_box`.
    getDatetime*: Option[GetDatetimeCallable]
      ## rich console.py:744 — `self.get_datetime = get_datetime or datetime.now`.
    getTime*: Option[GetTimeCallable]
      ## rich console.py:744 — `self.get_time = get_time or monotonic`.
    style*: StyleOpt      ## rich console.py:745 — `self.style = style`
                         ## (`Optional[StyleType]` → `StyleOpt`).
    noColor*: bool        ## rich console.py:746-749 — `self.no_color = …`.
    isInteractive*: bool  ## rich console.py:757-759 — `self.is_interactive = …`.
    recordBufferLock*: LockHandle
      ## rich console.py:753 — `self._record_buffer_lock = threading.RLock()`
      ## (renamed; provisional `LockHandle`).
    threadLocals*: ConsoleThreadLocals
      ## rich console.py:755 — `self._thread_locals = ConsoleThreadLocals(
      ## theme_stack=ThemeStack(themes.DEFAULT if theme is None else theme))`
      ## (renamed `_thread_locals`→`threadLocals`).
    recordBuffer*: seq[Segment]
      ## rich console.py:756 — `self._record_buffer: List[Segment] = []` (renamed).
    renderHooks*: seq[RenderHook]
      ## rich console.py:757 — `self._render_hooks: List[RenderHook] = []`.
    liveStack*: seq[Live]
      ## rich console.py:758 — `self._live_stack: List[Live] = []` (renamed).
    isAltScreenFlag*: bool
      ## rich console.py:759 — `self._is_alt_screen = False` (renamed
      ## `_is_alt_screen`→`isAltScreenFlag`, distinct from the `isAltScreen`
      ## getter).

# ---------------------------------------------------------------------------
# Module-level values — console.py:64-66, 274, 525, 38
# ---------------------------------------------------------------------------

const
  JUPYTER_DEFAULT_COLUMNS* = 115
    ## rich console.py:64 — `JUPYTER_DEFAULT_COLUMNS = 115`: default width
    ## (cells) when running in a Jupyter notebook (console.py:631).
  JUPYTER_DEFAULT_LINES* = 100
    ## rich console.py:65 — `JUPYTER_DEFAULT_LINES = 100`: default height (lines)
    ## in a Jupyter notebook (console.py:638).
  # `WINDOWS` (console.py:66) is NOT redeclared here: `color.nim:81` already
  # exports `WINDOWS* = defined(windows)` (same value, compile-time platform
  # check), and re-exporting both via the umbrella would make `WINDOWS`
  # ambiguous (Nim `let`/`const` symbols do not overload across modules).
  # `console` already imports `color` (below), so body bodies use
  # `color.WINDOWS` (single source of truth). The same reuse is applied in
  # `traceback.nim` (traceback.py:50 also defines `WINDOWS`).
  CONSOLE_HTML_FORMAT* = """<!DOCTYPE html>
<html>
<head>
<meta charset=\"UTF-8\">
<style>
{stylesheet}
body {{
    color: {foreground};
    background-color: {background};
}}
</style>
</head>
<body>
    <pre style=\"font-family:Menlo,'DejaVu Sans Mono',consolas,'Courier New',monospace\"><code style=\"font-family:inherit\">{code}</code></pre>
</body>
</html>
"""
    ## rich console.py:38 (via `_export_format`) — `CONSOLE_HTML_FORMAT`: the
    ## HTML export template, the default of `Console.save_html`'s
    ## `code_format` (console.py:2335). The verbatim rich 15.0.0 template
    ## (`_export_format.CONSOLE_HTML_FORMAT`); `pyFormat` substitutes
    ## `{stylesheet}`/`{foreground}`/`{background}`/`{code}` (Python `str.format`,
    ## `{{`/`}}` → literal braces).
  CONSOLE_SVG_FORMAT* = """<svg class=\"rich-terminal\" viewBox=\"0 0 {width} {height}\" xmlns=\"http://www.w3.org/2000/svg\">
    <!-- Generated with Rich https://www.textualize.io -->
    <style>

    @font-face {{
        font-family: \"Fira Code\";
        src: local(\"FiraCode-Regular\"),
                url(\"https://cdnjs.cloudflare.com/ajax/libs/firacode/6.2.0/woff2/FiraCode-Regular.woff2\") format(\"woff2\"),
                url(\"https://cdnjs.cloudflare.com/ajax/libs/firacode/6.2.0/woff/FiraCode-Regular.woff\") format(\"woff\");
        font-style: normal;
        font-weight: 400;
    }}
    @font-face {{
        font-family: \"Fira Code\";
        src: local(\"FiraCode-Bold\"),
                url(\"https://cdnjs.cloudflare.com/ajax/libs/firacode/6.2.0/woff2/FiraCode-Bold.woff2\") format(\"woff2\"),
                url(\"https://cdnjs.cloudflare.com/ajax/libs/firacode/6.2.0/woff/FiraCode-Bold.woff\") format(\"woff\");
        font-style: bold;
        font-weight: 700;
    }}

    .{unique_id}-matrix {{
        font-family: Fira Code, monospace;
        font-size: {char_height}px;
        line-height: {line_height}px;
        font-variant-east-asian: full-width;
    }}

    .{unique_id}-title {{
        font-size: 18px;
        font-weight: bold;
        font-family: arial;
    }}

    {styles}
    </style>

    <defs>
    <clipPath id=\"{unique_id}-clip-terminal\">
      <rect x=\"0\" y=\"0\" width=\"{terminal_width}\" height=\"{terminal_height}\" />
    </clipPath>
    {lines}
    </defs>

    {chrome}
    <g transform=\"translate({terminal_x}, {terminal_y})\" clip-path=\"url(#{unique_id}-clip-terminal)\">
    {backgrounds}
    <g class=\"{unique_id}-matrix\">
    {matrix}
    </g>
    </g>
</svg>
"""
    ## rich console.py:38 (via `_export_format`) — `CONSOLE_SVG_FORMAT`: the
    ## SVG export template, the default of `Console.export_svg`/`save_svg`'s
    ## `code_format` (console.py:2356, 2609). The verbatim rich 15.0.0 template
    ## (`_export_format.CONSOLE_SVG_FORMAT`); `pyFormat` substitutes the 16
    ## named fields (Python `str.format`, `{{`/`}}` → literal braces).

let
  nullHighlighter* {.used.} = NullHighlighter()
    ## rich console.py:274 — `_null_highlighter = NullHighlighter()`: the
    ## null-highlighter singleton, the fallback for `self.highlighter =
    ## highlighter or _null_highlighter` (console.py:742). `` until
    ## `Console.__init__`'s body references it in body.

# ---------------------------------------------------------------------------
# Private env/digit helpers (body bodies read `self._environ`; Python's
# `_environ.get(key)` → an `Option[string]` lookup over the console's environ
# table, which `initConsole` seeds from the real environment when no `_environ`
# is passed — matching rich's `os.environ` class default).
proc envGet(self: Console, key: string): Option[string] =
  if self.environ.hasKey(key): some(self.environ[key]) else: none(string)

proc isDigitStr(s: string): bool =
  if s.len == 0: return false
  for c in s:
    if not c.isDigit: return false
  true

# ---------------------------------------------------------------------------
# Private format/escape helpers (body bodies of export_html/export_svg
# and the `str.format`/`format(value,"g")` shims used by the export
# templates). These are internal helpers (not exported) — they port
# `html.escape`, `str.format` (named placeholders only) and `format(value,
# "g")` for the export_* bodies, which the canonical 56 modules do not own.
# ---------------------------------------------------------------------------
proc htmlEscape(s: string): string =
  ## rich `html.escape(s, quote=True)` (console.py:2298,2440) — escape `&`,
  ## `<`, `>`, `"`, `'` for HTML/SVG text. Approximates Python's `html.escape`
  ## with `quote=True` (the default at both call sites).
  result = newStringOfCap(s.len)
  for c in s:
    case c
    of '&': result.add("&amp;")
    of '<': result.add("&lt;")
    of '>': result.add("&gt;")
    of '"': result.add("&quot;")
    of '\'': result.add("&#x27;")
    else: result.add(c)

proc pyFormat(fmt: string, subs: Table[string, string]): string =
  ## rich `str.format(**subs)` (console.py:2307,2598) for the export templates:
  ## substitute `{key}` named placeholders and unescape `{{`/`}}` to literal
  ## braces. A minimal named-placeholder formatter — the export templates use
  ## only named `{...}` fields and `{{`/`}}` literals (no positional args or
  ## format specs), so the full `str.format` mini-language is not needed.
  result = newStringOfCap(fmt.len)
  var i = 0
  let n = fmt.len
  while i < n:
    if fmt[i] == '{' and i + 1 < n and fmt[i + 1] == '{':
      result.add('{'); i += 2
    elif fmt[i] == '}' and i + 1 < n and fmt[i + 1] == '}':
      result.add('}'); i += 2
    elif fmt[i] == '{':
      let close = fmt.find('}', i + 1)
      if close < 0:
        result.add(fmt[i]); i += 1
      else:
        let key = fmt[i + 1 ..< close]
        if subs.hasKey(key): result.add(subs[key])
        i = close + 1
    else:
      result.add(fmt[i]); i += 1

proc gFormat(f: float): string =
  ## rich `format(value, "g")` (console.py:2434, the SVG `make_tag` float
  ## stringifier): general format with 6 significant figures and trailing
  ## zeros/decimal point stripped (Python `"g"` default precision is 6).
  ## Approximated via `formatFloat(f, ffDefault, 6)` + trailing-zero stripping;
  ## not byte-identical to Python "g" for all magnitudes but renders identically
  ## (body does not byte-test SVG output).
  result = formatFloat(f, ffDefault, 6)
  if result.find('.') >= 0 and result.find('e') < 0 and result.find('E') < 0:
    while result.len > 1 and result[^1] == '0': result.setLen(result.len - 1)
    if result.len > 1 and result[^1] == '.': result.setLen(result.len - 1)

# ---------------------------------------------------------------------------
# NewLine — console.py:280-289
# ---------------------------------------------------------------------------

proc initNewLine*(count: int = 1): NewLine =
  ## rich console.py:283-284 — `NewLine.__init__(self, count: int = 1) -> None`:
  ## `self.count = count`.
  result = NewLine()
  result.count = count

method renderConsole*(self: NewLine, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich console.py:286-289 — `NewLine.__rich_console__(self, console: "Console",
  ## options: "ConsoleOptions") -> Iterable[Segment]`: `yield Segment("\n" *
  ## self.count)`. The richbase `ConsoleHandle`/`ConsoleOptions` placeholders;
  ## `Iterable[Segment]` → `RenderResult`. Faithful port via the port
  ## `addSegment*` constructor (richbase "unfreeze").
  result = @[]
  # `yield Segment("\n" * self.count)` (console.py:288) → a single Segment of
  # `self.count` line feeds. `repeat` (strutils) ports Python `str * int`.
  result.addSegment(initSegment(repeat("\n", self.count)))

# ---------------------------------------------------------------------------
# ScreenUpdate — console.py:292-307
# ---------------------------------------------------------------------------

proc initScreenUpdate*(lines: seq[seq[Segment]], x: int, y: int): ScreenUpdate =
  ## rich console.py:295-298 — `ScreenUpdate.__init__(self, lines: List[List
  ## [Segment]], x: int, y: int) -> None`: `self._lines = lines; self.x = x;
  ## self.y = y`. `List[List[Segment]]` → `seq[seq[Segment]]`.
  result = ScreenUpdate()
  result.linesData = lines
  result.x = x
  result.y = y

method renderConsole*(self: ScreenUpdate, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich console.py:300-307 — `ScreenUpdate.__rich_console__(self, console:
  ## "Console", options: ConsoleOptions) -> RenderResult`: for each line at its
  ## offset, `yield Control.move_to(x, offset); yield from line`. Faithful port
  ## via `addSegment*` (richbase "unfreeze").
  result = @[]
  # `x = self.x; move_to = Control.move_to; for offset, line in
  # enumerate(self._lines, self.y): yield move_to(x, offset); yield from line`
  # (console.py:303-306). The yielded `Control.move_to(x, offset)` is a
  # renderable that `Console.render` would recurse to `Control.renderConsole`
  # (yielding `control.segment`); here its pre-rendered `.segment` is added
  # directly via `addSegment` so a `ScreenUpdate` produces real `Segment`s even
  # before `Control.renderConsole` (child_2) is wired — the segment text is the
  # faithful ANSI, and a control `Segment` is what `Control.renderConsole`
  # itself would yield (control.py:113-115).
  let x = self.x
  for i, line in self.linesData:
    let offset = self.y + i
    result.addSegment(ctrl.moveTo(x, offset).segment)
    for seg in line:
      result.addSegment(seg)

# ---------------------------------------------------------------------------
# Capture — console.py:310-340
# ---------------------------------------------------------------------------

proc initCapture*(console: Console): Capture =
  ## rich console.py:318-320 — `Capture.__init__(self, console: "Console") ->
  ## None`: `self._console = console; self._result = None`.
  result = Capture()
  result.console = console
  result.captureResult = none(string)

# Forward declarations: Console procs called before their definitions (enter/exit context procs).
proc beginCapture*(self: Console)
proc endCapture*(self: Console): string
proc pushTheme*(self: Console, theme: Theme, inherit: bool = true)
proc popTheme*(self: Console)
proc enterBuffer*(self: Console)
proc exitBuffer*(self: Console)
proc checkBuffer*(self: Console)
proc renderBuffer*(self: Console, buffer: openArray[Segment]): string
proc writeBuffer*(self: Console)
proc size*(self: Console): ConsoleDimensions
proc updateScreenLines*(self: Console, lines: seq[seq[Segment]], x: int = 0, y: int = 0)
proc control*(self: Console, control: varargs[Control])
# Forward declaration: `renderStr` (rich console.py:1409) used in `render` (the
# rvString arm) before its definition below.
proc renderStr*(self: Console, text: string, style: StyleType = "",
               justify: Option[JustifyMethod] = none(JustifyMethod),
               overflow: Option[OverflowMethod] = none(OverflowMethod),
               emoji: Option[system.bool] = none(system.bool),
               markup: Option[system.bool] = none(system.bool),
               highlight: Option[system.bool] = none(system.bool),
               highlighter: Option[Highlighter] = none(Highlighter)): Text
proc setAltScreen*(self: Console, enable: bool = true): bool
proc showCursor*(self: Console, show: bool = true): bool
# Forward declarations: Console `@property` getters (rich console.py:931/979) used
# before their definitions (initConsole body + detectColorSystem) — `is_terminal`/
# `is_dumb_terminal` are Python properties (no parens), ported as procs.
proc isTerminal*(self: Console): bool
proc isDumbTerminal*(self: Console): bool
proc print*(self: Console, objects: openArray[RenderableValue], sep: string = " ",
           `end`: string = "\n", style: StyleOpt = default(StyleOpt),
           justify: Option[JustifyMethod] = none(JustifyMethod),
           overflow: Option[OverflowMethod] = none(OverflowMethod),
           noWrap: Option[system.bool] = none(system.bool), emoji: Option[system.bool] = none(system.bool),
           markup: Option[system.bool] = none(system.bool), highlight: Option[system.bool] = none(system.bool),
           width: Option[int] = none(int), crop: bool = true,
           softWrap: Option[system.bool] = none(system.bool), newLineStart: bool = false)
# Forward declaration: initGroup used at ~845, defined at ~875.
proc initGroup*(renderables: openArray[RenderableValue], fit: bool = true): Group

proc enter*(self: Capture): Capture =
  ## rich console.py:322-324 — `Capture.__enter__(self) -> "Capture"`:
  ## `self._console.begin_capture(); return self`. Dunder `__enter__`→`enter`
  ## (mirrors `live.nim`/`status.nim`); returns the `Capture`.
  self.console.beginCapture()
  result = self

proc exit*(self: Capture, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich console.py:326-332 — `Capture.__exit__`: `self._result =
  ## self._console.end_capture()`. Dunder `__exit__`→`exit`; the three exc params
  ## mirror `live.nim`/`status.nim`.
  self.captureResult = some(self.console.endCapture())

proc get*(self: Capture): string =
  ## rich console.py:334-340 — `Capture.get(self) -> str`: return the captured
  ## result, raising `CaptureError` if called before the context exits
  ## (console.py:337).
  # rich raises `CaptureError` (console.py:272, declared in console.py); that
  # type is not in the frozen tree, so raise a `CatchableError` with the
  # faithful message.
  if self.captureResult.isSome:
    return self.captureResult.get
  raise newException(CatchableError,
    "Capture result is not available until context manager exits.")

# ---------------------------------------------------------------------------
# ThemeContext — console.py:343-361
# ---------------------------------------------------------------------------

proc initThemeContext*(console: Console, theme: Theme,
                       inherit: bool = true): ThemeContext =
  ## rich console.py:346-349 — `ThemeContext.__init__(self, console: "Console",
  ## theme: Theme, inherit: bool = True) -> None`.
  result = ThemeContext()
  result.console = console
  result.theme = theme
  result.inherit = inherit

proc enter*(self: ThemeContext): ThemeContext =
  ## rich console.py:351-353 — `ThemeContext.__enter__`: `self.console.push_theme
  ## (self.theme); return self`. Dunder `__enter__`→`enter`.
  # rich's `ThemeContext.__enter__` calls `push_theme(self.theme)` (inherit
  # defaults to True) — the stored `inherit` is not applied here (console.py:352).
  self.console.pushTheme(self.theme)
  result = self

proc exit*(self: ThemeContext, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich console.py:355-361 — `ThemeContext.__exit__`: `self.console.pop_theme()`.
  self.console.popTheme()

# ---------------------------------------------------------------------------
# PagerContext — console.py:364-400
# ---------------------------------------------------------------------------

proc initPagerContext*(console: Console, pager: Option[Pager] = none(Pager),
                       styles: bool = false, links: bool = false): PagerContext =
  ## rich console.py:367-377 — `PagerContext.__init__(self, console: "Console",
  ## pager: Optional[Pager] = None, styles: bool = False, links: bool = False)
  ## -> None`. `pager: Optional[Pager]` → `Option[Pager]` (the provisional handle,
  ## default `none(Pager)`).
  result = PagerContext()
  result.console = console
  # rich resolves `None` to `SystemPager()` (console.py:373); `pager.nim` is not
  # ported this round, so the placeholder `Pager()` stands in for `SystemPager()`
  # (the real `SystemPager` is wired when `pager.nim` is imported).
  result.pager = if pager.isSome: pager.get else: Pager()
  result.styles = styles
  result.links = links

proc enter*(self: PagerContext): PagerContext =
  ## rich console.py:379-381 — `PagerContext.__enter__`:
  ## `self._console._enter_buffer(); return self`.
  self.console.enterBuffer()
  result = self

proc exit*(self: PagerContext, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich console.py:383-400 — `PagerContext.__exit__`: on success render the
  ## buffer (stripping styles/links per the flags) and `self.pager.show(content)`,
  ## then `self._console._exit_buffer()`. Body needs the real `Pager`
  ## (pager.nim) + `Segment.strip_styles`/`strip_links`.
  # rich renders the buffer (stripping styles/links per the flags) and calls
  # `self.pager.show(content)` only on success (console.py:383-400); that path is
  # DEFERRED (`Segment.strip_styles`/`strip_links` are stubs,
  # `_render_buffer` is blocked by the `StyleRef`→`Style` downcast, and the
  # provisional `Pager` has no `show()`). `_exit_buffer` (which flushes via
  # `_check_buffer`) is called unconditionally, faithful to console.py:400.
  self.console.exitBuffer()

# ---------------------------------------------------------------------------
# ScreenContext — console.py:403-447
# ---------------------------------------------------------------------------

proc initScreenContext*(console: Console, hideCursor: bool,
                        style: StyleType = ""): ScreenContext =
  ## rich console.py:406-412 — `ScreenContext.__init__(self, console: "Console",
  ## hide_cursor: bool, style: StyleType = "") -> None`. `style: StyleType = ""`
  ## (not `Optional`; the `string or Style` typeclass, default `""`). port
  ## stub.
  result = ScreenContext()
  result.console = console
  result.hideCursor = hideCursor
  let noRenderables: seq[RenderableValue] = @[]
  result.screen = initScreen(noRenderables, style, false)
  result.changed = false

proc update*(self: ScreenContext, renderables: openArray[RenderableValue],
             style: StyleOpt = default(StyleOpt)) =
  ## rich console.py:408-430 — `ScreenContext.update(self, *renderables:
  ## RenderableType, style: Optional[StyleType] = None) -> None`: replace the
  ## screen renderable (wrapping multiple in a `Group`) and/or its style, then
  ## `self.console.print(self.screen, end="")`. Python's `*renderables` varargs →
  ## `openArray[RenderableValue]` (Nim varargs must be last, but `style` follows
  ## — same translation as `initScreen`); `style: Optional[StyleType]` → `StyleOpt`
  ## (default `None` via `default(StyleOpt)`).
  if renderables.len > 0:
    let g: RenderableValue =
      if renderables.len > 1: toRenderableValue(initGroup(renderables)) else: renderables[0]
    self.screen.renderable = g
  if style.kind != sokNone:
    self.screen.style = style
  var objs: seq[RenderableValue] = @[]
  objs.add(self.screen)
  self.console.print(objs, `end` = "")

proc enter*(self: ScreenContext): ScreenContext =
  ## rich console.py:432-436 — `ScreenContext.__enter__`: `self._changed =
  ## self.console.set_alt_screen(True)` (hiding the cursor if changed). port
  ## stub.
  self.changed = self.console.setAltScreen(true)
  if self.changed and self.hideCursor:
    discard self.console.showCursor(false)
  result = self

proc exit*(self: ScreenContext, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich console.py:438-447 — `ScreenContext.__exit__`: if changed, restore the
  ## alt screen and the cursor.
  if self.changed:
    discard self.console.setAltScreen(false)
    if self.hideCursor:
      discard self.console.showCursor(true)

# ---------------------------------------------------------------------------
# Group — console.py:450-480
# ---------------------------------------------------------------------------

proc initGroup*(renderables: openArray[RenderableValue],
                fit: bool = true): Group =
  ## rich console.py:458-461 — `Group.__init__(self, *renderables:
  ## "RenderableType", fit: bool = True) -> None`. Python's `*renderables`
  ## varargs → `openArray[RenderableValue]` (the storable `RenderableType`
  ## handle).
  result = Group()
  result.renderablesData = @renderables
  result.fit = fit
  result.renderCache = none(seq[RenderableValue])

proc renderables*(self: Group): seq[RenderableValue] =
  ## rich console.py:464-467 — `Group.renderables` property (`@property`
  ## console.py:463): lazily materialise `self._renderables` into `self._render`
  ## (`list(self._renderables)`) and return it.
  if not self.renderCache.isSome:
    self.renderCache = some(self.renderablesData)
  return self.renderCache.get

proc richMeasure*(self: Group, console: ConsoleHandle,
                  options: ConsoleOptions): Measurement =
  ## rich console.py:469-475 — `Group.__rich_measure__`: if `fit`,
  ## `measure_renderables(console, options, self.renderables)` else
  ## `Measurement(options.max_width, options.max_width)`. The richbase
  ## `ConsoleHandle`/`ConsoleOptions`; `Measurement` from `measure.nim`. port
  ## stub.
  if not self.fit:
    return Measurement(minimum: options.maxWidth, maximum: options.maxWidth)
  # `measure_renderables(console, options, self.renderables)` (console.py:472) is
  # blocked by `RenderableValue`→`RenderableType` type erasure (the stored
  # `seq[RenderableValue]` cannot be passed to `measureRenderables`'s
  # `openArray[RenderableType]`); replicate its reduce (max of minimums, max of
  # maximums) with the same deferred fallback for the `RenderableBase` arms
  # (mirrors `tree.nim`/`measure.nim`).
  var mn = 0
  var mx = 0
  for r in self.renderables:
    let m = case r.kind
      of rvString: Measurement.get(console, options, r.textStr)
      of rvConsoleRenderable: Measurement(minimum: 0, maximum: options.maxWidth)
      of rvRichCast: Measurement(minimum: 0, maximum: options.maxWidth)
    mn = max(mn, m.minimum)
    mx = max(mx, m.maximum)
  return Measurement(minimum: mn, maximum: mx)

method renderConsole*(self: Group, console: ConsoleHandle,
                    options: ConsoleOptions): RenderResult =
  ## rich console.py:477-480 — `Group.__rich_console__`: `yield from
  ## self.renderables`. Faithful port via the port `addString*`/`addRenderable*`
  ## constructors (richbase "unfreeze"): each `RenderableValue` arm of
  ## `self.renderables` is re-yielded as the matching `RenderResultItem` arm so
  ## `Console.render` (the caller) recurses on the non-`Segment` outputs —
  ## exactly Python's `yield from` over a `List[RenderableType]`.
  result = @[]
  for r in self.renderables:
    case r.kind
    of rvString:
      result.addString(r.textStr)
    of rvConsoleRenderable:
      result.addRenderable(r.consoleItem, rrkConsoleRenderable)
    of rvRichCast:
      result.addRenderable(r.castItem, rrkRichCast)

# ---------------------------------------------------------------------------
# group decorator factory — console.py:483-502
# ---------------------------------------------------------------------------

proc group*(fit: bool = true):
    proc(`method`: proc(): seq[RenderableValue]): proc(): Group =
  ## rich console.py:483-502 — `group(fit: bool = True) -> Callable[...,
  ## Callable[..., Group]]`: a decorator factory turning a method returning an
  ## iterable of renderables into one returning a `Group(*renderables, fit=fit)`.
  ## The return type models the outer `Callable[..., Callable[..., Group]]`: a
  ## closure taking the decorated `method: Callable[..., Iterable[RenderableType]]`
  ## (→ `proc(): seq[RenderableValue]`) and returning the replacement `_replace:
  ## (*args, **kwargs) -> Group` (→ `proc(): Group`).
  return proc(`method`: proc(): seq[RenderableValue]): proc(): Group =
    return proc(): Group =
      let renderables = `method`()
      return initGroup(renderables, fit)

# ---------------------------------------------------------------------------
# Module-level probes — console.py:505, 566, 576
# ---------------------------------------------------------------------------

proc isJupyterImpl*(): bool =
  ## rich console.py:505-522 — `_is_jupyter() -> bool` (`# pragma: no cover`):
  ## check if running in a Jupyter notebook. Maps the private `_is_jupyter`;
  # `# pragma: no cover`: rich probes `get_ipython` (catching `NameError`) and
  # inspects the IPython shell class. No IPython integration is ported, so the
  # faithful non-Jupyter result is `False` (the `NameError` branch).
  result = false

proc getWindowsConsoleFeatures*(): WindowsConsoleFeatures =
  ## rich console.py:566-573 — `get_windows_console_features() ->
  ## "WindowsConsoleFeatures"` (`# pragma: no cover`, Windows-only). Returns the
  ## provisional `WindowsConsoleFeatures` handle.
  result = WindowsConsoleFeatures()

proc detectLegacyWindows*(): bool =
  ## rich console.py:576-578 — `detect_legacy_windows() -> bool`: detect legacy
  ## Windows (`WINDOWS and not is_jupyter()`, console.py:577).
  # rich: `WINDOWS and not get_windows_console_features().vt`. The Windows vt probe
  # (a private module, `# pragma: no cover`) isn't ported; the placeholder
  # `WindowsConsoleFeatures` carries no `vt`, so approximate with
  # `WINDOWS and not isJupyterImpl()` (vt is false only on legacy Windows).
  result = color.WINDOWS and not isJupyterImpl()

# ---------------------------------------------------------------------------
# ConsoleThreadLocals — console.py:536-541
# ---------------------------------------------------------------------------

proc initConsoleThreadLocals*(themeStack: ThemeStack): ConsoleThreadLocals =
  ## rich console.py:536-541 — `ConsoleThreadLocals.__init__` (dataclass): seed
  ## `theme_stack` with `themeStack`; `buffer`/`buffer_index` take their dataclass
  ## defaults. Drops the `threading.local` base (body concern).
  result = ConsoleThreadLocals()
  result.themeStack = themeStack
  result.buffer = @[]
  result.bufferIndex = 0

# ---------------------------------------------------------------------------
# RenderHook — console.py:544-560
# ---------------------------------------------------------------------------

proc processRenderables*(self: RenderHook,
                         renderables: openArray[RenderableBase]): seq[RenderableBase] =
  ## rich console.py:548-560 — `RenderHook.process_renderables(self, renderables:
  ## List[ConsoleRenderable]) -> List[ConsoleRenderable]` (`@abstractmethod`).
  ## `List[ConsoleRenderable]` → `seq[RenderableBase]` (the storable base;
  ## `ConsoleRenderable` is a concept); the param is `openArray[RenderableBase]`.
  ## stub (the `@abstractmethod` placeholder).
  # Genuine abstract no-op: rich's `RenderHook.process_renderables` is an
  # `@abstractmethod` (console.py:548-560) with no base body — subclasses
  # override it. The base returns the default (empty) list, faithfully matching
  # the abstract placeholder.
  discard

# ---------------------------------------------------------------------------
# Console — console.py:581-2642
# ---------------------------------------------------------------------------

proc initConsole*(
    colorSystem: Option[string] = some("auto"),
    forceTerminal: Option[system.bool] = none(system.bool),
    forceJupyter: Option[system.bool] = none(system.bool),
    forceInteractive: Option[system.bool] = none(system.bool),
    softWrap: bool = false,
    theme: Option[Theme] = none(Theme),
    stderr: bool = false,
    file: Option[FileHandle] = none(FileHandle),
    quiet: bool = false,
    width: Option[int] = none(int),
    height: Option[int] = none(int),
    style: StyleOpt = default(StyleOpt),
    noColor: Option[system.bool] = none(system.bool),
    tabSize: int = 8,
    record: bool = false,
    markup: bool = true,
    emoji: bool = true,
    emojiVariant: Option[EmojiVariant] = none(EmojiVariant),
    highlight: bool = true,
    logTime: bool = true,
    logPath: bool = true,
    logTimeFormat: string or FormatTimeCallable = "[%X]",
    highlighter: Option[Highlighter] = some[Highlighter](ReprHighlighter()),
    legacyWindows: Option[system.bool] = none(system.bool),
    safeBox: bool = true,
    getDatetime: Option[GetDatetimeCallable] = none(GetDatetimeCallable),
    getTime: Option[GetTimeCallable] = none(GetTimeCallable),
    environ: Option[Table[string, string]] = none(Table[string, string])
): Console =
  ## rich console.py:619-751 — `Console.__init__` (keyword-only, all params have
  ## defaults). `color_system: Optional[Literal[…]] = "auto"` → `Option[string] =
  ## some("auto")` (the `Literal` narrowing is body); `emoji_variant` →
  ## `Option[emoji.EmojiVariant]` (qualified — the real enum); `style:
  ## Optional[StyleType] = None` → `StyleOpt` (default `None` via
  ## `default(StyleOpt)`); `log_time_format: Union[str, FormatTimeCallable] =
  ## "[%X]"` → `string or FormatTimeCallable` (default the `str` `"[%X]"`);
  ## `highlighter: Optional[HighlighterType] = ReprHighlighter()` →
  ## `Option[Highlighter] = some[Highlighter](ReprHighlighter())` (the
  ## `ReprHighlighter()` ref-construction upcasts to the `Highlighter` base);
  ## `_environ` → `environ`.
  result = Console()
  # `_environ` (console.py:623): use the supplied mapping, else seed from the
  # real environment (rich's `os.environ` class default).
  if environ.isSome:
    result.environ = environ.get
  else:
    var env = initTable[string, string]()
    for k, v in envPairs():
      env[k] = v
    result.environ = env
  # is_jupyter (console.py:627).
  result.isJupyter = if forceJupyter.isSome: forceJupyter.get else: isJupyterImpl()
  # Jupyter width/height defaults (console.py:631-638).
  var w = width
  var h = height
  if result.isJupyter:
    if w.isNone:
      let jc = envGet(result, "JUPYTER_COLUMNS")
      if jc.isSome and isDigitStr(jc.get): w = some(parseInt(jc.get))
      else: w = some(JUPYTER_DEFAULT_COLUMNS)
    if h.isNone:
      let jl = envGet(result, "JUPYTER_LINES")
      if jl.isSome and isDigitStr(jl.get): h = some(parseInt(jl.get))
      else: h = some(JUPYTER_DEFAULT_LINES)
  result.tabSize = tabSize
  result.record = record
  result.markupFlag = markup
  result.emojiFlag = emoji
  result.emojiVariant = emojiVariant
  result.highlightFlag = highlight
  result.legacyWindows =
    if legacyWindows.isSome: legacyWindows.get
    else: (detectLegacyWindows() and not result.isJupyter)
  # width/height from COLUMNS/LINES env (console.py:647-650).
  if w.isNone:
    let cols = envGet(result, "COLUMNS")
    if cols.isSome and isDigitStr(cols.get):
      w = some(parseInt(cols.get) - (if result.legacyWindows: 1 else: 0))
  if h.isNone:
    let lns = envGet(result, "LINES")
    if lns.isSome and isDigitStr(lns.get):
      h = some(parseInt(lns.get))
  result.softWrap = softWrap
  result.widthVal = w
  result.heightVal = h
  # force_terminal / file / quiet / stderr (console.py:673-679) — set BEFORE
  # the color-system detection, which reads `is_terminal`.
  result.forceTerminalVal = forceTerminal
  result.fileVal = file
  result.quiet = quiet
  result.stderr = stderr
  # color_system (console.py:680-686).
  if colorSystem.isNone:
    result.colorSystemVal = none(ColorSystem)
  else:
    let cs = colorSystem.get
    if cs == "auto":
      result.colorSystemVal = result.detectColorSystem()
    else:
      result.colorSystemVal =
        case cs
        of "standard": some(ColorSystem.standard)
        of "256": some(ColorSystem.eightBit)
        of "truecolor": some(ColorSystem.truecolor)
        of "windows": some(ColorSystem.windows)
        else: raise newException(KeyError, cs)  # faithful to rich's COLOR_SYSTEMS[cs] KeyError (console.py:686)
  # locks / log render / highlighter / safe_box (console.py:737-743).
  result.lockRef = LockHandle()
  result.logRender = LogRender()  # provisional LogRender (no fields/ctor yet)
  result.highlighterField =
    if highlighter.isSome: highlighter.get else: nullHighlighter
  result.safeBox = safeBox
  # get_datetime/get_time (console.py:744): the rich defaults (`datetime.now`,
  # `time.monotonic`) are deferred (no portable default closure is wired); store
  # the supplied callable or `none`.
  result.getDatetime = getDatetime
  result.getTime = getTime
  result.style = style
  # no_color (console.py:746-749).
  result.noColor =
    if noColor.isSome: noColor.get
    else: envGet(result, "NO_COLOR").get("") != ""
  # force_interactive env (console.py:750-755).
  var fi = forceInteractive
  if fi.isNone:
    let ttyi = envGet(result, "TTY_INTERACTIVE")
    if ttyi.isSome:
      if ttyi.get == "0": fi = some(false)
      elif ttyi.get == "1": fi = some(true)
  result.isInteractive =
    if fi.isSome: fi.get
    else: (result.isTerminal and not result.isDumbTerminal)
  # record buffer / thread locals / render hooks / live stack / alt screen
  # (console.py:753-759).
  result.recordBufferLock = LockHandle()
  let baseTheme = if theme.isSome: theme.get else: themes.DEFAULT
  result.threadLocals = initConsoleThreadLocals(initThemeStack(baseTheme))
  result.recordBuffer = @[]
  result.renderHooks = @[]
  result.liveStack = @[]
  result.isAltScreenFlag = false

proc repr*(self: Console): string =
  ## rich console.py:753-754 — `Console.__repr__`:
  ## `f"<console width={self.width} {self._color_system!s}>"`. Overloads
  ## `system.repr` on the `Console` receiver.
  # `self._color_system!s` = `str(ColorSystem.X)` = `"ColorSystem.STANDARD"`
  # (color.py:29-33 → color.nim `$`/`repr`); `None` → `"None"`.
  let csStr = if self.colorSystemVal.isSome: $self.colorSystemVal.get else: "None"
  result = "<console width=" & $self.widthVal & " " & csStr & ">"

proc file*(self: Console): FileHandle =
  ## rich console.py:757-763 — `Console.file` property getter (`@property`
  ## console.py:756): get the file object to write to (defaulting `_file` to
  ## `sys.stderr` if `stderr` else `sys.stdout`). Returns the `FileHandle`. port
  ## stub.
  if self.fileVal.isSome:
    return self.fileVal.get
  # rich defaults `_file` to `sys.stderr` if `stderr` else `sys.stdout` and
  # follows `rich_proxied_file`; no `IO[str]` model is ported, so return a fresh
  # placeholder `FileHandle` stand-in for the std stream.
  return FileHandle()

proc setFile*(self: Console, newFile: FileHandle) =
  ## rich console.py:766-768 — `Console.file` setter (`@file.setter`
  ## console.py:765): `self._file = new_file`.
  self.fileVal = some(newFile)

proc buffer*(self: Console): seq[Segment] =
  ## rich console.py:771-773 — `Console._buffer` getter (`@property`
  ## console.py:770): get the thread-local buffer.
  return self.threadLocals.buffer

proc bufferIndex*(self: Console): int =
  ## rich console.py:776-778 — `Console._buffer_index` getter.
  return self.threadLocals.bufferIndex

proc setBufferIndex*(self: Console, value: int) =
  ## rich console.py:781-782 — `Console._buffer_index` setter.
  self.threadLocals.bufferIndex = value

proc themeStack*(self: Console): ThemeStack =
  ## rich console.py:785-787 — `Console._theme_stack` getter.
  return self.threadLocals.themeStack

proc detectColorSystem*(self: Console): Option[ColorSystem] =
  ## rich console.py:789-811 — `Console._detect_color_system(self) ->
  ## Optional[ColorSystem]`: detect the color system from env vars.
  if self.isJupyter:
    return some(ColorSystem.truecolor)
  if not self.isTerminal or self.isDumbTerminal:
    return none(ColorSystem)
  if color.WINDOWS:
    if self.legacyWindows:
      return some(ColorSystem.windows)
    # `get_windows_console_features().truecolor` (console.py:703) is not modelled
    # (Windows-only, `# pragma: no cover`); default to truecolor as a best-effort
    # for modern Windows.
    return some(ColorSystem.truecolor)
  let colorTerm = envGet(self, "COLORTERM").get("").strip().toLowerAscii()
  if colorTerm == "truecolor" or colorTerm == "24bit":
    return some(ColorSystem.truecolor)
  let term = envGet(self, "TERM").get("").strip().toLowerAscii()
  let idx = term.rfind('-')
  let colors = if idx >= 0: term.substr(idx + 1) else: ""
  # `_TERM_COLORS = {"kitty": EIGHT_BIT, "256color": EIGHT_BIT, "16color": STANDARD}`
  # (console.py:92-96); unknown suffix → STANDARD.
  case colors
  of "kitty", "256color": return some(ColorSystem.eightBit)
  of "16color": return some(ColorSystem.standard)
  else: return some(ColorSystem.standard)

proc enterBuffer*(self: Console) =
  ## rich console.py:813-815 — `Console._enter_buffer`: enter a buffer context
  ## (increment `_buffer_index`).
  self.threadLocals.bufferIndex += 1

proc exitBuffer*(self: Console) =
  ## rich console.py:817-820 — `Console._exit_buffer`: leave the buffer context,
  ## rendering the buffer if the index reaches 0.
  self.threadLocals.bufferIndex -= 1
  self.checkBuffer()

proc setLive*(self: Console, live: Live): bool =
  ## rich console.py:822-836 — `Console.set_live(self, live: "Live") -> bool`: set
  ## the `Live` instance using this Console; returns whether it is the topmost;
  ## raises `errors.LiveError` if a Live is already active.
  # rich appends under `self._lock` and returns whether it is the topmost
  # (console.py:834-836); the `RLock` is not ported (provisional `LockHandle`
  # with no methods), so the append runs unlocked — same single-threaded result.
  # The docstring's `errors.LiveError` note is a red herring: rich's body just
  # appends (no raise), so this is faithful.
  self.liveStack.add(live)
  return self.liveStack.len == 1

proc clearLive*(self: Console) =
  ## rich console.py:838-841 — `Console.clear_live`: clear the Live instance.
  if self.liveStack.len > 0:
    discard self.liveStack.pop()

proc pushRenderHook*(self: Console, hook: RenderHook) =
  ## rich console.py:843-850 — `Console.push_render_hook(self, hook: RenderHook)`:
  ## add a render hook to the stack.
  self.renderHooks.add(hook)

proc popRenderHook*(self: Console) =
  ## rich console.py:852-855 — `Console.pop_render_hook`: pop the last render hook.
  if self.renderHooks.len > 0:
    discard self.renderHooks.pop()

proc enter*(self: Console): Console =
  ## rich console.py:857-860 — `Console.__enter__`: own context manager —
  ## `self._enter_buffer(); return self`. Dunder `__enter__`→`enter`; returns the
  ## `Console`.
  self.enterBuffer()
  result = self

proc exit*(self: Console, excType: Option[RootRef],
           excVal: Option[ref CatchableError], excTb: Option[RootRef]) =
  ## rich console.py:862-864 — `Console.__exit__`: exit the buffer context. Dunder
  ## `__exit__`→`exit`; the three exc params mirror `live.nim`/`status.nim`.
  self.exitBuffer()

proc beginCapture*(self: Console) =
  ## rich console.py:866-868 — `Console.begin_capture`: begin capturing console
  ## output (enter buffer + reset buffer).
  # rich's `begin_capture` is `self._enter_buffer()` (console.py:867).
  self.enterBuffer()

proc endCapture*(self: Console): string =
  ## rich console.py:870-879 — `Console.end_capture(self) -> str`: end capture
  ## mode and return the captured string.
  let r = self.renderBuffer(self.buffer)
  self.threadLocals.buffer.setLen(0)
  self.exitBuffer()
  return r

proc pushTheme*(self: Console, theme: Theme, inherit: bool = true) =
  ## rich console.py:881-890 — `Console.push_theme(self, theme: Theme, *,
  ## inherit: bool = True)`: push a merged theme on to the stack.
  self.themeStack.pushTheme(theme, inherit)

proc popTheme*(self: Console) =
  ## rich console.py:892-894 — `Console.pop_theme`: pop the top-most theme.
  self.themeStack.popTheme()

proc useTheme*(self: Console, theme: Theme,
               inherit: bool = true): ThemeContext =
  ## rich console.py:896-906 — `Console.use_theme(self, theme: Theme, *,
  ## inherit: bool = True) -> ThemeContext`: return a `ThemeContext` for a
  ## temporary theme.
  result = initThemeContext(self, theme, inherit)

proc colorSystem*(self: Console): Option[string] =
  ## rich console.py:909-919 — `Console.color_system` property (`@property`
  ## console.py:908): get the color system string (`"standard"`/`"256"`/
  ## `"truecolor"` or `None`).
  if self.colorSystemVal.isNone:
    result = none(string)
  else:
    case self.colorSystemVal.get
    of ColorSystem.standard: result = some("standard")
    of ColorSystem.eightBit: result = some("256")
    of ColorSystem.truecolor: result = some("truecolor")
    of ColorSystem.windows: result = some("windows")

proc encoding*(self: Console): string =
  ## rich console.py:922-928 — `Console.encoding` property: get the encoding of
  ## the console file (e.g. `"utf-8"`).
  # rich reads `self.file.encoding` (defaulting to `"utf-8"`); the placeholder
  # `FileHandle` carries no `encoding`, so return the faithful default.
  result = "utf-8"

proc isTerminal*(self: Console): bool =
  ## rich console.py:931-976 — `Console.is_terminal` property: whether the console
  ## writes to a device capable of understanding escape sequences.
  if self.forceTerminalVal.isSome:
    return self.forceTerminalVal.get
  # Idle check (console.py:938-941) is Python-specific; skipped.
  if self.isJupyter:
    return false
  let ttyCompat = envGet(self, "TTY_COMPATIBLE").get("")
  if ttyCompat == "0":
    return false
  if ttyCompat == "1":
    return true
  let fc = envGet(self, "FORCE_COLOR")
  if fc.isSome:
    return fc.get != ""
  # `self.file.isatty()` (console.py:969-976) is not modelled (the placeholder
  # `FileHandle` has no `isatty`); a non-tty file defaults to `False`.
  return false

proc isDumbTerminal*(self: Console): bool =
  ## rich console.py:979-988 — `Console.is_dumb_terminal` property: detect a dumb
  ## terminal.
  let term = envGet(self, "TERM").get("").toLowerAscii()
  return self.isTerminal and (term == "dumb" or term == "unknown")

proc options*(self: Console): ConsoleOptions =
  ## rich console.py:991-1002 — `Console.options` property: get the default
  ## `ConsoleOptions` for this console.
  let sz = self.size
  result = initConsoleOptions(sz, self.legacyWindows, 1, sz.width,
                               self.isTerminal, self.encoding, sz.height)

proc size*(self: Console): ConsoleDimensions =
  ## rich console.py:1005-1043 — `Console.size` property: get the size as a
  ## `ConsoleDimensions` (width, height).
  let legacyInt = if self.legacyWindows: 1 else: 0
  if self.widthVal.isSome and self.heightVal.isSome:
    return (width: self.widthVal.get - legacyInt, height: self.heightVal.get)
  if self.isDumbTerminal:
    return (width: 80, height: 25)
  var w = 0
  var h = 0
  # `os.get_terminal_size(fd)` over the std streams (console.py:1018-1025) is
  # not ported (no portable Nim binding is wired this round); rely on
  # COLUMNS/LINES env or the 80×25 default.
  let cols = envGet(self, "COLUMNS")
  if cols.isSome and isDigitStr(cols.get): w = parseInt(cols.get)
  let lns = envGet(self, "LINES")
  if lns.isSome and isDigitStr(lns.get): h = parseInt(lns.get)
  if w == 0: w = 80
  if h == 0: h = 25
  let finalW = if self.widthVal.isSome: self.widthVal.get else: w - legacyInt
  let finalH = if self.heightVal.isSome: self.heightVal.get else: h
  return (width: finalW, height: finalH)

proc setSize*(self: Console, newSize: tuple[width: int, height: int]) =
  ## rich console.py:1046-1054 — `Console.size` setter (`@size.setter`
  ## console.py:1045): set a new size (`new_size: Tuple[int, int]` →
  ## `tuple[width: int, height: int]`).
  self.widthVal = some(newSize.width)
  self.heightVal = some(newSize.height)

proc width*(self: Console): int =
  ## rich console.py:1057-1063 — `Console.width` property: get the width (cells).
  return self.size.width

proc setWidth*(self: Console, width: int) =
  ## rich console.py:1066-1072 — `Console.width` setter: set the width. port
  ## stub.
  self.widthVal = some(width)

proc height*(self: Console): int =
  ## rich console.py:1075-1081 — `Console.height` property: get the height
  ## (lines).
  return self.size.height

proc setHeight*(self: Console, height: int) =
  ## rich console.py:1084-1090 — `Console.height` setter: set the height. port
  ## stub.
  self.heightVal = some(height)

proc bell*(self: Console) =
  ## rich console.py:1092-1094 — `Console.bell(self) -> None`: play a 'bell'
  ## (write the BEL control code).
  self.control(ctrl.bell())

proc capture*(self: Console): Capture =
  ## rich console.py:1096-1111 — `Console.capture(self) -> Capture`: return a
  ## `Capture` context manager that captures `print`/`log` output.
  result = initCapture(self)

proc pager*(self: Console, pager: Option[Pager] = none(Pager),
            styles: bool = false, links: bool = false): PagerContext =
  ## rich console.py:1113-1134 — `Console.pager(self, pager: Optional[Pager] =
  ## None, styles: bool = False, links: bool = False) -> PagerContext`: return a
  ## `PagerContext` that pages printed content through a pager. `pager:
  ## Optional[Pager]` → `Option[Pager]` (the provisional handle).
  result = initPagerContext(self, pager, styles, links)

proc line*(self: Console, count: int = 1) =
  ## rich console.py:1136-1144 — `Console.line(self, count: int = 1) -> None`:
  ## write `count` new lines. (Overload on the `Console` receiver; distinct from
  ## `richbase`'s param-less `Segment.line()`.) stub.
  assert count >= 0, "count must be >= 0"
  var objs: seq[RenderableValue] = @[]
  objs.add(initNewLine(count))
  self.print(objs)

proc clear*(self: Console, home: bool = true) =
  ## rich console.py:1146-1155 — `Console.clear(self, home: bool = True) ->
  ## None`: clear the screen (and move the cursor home if `home`).
  if home:
    self.control(ctrl.clear(), ctrl.home())
  else:
    self.control(ctrl.clear())

proc status*(self: Console, status: RenderableValue, spinner: string = "dots",
            spinnerStyle: StyleType = "status.spinner", speed: float = 1.0,
            refreshPerSecond: float = 12.5): Status =
  ## rich console.py:1157-1188 — `Console.status(self, status: RenderableType,
  ## *, spinner: str = "dots", spinner_style: StyleType = "status.spinner",
  ## speed: float = 1.0, refresh_per_second: float = 12.5) -> "Status"`: return a
  ## `Status` context manager. `status: RenderableType` (richbase, via
  ## `segment`); `spinner_style: StyleType = "status.spinner"` (the `string or
  ## Style` typeclass, default the `str`); `refresh_per_second`→`refreshPerSecond`.
  ## `status` is the name of both this proc and the imported module; only the
  ## uppercase `Status` type (the return) is read from the module, so they
  ## coexist.
  result = initStatus(status, self, spinnerName = spinner,
                      spinnerStyle = spinnerStyle, speed = speed,
                      refreshPerSecond = refreshPerSecond)

proc showCursor*(self: Console, show: bool = true): bool =
  ## rich console.py:1190-1199 — `Console.show_cursor(self, show: bool = True) ->
  ## bool`: show or hide the cursor; returns whether the control code was
  ## written.
  if self.isTerminal:
    self.control(ctrl.showCursor(show))
    return true
  return false

proc setAltScreen*(self: Console, enable: bool = true): bool =
  ## rich console.py:1201-1220 — `Console.set_alt_screen(self, enable: bool =
  ## True) -> bool`: enable/disable alternate screen; returns whether the
  ## control codes were written.
  var changed = false
  if self.isTerminal and not self.legacyWindows:
    self.control(ctrl.altScreen(enable))
    changed = true
    self.isAltScreenFlag = enable
  return changed

proc isAltScreen*(self: Console): bool =
  ## rich console.py:1223-1229 — `Console.is_alt_screen` property (`@property`
  ## console.py:1222): whether the alt screen was enabled.
  result = self.isAltScreenFlag

proc setWindowTitle*(self: Console, title: string): bool =
  ## rich console.py:1231-1261 — `Console.set_window_title(self, title: str) ->
  ## bool`: set the terminal window title; returns whether the control code was
  ## written.
  if self.isTerminal:
    self.control(ctrl.title(title))
    return true
  return false

proc screen*(self: Console, hideCursor: bool = true,
            style: StyleOpt = default(StyleOpt)): ScreenContext =
  ## rich console.py:1263-1275 — `Console.screen(self, hide_cursor: bool = True,
  ## style: Optional[StyleType] = None) -> "ScreenContext"`: return a
  ## `ScreenContext` enabling the alternate screen. `style: Optional[StyleType]`
  ## → `StyleOpt` (default `None` via `default(StyleOpt)`). `screen` is the name
  ## of both this proc and the imported module; only the uppercase `Screen` is
  ## read from the module (indirectly, via `ScreenContext.screen`'s field type).
  case style.kind
  of sokNone:
    result = initScreenContext(self, hideCursor, "")
  of sokStr:
    result = initScreenContext(self, hideCursor, style.strv)
  of sokStyle:
    result = initScreenContext(self, hideCursor, style.stv)

method measure*(self: Console, renderable: RenderableValue,
             options: Option[ConsoleOptions] = none(ConsoleOptions)): Measurement =
  ## rich console.py:1277-1292 — `Console.measure(self, renderable: RenderableType,
  ## *, options: Optional[ConsoleOptions] = None) -> Measurement`: measure a
  ## renderable. `renderable: RenderableType` → `RenderableValue`; `Measurement`
  ## from `measure.nim`. `measure` is the name of both this proc and the imported
  ## module; only the uppercase `Measurement` (the return) is read from the
  ## module.
  let opts = if options.isSome: options.get else: self.options
  case renderable.kind
  of rvString:
    return Measurement.get(self, opts, renderable.textStr)
  of rvConsoleRenderable:
    return Measurement(minimum: 0, maximum: opts.maxWidth)
  of rvRichCast:
    return Measurement(minimum: 0, maximum: opts.maxWidth)

proc dispatchRenderConsole(self: Console, item: RenderableBase,
                           opts: ConsoleOptions): RenderResult =
  ## [Nim-only helper] The runtime dispatch arm of `Console.render`
  ## (console.py:1310-1320): call the `renderConsole` virtual method on the
  ## `RenderableBase`. The `renderConsole` methods are declared on
  ## `RenderableBase` (richbase `{.base.}`) and overridden in each renderable
  ## module, so this is a single virtual call — NO `of`-table and NO per-type
  ## imports (breaks the console↔panel/import-cycle that ballooned the umbrella
  ## type-check). A subtype without an override (or a non-`RenderableBase`
  ## renderable like `Markdown`/`Emoji`/`Syntax` — `JupyterMixin`, not a
  ## `RenderableBase`) hits the base, which returns an empty result; rich would
  ## raise `NotRenderableError` for genuine non-renderables, but the
  ## `RenderableValue` kind check in `render` already gates the call.
  result = item.renderConsole(self, opts)

method render*(self: Console, renderable: RenderableValue,
            options: Option[ConsoleOptions] = none(ConsoleOptions)): RenderResult =
  ## rich console.py:1294-1343 — `Console.render(self, renderable: RenderableType,
  ## options: Optional[ConsoleOptions] = None) -> Iterable[Segment]`: render an
  ## object to an iterable of `Segment`s (the core render pipeline).
  ## `renderable: RenderableType` → `RenderableValue`; `Iterable[Segment]` →
  ## `RenderResult`. Faithful port via the port `addSegment*`/`addRenderable*`
  ## constructors (richbase "unfreeze") + the `dispatchRenderConsole`
  ## `of`-table above.
  let opts = if options.isSome: options.get else: self.options
  if opts.maxWidth < 1:
    # console.py:1301-1303 — no space to render anything (prevents recursion).
    return @[]
  # rich_cast + dispatch (console.py:1310-1320): get the raw `RenderResult` from
  # the renderable's `renderConsole` (or `render_str`→`Text.renderConsole` for a
  # bare `str`). `rvRichCast` is routed through the same `__rich_console__`
  # dispatch as a pragmatic fallback (the faithful `rich_cast`-first path needs
  # a runtime `richCast` dispatch table — the same gap as `renderConsole` — and
  # the `toRenderableValue` converter always tags a `RenderableBase` as
  # `rvConsoleRenderable`, so a true `rvRichCast` item is rare in practice).
  var raw: RenderResult
  case renderable.kind
  of rvString:
    let t = self.renderStr(renderable.textStr, highlight = opts.highlight,
                           markup = opts.markup)
    if t.isNil:
      return @[]
    raw = t.renderConsole(self, opts)
  of rvConsoleRenderable:
    raw = self.dispatchRenderConsole(renderable.consoleItem, opts)
  of rvRichCast:
    raw = self.dispatchRenderConsole(renderable.castItem, opts)
  # Flatten (console.py:1335-1343): `_options = _options.reset_height()`; for
  # each `render_output`: if `Segment` → yield; else `yield from self.render(...)`.
  # A Nim `RenderResult` is materialised, so non-`Segment` items are recursed
  # via `self.render` and their (already-flattened) items appended — the result
  # is all `Segment`s, like Python's generator which yields only `Segment`s.
  let opts2 = opts.resetHeight
  for it in raw:
    case it.kind
    of rrkSegment:
      result.addSegment(it.segmentItem)
    of rrkString:
      result.add(self.render(it.textStr, some(opts2)))
    of rrkConsoleRenderable:
      result.add(self.render(it.consoleItem, some(opts2)))
    of rrkRichCast:
      result.add(self.render(it.castItem, some(opts2)))

type
  Splitter* = ref object of RootObj
    ## [Nim-only helper] rich console.py:1320-1343 — splits a rendered stream
    ## into `seq[seq[Segment]]` at line feeds. In rich v15.0.0
    ## `Console.render_lines` calls `Segment.split_and_crop_lines` directly on
    ## the (already flat) rendered segments; here the line-split step is isolated
    ## as `Splitter.split` (delegating to `Segment.splitLinesTerminator`,
    ## segment.py:275-304) so `renderLines` composes it with `adjustLineLength`
    ## (crop/pad), `islice` (height) and pad-extra — faithfully mirroring
    ## `Segment.split_and_crop_lines` (segment.py:306-351). `Console.render`
    ## already recurses on non-`Segment` `RenderResult` items, so the splitter
    ## only ever sees terminal `Segment`s (exactly rich v15.0.0's path).

proc split*(self: Splitter, segments: openArray[Segment]):
     seq[tuple[line: seq[Segment], newLine: bool]] =
  ## Split a sequence of `Segment`s into lines paired with a terminator flag
  ## (the line-split half of `Segment.split_and_crop_lines`, segment.py:275-304).
  ## Delegates to `Segment.splitLinesTerminator` (the faithful classmethod):
  ## `newLine == true` marks a line that terminated with a line feed, so
  ## `renderLines` appends a `"\n"` segment only to terminated lines (matching
  ## `split_and_crop_lines`, which does not append `\n` to the final
  ## unterminated line).
  result = segment.splitLinesTerminator(segments)

method renderLines*(self: Console, renderable: RenderableValue,
                 options: Option[ConsoleOptions] = none(ConsoleOptions),
                 style: Option[Style] = none(Style), pad: bool = true,
                 newLines: bool = false): seq[seq[Segment]] =
  ## rich console.py:1345-1407 — `Console.render_lines(self, renderable:
  ## RenderableType, options: Optional[ConsoleOptions] = None, *, style:
  ## Optional[Style] = None, pad: bool = True, new_lines: bool = False) ->
  ## List[List[Segment]]`: render objects to a list of lines. `style:
  ## Optional[Style]` → `Option[Style]` (the `Style` ref); `new_lines`→`newLines`;
  ## `List[List[Segment]]` → `seq[seq[Segment]]`. Faithful port via `render` +
  ## `Splitter.split` + `Segment.adjustLineLength` + `islice`-by-height +
  ## pad-extra (mirrors `Segment.split_and_crop_lines`, console.py:1370-1395).
  let opts = if options.isSome: options.get else: self.options
  # `render(renderable, render_options)` → flat `RenderResult` (console.py:1372).
  let rendered = self.render(renderable, some(opts))
  # Flatten to `seq[Segment]` (`render` flattens → all `rrkSegment`).
  var segs: seq[Segment] = @[]
  for it in rendered:
    if it.kind == rrkSegment:
      segs.add(it.segmentItem)
  # `if style: _rendered = Segment.apply_style(_rendered, style)` (console.py:1373).
  let styleOpt = if style.isSome: some(style.get) else: none(Style)
  if styleOpt.isSome:
    segs = segment.applyStyle(segs, styleOpt)
  # Split into lines (Splitter) + crop/pad each via `adjustLineLength` + optional
  # `"\n"` (mirrors `split_and_crop_lines`, segment.py:308-351).
  let parts = Splitter().split(segs)
  var lines: seq[seq[Segment]] = @[]
  for p in parts:
    var cropped = segment.adjustLineLength(p.line, opts.maxWidth, style = styleOpt,
                                            pad = pad)
    if newLines and p.newLine:
      cropped.add(Segment(text: "\n"))
    lines.add(cropped)
  # `islice(..., None, render_height)` (console.py:1378-1383): clip to height.
  var renderHeight: Option[int] = opts.height
  if renderHeight.isSome:
    renderHeight = some(max(0, renderHeight.get))
  if renderHeight.isSome:
    let h = renderHeight.get
    if lines.len > h:
      lines.setLen(h)
  # Pad extra lines when `height` is set (console.py:1385-1395).
  if opts.height.isSome:
    let extra = opts.height.get - lines.len
    if extra > 0:
      let padStyle: Option[StyleRef] =
        if styleOpt.isSome: some(StyleRef(styleOpt.get)) else: none(StyleRef)
      let padSeg = Segment(text: repeat(" ", opts.maxWidth), style: padStyle)
      for _ in 0 ..< extra:
        var padLine: seq[Segment] = @[]
        padLine.add(padSeg)
        if newLines:
          padLine.add(Segment(text: "\n"))
        lines.add(padLine)
  result = lines

proc renderStr*(self: Console, text: string, style: StyleType = "",
               justify: Option[JustifyMethod] = none(JustifyMethod),
               overflow: Option[OverflowMethod] = none(OverflowMethod),
               emoji: Option[system.bool] = none(system.bool),
               markup: Option[system.bool] = none(system.bool),
               highlight: Option[system.bool] = none(system.bool),
               highlighter: Option[Highlighter] = none(Highlighter)): Text =
  ## rich console.py:1409-1468 — `Console.render_str(self, text: str, *, style:
  ## Union[str, Style] = "", justify: Optional[JustifyMethod] = None, overflow:
  ## Optional[OverflowMethod] = None, emoji: Optional[bool] = None, markup:
  ## Optional[bool] = None, highlight: Optional[bool] = None, highlighter:
  ## Optional[HighlighterType] = None) -> "Text"`: convert a string to a `Text`.
  ## `style: Union[str, Style] = ""` → `StyleType` (default the `str` `""`);
  ## `highlighter: Optional[HighlighterType] = None` → `Option[Highlighter] =
  ## none(Highlighter)`. Returns `Text`.
  let emojiEnabled = if emoji.isSome: emoji.get else: self.emojiFlag
  let markupEnabled = if markup.isSome: markup.get else: self.markupFlag
  let highlightEnabled =
    if highlight.isSome: highlight.get else: self.highlightFlag
  var richText: Text = nil
  if markupEnabled:
    richText = render(text, style = style, emoji = emojiEnabled,
                      emojiVariant = self.emojiVariant)
  else:
    # rich console.py:1451-1453 — `_emoji_replace(text, default_variant=
    # self._emoji_variant)` when `emoji_enabled` (the markup-disabled arm builds
    # a `Text` from the emoji-substituted string). `emojiReplaceForConsole`
    # dispatches the ported `emoji.emojiReplace` at module scope (the `emoji`
    # module is shadowed by `renderStr`'s `emoji` param here).
    let body = if emojiEnabled: emojiReplaceForConsole(text, self.emojiVariant)
               else: text
    richText = initText(body, style = style, justify = justify,
                        overflow = overflow)
  if not richText.isNil:
    richText.justify = justify
    richText.overflow = overflow
  let hl: Highlighter =
    if highlightEnabled:
      (if highlighter.isSome: highlighter.get else: self.highlighterField)
    else:
      nil
  if not hl.isNil and not richText.isNil:
    # Faithful to rich's `_highlighter(str(rich_text))` (console.py:1462): pass
    # the plain text so the highlighter builds a fresh `Text` (highlight spans
    # only); `richText`'s markup spans are then appended once by `copyStyles`,
    # matching Python — passing the `Text` directly would duplicate them.
    let highlightText = hl.call($richText)
    if not highlightText.isNil:
      highlightText.copyStyles(richText)
      return highlightText
  return richText

method renderStrValue*(self: Console, text: string,
    style: StyleOpt = default(StyleOpt),
    emoji: Option[system.bool] = none(system.bool),
    markup: Option[system.bool] = none(system.bool),
    highlight: Option[system.bool] = none(system.bool)): RenderableValue =
  ## rich console.py:1409-1468 — `Console.render_str` wrapped as a
  ## `RenderableValue` for the `console_api` dispatch (Table title/caption
  ## string arms, table.py:501). Delegates to the existing `renderStr` proc
  ## (markup/emoji/theme-style/highlight resolution) and wraps the resulting
  ## `Text` as `rvConsoleRenderable` so `console_api.render` dispatches it
  ## through the genuine `Text.renderConsole`; a `nil` Text falls back to a
  ## bare `rvString` (which `render`'s rvString arm re-runs `render_str` on).
  ## The `style: StyleOpt` handle dispatches to `renderStr`'s `StyleType`
  ## (str|Style) param: `sokStr`->`strv`, `sokStyle`->`stv`, `sokNone`->`""`
  ## (Rich's `render_str` default `style=""`). `emoji`/`markup`/`highlight`
  ## mirror `render_str`'s `Optional[bool]` flags (`None` => Console default);
  ## the Table call passes `highlight=some(false)` (table.py:501) and leaves
  ## `emoji`/`markup` as `None` (Console default), exactly like Rich.
  var t: Text = nil
  case style.kind
  of sokStr:
    t = self.renderStr(text, style = style.strv, emoji = emoji,
                       markup = markup, highlight = highlight)
  of sokStyle:
    t = self.renderStr(text, style = style.stv, emoji = emoji,
                       markup = markup, highlight = highlight)
  else:
    t = self.renderStr(text, emoji = emoji, markup = markup,
                       highlight = highlight)
  if t.isNil:
    result = RenderableValue(kind: rvString, textStr: text)
  else:
    result = RenderableValue(kind: rvConsoleRenderable, consoleItem: t)

method getStyle*(self: Console, name: StyleType,
              default: StyleOpt = default(StyleOpt)): Style =
  ## rich console.py:1470-1498 — `Console.get_style(self, name: Union[str,
  ## Style], *, default: Optional[Union[Style, str]] = None) -> Style`: get a
  ## `Style` by theme name or parse a definition. `name: StyleType`; `default:
  ## Optional[Union[Style, str]]` → `StyleOpt`. Returns `Style`.
  when name is Style:
    result = name
  else:
    var s: Style = nil
    let found = self.themeStack.get(name)
    if found.isSome:
      s = found.get
    else:
      try:
        s = Style.parse(name)
      except errors.StyleSyntaxError:
        if default.kind == sokStr:
          result = self.getStyle(default.strv)
          return
        elif default.kind == sokStyle:
          result = self.getStyle(default.stv)
          return
        else:
          raise newException(errors.MissingStyle,
            "Failed to get style " & name)
    if not s.isNil and s.link.isSome:
      result = s.copy()
    else:
      result = s

method getSafeBox*(self: Console): bool =
  ## rich console.py:743 — `self.safe_box` (`bool`); the real Console preference
  ## consumed by `Table._render` (table.py:769) via
  ## `pick_bool(self.safe_box, console.safe_box)`, so an explicit Table
  ## `safe_box` takes precedence and otherwise this real Console value decides
  ## box substitution. Overrides the `console_api` base (default `true`).
  result = self.safeBox

method getTabSize*(self: Console): int =
  ## rich console.py:633 — `self.tab_size` (`int`); the real Console tab size
  ## consumed by `Text.__rich_console__` (text.py:692 —
  ## `console.tab_size if self.tab_size is None else self.tab_size`), so an
  ## unset `Text.tab_size` inherits the real Console value while an explicit
  ## Text value wins. Overrides the `console_api` base (default `8`).
  result = self.tabSize

proc flattenRenderResult(rr: RenderResult): seq[Segment] =
  ## [Nim-only helper] Flatten a `RenderResult` (console.py:1294) to a flat
  ## `seq[Segment]`, keeping only the terminal `Segment` items (`rrkSegment`).
  ## Non-segment items (bare strings / renderables for recursive rendering) are
  ## dropped — the blocked render pipeline (`RenderResultItem` in richbase has
  ## no public constructor) means `Console.render` returns an empty
  ## `RenderResult` anyway, so this is a no-op pass-through until the
  ## constructor lands; it is wired now so `print`/`update_screen_lines` are
  ## type-correct against the real `RenderResult`.
  for it in rr:
    if it.kind == rrkSegment:
      result.add(it.segmentItem)

proc collectRenderables(self: Console, objects: openArray[RenderableValue],
                        sep: string, endStr: string,
                        justify: Option[JustifyMethod],
                        emoji: Option[system.bool], markup: Option[system.bool],
                        highlight: Option[system.bool]): seq[RenderableBase] =
  ## rich console.py:1500-1587 — `Console._collect_renderables(self, objects,
  ## sep, end, *, justify, emoji, markup, highlight) -> List[
  ## ConsoleRenderable]`: combine renderables and text into one list. Modelled
  ## as a free helper (a `self`-proc would require a frozen-signature change);
  ## the body mirrors Python: per-object dispatch (str→`render_str` into the
  ## text buffer, `Text`→text buffer, else→append), `check_text` joins the
  ## buffered `Text`s with a `Text(sep, justify, end)` separator. The
  ## `_highlighter` is `self.highlighter` when highlight-enabled (else
  ## `NullHighlighter`), passed to `render_str`. `Styled` (self.style), `Align`
  ## (justify) and `Pretty` (is_expandable) wrapping is DEFERRED — those modules
  ## are not ported this round; `self.style` is applied via `getStyle` in
  ## `print` instead, and `justify` is applied via `options.update`.
  var renderables: seq[RenderableBase] = @[]
  var textSeq: seq[Text] = @[]
  let hlEnabled = if highlight.isSome: highlight.get else: self.highlightFlag
  let hl: Highlighter =
    if hlEnabled: self.highlighterField
    else: highlighter.NullHighlighter()
  let hlOpt = if hl.isNil: none(Highlighter) else: some(hl)
  proc checkText(rens: var seq[RenderableBase], txts: var seq[Text],
                 sepv: string, justifyv: Option[JustifyMethod], endv: string) =
    if txts.len > 0:
      let sepText = initText(sepv, justify = justifyv, `end` = endv)
      rens.add(sepText.join(txts))
      txts.setLen(0)
  for o in objects:
    case o.kind
    of rvString:
      textSeq.add(self.renderStr(o.textStr, emoji = emoji, markup = markup,
                                 highlight = highlight, highlighter = hlOpt))
    of rvConsoleRenderable:
      let item = o.consoleItem
      if item of Text:
        textSeq.add(Text(item))
      else:
        checkText(renderables, textSeq, sep, justify, endStr)
        renderables.add(item)
    of rvRichCast:
      # DEFERRED(rvRichCast): the `toRenderableValue` converter always produces
      # `rvConsoleRenderable` for a `RenderableBase`, so this arm is dead;
      # treat the cast item as a console renderable (no `rich_cast`) for safety.
      checkText(renderables, textSeq, sep, justify, endStr)
      renderables.add(o.castItem)
  checkText(renderables, textSeq, sep, justify, endStr)
  # DEFERRED(rich.styled.Styled): when `self.style.kind != sokNone` Python wraps
  # every renderable in `Styled(renderable, get_style(self.style))`; rich.styled
  # is not ported, so the wrapping is deferred (self.style is applied via
  # getStyle in print() instead).
  result = renderables

proc rule*(self: Console, title: TextType = "", characters: string = "\u2500",
          style: StyleType = "rule.line", align: AlignMethod = amCenter) =
  ## rich console.py:1589-1608 — `Console.rule(self, title: TextType = '', *,
  ## characters: str = '─', style: Union[str, Style] = 'rule.line', align:
  ## AlignMethod = 'center') -> None`: draw a line with optional centered title.
  ## `title: TextType = ""` (string or Text); `characters` defaults to `"─"`
  ## (U+2500, written `"\u2500"`); `style: StyleType = "rule.line"`; `align:
  ## AlignMethod = amCenter` (the hosted `AlignMethod` from `text.nim`). port
  ## stub.
  let r = initRule(title = title, characters = characters, style = style,
                  align = align)
  var objs: seq[RenderableValue] = @[]
  objs.add(r)
  self.print(objs)

proc control*(self: Console, control: varargs[Control]) =
  ## rich console.py:1610-1618 — `Console.control(self, *control: Control) ->
  ## None`: insert non-printing control codes. Python's `*control: Control`
  ## varargs → `varargs[Control]` (each arg a `Control` instance). `control` is
  ## the name of both this proc, its param, and the imported module; only the
  ## uppercase `Control` type is read from the module, so they coexist. port
  ## stub.
  if not self.isDumbTerminal:
    discard self.enter()
    try:
      for c in control:
        self.threadLocals.buffer.add(c.segment)
    finally:
      self.exit(none(RootRef), none(ref CatchableError), none(RootRef))

proc `out`*(self: Console, objects: openArray[RenderableValue], sep: string = " ",
           `end`: string = "\n", style: StyleOpt = default(StyleOpt),
           highlight: Option[system.bool] = none(system.bool)) =
  ## rich console.py:1620-1650 — `Console.out(self, *objects: Any, sep: str =
  ## ' ', end: str = '\n', style: Optional[Union[str, Style]] = None, highlight:
  ## Optional[bool] = None) -> None`: low-level terminal output (no pretty-print /
  ## wrap / markup). `out` is a Nim keyword → backtick-quoted `` `out`* ``;
  ## `*objects: Any` → `openArray[RenderableValue]` (varargs must be last, but
  ## keyword params follow — `openArray` translation); `end` backtick-quoted;
  ## `style: Optional[Union[str,Style]]` → `StyleOpt`.
  var parts: seq[string] = @[]
  for o in objects:
    case o.kind
    of rvString:
      parts.add(o.textStr)
    of rvConsoleRenderable:
      let item = o.consoleItem
      if item of Text: parts.add($(Text(item)))
      else: parts.add("")  # DEFERRED(rich_cast/str for non-Text renderables)
    of rvRichCast:
      parts.add("")
  let rawOutput = parts.join(sep)
  var objs: seq[RenderableValue] = @[]
  objs.add(rawOutput)
  self.print(objs, style = style, highlight = highlight, emoji = some(false),
             markup = some(false), noWrap = some(true), overflow = some(omIgnore),
             crop = false, `end` = `end`)

proc print*(self: Console, objects: openArray[RenderableValue], sep: string = " ",
           `end`: string = "\n", style: StyleOpt = default(StyleOpt),
           justify: Option[JustifyMethod] = none(JustifyMethod),
           overflow: Option[OverflowMethod] = none(OverflowMethod),
           noWrap: Option[system.bool] = none(system.bool), emoji: Option[system.bool] = none(system.bool),
           markup: Option[system.bool] = none(system.bool), highlight: Option[system.bool] = none(system.bool),
           width: Option[int] = none(int), crop: bool = true,
           softWrap: Option[system.bool] = none(system.bool), newLineStart: bool = false) =
  ## rich console.py:1652-1756 — `Console.print(self, *objects: Any, sep = ' ',
  ## end = '\n', style = None, justify = None, overflow = None, no_wrap = None,
  ## emoji = None, markup = None, highlight = None, width = None, crop = True,
  ## soft_wrap = None, new_line_start = False) -> None`: print to the console.
  ## `*objects: Any` → `openArray[RenderableValue]`; `style: Optional[Union[str,
  ## Style]]` → `StyleOpt`; `end` backtick-quoted; `no_wrap`→`noWrap`,
  ## `new_line_start`→`newLineStart`.
  var objs: seq[RenderableValue] = @[]
  if objects.len == 0:
    if `end` == "\n":
      objs.add(initNewLine())
    else:
      objs.add("")
  else:
    for o in objects: objs.add(o)
  var sw = softWrap
  var nw = noWrap
  var ov = overflow
  var cr = crop
  if sw.isNone: sw = some(self.softWrap)
  if sw.isSome and sw.get:
    if nw.isNone: nw = some(true)
    if ov.isNone: ov = some(omIgnore)
    cr = false
  discard self.enter()
  try:
    let renderables = collectRenderables(self, objs, sep, `end`, justify, emoji,
                                         markup, highlight)
    # DEFERRED(rich.RenderHook.process_renderables): the abstract base is a
    # no-op; subclass hooks are not ported. The base would replace renderables
    # with the empty default, so hooks are skipped to preserve renderables.
    let renderOptions = self.options.update(
      justify = setChange(justify),
      overflow = setChange(ov),
      width = if width.isSome: setChange(min(width.get, self.width)) else: noChange[int](),
      no_wrap = setChange(nw),
      markup = setChange(markup),
      highlight = setChange(highlight))
    var newSegments: seq[Segment] = @[]
    if style.kind == sokNone:
      for renderable in renderables:
        newSegments.add(flattenRenderResult(self.render(renderable, some(renderOptions))))
    else:
      let renderStyle: Style =
        if style.kind == sokStr: self.getStyle(style.strv)
        else: self.getStyle(style.stv)
      let newLine = Segment(text: "\n")
      for renderable in renderables:
        for pair in segment.splitLinesTerminator(
            flattenRenderResult(self.render(renderable, some(renderOptions)))):
          newSegments.add(segment.applyStyle(pair.line, some(renderStyle)))
          if pair.newLine: newSegments.add(newLine)
    if newLineStart:
      var joined = ""
      for seg in newSegments: joined.add(seg.text)
      if joined.splitLines().len > 1:
        newSegments.insert(Segment(text: "\n"), 0)
    if cr:
      for line in segment.splitAndCropLines(newSegments, self.width, pad = false):
        self.threadLocals.buffer.add(line)
    else:
      self.threadLocals.buffer.add(newSegments)
  finally:
    self.exit(none(RootRef), none(ref CatchableError), none(RootRef))

proc printJson*(self: Console, json: Option[string] = none(string),
               data: Option[JsonNode] = none(JsonNode), indent: Option[int] = some(2),
               highlight: bool = true, skipKeys: bool = false,
               ensureAscii: bool = false, checkCircular: bool = true,
               allowNan: bool = true,
               defaultCallable: Option[JsonDefaultCallable] = none(JsonDefaultCallable),
               sortKeys: bool = false) =
  ## rich console.py:1758-1817 — `Console.print_json(self, json: Optional[str] =
  ## None, *, data: Any = None, indent: Union[None, int, str] = 2, highlight:
  ## bool = True, skip_keys = False, ensure_ascii = False, check_circular = True,
  ## allow_nan = True, default: Optional[Callable[[Any], Any]] = None,
  ## sort_keys = False) -> None`: pretty-print JSON. `json: Optional[str]` →
  ## `Option[string]`; `data: Any` → `Option[JsonNode]` (the `Any` handle);
  ## `indent: Union[None, int, str] = 2` → `Option[int] = some(2)` (the `str`/`None`
  ## arms are a body refinement); `default`→`defaultCallable` (`Option[
  ## JsonDefaultCallable]`). `json` is the name of both this param and the
  ## imported `std/json` module; only `JsonNode` is read from the module (the
  ## param shadows the module within this proc, whose body is `discard`). port
  ## stub.
  let jsonIndent =
    if indent.isSome: JsonIndent(kind: jiInt, spaces: indent.get)
    else: JsonIndent(kind: jiNone)
  var jsonRenderable: richjson.Json
  if json.isNone:
    let dataNode = if data.isSome: data.get else: newJNull()
    jsonRenderable = Json.fromData(dataNode, indent = jsonIndent,
                                  highlight = highlight, skipKeys = skipKeys,
                                  ensureAscii = ensureAscii,
                                  checkCircular = checkCircular,
                                  allowNan = allowNan,
                                  `default` = defaultCallable, sortKeys = sortKeys)
  else:
    jsonRenderable = initJson(json.get, indent = jsonIndent, highlight = highlight,
                              skipKeys = skipKeys, ensureAscii = ensureAscii,
                              checkCircular = checkCircular, allowNan = allowNan,
                              `default` = defaultCallable, sortKeys = sortKeys)
  var objs: seq[RenderableValue] = @[]
  objs.add(jsonRenderable.richCast())
  self.print(objs, softWrap = some(true))

proc updateScreen*(self: Console, renderable: RenderableValue,
                  region: Option[Region] = none(Region),
                  options: Option[ConsoleOptions] = none(ConsoleOptions)) =
  ## rich console.py:1819-1851 — `Console.update_screen(self, renderable:
  ## RenderableType, *, region: Optional[Region] = None, options:
  ## Optional[ConsoleOptions] = None) -> None`: update the screen at a given
  ## region. `renderable: RenderableType` → `RenderableValue`; `region:
  ## Optional[Region]` → `Option[Region]` (the `Region` tuple).
  if not self.isAltScreen:
    raise newException(errors.NoAltScreen,
      "Alt screen must be enabled to call update_screen")
  var renderOptions = if options.isSome: options.get else: self.options
  var x = 0
  var y = 0
  if region.isNone:
    x = 0
    y = 0
    let h = if renderOptions.height.isSome: renderOptions.height.get else: self.height
    renderOptions = renderOptions.updateDimensions(renderOptions.maxWidth, h)
  else:
    let r = region.get
    x = r.x
    y = r.y
    renderOptions = renderOptions.updateDimensions(r.width, r.height)
  let lines = self.renderLines(renderable, options = some(renderOptions))
  self.updateScreenLines(lines, x, y)

proc updateScreenLines*(self: Console, lines: seq[seq[Segment]],
                       x: int = 0, y: int = 0) =
  ## rich console.py:1853-1871 — `Console.update_screen_lines(self, lines:
  ## List[List[Segment]], x: int = 0, y: int = 0) -> None`: update lines of the
  ## screen at a given offset.
  if not self.isAltScreen:
    raise newException(errors.NoAltScreen,
      "Alt screen must be enabled to call update_screen")
  let screenUpdate = initScreenUpdate(lines, x, y)
  let segs = self.render(screenUpdate)
  self.threadLocals.buffer.add(flattenRenderResult(segs))
  self.checkBuffer()

proc printException*(self: Console, width: Option[int] = some(100),
                    extraLines: int = 3, theme: Option[string] = none(string),
                    wordWrap: bool = false, showLocals: bool = false,
                    suppress: openArray[string] = @[], maxFrames: int = 100) =
  ## rich console.py:1873-1906 — `Console.print_exception(self, *, width:
  ## Optional[int] = 100, extra_lines: int = 3, theme: Optional[str] = None,
  ## word_wrap: bool = False, show_locals: bool = False, suppress:
  ## Iterable[Union[str, ModuleType]] = (), max_frames: int = 100) -> None`:
  ## print a rich render of the last exception. `width` → `some(100)`; `theme` →
  ## `Option[string]`; `suppress: Iterable[Union[str, ModuleType]]` →
  ## `openArray[string]` (narrowed to the `str` arm; the `ModuleType` arm is a
  ## body refinement), default `@[]`.
  let tb = initTraceback(width = width, extraLines = extraLines, theme = theme,
                         wordWrap = wordWrap, showLocals = showLocals,
                         suppress = suppress, maxFrames = maxFrames)
  var objs: seq[RenderableValue] = @[]
  objs.add(tb)
  self.print(objs)

proc callerFrameInfo*(offset: int, currentframe: Option[CallerFrameCallable] =
                    none(CallerFrameCallable)):
    tuple[file: string, line: int, locals: Table[string, JsonNode]] =
  ## rich console.py:1909-1945 — `Console._caller_frame_info(offset: int,
  ## currentframe: Optional[Callable[[], Optional[FrameType]]] = None) ->
  ## Tuple[str, int, Dict[str, Any]]` (`@staticmethod`, console.py:1908): get
  ## caller frame information. Modelled as a free proc (no `self`), faithful to
  ## the `@staticmethod` (and to how `richbase` models `Segment.line` as a
  ## classmethod-free-proc). `currentframe` → `Option[CallerFrameCallable]`;
  ## `Dict[str, Any]` → `Table[string, JsonNode]` (the `Any` handle). port
  ## stub.
  # DEFERRED(frame introspection): Nim has no portable runtime frame
  # introspection (no `f_back`/`f_locals`/`co_filename`), and the
  # `CallerFrameCallable` placeholder returns no usable frame. Return the
  # default (empty file, line 0, empty locals) so callers (Console.log) degrade
  # gracefully; the real `_caller_frame_info` is a Phase N refinement pending a
  # frame-introspection binding.
  result = (file: "", line: 0, locals: initTable[string, JsonNode]())

proc log*(self: Console, objects: openArray[RenderableValue], sep: string = " ",
         `end`: string = "\n", style: StyleOpt = default(StyleOpt),
         justify: Option[JustifyMethod] = none(JustifyMethod),
         emoji: Option[system.bool] = none(system.bool), markup: Option[system.bool] = none(system.bool),
         highlight: Option[system.bool] = none(system.bool), logLocals: bool = false,
         stackOffset: int = 1) =
  ## rich console.py:1947-2028 — `Console.log(self, *objects: Any, sep = ' ',
  ## end = '\n', style = None, justify = None, emoji = None, markup = None,
  ## highlight = None, log_locals = False, _stack_offset = 1) -> None`: log
  ## rich content. `*objects: Any` → `openArray[RenderableValue]`; `style` →
  ## `StyleOpt`; `log_locals`→`logLocals`; `_stack_offset`→`stackOffset`. Phase
  ## 0 stub.
  # DEFERRED(rich._log_render.LogRender.__call__, rich.styled.Styled,
  # rich.scope.render_scope, callerFrameInfo frame introspection): the log line
  # (timestamp/level/path) requires `LogRender.__call__` (logRender is a
  # placeholder with no call method), `Styled`/`Align` wrapping needs rich.styled
  # (not ported), `render_scope` needs rich.scope (not ported), and
  # `callerFrameInfo` cannot introspect frames. Best-effort: emit the objects
  # via self.print (no timestamp/level/path) so log() is not silent; the rich
  # log formatting is a Phase N refinement.
  var objs: seq[RenderableValue] = @[]
  if objects.len == 0:
    objs.add(initNewLine())
  else:
    for o in objects: objs.add(o)
  self.print(objs, sep = sep, `end` = `end`, style = style, justify = justify,
             emoji = emoji, markup = markup, highlight = highlight)

proc onBrokenPipe*(self: Console) =
  ## rich console.py:2030-2042 — `Console.on_broken_pipe(self) -> None`: called
  ## when a `BrokenPipeError` is raised (default exits the app).
  self.quiet = true
  # DEFERRED(os.open devnull + os.dup2): redirecting stdout to /dev/null (the
  # Python path avoids further BrokenPipeError on shutdown) needs std/os file-
  # descriptor ops, deferred this round. `raise SystemExit(1)` → `quit(1)`.
  quit(1)

proc checkBuffer*(self: Console) =
  ## rich console.py:2044-2057 — `Console._check_buffer(self) -> None`: check if
  ## the buffer may be rendered and render it if so (also recording if enabled).
  if self.quiet:
    self.threadLocals.buffer.setLen(0)
    return
  try:
    self.writeBuffer()
  except IOError:
    self.onBrokenPipe()

proc writeBuffer*(self: Console) =
  ## rich console.py:2059-2130 — `Console._write_buffer(self) -> None`: write the
  ## buffer to the output file. Body needs `jupyter.display` + the
  ## Windows renderer (console.py:2069,2084-2085).
  if self.record and self.threadLocals.bufferIndex == 0:
    self.recordBuffer.add(self.threadLocals.buffer)
  if self.threadLocals.bufferIndex == 0:
    if self.isJupyter:
      # DEFERRED(rich.jupyter.display): the Jupyter display path is not wired.
      self.threadLocals.buffer.setLen(0)
    else:
      let text = self.renderBuffer(self.threadLocals.buffer)
      if self.fileVal.isNone:
        # rich writes to `self.file` (stdout or stderr per `self.stderr`) and
        # flushes that same stream (console.py:2127); flush the stream actually
        # written so a `stderr=True` Console flushes stderr, not stdout.
        if self.stderr:
          stderr.write(text)
          try: stderr.flushFile() except IOError: discard
        else:
          stdout.write(text)
          try: stdout.flushFile() except IOError: discard
      else:
        # DEFERRED(FileHandle.write): the provisional FileHandle has no write
        # method; writing to a custom file is deferred (output dropped this round).
        discard
      self.threadLocals.buffer.setLen(0)

proc renderBuffer*(self: Console, buffer: openArray[Segment]): string =
  ## rich console.py:2132-2154 — `Console._render_buffer(self, buffer:
  ## Iterable[Segment]) -> str`: render buffered output and clear the buffer.
  ## `Iterable[Segment]` → `openArray[Segment]`; returns the rendered string.
  var buf: seq[Segment]
  if self.noColor and self.colorSystemVal.isSome:
    buf = segment.removeColor(buffer)
  else:
    for seg in buffer: buf.add(seg)
  var output: seq[string] = @[]
  let notTerminal = not self.isTerminal
  for seg in buf:
    if seg.style.isSome:
      let st = Style(seg.style.get)
      output.add(st.render(seg.text, colorSystem = self.colorSystemVal,
                           legacyWindows = self.legacyWindows))
    elif not (notTerminal and seg.control.isSome and seg.control.get.len > 0):
      output.add(seg.text)
  result = output.join("")

proc input*(self: Console, prompt: TextType = "", markup: bool = true,
          emoji: bool = true, password: bool = false,
          stream: Option[FileHandle] = none(FileHandle)): string =
  ## rich console.py:2156-2190 — `Console.input(self, prompt: TextType = '', *,
  ## markup: bool = True, emoji: bool = True, password: bool = False, stream:
  ## Optional[TextIO] = None) -> str`: display a prompt and wait for input.
  ## `prompt: TextType = ""` (string or Text); `stream: Optional[TextIO]` →
  ## `Option[FileHandle]`. Returns the input string.
  when prompt is string:
    let hasPrompt = prompt != ""
  else:
    let hasPrompt = not prompt.isNil
  if hasPrompt:
    var objs: seq[RenderableValue] = @[]
    objs.add(prompt)
    self.print(objs, `end` = "", markup = some(markup), emoji = some(emoji))
  if password:
    # DEFERRED(getpass echo-hiding): portable password echo-hiding needs
    # std/terminal (readPasswordFromStdin), deferred to avoid the import change
    # and non-TTY runtime concerns; the password is read via stdin.readLine
    # (echo NOT hidden this round).
    result = stdin.readLine()
  else:
    if stream.isSome:
      # DEFERRED(FileHandle.readline): the provisional FileHandle has no
      # readline; fall back to stdin.
      result = stdin.readLine()
    else:
      result = stdin.readLine()

proc exportText*(self: Console, clear: bool = true, styles: bool = false): string =
  ## rich console.py:2192-2222 — `Console.export_text(self, *, clear: bool =
  ## True, styles: bool = False) -> str`: generate text from console contents
  ## (requires `record=True`).
  assert self.record, "To export console contents set record=True in the constructor or instance"
  if styles:
    var t = ""
    for seg in self.recordBuffer:
      if seg.style.isSome:
        let st = Style(seg.style.get)
        t.add(st.render(seg.text))
      else:
        t.add(seg.text)
    result = t
  else:
    var t = ""
    for seg in self.recordBuffer:
      if seg.control.isNone:
        t.add(seg.text)
    result = t
  if clear:
    self.recordBuffer.setLen(0)

proc saveText*(self: Console, path: string, clear: bool = true,
             styles: bool = false) =
  ## rich console.py:2224-2242 — `Console.save_text(self, path: Union[str,
  ## PathLike[str]], *, clear: bool = True, styles: bool = False) -> None`:
  ## generate text and save to `path`. `path` → `string`.
  let text = self.exportText(clear = clear, styles = styles)
  writeFile(path, text)

proc exportHtml*(self: Console, theme: Option[TerminalTheme] = none(TerminalTheme),
               clear: bool = true, codeFormat: Option[string] = none(string),
               inlineStyles: bool = false): string =
  ## rich console.py:2244-2319 — `Console.export_html(self, *, theme:
  ## Optional[TerminalTheme] = None, clear: bool = True, code_format:
  ## Optional[str] = None, inline_styles: bool = False) -> str`: generate HTML
  ## from console contents. `theme: Optional[TerminalTheme]` →
  ## `Option[TerminalTheme]`; `code_format: Optional[str] = None` →
  ## `Option[string]`; `inline_styles`→`inlineStyles`.
  assert self.record, "To export console contents set record=True in the constructor or instance"
  let themeVal = if theme.isSome: theme.get else: DEFAULT_TERMINAL_THEME
  let renderCodeFormat = if codeFormat.isSome: codeFormat.get else: CONSOLE_HTML_FORMAT
  var fragments: seq[string] = @[]
  var stylesheet = ""
  let simplified = segment.simplify(self.recordBuffer)
  let filtered = segment.filterControl(simplified)
  if inlineStyles:
    for seg in filtered:
      var t = htmlEscape(seg.text)
      if seg.style.isSome:
        let st = Style(seg.style.get)
        let rule = st.getHtmlStyle()  # `theme` inert in port (style.nim placeholder TerminalTheme; lookups deferred) — arg omitted to match the declared placeholder type.
        if st.link.isSome and st.link.get.len > 0:
          t = "<a href=\"" & st.link.get & "\">" & t & "</a>"
        if rule.len > 0:
          t = "<span style=\"" & rule & "\">" & t & "</span>"
      fragments.add(t)
  else:
    var styles = initTable[string, int]()
    for seg in filtered:
      var t = htmlEscape(seg.text)
      if seg.style.isSome:
        let st = Style(seg.style.get)
        let rule = st.getHtmlStyle()
        var sn: int
        if styles.hasKey(rule): sn = styles[rule]
        else:
          sn = styles.len + 1
          styles[rule] = sn
        if st.link.isSome and st.link.get.len > 0:
          t = "<a class=\"r" & $sn & "\" href=\"" & st.link.get & "\">" & t & "</a>"
        else:
          t = "<span class=\"r" & $sn & "\">" & t & "</span>"
      fragments.add(t)
    var rulesList: seq[string] = @[]
    for rule, sn in styles.pairs:
      if rule.len > 0: rulesList.add(".r" & $sn & " {" & rule & "}")
    stylesheet = rulesList.join("\n")
  var subs = initTable[string, string]()
  subs["code"] = fragments.join("")
  subs["stylesheet"] = stylesheet
  subs["foreground"] = themeVal.foregroundColor.hex
  subs["background"] = themeVal.backgroundColor.hex
  result = pyFormat(renderCodeFormat, subs)
  if clear: self.recordBuffer.setLen(0)

proc saveHtml*(self: Console, path: string,
             theme: Option[TerminalTheme] = none(TerminalTheme),
             clear: bool = true, codeFormat: string = CONSOLE_HTML_FORMAT,
             inlineStyles: bool = false) =
  ## rich console.py:2321-2350 — `Console.save_html(self, path, *, theme = None,
  ## clear = True, code_format: str = CONSOLE_HTML_FORMAT, inline_styles =
  ## False) -> None`: generate HTML and save to `path`. `code_format: str =
  ## CONSOLE_HTML_FORMAT` → `string = CONSOLE_HTML_FORMAT` (the provisional
  ## const).
  let html = self.exportHtml(theme = theme, clear = clear,
                             codeFormat = some(codeFormat), inlineStyles = inlineStyles)
  writeFile(path, html)

proc getSvgStyle(themeVal: TerminalTheme, style: Style): string =
  ## rich console.py:2391-2415 — the SVG `get_svg_style` closure (inlined as a
  ## module helper to avoid closure capture): convert a `Style` to CSS rules for
  ## SVG (`fill`/`font-weight`/`font-style`/`text-decoration`). The Python
  ## `style_cache` (`Dict[Style, str]`) is DEFERRED — value-based caching needs
  ## Style value-equality (Nim's ref `==` would miss every fresh `Style()`),
  ## so the CSS is recomputed each call (output identical, slower).
  var cssRules: seq[string] = @[]
  var fgColor = if style.color.isNone or style.color.get.isDefault: themeVal.foregroundColor
                else: style.color.get.getTruecolor()
  var bgColor = if style.bgcolor.isNone or style.bgcolor.get.isDefault: themeVal.backgroundColor
                else: style.bgcolor.get.getTruecolor()
  if style.reverse.isSome and style.reverse.get: swap(fgColor, bgColor)
  if style.dim.isSome and style.dim.get: fgColor = color.blendRgb(fgColor, bgColor, 0.4)
  cssRules.add("fill: " & fgColor.hex)
  if style.bold.isSome and style.bold.get: cssRules.add("font-weight: bold")
  if style.italic.isSome and style.italic.get: cssRules.add("font-style: italic;")
  if style.underline.isSome and style.underline.get: cssRules.add("text-decoration: underline;")
  if style.strike.isSome and style.strike.get: cssRules.add("text-decoration: line-through;")
  result = cssRules.join(";")

proc escapeSvgText(text: string): string =
  ## rich console.py:2427-2429 — the SVG `escape_text`: HTML-escape and replace
  ## spaces with `&#160;` (non-breaking space).
  result = htmlEscape(text).replace(" ", "&#160;")

proc makeSvgTag(name: string, content: Option[string], attribs: string): string =
  ## rich console.py:2431-2448 — the SVG `make_tag`: build `<name attribs>content
  ## </name>` (content truthy) or `<name attribs/>` (content None/empty). The
  ## Python `**attribs` kwargs are pre-serialised into `attribs` by the caller
  ## (Nim has no kwargs); float values are `gFormat`-formatted by the caller.
  if content.isSome and content.get.len > 0:
    "<" & name & " " & attribs & ">" & content.get & "</" & name & ">"
  else:
    "<" & name & " " & attribs & "/>"

proc exportSvg*(self: Console, title: string = "Rich",
              theme: Option[TerminalTheme] = none(TerminalTheme),
              clear: bool = true, codeFormat: string = CONSOLE_SVG_FORMAT,
              fontAspectRatio: float = 0.61,
              uniqueId: Option[string] = none(string)): string =
  ## rich console.py:2352-2604 — `Console.export_svg(self, *, title: str =
  ## "Rich", theme: Optional[TerminalTheme] = None, clear: bool = True,
  ## code_format: str = CONSOLE_SVG_FORMAT, font_aspect_ratio: float = 0.61,
  ## unique_id: Optional[str] = None) -> str`: generate an SVG from the console
  ## contents. `code_format: str = CONSOLE_SVG_FORMAT` → `string =
  ## CONSOLE_SVG_FORMAT` (the provisional const); `font_aspect_ratio`→
  ## `fontAspectRatio`; `unique_id`→`uniqueId`.
  assert self.record, "To export console contents set record=True in the Console constructor"
  let themeVal = if theme.isSome: theme.get else: SVG_EXPORT_THEME
  let width = self.width
  let charHeight = 20
  let charWidth = charHeight.float * fontAspectRatio
  let lineHeight = charHeight.float * 1.22
  let marginTop = 1
  let marginRight = 1
  let marginBottom = 1
  let marginLeft = 1
  let paddingTop = 40
  let paddingRight = 8
  let paddingBottom = 8
  let paddingLeft = 8
  let paddingWidth = paddingLeft + paddingRight
  let paddingHeight = paddingTop + paddingBottom
  let marginWidth = marginLeft + marginRight
  let marginHeight = marginTop + marginBottom
  var textBackgrounds: seq[string] = @[]
  var textGroup: seq[string] = @[]
  var classes = initTable[string, int]()
  var styleNo = 1
  let segments = segment.filterControl(self.recordBuffer)
  if clear: self.recordBuffer.setLen(0)
  var uid = if uniqueId.isSome: uniqueId.get else: ""
  if uid.len == 0:
    var content = ""
    for seg in segments: content.add(seg.text)
    content.add(title)
    uid = "terminal-" & $(cast[uint](hash(content)))
  var y = 0
  var lineNo = 0
  for line in segment.splitAndCropLines(segments, width):
    y = lineNo
    var x = 0
    for seg in line:
      # `style = style or Style()` (console.py:2418): a segment with no style
      # uses a null `Style` (Python `Style()` ≡ `Style.null()` ≡ `NULL_STYLE`).
      # `Style.null()` returns the allocated `nullStyle` singleton (a real ref,
      # avoiding a nil deref in `getSvgStyle`).
      let st = if seg.style.isSome: Style(seg.style.get) else: Style.null()
      let rules = getSvgStyle(themeVal, st)
      if not classes.hasKey(rules):
        classes[rules] = styleNo
        styleNo += 1
      let className = "r" & $classes[rules]
      var hasBackground: bool
      var background: string
      if st.reverse.isSome and st.reverse.get:
        hasBackground = true
        background = if st.color.isNone: themeVal.foregroundColor.hex
                     else: st.color.get.getTruecolor().hex
      else:
        let bgcolor = st.bgcolor
        hasBackground = bgcolor.isSome and not bgcolor.get.isDefault
        background = if st.bgcolor.isNone: themeVal.backgroundColor.hex
                     else: st.bgcolor.get.getTruecolor().hex
      let textLength = cells.cellLen(seg.text)
      if hasBackground:
        textBackgrounds.add(makeSvgTag("rect", none(string),
          "fill=\"" & background & "\" x=\"" & gFormat(x.float * charWidth) &
          "\" y=\"" & gFormat(y.float * lineHeight + 1.5) &
          "\" width=\"" & gFormat(charWidth * textLength.float) &
          "\" height=\"" & gFormat(lineHeight + 0.25) &
          "\" shape-rendering=\"crispEdges\""))
      if seg.text != spaces(seg.text.len):
        textGroup.add(makeSvgTag("text", some(escapeSvgText(seg.text)),
          "class=\"" & uid & "-" & className &
          "\" x=\"" & gFormat(x.float * charWidth) &
          "\" y=\"" & gFormat(y.float * lineHeight + charHeight.float) &
          "\" textLength=\"" & gFormat(charWidth * seg.text.len.float) &
          "\" clip-path=\"url(#" & uid & "-line-" & $y & ")\""))
      x += textLength
    lineNo += 1
  var lineOffsets: seq[float] = @[]
  for lineN in 0 ..< y: lineOffsets.add(lineN.float * lineHeight + 1.5)
  var linesParts: seq[string] = @[]
  for lineN, offset in lineOffsets.pairs:
    linesParts.add("<clipPath id=\"" & uid & "-line-" & $lineN & "\">\n    " &
      makeSvgTag("rect", none(string),
        "x=\"0\" y=\"" & gFormat(offset) &
        "\" width=\"" & gFormat(charWidth * width.float) &
        "\" height=\"" & gFormat(lineHeight + 0.25) & "\"") &
      "\n            </clipPath>")
  let linesStr = linesParts.join("\n")
  var stylesParts: seq[string] = @[]
  for css, ruleNo in classes.pairs:
    stylesParts.add("." & uid & "-r" & $ruleNo & " { " & css & " }")
  let stylesStr = stylesParts.join("\n")
  let backgrounds = textBackgrounds.join("")
  let matrix = textGroup.join("")
  let terminalWidth = ceil(width.float * charWidth + paddingWidth.float)
  let terminalHeight = (y + 1).float * lineHeight + paddingHeight.float
  var chrome = makeSvgTag("rect", none(string),
    "fill=\"" & themeVal.backgroundColor.hex &
    "\" stroke=\"rgba(255,255,255,0.35)\" stroke-width=\"1\" x=\"" & $marginLeft &
    "\" y=\"" & $marginTop & "\" width=\"" & gFormat(terminalWidth) &
    "\" height=\"" & gFormat(terminalHeight) & "\" rx=\"8\"")
  let titleColor = themeVal.foregroundColor.hex
  if title.len > 0:
    chrome.add(makeSvgTag("text", some(escapeSvgText(title)),
      "class=\"" & uid & "-title\" fill=\"" & titleColor &
      "\" text-anchor=\"middle\" x=\"" & gFormat(floor(terminalWidth / 2.0)) &
      "\" y=\"" & gFormat(marginTop.float + charHeight.float + 6.0) & "\""))
  chrome.add("\n            <g transform=\"translate(26,22)\">\n            <circle cx=\"0\" cy=\"0\" r=\"7\" fill=\"#ff5f57\"/>\n            <circle cx=\"22\" cy=\"0\" r=\"7\" fill=\"#febc2e\"/>\n            <circle cx=\"44\" cy=\"0\" r=\"7\" fill=\"#28c840\"/>\n            </g>\n        ")
  var subs = initTable[string, string]()
  subs["unique_id"] = uid
  subs["char_width"] = gFormat(charWidth)
  subs["char_height"] = gFormat(charHeight.float)
  subs["line_height"] = gFormat(lineHeight)
  subs["terminal_width"] = gFormat(charWidth * width.float - 1.0)
  subs["terminal_height"] = gFormat((y + 1).float * lineHeight - 1.0)
  subs["width"] = gFormat(terminalWidth + marginWidth.float)
  subs["height"] = gFormat(terminalHeight + marginHeight.float)
  subs["terminal_x"] = $(marginLeft + paddingLeft)
  subs["terminal_y"] = $(marginTop + paddingTop)
  subs["styles"] = stylesStr
  subs["chrome"] = chrome
  subs["backgrounds"] = backgrounds
  subs["matrix"] = matrix
  subs["lines"] = linesStr
  result = pyFormat(codeFormat, subs)

proc saveSvg*(self: Console, path: string, title: string = "Rich",
            theme: Option[TerminalTheme] = none(TerminalTheme),
            clear: bool = true, codeFormat: string = CONSOLE_SVG_FORMAT,
            fontAspectRatio: float = 0.61,
            uniqueId: Option[string] = none(string)) =
  ## rich console.py:2606-2642 — `Console.save_svg(self, path, *, title = "Rich",
  ## theme = None, clear = True, code_format = CONSOLE_SVG_FORMAT,
  ## font_aspect_ratio = 0.61, unique_id = None) -> None`: generate an SVG and
  ## save to `path`.
  let svg = self.exportSvg(title = title, theme = theme, clear = clear,
                           codeFormat = codeFormat, fontAspectRatio = fontAspectRatio,
                           uniqueId = uniqueId)
  writeFile(path, svg)

discard
