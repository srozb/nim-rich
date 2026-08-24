## Port of `rich.markup` (rich/markup.py).
##
## `markup` parses Rich's console-markup syntax (`"[bold red]text[/]"`) into a
## `Text` with style spans, and `escape` quotes brackets so literal text is not
## interpreted as markup.
##
## Import graph (markup.py:1-12): `import re` (markup.py:1) → the compiled
## regexes `RE_TAGS` (markup.py:8-13) / `RE_HANDLER` (markup.py:16) are body
## body concerns; their *patterns* are persisted below as `const` strings (no
## `std/re` import , keeping this a clean leaf). `from ast import
## literal_eval` (markup.py:2) and `from operator import attrgetter`
## (markup.py:3) are body-only. `from ._emoji_replace import _emoji_replace`
## (markup.py:5) → `emoji_replace` does NOT exist yet (body); `from .emoji
## import EmojiVariant` (markup.py:6) → `emoji`; `from .errors import
## MarkupError` (markup.py:7) is a body BODY import (raised only in `render`'s
## body), so `errors` is NOT imported  (stub body is `discard`);
## `from .style import Style`
## (markup.py:8) → `style`; `from .text import Span, Text` (markup.py:9) →
## `text`. `typing` aliases (`_ReStringMatch`/`_ReSubCallable`/`_EscapeSubMethod`,
## markup.py:35-40) are private Callable types — Nim-only, documented not
## declared.
##
## Module-level data (markup.py:8-16): `RE_TAGS = re.compile(r"""((\\*)\[([a-z#/@][^[]*?)])""", re.VERBOSE)` (markup.py:8-13) → `const reTagsPattern`; `RE_HANDLER = re.compile(r"^([\w.]*?)(\(.*?\))?$")` (markup.py:16) → `const reHandlerPattern`; the `escape` default `_escape = re.compile(r"(\\*)(\[[a-z#/@][^[]*?])").sub` (markup.py:26-30) → `const escapePattern`. The compiled `Regex` objects are built in body (the bodies call `.finditer`/`.sub`).
##
## Faithfulness: `Tag` (markup.py:19-33) is a `NamedTuple` → Nim named tuple
## `tuple[name: string, parameters: Option[string]]` (value type; `parameters:
## Optional[str]` → `Option[string]`). `Tag.__str__` (markup.py:24-27) → `str`;
## `Tag.markup` (`@property` markup.py:29-33) → a free `markup` proc (Nim
## tuples have no attached properties). `escape(markup: str)` (markup.py:43-62)
## → `escape` (the private `_escape` default is an internal `re.sub` hook,
## omitted from the Nim signature). `_parse(markup: str)` (markup.py:64-99) is
## private → `parse` (no `*`), returning the `(position, text, tag)` triples as
## `seq[ParsedToken]`. `render(markup: str, style: Union[str, Style] = "",
## emoji: bool = True, emoji_variant: Optional[EmojiVariant] = None) -> Text`
## (markup.py:101-185) → `render`; `style` keeps the `StyleType` typeclass with
## default `""` (panel.nim pattern); `emoji_variant` → `Option[EmojiVariant] =
## none(EmojiVariant)`.
##
## Naming: `__str__`→`str`, `markup`→`markup` (property→proc); `escape`/`render`
## keep their names; `_parse`→`parse` (private). Proc bodies are `discard`
## (port)` = nil ref / empty seq).

import std/[options, strutils, json, tables, algorithm]

import errors         # MarkupError — raised in `render`'s body (markup.py:135,
                     # 141, 158, 167; a Body dep, now wired).
import emoji          # EmojiVariant — the emoji_variant param type (the real
                     # `emoji.EmojiVariant`).
import style          # Style, StyleType — the style param (Union[str, Style]).
import text except EmojiVariant
                     # Span, Text — the render return type + Span (body, Phase
                     # 1). `text` re-exports a PROVISIONAL `EmojiVariant` (frozen
                     # Wave 3, to be dropped when `emoji.nim` exists); `except
                     # EmojiVariant` excludes it so the unqualified `EmojiVariant`
                     # in `render` resolves to the real `emoji.EmojiVariant`.
                     # (Unqualified `EmojiVariant` is not shadowed by the
                     # `emoji: bool` param — only `emoji.X` module-qualification
                     # would be.)

const
  reTagsPattern* = r"((\\*)\[([a-z#/@][^[]*?)])"
    ## rich markup.py:8-13 — `RE_TAGS = re.compile(r"""((\\*)\[([a-z#/@][^[]*?)])""",
    ## re.VERBOSE)`: the tag-matching regex. Persisted as the raw pattern; the
    ## compiled `Regex` (with `re.VERBOSE`) is built in body.

  reHandlerPattern* = r"^([\w.]*?)(\(.*?\))?$"
    ## rich markup.py:16 — `RE_HANDLER = re.compile(r"^([\w.]*?)(\(.*?\))?$")`:
    ## the `@`-handler parameter regex. Persisted as the raw pattern.

  escapePattern* = r"(\\*)(\[[a-z#/@][^[]*?])"
    ## rich markup.py:26 — the `escape` default `_escape = re.compile(
    ## r"(\\*)(\[[a-z#/@][^[]*?])").sub`. Persisted as the raw pattern.

type
  Tag* = tuple[name: string, parameters: Option[string]]
    ## rich markup.py:19-23 — `class Tag(NamedTuple)`: a tag in console markup.
    ## `name: str` (markup.py:21) and `parameters: Optional[str]` (markup.py:23,
    ## any additional parameters after `=`). A Nim named tuple (value type,
    ## matching `NamedTuple`).

  ParsedToken = tuple[position: int, text: Option[string], tag: Option[Tag]]
    ## rich markup.py:64-99 — a single `(position, text, tag)` triple yielded by
    ## `_parse` (markup.py:97): `position` is the char offset, `text` is the
    ## optional plain-text segment (`Optional[str]`), `tag` is the optional
    ## `Tag` (`Optional[Tag]`). Private (used by `parse`).

proc str*(self: Tag): string =
  ## rich markup.py:24-27 — `Tag.__str__(self) -> str`: `self.name if
  ## self.parameters is None else f"{self.name} {self.parameters}"`.
  ## `__str__`→`str` (consistent with `emoji.nim`/`control.nim`).
  if self.parameters.isSome:
    result = self.name & " " & self.parameters.get
  else:
    result = self.name

proc markup*(self: Tag): string =
  ## rich markup.py:29-33 — `Tag.markup` (`@property`): the string representation
  ## of this tag — `f"[{self.name}]"` if `parameters is None` else
  ## `f"[{self.name}={self.parameters}]"`. A free proc (Nim tuples carry no
  ## attached properties).
  if self.parameters.isSome:
    result = "[" & self.name & "=" & self.parameters.get & "]"
  else:
    result = "[" & self.name & "]"

proc escape*(markup: string): string =
  ## rich markup.py:43-62 — `escape(markup: str, _escape: _EscapeSubMethod =
  ## re.compile(r"(\\*)(\[[a-z#/@][^[]*?])").sub) -> str`: escape text so it
  ## won't be interpreted as markup (double backslashes before brackets,
  ## markup.py:50-56; trailing-backslash guard markup.py:58-60). The private
  ## `_escape` default (a `re.sub` bound method) is an internal optimisation
  ## hook, omitted from the Nim signature. Ported as a manual scan of the
  ## `(\\*)(\[[a-z#/@][^[]*?])` pattern (the host `libpcre` runtime dlopen is
  ## unavailable, so `std/re` is avoided).
  proc isTagChar(c: char): bool {.inline.} = c in {'a'..'z', '#', '/', '@'}
  let n = markup.len
  var i = 0
  while i < n:
    let bsStart = i
    while i < n and markup[i] == '\\': inc i
    let bs = i - bsStart
    var consumed = false
    if i < n and markup[i] == '[':
      var j = i + 1
      if j < n and isTagChar(markup[j]):
        inc j
        while j < n and markup[j] != '[' and markup[j] != ']': inc j
        if j < n and markup[j] == ']':
          for k in 1 .. (bs * 2): result.add('\\')
          result.add('\\')
          result.add(markup[i .. j])
          i = j + 1
          consumed = true
    if not consumed:
      for k in 1 .. bs: result.add('\\')
      if bs == 0 and i < n:
        result.add(markup[i])
        inc i
  if result.len >= 1 and result[^1] == '\\' and
      not (result.len >= 2 and result[^2] == '\\'):
    result.add('\\')

proc parse*(markup: string): seq[ParsedToken] =
  ## rich markup.py:64-99 — `_parse(markup: str) -> Iterable[Tuple[int,
  ## Optional[str], Optional[Tag]]]`: parse markup into an iterable of
  ## `(position, text, tag)` triples. Private (Python `_parse` underscore) —
  ## no `*`; `render` calls it internally. Ported as a manual scan of the
  ## `((\\*)\[([a-z#/@][^[]*?)])` pattern (no `std/re`, see `escape`).
  proc isTagChar(c: char): bool {.inline.} = c in {'a'..'z', '#', '/', '@'}
  let n = markup.len
  var position = 0
  var i = 0
  while i < n:
    let bsStart = i
    var p = i
    while p < n and markup[p] == '\\': inc p
    let escapes = p - bsStart
    var matched = false
    if p < n and markup[p] == '[':
      var j = p + 1
      if j < n and isTagChar(markup[j]):
        inc j
        while j < n and markup[j] != '[' and markup[j] != ']': inc j
        if j < n and markup[j] == ']':
          matched = true
          let mStart = bsStart
          let mEnd = j            # index of the closing ']'
          let endExcl = mEnd + 1
          if mStart > position:
            result.add((position, some(markup[position ..< mStart]),
                        none(Tag)))
          var startVar = mStart
          let backslashes = escapes div 2
          let escaped = escapes mod 2
          if escapes > 0:
            if backslashes > 0:
              result.add((mStart, some(repeat("\\", backslashes)),
                          none(Tag)))
              startVar = mStart + backslashes * 2
            if escaped > 0:
              result.add((startVar, some(markup[p .. mEnd]), none(Tag)))
              position = endExcl
              i = endExcl
          if escaped == 0:
            let tagText = markup[p + 1 ..< mEnd]
            let eqPos = tagText.find('=')
            var name = tagText
            var params: Option[string] = none(string)
            if eqPos >= 0:
              name = tagText[0 ..< eqPos]
              params = some(tagText[eqPos + 1 ..< tagText.len])
            result.add((startVar, none(string),
                        some((name: name, parameters: params))))
            position = endExcl
            i = endExcl
    if not matched:
      inc i
  if position < n:
    result.add((position, some(markup[position ..< n]), none(Tag)))

proc emojiReplaceForMarkup(text: string, v: Option[EmojiVariant]): string =
  ## rich markup.py:107/126 — dispatch `_emoji_replace` (ported in `emoji.nim`
  ## as `emojiReplace`) with the per-call `default_variant`. Defined at module
  ## scope so the `emoji` module symbol is not shadowed by `render`'s
  ## `emoji: bool` param (markup.py:103) — `emoji.emojiReplace` would resolve
  ## to the param inside `render`. The no-`[` fast path passes `emoji_variant`
  ## (markup.py:107); the parse slow path passes `None` (markup.py:126).
  emoji.emojiReplace(text, v)

proc render*(markup: string, style: StyleType = "", emoji: bool = true,
            emojiVariant: Option[EmojiVariant] = none(EmojiVariant)): Text =
  ## rich markup.py:101-185 — `render(markup: str, style: Union[str, Style] =
  ## "", emoji: bool = True, emoji_variant: Optional[EmojiVariant] = None) ->
  ## Text`: render console markup into a `Text` instance, applying style tags
  ## as spans. `style` keeps the `StyleType` typeclass with default `""`
  ## (panel.nim pattern); `emoji_variant` default `None` →
  ## `none(EmojiVariant)`. Raises `MarkupError` on a syntax error (markup.py:135,
  ## 141, 158, 167).
  # `_emoji_replace` (rich._emoji_replace) is ported in `emoji.nim` as
  # `emojiReplace`; the module-scope `emojiReplaceForMarkup` wrapper dispatches
  # it with the per-call `default_variant` (the no-`[` fast path passes
  # `emoji_variant`, markup.py:107; the parse slow path passes `None`,
  # markup.py:126).
  if "[" notin markup:
    let plain = if emoji: emojiReplaceForMarkup(markup, emojiVariant) else: markup
    return initText(plain, style = style)
  let text = initText(style = style)
  var styleStack: seq[(int, Tag)] = @[]
  var spans: seq[Span] = @[]
  for (pos, plainText, tag) in parse(markup):
    if plainText.isSome:
      var pt = plainText.get.replace("\\[", "[")
      if emoji: pt = emojiReplaceForMarkup(pt, none(EmojiVariant))
      discard text.append(pt)
    elif tag.isSome:
      let t = tag.get
      if t.name.startsWith("/"):
        let styleName = t.name[1 ..< t.name.len].strip()
        var startIdx: int
        var openTag: Tag
        var got = false
        if styleName.len > 0:
          let normalized = Style.normalize(styleName)
          for idx in countdown(styleStack.high, 0):
            if styleStack[idx][1].name == normalized:
              let pair = styleStack[idx]
              startIdx = pair[0]
              openTag = pair[1]
              styleStack.del(idx)
              got = true
              break
          if not got:
            raise newException(MarkupError,
              "closing tag '" & t.markup & "' at position " & $pos &
              " doesn't match any open tag")
        else:
          if styleStack.len == 0:
            raise newException(MarkupError,
              "closing tag '[/]' at position " & $pos & " has nothing to close")
          let pair = styleStack.pop()
          startIdx = pair[0]
          openTag = pair[1]
          got = true
        if openTag.name.startsWith("@"):
          # `@handler(params)` meta tags: parse the `()`-parameters as a JSON
          # literal (a best-effort stand-in for Python's `ast.literal_eval` —
          # tuples become JSON arrays) and wrap as `(handler_name, params)` when
          # a handler name is present. The result is passed to `Style(meta=…)`;
          # the exact meta structure is consumed once `Style.meta` is wired.
          var metaParams: JsonNode = newJArray()
          if openTag.parameters.isSome:
            let parameters = openTag.parameters.get.strip()
            var handlerName = ""
            var rawParams = "()"
            let lp = parameters.find('(')
            if lp >= 0:
              handlerName = parameters[0 ..< lp]
              rawParams = parameters[lp ..< parameters.len]
            else:
              rawParams = parameters
            if rawParams == "()":
              metaParams = newJArray()
            else:
              try:
                metaParams = parseJson(rawParams)
              except JsonParsingError:
                raise newException(MarkupError,
                  "error parsing " & rawParams & " in " & openTag.parameters.get)
            if handlerName.len > 0:
              let inner = newJArray()
              if metaParams.kind == JArray:
                for e in metaParams:
                  inner.add(e)
              else:
                inner.add(metaParams)
              let tup = newJArray()
              tup.add(newJString(handlerName))
              tup.add(inner)
              metaParams = tup
          var metaTbl = initTable[string, JsonNode]()
          metaTbl[openTag.name] = metaParams
          spans.add(Span(start: startIdx, `end`: text.len,
                        style: StyleValue(kind: svkStyle,
                                          stv: initStyle(
                                              meta = some(metaTbl)))))
        else:
          spans.add(Span(start: startIdx, `end`: text.len,
                        style: StyleValue(kind: svkStr, strv: str(openTag))))
      else:
        let normalizedTag = (name: Style.normalize(t.name),
                             parameters: t.parameters)
        styleStack.add((text.len, normalizedTag))
  let textLength = text.len
  while styleStack.len > 0:
    let pair = styleStack.pop()
    let st = str(pair[1])
    if st.len > 0:
      spans.add(Span(start: pair[0], `end`: textLength,
                    style: StyleValue(kind: svkStr, strv: st)))
  var sorted = reversed(spans)
  sorted.sort(proc(a, b: Span): int = cmp(a.start, b.start))
  text.setSpans(sorted)
  result = text
