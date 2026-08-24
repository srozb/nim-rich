#!/usr/bin/env python3
## golden_ref.py — Python rich reference renderer.
##
## Usage: golden_ref.py <case_name>
## Output: raw ANSI bytes on stdout (for byte-by-byte diff with golden_nim).
##
## Renders Text/Rule/Control/filesize via Python rich 15.0.0 (local copy).
## Uses Console with force_terminal=true, truecolor, width=80, record=True.
import sys, io, os, itertools
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from golden_cases import get_case, case_names, case_width, normalize_case

# Rich 15.0.0's `style._id_generator = count(getrandbits(24))` produces a
# random-start link-id for OSC 8 hyperlinks. The Nim port's `nextId()` starts
# from 1 (monotonic). Reset the Python generator to `count(1)` so both sides
# produce identical deterministic link ids (first link → id=4 after the
# Style.__init__ + 3 Style.__add__.copy() calls the link path makes).
from rich import style as _rich_style
_rich_style._id_generator = itertools.count(1)

from rich.text import Text
from rich.rule import Rule
from rich.control import Control
from rich.segment import ControlType
from rich.filesize import decimal as filesize_decimal
from rich.console import Console, Group
from rich.table import Table
from rich.panel import Panel
from rich.tree import Tree
from rich.box import HEAVY_HEAD, ASCII, ASCII2, ASCII_DOUBLE_HEAD, ROUNDED, DOUBLE, HEAVY, MINIMAL, SQUARE
from rich.emoji import Emoji
from rich.markdown import Markdown
from rich.bar import Bar
from rich.align import Align
from rich.columns import Columns
from rich.syntax import Syntax
from rich.spinner import Spinner
from rich.pretty import Pretty
from rich.status import Status
import logging
from rich.logging import RichHandler
from rich.progress import (
    Progress, BarColumn, TextColumn, TaskProgressColumn, TransferSpeedColumn,
    TimeElapsedColumn, MofNCompleteColumn, FileSizeColumn,
)
from rich.json import JSON
from rich.traceback import Traceback
from rich.prompt import Prompt
from rich.padding import Padding
from rich.styled import Styled
from rich.layout import Layout
from rich.ansi import AnsiDecoder
from rich.constrain import Constrain
from rich.scope import render_scope as rich_render_scope
from rich.region import Region
from rich.screen import Screen
# v0.6.0 — gap modules: measure/repr/theme/terminal_theme/errors.
from rich.measure import Measurement
from rich.terminal_theme import TerminalTheme, DEFAULT_TERMINAL_THEME
from rich.theme import Theme
from rich.errors import ConsoleError, StyleError, NotRenderableError, LiveError
from rich.repr import rich_repr, ReprError
# v0.7.0 — file_proxy gap module.
from rich.file_proxy import FileProxy
# v0.7.0 — live_render gap module.
from rich.live_render import LiveRender


def render_text(args):
    text, *rest = args
    style = rest[0] if rest else ""
    return Text(text, style=style or None)

def render_spans(args):
    # args = tuple of (text, style)
    t = Text()
    for text, style in args:
        t.append(text, style=style or None)
    return t

def render_rule(args):
    title, *rest = args
    # The literal "characters" marker means the first arg is Rule's
    # `characters` keyword (the rule line character), not a title or style.
    # `Rule.__init__` takes `characters` keyword-only (after `*`), so pass it
    # by name; title keeps its default (""), i.e. no title -> the plain
    # full-width rule line. `Style.parse("characters")` raises, so the
    # marker can never be a legitimate style and is unambiguous as a sentinel.
    if rest and rest[0] == "characters":
        return Rule(characters=title)
    # "align" marker — (title, align_value, "align"). Passes `align` by name
    # and omits `style`, so Rule uses its DEFAULT style "rule.line" (bright_green
    # \x1b[92m via DEFAULT_STYLES). This is DISTINCT from `rule_title` (whose
    # render_rule passes style=None -> no color): rule_title_center's centered
    # title "Section" renders WITH the green rule color, exercising the explicit
    # `align` keyword while keeping the default style.
    if rest and rest[-1] == "align":
        return Rule(title=title or None, align=rest[0])
    style = rest[0] if rest else None
    # Rule accepts title, characters, style
    return Rule(title=title or None, style=style)

def render_control(args):
    code, *rest = args
    payload = rest[0] if rest else None
    if code == "home":
        return Control.home()
    if code == "clear":
        return Control.clear()
    if code == "title":
        return Control.title(payload or "")
    # v0.5.0 — 5 new control codes (see golden_cases.py). `move` takes (x, y)
    # payload for `Control.move_to`; `move_up`/`move_down` use `Control.move`
    # with a negative/positive y (the spec `move_up`/`move_down` classmethods do
    # not exist in rich 15.0.0); `clear_line` uses the `ERASE_IN_LINE` control
    # code (no `clear_line` classmethod); `segment` is a multi-code `Control`
    # (the `Control.segment` attribute is not a callable).
    if code == "move":
        return Control.move_to(rest[0], rest[1])
    if code == "move_up":
        return Control.move(x=0, y=-3)
    if code == "move_down":
        return Control.move(x=0, y=3)
    if code == "clear_line":
        return Control((ControlType.ERASE_IN_LINE, 2))
    if code == "segment":
        return Control(ControlType.HOME, ControlType.CLEAR)
    # new control edge cases — `clear_screen` is Control.clear() (the sole
    # clear classmethod; "clear_screen" is the descriptive code identifier the
    # task requests, exercising the same \x1b[2J API). `move_rel` is
    # Control.move(x, y) (RELATIVE cursor move) at (10,20), emitting
    # \x1b[10C\x1b[20B per the original task's literal Control.move(10,20)
    # requirement; distinct from `move`'s Control.move_to(5,3) absolute → \x1b[4;6H.
    if code == "clear_screen":
        return Control.clear()
    if code == "move_rel":
        return Control.move(rest[0], rest[1])
    return Control("")

def render_filesize(args):
    # filesize returns a string, not a renderable — wrap in Text
    n = args[0]
    return Text(filesize_decimal(n))


def render_table(args):
    # args = (header_style, title, title_style, has_rows). Two fixed 4-wide
    # columns (Name/Data) sized exactly to their content; one row (abcd/efgh)
    # when has_rows. padding=0 so cells are not wrapped in Padding (any_padding
    # is False), keeping the Nim segmentation byte-exact for styled cells.
    #
    # v0.8.1 — new shape (data, box_style[, style]) where `data` is a nested
    # tuple ((header...), (row1...), ...). Detected by `isinstance(args[0],
    # tuple)`; builds a `Table(box=box[, style=style])` with auto-sized columns
    # (one per header), one `add_row` per data row. Width is 80 (case_width
    # default for "table"), matching `Table(box=box)` defaults.
    if args and isinstance(args[0], tuple):
        data = args[0]
        box_name = args[1] if len(args) > 1 else "rounded"
        style = args[2] if len(args) > 2 else None
        box_map = {"ascii": ASCII, "rounded": ROUNDED, "double": DOUBLE,
                   "heavy": HEAVY, "minimal": MINIMAL,
                   "heavy_head": HEAVY_HEAD}
        box = box_map[box_name]
        kw = dict(box=box)
        if style is not None:
            kw["style"] = style
        t = Table(**kw)
        headers = data[0]
        for h in headers:
            t.add_column(h)
        for row in data[1:]:
            t.add_row(*row)
        return t
    header_style, title, title_style, has_rows = args
    kw = dict(box=HEAVY_HEAD, padding=(0, 0, 0, 0), header_style=header_style)
    if title is not None:
        kw["title"] = title
        if title_style is not None:
            kw["title_style"] = title_style
    t = Table(**kw)
    t.add_column("Name", width=4, no_wrap=True)
    t.add_column("Data", width=4, no_wrap=True)
    if has_rows:
        t.add_row("abcd", "efgh")
    return t


def render_table_advanced(args):
    # args = (data, box_name, kwargs) where `data` is a nested tuple
    # ((header...), (row1...), ...) and `kwargs` is a dict of Table constructor
    # / add_column params. Builds a `Table(box=box, **table_kwargs)` with
    # per-column `justify` (when `col_justifies` is set) and one `add_row` per
    # data row. Width is 80 (case_width default for "table_advanced"),
    # matching `Table(box=box, ...)` defaults. The kwargs dict keys mirror
    # the real `Table.__init__` / `add_column` keyword names (header_style,
    # row_styles, padding, show_lines, col_justifies). Byte-exact rendering
    # is captured from Python rich 15.0.0 (the oracle).
    data, box_name, kwargs = args
    box_map = {"ascii": ASCII, "rounded": ROUNDED, "double": DOUBLE,
               "heavy": HEAVY, "minimal": MINIMAL,
               "heavy_head": HEAVY_HEAD, "square": SQUARE}
    box = box_map[box_name]
    kw = dict(box=box)
    # Forward known Table __init__ kwargs from the dict.
    for key in ("style", "padding", "row_styles", "header_style",
                "show_lines", "title", "title_style", "expand",
                "show_header", "show_edge", "show_footer", "leading"):
        if key in kwargs:
            kw[key] = kwargs[key]
    t = Table(**kw)
    headers = data[0]
    col_justifies = kwargs.get("col_justifies")
    col_widths = kwargs.get("col_widths")
    for i, h in enumerate(headers):
        ckw = {}
        if col_justifies is not None:
            ckw["justify"] = col_justifies[i]
        if col_widths is not None:
            ckw["width"] = col_widths[i]
            ckw["no_wrap"] = True
        t.add_column(h, **ckw)
    for row in data[1:]:
        t.add_row(*row)
    return t


def render_box(args):
    # args = (box_name,) or (box_name, content_variant). Constructs a
    # `Table(box=box)` exercising each box style (ASCII/ROUNDED/DOUBLE/HEAVY/
    # MINIMAL/SQUARE) with the Table defaults (padding=(0,1),
    # header_style="table.header"→bold header, auto-width columns). The default
    # content (no content_variant) is two columns "A"/"B" and one row "1"/"2"
    # — the original five box_* cases. The optional 2nd element
    # content_variant="three" builds three columns "X"/"Y"/"Z" and two rows
    # ("1","2","3")/("4","5","6") — a genuinely new 3-column/2-row edge config
    # used by the box_minimal_three/box_heavy_three cases (the default-content
    # box_minimal/box_heavy already exist in the baseline, so the "three"
    # variant exercises the minimal/heavy box styles with new content). The box
    # determines only the border characters; everything else is default. Width
    # is applied via the Console (capture_ansi's `width`, 80 via case_width),
    # matching golden_nim's renderBoxAnsi (renderTableAnsi at width 80).
    box_name = args[0]
    box_map = {"ascii": ASCII, "rounded": ROUNDED, "double": DOUBLE,
               "heavy": HEAVY, "minimal": MINIMAL, "square": SQUARE}
    box = box_map[box_name]
    t = Table(box=box)
    content_variant = args[1] if len(args) > 1 else None
    if content_variant == "three":
        for col in ("X", "Y", "Z"):
            t.add_column(col)
        t.add_row("1", "2", "3")
        t.add_row("4", "5", "6")
    else:
        t.add_column("A")
        t.add_column("B")
        t.add_row("1", "2")
    return t


def render_padding(args):
    # args = (text, (top, right, bottom, left)[, style]). Constructs a real
    # `rich.padding.Padding(Text(text), pad=pad, style=style)` (padding.py:19-135)
    # with `style` defaulting to `"none"` (a null style → no ANSI on the padding
    # spaces) and `expand=True` (the outer width is `options.max_width`; the
    # inner renderable renders within `width - left - right`). `pad` is the
    # CSS-style padding tuple (top, right, bottom, left); `Padding` draws space
    # around the renderable — blank lines for the top/bottom margins, space pads
    # for the left/right margins. A non-`"none"` `style` (the `padding_style` /
    # `padding_style_red` edge cases) is resolved via `console.get_style` and
    # applied to BOTH the padding spaces and the inner segments, wrapping the
    # whole padded block in the style's ANSI. Width is applied via the Console
    # (capture_ansi's `width`, 40 via case_width), matching golden_nim's
    # `renderPaddingAnsi` (real `Console` at width 40, truecolor, force_terminal).
    text, pad = args[0], args[1]
    style = args[2] if len(args) > 2 else "none"
    return Padding(Text(text), pad=pad, style=style)


def render_markup(args):
    # args = (markup_str,). Constructs the real `rich.text.Text.from_markup`
    # (text.py:259-291) — the public `@classmethod` that calls `markup.render`
    # (markup.py:101-185) to strip `[style]…[/]` console-markup tags into `Span`s
    # carrying the style NAME (resolved theme-aware by `Console.getStyle` at
    # render time, e.g. `[bold]x[/]` → plain `x` + `Span(0,1,"bold")` →
    # `\x1b[1m…\x1b[0m`), then sets `justify`/`overflow`/`end` (all defaults —
    # `None`/`None`/`"\n"`, matching `Text.from_markup`'s defaults). `emoji`/
    # `emoji_variant` keep their defaults (`True`/`None`). The `\[` escape renders
    # as the literal `[` with NO style (markup.render's parse path — `\[bold]`
    # → text `[bold]`, no spans). `console.print(Text, end="")` renders the
    # Text through the truecolor Console (width 80, case_width), matching
    # golden_nim's `renderMarkupAnsi` (`Text.fromMarkup` → `renderTextAnsi` at
    # width 80, the same `Text.render` path the `text_*`/`text_spans_*` cases
    # exercise). Byte-exact vs Python rich 15.0.0.
    markup_str = args[0]
    return Text.from_markup(markup_str)


def render_panel(args):
    # args = (text, title, subtitle, border_style, width[, box]). Panel uses
    # the ROUNDED box (the rich default) unless the optional 6th element `box`
    # names a different box style; the width is applied via the Console
    # (capture_ansi's `width` arg), so the panel fills the console width
    # (expand=True default; no explicit panel `width`). title/subtitle/
    # border_style are None when absent.
    text, title, subtitle, border_style, width = args[:5]
    box_name = args[5] if len(args) > 5 else None
    kw = {}
    if title is not None:
        kw["title"] = title
    if subtitle is not None:
        kw["subtitle"] = subtitle
    if border_style is not None:
        kw["border_style"] = border_style
    if box_name is not None:
        box_map = {"ascii": ASCII, "rounded": ROUNDED, "double": DOUBLE,
                   "heavy": HEAVY, "minimal": MINIMAL}
        kw["box"] = box_map[box_name]
    return Panel(text, **kw)


def render_tree(args):
    # args = (root_label, hide_root, style, width, children[, guide_style]).
    # `style` is None for the default "tree" theme, or a str for an explicit
    # style. `children` is a tuple of (label, grandchildren) specs (recursively;
    # () = no children). The optional 6th element `guide_style` overrides the
    # "tree.line" default (a str style applied to the guide lines ├── /└── ).
    # Builds the real Python rich `Tree` via chained `add` calls
    # (root.add(label).add(grandchild)...), the construction Rich's renderer
    # expects (passing a `Tree` as a label has different semantics).
    root_label, hide_root, style, width, children = args[:5]
    guide_style = args[5] if len(args) > 5 else None
    kw = {}
    if style is not None:
        kw["style"] = style
    if guide_style is not None:
        kw["guide_style"] = guide_style
    t = Tree(root_label, hide_root=hide_root, **kw)
    def add_children(parent, specs):
        for label, grand in specs:
            child = parent.add(label)
            add_children(child, grand)
    add_children(t, children)
    return t


def render_emoji(args):
    # args = (mode, ...). mode "obj" → construct and render a real `Emoji(name,
    # style, variant)` (emoji.py:20-48); mode "replace" → call the real
    # `Emoji.replace` classmethod (emoji.py:51-57) and render the resulting
    # string as plain Text (no markup), matching the harness pattern
    # (render_filesize returns Text). `style` is None (default "none") or a
    # str; `variant` is None, "emoji", or "text".
    mode = args[0]
    if mode == "replace":
        return Text(Emoji.replace(args[1]))
    # mode == "obj": (name, style, variant)
    name, style, variant = args[1], args[2], args[3]
    kw = {}
    if style is not None:
        kw["style"] = style
    if variant is not None:
        kw["variant"] = variant
    return Emoji(name, **kw)


def render_markdown(args):
    # args = (markup, width). Constructs the real `Markdown(markup)` with the
    # default code theme ("monokai"); `width` is applied via the Console (the
    # panel/tree pattern), so the Markdown renders within that width (headings
    # center, paragraphs left-align). No explicit `code_theme`/`justify`/
    # `style` overrides — defaults match the Nim `initMarkdown(markup)`.
    markup, width = args
    return Markdown(markup)


def render_bar(args):
    # args = (size, begin, end, bar_width, color). Constructs the real
    # `rich.bar.Bar`; `color` is None (default "default") or a str ("red").
    # The Bar's `width` (bar_width) caps the rendered bar; the Console width
    # (40, case_width) sets options.max_width (the bar renders min(self.width,
    # max_width) = 20 cells). bgcolor stays "default", so the default-style bar
    # emits `39;49` and the red bar `31;49`.
    size, begin, end, bar_width, color = args
    kw = dict(size=size, begin=begin, end=end, width=bar_width)
    if color is not None:
        kw["color"] = color
    return Bar(**kw)


def render_align(args):
    # v0.8.1 — new shape (text, align[, style]) where `style` is applied to
    # the Text (NOT the Align); detected by `len(args) < 4` (the legacy shape
    # (text, text_style, align, width) carries the Console width at index 3).
    # Width is supplied by case_width (50 for multiline, 40 otherwise).
    if len(args) < 4:
        if len(args) == 2:
            text, align = args
            style = None
        else:
            text, align, style = args
        t = Text(text, style=style or None)
        return Align(t, align=align)
    text, text_style, align, width = args
    t = Text(text, style=text_style or None)
    return Align(t, align=align)


def render_syntax(args):
    # args = (code, lexer[, theme, width]). Constructs the real
    # `Syntax(code, lexer, theme=theme)` with line_numbers=False, word_wrap=False
    # (defaults). `width` sets the Console options.max_width. The render goes
    # through the genuine `Syntax.__rich_console__` (highlight + segment render).
    if len(args) == 2:
        code, lexer = args
        theme = "monokai"
    else:
        code, lexer, theme, _width = args
    return Syntax(code, lexer, theme=theme, line_numbers=False, word_wrap=False)


def render_columns(args):
    # args = (texts_tuple, styles_tuple, padding_tuple, expand, width).
    texts, styles, padding, expand, width = args
    renderables = [Text(t, style=s) for t, s in zip(texts, styles)]
    return Columns(renderables, padding=padding, expand=expand)


def render_spinner(args):
    # args = (name, text, width). Constructs the real `Spinner(name)`;
    # `width` sets Console options.max_width. No `style` override.
    name, text, width = args
    return Spinner(name, text=text or None)


def render_pretty(args):
    # args = (obj,). Constructs the real `Pretty(obj)` (rich.pretty.Pretty,
    # pretty.py:170-261); `obj` is the literal Python object passed verbatim
    # (list/dict/str/int/bool/None). `Pretty` defaults to `ReprHighlighter`
    # (the automatic repr highlighting: brace=bold, number=bold cyan,
    # str=green, bool_true=italic bright_green, none=italic magenta), so no
    # explicit `highlighter` is set. Width is applied via the Console
    # (capture_ansi's `width` arg, 80 via case_width), matching golden_nim's
    # renderPrettyAnsi(width=80).
    obj = args[0]
    return Pretty(obj)


def render_status(args):
    # args = (text, [spinner_name]). Constructs the real `Status(text,
    # spinner=spinner_name)` (status.py:30-46); `.renderable` (the `@property`,
    # status.py:48-50) returns the `Spinner` it built (`Spinner(spinner,
    # text=status, style="status.spinner", speed=speed)`, status.py:42).
    # `capture_ansi` renders the Spinner via the Console: `Spinner.__rich_console__`
    # yields `self.render(time)` (spinner.py:54-56) → `Text.assemble(frame, " ",
    # self.text)` (spinner.py:99-108) — spinner frame 0 (styled `status.spinner`
    # → green via DEFAULT_STYLES) + " " + the status text, with the Text
    # default `end="\n"`. Byte-exact vs golden_nim's renderStatusAnsi.
    text, *rest = args
    spinner_name = rest[0] if rest else "dots"
    s = Status(text, spinner=spinner_name)
    return s.renderable


def render_logging(args):
    # args = (level, message) or ("LEVEL: message",). Constructs the real
    # `RichHandler(show_time=False,
    # show_level=True, show_path=False, rich_tracebacks=False)` (logging.py:71-
    # 121) and a `logging.LogRecord` (deterministic — no timestamp/path in the
    # output). `render_message` builds the message `Text` (logging.py:190-213);
    # `render` (logging.py:215-247) → `_log_render.LogRender.__call__`
    # (_log_render.py:43-103) builds a `Table.grid` (no box, expand=True) with a
    # `log.level` column (width=8) and a `log.message` column (ratio=1,
    # overflow=fold); the row is [level, message]. The level is
    # `Text.styled(levelname.ljust(8), "logging.level.<lower>")` (logging.py:132)
    # — INFO→blue / WARNING→yellow via DEFAULT_STYLES. Byte-exact vs
    # golden_nim's renderLoggingAnsi.
    if len(args) == 1:
        level, message = args[0].split(": ", 1)
    else:
        level, message = args
    level_map = {
        "INFO": logging.INFO,
        "WARNING": logging.WARNING,
        "ERROR": logging.ERROR,
    }
    rec = logging.LogRecord("test", level_map[level], "", 0, message, None, None)
    h = RichHandler(show_time=False, show_level=True, show_path=False,
                    rich_tracebacks=False)
    message_renderable = h.render_message(rec, message)
    return h.render(record=rec, traceback=None,
                    message_renderable=message_renderable)


def render_progress(args):
    # args = (description, total, completed), or nested task tuples for the
    # multi-task / transfer-speed cases. Constructs the real
    # `rich.progress.Progress` (progress.py:240-) with three columns in the
    # order golden_nim's `renderProgressAnsi` uses: `BarColumn()` (bar_width=40,
    # styles bar.back/bar.complete/bar.finished), `TextColumn("{task.description}")`
    # (a plain format string — no `[progress.description]` markup tag), and
    # `TaskProgressColumn()` (default text_format
    # `[progress.percentage]{task.percentage:>3.0f}%` → right-aligned width-3
    # percentage, e.g. ` 50%`/`100%`/` 38%`). `auto_refresh=False`+`disable=True`
    # suppress the Live display, so `add_task`'s internal `refresh()` is a no-op
    # (`Progress.refresh` guards on `not self.disable and self.live.is_started`)
    # and no stray bytes leak to stdout. `add_task(start=True)` (the default)
    # calls `start_task` → sets `task.start_time` → `task.started = True`
    # (`Task.started` is `start_time is not None`), so `BarColumn.render` builds
    # `ProgressBar(pulse=not task.started = False)` → the deterministic non-pulse
    # `ProgressBar.__rich_console__` path (completed/total/width only; no
    # `animation_time`/wall-clock in the output). `update(task_id,
    # completed=completed)` sets `task.completed`; `task.percentage =
    # (completed/total)*100`. `get_renderable()` returns
    # `Group(make_tasks_table(tasks))` — a single `Table.grid` (padding=(0,1),
    # expand=False) with one row [bar, description, percentage], matching
    # golden_nim's direct `makeTasksTable`+`Table.renderConsole`. Byte-exact vs
    # golden_nim's renderProgressAnsi (width 80, truecolor, force_terminal).
    if args and isinstance(args[0], tuple):
        tasks = args
        if len(tasks) == 1:
            progress = Progress(
                TextColumn("{task.description}"),
                TransferSpeedColumn(),
                auto_refresh=False,
                disable=True,
            )
        else:
            progress = Progress(
                TextColumn("{task.description}"),
                BarColumn(),
                TaskProgressColumn(),
                auto_refresh=False,
                disable=True,
            )
        for description, total, completed in tasks:
            task_id = progress.add_task(
                description, start=len(tasks) != 1, total=total
            )
            progress.update(task_id, completed=completed)
        return progress.get_renderable()

    description, total, completed = args
    progress = Progress(
        BarColumn(),
        TextColumn("{task.description}"),
        TaskProgressColumn(),
        auto_refresh=False,
        disable=True,
    )
    task_id = progress.add_task(description, start=True, total=total)
    progress.update(task_id, completed=completed)
    return progress.get_renderable()


def render_progress_advanced(args):
    # args = (layout, tasks) where `layout` is a string key selecting the
    # column set and `tasks` is a tuple of (description, total, completed)
    # task specs. Builds the real `rich.progress.Progress` (progress.py:240-)
    # with the columns named by `layout` — four NEW column types/layouts beyond
    # the baseline `render_progress`: `TimeElapsedColumn` (progress.py:688-695,
    # renders `str(timedelta(seconds=int(task.elapsed)))` styled
    # `progress.elapsed`), `MofNCompleteColumn` (progress.py:850-862, renders
    # `f"{completed:{total_width}d}/{total}"` styled `progress.download`), and
    # `FileSizeColumn` (progress.py:820-826, renders
    # `filesize.decimal(int(task.completed))` styled `progress.filesize`), plus
    # the description-first single-task layout and a three-task multi-row grid.
    # `auto_refresh=False`+`disable=True` suppress the Live display; all tasks
    # use `start=True` so `BarColumn` takes the deterministic non-pulse path
    # (completed/total/width only; no `animation_time`/wall-clock in the bar).
    # For `TimeElapsedColumn`, `task.elapsed = get_time() - start_time` is a
    # tiny sub-second value (synchronous render right after `add_task`), so
    # `int(elapsed) == 0` → "0:00:00" — byte-stable (300-run oracle-verified).
    # Width is 80 (case_width). `get_renderable()` returns the single
    # `make_tasks_table` grid; `capture_ansi` prints it through the real
    # truecolor Console. Byte-exact vs golden_nim's per-case render functions.
    layout, tasks = args
    col_map = {
        "bar_text_time": [BarColumn(), TextColumn("{task.description}"),
                          TimeElapsedColumn()],
        "text_bar_pct": [TextColumn("{task.description}"), BarColumn(),
                         TaskProgressColumn()],
        "bar_text_mofn": [BarColumn(), TextColumn("{task.description}"),
                          MofNCompleteColumn()],
        "bar_text_filesize": [BarColumn(), TextColumn("{task.description}"),
                              FileSizeColumn()],
    }
    columns = col_map[layout]
    progress = Progress(*columns, auto_refresh=False, disable=True)
    for description, total, completed in tasks:
        task_id = progress.add_task(description, start=True, total=total)
        progress.update(task_id, completed=completed)
    return progress.get_renderable()


def render_json(args):
    # args = (data_str,). Constructs the real `rich.json.JSON(data_str)`
    # (json.py:14-41): `loads(data_str)` then `dumps(indent=2, ensure_ascii=False)`
    # (the canonical pretty form, json.py:31-40), highlighted via the real
    # `JSONHighlighter` (highlighter.py:106-140) — `super().highlight` adds a
    # `json.<name>` span per named group (`brace`=bold, `bool_true`/`bool_false`/
    # `null`, `number`=bold cyan, `str`=green) via the combined regex, then the
    # JSON-key scan appends `json.key` (bold blue) spans for strings followed by
    # `:` (highlighter.py:127-139) — so keys render bold-blue (json.key overrides
    # json.str via Style.combine), values green, numbers bold-cyan, braces bold.
    # `JSON` is a `RichCast` (`__rich__`→`self.text`); `capture_ansi` renders it
    # through the truecolor Console (width 80). `console.print(JSON, end="")`
    # renders the `RichCast`'s `Text` with the print's `end` ("") overriding the
    # Text's own `end` (a trailing newline) via `sep_text.join` — the JSON output has NO trailing
    # newline (unlike the ConsoleRenderable `Pretty`). Byte-exact vs golden_nim's
    # `renderJsonAnsi` (which drives `initJson`→`richCast`→`Text.render` via the
    # real `Console` with a json.* theme push and `end=""`).
    data_str = args[0]
    return JSON(data_str)


def render_prompt(args):
    # args = (text, choices, default[, password]). `choices` is None (no
    # choices) or a list of str; `default` is None (no default — the Python
    # Ellipsis sentinel `...`, prompt.py:178 `default != ...`) or a str. The
    # optional 4th element `password` (bool, default False) constructs the Prompt
    # with `password=True` (PromptBase.__init__, prompt.py:54-76) — NOTE
    # `password` only affects the interactive `console.input` echo loop
    # (prompt.py:176-181), NOT the static `make_prompt` display (prompt.py:120-
    # 141 references no `password`), so the rendered Text is byte-identical to
    # the same Prompt without `password`; the case still exercises the
    # `Prompt(..., password=True)` construction path (the flag is stored on
    # PromptBase, prompt.py:62). Uses the STATIC non-interactive path
    # `PromptBase.make_prompt(default)` (prompt.py:120-141) which returns the
    # prompt DISPLAY `Text` (NO stdin, NO `console.input` loop) — byte-stable:
    # the base text (style "prompt", empty in DEFAULT_STYLES → no ANSI), the
    # optional choices bracket " [c1/c2/…]" (style "prompt.choices" → magenta
    # bold → ANSI `\x1b[1;35m…\x1b[0m`), the optional default bracket " (val)"
    # (style "prompt.default" → cyan bold → `\x1b[1;36m…\x1b[0m`) and the ": "
    # suffix (no style) — `Text.end` is set to "" by `make_prompt`, so no
    # trailing newline (the prompt waits on the input line). `Confirm` is
    # `PromptBase` with `choices=["y","n"]`; `make_prompt` lives on `PromptBase`,
    # so a plain `Prompt("Continue", choices=["y","n"])` reproduces
    # `Confirm("Continue")` byte-exact (verified) — no separate `Confirm` code
    # path needed.
    text, choices, default = args[0], args[1], args[2]
    password = args[3] if len(args) > 3 else False
    p = Prompt(text, choices=list(choices) if choices is not None else None,
               password=password)
    return p.make_prompt(... if default is None else default)


def render_abc(args):
    # args = (variant, width). The `rich.abc` module holds only the abstract
    # `RichRenderable` concept (no renderable, no constructor) — confirmed
    # round_001. ASCII-only box drawing is `rich.box.ASCII`/`ASCII2`/
    # `ASCII_DOUBLE_HEAD` (box.py:186-220), already exported from `box.nim`.
    # So the "abc golden" gap is filled with ASCII-box rendering on the
    # existing `Table`/`Panel` paths (the `render_box`/`render_panel` pattern),
    # NOT via `rich.abc.ABC`. variant "table" → `Table(box=ASCII, title=\"ABC\")`
    # (a title row + the ASCII box border — distinct from `box_ascii`, which is
    # a titleless ASCII Table); "panel" → `Panel(\"hello\", box=ASCII)` (an
    # ASCII-panel — the `panel_*` cases all use the ROUNDED default, so this is
    # genuine new coverage); "border" → `Panel(\"hello\", box=ASCII_DOUBLE_HEAD,
    # border_style=\"red\")` (a custom ASCII border — the `=` head divider + a
    # red border). `width` is the Console width (the panel fills it; the Table
    # is auto-sized).
    variant, width = args
    if variant == "table":
        t = Table(box=ASCII, title="ABC")
        t.add_column("A")
        t.add_column("B")
        t.add_row("1", "2")
        return t
    if variant == "panel":
        return Panel("hello", box=ASCII)
    if variant == "border":
        return Panel("hello", box=ASCII_DOUBLE_HEAD, border_style="red")
    raise ValueError(f"unknown abc variant: {variant}")


def render_styled(args):
    # args = (mode,). `rich.styled.Styled(renderable, style)` (styled.py:11-41):
    # render `self.renderable` then `Segment.apply_style(…,
    # console.get_style(self.style))` (styled.py:29-36). The style is applied
    # across the WHOLE rendered output. mode "simple" → `Styled(Text(\"hello\"),
    # \"bold red\")`; "nested" → `Styled(Text` with two color spans, `\"bold red\")`
    # (the outer style combines with the inner span styles — outer bold + inner
    # color); "style" → `Styled(Text(\"hi\"), \"bold italic red on blue\")` (a
    # complete style: bold+italic+fg+bg). The renderable is a `Text` (the
    # documented limitation is the non-`Text` arm where the style is NOT
    # applied — these cases AVOID it by using `Text`, so the style IS applied
    # and the output is byte-exact). Width is 80 (case_width).
    mode = args[0]
    if mode == "simple":
        return Styled(Text("hello"), "bold red")
    if mode == "nested":
        t = Text()
        t.append("he", style="red")
        t.append("llo", style="blue")
        return Styled(t, "bold red")
    if mode == "style":
        return Styled(Text("hi"), "bold italic red on blue")
    raise ValueError(f"unknown styled mode: {mode}")


def render_ratio(args):
    # args = (variant,). `rich._ratio` (`ratio_resolve`/`ratio_distribute`,
    # _ratio.py:14-141) is consumed by `Table.add_column(ratio=...)`
    # (table.py:547-581): ratio columns distribute the flexible width by their
    # `ratio` (a column with `ratio=None` is fixed-width; a `ratio>0` column is
    # flexible). variant "simple" → `Table(box=None, width=40)` with three
    # columns ratio 1:2:1 (the middle column gets half the flexible width);
    # "uneven" → two columns ratio 1:3; "three" → three columns ratio 1:1:1
    # (equal split). `box=None` suppresses the border (a `Table.grid`-style
    # layout) so the output is the padded columns only; `width=40` fixes the
    # table width (the flexible columns expand to fill it). One row of
    # single-char cells. Width is 40 (case_width).
    variant = args[0]
    if variant == "simple":
        t = Table(box=None, width=40)
        t.add_column("A", ratio=1)
        t.add_column("B", ratio=2)
        t.add_column("C", ratio=1)
        t.add_row("x", "y", "z")
        return t
    if variant == "uneven":
        t = Table(box=None, width=40)
        t.add_column("A", ratio=1)
        t.add_column("B", ratio=3)
        t.add_row("x", "y")
        return t
    if variant == "three":
        t = Table(box=None, width=40)
        t.add_column("A", ratio=1)
        t.add_column("B", ratio=1)
        t.add_column("C", ratio=1)
        t.add_row("x", "y", "z")
        return t
    raise ValueError(f"unknown ratio variant: {variant}")


def render_layout(args):
    # args = (variant, width). `rich.layout.Layout` (layout.py:106-336) divides
    # a fixed region into rows/columns of sub-layouts. `split_column`/`split_row`
    # (layout.py:223-229/215-221) set the splitter + children; an absent
    # renderable wraps a `_Placeholder` (layout.py:106-135) — the Nim port
    # renders the literal `\"Placeholder\"` for it (a documented simplification,
    # NOT byte-exact with Python's `Panel(Pretty(layout))`), so these cases
    # give each section a real `Text` renderable to stay byte-exact. variant
    # "simple" → `split_column(Text(\"upper\"), Text(\"lower\"))` (2 stacked
    # sections, each half the height); "row" → `split_row(Text(\"L\"),
    # Text(\"R\"))` (2 side-by-side columns, each half the width); "tree" → a
    # nested split (an upper section that itself `split_row`s into `a`/`b`, plus
    # a lower section). `width` is the Console width (40); the Console height is
    # 24 (capture_ansi's fixed height), so each `split_column` section is 12
    # rows and the output is 24 padded rows.
    variant, width = args
    if variant == "simple":
        l = Layout()
        l.split_column(Layout(Text("upper")), Layout(Text("lower")))
        return l
    if variant == "row":
        l = Layout()
        l.split_row(Layout(Text("L")), Layout(Text("R")))
        return l
    if variant == "tree":
        l = Layout()
        upper = Layout(Text("upper"))
        upper.split_row(Layout(Text("a")), Layout(Text("b")))
        l.split_column(upper, Layout(Text("lower")))
        return l
    raise ValueError(f"unknown layout variant: {variant}")


def render_ansi(args):
    # args = (ansi_str,). `rich.ansi.AnsiDecoder` (ansi.py:120-241) decodes
    # ANSI-coded text into styled `Text` — `decode` (ansi.py:137-145) splits on
    # newlines and yields `decode_line` per line; `decode_line` (ansi.py:147-
    # 241) walks the SGR/OSC codes via `_ansi_tokenize` + `SGR_STYLE_MAP`,
    # building a `Text` with `Span`s carrying the running `Style`. These cases
    # use single-line inputs (no `\n`), so `decode` yields exactly one `Text`;
    # `render_ansi` returns it. `capture_ansi` prints it with `end=\"\"` (the
    # print's end overrides the Text's own `end=\"\\n\"`), so the output is the
    # decoded content with NO trailing newline — matching the `text_plain`
    # pattern. ansi_simple → plain text (no SGR → no spans → plain output);
    # ansi_color → `\x1b[31mred\x1b[0m` (SGR 31 → `color(1)` → red); ansi_bold →
    # `\x1b[1mbold\x1b[0m` (SGR 1 → bold); ansi_bold_color →
    # `\x1b[1;31mbold red\x1b[0m` (combined SGR `1;31`); ansi_reset → a reset
    # followed by text (the reset clears the running style, the text after it
    # is unstyled). Width is 80 (case_width, unused by the single-segment Text).
    s = args[0]
    decoder = AnsiDecoder()
    texts = list(decoder.decode(s))
    return texts[0]


def render_constrain(args):
    # v0.5.0 — args = (width,) or (width, text). `rich.constrain.Constrain(
    # renderable, width=N)` (constrain.py:10-37) caps the renderable's render
    # width to N. The renderable is `Align(Text(text), align="center")`
    # (expand=True), so it fills the constrained width N — the constraint is
    # visibly exercised (the output width = N). The Console width (case_width)
    # = N, so the Align fills exactly N. `Constrain` has no `height` param, so
    # constrain_height/constrain_both use a distinct width (30/40) — feasible
    # substitutes for the infeasible spec-named cases (see golden_cases.py).
    # The optional `text` (args[1], default "hi") lets the layout_constrain
    # cases use a distinct inner text (e.g. "constrained max"/"ok").
    width = args[0]
    text = args[1] if len(args) > 1 else "hi"
    return Constrain(Align(Text(text), align="center"), width=width)


def render_group(args):
    # layout_constrain — args = (variant, width). `rich.console.Group(
    # *renderables, fit=True)` (console.py:450-480) renders each renderable
    # sequentially (`__rich_console__` yields from `self.renderables`); each
    # renderable's Console.print adds its own trailing `\n`. variant selects
    # the renderable set: "render" → 3 plain Texts; "styled" → 2 styled Texts
    # (bold/red); "rule" → Text + Rule + Text (exercises a non-Text renderable
    # in the group). Width 40 (case_width; the plain/styled texts are
    # width-independent; the Rule fills 40).
    variant, width = args
    if variant == "render":
        return Group(Text("line one"), Text("line two"), Text("line three"))
    if variant == "styled":
        return Group(Text("bold line", style="bold"), Text("red line", style="red"))
    if variant == "rule":
        return Group(Text("before"), Rule(), Text("after"))
    raise ValueError(f"unknown group variant: {variant}")


def render_scope_case(args):
    # v0.5.0 — args = (variant, width). `rich.scope.render_scope(mapping, *,
    # title=...)` (scope.py:14-73) renders a `Panel.fit` of a `Table.grid` of
    # `key = Pretty(value)` rows (no `Scope` class exists in rich 15.0.0). The
    # Console width (case_width) = the panel's content-fit width, so the
    # content-fit panel renders identically on both sides. variant selects the
    # mapping/title (uniform int values keep `Pretty(int)` byte-identical;
    # `style` uses the `title` kwarg — `render_scope` has no `style` param).
    variant, width = args
    if variant == "simple":
        return rich_render_scope({"a": 1, "b": 2})
    if variant == "nested":
        return rich_render_scope({"d": {"inner": 5}})
    if variant == "style":
        return rich_render_scope({"x": 1}, title="Variables")
    return rich_render_scope({})


def render_region(args):
    # v0.5.0 — args = (x, y, width, height). `rich.region.Region` (region.py:
    # 4-10) is a `NamedTuple`, NOT a renderable (no `__rich_console__`), so
    # `console.print(Region(...))` renders the `ReprHighlighter`-painted repr
    # (Python wraps the non-renderable in `Pretty`). `region_overlap` has no
    # `overlap` method — a third distinct `Region` is the feasible substitute.
    # Width 80 (case_width; the single-line repr is width-independent).
    x, y, w, h = args
    return Region(x, y, w, h)


def render_screen(args):
    # v0.5.0 — args = (variant, width, height). `rich.screen.Screen(
    # *renderables, style=None, application_mode=False)` (screen.py:15-46)
    # fills the terminal screen (width x height) and crops excess. variant
    # "simple" -> `Screen(Text("hi"))`; "multi" -> `Screen(Text("line1"),
    # Text("line2"))`; "update" -> `Screen(Text("hi"), application_mode=True)`
    # (the spec `Screen.update` method does not exist — `application_mode` is
    # the feasible substitute; it changes the line separator to `"\n\r"`). The
    # Console height is 24 (capture_ansi's fixed height); the Screen fills
    # width x 24.
    variant, width, height = args
    if variant == "simple":
        return Screen(Text("hi"))
    if variant == "multi":
        return Screen(Text("line1"), Text("line2"))
    if variant == "update":
        return Screen(Text("hi"), application_mode=True)
    return Screen(Text(""))


# NOTE on render_pager: `rich.pager.Pager` is OMITTED from the golden suite.
# `Pager` is an abstract `show(content: str) -> None` whose sole concrete impl
# `SystemPager.show` delegates to `pydoc.pager(content)` (pager.py:20-25), which
# spawns the system pager (`less`/`$PAGER`) as a SUBPROCESS and pipes `content`
# to its stdin — it returns `None`, writes nothing to the Console, and the
# bytes that reach the terminal are controlled entirely by the pager binary
# (line wrapping, scroll UI, terminal-size dependent). `Pager` is NOT a
# `RenderableBase` (no `__rich_console__`/`__rich__`); there is no static render
# path and no byte-stable output. Byte-exact comparison against a Nim port is
# therefore impossible (the contract's C6 permits omitting pager with a
# documented rationale; prompt is never skipped). The case-count target
# adjusts accordingly: 5 prompt cases ship (prompt_simple/prompt_confirm/
# prompt_choices/prompt_default/prompt_choices_default), pager ships none.


def _make_exc_info(exc_type_name, msg, depth):
    # Synthesize a real `exc_info` (type, value, tb) with exactly `depth`
    # frames, all sourced from `<string>` (so rich's `Traceback` takes the
    # compact format — no source block, no inter-frame blank line, frames
    # rendered ` in <name>:<lineno>`). The raise lives at a deterministic
    # line; a `_lh_catch` wrapper wraps it in `try/except` so the most-recent
    # frame is the call site and the deepest frame is the raise. `depth=1` →
    # `_lh_catch` raises directly (1 frame); `depth>=2` → `_lh_catch` calls
    # `_lh_r{depth-2}` → ... → `_lh_r0` (raise), giving `depth` frames.
    # `exec(compile(code, "<string>", "exec"))` keeps every frame's filename
    # `<string>` (non-existent → compact path, traceback.py:813-825).
    lines = ["import sys"]
    if depth == 1:
        lines += ["def _lh_catch():", "    try:",
                  f"        raise {exc_type_name}({msg!r})",
                  "    except Exception:", "        return sys.exc_info()"]
    else:
        lines += ["def _lh_r0():", f"    raise {exc_type_name}({msg!r})"]
        for i in range(1, depth - 1):
            lines += [f"def _lh_r{i}():", f"    _lh_r{i-1}()"]
        lines += ["def _lh_catch():", "    try:",
                  f"        _lh_r{depth-2}()", "    except Exception:",
                  "        return sys.exc_info()"]
    ns = {}
    exec(compile("\n".join(lines), "<string>", "exec"), ns)
    return ns["_lh_catch"]()


def render_traceback(args):
    # args = (exc_type_name, msg, depth). Synthesize a real `<string>`-sourced
    # `exc_info` raised across `depth` frames (so rich uses the compact
    # traceback format — no source block, no inter-frame blank line, frames
    # ` in <name>:<lineno>`), then construct the real
    # `Traceback.from_exception(*exc_info)` (traceback.py:353-421) with rich
    # 15.0.0 defaults (width=100, code_width=88, extra_lines=3, word_wrap=False,
    # indent_guides=True, show_locals=False). `from_exception` returns a
    # `Traceback` whose `__rich_console__` (`@group`) yields the `Panel` (title
    # `[traceback.title]Traceback [dim](most recent call last)`, border
    # `traceback.border`, padding=(0,1)) of the frame lines + the exception line
    # `Text.assemble((f"{exc_type}: ", "traceback.exc_type"),
    # highlighter(exc_value))` — `traceback.exc_type`=bold bright_red,
    # `ReprHighlighter` adds `repr.str`=green on quoted values (e.g. KeyError's
    # `'missing key'`); a plain message (ValueError's `test message`) stays
    # uncolored. `capture_ansi` renders it through the truecolor Console
    # (width 80) with `end=""` — the Panel keeps its trailing newlines and the
    # exception line ends with `\n`. Byte-exact vs golden_nim's
    # `renderTracebackAnsi` (Panel + exception-line carrier, real Console,
    # traceback.* theme push).
    if len(args) == 3:
        exc_type_name, msg, depth = args
        exc_info = _make_exc_info(exc_type_name, msg, depth)
        return Traceback.from_exception(*exc_info)

    if args == ("ValueError: test error",):
        exc_info = _make_exc_info("ValueError", "test error", 1)
        return Traceback.from_exception(*exc_info)

    if args == ("TypeError: bad arg", "x=1, y='str'"):
        code = "\n".join([
            "import sys",
            "def _lh_catch():",
            "    x = 1",
            "    y = 'str'",
            "    try:",
            "        raise TypeError('bad arg')",
            "    except Exception:",
            "        return sys.exc_info()",
        ])
        ns = {}
        exec(compile(code, "<string>", "exec"), ns)
        return Traceback.from_exception(*ns["_lh_catch"](), show_locals=True)

    if args == ("SyntaxError: invalid syntax (test.py, line 5)",):
        bad_source = "\n\n\n\nif True print('bad')\n"
        code = "\n".join([
            "import sys",
            "def _lh_catch():",
            "    try:",
            f"        compile({bad_source!r}, 'test.py', 'exec')",
            "    except SyntaxError:",
            "        return sys.exc_info()",
        ])
        ns = {}
        exec(compile(code, "<string>", "exec"), ns)
        return Traceback.from_exception(*ns["_lh_catch"]())

    if args == ("RuntimeError: outer", "ValueError: inner cause"):
        code = "\n".join([
            "import sys",
            "def _lh_inner():",
            "    try:",
            "        raise ValueError('inner cause')",
            "    except ValueError as exc:",
            "        raise RuntimeError('outer') from exc",
            "def _lh_catch():",
            "    try:",
            "        _lh_inner()",
            "    except Exception:",
            "        return sys.exc_info()",
        ])
        ns = {}
        exec(compile(code, "<string>", "exec"), ns)
        return Traceback.from_exception(*ns["_lh_catch"]())

    if args == ("RecursionError: maximum recursion depth exceeded",):
        exc_info = _make_exc_info(
            "RecursionError", "maximum recursion depth exceeded", 8
        )
        return Traceback.from_exception(*exc_info, max_frames=3)

    raise ValueError(f"unknown traceback case arguments: {args!r}")


def render_measure(args):
    # v0.6.0 — args = (minimum, maximum). Constructs the real
    # `rich.measure.Measurement(min, max)` (a `NamedTuple`, NOT a renderable).
    # `capture_ansi`'s `console.print(Measurement(...))` wraps the non-renderable
    # in `Pretty` → renders `repr(obj)` = `Measurement(minimum=.., maximum=..)`
    # via `ReprHighlighter` (the `Region`/NamedTuple path): `repr.call`=bold
    # magenta on `Measurement`, `repr.brace`=bold on `(`/`)`, `repr.attrib_name`
    # =yellow on `minimum`/`maximum`, `=` bare (the `attrib_value` regex's
    # optional group matches empty before a digit), `repr.number`=bold cyan on
    # the ints. The four (min,max) pairs are shell-probed from
    # `Measurement.get(console, options, renderable)` on the four renderables
    # (Text("hello")→5/5, the golden HEAVY_HEAD Table→11/11, Panel("content")
    # →11/11, Text("wide string here")→6/16) — rich's real measurements. The
    # Nim `Measurement.get` is DEFERRED, so the Nim `renderMeasureAnsi`
    # constructs `Measurement(min,max)` directly with these probed values
    # (the contract's allowed substitute), matching rich bytes. The Pretty
    # `Text.from_ansi` keeps its default `end="\n"`, so the output ends with
    # `\n` (the print's `end=""` does NOT override a yielded renderable's own
    # `end` — only the top-level print `end` for the joined segments; the
    # `Pretty`'s trailing `Segment.line()` survives as a real `\n`).
    minimum, maximum = args
    return Measurement(minimum, maximum)


def render_repr(args):
    # v0.6.0 — args = (variant,). There is NO `Repr` class in rich 15.0.0
    # (the spec's `Repr(obj)` is infeasible — confirmed by shell probe); the
    # actual `rich.repr` machinery is the `@rich_repr`/`@auto` class decorator
    # that installs a `__repr__` from a `__rich_repr__` generator, plus the
    # `ReprError` exception. The decorated object is NOT a renderable, so
    # `console.print(obj)` renders `repr(obj)` via `Pretty`+`ReprHighlighter`
    # (the `Region`/`Measurement` path). variant "simple"→`Thing(name='widget',
    # count=3)` (kv: str + int), "text"→`PosArgs('only', 'args')` (positional
    # string args — the "text" value intent), "panel"→`WithStr(title='hello',
    # items=[1, 2, 3])` (a nested-list container — the "panel"/container
    # intent), "error"→`ReprError("boom")` (the real `rich.repr.ReprError`;
    # `console.print(exception)` renders `str(exception)`="boom" via
    # `_highlighter(str)` with NO trailing newline, unlike the Pretty-repr
    # cases). The Nim `renderReprAnsi` builds the repr string via the real
    # `repr.autoRepr` then applies `ReprHighlighter`; `repr_error` renders the
    # `ReprError` message with `end=""`.
    variant = args[0]
    if variant == "simple":
        @rich_repr
        class Thing:
            def __rich_repr__(self):
                yield "name", "widget"
                yield "count", 3
        return Thing()
    if variant == "text":
        @rich_repr
        class PosArgs:
            def __rich_repr__(self):
                yield "only"
                yield "args"
        return PosArgs()
    if variant == "panel":
        @rich_repr
        class WithStr:
            def __rich_repr__(self):
                yield "title", "hello"
                yield "items", [1, 2, 3]
        return WithStr()
    if variant == "error":
        return ReprError("boom")
    raise ValueError(f"unknown repr variant: {variant}")


def render_theme(args):
    # v0.6.0 — args = (variant, width). `rich.theme.Theme` is a container of
    # named styles, NOT a renderable; printing a `Theme` yields the non-
    # deterministic default object repr (`<rich.theme.Theme object at 0x...>` —
    # NOT byte-stable, confirmed by shell probe). So the Theme gap is filled
    # by APPLYING a `Theme` to a renderable via the Console theme stack: the
    # renderable's custom style names resolve through `Console.get_style` →
    # the theme's parsed `Style`s. `render_theme` returns a `(renderable,
    # theme)` pair; `main()` passes the `theme` to `capture_ansi`'s `theme=`
    # kwarg so the `Console` is constructed with it (the real Theme
    # application path). variant "simple"→`Theme({"key": "bold red"})` applied
    # to `Text("hi", style="key")`; "multi"→`Theme({"a": "bold red", "b":
    # "italic blue", "c": "dim yellow"})` applied to a single `Text` with three
    # spans (byte-identical to three separate prints — verified); "apply"→
    # `Theme({"my_border": "magenta"})` applied to `Panel("content",
    # border_style="my_border")` (the border resolves `my_border`→magenta via
    # the theme — exercises Theme on a non-trivial renderable). The Nim
    # `renderThemeAnsi` pushes the same `Theme` via `console.pushTheme
    # (initTheme(...))` (the established `pushJsonTheme` pattern) and renders
    # the renderable through the real `Console`.
    variant, width = args
    if variant == "simple":
        return (Text("hi", style="key"), Theme({"key": "bold red"}))
    if variant == "multi":
        t = Text()
        t.append("a", style="a")
        t.append("b", style="b")
        t.append("c", style="c")
        return (t, Theme({"a": "bold red", "b": "italic blue", "c": "dim yellow"}))
    if variant == "apply":
        return (Panel("content", border_style="my_border"),
                Theme({"my_border": "magenta"}))
    raise ValueError(f"unknown theme variant: {variant}")


def render_terminal_theme(args):
    # v0.6.0 — args = (variant,). `rich.terminal_theme.TerminalTheme` bundles
    # a background/foreground `ColorTriplet` plus a 16-colour `Palette` for
    # SVG/HTML export; it is NOT a renderable and prints as the non-
    # deterministic default object repr (NOT byte-stable), and
    # `TerminalTheme()` with no args raises (it requires background/
    # foreground/normal). So the gap is filled by rendering a `ColorTriplet`
    # attribute repr of a real `TerminalTheme` (`ColorTriplet` IS a
    # `NamedTuple` → its repr is byte-stable via `ReprHighlighter`, the
    # `Region`/`Measurement` pattern). variant "simple"→
    # `DEFAULT_TERMINAL_THEME.background_color` (the real predefined default —
    # white bg `ColorTriplet(255,255,255)`); "custom"→ a custom
    # `TerminalTheme((10,20,30),(40,50,60),[...16 colours...]).background_color`
    # (`ColorTriplet(10,20,30)`); "fg"→ the same custom theme's
    # `.foreground_color` (`ColorTriplet(40,50,60)`). `render_terminal_theme`
    # returns the `ColorTriplet` (constructing the custom `TerminalTheme` with
    # the real args). The Nim `renderTerminalThemeAnsi` constructs the same
    # `TerminalTheme` via `initTerminalTheme`/`DEFAULT_TERMINAL_THEME` and
    # builds the `ColorTriplet(red=.., green=.., blue=..)` repr from the fields,
    # applies `ReprHighlighter`, renders with `end="\n"`.
    variant = args[0]
    # The 16 standard ANSI colours (8 normal + 8 bright) for the custom theme.
    _normal = [(0,0,0),(128,0,0),(0,128,0),(128,128,0),(0,0,128),(128,0,128),
               (0,128,128),(192,192,192)]
    _bright = [(128,128,128),(255,0,0),(0,255,0),(255,255,0),(0,0,255),
               (255,0,255),(0,255,255),(255,255,255)]
    if variant == "simple":
        return DEFAULT_TERMINAL_THEME.background_color
    custom = TerminalTheme((10, 20, 30), (40, 50, 60), _normal, _bright)
    if variant == "custom":
        return custom.background_color
    if variant == "fg":
        return custom.foreground_color
    raise ValueError(f"unknown terminal_theme variant: {variant}")


def render_errors(args):
    # v0.6.0 — args = (class_name, message). `rich.errors` exceptions are NOT
    # renderable (`is_renderable(Exception)` is False), so `console.print(exc)`
    # renders `_highlighter(str(exc))` (console.py:1577
    # `append_text(_highlighter(str(renderable)))`) — the message string with
    # `ReprHighlighter` applied (no spans for the plain messages below → plain
    # text) and NO trailing newline (the print's `end=""` overrides the Text
    # end). `render_errors` constructs the real exception and returns it. The
    # four classes cover the two base error families: `ConsoleError` (the
    # console base) + its subclasses `NotRenderableError`/`LiveError`, and
    # `StyleError` (the style base). The messages are plain (no `[`/`(`/digits
    # → `ReprHighlighter` adds no spans → byte-stable plain text). The Nim
    # `renderErrorsAnsi` constructs the same exception via `newException` and
    # renders the message via `ReprHighlighter` + the real `Console` with
    # `end=""`.
    class_name, message = args
    classes = {"ConsoleError": ConsoleError, "StyleError": StyleError,
              "NotRenderableError": NotRenderableError, "LiveError": LiveError}
    return classes[class_name](message)


def _fp_renderables(variant):
    # v0.7.0 — the renderable(s) a `file_proxy_*` variant renders. Each
    # variant maps to a list of one renderable (or two for "multi"); the same
    # mapping is mirrored byte-for-byte by `golden_nim.nim`'s `renderCase`
    # `file_proxy_*` dispatch (each uses the proven `render*Ansi` carrier, so
    # the raw source ANSI is byte-identical to the matching existing case).
    if variant == "simple":      return [Text("hello")]
    if variant == "text":        return [Text("red text", style="red")]
    if variant == "text_bold":   return [Text("bold hi", style="bold")]
    if variant == "panel":      return [Panel("hello")]
    if variant == "panel_title": return [Panel("hello", title="Title")]
    if variant == "table":
        # Same config as `table_simple` (HEAVY_HEAD, padding 0, Name/Data
        # width-4 columns, row abcd/efgh) so the raw is byte-identical to the
        # proven `table_simple` golden output.
        t = Table(box=HEAVY_HEAD, padding=(0, 0, 0, 0), header_style="")
        t.add_column("Name", width=4, no_wrap=True)
        t.add_column("Data", width=4, no_wrap=True)
        t.add_row("abcd", "efgh")
        return [t]
    if variant == "multi":       return [Text("first"), Text("second", style="red")]
    raise ValueError(f"unknown file_proxy variant: {variant}")


def render_file_proxy(args):
    # v0.7.0 — args = (variant, width). `rich.file_proxy.FileProxy` (file_proxy
    # .py:12-60) is a file-like proxy (`io.TextIOBase` subclass) wrapping a real
    # file plus an owning `Console`: `write` partitions text on newlines,
    # ANSI-decodes each COMPLETE line via `AnsiDecoder.decode_line`, joins the
    # decoded lines with `Text("\n")`, and `console.print`s the result
    # (`end="\n"`); `flush` prints any trailing partial line.
    #
    # This case builds the variant's renderable(s), renders each to raw ANSI
    # (`capture_ansi`-style, `end=""`), and concatenates with EXACTLY ONE
    # trailing newline per renderable (appended only if the raw does not
    # already end with `"\n"`; `Panel`/`Table` `renderConsole` yield a trailing
    # `"\n"` themselves, `Text` does not). The concatenation is fed to a real
    # `FileProxy(console, file)` in a single `write` + `flush`.
    #
    # `FileProxy` is a PERFECT round-tripper when the input ends with `"\n"`
    # (each complete line decodes to a `Text` whose `console.print` re-emits
    # the same ANSI — the decode inverts the encode), so the FileProxy output
    # equals the concatenated source ANSI. A `Text` object passed to
    # `console.print` is NOT run through the highlighter (only plain strings
    # are; collect_renderables console.py:1500-1587), so the round-trip is
    # byte-stable even for content with digits/quotes.
    #
    # The returned `Text.from_ansi(fp_out)` lets `capture_ansi` reproduce
    # `fp_out` bytes: `Text.from_ansi` + `console.print(end="")` is itself a
    # perfect round-trip (probed byte-identical for all variants). The Nim
    # `renderFileProxyAnsi` round-trips the same source ANSI through the Nim
    # `FileProxy` (its `AnsiDecoder.decodeLine` + `Console.print`/`renderBuffer`
    # path is byte-identical to rich's), so the two outputs match byte-for-byte.
    variant, width = args
    renderables = _fp_renderables(variant)
    ansi_in = ""
    for r in renderables:
        raw = _fp_raw_str(r, width)
        ansi_in += raw + ("" if raw.endswith("\n") else "\n")
    inner_buf = io.StringIO()
    inner = Console(file=inner_buf, force_terminal=True, color_system="truecolor",
                    width=width, height=24, record=False, soft_wrap=False,
                    legacy_windows=False)
    fp = FileProxy(inner, io.StringIO())
    fp.write(ansi_in)
    fp.flush()
    fp_out = inner_buf.getvalue()
    return Text.from_ansi(fp_out)


def _fp_raw_str(renderable, width):
    # v0.7.0 — render a renderable to raw ANSI (str, end="") at `width`, the
    # faithful source for the FileProxy round-trip (mirrors `capture_ansi` but
    # returns str so `FileProxy.write` can consume it).
    buf = io.StringIO()
    c = Console(file=buf, force_terminal=True, color_system="truecolor",
                width=width, height=24, record=False, soft_wrap=False,
                legacy_windows=False)
    c.print(renderable, end="")
    return buf.getvalue()


def _lr_renderables(variant):
    # v0.7.0 — the renderable a `live_render_*` variant wraps. Each variant
    # maps to one renderable (the same config the matching existing case uses,
    # so the inner render is byte-identical); mirrored byte-for-byte by
    # `golden_nim.nim`'s `renderCase` `live_render_*` dispatch.
    if variant == "simple":      return Text("hello")
    if variant == "text_styled": return Text("red text", style="red")
    if variant == "text_bold":   return Text("bold hi", style="bold")
    if variant == "panel":       return Panel("hello")
    if variant == "table":
        # Same config as `table_simple` (HEAVY_HEAD, padding 0, Name/Data
        # width-4 columns, row abcd/efgh).
        t = Table(box=HEAVY_HEAD, padding=(0, 0, 0, 0), header_style="")
        t.add_column("Name", width=4, no_wrap=True)
        t.add_column("Data", width=4, no_wrap=True)
        t.add_row("abcd", "efgh")
        return t
    if variant == "columns":
        # Same config as `columns_simple` (a/b/c, padding (0,1)).
        return Columns([Text("a"), Text("b"), Text("c")], padding=(0, 1))
    if variant == "multi":
        return Columns([Text("first"), Text("second", style="red")], padding=(0, 1))
    raise ValueError(f"unknown live_render variant: {variant}")


def render_live_render(args):
    # v0.7.0 — args = (variant, width). `rich.live_render.LiveRender`
    # (live_render.py:18-116) wraps a renderable so it may be updated in place;
    # `__rich_console__` renders the inner renderable to lines
    # (`console.render_lines(..., pad=False)`, live_render.py:92), applies the
    # resolved `style`, captures the shape, applies `vertical_overflow`
    # crop/ellipsis, and yields the lines joined by `"\n"` between (NOT after
    # the last). `capture_ansi` does `console.print(LiveRender(R), end="")`,
    # which equals `console.print(R, end="")` minus exactly one trailing
    # `"\n"` (when `R` yields one — Panel/Table/Columns do; Text does not). The
    # Nim `renderLiveRenderAnsi` wraps the same renderable in a real Nim
    # `LiveRender` and renders via the real `Console`, reproducing the bytes.
    variant, width = args
    return LiveRender(_lr_renderables(variant))


RENDERERS = {
    "text": render_text,
    "spans": render_spans,
    "rule": render_rule,
    "control": render_control,
    "filesize": render_filesize,
    "table": render_table,
    "table_advanced": render_table_advanced,
    "box": render_box,
    "padding": render_padding,
    "markup": render_markup,
    "panel": render_panel,
    "tree": render_tree,
    "emoji": render_emoji,
    "markdown": render_markdown,
    "bar": render_bar,
    "align": render_align,
    "columns": render_columns,
    "syntax": render_syntax,
    "spinner": render_spinner,
    "pretty": render_pretty,
    "status": render_status,
    "logging": render_logging,
    "progress": render_progress,
    "progress_advanced": render_progress_advanced,
    "json": render_json,
    "traceback": render_traceback,
    "prompt": render_prompt,
    "abc": render_abc,
    "styled": render_styled,
    "ratio": render_ratio,
    "layout": render_layout,
    "ansi": render_ansi,
    "constrain": render_constrain,
    "group": render_group,
    "scope": render_scope_case,
    "region": render_region,
    "screen": render_screen,
    "measure": render_measure,
    "repr": render_repr,
    "theme": render_theme,
    "terminal_theme": render_terminal_theme,
    "errors": render_errors,
    "file_proxy": render_file_proxy,
    "live_render": render_live_render,
}


def capture_ansi(renderable, case_name, width=80, theme=None):
    """Render a renderable through Console, capture raw ANSI bytes. `width`
    is the Console width (default 80); Panel cases pass their own width so
    the panel fills it (expand=True), matching golden_cases.case_width.
    `theme` (v0.6.0) — an optional `rich.theme.Theme` passed to `Console(theme=)`
    so the theme cases apply a custom Theme to the renderable via the real
    Console theme stack (the only byte-stable way to exercise a custom
    `Theme`; printing a `Theme` object yields a non-deterministic address)."""
    import io as _io
    # Rich 15.0.0 writes str to file (even with force_terminal); use StringIO,
    # then encode to bytes for byte-exact comparison with Nim.
    buf = _io.StringIO()
    kw = dict(file=buf, force_terminal=True, color_system="truecolor",
              width=width, height=24, record=False, soft_wrap=False,
              legacy_windows=False)
    if theme is not None:
        kw["theme"] = theme
    console = Console(**kw)
    console.print(renderable, end="")
    return buf.getvalue().encode("utf-8")


def main():
    if len(sys.argv) < 2:
        print("usage: golden_ref.py <case>", file=sys.stderr)
        print("cases:", ", ".join(case_names()[:8]) + " ...", file=sys.stderr)
        sys.exit(2)
    name = sys.argv[1]
    case = get_case(name)
    if case is None:
        print(f"unknown case: {name}", file=sys.stderr)
        sys.exit(3)

    cname, kind, args = normalize_case(case)
    if kind not in RENDERERS:
        print(f"unknown kind: {kind}", file=sys.stderr)
        sys.exit(4)

    # v0.6.0 — the "theme" kind returns a (renderable, theme) pair so a
    # custom `Theme` can be applied to the renderable via the Console theme
    # stack (the byte-stable way to exercise `Theme`). Other kinds return a
    # plain renderable (including `Region`/`Measurement` `NamedTuple`s, which
    # ARE tuples — so the unpack is gated on `kind == "theme"`, NOT on
    # `isinstance(result, tuple)`, to avoid mis-unpacking a NamedTuple).
    if kind == "theme":
        renderable, theme = RENDERERS[kind](args)
        ansi = capture_ansi(renderable, cname, case_width(case), theme=theme)
    else:
        renderable = RENDERERS[kind](args)
        ansi = capture_ansi(renderable, cname, case_width(case))
    # Write raw bytes to stdout
    sys.stdout.buffer.write(ansi)
    sys.stdout.buffer.flush()


if __name__ == "__main__":
    main()
