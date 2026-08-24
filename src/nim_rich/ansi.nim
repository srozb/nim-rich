## Nim port of `rich.ansi` (rich/ansi.py).
##
## ANSI escape-sequence handling: the `re_ansi` tokenizer regex (ansi.py:7-15),
## the `_AnsiToken`/`_ansi_tokenize` tokenizer (ansi.py:20-48), the
## `SGR_STYLE_MAP` SGR-code→style table (ansi.py:59-107) and the `AnsiDecoder`
## that turns ANSI-coded text into styled `Text` (ansi.py:120-241).
## `rich.console`/`rich.text` consume it (the `from_ansi` path).
##
## Import graph (rich/ansi.py:1-8): runtime imports are `import re`
## (ansi.py:1), `import sys` (ansi.py:2), `from contextlib import suppress`
## (ansi.py:3), `from typing import Iterable, NamedTuple, Optional` (ansi.py:4),
## `from .color import Color` (ansi.py:6), `from .style import Style`
## (ansi.py:7), `from .text import Text` (ansi.py:8). `from .console import
## Console` @ ansi.py:231 is `__main__`-only.
##
## wiring (this file):
##   `import std/[options, tables, strutils]` — `Option[string]` (`_AnsiToken.sgr`/
##                       `osc`, `Optional[str]`, ansi.py:21-22); `Table[int,
##                       string]` (`sgrStyleMap`, the `SGR_STYLE_MAP`
##                       `Dict[int, str]`); `strutils` for the manual ANSI
##                       tokenization (the Nim port tokenizes without a runtime
##                       regex).
##   `import style`      — `Style` (the `AnsiDecoder.style` field type,
##                       ansi.py:123; `_Style = Style` in `decode_line`,
##                       ansi.py:153).
##   `import text`       — `Text` (the `decode`/`decode_line` return type,
##                       ansi.py:138,146).
##   `import color`      — `Color` (`Color.fromAnsi`/`fromTriplet`,
##                       ansi.py:148-149,189-200, for the 38/48 SGR color codes
##                       in `decodeLine`).
## `sys`/`suppress` (ansi.py:2-3) are Python body-only and not ported.
##
## `re_ansi = re.compile(...)` (ansi.py:10): Python's compiled tokenizer regex.
## The Nim port does NOT port `reAnsi` — it tokenizes manually in
## `ansiTokenizeIter` (mirroring `re_ansi.finditer` without a runtime regex,
## avoiding PCRE; `reAnsi` was removed in N1). `SGR_STYLE_MAP = {...}`
## (ansi.py:59) is ported as the full 41-entry `sgrStyleMap*` table
## (ansi.py:60-107); it is NOT a placeholder.
##
## `_AnsiToken` (ansi.py:20, `NamedTuple`, private `_`) and `_ansi_tokenize`
## (ansi.py:28, private generator) are non-`*` here. `AnsiDecoder.decode`
## (ansi.py:137, generator `-> Iterable[Text]`) and `_ansi_tokenize`
## (generator `-> Iterable[_AnsiToken]`) are modelled as Nim closure iterators
## (`iterator(): T {.closure.}`, the established generator port form —
## `containers.nim` uses the same shape). Proc bodies are ported
## (ansiTokenizeIter/decode/decodeLine/initAnsiDecoder implement ansi.py:20-241).

import std/[options, tables, strutils]

import style       # Style — the AnsiDecoder.style field type (ansi.py:123).
import text        # Text — the decode/decode_line return type (ansi.py:138,146).
import color       # Color — `Color.fromAnsi`/`fromTriplet` (ansi.py:148-149,
                   # 189-200) for the 38/48 SGR color codes in `decodeLine`.

type
  AnsiToken = object
    ## rich ansi.py:20-25 — `_AnsiToken(NamedTuple)`: result of ANSI tokenization
    ## (`plain: str = ""`, `sgr: Optional[str] = ""`, `osc: Optional[str] =
    ## ""`). Private (`_`-prefixed; non-`*`). `sgr`/`osc` are `Optional[str]` →
    ## `Option[string]` (the Python defaults `""` are str, not `None`, but the
    ## *type* is `Optional[str]`). Nim-only handle.
    plain: string           ## rich ansi.py:21-21 — `plain: str = ""`.
    sgr: Option[string]     ## rich ansi.py:22-22 — `sgr: Optional[str] = ""`.
    osc: Option[string]     ## rich ansi.py:23-23 — `osc: Optional[str] = ""`.

  AnsiDecoder* = ref object of RootObj
    ## rich ansi.py:120-241 — `class AnsiDecoder`: "Translate ANSI code in to
    ## styled Text." `__init__` sets `self.style = Style.null()` (ansi.py:123);
    ## `decode` yields a `Text` per line (ansi.py:137-145); `decode_line`
    ## builds one `Text` from the SGR/OSC codes (ansi.py:147-241). `ref object
    ## of RootObj` (Python `AnsiDecoder` is a plain class with reference
    ## semantics — mutating `self.style` across tokens — so a Nim `ref` is the
    ## faithful mirror). Field mirrors `__init__` (ansi.py:123).
    style*: Style            ## rich ansi.py:123-123 — `self.style = Style.null()` (the running `Style`, mutated by SGR/OSC codes).

let
  sgrStyleMap* = {
      1: "bold", 2: "dim", 3: "italic", 4: "underline", 5: "blink",
      6: "blink2", 7: "reverse", 8: "conceal", 9: "strike",
      21: "underline2", 22: "not dim not bold", 23: "not italic",
      24: "not underline", 25: "not blink", 26: "not blink2",
      27: "not reverse", 28: "not conceal", 29: "not strike",
      30: "color(0)", 31: "color(1)", 32: "color(2)", 33: "color(3)",
      34: "color(4)", 35: "color(5)", 36: "color(6)", 37: "color(7)",
      39: "default", 40: "on color(0)", 41: "on color(1)",
      42: "on color(2)", 43: "on color(3)", 44: "on color(4)",
      45: "on color(5)", 46: "on color(6)", 47: "on color(7)",
      49: "on default", 51: "frame", 52: "encircle", 53: "overline",
      54: "not frame not encircle", 55: "not overline", 90: "color(8)",
      91: "color(9)", 92: "color(10)", 93: "color(11)", 94: "color(12)",
      95: "color(13)", 96: "color(14)", 97: "color(15)",
      100: "on color(8)", 101: "on color(9)", 102: "on color(10)",
      103: "on color(11)", 104: "on color(12)", 105: "on color(13)",
      106: "on color(14)", 107: "on color(15)"
    }.toTable
    ## rich ansi.py:59-107 — `SGR_STYLE_MAP = {...}`: the SGR code → style-name
    ## table (41 entries, ansi.py:60-107; `SGR_STYLE_MAP = {` @59, closes `}`
    ## @107; e.g. `1: "bold"`, `22: "not dim not bold"`, `38: …` handled
    ## specially in `decode_line`). `Table[int, string]` (the `Dict[int, str]`);
    ## `let` + `{.used.}` placeholder (empty); body wires the
    ## faithful 41-entry table. Used by `decode_line` (ansi.py:172).

iterator ansiTokenizeIter(ansiText: string): AnsiToken {.closure.} =
  ## [Nim-only helper] Faithful port of `_ansi_tokenize` (ansi.py:28-48): a
  ## manual ESC scanner that yields `AnsiToken`s (plain / sgr / osc),
  ## mirroring `re_ansi.finditer` without a runtime regex (avoids PCRE
  ## verbose-mode porting). SGR (`\x1b[...m`) → sgr codes; OSC
  ## (`\x1b]...\x1b\\`) → osc content; `(` charset → skip next char; other
  ## escapes consumed/skipped per ansi.py:34-48.
  let s = ansiText
  let n = s.len
  var position = 0
  var i = 0
  while i < n:
    if s[i] != '\x1b':
      inc i
      continue
    if i + 1 >= n:
      inc i
      continue
    let escStart = i
    let c1 = s[i + 1]
    if c1 == ']':
      # OSC: \x1b] (.*?) \x1b\\
      var j = i + 2
      var term = -1
      while j + 1 < n:
        if s[j] == '\x1b' and s[j + 1] == '\\':
          term = j
          break
        inc j
      if term >= 0:
        let content = s[i + 2 ..< term]
        let endPos = term + 2
        if escStart > position:
          yield AnsiToken(plain: s[position ..< escStart])
        yield AnsiToken(plain: "", sgr: none(string), osc: some(content))
        position = endPos
        i = endPos
      else:
        inc i
      continue
    elif c1 == '[':
      # CSI: \x1b [0-?]* [ -/]* [@-~]
      var j = i + 2
      while j < n and s[j] >= '0' and s[j] <= '?':
        inc j
      while j < n and s[j] >= ' ' and s[j] <= '/':
        inc j
      if j < n and s[j] >= '@' and s[j] <= '~':
        let sgrFull = s[i + 1 .. j]
        let endPos = j + 1
        if escStart > position:
          yield AnsiToken(plain: s[position ..< escStart])
        if sgrFull == "(":
          position = endPos + 1
          i = endPos + 1
        elif sgrFull.endsWith("m"):
          yield AnsiToken(plain: "",
                          sgr: some(sgrFull[1 ..< sgrFull.len - 1]),
                          osc: none(string))
          position = endPos
          i = endPos
        else:
          # non-SGR CSI: consumed silently (no token), per ansi.py:39-41.
          position = endPos
          i = endPos
      else:
        inc i
      continue
    elif c1 >= '0' and c1 <= '?':
      # alt1: \x1b[0-?] -> (None, None)
      let endPos = i + 2
      if escStart > position:
        yield AnsiToken(plain: s[position ..< escStart])
      yield AnsiToken(plain: "", sgr: none(string), osc: none(string))
      position = endPos
      i = endPos
      continue
    elif c1 == '(' or (c1 >= '-' and c1 <= '_'):
      # alt3 single char: \x1b + one charset char (after alt1/alt2 precedence)
      let sgrFull = s[i + 1 .. i + 1]
      let endPos = i + 2
      if escStart > position:
        yield AnsiToken(plain: s[position ..< escStart])
      if sgrFull == "(":
        position = endPos + 1
        i = endPos + 1
      elif sgrFull.endsWith("m"):
        yield AnsiToken(plain: "",
                        sgr: some(sgrFull[1 ..< sgrFull.len - 1]),
                        osc: none(string))
        position = endPos
        i = endPos
      else:
        position = endPos
        i = endPos
      continue
    else:
      inc i
      continue
  if position < n:
    yield AnsiToken(plain: s[position ..< n])

proc ansiTokenize(ansiText: string): iterator(): AnsiToken {.closure.} =
  ## rich ansi.py:28-48 — `_ansi_tokenize(ansi_text: str) -> Iterable
  ## [_AnsiToken]`: tokenize a string into plain text and ANSI codes, yielding
  ## `_AnsiToken`s (plain / sgr / osc). A generator → Nim closure iterator
  ## (`iterator(): AnsiToken {.closure.}`). Private (`_`-prefixed; non-`*`).
  ## Delegates to the named `ansiTokenizeIter` closure iterator via an
  ## anonymous `iterator(): AnsiToken {.closure.}` — Nim 2.2.10 rejects
  ## first-class assignment of a *called* closure iterator
  ## (`result = ansiTokenizeIter(ansiText)` → "attempting to call routine"),
  ## so the delegation `for tok in ansiTokenizeIter(ansiText): yield tok`
  ## (a direct iterator call inside `for`, the canonical closure-iterator
  ## consumption form) returns the faithful generator.
  result = iterator(): AnsiToken {.closure.} =
    for tok in ansiTokenizeIter(ansiText):
      yield tok

proc initAnsiDecoder*(): AnsiDecoder =
  ## rich ansi.py:122-124 — `AnsiDecoder.__init__(self) -> None`:
  ## `self.style = Style.null()`. Naming: `__init__`->`initAnsiDecoder` (the
  ## class has no positional `__init__` args, so the Nim constructor takes
  ## none). (body `discard` ⇒ returns `default(AnsiDecoder)`).
  result = AnsiDecoder()
  result.style = Style.null()

# Forward declaration so `decodeIter` can call `decodeLine` (the richbase
# `splitCellsImpl` precedent — Nim resolves the call to the later definition).
proc decodeLine*(self: AnsiDecoder, line: string): Text

iterator decodeIter(self: AnsiDecoder, terminalText: string): Text {.closure.} =
  ## [Nim-only helper] Faithful port of `AnsiDecoder.decode` (ansi.py:137-145):
  ## split after each `\n` (mirroring `re.split(r"(?<=\\n)", terminal_text)` —
  ## producing a trailing empty piece when the text ends with `\n`) and yield
  ## `decodeLine(piece.rstrip("\\n"))` per piece (ansi.py:139-143). A manual
  ## split avoids a lookbehind regex.
  let s = terminalText
  var start = 0
  for k in 0 ..< s.len:
    if s[k] == '\n':
      var piece = s[start .. k]
      var pe = piece.len
      while pe > 0 and piece[pe - 1] == '\n':
        dec pe
      yield self.decodeLine(piece[0 ..< pe])
      start = k + 1
  var last = s[start ..< s.len]
  var le = last.len
  while le > 0 and last[le - 1] == '\n':
    dec le
  yield self.decodeLine(last[0 ..< le])

proc decode*(self: AnsiDecoder, terminalText: string): iterator(): Text {.closure.} =
  ## rich ansi.py:137-145 — `AnsiDecoder.decode(self, terminal_text: str)
  ## -> Iterable[Text]`: split on newlines and `yield self.decode_line(...)` per
  ## line (ansi.py:139-143). A generator → Nim closure iterator
  ## (`iterator(): Text {.closure.}`). Body needs `re.split`
  ## (ansi.py:139). Delegates to the named `decodeIter` closure iterator via
  ## an anonymous `iterator(): Text {.closure.}` — Nim 2.2.10 rejects
  ## first-class assignment of a *called* closure iterator
  ## (`result = decodeIter(self, terminalText)` → "attempting to call
  ## routine"), so the delegation `for t in decodeIter(self, terminalText):
  ## yield t` (a direct iterator call inside `for`, the canonical
  ## closure-iterator consumption form) returns the faithful generator.
  result = iterator(): Text {.closure.} =
    for t in decodeIter(self, terminalText):
      yield t

proc decodeLine*(self: AnsiDecoder, line: string): Text =
  ## rich ansi.py:147-241 — `AnsiDecoder.decode_line(self, line: str) -> Text`:
  ## decode one line of ANSI codes into a marked-up `Text`, walking SGR/OSC
  ## codes via `_ansi_tokenize` + `SGR_STYLE_MAP` (ansi.py:148-241). Naming:
  ## `decode_line`->`decodeLine`. Body needs `color.Color.fromAnsi`/
  ## `fromRgb` (ansi.py:148-149,189-200) + `style.Style` (ansi.py:153) +
  ## `text.Text` (ansi.py:151). (body `discard` ⇒ returns
  ## `default(Text)`).
  result = initText()
  var l = line
  let ri = l.rfind('\r')
  if ri >= 0:
    l = l[ri + 1 ..< l.len]
  for tok in ansiTokenizeIter(l):
    if tok.plain.len > 0:
      if self.style != nil and self.style.bool:
        discard result.append(tok.plain, self.style)
      else:
        discard result.append(tok.plain)
    elif tok.osc.isSome:
      let osc = tok.osc.get
      if osc.startsWith("8;"):
        let rest = osc[2 ..< osc.len]
        let semi = rest.find(";")
        if semi >= 0:
          let link = rest[semi + 1 ..< rest.len]
          self.style = self.style.updateLink(
            if link.len > 0: some(link) else: none(string))
    elif tok.sgr.isSome:
      let sgr = tok.sgr.get
      var codes: seq[int] = @[]
      for part in sgr.split(";"):
        if part.len == 0:
          codes.add(0)
        else:
          var allDigits = true
          for c in part:
            if c < '0' or c > '9':
              allDigits = false
              break
          if allDigits:
            codes.add(min(255, parseInt(part)))
      var idx = 0
      while idx < codes.len:
        let code = codes[idx]
        inc idx
        if code == 0:
          self.style = Style.null()
        elif sgrStyleMap.hasKey(code):
          self.style = self.style + some(Style.parse(sgrStyleMap[code]))
        elif code == 38:
          if idx < codes.len:
            let colorType = codes[idx]
            inc idx
            if colorType == 5 and idx < codes.len:
              let n8 = codes[idx]
              inc idx
              self.style = self.style +
                some(Style.fromColor(some(Color.fromAnsi(n8))))
            elif colorType == 2 and idx + 2 < codes.len:
              let r = codes[idx]
              let g = codes[idx + 1]
              let b = codes[idx + 2]
              idx += 3
              self.style = self.style +
                some(Style.fromColor(
                  some(Color.fromTriplet((red: r, green: g, blue: b)))))
        elif code == 48:
          if idx < codes.len:
            let colorType = codes[idx]
            inc idx
            if colorType == 5 and idx < codes.len:
              let n8 = codes[idx]
              inc idx
              self.style = self.style +
                some(Style.fromColor(none(Color), some(Color.fromAnsi(n8))))
            elif colorType == 2 and idx + 2 < codes.len:
              let r = codes[idx]
              let g = codes[idx + 1]
              let b = codes[idx + 2]
              idx += 3
              self.style = self.style +
                some(Style.fromColor(
                  none(Color),
                  some(Color.fromTriplet((red: r, green: g, blue: b)))))
