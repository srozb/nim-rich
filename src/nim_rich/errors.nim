## Port of `rich.errors` (rich/errors.py).
##
## Exception classes for `rich`. Python `Exception` is mirrored as Nim
## `CatchableError` (the base of all catchable exceptions); subclasses mirror
## the Python hierarchy (`StyleSyntaxError`/`StyleStackError`/`NotRenderableError`/
## `MarkupError`/`LiveError`/`NoAltScreen` are `ConsoleError` subclasses;
## `MissingStyle` is a `StyleError` subclass). No imports — Nim exceptions are
## built into `system`. These are pure type declarations with no methods.

type
  ConsoleError* = object of CatchableError
    ## rich errors.py:1 — `ConsoleError(Exception)`: an error in console
    ## operation. Base of most rich errors.

  StyleError* = object of CatchableError
    ## rich errors.py:5 — `StyleError(Exception)`: an error in styles. Base of
    ## `MissingStyle`.

  StyleSyntaxError* = object of ConsoleError
    ## rich errors.py:9 — `StyleSyntaxError(ConsoleError)`: style was badly
    ## formatted. Raised by `Style.parse` (style.py:525,529,538,546,556) and
    ## `Style.chain` (style.py:401).

  MissingStyle* = object of StyleError
    ## rich errors.py:13 — `MissingStyle(StyleError)`: no such style.

  StyleStackError* = object of ConsoleError
    ## rich errors.py:17 — `StyleStackError(ConsoleError)`: style stack is
    ## invalid.

  NotRenderableError* = object of ConsoleError
    ## rich errors.py:21 — `NotRenderableError(ConsoleError)`: object is not
    ## renderable. Raised by `Measurement.get` (measure.py:115).

  MarkupError* = object of ConsoleError
    ## rich errors.py:25 — `MarkupError(ConsoleError)`: markup was badly
    ## formatted.

  LiveError* = object of ConsoleError
    ## rich errors.py:29 — `LiveError(ConsoleError)`: error related to Live
    ## display.

  NoAltScreen* = object of ConsoleError
    ## rich errors.py:33 — `NoAltScreen(ConsoleError)`: alt screen mode was
    ## required.
