## Port of `rich.terminal_theme` (rich/terminal_theme.py).
##
## `TerminalTheme` is a colour theme used when exporting console content to
## non-terminal formats (SVG, HTML). It bundles a background/foreground
## `ColorTriplet` plus a `Palette` of the 16 ANSI colours (8 normal + 8 bright,
## bright defaulting to normal when `None`).
##
## Import graph (terminal_theme.py:1-5): `from typing import List, Optional,
## Tuple` (terminal_theme.py:1) → `std/options` (`Option[seq[...]]` for `bright`)
## + the private alias `_ColorTuple = Tuple[int, int, int]` (terminal_theme.py:8)
## modelled as the unnamed Nim tuple `(int, int, int)`. `from .color_triplet
## import ColorTriplet` (terminal_theme.py:3) → `color_triplet`; `from .palette
## import Palette` (terminal_theme.py:4) → `palette`.
##
## Faithfulness note: Python's `_ColorTuple` is an *unnamed* `Tuple[int, int,
## int]`, so the `__init__` parameters are typed `(int, int, int)` /
## `openArray[(int, int, int)]` / `Option[seq[(int, int, int)]]` — exactly the
## literal form of the five module-level themes below (no named-tuple coercion).
## The *fields* (`background_color`/`foreground_color`) are `ColorTriplet`
## (named) because Python converts via `ColorTriplet(*background)`
## (terminal_theme.py:27-29); the `ansi_colors` field is a `Palette` built from
## `normal + (bright or normal)` (terminal_theme.py:30). body wires the
## construction body; the five `let` themes already carry the faithful colour
## data from terminal_theme.py:32-153 (verbatim tuples).
##
## Naming: `__init__`→`initTerminalTheme`, `background_color`→`backgroundColor`,
## `foreground_color`→`foregroundColor`, `ansi_colors`→`ansiColors`. Proc body
## is `discard` (port)` = nil ref).

import std/options

import color_triplet   # ColorTriplet — the named field type.
import palette          # Palette — the ansi_colors field type.

type
  TerminalTheme* = ref object of RootObj
    ## rich terminal_theme.py:9-30 — `class TerminalTheme`: a colour theme used
    ## when exporting console content. `ref object of RootObj` (Python reference
    ## semantics; built once, read many). Fields mirror the `__init__`
    ## assignments (terminal_theme.py:27-30).
    backgroundColor*: ColorTriplet
      ## terminal_theme.py:27 — `self.background_color = ColorTriplet(*background)`
      ## (a named `ColorTriplet`; the *param* is the unnamed `(int,int,int)`).
    foregroundColor*: ColorTriplet
      ## terminal_theme.py:28 — `self.foreground_color = ColorTriplet(*foreground)`.
    ansiColors*: Palette
      ## terminal_theme.py:30 — `self.ansi_colors = Palette(normal + (bright or
      ## normal))` (a 16-entry `Palette`; `bright` defaults to `normal` when
      ## `None`, terminal_theme.py:21-22 + 30).

proc initTerminalTheme*(
    background: (int, int, int),
    foreground: (int, int, int),
    normal: openArray[(int, int, int)],
    bright: Option[seq[(int, int, int)]] = none(seq[(int, int, int)]),
): TerminalTheme =
  ## rich terminal_theme.py:13-30 — `TerminalTheme.__init__(self, background:
  ## _ColorTuple, foreground: _ColorTuple, normal: List[_ColorTuple], bright:
  ## Optional[List[_ColorTuple]] = None) -> None`. `_ColorTuple = Tuple[int,
  ## int, int]` (terminal_theme.py:8) → the unnamed Nim tuple `(int, int, int)`,
  ## so every colour literal below typechecks verbatim. `bright` default `None`
  ## → `none(seq[(int, int, int)])`; body builds `ansiColors = Palette(normal
  ## + (bright.get(normal)))` and stores `ColorTriplet` conversions.
  result = TerminalTheme()
  result.backgroundColor = (red: background[0], green: background[1], blue: background[2])
  result.foregroundColor = (red: foreground[0], green: foreground[1], blue: foreground[2])
  # `self.ansi_colors = Palette(normal + (bright or normal))` (terminal_theme.py:30):
  # concatenate `normal` with `bright` (or `normal` again when `bright` is
  # `None`), converting each unnamed `(int,int,int)` to a named `ColorTriplet`.
  var palette: seq[ColorTriplet] = @[]
  for c in normal:
    palette.add((red: c[0], green: c[1], blue: c[2]))
  let brightSeq: seq[(int, int, int)] =
    if bright.isSome: bright.get else: @normal
  for c in brightSeq:
    palette.add((red: c[0], green: c[1], blue: c[2]))
  result.ansiColors = initPalette(palette)

# rich terminal_theme.py:32-153 — the five module-level themes. The colour
# tuples are transcribed verbatim from the Python source; body's
# `initTerminalTheme` body will store them into the `TerminalTheme` fields
# (returns `nil`, but the data is preserved in the call expressions).

let DEFAULT_TERMINAL_THEME* = initTerminalTheme(
  (255, 255, 255),
  (0, 0, 0),
  [
    (0, 0, 0),
    (128, 0, 0),
    (0, 128, 0),
    (128, 128, 0),
    (0, 0, 128),
    (128, 0, 128),
    (0, 128, 128),
    (192, 192, 192),
  ],
  some(@[
    (128, 128, 128),
    (255, 0, 0),
    (0, 255, 0),
    (255, 255, 0),
    (0, 0, 255),
    (255, 0, 255),
    (0, 255, 255),
    (255, 255, 255),
  ]),
) ## terminal_theme.py:32-58 — `DEFAULT_TERMINAL_THEME`: the default
  ## theme (white background, black foreground, the standard 16 ANSI colours).

let MONOKAI* = initTerminalTheme(
  (12, 12, 12),
  (217, 217, 217),
  [
    (26, 26, 26),
    (244, 0, 95),
    (152, 224, 36),
    (253, 151, 31),
    (157, 101, 255),
    (244, 0, 95),
    (88, 209, 235),
    (196, 197, 181),
    (98, 94, 76),
  ],
  some(@[
    (244, 0, 95),
    (152, 224, 36),
    (224, 213, 97),
    (157, 101, 255),
    (244, 0, 95),
    (88, 209, 235),
    (246, 246, 239),
  ]),
) ## terminal_theme.py:60-88 — `MONOKAI`: the Monokai theme (9 normal + 7
  ## bright; the extra normal entry is the bold/grey colour).

let DIMMED_MONOKAI* = initTerminalTheme(
  (25, 25, 25),
  (185, 188, 186),
  [
    (58, 61, 67),
    (190, 63, 72),
    (135, 154, 59),
    (197, 166, 53),
    (79, 118, 161),
    (133, 92, 141),
    (87, 143, 164),
    (185, 188, 186),
    (136, 137, 135),
  ],
  some(@[
    (251, 0, 31),
    (15, 114, 47),
    (196, 112, 51),
    (24, 109, 227),
    (251, 0, 103),
    (46, 112, 109),
    (253, 255, 185),
  ]),
) ## terminal_theme.py:90-118 — `DIMMED_MONOKAI`: a dimmed Monokai variant.

let NIGHT_OWLISH* = initTerminalTheme(
  (255, 255, 255),
  (64, 63, 83),
  [
    (1, 22, 39),
    (211, 66, 62),
    (42, 162, 152),
    (218, 170, 1),
    (72, 118, 214),
    (64, 63, 83),
    (8, 145, 106),
    (122, 129, 129),
    (122, 129, 129),
  ],
  some(@[
    (247, 110, 110),
    (73, 208, 197),
    (218, 194, 107),
    (92, 167, 228),
    (105, 112, 152),
    (0, 201, 144),
    (152, 159, 177),
  ]),
) ## terminal_theme.py:120-148 — `NIGHT_OWLISH`: a light-background theme.

let SVG_EXPORT_THEME* = initTerminalTheme(
  (41, 41, 41),
  (197, 200, 198),
  [
    (75, 78, 85),
    (204, 85, 90),
    (152, 168, 75),
    (208, 179, 68),
    (96, 138, 177),
    (152, 114, 159),
    (104, 160, 179),
    (197, 200, 198),
    (154, 155, 153),
  ],
  some(@[
    (255, 38, 39),
    (0, 130, 61),
    (208, 132, 66),
    (25, 132, 233),
    (255, 44, 122),
    (57, 130, 128),
    (253, 253, 197),
  ]),
) ## terminal_theme.py:150-153 — `SVG_EXPORT_THEME`: the theme used for SVG
  ## export (a dark Pygments-like palette).
