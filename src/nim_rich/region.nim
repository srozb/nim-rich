## Port of `rich.region` (rich/region.py).
##
## `Region` is a `NamedTuple` defining a rectangular region of the screen
## (region.py:4-10). Faithful Nim port: a named tuple mirrors Python's
## ``NamedTuple`` exactly (value type, named fields, default-initialisable to
## ``(0, 0, 0, 0)``), exactly as `color_triplet.nim` models `ColorTriplet`.
## `region.py` has no runtime sibling imports (only `from typing import
## NamedTuple` @ region.py:1-1) and no methods, so this module needs no sibling
## imports — it is a pure leaf.
##
## rules: no proc bodies (`Region` declares only fields); the exported
## type carries a `##` docstring with its rich source mapping.

type
  Region* = tuple[x: int, y: int, width: int, height: int]
    ## rich region.py:4-10 — `class Region(NamedTuple)`: defines a rectangular
    ## region of the screen (docstring region.py:5-5). A named tuple mirrors
    ## the `NamedTuple` exactly (value type, named fields). Field line refs:
    ## ``x``      → region.py:7 — The x coordinate (column).
    ## ``y``      → region.py:8 — The y coordinate (row).
    ## ``width``  → region.py:9 — The width of the region.
    ## ``height`` → region.py:10 — The height of the region.
