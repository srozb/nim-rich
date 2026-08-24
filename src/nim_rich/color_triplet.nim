## Port of `rich.color_triplet` (rich/color_triplet.py).
##
## A `ColorTriplet` is the red, green, and blue components of a color.
## Faithful Nim port: a named tuple mirrors Python's ``NamedTuple`` exactly
## (value type, named fields, default-initialisable to ``(0, 0, 0)``).
## Bodies mirror the Python source (``discard``) — see ``rich/color_triplet.py``.

import std/strutils

type
  ColorTriplet* = tuple[red: int, green: int, blue: int]
    ## rich color_triplet.py:4-38 — The red, green, and blue components of a
    ## color (`class ColorTriplet(NamedTuple)`). Field line refs:
    ## ``red``   → color_triplet.py:7 — Red component in 0 to 255 range.
    ## ``green`` → color_triplet.py:9 — Green component in 0 to 255 range.
    ## ``blue``  → color_triplet.py:11 — Blue component in 0 to 255 range.

proc hex*(self: ColorTriplet): string =
  ## rich color_triplet.py:15-18 — get the color triplet in CSS style
  ## (`@property` @14, `def hex` @15). Returns the CSS hex string
  ## ``"#rrggbb"`` (Python body `return` @18).
  result = "#" & toHex(self.red, 2).toLowerAscii & toHex(self.green, 2).toLowerAscii &
    toHex(self.blue, 2).toLowerAscii

proc rgb*(self: ColorTriplet): string =
  ## rich color_triplet.py:21-28 — The color in RGB format (`@property` @20,
  ## `def rgb` @21). Returns e.g. ``"rgb(100,23,255)"`` (Python body `return`
  ## @28).
  result = "rgb(" & $self.red & "," & $self.green & "," & $self.blue & ")"

proc normalized*(self: ColorTriplet): tuple[red: float, green: float, blue: float] =
  ## rich color_triplet.py:31-38 — Convert components into floats between 0
  ## and 1 (`@property` @30, `def normalized` @31). Returns
  ## ``(red/255.0, green/255.0, blue/255.0)`` (Python body `return` @38).
  result = (red: self.red.float / 255.0, green: self.green.float / 255.0,
           blue: self.blue.float / 255.0)
