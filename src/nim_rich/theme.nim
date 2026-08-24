## Port of `rich.theme` (rich/theme.py).
##
## `Theme` is a container of named styles used by `Console`; `ThemeStack` is a
## push/pop stack of merged style tables. Both are plain reference objects (no
## renderable protocol).
##
## Import graph (theme.py:1-5): `from typing import IO, Dict, List, Mapping,
## Optional` (theme.py:1) → `std/streams` (`IO[str]` → `Stream`, for
## `from_file`), `std/tables` (`Dict`/`OrderedTable`), `std/options`
## (`Optional`). `from .default_styles import DEFAULT_STYLES` (theme.py:3) is
## a body BODY import (used only in `initTheme`'s `DEFAULT_STYLES.copy()`),
## so `default_styles` is NOT imported  (stub body is `discard`);
## `from .style import Style, StyleType` (theme.py:4) → `style`.
## Nim-only: `import text` for `StyleValue` (the `Union[str, Style]` case object)
## so the `styles: Optional[Mapping[str, StyleType]]` param accepts both `str`
## and `Style` values (mirrors `Union[str, Style]` at the API boundary); theme.py
## does not import text but the handle is needed because Nim cannot store a
## `StyleType` typeclass directly in a `Table` value.
##
## Faithfulness: `Theme.styles: Dict[str, Style]` (theme.py:12) → field
## `OrderedTable[string, Style]` (Python `dict` is insertion-ordered since
## 3.7; `DEFAULT_STYLES.copy()` / `.update()` preserve order). The `styles`
## PARAM is `Optional[Mapping[str, StyleType]]` (theme.py:18) →
## `Option[OrderedTable[string, StyleValue]]` (str|Style values); body's
## body runs `Style.parse(style)` for the non-`Style` entries (theme.py:30-36).
## `ThemeStackError(Exception)` (theme.py:95) → `object of CatchableError`;
## `ThemeStack._entries` (theme.py:108, private) → private `entries` (no `*`);
## the dynamic `self.get = self._entries[-1].get` alias (theme.py:109) is modelled
## as a `get` proc (Nim has no runtime rebindable field).
##
## Naming: `__init__`→`initTheme`/`initThemeStack`, `from_file`→`fromFile`,
## `push_theme`→`pushTheme`, `pop_theme`→`popTheme`, `config`→`config` (the
## `@property` theme.py:38 → proc). Classmethods `from_file`/`read` drop `cls`
## (return a fresh `Theme`). Proc bodies are `discard` (port).

import std/options
import std/streams
import std/tables
import std/strutils
import std/algorithm

import style           # Style, StyleType — the field/param value types.
import text            # StyleValue — Nim-only handle for Union[str, Style] table values.
import default_styles  # DEFAULT_STYLES — the inherit=True base (theme.py:25-26).

type
  Theme* = ref object of RootObj
    ## rich theme.py:10-92 — `class Theme`: a container of style information
    ## used by `Console`. `ref object of RootObj` (Python reference semantics).
    ## Fields mirror the `__init__` assignment (theme.py:25-36).
    styles*: OrderedTable[string, Style]
      ## theme.py:12 — `self.styles: Dict[str, Style]`; initialised to
      ## `DEFAULT_STYLES.copy()` when `inherit` else `{}` (theme.py:25-26), then
      ## updated from the `styles` mapping (theme.py:27-36). `OrderedTable`
      ## preserves Python `dict` insertion order.

  ThemeStackError* = object of CatchableError
    ## rich theme.py:95-96 — `class ThemeStackError(Exception)`: base exception
    ## for errors related to the theme stack. `Exception` → `CatchableError`.

  ThemeStack* = ref object of RootObj
    ## rich theme.py:99-122 — `class ThemeStack`: a stack of themes. `ref
    ## object of RootObj` (Python reference semantics). Fields mirror the
    ## `__init__` assignment (theme.py:108-109).
    entries: seq[OrderedTable[string, Style]]
      ## theme.py:108 (private `_entries: List[Dict[str, Style]]`) — the stack
      ## of merged style tables; `__init__` seeds it with `[theme.styles]`
      ## (theme.py:108). Private (no `*`) to match the Python underscore.

proc initTheme*(
    styles: Option[OrderedTable[string, StyleValue]] = none(OrderedTable[string, StyleValue]),
    inherit: bool = true,
): Theme =
  ## rich theme.py:17-36 — `Theme.__init__(self, styles: Optional[Mapping[str,
  ## StyleType]] = None, inherit: bool = True)`. `styles` default `None` →
  ## `none(OrderedTable[string, StyleValue])`; body sets `self.styles =
  ## DEFAULT_STYLES.copy() if inherit else initOrderedTable[string, Style]()`
  ## and merges `styles` (running `Style.parse` on non-`Style` values,
  ## theme.py:27-36).
  result = Theme()
  if inherit:
    # `DEFAULT_STYLES.copy()` (theme.py:25): Nim `OrderedTable` assignment
    # copies, so `result.styles = DEFAULT_STYLES` is a faithful copy.
    result.styles = DEFAULT_STYLES
  else:
    result.styles = initOrderedTable[string, Style]()
  if styles.isSome:
    # theme.py:27-36: `self.styles.update({name: style if isinstance(style,
    # Style) else Style.parse(style) ...})` — a `str` value is parsed, a
    # `Style` value is stored as-is.
    for name, sv in styles.get.pairs:
      let st = case sv.kind
               of svkStr: Style.parse(sv.strv)
               of svkStyle: sv.stv
      result.styles[name] = st

proc config*(self: Theme): string =
  ## rich theme.py:38-46 — `Theme.config` (`@property` theme.py:38): get the
  ## contents of an INI-style config file for this theme (`"[styles]\n" + ...`,
  ## sorted by name, theme.py:40-45).
  # theme.py:40-45: `"[styles]\n" + "\n".join(f"{name} = {style}" for
  # name, style in sorted(self.styles.items()))` — sort by name, no trailing NL.
  var names: seq[string] = @[]
  for name in self.styles.keys:
    names.add(name)
  names.sort(proc(x, y: string): int = cmp(x, y))
  var parts: seq[string] = @[]
  for name in names:
    parts.add(name & " = " & $(self.styles[name]))
  result = "[styles]\n" & join(parts, "\n")

proc fromFile*(
    configFile: Stream,
    source: Option[string] = none(string),
    inherit: bool = true,
): Theme =
  ## rich theme.py:48-69 — `Theme.from_file(cls, config_file: IO[str], source:
  ## Optional[str] = None, inherit: bool = True) -> Theme` (`@classmethod`
  ## theme.py:48): load a theme from a text-mode config file via
  ## `configparser`. `IO[str]` → `Stream`; drops `cls` (returns a fresh
  ## `Theme`).
  # Minimal INI parser (rich uses Python `configparser`): recognise a
  # `[styles]` section and `name = value` lines; `#`/`;` comments and blank
  # lines are skipped. `source` (the filename) is used by `configparser` only
  # for error attribution and is unused by this simple parser.
  var styles = initOrderedTable[string, StyleValue]()
  var inStyles = false
  for line in configFile.readAll().splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith(";"):
      continue
    if stripped.startsWith("[") and stripped.endsWith("]"):
      inStyles = (stripped == "[styles]")
      continue
    if inStyles:
      let kv = stripped.split("=", 1)
      if kv.len == 2:
        styles[kv[0].strip()] = kv[1].strip()  # str -> StyleValue (converter)
  result = initTheme(some(styles), inherit)

proc read*(
    path: string,
    inherit: bool = true,
    encoding: Option[string] = none(string),
): Theme =
  ## rich theme.py:71-91 — `Theme.read(cls, path: str, inherit: bool = True,
  ## encoding: Optional[str] = None) -> Theme` (`@classmethod` theme.py:71):
  ## open `path` and delegate to `from_file`. Drops `cls`.
  # Python `open(path, encoding=encoding)` raises `FileNotFoundError` (OSError)
  # when the path is missing; Nim's `newFileStream` returns nil, so raise
  # `IOError` to mirror the failure. `encoding` is not applied (Nim reads the
  # file as raw bytes; UTF-8, the common case, round-trips correctly) — a
  # best-effort deviation.
  let f = newFileStream(path, fmRead)
  if f == nil:
    raise newException(IOError, "could not open " & path)
  defer: f.close()
  result = fromFile(f, some(path), inherit)

proc initThemeStack*(theme: Theme): ThemeStack =
  ## rich theme.py:104-109 — `ThemeStack.__init__(self, theme: Theme) -> None`:
  ## seed `self._entries = [theme.styles]` and alias `self.get =
  ## self._entries[-1].get` (modelled here by the `get` proc below).
  result = ThemeStack()
  result.entries = @[theme.styles]  # `[theme.styles]` (a copy of the table)

proc pushTheme*(self: ThemeStack, theme: Theme, inherit: bool = true) =
  ## rich theme.py:111-128 — `ThemeStack.push_theme(self, theme: Theme, inherit:
  ## bool = True) -> None`: push a merged style table on top (`{**top,
  ## **theme.styles}` if `inherit` else `theme.styles.copy()`, theme.py:122-125).
  # `{**top, **theme.styles}` = top with theme.styles merged over it; Nim
  # `OrderedTable` assignment copies, so `styles = self.entries[^1]` is a copy.
  var styles: OrderedTable[string, Style]
  if inherit:
    styles = self.entries[^1]
    for name, st in theme.styles.pairs:
      styles[name] = st
  else:
    styles = theme.styles
  self.entries.add(styles)

proc popTheme*(self: ThemeStack) =
  ## rich theme.py:130-136 — `ThemeStack.pop_theme(self) -> None`: pop the
  ## top-most theme; raise `ThemeStackError` if the base theme would be popped
  ## (theme.py:133-134).
  if self.entries.len == 1:
    raise newException(ThemeStackError, "Unable to pop base theme")
  discard self.entries.pop()

proc get*(self: ThemeStack, name: string): Option[Style] =
  ## rich theme.py:109 — `ThemeStack.get` (the dynamic `self.get =
  ## self._entries[-1].get` alias): look up `name` in the top-most merged table,
  ## returning `Optional[Style]`. Modelled as a proc (Nim cannot store a
  ## rebindable bound method in a field).
  # `self._entries[-1].get(name)` — dict.get returns the value or None.
  let top = self.entries[^1]
  result = if top.hasKey(name): some(top[name]) else: none(Style)
