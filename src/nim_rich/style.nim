## Port of `rich.style` (rich/style.py).
##
## A terminal style: a (foreground) color, a background color, and 13 tri-state
## attributes (on/off/unset), plus a link URL and meta data. `Style` is a
## `ref object of StyleRef` (Python `Style` has reference semantics, style.py:40).
##
## Sibling imports: `richbase` (`StyleRef` base), `color` (`Color`,
## `ColorSystem`, `ColorParseError`, `blendRgb` — the Python import is
## `from .color import Color, ColorParseError, ColorSystem, blend_rgb`,
## style.py:10).
## Deferred (body-only, not imported/wired): `rich.errors`
## (`errors.StyleSyntaxError`, style.py:9, raised in `parse`/`chain`),
## `rich.repr` (`rich_repr` decorator, style.py:11), `rich.terminal_theme`
## (`DEFAULT_TERMINAL_THEME`, style.py:12; used in `get_html_style` body).
## Module-level callables `_hash_getter` (style.py:14) and `_id_generator`
## (style.py:22), and class data `_style_map` (style.py:90) /
## `STYLE_ATTRIBUTES` (style.py:106) are body-only and deferred to body.
##
## Forward placeholder types (`TerminalTheme`, `Result`) are private and stand
## in for not-yet-written modules; removed when those are imported. Bodies are
## ports (`discard`).
##
## Naming notes: Python `_`-private instance fields are exported here with
## Nim-idiomatic names (the module boundary provides encapsulation). Pure
## getter properties (`color`/`bgcolor`/`link`/`link_id`, which only `return
## self._<field>`) are merged into the corresponding exported field (the field
## type equals the property return type); transforming properties
## (`transparent_background`/`background_style`/`meta`/`without_color`) and the
## 13 `_Bit` descriptor attributes are modelled as procs. `_null` is named
## `isNull` to avoid clashing with the `null` classmethod. `Dict[str, Any]`
## meta is modelled as `Table[string, JsonNode]` (rich meta is JSON metadata).

import std/[options, hashes, tables, json, macros, strutils, algorithm]

import richbase
import color
import color_triplet
import errors
from repr import Result, ReprArg, ReprArgKind

type
  TerminalTheme = object
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] rich
    ## `rich.terminal_theme.TerminalTheme` — `terminal_theme.py:9` (`class
    ## TerminalTheme`); the `theme` parameter of `Style.get_html_style`
    ## (style.py:564). It rejects no legal Python variant: the parameter
    ## defaults to `none(TerminalTheme)` (Python `theme=None`, style.py:564) and
    ## accepts `some(TerminalTheme())`; the real `TerminalTheme` replaces this
    ## placeholder by name without changing the signature. Removed when
    ## `terminal_theme.nim` is imported.

  Bit* = object
    ## rich style.py:25 — `_Bit`: a descriptor to get/set a style attribute bit.
    ## Faithful declaration of the Python descriptor class; the 13 style
    ## attributes are modelled as procs (below) rather than `Bit` instances
    ## (Nim has no descriptor protocol), so `Bit` is retained for API
    ## completeness.
    bit*: int          ## rich style.py:31 — `self.bit = 1 << bit_no` (`__init__`).

  StyleType* = string or Style
    ## rich style.py:19 — `StyleType = Union[str, "Style"]`. Styles and style
    ## definitions (strings) are often interchangeable.

  StyleOptKind* = enum
    ## [NON-NARROWING TEMPORARY HANDLE] Nim-only discriminator for the
    ## `StyleOpt` union (below), which models rich `Optional[StyleType]` =
    ## `Optional[Union[str, "Style"]]` (style.py:19, 405). Refined/removed
    ## when a faithful `StyleType` value union is introduced before the port
    ## gate; does not narrow any legal Python variant.
    sokNone   ## the `None` arm of `Optional[StyleType]`.
    sokStr    ## the `str`  arm (`StyleType = Union[str, Style]`, style.py:19).
    sokStyle  ## the `Style` arm (`StyleType = Union[str, Style]`, style.py:19).

  StyleOpt* = object
    ## [NON-NARROWING TEMPORARY HANDLE] rich `Optional[StyleType]` =
    ## `Optional[Union[str, "Style"]]` (style.py:19, 405) — a value that is
    ## `None`, a `str` definition, or a `Style`. Modelled as a Nim case object
    ## (a true tagged union) so `Style.pick_first(cls, *values:
    ## Optional[StyleType])` (style.py:405) can accept a *heterogeneous*
    ## varargs of `None` positions, `str` definitions and `Style` objects in a
    ## single call (Python's `*values` is a heterogeneous tuple; Nim `varargs`
    ## requires a uniform element type, so the element is this union). The four
    ## `toStyleOpt*` converters (below) accept every legal Python variant
    ## (`string`, `Style`, `Option[string]`, `Option[Style]`) and reject
    ## illegal ones (e.g. `int`), so `pickFirst(Style, none(string), "red")`
    ## compiles while `pickFirst(Style, 5)` is rejected. `pickFirst` also
    ## returns `StyleOpt` (the `StyleType` union; `sokNone` is unreachable for a
    ## successful pick — `pick_first` raises `ValueError` if all values are
    ## `None`, style.py:408-409).
    case kind*: StyleOptKind
    of sokNone: discard
    of sokStr: strv*: string
    of sokStyle: stv*: Style

  Style* = ref object of StyleRef
    ## rich style.py:40 — `Style` (`@rich_repr` style.py:39). A terminal style.
    ## `ref` mirrors Python reference semantics. Fields map the Python
    ## `_`-private slots (style.py:76-86); pure-getter properties are merged in.
    color*: Option[Color]            ## rich style.py:67 `_color` + style.py:448 `color` property (getter).
    bgcolor*: Option[Color]          ## rich style.py:68 `_bgcolor` + style.py:453 `bgcolor` property (getter).
    attributes*: int                 ## rich style.py:69 `_attributes`.
    setAttributes*: int              ## rich style.py:70 `_set_attributes`.
    link*: Option[string]           ## rich style.py:80 `_link` + style.py:458 `link` property (getter).
    linkId*: string                 ## rich style.py:81 `_link_id` + style.py:290 `link_id` property (getter).
    ansi*: Option[string]           ## rich style.py:82 `_ansi` (rendered ANSI codes cache).
    styleDefinition*: Option[string] ## rich style.py:83 `_style_definition`.
    hashValue*: Option[int]         ## rich style.py:71 `_hash` (renamed; `hash` is the `__hash__` proc).
    isNull*: bool                   ## rich style.py:72 `_null` (renamed to avoid the `null` classmethod clash).
    metaBytes*: Option[seq[byte]]   ## rich style.py:73 `_meta` (pickled meta; `meta` proc deserialises it).

  StyleStack* = ref object of RootObj
    ## rich style.py:765 — `StyleStack`: a stack of styles.
    stack*: seq[Style]               ## rich style.py:771 `_stack` (stack of styles; `[default_style]` initially).

  StyleValueKind* = enum
    ## [Nim-only discriminator] for `StyleValue` (the `Union[str, Style]` value
    ## handle), mirroring `StyleOptKind` but WITHOUT the `None` arm — faithful
    ## to `Union[str, Style]` (text.py:54 `Span.style`; also `Text.style`
    ## text.py:158, `Emoji.style` emoji.py:33), which has no `None`.
    svkStr    ## the `str`   arm (`Union[str, Style]`).
    svkStyle  ## the `Style` arm (`Union[str, Style]`).

  StyleValue* = object
    ## rich `Union[str, Style]` (text.py:54 `Span.style`) as a Nim case object
    ## (a true tagged union) so it can be stored in a field (`Span.style`,
    ## `Text.style` text.py:158, `Emoji.style` emoji.py:33). Unlike `StyleOpt`
    ## (which models `Optional[StyleType]` and adds the `None` arm), `StyleValue`
    ## has NO `None` arm — faithful to `Union[str, Style]`. The `toStyleValue*`
    ## converters accept both legal variants (`string`, `Style`); `int` is
    ## rejected. MOVED here from `text.nim` so foundation module `emoji` can
    ## import it within the 10-module set; later modules import it
    ## from `style`, not `text`.
    case kind*: StyleValueKind
    of svkStr:
      strv*: string   ## the `str` arm — a style definition string.
    of svkStyle:
      stv*: Style      ## the `Style` arm — a `Style` instance.

# ---------------------------------------------------------------------------
# body private helpers (module-level; not exported). Mirror Python
# `style.py` module-level callables `_id_generator` (style.py:22) and the
# `_style_map` (style.py:90) used by `_make_ansi_codes`. Meta is serialised
# as canonical JSON (sorted keys) for deterministic hashing (Python uses
# `pickle.dumps`; JSON is the Nim handle for `Dict[str, Any]`). The
# `styleOnMacro` macro implements `Style.on` (style.py:258) by building a meta
# table from `key = value` handlers forwarded by the `on` template.
#
# NOTE: this Nim toolchain does not allow forward references to procs defined
# later in the same module, so helpers are ordered before their users and
# `newStyleFromMeta`/`styleOnMacro` follow `fromMeta`.
# ---------------------------------------------------------------------------

var idCounter = 0                  # rich style.py:22 — `_id_generator` (count()).
proc nextId(): int =
  ## rich style.py:22 — `next(_id_generator)`: a monotonic link id.
  inc idCounter
  result = idCounter

const styleMapArr = ["1", "2", "3", "4", "5", "6", "7", "8", "9",
                     "21", "51", "52", "53"]  # rich style.py:90 — `_style_map`.

proc pyReprStr(s: string): string =
  ## Best-effort Python `repr` for a string (single-quoted), mirroring
  ## `f"{word!r}"` in `parse` errors (style.py:529,538,546,556).
  result = "'"
  for ch in s:
    if ch == '\\': result.add("\\\\")
    elif ch == '\'': result.add("\\'")
    else: result.add(ch)
  result.add("'")

proc toJsonNode(x: auto): JsonNode =
  ## Wrap an `on` handler value as a `JsonNode` (the Nim handle for `Any`).
  ## Uses std/json `%` (single-arg; std/strutils `%` is two-arg, so this
  ## resolves to json unambiguously).
  result = %x

proc toColorOpt(c: Option[Color] or Color or string): Option[Color] =
  ## rich style.py:151 — `_make_color`: coerce a `color`/`bgcolor` param
  ## (`Option[Color] or Color or string`) to `Option[Color]`.
  when typeof(c) is Option[Color]:
    result = c
  elif typeof(c) is Color:
    result = some(c)
  else:
    result = some(Color.parse(c))

proc metaToBytes(meta: Table[string, JsonNode]): seq[byte] =
  ## Serialise meta to canonical JSON bytes (sorted keys) — the Nim
  ## equivalent of Python `pickle.dumps(meta)` (style.py:158).
  var keys: seq[string] = @[]
  for k in meta.keys: keys.add(k)
  sort(keys)
  var s = "{"
  for i, k in keys:
    if i > 0: s.add(',')
    s.add('"')
    s.add(k)
    s.add('"')
    s.add(':')
    s.add($meta[k])
  s.add('}')
  result = cast[seq[byte]](s)

proc bytesToMeta(b: seq[byte]): Table[string, JsonNode] =
  ## Deserialise meta from JSON bytes — the Nim equivalent of Python
  ## `pickle.loads(self._meta)` (style.py:475).
  result = initTable[string, JsonNode]()
  if b.len == 0: return
  let s = cast[string](b)
  let node = parseJson(s)
  if node.kind == JObject:
    for k, v in node.pairs: result[k] = v

proc mergeMeta(m: var Table[string, JsonNode],
               meta: Option[Table[string, JsonNode]]) =
  ## Merge an optional meta table into `m` (for `Style.on` positional meta).
  if meta.isSome:
    for k, v in meta.get.pairs: m[k] = v

proc mergeMeta(m: var Table[string, JsonNode], meta: Table[string, JsonNode]) =
  ## Merge a meta table into `m` (for `Style.on` positional meta).
  for k, v in meta.pairs: m[k] = v

proc setMetaKey(m: var Table[string, JsonNode], key: string, val: JsonNode) =
  ## Insert a meta key/value into `m`. Bound by `styleOnMacro` (via `bindSym`)
  ## so the generated code is self-contained at the expansion site (the caller
  ## need not import `std/tables` for the `[]=` operator).
  m[key] = val

proc hashColor(c: Color): Hash =
  ## Hash a `Color` (no system `hash`; combine its fields).
  var h: Hash = 0
  h = h !& hash(c.name)
  h = h !& hash(c.`type`.ord)
  if c.number.isSome: h = h !& c.number.get else: h = h !& 0
  if c.triplet.isSome:
    let t = c.triplet.get
    h = h !& t.red
    h = h !& t.green
    h = h !& t.blue
  else:
    h = h !& 0
  result = !$h

proc hashOptColor(o: Option[Color]): Hash =
  if o.isSome: result = hashColor(o.get) else: result = 0.Hash

proc hashOptString(o: Option[string]): Hash =
  if o.isSome: result = hash(o.get) else: result = 0.Hash

proc hashOptBytes(o: Option[seq[byte]]): Hash =
  if o.isSome: result = hash(o.get) else: result = 0.Hash

proc getBitValue(self: Style, bit: int): Option[bool] =
  ## rich style.py:33 — `_Bit.__get__`: the descriptor read shared by the 13
  ## attribute getters (below).
  if (self.setAttributes and bit) != 0:
    result = some((self.attributes and bit) != 0)
  else:
    result = none(bool)

proc attrCanonical(word: string): Option[string] =
  ## rich style.py:106 — `STYLE_ATTRIBUTES.get(word)`: map an attribute
  ## alias to its canonical name (or `None`).
  case word:
  of "dim", "d": result = some("dim")
  of "bold", "b": result = some("bold")
  of "italic", "i": result = some("italic")
  of "underline", "u": result = some("underline")
  of "blink": result = some("blink")
  of "blink2": result = some("blink2")
  of "reverse", "r": result = some("reverse")
  of "conceal", "c": result = some("conceal")
  of "strike", "s": result = some("strike")
  of "underline2", "uu": result = some("underline2")
  of "frame": result = some("frame")
  of "encircle": result = some("encircle")
  of "overline", "o": result = some("overline")
  else: result = none(string)

converter toStyleOpt*(x: string): StyleOpt =
  ## Accept a `str` style definition as an `Optional[StyleType]` value
  ## (style.py:19, 405) — the `str` arm. Lets `pickFirst(Style, "red", ...)`
  ## compile. (`discard` ⇒ `default(StyleOpt)` = `sokNone`);
  ## body wraps as `StyleOpt(kind: sokStr, strv: x)`.
  result = StyleOpt(kind: sokStr, strv: x)

converter toStyleOpt*(x: Style): StyleOpt =
  ## Accept a `Style` as an `Optional[StyleType]` value (style.py:19, 405) —
  ## the `Style` arm. Lets `pickFirst(Style, aStyle, ...)` compile. port
  ## stub.
  result = StyleOpt(kind: sokStyle, stv: x)

converter toStyleOpt*(x: Option[string]): StyleOpt =
  ## Accept an `Optional[str]` (a `None`/`str` position in `pick_first`,
  ## style.py:405). Lets `pickFirst(Style, none(string), ...)` and
  ## `pickFirst(Style, some("red"), ...)` compile.
  if x.isSome: result = StyleOpt(kind: sokStr, strv: x.get)
  else: result = StyleOpt(kind: sokNone)

converter toStyleOpt*(x: Option[Style]): StyleOpt =
  ## Accept an `Optional[Style]` (a `None`/`Style` position in `pick_first`,
  ## style.py:405). Lets `pickFirst(Style, none(Style), ...)` and
  ## `pickFirst(Style, some(aStyle), ...)` compile.
  if x.isSome: result = StyleOpt(kind: sokStyle, stv: x.get)
  else: result = StyleOpt(kind: sokNone)

converter toStyleValue*(x: string): StyleValue =
  ## Accept a `str` style definition as a `Union[str, Style]` value (text.py:54)
  ## — the `str` arm. Lets `Span(style: "bold")` / `initEmoji(style = "bold")`
  ## compile. (`discard` ⇒ `default(StyleValue)` = `svkStr` arm).
  result = StyleValue(kind: svkStr, strv: x)

converter toStyleValue*(x: Style): StyleValue =
  ## Accept a `Style` as a `Union[str, Style]` value (text.py:54) — the `Style`
  ## arm. Lets `Span(style: aStyle)` / `initEmoji(style: aStyle)` compile.
  result = StyleValue(kind: svkStyle, stv: x)

proc initBit*(bitNo: int): Bit =
  ## rich style.py:30 — `_Bit.__init__(self, bit_no: int)`: `self.bit = 1 << bit_no`.
  result.bit = 1 shl bitNo

proc getBit*(b: Bit, obj: Style, objType: typedesc[Style]): Option[bool] =
  ## rich style.py:33 — `_Bit.__get__(self, obj, objtype) -> Optional[bool]`:
  ## the descriptor read returning the attribute state (`None` if unset).
  if (obj.setAttributes and b.bit) != 0:
    result = some((obj.attributes and b.bit) != 0)
  else:
    result = none(bool)

proc initStyle*(
    color: Option[Color] or Color or string = none(Color),
    bgcolor: Option[Color] or Color or string = none(Color),
    bold: Option[bool] = none(bool),
    dim: Option[bool] = none(bool),
    italic: Option[bool] = none(bool),
    underline: Option[bool] = none(bool),
    blink: Option[bool] = none(bool),
    blink2: Option[bool] = none(bool),
    reverse: Option[bool] = none(bool),
    conceal: Option[bool] = none(bool),
    strike: Option[bool] = none(bool),
    underline2: Option[bool] = none(bool),
    frame: Option[bool] = none(bool),
    encircle: Option[bool] = none(bool),
    overline: Option[bool] = none(bool),
    link: Option[string] = none(string),
    meta: Option[Table[string, JsonNode]] = none(Table[string, JsonNode])
): Style =
  ## rich style.py:131 — `Style.__init__(self, *, color=None, bgcolor=None,
  ## bold=..., dim=..., italic=..., underline=..., blink=..., blink2=...,
  ## reverse=..., conceal=..., strike=..., underline2=..., frame=...,
  ## encircle=..., overline=..., link=None, meta=None)`. Keyword-only (Python
  ## `*`). `color`/`bgcolor` are `Optional[Union[Color, str]]` in Python
  ## (style.py:132-133); a `str` is converted via `Color.parse` in the body
  ## (style.py:155-156). Modelled as a Nim typeclass param `Option[Color] or
  ## Color or string` so every legal Python variant compiles in a single
  ## signature — `initStyle()`, `initStyle(color = "red")` (str),
  ## `initStyle(color = aColor)` (Color), `initStyle(color = some(aColor))`
  ## (Option[Color]), `initStyle(color = none(Color))` — while illegal
  ## `initStyle(color = 5)` (int, not `Union[Color, str]`) is rejected.
  ## `meta: Optional[Dict[str, Any]]` modelled as `Option[Table[string,
  ## JsonNode]]` (rich meta is JSON metadata; `JsonNode` is the non-narrowing
  ## handle for `Any`, covering str/int/float/bool/None/seq/dict — every rich
  ## meta value type).
  result = Style()
  result.ansi = none(string)
  result.styleDefinition = none(string)
  let colorOpt = toColorOpt(color)
  let bgcolorOpt = toColorOpt(bgcolor)
  var setAttrs = 0
  if bold.isSome: setAttrs = setAttrs or 1
  if dim.isSome: setAttrs = setAttrs or 2
  if italic.isSome: setAttrs = setAttrs or 4
  if underline.isSome: setAttrs = setAttrs or 8
  if blink.isSome: setAttrs = setAttrs or 16
  if blink2.isSome: setAttrs = setAttrs or 32
  if reverse.isSome: setAttrs = setAttrs or 64
  if conceal.isSome: setAttrs = setAttrs or 128
  if strike.isSome: setAttrs = setAttrs or 256
  if underline2.isSome: setAttrs = setAttrs or 512
  if frame.isSome: setAttrs = setAttrs or 1024
  if encircle.isSome: setAttrs = setAttrs or 2048
  if overline.isSome: setAttrs = setAttrs or 4096
  result.setAttributes = setAttrs
  var attrs = 0
  if setAttrs != 0:
    if bold.isSome and bold.get: attrs = attrs or 1
    if dim.isSome and dim.get: attrs = attrs or 2
    if italic.isSome and italic.get: attrs = attrs or 4
    if underline.isSome and underline.get: attrs = attrs or 8
    if blink.isSome and blink.get: attrs = attrs or 16
    if blink2.isSome and blink2.get: attrs = attrs or 32
    if reverse.isSome and reverse.get: attrs = attrs or 64
    if conceal.isSome and conceal.get: attrs = attrs or 128
    if strike.isSome and strike.get: attrs = attrs or 256
    if underline2.isSome and underline2.get: attrs = attrs or 512
    if frame.isSome and frame.get: attrs = attrs or 1024
    if encircle.isSome and encircle.get: attrs = attrs or 2048
    if overline.isSome and overline.get: attrs = attrs or 4096
  result.attributes = attrs
  result.color = colorOpt
  result.bgcolor = bgcolorOpt
  result.link = link
  let linkNonEmpty = link.isSome and link.get.len > 0
  let metaNonEmpty = meta.isSome and meta.get.len > 0
  if meta.isSome:
    result.metaBytes = some(metaToBytes(meta.get))
  else:
    result.metaBytes = none(seq[byte])
  if linkNonEmpty or metaNonEmpty:
    result.linkId = $nextId()
  else:
    result.linkId = ""
  result.hashValue = none(int)
  result.isNull = not (setAttrs != 0 or colorOpt.isSome or bgcolorOpt.isSome or
                       linkNonEmpty or metaNonEmpty)

let
  nullStyle* = Style(isNull: true)
    ## rich style.py:762 — `NULL_STYLE = Style()`: the null style. port
    ## constructs the faithful default (`_null=True`, all colors/attributes
    ## unset); the performant `Style.null()` classmethod returns this singleton.

proc null*(T: typedesc[Style]): Style =
  ## rich style.py:208 — `Style.null(cls) -> Style` (`@classmethod`
  ## style.py:207): a 'null' style, equivalent to `Style()` but more
  ## performant (returns `NULL_STYLE`, style.py:210).
  result = nullStyle

proc fromColor*(T: typedesc[Style], color: Option[Color] = none(Color),
                bgcolor: Option[Color] = none(Color)): Style =
  ## rich style.py:213 — `Style.from_color(cls, color=None, bgcolor=None) ->
  ## Style` (`@classmethod` style.py:212): a new style with colors and no
  ## attributes.
  result = Style()
  result.ansi = none(string)
  result.styleDefinition = none(string)
  result.color = color
  result.bgcolor = bgcolor
  result.setAttributes = 0
  result.attributes = 0
  result.link = none(string)
  result.linkId = ""
  result.metaBytes = none(seq[byte])
  result.isNull = not (color.isSome or bgcolor.isSome)
  result.hashValue = none(int)

proc fromMeta*(T: typedesc[Style], meta: Option[Table[string, JsonNode]]): Style =
  ## rich style.py:237 — `Style.from_meta(cls, meta: Optional[Dict[str, Any]])
  ## -> Style` (`@classmethod` style.py:236): a new style with meta data.
  result = Style()
  result.ansi = none(string)
  result.styleDefinition = none(string)
  result.color = none(Color)
  result.bgcolor = none(Color)
  result.setAttributes = 0
  result.attributes = 0
  result.link = none(string)
  if meta.isSome:
    result.metaBytes = some(metaToBytes(meta.get))
  else:
    result.metaBytes = none(seq[byte])
  let metaNonEmpty = meta.isSome and meta.get.len > 0
  result.linkId = if metaNonEmpty: $nextId() else: ""
  result.isNull = not metaNonEmpty
  result.hashValue = none(int)

proc newStyleFromMeta(meta: Option[Table[string, JsonNode]]): Style =
  ## Private wrapper so `styleOnMacro` can build a `Style.from_meta` without
  ## passing the `typedesc[Style]` (a `bindSym` of a type used as a call arg
  ## is read as a value, not a typedesc).
  result = Style.fromMeta(meta)

macro styleOnMacro(handlers: varargs[untyped]): Style =
  ## rich style.py:258 — `Style.on` body: build a meta table from `key =
  ## value` handlers (and an optional leading positional meta) and delegate
  ## to `Style.from_meta`. Each `name = value` is captured as
  ## `nnkExprEqExpr` by the `on` template's `varargs[untyped]` and forwarded
  ## here; `bindSym` binds the helper symbols at this module so the expansion
  ## resolves regardless of the caller's imports. `genSym` gives the local
  ## table a fresh name per expansion.
  result = newNimNode(nnkStmtListExpr)
  let mSym = genSym(nskVar, "m")
  let initTableCall = newCall(newNimNode(nnkBracketExpr).add(
    bindSym("initTable"), bindSym("string"), bindSym("JsonNode")))
  result.add(newVarStmt(mSym, initTableCall))
  let h = handlers
  for i in 0 ..< h.len:
    let node = h[i]
    if node.kind == nnkExprEqExpr:
      let keyStr = newStrLitNode("@" & $node[0])
      result.add(newCall(bindSym("setMetaKey"), mSym, keyStr,
                         newCall(bindSym("toJsonNode"), node[1])))
    elif i == 0:
      result.add(newCall(bindSym("mergeMeta", brForceOpen), mSym, node))
  result.add(newCall(bindSym("newStyleFromMeta"),
                     newCall(bindSym("some"), mSym)))

template on*(T: typedesc[Style], handlers: varargs[untyped]): Style =
  ## rich style.py:258 — `Style.on(cls, meta=None, **handlers: Any) -> Style`
  ## (`@classmethod` style.py:257): a blank style with meta information.
  ## Python's `**handlers: Any` (style.py:258) accepts arbitrary keyword
  ## arguments, translated to meta keys `f"@{key}"` (style.py:271). Nim has no
  ## `**kwargs`, so this is modelled as a `template` taking `varargs[untyped]`:
  ## each `name = value` argument is captured as an `nnkExprColonExpr` AST
  ## node, so the full legal surface compiles — `on(Style, click = 1)`,
  ## `on(Style, click = "CLICK")`, `on(Style, click = 1, hover = 2)`. The
  ## positional `meta` first parameter (`on(Style, metaTable, click = 1)`,
  ## where `metaTable` is an `Option[Table[string, JsonNode]]` / dict) is
  ## captured positionally among the same varargs and distinguished from the
  ## `key = value` handlers in the Body. This is the non-narrowing
  ## representation of `**handlers: Any` (every keyword handler compiles; there
  ## is no compile-time-illegal variant, matching Python's dynamic `Any`).
  ## body: `default(Style)`.
  bind styleOnMacro
  styleOnMacro(handlers)

proc bold*(self: Style): Option[bool] =
  ## rich style.py:275 — `Style.bold` (`_Bit(0)` descriptor, `__get__`
  ## style.py:33): bold attribute state (`None` if unset).
  result = getBitValue(self, 1)

proc dim*(self: Style): Option[bool] =
  ## rich style.py:276 — `Style.dim` (`_Bit(1)`, `__get__` style.py:33).
  result = getBitValue(self, 2)

proc italic*(self: Style): Option[bool] =
  ## rich style.py:277 — `Style.italic` (`_Bit(2)`, `__get__` style.py:33).
  result = getBitValue(self, 4)

proc underline*(self: Style): Option[bool] =
  ## rich style.py:278 — `Style.underline` (`_Bit(3)`, `__get__` style.py:33).
  result = getBitValue(self, 8)

proc blink*(self: Style): Option[bool] =
  ## rich style.py:279 — `Style.blink` (`_Bit(4)`, `__get__` style.py:33).
  result = getBitValue(self, 16)

proc blink2*(self: Style): Option[bool] =
  ## rich style.py:280 — `Style.blink2` (`_Bit(5)`, `__get__` style.py:33).
  result = getBitValue(self, 32)

proc reverse*(self: Style): Option[bool] =
  ## rich style.py:281 — `Style.reverse` (`_Bit(6)`, `__get__` style.py:33).
  result = getBitValue(self, 64)

proc conceal*(self: Style): Option[bool] =
  ## rich style.py:282 — `Style.conceal` (`_Bit(7)`, `__get__` style.py:33).
  result = getBitValue(self, 128)

proc strike*(self: Style): Option[bool] =
  ## rich style.py:283 — `Style.strike` (`_Bit(8)`, `__get__` style.py:33).
  result = getBitValue(self, 256)

proc underline2*(self: Style): Option[bool] =
  ## rich style.py:284 — `Style.underline2` (`_Bit(9)`, `__get__` style.py:33).
  result = getBitValue(self, 512)

proc frame*(self: Style): Option[bool] =
  ## rich style.py:285 — `Style.frame` (`_Bit(10)`, `__get__` style.py:33).
  result = getBitValue(self, 1024)

proc encircle*(self: Style): Option[bool] =
  ## rich style.py:286 — `Style.encircle` (`_Bit(11)`, `__get__` style.py:33).
  result = getBitValue(self, 2048)

proc overline*(self: Style): Option[bool] =
  ## rich style.py:287 — `Style.overline` (`_Bit(12)`, `__get__` style.py:33).
  result = getBitValue(self, 4096)

proc `$`*(self: Style): string =
  ## rich style.py:294 — `Style.__str__(self) -> str`: re-generate the style
  ## definition from attributes.
  if self.styleDefinition.isNone:
    var attrs: seq[string] = @[]
    let bits = self.setAttributes
    if (bits and 0b0000000001111) != 0:
      if (bits and 1) != 0:
        attrs.add(if self.bold.get: "bold" else: "not bold")
      if (bits and 2) != 0:
        attrs.add(if self.dim.get: "dim" else: "not dim")
      if (bits and 4) != 0:
        attrs.add(if self.italic.get: "italic" else: "not italic")
      if (bits and 8) != 0:
        attrs.add(if self.underline.get: "underline" else: "not underline")
    if (bits and 0b0000111110000) != 0:
      if (bits and 16) != 0:
        attrs.add(if self.blink.get: "blink" else: "not blink")
      if (bits and 32) != 0:
        attrs.add(if self.blink2.get: "blink2" else: "not blink2")
      if (bits and 64) != 0:
        attrs.add(if self.reverse.get: "reverse" else: "not reverse")
      if (bits and 128) != 0:
        attrs.add(if self.conceal.get: "conceal" else: "not conceal")
      if (bits and 256) != 0:
        attrs.add(if self.strike.get: "strike" else: "not strike")
    if (bits and 0b1111000000000) != 0:
      if (bits and 512) != 0:
        attrs.add(if self.underline2.get: "underline2" else: "not underline2")
      if (bits and 1024) != 0:
        attrs.add(if self.frame.get: "frame" else: "not frame")
      if (bits and 2048) != 0:
        attrs.add(if self.encircle.get: "encircle" else: "not encircle")
      if (bits and 4096) != 0:
        attrs.add(if self.overline.get: "overline" else: "not overline")
    if self.color.isSome: attrs.add(self.color.get.name)
    if self.bgcolor.isSome:
      attrs.add("on")
      attrs.add(self.bgcolor.get.name)
    if self.link.isSome and self.link.get.len > 0:
      attrs.add("link")
      attrs.add(self.link.get)
    let def = if attrs.len > 0: attrs.join(" ") else: "none"
    self.styleDefinition = some(def)
  result = self.styleDefinition.get

proc bool*(self: Style): bool =
  ## rich style.py:340 — `Style.__bool__(self) -> bool`: a Style is false if it
  ## has no attributes, colors, or links. Mirrored as a proc named `bool`
  ## (`bool(style)`); Nim has no custom truthiness coercion.
  result = not self.isNull

proc makeAnsiCodes*(self: Style, colorSystem: ColorSystem): string =
  ## rich style.py:344 — `Style._make_ansi_codes(self, color_system: ColorSystem)
  ## -> str`: generate ANSI codes for this style.
  if self.ansi.isNone:
    var sgr: seq[string] = @[]
    let attributes = self.attributes and self.setAttributes
    if attributes != 0:
      if (attributes and 1) != 0: sgr.add(styleMapArr[0])
      if (attributes and 2) != 0: sgr.add(styleMapArr[1])
      if (attributes and 4) != 0: sgr.add(styleMapArr[2])
      if (attributes and 8) != 0: sgr.add(styleMapArr[3])
      if (attributes and 0b0000111110000) != 0:
        for bit in 4 .. 8:
          if (attributes and (1 shl bit)) != 0: sgr.add(styleMapArr[bit])
      if (attributes and 0b1111000000000) != 0:
        for bit in 9 .. 12:
          if (attributes and (1 shl bit)) != 0: sgr.add(styleMapArr[bit])
    if self.color.isSome:
      for c in self.color.get.downgrade(colorSystem).getAnsiCodes():
        sgr.add(c)
    if self.bgcolor.isSome:
      for c in self.bgcolor.get.downgrade(colorSystem).getAnsiCodes(foreground = false):
        sgr.add(c)
    self.ansi = some(sgr.join(";"))
  result = self.ansi.get

proc parse*(T: typedesc[Style], styleDefinition: string): Style =
  ## rich style.py:498 — `Style.parse(cls, style_definition: str) -> Style`
  ## (`@classmethod` style.py:496, `@lru_cache(maxsize=4096)` style.py:497):
  ## parse a style definition. Raises `errors.StyleSyntaxError`
  ## (style.py:525,529,538,546,556); catches `ColorParseError` (style.py:528,555).
  if styleDefinition.strip() == "none" or styleDefinition.len == 0:
    return Style.null()
  var
    colorStr: Option[string] = none(string)
    bgcolorStr: Option[string] = none(string)
    linkStr: Option[string] = none(string)
    # `system.bool` (not `bool`): the `proc bool*(Style): bool` mirror of
    # `__bool__` (defined above) shadows the bare `bool` type here, so qualify
    # the type explicitly (the `initStyle` defaults resolve `bool` to the type
    # because `initStyle` precedes the `bool` proc).
    boldP, dimP, italicP, underlineP, blinkP, blink2P, reverseP, concealP,
      strikeP, underline2P, frameP, encircleP, overlineP: Option[system.bool] =
        none(system.bool)
  # Python `str.split()` (no arg) drops empty fields; Nim `split()` does not,
  # so filter (rich style.py:516 `words = iter(style_definition.split())`).
  var words: seq[string] = @[]
  for w in styleDefinition.split():
    if w.len > 0: words.add(w)
  var i = 0
  while i < words.len:
    let originalWord = words[i]; inc i
    let word = originalWord.toLowerAscii
    if word == "on":
      let nextWord = if i < words.len: words[i] else: ""
      if nextWord.len == 0:
        raise newException(StyleSyntaxError, "color expected after 'on'")
      inc i
      try: discard Color.parse(nextWord)
      except ColorParseError as e:
        raise newException(StyleSyntaxError,
          "unable to parse " & pyReprStr(nextWord) &
          " as background color; " & e.msg)
      bgcolorStr = some(nextWord)
    elif word == "not":
      let nextWord = if i < words.len: words[i] else: ""
      inc i
      # Python style.py:535 uses the RAW (case-sensitive) next word here —
      # `STYLE_ATTRIBUTES.get(word)` where `word = next(words, "")` is NOT
      # lowered — unlike the positive branch (`word in STYLE_ATTRIBUTES`,
      # style.py:536, where `word = original_word.lower()`). So `not BOLD`
      # raises (not found), but `BOLD` (positive) succeeds.
      let attr = attrCanonical(nextWord)
      if attr.isNone:
        raise newException(StyleSyntaxError,
          "expected style attribute after 'not', found " & pyReprStr(nextWord))
      case attr.get
      of "bold": boldP = some(false)
      of "dim": dimP = some(false)
      of "italic": italicP = some(false)
      of "underline": underlineP = some(false)
      of "blink": blinkP = some(false)
      of "blink2": blink2P = some(false)
      of "reverse": reverseP = some(false)
      of "conceal": concealP = some(false)
      of "strike": strikeP = some(false)
      of "underline2": underline2P = some(false)
      of "frame": frameP = some(false)
      of "encircle": encircleP = some(false)
      of "overline": overlineP = some(false)
      else: discard
    elif word == "link":
      let nextWord = if i < words.len: words[i] else: ""
      if nextWord.len == 0:
        raise newException(StyleSyntaxError, "URL expected after 'link'")
      inc i
      linkStr = some(nextWord)
    else:
      let attr = attrCanonical(word)
      if attr.isSome:
        case attr.get
        of "bold": boldP = some(true)
        of "dim": dimP = some(true)
        of "italic": italicP = some(true)
        of "underline": underlineP = some(true)
        of "blink": blinkP = some(true)
        of "blink2": blink2P = some(true)
        of "reverse": reverseP = some(true)
        of "conceal": concealP = some(true)
        of "strike": strikeP = some(true)
        of "underline2": underline2P = some(true)
        of "frame": frameP = some(true)
        of "encircle": encircleP = some(true)
        of "overline": overlineP = some(true)
        else: discard
      else:
        try: discard Color.parse(word)
        except ColorParseError as e:
          raise newException(StyleSyntaxError,
            "unable to parse " & pyReprStr(word) & " as color; " & e.msg)
        colorStr = some(word)
  result = initStyle(
    color = if colorStr.isSome: some(Color.parse(colorStr.get)) else: none(Color),
    bgcolor = if bgcolorStr.isSome: some(Color.parse(bgcolorStr.get)) else: none(Color),
    bold = boldP, dim = dimP, italic = italicP, underline = underlineP,
    blink = blinkP, blink2 = blink2P, reverse = reverseP, conceal = concealP,
    strike = strikeP, underline2 = underline2P, frame = frameP,
    encircle = encircleP, overline = overlineP,
    link = linkStr,
    meta = none(Table[string, JsonNode]))

proc normalize*(T: typedesc[Style], style: string): string =
  ## rich style.py:389 — `Style.normalize(cls, style: str) -> str`
  ## (`@classmethod` style.py:387, `@lru_cache(maxsize=1024)` style.py:388):
  ## normalize a style definition so equivalent styles share a string form.
  try:
    result = $Style.parse(style)
  except StyleSyntaxError:
    result = style.strip().toLowerAscii

proc pickFirst*(T: typedesc[Style], values: varargs[StyleOpt]): StyleOpt =
  ## rich style.py:405 — `Style.pick_first(cls, *values: Optional[StyleType])
  ## -> StyleType` (`@classmethod` style.py:404): pick first non-None style.
  ## Python's `*values: Optional[StyleType]` (style.py:405) is a heterogeneous
  ## tuple whose elements are each `None`, a `str`, or a `Style`; Nim `varargs`
  ## requires a uniform element type, so the element is the `StyleOpt` union
  ## handle (above) and the four `toStyleOpt*` converters accept every legal
  ## Python variant per slot. Thus `pickFirst(Style, none(string), "red")`,
  ## `pickFirst(Style, aStyle, "table.title")`, `pickFirst(Style,
  ## some("red"), none(Style))` and `pickFirst(Style)` all compile, while
  ## `pickFirst(Style, 5)` (an `int`, not `Optional[StyleType]`) is rejected.
  ## Returns `StyleOpt` (the `StyleType = Union[str, Style]` union; `sokNone`
  ## is unreachable for a successful pick — `pick_first` raises `ValueError`
  ## if all values are `None`, style.py:408-409).
  for v in values:
    if v.kind != sokNone:
      return v
  raise newException(ValueError, "expected at least one non-None style")

proc optBoolToJson(o: Option[system.bool]): JsonNode =
  ## Encode an `Option[bool]` (a `__rich_repr__` value, e.g. `bold`/`dim`) as a
  ## `JsonNode` — the Nim `Any` handle (see `repr.ReprArg.tripleValue`). `None`
  ## → `null` (matches the triple's `default=None`, so `auto_repr` skips unset
  ## attributes, repr.py:63-64); `Some(b)` → `bool` (rendered, repr.py:66).
  ## NOTE: param is `Option[system.bool]` (not `Option[bool]`) to disambiguate
  ## the `bool` symbol: the exported `proc bool*(self: Style): bool` (the
  ## `__bool__` mirror, line 620) shadows `system.bool` for any proc defined
  ## AFTER it. The public attribute getters (`bold`/`dim`/..., lines 521-570)
  ## are declared BEFORE `proc bool*`, so their `Option[bool]` return types
  ## resolve to `Option[system.bool]`; this private helper is declared AFTER,
  ## so it must qualify. `system.bool` is identical to `bool`; this changes no
  ## frozen public signature (the helper is private/non-exported).
  result = if o.isNone: newJNull() else: newJBool(o.get)

proc optColorToJson(o: Option[Color]): JsonNode =
  ## Encode an `Option[Color]` (the `color`/`bgcolor` repr values) as a
  ## `JsonNode`. `None` → `null` (skip, repr.py:63-64); `Some(c)` → the color's
  ## `name` string — the canonical identity rich `Color.__rich_repr__` yields
  ## first (color.py:327 `yield self.name`).
  result = if o.isNone: newJNull() else: newJString(o.get.name)

proc optStrToJson(o: Option[string]): JsonNode =
  ## Encode an `Option[string]` (the `link` repr value) as a `JsonNode`.
  ## `None` → `null` (skip); `Some(s)` → the string.
  result = if o.isNone: newJNull() else: newJString(o.get)

proc metaTableToJson(t: Table[string, JsonNode]): JsonNode =
  ## Encode the `meta` `Table[string, JsonNode]` (Python `Dict[str, Any]`,
  ## deserialised by `Style.meta`, style.py:475) as a `JsonNode` object — the
  ## pair value of `("meta", self.meta)` (repr.py:66 always renders pairs).
  result = newJObject()
  for k, v in t.pairs:
    result[k] = v

proc richRepr*(self: Style): Result =
  ## rich style.py:412 — `Style.__rich_repr__(self) -> Result`: yield the
  ## style's color/bgcolor/attributes/link/meta for repr (style.py:414-428).
  ## Decorated `@rich_repr` (style.py:39). Mirrored as a Nim closure iterator
  ## over `repr.ReprArg` (the `Result` form, repr.py:18): 15 `(key, value,
  ## None)` triples (skipped by `auto_repr` when the value is `None`,
  ## repr.py:63-64) then, when meta is set, a `("meta", self.meta)` pair
  ## (always rendered). `Option[bool]`/`Option[Color]`/`Option[string]`
  ## values are encoded as `JsonNode` by the `opt*ToJson` helpers (`None`→
  ## `null`, matching the triple default so `auto_repr` skips unset attrs).
  iterator gen(): ReprArg {.closure.} =
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "color",
                  tripleValue: optColorToJson(self.color), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "bgcolor",
                  tripleValue: optColorToJson(self.bgcolor), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "bold",
                  tripleValue: optBoolToJson(self.bold), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "dim",
                  tripleValue: optBoolToJson(self.dim), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "italic",
                  tripleValue: optBoolToJson(self.italic), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "underline",
                  tripleValue: optBoolToJson(self.underline), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "blink",
                  tripleValue: optBoolToJson(self.blink), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "blink2",
                  tripleValue: optBoolToJson(self.blink2), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "reverse",
                  tripleValue: optBoolToJson(self.reverse), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "conceal",
                  tripleValue: optBoolToJson(self.conceal), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "strike",
                  tripleValue: optBoolToJson(self.strike), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "underline2",
                  tripleValue: optBoolToJson(self.underline2), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "frame",
                  tripleValue: optBoolToJson(self.frame), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "encircle",
                  tripleValue: optBoolToJson(self.encircle), tripleDefault: newJNull())
    yield ReprArg(kind: ReprArgKind.rakTriple, tripleKey: "link",
                  tripleValue: optStrToJson(self.link), tripleDefault: newJNull())
    if self.metaBytes.isSome and self.metaBytes.get.len > 0:
      # Inlined `meta(self)` body (the `isSome` branch) rather than calling
      # `meta(self)`: the `meta` getter proc is defined further down (line ~924)
      # and is not hoisted into this `closure` iterator's scope, so neither
      # `self.meta` (method-call) nor `meta(self)` (direct call) resolves here.
      # `bytesToMeta` (line 205) is visible, and inside this `isSome` guard
      # `meta(self)` is exactly `bytesToMeta(self.metaBytes.get)` (the `else`
      # arm of `meta`), so this is semantically identical to Python's
      # `("meta", self.meta)` pair (repr.py:66).
      yield ReprArg(kind: ReprArgKind.rakPair, key: "meta",
                    pairValue: metaTableToJson(bytesToMeta(self.metaBytes.get)))
  result = gen

proc hash*(self: Style): Hash =
  ## rich style.py:441 — `Style.__hash__(self) -> int`: `hash(_hash_getter(self))`
  ## (style.py:444). Mirrored as a `hash` overload (returning `Hash` from
  ## `std/hashes`).
  if self.hashValue.isSome:
    return self.hashValue.get.Hash
  var h: Hash = 0
  h = h !& hashOptColor(self.color)
  h = h !& hashOptColor(self.bgcolor)
  h = h !& self.attributes
  h = h !& self.setAttributes
  h = h !& hashOptString(self.link)
  h = h !& hashOptBytes(self.metaBytes)
  result = !$h
  self.hashValue = some(result.int)

proc `==`*[T](a: Style, b: T): bool =
  ## rich style.py:431 — `Style.__eq__(self, other: Any) -> bool`: a `Style`
  ## operand compares by hash (`hash(self) == hash(other)`, style.py:434); a
  ## non-`Style` operand returns `NotImplemented` (style.py:432-433), which
  ## Python resolves to identity (`self is other`) — `False` for a real
  ## `Style` vs `None`/`str`/`int`, `True` for `None == None`. Modelled as a
  ## generic `proc` `[T](a: Style, b: T)` so a comparison with any right
  ## operand compiles (`style == otherStyle`, `style == "foo"`, `style == 42`,
  ## `style == nil`) — faithful to `other: Any`. The `when` branches mirror the
  ## Python outcomes: a genuine `Style` operand (NOT the `nil` literal —
  ## `typeof(nil) is Style` is `true` in Nim since `nil` is a valid ref value,
  ## so it is excluded explicitly) compares by hash; a `nil` operand (Python
  ## `None`) yields the identity result `a.isNil` (`None == None` ⇒ `True`, a
  ## real `Style` ⇒ `False`); any other operand yields `False` (the
  ## `NotImplemented`→identity outcome for a non-`Style`). Python's `self` is
  ## always a real `Style` (a `None` left operand uses `NoneType.__eq__`, not
  ## `Style.__eq__`), so the hash branch assumes `a` is non-`nil` (a `nil` `a`
  ## in a `Style`-vs-`Style` compare would raise, mirroring Python's
  ## `_hash_getter(None)` crash). The explicit `nil` exclusion is required:
  ## without it `hash(b)` for `b == nil` is ambiguous between this `hash(Style)`
  ## and any other module's `hash(<ref>)` (e.g. `json.hash(JsonNode)`) once the
  ## umbrella imports that module.
  when typeof(b) is Style and typeof(b) isnot typeof(nil):
    result = hash(a) == hash(b)
  elif typeof(b) is typeof(nil):
    result = a.isNil
  else:
    result = false

proc `!=`*[T](a: Style, b: T): bool =
  ## rich style.py:436 — `Style.__ne__(self, other: Any) -> bool`: a `Style`
  ## operand compares by hash (`hash(self) != hash(other)`, style.py:439); a
  ## non-`Style` operand returns `NotImplemented` (style.py:437-438), which
  ## Python resolves to identity (`self is not other`) — `True` for a real
  ## `Style` vs `None`/`str`/`int`, `False` for `None != None`. Generic `[T]`
  ## mirrors `other: Any` (see `==`); the `when` branches mirror the Python
  ## outcomes: a genuine `Style` operand (NOT the `nil` literal) compares by
  ## hash; a `nil` operand yields `not a.isNil` (the identity result, used as a
  ## nil-guard in `ansi.nim`/`jupyter.nim`: `style != nil` ⇒ `True` iff the ref
  ## is non-`nil`); any other operand yields `True` (the `NotImplemented`→
  ## identity outcome for a non-`Style`). See `==` for why the `nil` literal is
  ## excluded from the hash branch (ambiguity with foreign `hash(<ref>)`).
  when typeof(b) is Style and typeof(b) isnot typeof(nil):
    result = hash(a) != hash(b)
  elif typeof(b) is typeof(nil):
    result = not a.isNil
  else:
    result = true

proc transparentBackground*(self: Style): bool =
  ## rich style.py:463 — `Style.transparent_background` (`@property`
  ## style.py:462): `self.bgcolor is None or self.bgcolor.is_default`
  ## (style.py:465).
  result = self.bgcolor.isNone or
           (self.bgcolor.isSome and self.bgcolor.get.isDefault)

proc backgroundStyle*(self: Style): Style =
  ## rich style.py:468 — `Style.background_style` (`@property` style.py:467):
  ## `Style(bgcolor=self.bgcolor)` (style.py:470) — a Style with background only.
  result = initStyle(bgcolor = self.bgcolor)

proc meta*(self: Style): Table[string, JsonNode] =
  ## rich style.py:473 — `Style.meta` (`@property` style.py:472): get meta
  ## information (deserialised from `_meta` bytes, style.py:475). Python
  ## `Dict[str, Any]` modelled as `Table[string, JsonNode]`.
  if self.metaBytes.isNone:
    result = initTable[string, JsonNode]()
  else:
    result = bytesToMeta(self.metaBytes.get)

proc withoutColor*(self: Style): Style =
  ## rich style.py:478 — `Style.without_color` (`@property` style.py:477): a
  ## copy of the style with color removed (style.py:480-494).
  if self.isNull: return nullStyle
  result = Style()
  result.ansi = none(string)
  result.styleDefinition = none(string)
  result.color = none(Color)
  result.bgcolor = none(Color)
  result.attributes = self.attributes
  result.setAttributes = self.setAttributes
  result.link = self.link
  result.linkId = if self.link.isSome and self.link.get.len > 0: $nextId() else: ""
  result.isNull = false
  result.metaBytes = none(seq[byte])
  result.hashValue = none(int)

proc getHtmlStyle*(self: Style, theme: Option[TerminalTheme] = none(TerminalTheme)): string =
  ## rich style.py:564 — `Style.get_html_style(self, theme=None) -> str`
  ## (`@lru_cache(maxsize=1024)` style.py:563): a CSS style rule. `theme`
  ## defaults to `DEFAULT_TERMINAL_THEME` (style.py:566); uses `blend_rgb`
  ## (style.py:579). The `theme` type is not importable here (the
  ## `style ← palette ← terminal_theme` import cycle), so the passed `theme`
  ## is inert and `DEFAULT_TERMINAL_THEME`'s colours are inlined
  ## (`foreground=(0,0,0)`, `background=(255,255,255)`, terminal_theme.nim);
  ## `color.getTruecolor(theme)` omits the theme arg (color.nim's private
  ## `TerminalTheme` placeholder) — truecolour colours resolve exactly,
  ## named colours defer to `(0,0,0)` (color.nim).
  let defaultFg = (red: 0, green: 0, blue: 0)
  let defaultBg = (red: 255, green: 255, blue: 255)
  var css: seq[string] = @[]
  var color = self.color
  var bgcolor = self.bgcolor
  if self.reverse.isSome and self.reverse.get:
    swap(color, bgcolor)
  if self.dim.isSome and self.dim.get:
    let foregroundColor = if color.isNone: defaultFg else: color.get.getTruecolor()
    color = some(Color.fromTriplet(blendRgb(foregroundColor, defaultBg, 0.5)))
  if color.isSome:
    let themeColor = color.get.getTruecolor()
    css.add("color: " & themeColor.hex)
    css.add("text-decoration-color: " & themeColor.hex)
  if bgcolor.isSome:
    let themeColor = bgcolor.get.getTruecolor(foreground = false)
    css.add("background-color: " & themeColor.hex)
  if self.bold.isSome and self.bold.get:
    css.add("font-weight: bold")
  if self.italic.isSome and self.italic.get:
    css.add("font-style: italic")
  if self.underline.isSome and self.underline.get:
    css.add("text-decoration: underline")
  if self.strike.isSome and self.strike.get:
    css.add("text-decoration: line-through")
  if self.overline.isSome and self.overline.get:
    css.add("text-decoration: overline")
  result = css.join("; ")

proc copy*(self: Style): Style =
  ## rich style.py:626 — `Style.copy(self) -> Style`: get a copy of this style.
  if self.isNull: return nullStyle
  result = Style()
  result.ansi = self.ansi
  result.styleDefinition = self.styleDefinition
  result.color = self.color
  result.bgcolor = self.bgcolor
  result.attributes = self.attributes
  result.setAttributes = self.setAttributes
  result.link = self.link
  result.linkId = if self.link.isSome and self.link.get.len > 0: $nextId() else: ""
  result.hashValue = self.hashValue
  result.isNull = false
  result.metaBytes = self.metaBytes

proc clearMetaAndLinks*(self: Style): Style =
  ## rich style.py:649 — `Style.clear_meta_and_links(self) -> Style`
  ## (`@lru_cache(maxsize=128)` style.py:648): a copy with link and meta removed.
  if self.isNull: return nullStyle
  result = Style()
  result.ansi = self.ansi
  result.styleDefinition = self.styleDefinition
  result.color = self.color
  result.bgcolor = self.bgcolor
  result.attributes = self.attributes
  result.setAttributes = self.setAttributes
  result.link = none(string)
  result.linkId = ""
  result.hashValue = none(int)
  result.isNull = false
  result.metaBytes = none(seq[byte])

proc updateLink*(self: Style, link: Option[string] = none(string)): Style =
  ## rich style.py:671 — `Style.update_link(self, link=None) -> Style`: a copy
  ## with a different value for link.
  result = Style()
  result.ansi = self.ansi
  result.styleDefinition = self.styleDefinition
  result.color = self.color
  result.bgcolor = self.bgcolor
  result.attributes = self.attributes
  result.setAttributes = self.setAttributes
  result.link = link
  result.linkId = if link.isSome and link.get.len > 0: $nextId() else: ""
  result.hashValue = none(int)
  result.isNull = false
  result.metaBytes = self.metaBytes

proc addImpl*(self: Style, style: Option[Style]): Style =
  ## rich style.py:733 — `Style._add(self, style: Optional["Style"]) -> Style`
  ## (`@lru_cache(maxsize=1024)` style.py:732): the internal add used by
  ## `__add__` (the `Impl` suffix avoids clashing with `system.add`).
  if style.isNone or style.get.isNull:
    return self
  if self.isNull:
    return style.get
  let other = style.get
  result = Style()
  result.ansi = none(string)
  result.styleDefinition = none(string)
  result.color = if other.color.isSome: other.color else: self.color
  result.bgcolor = if other.bgcolor.isSome: other.bgcolor else: self.bgcolor
  result.attributes = (self.attributes and (not other.setAttributes)) or
                      (other.attributes and other.setAttributes)
  result.setAttributes = self.setAttributes or other.setAttributes
  result.link = if other.link.isSome and other.link.get.len > 0: other.link
                else: self.link
  result.linkId = if other.linkId.len > 0: other.linkId else: self.linkId
  result.isNull = other.isNull
  if self.metaBytes.isSome and other.metaBytes.isSome:
    var merged = bytesToMeta(self.metaBytes.get)
    let m2 = bytesToMeta(other.metaBytes.get)
    for k, v in m2.pairs: merged[k] = v
    result.metaBytes = some(metaToBytes(merged))
  else:
    result.metaBytes = if self.metaBytes.isSome: self.metaBytes
                       else: other.metaBytes
  result.hashValue = none(int)

proc `+`*(self: Style, style: Option[Style]): Style =
  ## rich style.py:757 — `Style.__add__(self, style: Optional["Style"]) -> Style`:
  ## combine two styles (delegates to `_add`, style.py:759). Mirrored as the
  ## `+` operator.
  let combined = self.addImpl(style)
  if combined.link.isSome and combined.link.get.len > 0:
    return combined.copy()
  return combined

proc combine*(T: typedesc[Style], styles: openArray[Style]): Style =
  ## rich style.py:601 — `Style.combine(cls, styles: Iterable["Style"]) -> Style`
  ## (`@classmethod` style.py:600): combine styles and get the result.
  ## `Iterable[Style]` modelled as `openArray[Style]`.
  if styles.len == 0:
    return Style()
  result = styles[0]
  for i in 1 ..< styles.len:
    result = result + some(styles[i])

proc chain*(T: typedesc[Style], styles: varargs[Style]): Style =
  ## rich style.py:614 — `Style.chain(cls, *styles: "Style") -> Style`
  ## (`@classmethod` style.py:613): combine styles from positional arguments.
  ## `*styles` modelled as `varargs[Style]`.
  if styles.len == 0:
    return Style()
  result = styles[0]
  for i in 1 ..< styles.len:
    result = result + some(styles[i])

proc render*(self: Style, text: string = "",
             colorSystem: Option[ColorSystem] = some(ColorSystem.truecolor),
             legacyWindows: bool = false): string =
  ## rich style.py:694 — `Style.render(self, text="", *, color_system=
  ## ColorSystem.TRUECOLOR, legacy_windows=False) -> str`: render the ANSI
  ## codes for the style. `color_system` defaults to `ColorSystem.TRUECOLOR`
  ## (style.py:698, not `None`).
  if text.len == 0 or colorSystem.isNone:
    return text
  let cs = colorSystem.get
  let attrs = if self.ansi.isSome and self.ansi.get.len > 0: self.ansi.get
              else: self.makeAnsiCodes(cs)
  var rendered = if attrs.len > 0: "\x1b[" & attrs & "m" & text & "\x1b[0m"
                 else: text
  if self.link.isSome and self.link.get.len > 0 and not legacyWindows:
    rendered = "\x1b]8;id=" & self.linkId & ";" & self.link.get & "\x1b\\" &
               rendered & "\x1b]8;;\x1b\\"
  result = rendered

proc test*(self: Style, text: Option[string] = none(string)) =
  ## rich style.py:720 — `Style.test(self, text=None) -> None`: write text with
  ## style directly to terminal (for testing). Returns `None` (void).
  let t = if text.isSome and text.get.len > 0: text.get else: $self
  stdout.write(self.render(t) & "\n")

proc initStyleStack*(defaultStyle: Style): StyleStack =
  ## rich style.py:770 — `StyleStack.__init__(self, default_style: "Style")`:
  ## initialise the stack with `[default_style]`.
  result = StyleStack()
  result.stack = @[defaultStyle]

proc repr*(self: StyleStack): string =
  ## rich style.py:773 — `StyleStack.__repr__(self) -> str`:
  ## `f"<stylestack {self._stack!r}>"`.
  var parts: seq[string] = @[]
  for s in self.stack: parts.add($s)
  result = "<stylestack [" & parts.join(", ") & "]>"

proc current*(self: StyleStack): Style =
  ## rich style.py:777 — `StyleStack.current` (`@property` style.py:776): the
  ## `Style` at the top of the stack (`self._stack[-1]`).
  result = self.stack[^1]

proc push*(self: StyleStack, style: Style) =
  ## rich style.py:781 — `StyleStack.push(self, style: Style) -> None`: push a
  ## new style onto the stack (combines with current, `self._stack[-1] + style`).
  self.stack.add(self.stack[^1] + some(style))

proc pop*(self: StyleStack): Style =
  ## rich style.py:789 — `StyleStack.pop(self) -> Style`: pop the last style and
  ## discard; returns the new current style.
  discard self.stack.pop()
  result = self.stack[^1]
