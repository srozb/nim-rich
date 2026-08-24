## Nim port of `rich.filesize` (rich/filesize.py).
##
## Functions for reporting filesizes (rich/filesize.py:1-88). Three functions
## cover the different use-cases for a string representation of a file size;
## only `decimal` is public (`__all__ = ["decimal"]`, filesize.py:13). The two
## helpers `_to_str` (filesize.py:18) and `pick_unit_and_suffix` (filesize.py:43)
## are module-private (underscore-prefixed) and so are non-`*` here.
##
## Import graph (rich/filesize.py:15): only `from typing import Iterable, List,
## Optional, Tuple` — no rich sibling imports; this is a pure leaf. Nim needs
## `std/options` for the `Optional[int]`/`Optional[str]` params
## (`precision`/`separator`) and `std/strutils` for the comma-formatting
## helpers (`formatBiggestFloat`); `Iterable[str]` → `openArray[string]`,
## `List[str]` → `openArray[string]`/`seq[string]`, `Tuple[int, str]` →
## `tuple[unit: int, suffix: string]` (a Nim named tuple — the unnamed
## `tuple[int, string]` is not valid Nim syntax; the field names `unit`/`suffix`
## mirror the return's semantics).
##
## wiring (this file): `import std/options` and `import std/strutils`.
## Proc bodies are ported (toStr/decimal/pickUnitAndSuffix implement
## filesize.py:18-88).

import std/options
import std/strutils

proc formatIntCommas(n: int): string =
  ## [Nim-only helper] Format an integer with comma thousands separators,
  ## mirroring Python's `f"{n:,}"`.
  let s = $abs(n)
  let neg = n < 0
  var built = ""
  let n2 = s.len
  for i, ch in s:
    if i > 0 and (n2 - i) mod 3 == 0:
      built.add(',')
    built.add(ch)
  result = (if neg: "-" else: "") & built

proc formatFloatCommas*(value: BiggestFloat, precision: int): string =
  ## [Nim-only helper] Format a float with comma thousands separators and
  ## `precision` decimals, mirroring Python's `"{:,.{precision}f}".format(...)`.
  ## Exported in Nim so `progress.nim` can reuse it (was duplicated locally).
  ## Handles Nim's `ffDecimal` orphan-dot at precision=0 (emits `1234.`; Python
  ## `f"{v:,.0f}"` yields `1234`) by stripping the trailing dot.
  var s = value.formatBiggestFloat(ffDecimal, precision)
  if precision == 0 and s.endsWith('.'): s = s[0..^2]
  var neg = false
  if s.len > 0 and s[0] == '-':
    neg = true
    s = s[1..^1]
  let dotPos = s.find('.')
  var intPart: string
  var fracPart: string
  if dotPos >= 0:
    intPart = s[0..<dotPos]
    fracPart = s[dotPos..^1]
  else:
    intPart = s
    fracPart = ""
  var built = ""
  let ilen = intPart.len
  for i, ch in intPart:
    if i > 0 and (ilen - i) mod 3 == 0:
      built.add(',')
    built.add(ch)
  result = (if neg: "-" else: "") & built & fracPart

proc toStr(size: int, suffixes: openArray[string], base: int,
           precision: Option[int] = some(1),
           separator: Option[string] = some(" ")): string =
  ## rich filesize.py:18-40 — `_to_str(size, suffixes, base, *, precision=1,
  ## separator=" ") -> str`: build the filesize string. `Iterable[str]` →
  ## `openArray[string]`; `Optional[int]` → `Option[int]` (default `some(1)`,
  ## the Python default is the int `1` wrapped to `Optional`); `Optional[str]`
  ## → `Option[string]` (default `some(" ")`). Private (`_`-prefixed; not in
  ## `__all__`). (body `discard` ⇒ returns `""`).
  if size == 1:
    return "1 byte"
  elif size < base:
    return formatIntCommas(size) & " bytes"
  var unit = float(base) * float(base)
  var suffix = ""
  for i, sfx in suffixes:
    suffix = sfx
    if float(size) < unit:
      break
    # Don't advance `unit` past the last suffix's power: rich's loop
    # (`for i, suffix in enumerate(suffixes, 2): unit = base**i; if size < unit:
    # break`, filesize.py:24-28) computes `unit = base**i` per iteration and
    # leaves `unit = base**(len+1)` when the loop exhausts without a break. An
    # unconditional `unit *= base` here would overshoot to `base**(len+2)` for the
    # no-break (size >= base**(len+1)) case — a trailing-multiply that makes the
    # value one `base` too small. Guard so only a non-last, non-breaking
    # iteration advances (break cases exit above before this line).
    if i < suffixes.len - 1:
      unit *= float(base)
  let value = (float(base) * float(size)) / unit
  let prec = precision.get(1)
  let sep = separator.get(" ")
  result = formatFloatCommas(value, prec) & sep & suffix

proc pickUnitAndSuffix*(size: int, suffixes: openArray[string],
                       base: int): tuple[unit: int, suffix: string] =
  ## rich filesize.py:43-49 — `pick_unit_and_suffix(size, suffixes, base)
  ## -> Tuple[int, str]`: pick a suffix and base for the given size. `List[str]`
  ## → `openArray[string]`; `Tuple[int, str]` → `tuple[unit: int, suffix: string]`. Private
  ## (`_`-prefixed; not in `__all__`). Exported in Nim so `progress.nim` can reuse it
  ## (was duplicated locally — now consolidated).
  var unit = 1
  var suffix = ""
  for i, sfx in suffixes:
    if i > 0:
      unit *= base
    suffix = sfx
    if size div base < unit:
      break
  result = (unit: unit, suffix: suffix)

proc decimal*(size: int, precision: Option[int] = some(1),
              separator: Option[string] = some(" ")): string =
  ## rich filesize.py:52-88 — `decimal(size, *, precision=1, separator=" ")
  ## -> str`: convert a filesize to a string (powers of 1000, SI prefixes:
  ## `1000 B = 1 kB`). The single public name (`__all__ = ["decimal"]`,
  ## filesize.py:13); delegates to `_to_str` with the `("kB","MB","GB","TB",
  ## "PB","EB","ZB","YB")` suffixes and `base = 1000` (filesize.py:82-87). port
  ## stub (body `discard` ⇒ returns `""`).
  result = toStr(size, ["kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"], 1000,
                 precision = precision, separator = separator)
