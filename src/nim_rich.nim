## Umbrella module for `nim_rich` — mirrors Python `rich`'s top-level package.
##
## All modules wired into the umbrella (56 canonical + 4
## helpers: richbase, markup, tree, api_types). Proc bodies mirror the Python source
## (`discard` / `default(T)`); body fills them. Sibling imports use short
## names; the umbrella uses package paths (`import nim_rich/[…]`).

import nim_rich/[richbase, console_api, abc, align, ansi, api_types, bar, box, cells, color, color_triplet, columns, console, constrain, containers, control, default_styles, diagnose, emoji, errors, file_proxy, filesize, highlighter, json, jupyter, layout, live, live_render, logging, markdown, markup, measure, padding, pager, palette, panel, pretty, progress, progress_bar, prompt, protocol, ratio, region, repr, rule, scope, screen, segment, spinner, status, style, styled, syntax, table, terminal_theme, text, theme, themes, traceback, tree, unicode_data]
export richbase, console_api, abc, align, ansi, api_types, bar, box, cells, color, color_triplet, columns, console, constrain, containers, control, default_styles, diagnose, emoji, errors, file_proxy, filesize, highlighter, json, jupyter, layout, live, live_render, logging, markdown, markup, measure, padding, pager, palette, panel, pretty, progress, progress_bar, prompt, protocol, ratio, region, repr, rule, scope, screen, segment, spinner, status, style, styled, syntax, table, terminal_theme, text, theme, themes, traceback, tree, unicode_data
