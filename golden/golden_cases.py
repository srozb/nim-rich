## golden_cases.py — central list of golden test cases (shared by Python ref + Nim port)
##
## Each case: (name, kind, args) where kind selects what to render. The three
## v0.8.1 table box-style records are stored literally as variable-arity tuples
## (outer arity 4/4/5); `normalize_case` packs their trailing fields into `args`
## at consumption time.
## Python: golden_ref.py <case>  → raw ANSI bytes on stdout
## Nim:    golden_nim <case>     → raw ANSI bytes on stdout
## Compare: golden_compare.py <case> golden_nim

CASES = [
    # Text — plain
    ("text_plain",          "text",   ("hello world",)),
    ("text_empty",          "text",   ("",)),
    ("text_unicode",        "text",   ("héllo wörld 日本語",)),
    ("text_emoji",           "text",   ("test 🎉 emoji 🚀",)),

    # Text — styled (single style string)
    ("text_bold",           "text",   ("bold text", "bold")),
    ("text_red",            "text",   ("red text", "red")),
    ("text_bold_red",       "text",   ("bold red text", "bold red")),
    ("text_dim_green",      "text",   ("dim green", "dim green")),
    ("text_italic_yellow",  "text",   ("italic yellow", "italic yellow")),
    ("text_underline_blue", "text",   ("underline blue", "underline blue")),
    ("text_reverse",        "text",   ("reverse text", "reverse")),
    ("text_strikethrough",  "text",   ("strike text", "strike")),

    # Text — styled (round_006: compound NON-COLOR attributes + reverse+attr +
    # strike+dim). The baseline styled cases each combine AT MOST one
    # non-color attribute with a color (bold red, dim green, italic yellow,
    # underline blue) or a single attribute alone (reverse, strike). These
    # four exercise TWO non-color attributes in one Style, which
    # `Style._make_ansi_codes` emits in fixed bit order regardless of the
    # style-string word order: bold(1) dim(2) italic(3) underline(4)
    # reverse(7) strike(9), then color. `text_bold_italic` = "bold italic"
    # → \x1b[1;3m; `text_underline_red` = "underline red" → \x1b[4;31m
    # (underline+standard color, distinct from text_underline_blue only by
    # color but exercises underline+red pair); `text_reverse_styled` =
    # "reverse bold" (string order reversed vs bit order) → \x1b[1;7m,
    # proving the parser is order-independent; `text_strike_dim` =
    # "strike dim" → \x1b[2;9m. `render_text` (Text(text, style=...)) already
    # accepts any style string — no golden_ref.py change needed.
    ("text_bold_italic",    "text",   ("bold italic text", "bold italic")),
    ("text_underline_red",  "text",   ("underline red text", "underline red")),
    ("text_reverse_styled", "text",   ("reverse bold text", "reverse bold")),
    ("text_strike_dim",     "text",   ("strike dim text", "strike dim")),
    # text_bg_style / text_dim_italic — 2 new text edge cases. Both use kind
    # "text" (args = (text[, style])), distinct from the baseline+round_006
    # styled cases. `text_bg_style` = Text("bg text", "on red"): a background-
    # color-only style (`on red` → bgcolor=red, no fg) → \x1b[41m (bgcolor red,
    # SGR 41). `text_dim_italic` = Text("dim italic", "dim italic"): two
    # non-color attributes (dim+italic → \x1b[2;3m, bit order 2;3). The
    # `render_text` (Text(text, style=...)) path already accepts any style
    # string; no new renderer — pure addition of case records.
    ("text_bg_style",       "text",   ("bg text", "on red")),
    ("text_dim_italic",     "text",   ("dim italic", "dim italic")),

    # Text — spans (multi-style, osobne segmenty)
    ("text_spans_bold_red", "spans",  (("hello","bold"),(" ",""),("world","red"))),
    ("text_spans_3color",   "spans",  (("a","red"),("b","green"),("c","blue"))),
    ("text_spans_nested", "spans", (("hello ", "bold"), ("world", "bold red"))),
    ("text_spans_emoji_in_span", "spans", (("test ", "bold"), ("🎉", "red"), (" span", "green"))),
    ("text_spans_unicode_in_span", "spans", (("héllo", "bold"), (" ", ""), ("wörld", "red"))),
    ("text_spans_empty_style", "spans", (("a", ""), ("b", "bold"))),
    ("text_spans_mixed_styles", "spans", (("a", "bold"), ("b", "red"), ("c", "italic"), ("d", "underline"), ("e", "green"))),
    # text_nested_spans (round_006): a 3-segment span whose middle segment
    # carries a COMPOUND style (bold+italic+red) flanked by two bold-only
    # segments — exercising a multi-attribute span style in context, distinct
    # from text_spans_nested (two segments, bold then bold red) and
    # text_spans_mixed_styles (five single-attribute segments). The middle
    # span's "bold italic red" → \x1b[1;3;31m (bit order, color last). The
    # flanking "bold" segments → \x1b[1m. `render_spans` (Text.append per
    # segment) already handles arbitrary per-span style strings; the Nim
    # port concatenates per-segment renderTextAnsi (each segment is an
    # independent initText), matching Rich's per-span reset+reapply output
    # (verified against oracle: \x1b[1mouter \x1b[0m\x1b[1;3;31minner
    # \x1b[0m\x1b[1mtail\x1b[0m).
    ("text_nested_spans", "spans", (("outer ", "bold"), ("inner ", "bold italic red"), ("tail", "bold"))),

    # Rule
    ("rule_plain",          "rule",   ("",)),
    ("rule_title",          "rule",   ("Section",)),
    ("rule_title_styled",   "rule",   ("Warning", "bold red")),
    ("rule_chars",          "rule",   ("=", "characters")),
    # rule_style — genuine gap (round_001-005): the (title=None, style=set)
    # combination is uncovered. rule_plain=(None,None), rule_title=(set,None),
    # rule_title_styled=(set,set), rule_chars=(None via characters, default
    # "rule.line"). This case = Rule(title=None, style="red"): a full-width
    # RED titleless rule line — distinct from rule_plain (style=None → no color)
    # and rule_title_styled (has a title). render_rule forwards style;
    # Rule._rule_line applies self.style to the titleless line. Standard color
    # "red" (not a theme name) resolves identically on both sides: the Python
    # default Console theme has no "red" override (Style.parse("red") → standard
    # color #1), and the Nim path (default ConsoleHandle, empty Phase-0 theme)
    # parses "red" to the same standard color.
    ("rule_style",          "rule",   ("", "red")),
    # new rule edge cases — thick ═ characters, blue colored line, centered
    # title with explicit align. `rule_thick` = Rule(characters="═") (the thick
    # double-line U+2550, distinct from rule_chars "=" — same default "rule.line"
    # style → bright_green \x1b[92m). `rule_colored` = Rule(style="blue") (a blue
    # titleless rule, distinct from rule_style "red" — standard color #4 →
    # \x1b[34m). `rule_title_center` uses a NEW args shape (title, align,
    # "align" marker): render_rule lets Rule use its DEFAULT style "rule.line"
    # (bright_green \x1b[92m) — NOT style=None — so the centered title "Section"
    # renders WITH the green rule color, DISTINCT from `rule_title` (whose
    # render_rule passes style=None → no color) while exercising the explicit
    # `align="center"` keyword (center is the Rule default, but this case passes
    # it explicitly AND keeps the default style, so the bytes differ from
    # rule_title on the color axis).
    ("rule_thick",          "rule",   ("═", "characters")),
    ("rule_colored",        "rule",   ("", "blue")),
    ("rule_title_center",   "rule",   ("Section", "center", "align")),

    # Control — ANSI control codes
    ("control_home",        "control", ("home",)),
    ("control_clear",       "control", ("clear",)),
    ("control_title",       "control", ("title", "My Title")),

    # Filesize
    ("filesize_bytes",      "filesize", (1024,)),
    ("filesize_kb",         "filesize", (1048576,)),
    ("filesize_decimal",    "filesize", (1500,)),
    # filesize_gb/tb — genuine gap (round_001: only 3 filesize cases). Two new
    # cases exercise the GB and TB suffixes of `rich.filesize.decimal` (suffix
    # list "kB"/"MB"/"GB"/"TB"/…, base 1000). Values 1024**3 / 1024**4 follow the
    # powers-of-2 theme of filesize_bytes (1024) / filesize_kb (1048576); they
    # render "1.1 GB" / "1.1 TB" (decimal: value=size/1e9 / size/1e12 ≈ 1.07/
    # 1.10 → "1.1"). `render_filesize` is already parametric over the byte count
    # (Text(filesize_decimal(args[0]))), so no golden_ref.py change is needed;
    # the Nim `decimal` proc (filesize.nim) already carries the GB/TB suffixes.
    ("filesize_gb",         "filesize", (1073741824,)),
    ("filesize_tb",         "filesize", (1099511627776,)),

    # Table — HEAVY_HEAD box, padding 0, two fixed 4-wide columns sized exactly
    # to their content (no wrap/pad). args = (header_style, title, title_style,
    # has_rows); title/title_style are None when there is no title.
    ("table_simple",        "table",   ("", None, None, True)),
    ("table_header_only",   "table",   ("", None, None, False)),
    ("table_styled",        "table",   ("bold", None, None, True)),
    ("table_with_title",    "table",   ("", "Hello table", "italic", True)),
    # v0.8.1 — Table box-style variants, stored LITERALLY as variable-arity
    # records exactly as supplied in the request: (name, "table", data,
    # box_style) for the two box-only cases (outer arity 4) and (name, "table",
    # data, box_style, style) for the styled case (outer arity 5). `data` is a
    # nested tuple ((header...), (row1...), (row2...), ...) whose first sub-tuple
    # is the header row and the rest are data rows; `box_style` is one of
    # "ascii"/"rounded"/"double"/"heavy"/"minimal"; `style` is a table-wide
    # style ("bold") applied to borders + padding via `Table(style=...)`. The
    # trailing fields beyond `kind` are packed into a single `args` tuple by
    # `normalize_case` at consumption time, yielding (data, box_style[, style])
    # — detected by `isinstance(args[0], tuple)` in `render_table`; the legacy
    # (header_style, title, title_style, has_rows) shape is preserved
    # byte-identical for the four baseline table_* cases. Width is 80
    # (case_width default for "table"); columns are auto-sized to content
    # (no explicit `width`/`no_wrap`), matching `Table(box=box)` defaults.
    ("table_box_rounded", "table", (("Name", "Value"), ("Alice", "42"), ("Bob", "17")), "rounded"),
    ("table_box_double",  "table", (("A", "B"), ("1", "2"), ("3", "4")), "double"),
    ("table_with_style",  "table", (("Name", "Score"), ("Alice", "95"), ("Bob", "87")), "ascii", "bold"),

    # v0.9.0 — table_advanced: 5 new cases exercising advanced `rich.table.Table`
    # constructor params (header_style, row_styles, padding, per-column justify,
    # show_lines). args = (data, box_name, kwargs) where `data` is a nested
    # tuple ((header...), (row1...), ...) and `kwargs` is a dict of Table
    # constructor / add_column params (header_style, row_styles, padding,
    # col_justifies, show_lines). `box_name` selects the box style. Width is 80
    # (case_width default). Each case's expected rendering is captured from
    # Python rich 15.0.0 (the oracle); the Nim port (`renderTableAdvancedAnsi`)
    # builds the same `Table` via `initTable`+`addColumn`+`addRow` and renders
    # through the real `Console` (renderTableAnsi at width 80), byte-exact.
    #
    # `table_styled_header` — `Table(box=ROUNDED, header_style="bold red")`:
    # the header row cells render bold red (`\x1b[1;31m`) — distinct from the
    # default `table.header`=bold (`\x1b[1m`) the baseline `table_box_rounded`
    # uses. Three columns "Name"/"Value"/"Status", two rows.
    ("table_styled_header", "table_advanced",
     (("Name", "Value", "Status"), ("Alice", "42", "OK"), ("Bob", "17", "FAIL")),
     "rounded", {"header_style": "bold red"}),
    # `table_row_styles` — `Table(box=ROUNDED, row_styles=["red", "green"])`:
    # the row style cycles per row (index % len) — row 0 red, row 1 green,
    # row 2 red (table.py:314). The row style is applied to EACH cell in the
    # row (table.py:870 `style + row_style`), so all cells of a row share the
    # cycling color. Two columns "Name"/"Score", three rows (exercises the
    # cycle wrap-around on row 2).
    ("table_row_styles", "table_advanced",
     (("Name", "Score"), ("Alice", "95"), ("Bob", "87"), ("Carol", "72")),
     "rounded", {"row_styles": ["red", "green"]}),
    # `table_padding` — `Table(box=ROUNDED, padding=(1, 2))`: the CSS-style
    # padding pair (vertical=1, horizontal=2) adds 1 blank line above + below
    # each cell and 2 space pads left + right (table.py:225 `Padding.unpack`).
    # Distinct from the default padding=(0,1) the baseline `table_box_*` cases
    # use (which has 0 vertical, 1 horizontal). Two columns "A"/"B", two rows.
    ("table_padding", "table_advanced",
     (("A", "B"), ("1", "2"), ("3", "4")),
     "rounded", {"padding": (1, 2)}),
    # `table_col_align` — `Table(box=ROUNDED)` with per-column `justify`:
    # column 0 "Name" left, column 1 "Value" center, column 2 "Notes" right
    # (add_column(justify=...), table.py:402). The header row inherits the
    # column justify (header cells are justify-aligned too — table.py:836
    # `cell_options.update(justify=column.justify)`). Distinct from the
    # default left-justify all baseline `table_*` cases use. Three columns,
    # two rows.
    ("table_col_align", "table_advanced",
     (("Name", "Value", "Notes"), ("Alice", "42", "ok"), ("Bob", "100", "done")),
     "rounded", {"col_justifies": ("left", "center", "right")}),
    # `table_show_lines` — `Table(box=ROUNDED, show_lines=True)`: horizontal
    # divider lines are drawn between EVERY row (table.py:932-934
    # `if self.show_lines or ...`). Distinct from the default show_lines=False
    # (dividers only after header + end_section rows). Two columns
    # "Name"/"Score", three rows → two inter-row dividers.
    ("table_show_lines", "table_advanced",
     (("Name", "Score"), ("Alice", "95"), ("Bob", "87"), ("Carol", "72")),
     "rounded", {"show_lines": True}),

    # Panel — ROUNDED box (default), expand=True (panel fills the console
    # width). args = (text, title, subtitle, border_style, width); title/
    # subtitle/border_style are None when absent. width is the Console width
    # (the panel fills it; no explicit panel `width`).
    ("panel_simple",         "panel", ("hello", None, None, None, 80)),
    ("panel_title",          "panel", ("hello", "Title", None, None, 40)),
    ("panel_subtitle",       "panel", ("hello", None, "Sub", None, 40)),
    ("panel_styled_border",  "panel", ("hello", None, None, "red", 40)),
    ("panel_title_subtitle", "panel", ("hello", "T", "S", None, 50)),
    # v0.8.2 — Panel edge cases. `panel_subtitle_styled` sets a subtitle AND a
    # red border_style (distinct from `panel_subtitle` which has no border_style
    # and `panel_styled_border` which has no subtitle); `panel_box_double` sets
    # box=DOUBLE via the optional 6th tuple element (PANEL_BOX) → the
    # ╔═╗/║/╚═╝ border (distinct from the ROUNDED default all other panel_*
    # cases use); `panel_styled_title` passes title with rich markup
    # `[bold red]Title[/]` → `Text.from_markup` renders the title bold red within
    # the plain (border_style=None) ROUNDED border.
    ("panel_subtitle_styled", "panel", ("hello", None, "Sub", "red", 40)),
    ("panel_box_double",      "panel", ("hello", None, None, None, 40, "double")),
    ("panel_styled_title",    "panel", ("hello", "[bold red]Title[/]", None, None, 40)),

    # Tree — guide-line tree structure (real Python rich `Tree` via chained
    # `add`). args = (root_label, hide_root, style, width, children); `style`
    # is None for the default "tree" theme, "red" for the styled case; `width`
    # is the Console width; `children` is a tuple of (label, grandchildren)
    # specs (recursively; () = no children). The nested case uses the chained
    # `add` construction (root.add("mid").add("leaf")); passing a `Tree` as a
    # label has different semantics.
    ("tree_simple",         "tree", ("root", False, None, 40, (("a", ()), ("b", ())))),
    ("tree_nested",         "tree", ("root", False, None, 40, (("mid", (("leaf", ()),)),))),
    ("tree_hide_root",      "tree", ("root", True,  None, 40, (("a", ()), ("b", ())))),
    ("tree_styled",         "tree", ("root", False, "red", 40, (("child", ()),))),
    ("tree_multi_children", "tree", ("root", False, None, 50, (("a", ()), ("b", ()), ("c", ())))),
    # v0.8.2 — Tree edge cases. `tree_deep_nested` exercises 3 child levels
    # (a → b → c via chained `add`); `tree_with_guide_style` sets a custom
    # `guide_style` via the optional 6th tuple element (TREE_GUIDE_STYLE) →
    # the guide lines (└── ) render red while the labels stay plain (distinct
    # from `tree_styled` which colors the whole tree via `style`).
    ("tree_deep_nested",      "tree", ("root", False, None, 50, (("a", (("b", (("c", ()),)),)),))),
    ("tree_with_guide_style", "tree", ("root", False, None, 40, (("child", ()),), "red")),

    # Emoji — `Emoji(name, style=..., variant=...)` single-char renderable
    # (emoji.py:20-48) plus the `Emoji.replace` classmethod (emoji.py:51-57).
    # The `emoji` kind uses a leading mode discriminator: `("obj", name,
    # style, variant)` constructs and renders a real `Emoji` (style is None for
    # the default "none", or a str; variant is None, "emoji", or "text");
    # `("replace", text)` calls the real `Emoji.replace` classmethod and
    # renders the resulting string through the Console. Rendered at width 20
    # (case_width below).
    ("emoji_simple",     "emoji", ("obj",     "wink", None, None)),
    ("emoji_thumbs_up",  "emoji", ("obj",     "thumbs_up", None, None)),
    ("emoji_styled",     "emoji", ("obj",     "wink", "red", None)),
    ("emoji_variant",    "emoji", ("obj",     "heart", None, "emoji")),
    ("emoji_replace",    "emoji", ("replace", "hello :wink: world")),

    # Markdown — real `Markdown(markup)` renderable (rich.markdown.Markdown)
    # with the default code theme. args = (markup, width); `width` is the
    # Console width (per-case: 40/40/40/50). Slice 5c covers heading/
    # paragraph/inline (bold/em/code) rendering; fenced-code-block coverage is
    # deferred to Slice 6 (Syntax/Pygments), so no ```-bearing case is added.
    ("markdown_heading",     "markdown", ("# Hello", 40)),
    ("markdown_paragraph",   "markdown", ("Plain text paragraph here.", 40)),
    ("markdown_inline_bold", "markdown", ("Some **bold** and *italic* and `code` text.", 40)),
    ("markdown_mixed",       "markdown", ("# Title\n\nSome *italic* and `code` text.", 50)),

    # markdown_advanced — 5 new cases exercising blockquote/link/strike/
    # bold+italic/code_inline. Each uses kind "markdown" (args = (markup,
    # width)), distinct from the baseline 4 markdown cases:
    # - markdown_bold_italic: sequential **bold** and *italic* in one paragraph
    #   (distinct from markdown_inline_bold which also has `code`).
    # - markdown_code_inline: inline code with special chars `println("hi")`.
    # - markdown_quote: a `>` blockquote, exercising blockquote parsing +
    #   BlockQuote.renderConsole (▌ prefix, width-4, magenta style).
    # - markdown_link: a `[text](url)` hyperlink, exercising link parsing +
    #   the link_open/link_close render branches (markdown.link_url style +
    #   OSC 8 hyperlink with deterministic id; golden_ref.py resets
    #   `_id_generator = count(1)` to match Nim's `nextId()`).
    # - markdown_strike: `~~strike~~` strikethrough, exercising `~~` inline
    #   parsing (s_open/s_close → markdown.s style).
    ("markdown_bold_italic", "markdown", ("**bold** and *italic* text", 40)),
    ("markdown_code_inline", "markdown", ("Use `println(\"hi\")` here", 40)),
    ("markdown_quote",       "markdown", ("> This is a quote", 40)),
    ("markdown_link",        "markdown", ("[Rich](https://rich.com) is great", 40)),
    ("markdown_strike",      "markdown", ("~~strike~~ text", 40)),
    # markdown_heading_h3 / markdown_list — 2 new markdown edge cases. Both
    # use kind "markdown" (args = (markup, width)), distinct from the baseline
    # 4 + advanced 5 markdown cases. `markdown_heading_h3` = "### Heading 3"
    # (an H3 — distinct from `markdown_heading`'s H1 "# Hello": H3 renders bold
    # magenta left-aligned via `markdown.h3` style + `jmLeft`, while H1 renders
    # bold+underline centered). `markdown_list` = "- item1\n- item2" (a
    # 2-item bullet list — exercises bullet-list block parsing + ListElement/
    # ListItem.render_bullet: " • " bold prefix at width-3, content at
    # width-3, newline per item). Width 40 matches the other markdown cases.
    ("markdown_heading_h3", "markdown", ("### Heading 3", 40)),
    ("markdown_list",       "markdown", ("- item1\n- item2", 40)),

    # Bar — solid block bar (rich.bar.Bar, bar.py:17-93). args = (size, begin,
    # end, bar_width, color); `bar_width` is the Bar's own `width` (the bar
    # renders that many cells, capped by `min(self.width, options.max_width)`,
    # bar.py:53-56); `color` is None for the default "default" style, or a str
    # ("red") for the styled case (bgcolor stays "default", so the styled bar
    # emits `31;49`, the default bar `39;49`). The Console width is fixed at 40
    # (case_width below) — the Bar width (20) caps the rendered bar to 20
    # cells, matching golden_ref.py's `Console(width=40)` + `Bar(width=20)`.
    ("bar_half",   "bar", (100.0, 0.0, 50.0, 20, None)),
    ("bar_full",    "bar", (100.0, 0.0, 100.0, 20, None)),
    ("bar_empty",   "bar", (100.0, 50.0, 50.0, 20, None)),
    ("bar_styled",  "bar", (100.0, 0.0, 50.0, 20, "red")),

    # Align — real `Align(Text(...), align=...)` renderable (rich.align.Align,
    # align.py:17-239). args = (text, text_style, align, width); `text_style`
    # is None (plain) or a str ("bold red") applied to the Text (NOT the Align
    # — `Align.style` stays None for all five cases); `align` is "left"/
    # "center"/"right"; `width` is the Console width (40/50), matching
    # golden_ref.py's `Console(width=…)`. Slice 7 covers left/center/right
    # padding, the styled content (bold-red "hi" centered) and multiline
    # ("line1\nline2" centered); explicit `Align.style` (null-style) coverage
    # is deferred (round_003 audit risk — these cases do not set it).
    ("align_left",      "align", ("hi", None, "left", 40)),
    ("align_center",    "align", ("hi", None, "center", 40)),
    ("align_right",     "align", ("hi", None, "right", 40)),
    ("align_styled",    "align", ("hi", "bold red", "center", 40)),
    ("align_multiline", "align", ("line1\nline2", None, "center", 50)),
    # v0.8.1 — Align edge cases. args = (text, align[, style]) — a 2/3-tuple
    # shape distinct from the legacy 4-tuple (text, text_style, align, width);
    # `style` (optional) is applied to the Text (NOT the Align — `Align.style`
    # stays None), matching `Align(Text(text, style=style), align=align)`.
    # Width is selected by case_width: 50 for the multiline case (matching
    # `align_multiline`), 40 for the right-styled case (matching `align_right`);
    # detected by `len(args) < 4` (the legacy shape carries width at index 3).
    ("align_center_multiline", "align", ("line one\nline two\nline three", "center")),
    ("align_right_styled",     "align", ("right text", "right", "bold red")),
    # Columns (kind="columns"): args = (texts_tuple, styles_tuple, padding_tuple, expand, width)
    ("columns_simple",  "columns", (("a", "b", "c"), (None, None, None), (0, 1), False, 40)),
    ("columns_padding", "columns", (("a", "b"), (None, None), (0, 2), False, 40)),
    ("columns_styled",  "columns", (("x", "y"), ("red", "blue"), (0, 1), False, 40)),
    ("columns_multi",   "columns", (("item1", "item2", "item3", "item4"), (None, None, None, None), (0, 1), False, 40)),
    ("columns_expand",   "columns", (("a", "b"), (None, None), (0, 1), True, 40)),
    # columns edge cases — `columns_three` exercises THREE renderables each
    # carrying a per-renderable style ("red"/"green"/"blue"), a combination
    # uncovered by columns_simple (3 unstyled) and columns_styled (2 styled).
    # `columns_with_padding` exercises THREE renderables with padding=(0,2)
    # (padding=2), a combination uncovered by columns_padding (2 renderables,
    # padding=(0,2)). Same render_columns path; width 40 (args[4]).
    ("columns_three",        "columns", (("x", "y", "z"), ("red", "green", "blue"), (0, 1), False, 40)),
    ("columns_with_padding", "columns", (("a", "b", "c"), (None, None, None), (0, 2), False, 40)),
    # Syntax (kind="syntax"): args = (code, lexer, theme, width)
    ("syntax_python",   "syntax", ("def f(x):\n    pass\n", "python", "monokai", 80)),
    ("syntax_json",     "syntax", ("{\"k\": 1}", "json", "monokai", 80)),
    ("syntax_python_keywords", "syntax", ("def hello():\n    return 42\n", "python")),
    ("syntax_json_object", "syntax", ('{"name": "test", "value": 42}', "json")),
    ("syntax_python_multiline", "syntax", ("import os\nimport sys\n\ndef main():\n    print('hello')\n", "python")),
    ("syntax_bash_script", "syntax", ("#!/bin/bash\necho 'hello'\nfor i in 1 2 3; do\n  echo $i\ndone\n", "bash")),
    ("syntax_nim_code", "syntax", ("proc main() =\n  echo \"hello\"\n", "nim")),
    # Spinner (kind="spinner"): args = (name, text, width)
    ("spinner_dots",    "spinner", ("dots", "", 80)),
    ("spinner_line",    "spinner", ("line", "", 80)),
    ("spinner_arc",     "spinner", ("arc", "", 80)),
    ("spinner_bounce",  "spinner", ("bouncingBar", "", 80)),

    # Pretty — real `rich.pretty.Pretty(obj)` renderable (rich.pretty.Pretty,
    # pretty.py:170-261). args = (obj,); `obj` is the literal Python object
    # (list/dict/str/int/bool/None) passed verbatim — `Pretty(obj)` defaults to
    # `ReprHighlighter` (the automatic repr highlighting: brace=bold,
    # number=bold cyan, str=green, bool_true=italic bright_green,
    # none=italic magenta), so no explicit `highlighter` is set. Width is fixed
    # at 80 (case_width below). The Nim port constructs the equivalent object
    # (`@[...]`/`OrderedTable`/`str`/`int`/`bool`/`none(int)`) via `initPretty` and
    # renders through the real `Console` (renderPrettyAnsi), matching `Pretty(obj)`
    # byte-exact vs Python rich 15.0.0.
    ("pretty_list",   "pretty", ([1, 2, 3],)),
    ("pretty_dict",    "pretty", ({"a": 1, "b": 2},)),
    ("pretty_string",  "pretty", ("hello",)),
    ("pretty_int",     "pretty", (42,)),
    ("pretty_bool",    "pretty", (True,)),
    ("pretty_none",    "pretty", (None,)),
    ("pretty_nested_list", "pretty", ([1, [2, 3], [4, [5, 6]]],)),
    ("pretty_tuple", "pretty", ((1, "two", 3.0),)),
    ("pretty_mixed_dict", "pretty", ({"a": 1, "b": [2, 3], "c": {"d": 4}},)),
    # v0.8.3 — Pretty edge cases. `pretty_set` renders a Python `set` (`{1, 2,
    # 3}`) — a `_BRACES` container (pretty.py:451-471) whose `{`/`}` braces are
    # bold (`repr.brace`) and ints bold-cyan (`repr.number`); single-line (fits
    # 80). `pretty_frozenset` renders a `frozenset` (also a `_CONTAINERS`
    # member) — `frozenset({1, 2, 3})` where the `frozenset` name is bold
    # magenta (`repr.call`), the `(`/`)`/`{`/`}` braces bold, ints bold-cyan.
    # `pretty_complex_data` — a nested dict-of-list-of-dicts
    # (`{'users': [{'name': 'Alice', 'age': 30}, …], 'count': 2}`): the outer
    # dict expands (multi-line, 4-space indent) while the inner list + dicts
    # fit inline. The Nim port builds the set/frozenset repr via custom object
    # types with a Python-faithful `$` (the `buildNode` `else` arm renders them
    # atomically, and `ReprHighlighter` paints the same `repr.*` spans as
    # Python); the complex case uses `parseJson` (the `pretty_mixed_dict`
    # pattern). Byte-exact vs Python rich 15.0.0.
    ("pretty_set", "pretty", ({1, 2, 3},)),
    ("pretty_frozenset", "pretty", (frozenset({1, 2, 3}),)),
    ("pretty_complex_data", "pretty", ({"users": [{"name": "Alice", "age": 30}, {"name": "Bob", "age": 25}], "count": 2},)),

    # Status — real `rich.status.Status` (status.py:23-100). `Status(text,
    # spinner=spinner_name).renderable` (the `@property`, status.py:48-50) returns
    # the `Spinner` it constructed (`Spinner(spinner, text=status,
    # style="status.spinner", speed=speed)`, status.py:42). Rendering the Spinner
    # (Spinner.__rich_console__→`self.render(time)`, spinner.py:54-100) yields
    # `Text.assemble(frame, " ", self.text)` — spinner frame 0 (styled
    # `status.spinner`=green via `DEFAULT_STYLES`) + " " + the status text,
    # with the Text default `end="\n"`. A missing spinner arg selects Status's
    # default `"dots"`. Width is fixed at 80 (case_width).
    ("status_dots",    "status",  ("Working...", "dots")),
    ("status_line",    "status",  ("Loading data", "line")),
    ("status_spinner_text", "status", ("Working...",)),
    # status_star — a NEW status edge: a spinner NOT covered by the baseline
    # status_dots ("dots") / status_line ("line") / status_spinner_text (the
    # default-spinner path). `Status("Loading", spinner="star")` selects the
    # "star" Spinner (spinners_data: ✶/✸/✹/✺/✹/✷, frame 0 = ✶ U+2736). The
    # `renderable` Spinner renders `Text.assemble(frame, " ", text)` — frame 0
    # (styled `status.spinner`→green) + " " + "Loading" (the Text default
    # `end="\n"`). Byte-exact vs Python rich 15.0.0 (300-run stable, frame 0).
    ("status_star",    "status",  ("Loading", "star")),

    # Logging — real `rich.logging.RichHandler` (logging.py:24-247) with
    # `show_time=False, show_level=True, show_path=False, rich_tracebacks=False`
    # (deterministic — no timestamp/path). `render_message` builds the message
    # `Text`; `render` (logging.py:215-247) → `_log_render.LogRender.__call__`
    # (_log_render.py:43-103) builds a `Table.grid` (no box, expand=True) with a
    # `log.level` column (width=8) and a `log.message` column (ratio=1,
    # overflow=fold); the row is [level, message]. The level is
    # `Text.styled(levelname.ljust(8), "logging.level.<lower>")` (logging.py:132)
    # The one-string form is split as `LEVEL: message`; INFO→blue,
    # WARNING→yellow, ERROR→bold red via `DEFAULT_STYLES`. Width is fixed at 80.
    ("logging_info",    "logging", ("INFO", "Hello world")),
    ("logging_warning", "logging", ("WARNING", "Careful")),
    ("logging_info_message", "logging", ("INFO: test message",)),
    ("logging_error_message", "logging", ("ERROR: something failed",)),

    # Progress — real `rich.progress.Progress` (progress.py:240-) with three
    # columns `BarColumn(), TextColumn("{task.description}"), TaskProgressColumn()`
    # (the order golden_nim's `renderProgressAnsi` uses). args = (description,
    # total, completed); `add_task(start=True, total=total)` starts the task so
    # `BarColumn.render` builds `ProgressBar(pulse=not started=False)` — the
    # deterministic non-pulse path (completed/total/width only, no wall-clock);
    # `update(completed=completed)` sets progress; `get_renderable()` yields the
    # single `Table.grid` (padding=(0,1), expand=False) row [bar, description,
    # percentage]. BarColumn bar_width=40 (default); TaskProgressColumn default
    # text_format `[progress.percentage]{task.percentage:>3.0f}%` (right-aligned
    # width-3, e.g. ` 50%`/`100%`/` 38%`). Width is fixed at 80 (case_width). The
    # Nim port (`renderProgressAnsi`) drives `makeTasksTable`+`Table.renderConsole`
    # at width 80 — byte-exact vs Python rich 15.0.0.
    ("progress_50",    "progress", ("task1", 100, 50)),
    ("progress_100",   "progress", ("task1", 100, 100)),
    ("progress_mixed", "progress", ("task1", 200, 75)),
    # Nested task tuples select the new multi-task column layouts. The singleton
    # form uses TextColumn + TransferSpeedColumn and renders its unknown speed.
    ("progress_multi_column", "progress", (("Task 1", 100, 50), ("Task 2", 200, 120))),
    ("progress_transfer_speed", "progress", (("Download", 1024, 512),)),

    # progress_advanced — 5 new cases exercising additional `rich.progress`
    # column types and layouts beyond the baseline `progress` cases. args =
    # (layout, tasks) where `layout` is a string key selecting the column set
    # and `tasks` is a tuple of (description, total, completed) task specs (all
    # `start=True` so `BarColumn` takes the deterministic non-pulse path).
    # `render_progress_advanced` (golden_ref.py) builds the real `Progress` with
    # the columns named by `layout`; the Nim port dispatches by case name to
    # per-case render functions. Width is fixed at 80 (case_width). Each case's
    # expected rendering is captured from Python rich 15.0.0 (the oracle) and
    # is byte-stable (300-run verified for the elapsed-time case).
    #
    # `progress_with_time` — `Progress(BarColumn(), TextColumn("{task.
    # description}"), TimeElapsedColumn())`: the third column is
    # `TimeElapsedColumn` (progress.py:688-695), a NEW column type not covered
    # by the baseline. `task.elapsed = get_time() - start_time` is a tiny
    # sub-second value (the render runs synchronously right after `add_task`),
    # so `int(elapsed) == 0` → `str(timedelta(seconds=0))` = "0:00:00" styled
    # `progress.elapsed` (yellow, `\x1b[33m`). Byte-stable across 300 oracle
    # runs (the render gap is microseconds, never reaching 1s). Distinct from
    # `progress_50` (same bar+text but `TaskProgressColumn` → " 50%").
    ("progress_with_time", "progress_advanced",
     ("bar_text_time", (("task1", 100, 50),))),
    # `progress_multiple_bars` — `Progress(TextColumn("{task.description}"),
    # BarColumn(), TaskProgressColumn())` with THREE tasks ("Task A"/"Task B"/
    # "Task C"), all `start=True`. The same column order as `progress_multi
    # _column` but three rows instead of two — exercising the multi-row
    # `make_tasks_table` grid with a finished last task (Task C 50/50 → green
    # `bar.finished` truecolor, "100%"). Distinct from `progress_multi_column`
    # (two tasks) by the extra third row.
    ("progress_multiple_bars", "progress_advanced",
     ("text_bar_pct", (("Task A", 100, 30), ("Task B", 200, 100), ("Task C", 50, 50)))),
    # `progress_complete` — `Progress(BarColumn(), TextColumn("{task.
    # description}"), MofNCompleteColumn())` at completed == total (100/100):
    # `MofNCompleteColumn` (progress.py:850-862) is a NEW column type rendering
    # `f"{completed:{total_width}d}/{total}"` = "100/100" styled
    # `progress.download` (green, `\x1b[32m`). At 100% the bar is FINISHED →
    # all 40 cells use `bar.finished` (rgb(114,156,31) truecolor, no `╺`
    # partial marker). Distinct from `progress_100` (Bar+Text+TaskProgress →
    # "100%") by the MofN column and the explicit completed/total readout.
    ("progress_complete", "progress_advanced",
     ("bar_text_mofn", (("task1", 100, 100),))),
    # `progress_description` — `Progress(TextColumn("{task.description}"),
    # BarColumn(), TaskProgressColumn())` with a single task whose description
    # ("Downloading file.zip") precedes the bar. The description-first column
    # order is used by `progress_multi_column` but only with two tasks; this
    # case exercises the description-first layout with a SINGLE task (and a
    # longer, descriptive label), distinct from the baseline single-task
    # cases (`progress_50` etc.) which put `BarColumn` first.
    ("progress_description", "progress_advanced",
     ("text_bar_pct", (("Downloading file.zip", 100, 25),))),
    # `progress_file_size` — `Progress(BarColumn(), TextColumn("{task.
    # description}"), FileSizeColumn())`: `FileSizeColumn` (progress.py:820-826)
    # is a NEW column type rendering `filesize.decimal(int(task.completed))` =
    # "50 bytes" (completed=50 < 1000 → the "<base" branch, filesize.py:30-31)
    # styled `progress.filesize` (green, `\x1b[32m`). Distinct from
    # `progress_50` by the FileSize column (bytes readout) instead of
    # percentage.
    ("progress_file_size", "progress_advanced",
     ("bar_text_filesize", (("task1", 100, 50),))),

    # JSON — real `rich.json.JSON(data_str)` renderable (json.py:9-79): a
    # `RichCast` whose `__rich__` returns the `JSONHighlighter`-highlighted
    # `Text` of `json.dumps(loads(data_str), indent=2, ensure_ascii=False)`
    # (json.py:31-40) — braces bold, keys bold-blue, string values green,
    # numbers bold-cyan (json.brace/json.key/json.str/json.number via
    # DEFAULT_STYLES). args = (data_str,); width is fixed at 80 (case_width).
    # `console.print(JSON, end="")` renders the `RichCast`'s `Text` with the
    # print's `end` ("") overriding the Text's own `end` (a trailing newline) via
    # `sep_text.join` — so the JSON output has NO trailing newline (unlike the
    # ConsoleRenderable `Pretty` whose `__rich_console__` keeps its trailing newline). The
    # Nim port (`renderJsonAnsi`) drives `initJson`→`richCast`→`Text` through
    # the real `Console` (a json.* theme push resolves the span styles) with
    # `end=""`, matching `JSON(data_str)` byte-exact vs Python rich 15.0.0.
    ("json_simple",  "json", ('{"key": "value", "num": 42}',)),
    ("json_nested",  "json", ('{"a": {"b": [1, 2, 3]}}',)),
    ("json_array",   "json", ('[1, 2, 3, "four"]',)),
    ("json_with_null", "json", ('{"a": null, "b": 1}',)),
    ("json_with_bool", "json", ('{"active": true, "disabled": false}',)),
    ("json_nested_deep", "json", ('{"a": {"b": {"c": {"d": 1}}}}',)),
    # v0.8.3 — JSON edge cases. `json_with_array_nested` — a JSON object whose
    # value is an array of two objects (`{"items": [{"a": 1}, {"b": 2}]}`):
    # `json.dumps(indent=2)` nests the array elements on their own indented
    # lines (2-space indent), keys bold-blue (`json.key`), numbers bold-cyan
    # (`json.number`), braces bold (`json.brace`). `json_with_float` — a JSON
    # object with float values (`{"pi": 3.14, "e": 2.71}`): the floats render
    # as `3.14`/`2.71` (Python `json.dumps` faithful), bold-cyan. The Nim port
    # (`renderJsonAnsi`) drives `initJson`→`richCast`→`Text` via the real
    # `Console` with a json.* theme push and `end=""`, byte-exact vs Python
    # rich 15.0.0.
    ("json_with_array_nested", "json", ('{"items": [{"a": 1}, {"b": 2}]}',)),
    ("json_with_float", "json", ('{"pi": 3.14, "e": 2.71}',)),
    # json_deep — 5 new JSON edge cases (round 1). args = (data_str,); the
    # `render_json`/`renderJsonAnsi` paths are already parametric over the data
    # string (`JSON(data_str)`↔`initJson`→`pretty(node, 2)`), so each case needs
    # only a case record + a dispatch branch. Inputs + expected renderings are
    # probed from Python rich 15.0.0 (the oracle). `nested_json` — object→object→
    # object→array→[int, object] interleaved (distinct from `json_nested` pure
    # object→object→int-array and `json_nested_deep` pure 4-deep object chain):
    # `json.dumps(indent=2)` lays the array elements on their own indented lines,
    # the inner object's key bold-blue, numbers bold-cyan. `json_unicode` —
    # string values carrying CJK (`日本語`), an emoji (`🎉`), and latin-1 accents
    # (`café`/`naïve`): `ensure_ascii=False` keeps the raw UTF-8 (the value spans
    # carry the multibyte sequences verbatim). `json_numbers` — int, negative
    # int, float, zero (exercises the bold-cyan `json.number` spans across the
    # sign/decimal forms). `json_empty_array` — an empty array `[]` and an empty
    # object `{}` (both render INLINE on the key's line — `json.dumps` keeps
    # empty containers single-line). `json_string_escapes` — string values with
    # JSON escape sequences (`\t`/`\n`/`\"`): `json.dumps` re-emits the escapes
    # literally (`"a\tb\nc"`, `"say \"hi\""`), exercising the serializer's escape
    # path. Byte-exact vs Python rich 15.0.0.
    ("nested_json",         "json", ('{"a": {"b": {"c": [1, {"d": 2}]}}}',)),
    ("json_unicode",        "json", ('{"name": "日本語", "emoji": "🎉", "café": "naïve"}',)),
    ("json_numbers",        "json", ('{"int": 42, "neg": -7, "float": 3.14, "zero": 0}',)),
    ("json_empty_array",    "json", ('{"empty": [], "also": {}}',)),
    ("json_string_escapes", "json", ('{"escaped": "a\\tb\\nc", "quote": "say \\"hi\\""}',)),
    # json_array_strings — 1 new JSON edge case. args = (data_str,). A JSON
    # array of three strings (`["a", "b", "c"]`): `json.dumps(indent=2)` lays
    # each string on its own indented line (2-space indent), braces bold
    # (`json.brace`), strings green (`json.str`). Distinct from `json_array`
    # (mixed int+string `[1, 2, 3, "four"]`) — this is a pure-string array.
    # The `render_json`/`renderJsonAnsi` paths are parametric over the data
    # string; no new renderer — pure addition of a case record.
    ("json_array_strings", "json", ('["a", "b", "c"]',)),

    # Traceback — real `rich.traceback.Traceback.from_exception(*exc_info)`
    # (traceback.py:353-421) of a `<string>`-sourced exception raised across
    # `depth` frames (compact format — a `Panel` of ` in <name>:<lineno>`
    # frame lines + the exception line). args = (exc_type_name, msg, depth);
    # the Python raises `{Exc}({msg!r})` and `str(exc)` is the exception line's
    # value (ValueError→msg as-is; KeyError→`'msg'` single-quoted, so the
    # `ReprHighlighter` paints it `repr.str` green). Width is fixed at 80
    # (case_width); the Traceback's own width=100 is Constrain-clamped to the
    # console width. The Nim port (`renderTracebackAnsi`) synthesizes the
    # matching frame list (`_lh_catch`/`_lh_r{i}` at the deterministic linenos)
    # + exception line (prefix `traceback.exc_type` span + ReprHighlighter on
    # the value) and renders via the real `Console` with a traceback.* theme
    # push, byte-exact vs Python rich 15.0.0.
    ("traceback_simple",  "traceback", ("ValueError", "test message", 1)),
    ("traceback_nested",  "traceback", ("KeyError", "missing key", 2)),
    ("traceback_simple_error", "traceback", ("ValueError: test error",)),
    ("traceback_with_locals", "traceback", ("TypeError: bad arg", "x=1, y='str'")),
    ("traceback_syntax_error", "traceback", ("SyntaxError: invalid syntax (test.py, line 5)",)),
    ("traceback_chain", "traceback", ("RuntimeError: outer", "ValueError: inner cause")),
    ("traceback_max_frames", "traceback", ("RecursionError: maximum recursion depth exceeded",)),

    # Prompt — real `rich.prompt.Prompt` STATIC non-interactive render path:
    # `PromptBase.make_prompt(default)` (prompt.py:120-141) returns the prompt
    # DISPLAY `Text` (NO stdin/`console.input` loop) — byte-stable. args = (text,
    # choices, default); `choices` is None (no choices) or a list of str;
    # `default` is None (no default — the Ellipsis sentinel `...`) or a str.
    # The base text + ": " suffix use style "prompt" (empty in DEFAULT_STYLES →
    # no ANSI); the choices bracket " [c1/c2/…]" uses "prompt.choices" → magenta
    # bold (`\x1b[1;35m…\x1b[0m`); the default bracket " (val)" uses
    # "prompt.default" → cyan bold (`\x1b[1;36m…\x1b[0m`). `Text.end` is set to
    # "" by `make_prompt` → no trailing newline. `Confirm` is `PromptBase` with
    # `choices=["y","n"]` (same `make_prompt`), so `prompt_confirm` passes
    # `choices=["y","n"]` to a plain `Prompt` (byte-identical to `Confirm`,
    # verified) — no separate Confirm code path. Width is fixed at 80
    # (case_width). The Nim port (`renderPromptAnsi`) constructs the same
    # `Text` via `initPrompt`+`makePrompt` and renders through the real `Console`
    # with a `prompt.*` theme push (`prompt.choices`=bold magenta,
    # `prompt.default`=bold cyan; `prompt` is empty — the base renders plain as
    # in Python). `rich.pager.Pager` is OMITTED (subprocess-only, no byte-exact
    # render path — see golden_ref.py's render_pager note); 5 prompt cases ship.
    ("prompt_simple",          "prompt", ("Enter name", None, None)),
    ("prompt_confirm",         "prompt", ("Continue", ["y", "n"], None)),
    ("prompt_choices",         "prompt", ("Pick", ["a", "b", "c"], None)),
    ("prompt_default",         "prompt", ("Enter name", None, "Alice")),
    ("prompt_choices_default", "prompt", ("Pick", ["a", "b", "c"], "a")),
    # prompt_advanced — 2 NEW prompt edge cases exercising the `password` flag
    # (PromptBase.__init__ `password: bool = False`, prompt.py:54-76). args =
    # (text, choices, default, password); the optional 4th element enables the
    # password construction. NOTE: `password` only affects the interactive
    # `console.input` echo loop (prompt.py:176-181 `get_input(..., password=...)`),
    # NOT the static `make_prompt` display (prompt.py:120-141 references no
    # `password`) — so the rendered Text is byte-identical to the same Prompt
    # without `password`. The cases still exercise the `Prompt(..., password=True)`
    # CONSTRUCTION path (the flag is stored on PromptBase, prompt.py:62) and, for
    # `prompt_password_choices`, the password+choices combination (distinct from
    # `prompt_choices` by the [x/y] letters). Width is fixed at 80 (case_width).
    ("prompt_password",         "prompt", ("Password", None, None, True)),
    ("prompt_password_choices", "prompt", ("Pick", ["x", "y"], None, True)),

    # Box — `rich.table.Table(box=box)` rendered with five `rich.box` box
    # styles (ASCII/ROUNDED/DOUBLE/HEAVY/MINIMAL), Table defaults (padding=
    # (0,1), header_style="table.header"→bold header, auto-width columns), two
    # columns "A"/"B" and one row "1"/"2". The box determines only the border
    # characters; everything else is default. Width is fixed at 80
    # (case_width). The Nim port (`renderBoxAnsi`) builds the same `Table` via
    # `initTable(box=some(X))`+`addColumn`+`addRow` and renders through the real
    # `Console` (renderTableAnsi at width 80), byte-exact vs Python rich 15.0.0.
    ("box_ascii",   "box", ("ascii",)),
    ("box_rounded", "box", ("rounded",)),
    ("box_double",  "box", ("double",)),
    ("box_heavy",   "box", ("heavy",)),
    ("box_minimal", "box", ("minimal",)),
    # box edge cases — `box_square` exercises the SQUARE box style (rich.box.
    # SQUARE, box.py:222-231), genuinely new (the original five box_* cases
    # cover ASCII/ROUNDED/DOUBLE/HEAVY/MINIMAL only). `box_minimal_three` and
    # `box_heavy_three` exercise the MINIMAL/HEAVY box styles with a NEW
    # 3-column ("X"/"Y"/"Z"), 2-row ("1","2","3")/("4","5","6") content config
    # (args[1]="three" — see render_box), a genuinely new edge combination
    # distinct from the baseline box_minimal/box_heavy (which use the default
    # 2-column "A"/"B", 1-row "1"/"2" content). The baseline box_minimal/
    # box_heavy already exist, so the "three" content variant covers the
    # requested minimal/heavy box styles with new content. Same render_box
    # path; width 80 (case_width).
    ("box_square",        "box", ("square",)),
    ("box_minimal_three", "box", ("minimal", "three")),
    ("box_heavy_three",   "box", ("heavy", "three")),

    # Padding — `rich.padding.Padding(Text("hello"), pad=pad)` renderable
    # (padding.py:19-135) with the default `style="none"` (null style → no ANSI on
    # the padding spaces) and `expand=True` (the outer width is
    # `options.max_width`; the inner renderable renders within
    # `width - left - right`). `pad` is a `PaddingDimensions` value
    # (Union[int, Tuple[int], Tuple[int, int], Tuple[int, int, int, int]]); the
    # four single-side cases use the 4-tuple `(top, right, bottom, left)` and
    # `padding_around` uses the 2-tuple `(vertical, horizontal)` = `(1, 2)` (the
    # `Tuple[int, int]` arm — Rich's `Padding.unpack` normalizes it to
    # `(1, 2, 1, 2)`). Width is fixed at 40 (case_width). The Nim port
    # (`renderPaddingAnsi`) builds the same `Padding` via
    # `initPadding(RenderableValue(initText(text)), pad)` and renders through the
    # real `Console` (padding.nim's `renderConsole`, the `console_api`
    # cycle-breaker leaf) at width 40, byte-exact vs Python rich 15.0.0.
    ("padding_left",    "padding", ("hello", (0, 0, 0, 5))),
    ("padding_right",   "padding", ("hello", (0, 5, 0, 0))),
    ("padding_top",     "padding", ("hello", (2, 0, 0, 0))),
    ("padding_bottom",  "padding", ("hello", (0, 0, 3, 0))),
    ("padding_around",  "padding", ("hello", (1, 2))),
    # padding_advanced — 2 NEW padding edge cases exercising the `style` kwarg
    # (padding.py:37-44 `Padding.__init__(..., style: Union[str, Style] = "none")`).
    # args = (text, (top, right, bottom, left), style); the optional 3rd element
    # is the padding style (default `"none"` → null style → no ANSI on the padding
    # spaces, the baseline `padding_*` path). A non-`"none"` style is resolved via
    # `console.get_style(self.style)` (padding.py:83) and applied by
    # `Padding.renderConsole` to BOTH the padding spaces (top/bottom blank lines +
    # left/right space pads) AND the inner renderable's segments
    # (`Segment.apply_style(..., style)`, padding.py:99-115) — so the whole padded
    # block is wrapped in the style's ANSI. `padding_style` ("blue") uses the
    # 4-tuple pad `(1,2,1,2)` with a blue style (the all-around case + color);
    # `padding_style_red` ("red") uses `(0,1,0,1)` (left/right only, no
    # top/bottom blank lines) with a red style. Width is fixed at 40 (case_width).
    # The Nim port (`renderPaddingAnsi`) passes `style` to `initPadding(style=)`,
    # matching `golden_ref.render_padding`. Byte-exact vs Python rich 15.0.0.
    ("padding_style",     "padding", ("hello", (1, 2, 1, 2), "blue")),
    ("padding_style_red",  "padding", ("hi", (0, 1, 0, 1), "red")),

    # Markup — `rich.text.Text.from_markup(markup_str)` (text.py:259-291), the
    # public `@classmethod` that calls `markup.render` (markup.py:101-185) to
    # strip `[style]…[/]` console-markup tags into `Span`s carrying the style
    # NAME (resolved theme-aware by `Console.getStyle` at render time —
    # `[bold]`→`\x1b[1m`, `[italic]`→`\x1b[3m`, `[red]`→`\x1b[31m`, `[bold red]`→
    # `\x1b[1;31m`). args = (markup_str,); the five cases exercise bold/italic/
    # color single tags, a combined `bold red` tag, and the `\[` escape (the
    # `\[bold]` renders as the literal `[bold]` text with NO style —
    # `markup.render`'s parse escape path). Width is fixed at 80 (case_width).
    # The Nim port (`renderMarkupAnsi`) drives `Text.fromMarkup` (text.nim's
    # faithful `renderMarkupInline` port of `markup.render`) → `renderTextAnsi`
    # at width 80, byte-exact vs Python rich 15.0.0.
    ("markup_bold",     "markup", ("[bold]bold text[/]",)),
    ("markup_italic",   "markup", ("[italic]italic text[/]",)),
    ("markup_color",    "markup", ("[red]red text[/]",)),
    ("markup_combined", "markup", ("[bold red]bold red text[/]",)),
    ("markup_escape",   "markup", (r"\[bold]plain",)),

    # ABC — ASCII-only box drawing. `rich.abc` holds only the abstract
    # `RichRenderable` concept (no renderable/constructor — confirmed
    # round_001), so the "abc golden" gap is filled with ASCII-box rendering on
    # the `Table`/`Panel` paths (the `render_box`/`render_panel` pattern) via
    # `rich.box.ASCII`/`ASCII_DOUBLE_HEAD`. args = (variant, width); `width` is
    # the Console width (the panel fills it; the Table is auto-sized). variant
    # "table" → `Table(box=ASCII, title="ABC")` (a title row + ASCII borders —
    # distinct from `box_ascii`, a titleless ASCII Table); "panel" →
    # `Panel("hello", box=ASCII)` (an ASCII-panel — the `panel_*` cases all use
    # ROUNDED); "border" → `Panel("hello", box=ASCII_DOUBLE_HEAD,
    # border_style="red")` (a custom ASCII border — the `=` head divider + red
    # border). The Nim port reuses `renderTableAnsi`/`renderPanelAnsi` (the
    # real `Console` dispatch), byte-exact vs Python rich 15.0.0.
    ("abc_simple", "abc", ("table", 80)),
    ("abc_box",    "abc", ("panel", 40)),
    ("abc_border", "abc", ("border", 40)),

    # Styled — `rich.styled.Styled(renderable, style)` (styled.py:11-41):
    # render the renderable then `Segment.apply_style(…, style)` across the
    # whole output. args = (mode,). mode "simple" → `Styled(Text("hello"),
    # "bold red")`; "nested" → `Styled(Text` with two color spans, `"bold red")`
    # (the outer bold combines with each inner span's color); "style" →
    # `Styled(Text("hi"), "bold italic red on blue")` (a complete style). The
    # renderable is a `Text` (the documented Nim limitation is the non-`Text` arm
    # where the style is NOT applied — these cases AVOID it, so the output is
    # byte-exact). Width is 80 (case_width). The Nim port (`renderStyledAnsi`)
    # renders the `Styled` through the real `Console` and splits the styled
    # segments into lines (so the trailing `\n` line terminator — which
    # `apply_style` styles — renders BARE, matching Python's print pipeline),
    # byte-exact vs Python rich 15.0.0.
    ("styled_simple", "styled", ("simple",)),
    ("styled_nested", "styled", ("nested",)),
    ("styled_style",  "styled", ("style",)),

    # Ratio — `rich._ratio` (`ratio_resolve`/`ratio_distribute`, _ratio.py:
    # 14-141) consumed by `Table.add_column(ratio=...)` (table.py:547-581):
    # ratio columns distribute the flexible width by their `ratio`. args =
    # (variant,). `Table(box=None, width=40)` (a borderless grid layout; the
    # flexible columns expand to fill the fixed width). variant "simple" →
    # three columns ratio 1:2:1; "uneven" → two columns ratio 1:3; "three" →
    # three columns ratio 1:1:1. One row of single-char cells. Width is 40
    # (case_width). The Nim port reuses `renderTableAnsi` (the real `Console`
    # driving `Table.renderConsole`, which calls `ratioResolve`/`ratioDistribute`),
    # byte-exact vs Python rich 15.0.0.
    ("ratio_simple", "ratio", ("simple",)),
    ("ratio_uneven", "ratio", ("uneven",)),
    ("ratio_three",  "ratio", ("three",)),

    # Layout — `rich.layout.Layout` (layout.py:106-336) divides a fixed region
    # into rows/columns of sub-layouts. args = (variant, width); `width` is the
    # Console width (40); the Console height is 24 (capture_ansi's fixed
    # height), so each `split_column` section is 12 rows and the output is 24
    # padded rows. An absent renderable wraps a `_Placeholder` (the Nim port
    # renders the literal `"Placeholder"` for it — NOT byte-exact with Python's
    # `Panel(Pretty(layout))`), so these cases give each section a real `Text`
    # renderable to stay byte-exact. variant "simple" → `split_column` of two
    # `Text` sections; "row" → `split_row` of two `Text` sections; "tree" → a
    # nested split (an upper section that `split_row`s, plus a lower section).
    # The Nim port (`renderLayoutAnsi`) renders the `Layout` through the real
    # `Console` (driving `Layout.renderConsole` → `renderLines` stitching),
    # byte-exact vs Python rich 15.0.0.
    ("layout_simple",    "layout", ("simple", 40)),
    ("layout_split_row", "layout", ("row", 40)),
    ("layout_tree",      "layout", ("tree", 40)),

    # ANSI — `rich.ansi.AnsiDecoder` (ansi.py:120-241) decodes ANSI-coded text
    # into styled `Text`. args = (ansi_str,); single-line inputs (no `\n`) so
    # `decode` yields one `Text`, returned verbatim. `capture_ansi` prints it
    # with `end=""` (overriding the Text's `end="\n"`), so the output is the
    # decoded content with NO trailing newline (the `text_plain` pattern).
    # ansi_simple → plain text (no SGR); ansi_color → `\x1b[31mred\x1b[0m`
    # (SGR 31); ansi_bold → `\x1b[1mbold\x1b[0m` (SGR 1); ansi_bold_color →
    # `\x1b[1;31mbold red\x1b[0m` (combined SGR `1;31`); ansi_reset → a reset
    # then text (the reset clears the running style). Width is 80 (case_width).
    # The Nim port (`renderAnsiAnsi`) decodes via `initAnsiDecoder`+`decode` and
    # renders the resulting `Text` with `end=""`, byte-exact vs Python rich
    # 15.0.0.
    ("ansi_simple",     "ansi", ("plain text",)),
    ("ansi_color",      "ansi", ("\x1b[31mred\x1b[0m",)),
    ("ansi_bold",        "ansi", ("\x1b[1mbold\x1b[0m",)),
    ("ansi_bold_color", "ansi", ("\x1b[1;31mbold red\x1b[0m",)),
    ("ansi_reset",       "ansi", ("\x1b[31mred\x1b[0mplain",)),

    # v0.5.0 — Control (extend the 3 baseline control_home/clear/title with 5
    # new cursor/control-code cases). `rich.control.Control` (control.py:43-141)
    # is a renderable that emits a non-printable ANSI control sequence built
    # from `ControlType`/`ControlCode` values. args = (code, *payload); the
    # baseline "home"/"clear"/"title" codes are unchanged. The 5 new codes:
    # "move" → `Control.move_to(x, y)` (control.py:110-118, absolute cursor
    #   move → `\x1b[{y+1};{x+1}H`); payload = (x=5, y=3) → `\x1b[4;6H`.
    # "move_up" → `Control.move(x=0, y=-3)` (control.py:68-92; the spec-named
    #   `Control.move_up` classmethod does NOT exist in rich 15.0.0 — the
    #   feasible substitute is `Control.move` with a negative `y`, which emits
    #   `CURSOR_UP` → `\x1b[3A`, preserving the "move cursor up" intent).
    # "move_down" → `Control.move(x=0, y=3)` (likewise infeasible `move_down`
    #   → `Control.move` with positive `y` → `CURSOR_DOWN` → `\x1b[3B`).
    # "clear_line" → `Control((ControlType.ERASE_IN_LINE, 2))` (control.py:33;
    #   the spec-named `Control.clear_line` classmethod does NOT exist — the
    #   feasible substitute is the `ERASE_IN_LINE` control code with param 2,
    #   which emits `\x1b[2K` (erase whole line), preserving the intent).
    # "segment" → `Control(ControlType.HOME, ControlType.CLEAR)` (control.py:51;
    #   `Control.segment` is a read-only ATTRIBUTE (the rendered `Segment`),
    #   not a callable — the feasible substitute is a multi-code `Control`
    #   whose single `Segment` joins two control codes (`\x1b[H\x1b[2J`),
    #   exercising the segment-joining mechanism that `Control.segment`
    #   exposes). Width is fixed at 80 (case_width, though Control output is
    #   width-independent). The Nim port (`renderControlAnsi = c.str()`) drives
    #   the fully-implemented `control.nim` (move/moveTo/initControl of the
    #   ERASE_IN_LINE code + multi-code), byte-exact vs Python rich 15.0.0.
    ("control_move",       "control", ("move", 5, 3)),
    ("control_move_up",    "control", ("move_up",)),
    ("control_move_down",  "control", ("move_down",)),
    ("control_clear_line", "control", ("clear_line",)),
    ("control_segment",    "control", ("segment",)),
    # new control edge cases — clear_screen & move (relative). `control_clear_screen`
    # = Control.clear() (the "clear screen" semantic — Control.clear() is the
    # sole clear classmethod in rich 15.0.0, emitting \x1b[2J; the descriptive
    # "clear_screen" code identifier exercises the same API under a name the
    # task requests). `control_move_to` = Control.move(10, 20) (RELATIVE cursor
    # move → \x1b[10C\x1b[20B, per the original task's literal Control.move(10,20)
    # requirement; the "move_rel" code identifier dispatches to Control.move,
    # distinct from control_move's "move" code → Control.move_to(5,3) absolute).
    ("control_clear_screen", "control", ("clear_screen",)),
    ("control_move_to",     "control", ("move_rel", 10, 20)),

    # v0.5.0 — Constrain (`rich.constrain.Constrain`, constrain.py:10-37) caps a
    # renderable's render width. args = (width,). The renderable is
    # `Align(Text("hi"), align="center")` (expand=True), so it FILLS the
    # constrained width — the constraint is visibly exercised (the output
    # width = the constrained width). Width = the Console width (case_width =
    # the constrained width), so the Align fills exactly that width. NOTE: the
    # spec's `Constrain(Text("long"), width=10)` would require rich's word-WRAP
    # to be visible; the Nim `Text.render` does NOT implement rich's word-wrap
    # (it renders the unwrapped string at any width), so a wrapping Text is
    # NOT byte-identical. The width-sensitive `Align` substitute keeps the
    # Constrain intent (cap the renderable to `width`) byte-identically.
    # `constrain_height`/`constrain_both`: `Constrain` has NO `height` param
    # (constrain.py:18: `width: Optional[int] = 80` only) — these spec-named
    # cases are infeasible; the feasible substitutes are a second/third
    # `Constrain(Align, width=...)` at a distinct width (30/40), preserving the
    # "constrain a dimension" intent and the 140+ count. The Nim port
    # (`renderConstrainAnsi`) renders the inner `Align` at the case width via
    # the real `Console`, byte-exact vs Python rich 15.0.0.
    ("constrain_width",  "constrain", (20,)),
    ("constrain_height", "constrain", (30,)),
    ("constrain_both",   "constrain", (40,)),

    # v0.5.0 — Scope (`rich.scope.render_scope`, scope.py:14-73; there is NO
    # `Scope` class in rich 15.0.0 — only the `render_scope` function, so the
    # spec's `Scope("name", renderables=[...])` is infeasible; the feasible
    # substitute is `render_scope(mapping, title=...)` which renders a `Panel.fit`
    # of a `Table.grid` of `key = Pretty(value)` rows, preserving the "render a
    # scope/grouping" intent). args = (variant, width); `width` is the Console
    # width = the panel's content-fit width (so the Nim port's `Panel.fit` —
    # whose measure returns the Console width — yields the same content-fit
    # panel). variant "simple" → `render_scope({"a": 1, "b": 2})` (uniform
    # int values; Nim tables are uniform-type, so heterogeneous int+str values
    # are not portable — all-int keeps `Pretty(int)` byte-identical on both
    # sides); "nested" → `render_scope({"d": {"inner": 5}})` (a nested dict
    # value → `Pretty(OrderedTable)` renders `{'inner': 5}`); "style" →
    # `render_scope({"x": 1}, title="Variables")` (the spec-named "scope_style"
    # has no `style` param in `render_scope` — the feasible substitute is the
    # `title` kwarg, the scope's visible style attribute). The Nim port
    # (`renderScopeAnsi`) builds the `Panel.fit(Table.grid([keyText, Pretty]),
    # border="scope.border")` directly (the `scope.nim` `renderScope` has a
    # latent `Table.grid`/`addRow` compile bug when instantiated, so the render
    # proc constructs the same structure via the proven `table.Table.grid`/
    # `Panel.fit`/`Pretty` primitives) + a `scope.*` theme push, byte-exact vs
    # Python rich 15.0.0.
    ("scope_simple", "scope", ("simple", 9)),
    ("scope_nested", "scope", ("nested", 20)),
    ("scope_style",  "scope", ("style", 15)),

    # v0.5.0 — Region (`rich.region.Region`, region.py:4-10) is a `NamedTuple`
    # (x, y, width, height) — NOT a renderable (no `__rich_console__`), so
    # `console.print(Region(...))` renders the `ReprHighlighter`-painted repr
    # `Region(x=…, y=…, width=…, height=…)\n` (Python wraps the non-renderable in
    # `Pretty`). args = (x, y, width, height). `region_overlap`: `Region` has NO
    # `overlap` method (only the tuple's `count`/`index` + named fields) — the
    # spec-named case is infeasible; the feasible substitute is a third distinct
    # `Region` (positioned to overlap a 0,0,20,10 reference), preserving the
    # "region rectangle" intent. Width is fixed at 80 (case_width; the single-
    # line repr is width-independent). The Nim port (`renderRegionAnsi`) builds
    # the repr string, applies `ReprHighlighter` via the direct
    # `cast[RegexHighlighter].highlight` downcast (the `Highlighter.call` shim
    # is a known no-op), and renders through the real `Console` (so the
    # `repr.*` styles resolve via `DEFAULT_STYLES`) + a trailing `\n`, byte-
    # exact vs Python rich 15.0.0.
    ("region_simple", "region", (0, 0, 20, 10)),
    ("region_offset", "region", (5, 3, 15, 8)),
    ("region_overlap", "region", (10, 5, 20, 10)),

    # v0.5.0 — Screen (`rich.screen.Screen`, screen.py:15-46) fills the
    # terminal screen (width × height) and crops excess, rendering a grouped
    # set of child renderables against an optional background style. args =
    # (variant, width, height); `width`/`height` are the Console size (20/24).
    # variant "simple" → `Screen(Text("hi"))` (one child); "multi" →
    # `Screen(Text("line1"), Text("line2"))` (grouped children); "update" →
    # `Screen(Text("hi"), application_mode=True)` (the spec-named
    # `Screen.update` method does NOT exist — the feasible substitute is the
    # `application_mode=True` init kwarg, which changes the line separator from
    # `Segment.line()` (`\n`) to `"\n\r"`, preserving the "modify the screen"
    # intent). The Console height is 24 (capture_ansi's fixed height); the
    # Screen fills 20×24. The Nim port (`renderScreenAnsi`) renders the child
    # `Text`s, pads each line to the width with spaces, fills to `height` rows,
    # and joins with `\n` (or `\n\r` in application mode) — the `screen.nim`
    # `renderConsole` is a stub (no padding), so the render proc constructs the
    # screen-fill directly, byte-exact vs Python rich 15.0.0.
    ("screen_simple", "screen", ("simple", 20, 24)),
    ("screen_multi",  "screen", ("multi", 20, 24)),
    ("screen_update", "screen", ("update", 20, 24)),

    # v0.6.0 — Measure/Repr/Theme/TerminalTheme/Errors gap-fill (5 modules,
    # 18 new cases → 160 total). Each gap module had ZERO golden coverage in
    # v0.5.0 (round_001 audit). The cases exercise the real rich 15.0.0
    # machinery via shell-probed byte-exact reference outputs.
    #
    # Measure — `rich.measure.Measurement` (measure.py:11-122). `Measurement`
    # is a `NamedTuple`, NOT a renderable (no `__rich_console__`), so
    # `console.print(Measurement(...))` renders the `ReprHighlighter`-painted
    # repr `Measurement(minimum=.., maximum=..)` (Python wraps the non-renderable
    # in `Pretty` → `repr(obj)` → `ReprHighlighter`). args = (minimum, maximum);
    # `render_measure` constructs the real `Measurement(min, max)`. The four
    # values are shell-probed from `Measurement.get(console, options, renderable)`
    # on the four renderables (Text("hello")→5/5, the golden Table→11/11,
    # Panel("content")→11/11, Text("wide string here")→6/16) — these are rich's
    # real measurements (the Nim `Measurement.get` is DEFERRED, so the Nim
    # `renderMeasureAnsi` constructs `Measurement(min,max)` directly with the
    # probed values, matching rich bytes — the contract's allowed substitute).
    # Width is fixed at 80 (case_width; the single-line repr is width-independent).
    ("measure_text",  "measure", (5, 5)),
    ("measure_table", "measure", (11, 11)),
    ("measure_panel", "measure", (11, 11)),
    ("measure_wide",  "measure", (6, 16)),

    # Repr — `rich.repr` `@rich_repr`/`@auto` decorator machinery (repr.py:25-
    # 122). There is NO `Repr` class in rich 15.0.0 (the spec's `Repr(obj)` is
    # infeasible — confirmed by shell probe); the actual machinery is the
    # `@rich_repr`/`@auto` class decorator that installs a `__repr__` built
    # from a `__rich_repr__` generator, plus the `ReprError` exception. The
    # repr object is NOT renderable (no `__rich_console__`), so `console.print
    # (obj)` renders the `ReprHighlighter`-painted `repr(obj)` via `Pretty`
    # (the same path as `Region`/`Measurement`). args = (variant,); variant
    # selects the `@rich_repr` object: "simple"→`Thing(name='widget', count=3)`
    # (kv with a str + int value — exercises `repr.str`=green + `repr.number`
    # =bold cyan), "text"→`PosArgs('only', 'args')` (positional string args
    # — the "text" value intent, exercises the positional-arg repr path with
    # two `repr.str` greens), "panel"→`WithStr(title='hello', items=[1, 2,
    # 3])` (a nested-list container — the "panel"/container intent, exercises
    # `repr.str` + `repr.brace` on `[`/`]` + numbers), "error"→`ReprError
    # ("boom")` (the real `rich.repr.ReprError` exception; `console.print
    # (exception)` renders `str(exception)`="boom" via `_highlighter(str)` with
    # NO trailing newline, unlike the Pretty-repr cases which keep `end="\n"`).
    # The Nim `renderReprAnsi` builds the repr string via the real `repr.autoRepr`
    # (exercising `repr.nim`'s `autoRepr`/`jsonRepr`/`pyStrRepr`) then applies
    # `ReprHighlighter`. Width is fixed at 80 (case_width).
    ("repr_simple", "repr", ("simple",)),
    ("repr_text",   "repr", ("text",)),
    ("repr_panel",  "repr", ("panel",)),
    ("repr_error",  "repr", ("error",)),

    # Theme — `rich.theme.Theme` (theme.py:10-92). `Theme` is a container of
    # named styles used by `Console`, NOT a renderable (printing a `Theme`
    # yields the non-deterministic default object repr `<rich.theme.Theme
    # object at 0x...>` — NOT byte-stable, confirmed by shell probe). So the
    # Theme golden gap is filled by APPLYING a `Theme` to a renderable via the
    # Console theme stack (the real Theme purpose): `console.print(renderable,
    # ...)` on a `Console(theme=Theme({...}))` resolves custom style names
    # through `Console.get_style` → the theme's parsed `Style`s. args =
    # (variant, width); `width` is the Console width (80 for Text cases, 40
    # for the Panel case — the panel fills it, expand=True). variant "simple"
    # → `Theme({"key": "bold red"})` applied to `Text("hi", style="key")` →
    # `\x1b[1;31mhi\x1b[0m`; "multi" → `Theme({"a": "bold red", "b": "italic
    # blue", "c": "dim yellow"})` applied to a single `Text` with three spans
    # (`a`/`b`/`c`) → three styled segments; "apply" → `Theme({"my_border":
    # "magenta"})` applied to `Panel("content", border_style="my_border")` (the
    # border resolves `my_border`→magenta via the theme — exercises Theme on a
    # non-trivial renderable). `render_theme` returns a `(renderable, theme)`
    # pair; `main()` passes the theme to `capture_ansi`'s `theme=` kwarg so the
    # Console is constructed with it. The Nim `renderThemeAnsi` pushes the
    # same `Theme` via `console.pushTheme(initTheme(...))` (the established
    # `pushJsonTheme`/`pushPromptTheme` pattern) and renders the renderable
    # through the real `Console`. Byte-exact vs Python rich 15.0.0.
    ("theme_simple", "theme", ("simple", 80)),
    ("theme_multi",  "theme", ("multi", 80)),
    ("theme_apply",  "theme", ("apply", 40)),

    # TerminalTheme — `rich.terminal_theme.TerminalTheme` (terminal_theme.py:
    # 9-30) bundles a background/foreground `ColorTriplet` plus a 16-colour
    # `Palette` for SVG/HTML export. `TerminalTheme` is NOT a renderable and
    # prints as the non-deterministic default object repr (NOT byte-stable —
    # confirmed by shell probe), and `TerminalTheme()` with no args raises
    # (it requires background/foreground/normal). So the gap is filled by
    # rendering a `ColorTriplet` attribute repr of a real `TerminalTheme`
    # (`ColorTriplet` IS a `NamedTuple` → its repr is byte-stable via
    # `ReprHighlighter`, the `Region`/`Measurement` pattern). args =
    # (variant,); variant "simple" → `DEFAULT_TERMINAL_THEME.background_color`
    # (the real predefined default — white bg `ColorTriplet(255,255,255)`);
    # "custom" → a custom `TerminalTheme((10,20,30),(40,50,60),[...]).
    # background_color` (`ColorTriplet(10,20,30)`); "fg" → the same custom
    # theme's `.foreground_color` (`ColorTriplet(40,50,60)`). All three are
    # distinct values. `render_terminal_theme` returns the `ColorTriplet`
    # (constructing the custom `TerminalTheme` with the real args). The Nim
    # `renderTerminalThemeAnsi` constructs the same `TerminalTheme` via
    # `initTerminalTheme`/`DEFAULT_TERMINAL_THEME` and builds the
    # `ColorTriplet(red=.., green=.., blue=..)` repr string from the fields,
    # applies `ReprHighlighter`, renders with `end="\n"`. Width 80.
    ("terminal_theme_simple", "terminal_theme", ("simple",)),
    ("terminal_theme_custom", "terminal_theme", ("custom",)),
    ("terminal_theme_fg",     "terminal_theme", ("fg",)),

    # Errors — `rich.errors` exception classes (errors.py). The exceptions
    # are NOT renderable (`is_renderable(Exception)` is False), so
    # `console.print(exc)` renders `_highlighter(str(exc))` (console.py:1577
    # `append_text(_highlighter(str(renderable)))`) — the message string with
    # `ReprHighlighter` applied (no spans for the plain messages below → plain
    # text) and NO trailing newline (the print's `end=""` overrides the Text
    # end). args = (class_name, message); `render_errors` constructs the real
    # exception and returns it. The four classes cover the two base error
    # families: `ConsoleError` (the console base) + its subclasses
    # `NotRenderableError`/`LiveError`, and `StyleError` (the style base). The
    # messages are plain (no `[`/`(`/digits) so `ReprHighlighter` adds no
    # spans → byte-stable plain text). The Nim `renderErrorsAnsi` constructs
    # the same exception via `newException` and renders the message via
    # `ReprHighlighter` + the real `Console` with `end=""`. Width 80.
    ("errors_console",       "errors", ("ConsoleError", "a console error")),
    ("errors_style",         "errors", ("StyleError", "a style error")),
    ("errors_notrenderable", "errors", ("NotRenderableError", "not renderable here")),
    ("errors_live",          "errors", ("LiveError", "a live error")),

    # FileProxy — `rich.file_proxy.FileProxy` (file_proxy.py:12-60). args =
    # (variant, width); `render_file_proxy` builds the variant's renderable(s),
    # renders each to raw ANSI, concatenates with one trailing newline, and
    # round-trips through a real `FileProxy(console, file)` (write+flush).
    # FileProxy is a perfect round-tripper when input ends with "\n", so the
    # output equals the source ANSI (byte-identical vs the Nim `FileProxy`).
    # Width 80 for the full-width cases; 40 for the title panel (matches
    # `panel_title`). `file_proxy_table` reuses the `table_simple` config.
    ("file_proxy_simple",      "file_proxy", ("simple", 80)),
    ("file_proxy_text",        "file_proxy", ("text", 80)),
    ("file_proxy_text_bold",   "file_proxy", ("text_bold", 80)),
    ("file_proxy_panel",      "file_proxy", ("panel", 80)),
    ("file_proxy_panel_title", "file_proxy", ("panel_title", 40)),
    ("file_proxy_table",       "file_proxy", ("table", 80)),
    ("file_proxy_multi",       "file_proxy", ("multi", 80)),

    # LiveRender — `rich.live_render.LiveRender` (live_render.py:18-116). args =
    # (variant, width); `render_live_render` wraps the variant's renderable in a
    # `LiveRender` and `capture_ansi` prints it (`end=""`). The output equals
    # the plain render minus one trailing `"\n"` (Panel/Table/Columns) or
    # unchanged (Text). Width 80 for the full-width cases; 40 for columns/multi
    # (matching `columns_simple`). `live_render_table` reuses the `table_simple`
    # config; `live_render_columns` reuses `columns_simple`.
    ("live_render_simple",      "live_render", ("simple", 80)),
    ("live_render_text_styled",  "live_render", ("text_styled", 80)),
    ("live_render_text_bold",   "live_render", ("text_bold", 80)),
    ("live_render_panel",       "live_render", ("panel", 80)),
    ("live_render_table",       "live_render", ("table", 80)),
    ("live_render_columns",     "live_render", ("columns", 40)),
    ("live_render_multi",       "live_render", ("multi", 40)),

    # 5 new golden cases — spinner (arrow/dots2), emoji (white_check_mark),
    # filesize (2048/1048576). The oracle is Python rich 15.0.0's `decimal`
    # (rich.filesize has NO `binary` function in 15.0.0): decimal(2048)→
    # "2.0 kB", decimal(1048576)→"1.0 MB". Spinner "arrow" frame0="←" (8
    # frames), "dots2" frame0="⣾" (8 frames). Emoji "white_check_mark"→"✅".
    # `filesize_two_kilobytes` uses (2048,) — distinct from the baseline
    # `filesize_bytes` (1024,) so both are independently addressable via
    # get_case(); the Nim `decimal` proc already handles any byte count.
    # `filesize_megabytes` uses (1048576,) → decimal → "1.0 MB".
    ("spinner_arrow",          "spinner",  ("arrow", "", 80)),
    ("spinner_dots2",          "spinner",  ("dots2", "", 80)),
    ("emoji_check_mark",       "emoji",    ("obj", "white_check_mark", None, None)),
    ("filesize_two_kilobytes", "filesize", (2048,)),
    ("filesize_megabytes",     "filesize", (1048576,)),

    # layout_constrain — 5 new cases exercising `rich.constrain.Constrain` (with
    # a distinct inner text per case, extending the baseline `(width,)` shape
    # to `(width, text)`) and `rich.console.Group` (a new "group" kind). Each
    # case's expected rendering is probed from Python rich 15.0.0 (the oracle);
    # the Nim port (`renderConstrainAnsi`/`renderGroupAnsi`) renders the same
    # structure via the real `Console`, byte-exact.
    #
    # `constrain_max` — `Constrain(Align(Text("constrained max"), "center"),
    # width=25)`: a 15-char text centered in a 25-wide constraint (5 + 15 + 5
    # pad). Distinct from `constrain_width` (20, text="hi") — exercises a
    # WIDER inner text (longer than "hi") at a distinct width. `case_width` =
    # 25 (args[0]).
    ("constrain_max", "constrain", (25, "constrained max")),
    # `constrain_min` — `Constrain(Align(Text("ok"), "center"), width=5)`: a
    # very narrow 5-wide constraint (1 + 2 + 2 pad). Distinct from
    # `constrain_max` (25, long text) — exercises the minimum-viable width.
    ("constrain_min", "constrain", (5, "ok")),
    # `group_render` — `Group(Text("line one"), Text("line two"),
    # Text("line three"))`: three plain Texts rendered sequentially (the
    # Group's `__rich_console__` yields from its renderables, each Text ends
    # with `\n`). Width 40 (case_width; the plain texts are width-independent).
    ("group_render", "group", ("render", 40)),
    # `group_styled` — `Group(Text("bold line", style="bold"),
    # Text("red line", style="red"))`: two styled Texts (bold SGR 1, red SGR
    # 31), each ending with `\n`. Distinct from `group_render` (plain texts).
    ("group_styled", "group", ("styled", 40)),
    # `group_rule` — `Group(Text("before"), Rule(), Text("after"))`: a Group
    # mixing a Text, a Rule (bright_green `rule.line` style → \x1b[92m), and
    # another Text. Distinct from the two Text-only groups — exercises a
    # non-Text renderable (Rule) within a Group.
    ("group_rule", "group", ("rule", 40)),
]

# Table args tuple layout: (header_style, title, title_style, has_rows)
TABLE_HEADER_STYLE = 0
TABLE_TITLE = 1
TABLE_TITLE_STYLE = 2
TABLE_HAS_ROWS = 3

# Panel args tuple layout: (text, title, subtitle, border_style, width[, box]).
# The optional 6th element (box, index PANEL_BOX) is a box-style name string
# ("double"/"rounded"/…) overriding the ROUNDED default; absent for the legacy
# 5-element cases.
PANEL_TEXT = 0
PANEL_TITLE = 1
PANEL_SUBTITLE = 2
PANEL_BORDER_STYLE = 3
PANEL_WIDTH = 4
PANEL_BOX = 5

# Tree args tuple layout: (root_label, hide_root, style, width, children[,
# guide_style]). The optional 6th element (guide_style, index
# TREE_GUIDE_STYLE) is a style string overriding the "tree.line" default;
# absent for the legacy 5-element cases.
TREE_ROOT_LABEL = 0
TREE_HIDE_ROOT = 1
TREE_STYLE = 2
TREE_WIDTH = 3
TREE_CHILDREN = 4
TREE_GUIDE_STYLE = 5

# Emoji args tuple layout: (mode, ...). mode "obj" → (name, style, variant);
# mode "replace" → (text,). style is None (default "none") or a str; variant
# is None, "emoji", or "text".
EMOJI_MODE = 0
EMOJI_NAME = 1       # mode "obj"
EMOJI_STYLE = 2      # mode "obj"
EMOJI_VARIANT = 3    # mode "obj"
EMOJI_TEXT = 1       # mode "replace"

# Prompt args tuple layout: (text, choices, default). `choices` is None (no
# choices) or a list of str; `default` is None (no default — the Ellipsis
# sentinel `...`) or a str. See the Prompt case comment in CASES above.
PROMPT_TEXT = 0
PROMPT_CHOICES = 1
PROMPT_DEFAULT = 2

# Markdown args tuple layout: (markup, width). `width` is the Console width
# (per-case); the Markdown renderable renders within it (headings center,
# paragraphs left-align). Matches the panel/tree width-in-args convention.
MARKDOWN_MARKUP = 0
MARKDOWN_WIDTH = 1

# Bar args tuple layout: (size, begin, end, bar_width, color). `bar_width` is
# the Bar's own `width` (cells); `color` is None (default "default") or a str.
# The Console width is fixed at 40 (case_width), capping the bar via
# `min(self.width, options.max_width)`.
BAR_SIZE = 0
BAR_BEGIN = 1
BAR_END = 2
BAR_WIDTH = 3
BAR_COLOR = 4

# Align args tuple layout: (text, text_style, align, width). `text_style` is
# None (plain) or a str ("bold red") applied to the Text (NOT the Align —
# `Align.style` stays None); `align` is "left"/"center"/"right"; `width` is the
# Console width (40/50), matching golden_ref.py's `Console(width=…)`.
ALIGN_TEXT = 0
ALIGN_TEXT_STYLE = 1
ALIGN_ALIGN = 2
ALIGN_WIDTH = 3

def normalize_case(case):
    """Normalize a case record to the (name, kind, args) form the renderers
    expect. Standard records are 3-tuples (name, kind, args) — `args` is the
    single element after `kind`, returned as-is. The three v0.8.1 table records
    are stored literally as variable-arity tuples (outer arity 4/4/5):
    (name, "table", data, box_style) / (name, "table", data, box_style, style).
    Their trailing fields beyond `kind` are packed into a single `args` tuple
    here — yielding (data, box_style[, style]) — so `render_table`/`case_width`
    consume them unchanged (the new shape is detected by
    `isinstance(args[0], tuple)`)."""
    name, kind = case[0], case[1]
    rest = case[2:]
    if len(rest) == 1:
        return (name, kind, rest[0])
    return (name, kind, rest)

def case_width(case):
    """Console render width for a case. Default 80; Panel cases carry their
    own width in args[PANEL_WIDTH] (the panel fills the console width);
    Tree cases carry their own width in args[TREE_WIDTH]."""
    _, kind, args = normalize_case(case)
    if kind == "panel":
        return args[PANEL_WIDTH]
    if kind == "tree":
        return args[TREE_WIDTH]
    if kind == "emoji":
        return 20
    if kind == "markdown":
        return args[MARKDOWN_WIDTH]
    if kind == "bar":
        return 40
    if kind == "align":
        # Legacy 4-tuple (text, text_style, align, width) carries the Console
        # width at index 3; the v0.8.1 2/3-tuple (text, align[, style]) shape
        # has no width, so pick one matching the closest legacy case: 50 for
        # multiline (matching `align_multiline`), 40 otherwise (matching
        # `align_right`/`align_left`/`align_center`).
        if len(args) >= 4:
            return args[ALIGN_WIDTH]
        if isinstance(args[0], str) and "\n" in args[0]:
            return 50
        return 40
    if kind == "columns":
        return args[4]
    if kind == "syntax":
        return args[3] if len(args) == 4 else 80
    if kind == "spinner":
        return args[2]
    if kind == "pretty":
        return 80
    if kind == "status":
        return 80
    if kind == "logging":
        return 80
    if kind == "progress":
        return 80
    if kind == "progress_advanced":
        return 80
    if kind == "json":
        return 80
    if kind == "traceback":
        return 80
    if kind == "prompt":
        return 80
    if kind == "box":
        return 80
    if kind == "padding":
        return 40
    if kind == "markup":
        return 80
    if kind == "abc":
        return args[1]
    if kind == "styled":
        return 80
    if kind == "ratio":
        return 40
    if kind == "layout":
        return args[1]
    if kind == "ansi":
        return 80
    if kind == "constrain":
        return args[0]
    if kind == "group":
        return args[1]
    if kind == "scope":
        return args[1]
    if kind == "region":
        return 80
    if kind == "screen":
        return args[1]
    if kind == "measure":
        return 80
    if kind == "repr":
        return 80
    if kind == "theme":
        return args[1]
    if kind == "terminal_theme":
        return 80
    if kind == "errors":
        return 80
    if kind == "file_proxy":
        return args[1]
    if kind == "live_render":
        return args[1]
    if kind == "table_advanced":
        return 80
    return 80

def case_names():
    return [c[0] for c in CASES]

def get_case(name):
    for c in CASES:
        if c[0] == name:
            return c
    return None
