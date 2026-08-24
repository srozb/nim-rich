## Port of `rich.themes` (rich/themes.py).
##
## `rich.themes` is a 5-line module whose sole purpose is to expose the default
## theme singleton `DEFAULT = Theme(DEFAULT_STYLES)` (themes.py:5). It imports
## `DEFAULT_STYLES` from `default_styles` (themes.py:1) and `Theme` from `theme`
## (themes.py:2), then constructs the default theme from the default style table.
##
## Import graph (rich/themes.py:1-2): `from .default_styles import
## DEFAULT_STYLES` (themes.py:1) and `from .theme import Theme` (themes.py:2).
## `Theme` is the type of `DEFAULT` (themes.py:5), so `theme` is imported here.
## `DEFAULT_STYLES` is a body BODY concern — `theme.nim` itself treats
## `default_styles` as a body-only import (used only in `initTheme`'s
## `DEFAULT_STYLES.copy()` merge, theme.py:25-36) and does NOT import it at
## port; this module follows the same rule, so `default_styles` is NOT
## imported  (the `Theme(DEFAULT_STYLES)` construction runs in the
## `initTheme` body, which is `discard` until body).
##
## Faithfulness: `DEFAULT = Theme(DEFAULT_STYLES)` (themes.py:5) is a module-level
## computed value. At the `initTheme` body is `discard` (returns
## `default(Theme)` = `nil`), so the real `DEFAULT_STYLES` merge is wired in Phase
## 1; the `DEFAULT` is a placeholder `Theme` constructed via `initTheme()`
## (mirroring `ansi.nim`'s `reAnsi* = re("")` / `default_styles.nim`'s
## `DEFAULT_STYLES* = initOrderedTable[…]()` placeholder pattern for
## module-level computed values). `{.used.}` suppresses the unused warning until
## consumers (`Console.__init__`'s `themes.DEFAULT` default, console.py:743)
## reference it in body.
##
## Naming: the module keeps the rich name `DEFAULT` (no translation). Proc bodies
## are `discard` (port).

import theme   # Theme — the type of `DEFAULT` (themes.py:2, themes.py:5).

let DEFAULT* = initTheme()
  ## rich themes.py:5 — `DEFAULT = Theme(DEFAULT_STYLES)`: the default theme
  ## singleton consumed by `Console.__init__` (console.py:743,
  ## `ThemeStack(themes.DEFAULT if theme is None else theme)`). port
  ## placeholder — the `initTheme` body is `discard` (returns `nil`), so the
  ## faithful `Theme(DEFAULT_STYLES)` merge (running `Style.parse` over the
  ## `DEFAULT_STYLES` table, theme.py:27-36) is wired in body when
  ## `default_styles` is imported as a body dep. `{.used.}` suppresses the unused
  ## warning until a consumer references it.
