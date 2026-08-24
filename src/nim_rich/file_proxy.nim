## nim_rich / file_proxy.nim — port of rich source.
## =====================================================================
## rich port, `rich/file_proxy.py` (60 lines).
##
## `FileProxy` — a file-like proxy (`io.TextIOBase` subclass) that wraps a real
## file plus the owning `Console`; `write` text is ANSI-decoded and routed
## through the console's render path (file_proxy.py:12-60).
##
## Import graph (faithful to file_proxy.py:1-11):
##   `ansi`    → `AnsiDecoder`, `initAnsiDecoder` (file_proxy.py:9)
##               [signature dep — `FileProxy.ansiDecoder` field type]
##   `console` → `Console` (file_proxy.py:10), `FileHandle` (the `IO[str]` base)
##               [signature dep — `FileProxy.console`/`file` field types]
##   `text`    → `Text` (file_proxy.py:11)
##               [body dep — `write` builds `Text("\\n").join(...)` (file_proxy.py:43);
##                imported for graph faithfulness; emits an unused-import
##                warning , as `columns.nim` does for its body deps]
## `Console` is imported at runtime here (rich guards it under `TYPE_CHECKING`,
## file_proxy.py:10-11, but `FileProxy.__console` is typed `Console`, so the Nim
## port imports it for the field type). `FileHandle` (the `IO[str]` handle) is
## the provisional `ref object of RootObj` defined in `console.nim`,
## modelling Python's `IO[str]`; `FileProxy` subclasses it so a `FileProxy` may
## be passed where a `FileHandle` is expected (mirrors rich assigning a
## `FileProxy` to `Console.file`).
##
## Omissions (documented):
##   * `FileProxy.__getattr__(self, name: str) -> Any` (file_proxy.py:25-26):
##     Python's dynamic attribute delegation to the wrapped file has no direct
##     Nim analogue (Nim objects are not dynamically dispatchable on arbitrary
##     attribute names). Consumers reach the wrapped file via `richProxiedFile`.
##   * `write`/`flush`/`fileno`/`isatty` bodies (file_proxy.py:28-60) are body
##     (they need `AnsiDecoder.decode_line` + `Console`'s render/buffer path).
##
## Naming (convention): `__init__`→`initFileProxy`, the `__console`/
## `__file`/`__buffer`/`__ansi_decoder` name-mangled privates → `console`/`file`/
## `buffer`/`ansiDecoder` (the `__file`→`file` field coexists with the
## `richProxiedFile` proc; the `console` field coexists with the `console`
## module — only the uppercase `Console`/`FileHandle` types are read from it).

import ansi                 # AnsiDecoder, initAnsiDecoder (file_proxy.py:9).
import console              # Console (file_proxy.py:10), FileHandle (IO[str]).
import text                 # Text (file_proxy.py:11; body dep — `write` builds
                            # `Text("\n").join(...)` (file_proxy.py:43); graph
                            # faithfulness, accepts the Phase-0 unused warning).

import std/strutils          # `find`/`join` — `write`/`flush` string partitioning/join.
import std/options          # `none(…)` — `Console.exit` exc-triple args.
import std/sequtils         # `mapIt` — decode-line collection (type-inferred).
import api_types            # `RenderableValue`/`rvString`/`rvConsoleRenderable` —
                            # the storable `RenderableType` handle for `Console.print`.
import richbase             # `RenderableBase` — upcast base for `Text`→field.

# Python `str.partition` analogue (file_proxy.py:34): `(before, sep, after)`;
# `sep` is the empty string when `sep` is not found. Private (Nim `strutils` has
# no `partition`).
proc partitionStr(s, sep: string): tuple[before, sepMatched, after: string] =
  let i = s.find(sep)
  if i < 0:
    result = (s, "", "")
  else:
    result = (s[0..<i], sep, s[i+sep.len..<s.len])

type
  FileHandle = console.FileHandle
    ## Private alias disambiguating `FileHandle`: `std/syncio` also exports a
    ## `FileHandle` (the C `File` handle), and the `console.FileHandle`
    ## (provisional `IO[str]` handle) this module means is ambiguous with it when
    ## both are in scope. Module-scoped (where `console` = the module, not the
    ## `initFileProxy` `console` param) so it also sidesteps the
    ## param-shadows-module issue. Private (no `*`) so the umbrella does not
    ## re-export a second `FileHandle` alongside `console.FileHandle`.
  FileProxy* = ref object of FileHandle
    ## rich file_proxy.py:12-24 — `class FileProxy(io.TextIOBase)`: a file-like
    ## proxy that wraps a real file and an owning `Console`; `write` text is
    ## decoded (strip ANSI) and printed via the console. A subtype of
    ## `FileHandle` (the `IO[str]` handle from `console.nim`), so a `FileProxy`
    ## may be passed where a `FileHandle` is expected (mirrors rich passing a
    ## `FileProxy` to `Console.file`). The four name-mangled privates
    ## (`__console`/`__file`/`__buffer`/`__ansi_decoder`, file_proxy.py:15-18)
    ## become the exported `console`/`file`/`buffer`/`ansiDecoder` fields.
    console*: Console          ## file_proxy.py:15 — `__console: Console`.
    file*: FileHandle          ## file_proxy.py:16 — `__file: IO[str]`.
    buffer*: seq[string]       ## file_proxy.py:17 — `__buffer: List[str]`.
    ansiDecoder*: AnsiDecoder  ## file_proxy.py:18 — `__ansi_decoder: AnsiDecoder`.

proc initFileProxy*(console: Console, file: FileHandle): FileProxy =
  ## rich file_proxy.py:19-24 — `FileProxy.__init__(self, console: "Console",
  ## file: IO[str]) -> None`: store the owning console, the wrapped file, an
  ## empty line buffer, and a fresh `AnsiDecoder`. The `console`/`file` params
  ## shadow the `console` module within this proc (body body).
  ## (returns a default `FileProxy`; body populates the fields from the
  ## args, per the `initNode`/`initPretty` stub convention).
  result = FileProxy()
  result.console = console
  result.file = file
  result.buffer = @[]
  result.ansiDecoder = initAnsiDecoder()

proc richProxiedFile*(self: FileProxy): FileHandle =
  ## rich file_proxy.py:26-28 — `FileProxy.rich_proxied_file` (`@property`,
  ## file_proxy.py:25): the wrapped file. Returns `self.__file`.
  result = self.file

proc write*(self: FileProxy, text: string): int =
  ## rich file_proxy.py:30-48 — `FileProxy.write(self, text: str) -> int`:
  ## partition `text` on newlines, ANSI-decode each complete line via
  ## `self.ansi_decoder.decode_line`, join with `Text("\\n")`, and print via
  ## `self.console`; returns `len(text)`. Body needs `AnsiDecoder`'s
  ## `decode_line` + `Console.print`.
  # Python raises `TypeError` if `text` is not a `str`; the Nim param is typed
  # `string`, so the check is enforced at compile time (no runtime raise).
  var buffer = self.buffer
  var lines: seq[string] = @[]
  var t = text
  while t.len > 0:
    let (line, newLine, rest) = partitionStr(t, "\n")
    t = rest
    if newLine.len > 0:
      lines.add(join(buffer, "") & line)
      buffer.setLen(0)
    else:
      buffer.add(line)
      break
  self.buffer = buffer
  if lines.len > 0:
    let console = self.console
    # `with console:` enters a buffer context so the single print is flushed
    # atomically (file_proxy.py:42-45).
    discard console.enter()
    try:
      let decoded = lines.mapIt(self.ansiDecoder.decodeLine(it))
      let output = initText("\n").join(decoded)
      var objs: seq[RenderableValue] = @[]
      objs.add(RenderableValue(kind: rvConsoleRenderable,
                               consoleItem: RenderableBase(output)))
      console.print(objs)
    finally:
      console.exit(none(RootRef), none(ref CatchableError), none(RootRef))
  result = t.len

proc flush*(self: FileProxy) =
  ## rich file_proxy.py:50-54 — `FileProxy.flush(self) -> None`: flush any
  ## buffered partial line by printing it and clearing the buffer.
  let output = join(self.buffer, "")
  if output.len > 0:
    var objs: seq[RenderableValue] = @[]
    objs.add(RenderableValue(kind: rvString, textStr: output))
    self.console.print(objs)
  self.buffer.setLen(0)

proc fileno*(self: FileProxy): int =
  ## rich file_proxy.py:56-57 — `FileProxy.fileno(self) -> int`: delegate to
  ## the wrapped file's `fileno`.
  # DEFERRED(console.FileHandle, Batch 7): the provisional `FileHandle` placeholder
  # (`ref object of RootObj`, no `fileno`) cannot delegate; return -1 (the
  # `NullFile` analogue, _null_file.py) until a real `IO[str]` handle is wired.
  result = -1

proc isatty*(self: FileProxy): bool =
  ## rich file_proxy.py:59-60 — `FileProxy.isatty(self) -> bool`: delegate to
  ## the wrapped file's `isatty`.
  # DEFERRED(console.FileHandle, Batch 7): the provisional `FileHandle` placeholder
  # (`ref object of RootObj`, no `isatty`) cannot delegate; return `false` until
  # a real `IO[str]` handle is wired.
  result = false

discard
