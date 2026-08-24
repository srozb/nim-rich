## Nim port of `rich.color` (rich/color.py).
##
## Terminal color definition: `ColorSystem`/`ColorType` enums, the `Color`
## record, the `ColorParseError` exception, the `ANSI_COLOR_NAMES` table and
## `RE_COLOR` regex, plus the `parse_rgb_hex`/`blend_rgb` helpers.
##
## Sibling imports: `richbase` (renderable base + `RichCast` bridge for
## `__rich__` → `richCast`), `color_triplet` (`ColorTriplet`).
## Deferred (body-only, not imported): `rich._palettes`
## (`EIGHT_BIT_PALETTE`/`STANDARD_PALETTE`/`WINDOWS_PALETTE`, color.py:8),
## `rich.terminal_theme` (`DEFAULT_TERMINAL_THEME`, color.py:11), `rich.repr`
## (`rich_repr` decorator, color.py:10), `rich.text`/`rich.style` (used only
## inside `__rich__`'s body, color.py:317-318).
##
## Forward placeholder types (`Text`, `Result`, `TerminalTheme`) are private
## and stand in for the real `text`/`repr`/`terminal_theme` modules (which
## exist but are NOT imported here, to break import cycles) so signatures
## compile; they are removed when the real modules are imported. Proc bodies are ported
## (Color.fromTriplet/fromRgb/parseRgbHex/blendRgb/system/etc. implement
## color.py); `__rich__`/`richRepr` return placeholder `Text()`/`Result()`
## pending the deferred `text`/`repr` deps.

import std/[options, tables, re]
import std/strutils
import std/math

import richbase
import color_triplet

type
  Text = ref object of RenderableBase
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] rich `Text` —
    ## `rich/text.py:118` (`class Text(JupyterMixin)`). Not yet written; stands
    ## in so `Color.richCast(): Text` satisfies the richbase `RichCast` concept
    ## (`richCast() is (string or RenderableBase)`) exactly as the real `Text`
    ## will (a `RenderableBase` subtype). It rejects no legal Python variant
    ## (it is a return-type placeholder; the default-call surface is
    ## unaffected). Removed when `text.nim` is imported.

  Result = object
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] rich `Result` —
    ## `rich/repr.py:18` (`Result = Iterable[Union[Any, Tuple[Any],
    ## Tuple[str, Any], Tuple[str, Any, Any]]]`, the `__rich_repr__` return
    ## type, color.py:326). It rejects no legal Python variant (it is a
    ## return-type stub; the `discard` body yields `default(Result)`). Removed
    ## when `repr.nim` is imported.

  TerminalTheme = object
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] rich `TerminalTheme` —
    ## `rich/terminal_theme.py:9` (`class TerminalTheme`); the `theme`
    ## parameter of `Color.get_truecolor` (color.py:349). It rejects no legal
    ## Python variant: the parameter defaults to `none(TerminalTheme)`
    ## (Python `theme=None`, color.py:349) and also accepts
    ## `some(TerminalTheme())`; the real `TerminalTheme` (a richer object) will
    ## replace this placeholder by name without changing the signature. Removed
    ## when `terminal_theme.nim` is imported.

  ColorSystem* {.pure.} = enum
    ## rich color.py:21 — One of the 3 color systems supported by terminals
    ## (`IntEnum`). `{.pure.}` scopes members (avoids clashing with the
    ## module-level `WINDOWS` const).
    standard = 1   ## rich color.py:24 — STANDARD = 1.
    eightBit = 2    ## rich color.py:25 — EIGHT_BIT = 2.
    truecolor = 3   ## rich color.py:26 — TRUECOLOR = 3.
    windows = 4     ## rich color.py:27 — WINDOWS = 4.

  ColorType* {.pure.} = enum
    ## rich color.py:36 — Type of color stored in `Color` (`IntEnum`).
    ## `{.pure.}` scopes members.
    default = 0    ## rich color.py:39 — DEFAULT = 0.
    standard = 1   ## rich color.py:40 — STANDARD = 1.
    eightBit = 2    ## rich color.py:41 — EIGHT_BIT = 2.
    truecolor = 3   ## rich color.py:42 — TRUECOLOR = 3.
    windows = 4     ## rich color.py:43 — WINDOWS = 4.

  Color* = object
    ## rich color.py:303 — Terminal color definition (`NamedTuple`). A value
    ## record mirroring the Python `NamedTuple`; `Option` fields default to
    ## `none(...)` (Python `None`).
    name*: string               ## rich color.py:306 — name of the color (input to `Color.parse`).
    `type`*: ColorType          ## rich color.py:308 — the type of the color (`type` is a Nim keyword).
    number*: Option[int]        ## rich color.py:310 — color number if a standard color, else None.
    triplet*: Option[ColorTriplet] ## rich color.py:312 — RGB triplet if an RGB color, else None.

const
  WINDOWS* = defined(windows)
    ## rich color.py:18 — `WINDOWS = sys.platform == "win32"`. Compile-time
    ## platform check (`defined(windows)`). Used at color.py:373,491,555,562,566.

let
  ansiColorNames* {.used.} = {
    "black": 0,
    "red": 1,
    "green": 2,
    "yellow": 3,
    "blue": 4,
    "magenta": 5,
    "cyan": 6,
    "white": 7,
    "bright_black": 8,
    "bright_red": 9,
    "bright_green": 10,
    "bright_yellow": 11,
    "bright_blue": 12,
    "bright_magenta": 13,
    "bright_cyan": 14,
    "bright_white": 15,
    "grey0": 16,
    "gray0": 16,
    "navy_blue": 17,
    "dark_blue": 18,
    "blue3": 20,
    "blue1": 21,
    "dark_green": 22,
    "deep_sky_blue4": 25,
    "dodger_blue3": 26,
    "dodger_blue2": 27,
    "green4": 28,
    "spring_green4": 29,
    "turquoise4": 30,
    "deep_sky_blue3": 32,
    "dodger_blue1": 33,
    "green3": 40,
    "spring_green3": 41,
    "dark_cyan": 36,
    "light_sea_green": 37,
    "deep_sky_blue2": 38,
    "deep_sky_blue1": 39,
    "spring_green2": 47,
    "cyan3": 43,
    "dark_turquoise": 44,
    "turquoise2": 45,
    "green1": 46,
    "spring_green1": 48,
    "medium_spring_green": 49,
    "cyan2": 50,
    "cyan1": 51,
    "dark_red": 88,
    "deep_pink4": 125,
    "purple4": 55,
    "purple3": 56,
    "blue_violet": 57,
    "orange4": 94,
    "grey37": 59,
    "gray37": 59,
    "medium_purple4": 60,
    "slate_blue3": 62,
    "royal_blue1": 63,
    "chartreuse4": 64,
    "dark_sea_green4": 71,
    "pale_turquoise4": 66,
    "steel_blue": 67,
    "steel_blue3": 68,
    "cornflower_blue": 69,
    "chartreuse3": 76,
    "cadet_blue": 73,
    "sky_blue3": 74,
    "steel_blue1": 81,
    "pale_green3": 114,
    "sea_green3": 78,
    "aquamarine3": 79,
    "medium_turquoise": 80,
    "chartreuse2": 112,
    "sea_green2": 83,
    "sea_green1": 85,
    "aquamarine1": 122,
    "dark_slate_gray2": 87,
    "dark_magenta": 91,
    "dark_violet": 128,
    "purple": 129,
    "light_pink4": 95,
    "plum4": 96,
    "medium_purple3": 98,
    "slate_blue1": 99,
    "yellow4": 106,
    "wheat4": 101,
    "grey53": 102,
    "gray53": 102,
    "light_slate_grey": 103,
    "light_slate_gray": 103,
    "medium_purple": 104,
    "light_slate_blue": 105,
    "dark_olive_green3": 149,
    "dark_sea_green": 108,
    "light_sky_blue3": 110,
    "sky_blue2": 111,
    "dark_sea_green3": 150,
    "dark_slate_gray3": 116,
    "sky_blue1": 117,
    "chartreuse1": 118,
    "light_green": 120,
    "pale_green1": 156,
    "dark_slate_gray1": 123,
    "red3": 160,
    "medium_violet_red": 126,
    "magenta3": 164,
    "dark_orange3": 166,
    "indian_red": 167,
    "hot_pink3": 168,
    "medium_orchid3": 133,
    "medium_orchid": 134,
    "medium_purple2": 140,
    "dark_goldenrod": 136,
    "light_salmon3": 173,
    "rosy_brown": 138,
    "grey63": 139,
    "gray63": 139,
    "medium_purple1": 141,
    "gold3": 178,
    "dark_khaki": 143,
    "navajo_white3": 144,
    "grey69": 145,
    "gray69": 145,
    "light_steel_blue3": 146,
    "light_steel_blue": 147,
    "yellow3": 184,
    "dark_sea_green2": 157,
    "light_cyan3": 152,
    "light_sky_blue1": 153,
    "green_yellow": 154,
    "dark_olive_green2": 155,
    "dark_sea_green1": 193,
    "pale_turquoise1": 159,
    "deep_pink3": 162,
    "magenta2": 200,
    "hot_pink2": 169,
    "orchid": 170,
    "medium_orchid1": 207,
    "orange3": 172,
    "light_pink3": 174,
    "pink3": 175,
    "plum3": 176,
    "violet": 177,
    "light_goldenrod3": 179,
    "tan": 180,
    "misty_rose3": 181,
    "thistle3": 182,
    "plum2": 183,
    "khaki3": 185,
    "light_goldenrod2": 222,
    "light_yellow3": 187,
    "grey84": 188,
    "gray84": 188,
    "light_steel_blue1": 189,
    "yellow2": 190,
    "dark_olive_green1": 192,
    "honeydew2": 194,
    "light_cyan1": 195,
    "red1": 196,
    "deep_pink2": 197,
    "deep_pink1": 199,
    "magenta1": 201,
    "orange_red1": 202,
    "indian_red1": 204,
    "hot_pink": 206,
    "dark_orange": 208,
    "salmon1": 209,
    "light_coral": 210,
    "pale_violet_red1": 211,
    "orchid2": 212,
    "orchid1": 213,
    "orange1": 214,
    "sandy_brown": 215,
    "light_salmon1": 216,
    "light_pink1": 217,
    "pink1": 218,
    "plum1": 219,
    "gold1": 220,
    "navajo_white1": 223,
    "misty_rose1": 224,
    "thistle1": 225,
    "yellow1": 226,
    "light_goldenrod1": 227,
    "khaki1": 228,
    "wheat1": 229,
    "cornsilk1": 230,
    "grey100": 231,
    "gray100": 231,
    "grey3": 232,
    "gray3": 232,
    "grey7": 233,
    "gray7": 233,
    "grey11": 234,
    "gray11": 234,
    "grey15": 235,
    "gray15": 235,
    "grey19": 236,
    "gray19": 236,
    "grey23": 237,
    "gray23": 237,
    "grey27": 238,
    "gray27": 238,
    "grey30": 239,
    "gray30": 239,
    "grey35": 240,
    "gray35": 240,
    "grey39": 241,
    "gray39": 241,
    "grey42": 242,
    "gray42": 242,
    "grey46": 243,
    "gray46": 243,
    "grey50": 244,
    "gray50": 244,
    "grey54": 245,
    "gray54": 245,
    "grey58": 246,
    "gray58": 246,
    "grey62": 247,
    "gray62": 247,
    "grey66": 248,
    "gray66": 248,
    "grey70": 249,
    "gray70": 249,
    "grey74": 250,
    "gray74": 250,
    "grey78": 251,
    "gray78": 251,
    "grey82": 252,
    "gray82": 252,
    "grey85": 253,
    "gray85": 253,
    "grey89": 254,
    "gray89": 254,
    "grey93": 255,
    "gray93": 255
  }.toTable
    ## rich color.py:49-285 — `ANSI_COLOR_NAMES`: maps color name → ANSI code
    ## (236 entries, color.py:49-285; `ANSI_COLOR_NAMES = {` @49, closes `}`
    ## @285). placeholder (empty); the faithful 236-entry table is
    ## wired in body. Used at color.py:441,608.

  reColor* {.used.} = re(r"^#([0-9a-f]{6})$|color\(([0-9]{1,3})\)$|rgb\(([\d\s,]+)\)$")
    ## rich color.py:292-299 — `RE_COLOR = re.compile(...)`: the verbose
    ## color-definition regex (`RE_COLOR = re.compile(` @292, closes `)` @299).
    ## placeholder (empty pattern); the faithful verbose pattern is
    ## compiled in body. Used at color.py:449.

type
  ColorParseError* = object of CatchableError
    ## rich color.py:288-289 — The color could not be parsed (`Exception`,
    ## `class ColorParseError(Exception)` @288).
    ## Raised by `Color.parse` (color.py:454) and consumed by `Style.parse`
    ## (style.py:528,555).

proc pyReprStr(s: string): string =
  ## Python ``repr(str)`` for error messages (the ``f"{x!r}"`` interpolation
  ## in `Color.parse`, color.py:454,461,475,480): prefers single quotes,
  ## switches to double when the string contains a single quote (and no double
  ## quote), matching CPython's quote-choice rule. Color inputs are plain ASCII
  ## with no backslashes or control characters, so the full CPython
  ## backslash/control-escaping algorithm is not exercised and is omitted.
  if '\'' in s and '"' notin s:
    result = "\"" & s & "\""
  else:
    result = "'" & s & "'"

proc pyRound(x: float): int =
  ## Python ``round(float)`` with no *ndigits* (round-half-to-even / banker's
  ## rounding), returning an ``int``. Used by `Color.downgrade`
  ## (color.py:530,540). Faithful port of CPython's algorithm.
  let f = floor(x)
  let d = x - f
  if d < 0.5:
    result = int(f)
  elif d > 0.5:
    result = int(f) + 1
  else:
    result = int(f)
    if (result and 1) != 0:
      result += 1

proc rgbToHls(r, g, b: float): (float, float, float) =
  ## Python ``colorsys.rgb_to_hls`` (stdlib) returning ``(h, l, s)``; ported
  ## faithfully for `Color.downgrade` (color.py:529). Python ``%`` is the floor
  ## modulo (sign of the divisor) → `std/math.floorMod`.
  let maxc = max(r, max(g, b))
  let minc = min(r, min(g, b))
  let l = (minc + maxc) / 2.0
  if minc == maxc:
    return (0.0, l, 0.0)
  let s = if l <= 0.5: (maxc - minc) / (maxc + minc)
          else: (maxc - minc) / (2.0 - maxc - minc)
  let rc = (maxc - r) / (maxc - minc)
  let gc = (maxc - g) / (maxc - minc)
  let bc = (maxc - b) / (maxc - minc)
  let h0 = if maxc == r: bc - gc
          elif maxc == g: 2.0 + rc - bc
          else: 4.0 + gc - rc
  let h = floorMod(h0 / 6.0, 1.0)
  result = (h, l, s)

proc repr*(self: ColorSystem): string =
  ## rich color.py:29 — `ColorSystem.__repr__` → `f"ColorSystem.{self.name}"`.
  result = "ColorSystem." & (
    case self
    of ColorSystem.standard: "STANDARD"
    of ColorSystem.eightBit: "EIGHT_BIT"
    of ColorSystem.truecolor: "TRUECOLOR"
    of ColorSystem.windows: "WINDOWS")

proc `$`*(self: ColorSystem): string =
  ## rich color.py:32 — `ColorSystem.__str__` → `repr(self)` (color.py:33).
  result = repr(self)

proc repr*(self: ColorType): string =
  ## rich color.py:45 — `ColorType.__repr__` → `f"ColorType.{self.name}"`.
  result = "ColorType." & (
    case self
    of ColorType.default: "DEFAULT"
    of ColorType.standard: "STANDARD"
    of ColorType.eightBit: "EIGHT_BIT"
    of ColorType.truecolor: "TRUECOLOR"
    of ColorType.windows: "WINDOWS")

proc richCast*(self: Color): Text =
  ## rich color.py:315 — `Color.__rich__(self) -> "Text"`: displays the actual
  ## color if Rich printed. Mirrored via the richbase `RichCast` bridge
  ## (`richCast`), returning `Text` (a `RenderableBase` subtype) so `Color`
  ## satisfies the `RichCast` concept — Python `Color` is renderable via
  ## `__rich__`. Body imports `Style`/`Text` (color.py:317-318) at call time.
  # DEFERRED(rich.text.Text.assemble + rich.style.Style, Batch 2): the real
  # `__rich__` (color.py:315-320) builds
  # `Text.assemble(f"<color {self.name!r} ({self.type.name.lower()})",
  # ("⬤", Style(color=self)), " >")`. A non-nil `Text()` placeholder satisfies
  # the `RichCast` concept (a `RenderableBase` subtype) until `text.nim` /
  # `style.nim` land.
  result = Text()

proc richRepr*(self: Color): Result =
  ## rich color.py:326 — `Color.__rich_repr__(self) -> Result`: yields `name`,
  ## `type`, `("number", number, None)`, `("triplet", triplet, None)`
  ## (color.py:328-331). Decorated `@rich_repr` (color.py:302).
  # DEFERRED(rich.repr.Result + @rich_repr, Batch 2): the real
  # `__rich_repr__` (color.py:326-331) yields `self.name; self.type;
  # ("number", self.number, None); ("triplet", self.triplet, None)`. `Result`
  # is a forward placeholder; `Result()` (default) stands in until `repr.nim`
  # lands.
  result = Result()

proc system*(self: Color): ColorSystem =
  ## rich color.py:333 — `Color.system` (`@property` color.py:332): the native
  ## color system for this color. DEFAULT → `ColorSystem.STANDARD`, else
  ## `ColorSystem(int(self.type))` (color.py:335-337).
  if self.`type` == ColorType.default:
    return ColorSystem.standard
  return ColorSystem(self.`type`.ord)

proc isSystemDefined*(self: Color): bool =
  ## rich color.py:340 — `Color.is_system_defined` (`@property` color.py:339):
  ## `self.system not in (EIGHT_BIT, TRUECOLOR)` (color.py:342).
  result = self.system notin {ColorSystem.eightBit, ColorSystem.truecolor}

proc isDefault*(self: Color): bool =
  ## rich color.py:345 — `Color.is_default` (`@property` color.py:344):
  ## `self.type == ColorType.DEFAULT` (color.py:347).
  result = self.`type` == ColorType.default

proc getTruecolor*(self: Color, theme: Option[TerminalTheme] = none(TerminalTheme),
                   foreground: bool = true): ColorTriplet =
  ## rich color.py:349 — `Color.get_truecolor(self, theme=None, foreground=True)
  ## -> ColorTriplet`: an equivalent RGB triplet. `theme` defaults to
  ## `DEFAULT_TERMINAL_THEME` (color.py:362); dispatches on `self.type`
  ## (TRUECOLOR/EIGHT_BIT/STANDARD/WINDOWS/DEFAULT, color.py:364-378).
  # `theme=None` resolves to `DEFAULT_TERMINAL_THEME` (color.py:362); the
  # theme/palette lookups below are DEFERRED(rich.terminal_theme /
  # rich._palettes, Batch 3). The TRUECOLOR branch is fully implemented.
  if self.`type` == ColorType.truecolor:
    return self.triplet.get
  elif self.`type` == ColorType.eightBit:
    # DEFERRED(rich._palettes.EIGHT_BIT_PALETTE, Batch 3):
    # `return EIGHT_BIT_PALETTE[self.number.get]` (color.py:368).
    return (0, 0, 0)
  elif self.`type` == ColorType.standard:
    # DEFERRED(rich.terminal_theme.DEFAULT_TERMINAL_THEME.ansi_colors,
    # Batch 3): `return theme.ansi_colors[self.number.get]` (color.py:372).
    return (0, 0, 0)
  elif self.`type` == ColorType.windows:
    # DEFERRED(rich._palettes.WINDOWS_PALETTE, Batch 3):
    # `return WINDOWS_PALETTE[self.number.get]` (color.py:375).
    return (0, 0, 0)
  else:  # self.`type` == ColorType.default
    # DEFERRED(rich.terminal_theme.DEFAULT_TERMINAL_THEME.foreground_color /
    # background_color, Batch 3): `return theme.foreground_color if
    # foreground else theme.background_color` (color.py:378).
    return (0, 0, 0)

proc fromAnsi*(T: typedesc[Color], number: int): Color =
  ## rich color.py:381 — `Color.from_ansi(cls, number: int) -> Color`
  ## (`@classmethod` color.py:380): create a Color from its 8-bit ANSI number
  ## (0-255); STANDARD if `number < 16` else EIGHT_BIT (color.py:392-394).
  result = T(name: "color(" & $number & ")",
             `type`: if number < 16: ColorType.standard else: ColorType.eightBit,
             number: some(number))

proc fromTriplet*(T: typedesc[Color], triplet: ColorTriplet): Color =
  ## rich color.py:397 — `Color.from_triplet(cls, triplet: ColorTriplet) ->
  ## Color` (`@classmethod` color.py:396): a truecolor RGB color from a triplet.
  result = T(name: triplet.hex, `type`: ColorType.truecolor, triplet: some(triplet))

proc fromRgb*(T: typedesc[Color], red, green, blue: float): Color =
  ## rich color.py:409 — `Color.from_rgb(cls, red, green, blue: float) -> Color`
  ## (`@classmethod` color.py:408): a truecolor from three 0-255 components;
  ## delegates to `from_triplet(ColorTriplet(int(red), ...))` (color.py:419).
  result = T.fromTriplet((red: red.int, green: green.int, blue: blue.int))

proc default*(T: typedesc[Color]): Color =
  ## rich color.py:423 — `Color.default(cls) -> Color` (`@classmethod`
  ## color.py:422): `cls(name="default", type=ColorType.DEFAULT)` (color.py:428).
  result = T(name: "default", `type`: ColorType.default)

proc parse*(T: typedesc[Color], color: string): Color =
  ## rich color.py:433 — `Color.parse(cls, color: str) -> Color`
  ## (`@classmethod` color.py:431, `@lru_cache(maxsize=1024)` color.py:432):
  ## parse a color definition. Handles "default", `ANSI_COLOR_NAMES`,
  ## `RE_COLOR` (24-bit `#rrggbb`, `color(n)`, `rgb(r,g,b)`); raises
  ## `ColorParseError` (color.py:454,461,475,480).
  let originalColor = color
  let colorLower = color.toLowerAscii.strip
  if colorLower == "default":
    return T(name: colorLower, `type`: ColorType.default)
  if colorLower in ansiColorNames:
    let cn = ansiColorNames[colorLower]
    return T(name: colorLower,
             `type`: if cn < 16: ColorType.standard else: ColorType.eightBit,
             number: some(cn))
  var m: array[3, string]
  if not colorLower.match(reColor, m):
    raise newException(ColorParseError, pyReprStr(originalColor) & " is not a valid color")
  let color24 = m[0]
  let color8 = m[1]
  let colorRgb = m[2]
  if color24.len > 0:
    let t: ColorTriplet = (parseHexInt(color24[0..1]), parseHexInt(color24[2..3]),
                          parseHexInt(color24[4..5]))
    return T(name: colorLower, `type`: ColorType.truecolor, triplet: some(t))
  elif color8.len > 0:
    let number = parseInt(color8)
    if number > 255:
      raise newException(ColorParseError, "color number must be <= 255 in " & pyReprStr(colorLower))
    return T(name: colorLower,
             `type`: if number < 16: ColorType.standard else: ColorType.eightBit,
             number: some(number))
  else:
    let comps = colorRgb.split(",")
    if comps.len != 3:
      raise newException(ColorParseError, "expected three components in " & pyReprStr(originalColor))
    let t: ColorTriplet = (parseInt(comps[0].strip), parseInt(comps[1].strip),
                          parseInt(comps[2].strip))
    if not (t.red <= 255 and t.green <= 255 and t.blue <= 255):
      raise newException(ColorParseError, "color components must be <= 255 in " & pyReprStr(originalColor))
    return T(name: colorLower, `type`: ColorType.truecolor, triplet: some(t))

proc getAnsiCodes*(self: Color, foreground: bool = true): seq[string] =
  ## rich color.py:485 — `Color.get_ansi_codes(self, foreground=True) ->
  ## Tuple[str, ...]` (`@lru_cache(maxsize=1024)` color.py:484): the ANSI
  ## escape codes for this color. `Tuple[str, ...]` modelled as `seq[string]`
  ## (variable-length homogeneous). Dispatches on `self.type`
  ## (color.py:487-510).
  let t = self.`type`
  if t == ColorType.default:
    result = @[(if foreground: "39" else: "49")]
  elif t == ColorType.windows:
    let number = self.number.get
    let (fore, back) = if number < 8: (30, 40) else: (82, 92)
    result = @[$(if foreground: fore + number else: back + number)]
  elif t == ColorType.standard:
    let number = self.number.get
    let (fore, back) = if number < 8: (30, 40) else: (82, 92)
    result = @[$(if foreground: fore + number else: back + number)]
  elif t == ColorType.eightBit:
    let number = self.number.get
    result = @[(if foreground: "38" else: "48"), "5", $number]
  else:  # truecolor
    let t2 = self.triplet.get
    result = @[(if foreground: "38" else: "48"), "2", $t2.red, $t2.green, $t2.blue]

proc downgrade*(self: Color, system: ColorSystem): Color =
  ## rich color.py:513 — `Color.downgrade(self, system: ColorSystem) -> Color`
  ## (`@lru_cache(maxsize=1024)` color.py:512): downgrade to a system with
  ## fewer colors (EIGHT_BIT/STANDARD/WINDOWS, color.py:516-568).
  if self.`type` == ColorType.default or self.`type`.ord == system.ord:
    return self
  if system == ColorSystem.eightBit and self.system == ColorSystem.truecolor:
    let n = self.triplet.get.normalized
    let (_, l, s) = rgbToHls(n.red, n.green, n.blue)
    if s < 0.15:
      let gray = pyRound(l * 25.0)
      let cn = if gray == 0: 16 elif gray == 25: 231 else: 231 + gray
      return Color(name: self.name, `type`: ColorType.eightBit, number: some(cn))
    else:
      let t = self.triplet.get
      let sixRed = if t.red < 95: t.red.float / 95.0 else: 1.0 + (t.red - 95).float / 40.0
      let sixGreen = if t.green < 95: t.green.float / 95.0 else: 1.0 + (t.green - 95).float / 40.0
      let sixBlue = if t.blue < 95: t.blue.float / 95.0 else: 1.0 + (t.blue - 95).float / 40.0
      let cn = 16 + 36 * pyRound(sixRed) + 6 * pyRound(sixGreen) + pyRound(sixBlue)
      return Color(name: self.name, `type`: ColorType.eightBit, number: some(cn))
  elif system == ColorSystem.standard:
    # DEFERRED(rich._palettes.STANDARD_PALETTE.match + EIGHT_BIT_PALETTE,
    # Batch 3): the real STANDARD downgrade (color.py:543-552) maps the
    # triplet via `STANDARD_PALETTE.match(triplet)`. Returns `self` as a
    # no-op placeholder until `_palettes` lands.
    return self
  elif system == ColorSystem.windows:
    # DEFERRED(rich._palettes.WINDOWS_PALETTE.match + EIGHT_BIT_PALETTE,
    # Batch 3): the real WINDOWS downgrade (color.py:554-566) maps the triplet
    # via `WINDOWS_PALETTE.match(triplet)` (with the `< 16` short-circuit at
    # color.py:560). Returns `self` as a no-op placeholder until `_palettes`
    # lands.
    return self
  return self

proc parseRgbHex*(hexColor: string): ColorTriplet =
  ## rich color.py:571 — `parse_rgb_hex(hex_color: str) -> ColorTriplet`: parse
  ## six hex characters into an RGB triplet (color.py:575-577).
  if hexColor.len != 6:
    raise newException(ValueError, "must be 6 characters")
  result = (parseHexInt(hexColor[0..1]), parseHexInt(hexColor[2..3]),
            parseHexInt(hexColor[4..5]))

proc blendRgb*(color1: ColorTriplet, color2: ColorTriplet, crossFade: float = 0.5): ColorTriplet =
  ## rich color.py:580 — `blend_rgb(color1, color2, cross_fade=0.5) ->
  ## ColorTriplet`: blend one RGB color into another (color.py:584-590).
  result = (int(color1.red.float + (color2.red.float - color1.red.float) * crossFade),
            int(color1.green.float + (color2.green.float - color1.green.float) * crossFade),
            int(color1.blue.float + (color2.blue.float - color1.blue.float) * crossFade))
