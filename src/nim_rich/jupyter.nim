## Port of `rich.jupyter` (rich/jupyter.py).
##
## Jupyter notebook integration: `JupyterRenderable` (jupyter.py:18) and
## `JupyterMixin` (jupyter.py:36) provide `_repr_mimebundle_`; `_render_segments`
## (jupyter.py:59) renders segments to HTML; `display` (jupyter.py:84) and
## `print` (jupyter.py:98) proxy to the console. `console`/`bar`/`constrain`/
## `panel`/`table`/… mix in `JupyterMixin` (`from .jupyter import JupyterMixin`).
## `jupyter.py` has no `__all__`; all non-underscore top-level names are public,
## while `_render_segments` (jupyter.py:59) is private.
##
## Import graph (rich/jupyter.py:1-8): `from typing import TYPE_CHECKING, Any,
## Dict, Iterable, List, Sequence`, `from . import get_console` (jupyter.py:6),
## `from .segment import Segment` (jupyter.py:7), `from .terminal_theme import
## DEFAULT_TERMINAL_THEME` (jupyter.py:8). The rich sibling deps that exist in
## are `segment` (`Segment`) and `richbase` (`RenderableBase`, the
## `JupyterMixin` base). `get_console` (from `.`, i.e. `console.py`, jupyter.py:6)
## and `DEFAULT_TERMINAL_THEME` (`terminal_theme.py`, jupyter.py:8) are not yet
## written → body-only (body) and referenced in docstrings, not imported.
##
## `JupyterMixin` base choice. Python `JupyterMixin` is a plain mixin
## (`__slots__ = ()`, jupyter.py:38); `class Foo(JupyterMixin)` makes `Foo`
## renderable in Jupyter. The already-frozen modules (`align`/`rule`/`panel`/
## `bar`/`constrain`/`columns`/`containers`/`table`/…) predate `jupyter.nim` and
## model `class Foo(JupyterMixin)` as `ref object of RenderableBase` (documenting
## "JupyterMixin modelled via RenderableBase"). To stay consistent and let a
## future Phase-1 `ref object of JupyterMixin` be transitively a `RenderableBase`,
## `JupyterMixin` itself is `ref object of RenderableBase`. body may switch
## those modules' base from `RenderableBase` to `JupyterMixin` (signatures
## unchanged). `JupyterRenderable` is NOT a console renderable (it is a mime
## shim) → `ref object of RootObj`.
##
## `include`/`exclude` are Nim keywords, so `_repr_mimebundle_`'s `include`/
## `exclude` params (jupyter.py:26-27, 43-44) are renamed `includeSet`/
## `excludeSet`. `**kwargs: Any` (jupyter.py:27, 44) has no Nim equivalent and is
## body-only (body). `print(*args: Any, **kwargs: Any)` (jupyter.py:98) is
## modelled as a `varargs[untyped]` template — non-narrowing (every legal Python
## call form compiles), exactly as `style.nim` models `**handlers: Any` via a
## `varargs[untyped]` template. Proc bodies are `discard` (port).

import std/options  # Option.isSome/.get — Segment.style/.control/.link handling (_render_segments).
import std/tables   # Table[string, string] — _repr_mimebundle_ return (Dict[str, str]).
import std/strutils # replace/join — HTML escape + fragment join (_render_segments).
import segment      # Segment (jupyter.py:7) — _render_segments/display params.
import richbase     # RenderableBase — JupyterMixin base (see header).
import style        # Style — Segment.style downcast + Style.getHtmlStyle/bool/link.

const jupyterHtmlFormat* = """<pre style="white-space:pre;overflow-x:auto;line-height:normal;font-family:Menlo,'DejaVu Sans Mono',consolas,'Courier New',monospace">{code}</pre>"""
  ## rich jupyter.py:13-17 — `JUPYTER_HTML_FORMAT`: the HTML template wrapping
  ## rendered segments; `{code}` is the placeholder substituted in
  ## `_render_segments` (jupyter.py:79). Stored verbatim (triple-quoted so the
  ## embedded quotes/braces are literal).

type
  JupyterRenderable* = ref object of RootObj
    ## rich jupyter.py:18-33 — `class JupyterRenderable`: a shim to write html to
    ## a Jupyter notebook (NOT a console renderable → `ref object of RootObj`).
    ## Fields mirror the `__init__` assignments (jupyter.py:22-23).
    html*: string   ## rich jupyter.py:22 — `self.html = html` (the rendered HTML).
    text*: string   ## rich jupyter.py:23 — `self.text = text` (the plain-text fallback).

  ## `JupyterMixin` is now defined ONCE in `richbase.nim` (`of RenderableBase`)
  ## — UNIFIED (audit): the former duplicate `JupyterMixin` here
  ## competed with `richbase`'s `of RootObj`, leaving `Emoji` (which imports
  ## `richbase`) off the `RenderableBase` hierarchy. `jupyter.nim` imports
  ## `richbase` (line 44) so it uses the canonical `JupyterMixin` directly; the
  ## `_repr_mimebundle_` proc below takes `JupyterMixin` (resolved to
  ## `richbase`'s via the import). Markdown/Syntax/Emoji all inherit the SAME
  ## `JupyterMixin` → all dispatch via the virtual `renderConsole`.

proc initJupyterRenderable*(html: string, text: string): JupyterRenderable =
  ## rich jupyter.py:21-23 — `JupyterRenderable.__init__(self, html: str, text:
  ## str) -> None`: store `html`/`text` (jupyter.py:22-23). (body
  ## `discard` ⇒ returns `nil`).
  result = JupyterRenderable(html: html, text: text)

proc reprMimeBundle*(self: JupyterRenderable, includeSet: openArray[string],
                     excludeSet: openArray[string]): Table[string, string] =
  ## rich jupyter.py:25-33 — `JupyterRenderable._repr_mimebundle_(self, include,
  ## exclude, **kwargs) -> Dict[str, str]`: build `{text/plain: self.text,
  ## text/html: self.html}` then filter by `include`/`exclude` (jupyter.py:28-32).
  ## `include`/`exclude` are Nim keywords → `includeSet`/`excludeSet`;
  ## `Sequence[str]` → `openArray[string]`; `Dict[str, str]` →
  ## `Table[string, string]`; `**kwargs: Any` is body-only (body). port
  ## stub (body `discard` ⇒ returns `init(Table[string, string])`).
  # jupyter.py:28-32: `data = {text/plain: self.text, text/html: self.html}`
  # then filter by `include`/`exclude` (keep if `include` non-empty and key in
  # it; drop if `exclude` non-empty and key in it).
  var data = {"text/plain": self.text, "text/html": self.html}.toTable
  if includeSet.len > 0:
    var filtered = initTable[string, string]()
    for k, v in data.pairs:
      if includeSet.contains(k): filtered[k] = v
    data = filtered
  if excludeSet.len > 0:
    var filtered = initTable[string, string]()
    for k, v in data.pairs:
      if not excludeSet.contains(k): filtered[k] = v
    data = filtered
  result = data

proc reprMimeBundle*(self: JupyterMixin, includeSet: openArray[string],
                     excludeSet: openArray[string]): Table[string, string] =
  ## rich jupyter.py:41-56 — `JupyterMixin._repr_mimebundle_(self, include,
  ## exclude, **kwargs) -> Dict[str, str]`: render `self` via `get_console()`
  ## (jupyter.py:43, 45), build HTML with `_render_segments` (jupyter.py:46) and
  ## plain text with `console._render_buffer` (jupyter.py:47), then filter by
  ## `include`/`exclude` (jupyter.py:51-54). `get_console` (`.`, jupyter.py:43)
  ## and `DEFAULT_TERMINAL_THEME` (used by `_render_segments`) are not yet
  ## written → body-only (body). `include`/`exclude` → `includeSet`/
  ## `excludeSet` (Nim keywords). (body `discard`).
  # DEFERRED(console.get_console, later batch): `get_console()` (jupyter.py:43)
  # is not exposed in the Nim port (no `getConsole`/`get_console` proc in
  # `console.nim`). The faithful body renders `self` via the console, builds
  # HTML with `renderSegments` and plain text with `console.renderBuffer`, then
  # filters by `includeSet`/`excludeSet` (jupyter.py:45-54); without a console
  # getter none of that is reachable. Return an empty mime bundle as a safe
  # best-effort until `get_console` lands.
  result = initTable[string, string]()

proc renderSegments(segments: openArray[Segment]): string =
  ## rich jupyter.py:59-81 — `_render_segments(segments: Iterable[Segment])
  ## -> str`: HTML-escape each segment's text, wrap styled text in
  ## `<span style="…">` (via `style.get_html_style(theme)`, jupyter.py:73-76) and
  ## links in `<a href>`, join and wrap in `JUPYTER_HTML_FORMAT` (jupyter.py:79).
  ## Private (`_`-prefixed). `Iterable[Segment]` → `openArray[Segment]`; uses
  ## `Segment.simplify`/`style.get_html_style`/`DEFAULT_TERMINAL_THEME` (body-only,
  ## body). (body `discard` ⇒ `""`).
  proc escapeHtml(text: string): string =
    # jupyter.py:61-63: `&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`.
    text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
  var fragments: seq[string] = @[]
  for seg in segment.simplify(segments):
    if seg.control.isSome and seg.control.get.len > 0:
      continue  # jupyter.py:70: `if control: continue`
    var text = escapeHtml(seg.text)
    if seg.style.isSome and seg.style.get != nil:
      let s = Style(seg.style.get)  # downcast StyleRef -> Style
      if s.bool():  # jupyter.py:73: `if style:` (Style.__bool__)
        let rule = s.getHtmlStyle()  # theme=None -> DEFAULT_TERMINAL_THEME
        if rule.len > 0:
          text = "<span style=\"" & rule & "\">" & text & "</span>"
        if s.link.isSome and s.link.get.len > 0:
          text = "<a href=\"" & s.link.get & "\" target=\"_blank\">" & text & "</a>"
    fragments.add(text)
  let code = join(fragments, "")
  result = jupyterHtmlFormat.replace("{code}", code)

proc display*(segments: openArray[Segment], text: string) =
  ## rich jupyter.py:84-95 — `display(segments, text) -> None`: render segments
  ## to Jupyter via `IPython.display` (jupyter.py:86-94; `ModuleNotFoundError` is
  ## swallowed, jupyter.py:93-95). `Iterable[Segment]` → `openArray[Segment]`.
  # jupyter.py:84-95: build the HTML and a JupyterRenderable, then attempt
  # `IPython.display.display(jupyter_renderable)` inside a
  # `try/except ModuleNotFoundError`. IPython is never installed in the Nim
  # runtime, so the `except` arm always fires — the proc is a no-op beyond
  # building the renderable (which has no observable side effect).
  let html = renderSegments(segments)
  let jupyterRenderable = initJupyterRenderable(html, text)
  # DEFERRED(IPython.display, not available in Nim): the `ipython_display` call
  # (jupyter.py:93) cannot run; `discard` mirrors that the built renderable is
  # never actually displayed.
  discard jupyterRenderable

template print*(args: varargs[untyped]) =
  ## rich jupyter.py:98-101 — `print(*args: Any, **kwargs: Any) -> None`: proxy
  ## for `Console.print` (`get_console().print(*args, **kwargs)`, jupyter.py:100).
  ## `*args: Any` + `**kwargs: Any` are modelled as `varargs[untyped]` (each
  ## `name = value` keyword arg is captured as an AST node), exactly as
  ## `style.nim` models `**handlers: Any` — non-narrowing, so every legal Python
  ## call form compiles (`jupyterPrint(a)`, `jupyterPrint(a, b, sep = " ")`).
  ## stub (body `discard`).
  # DEFERRED(console.get_console + Console.print, later batch): Python
  # `print(*args, **kwargs)` proxies to `get_console().print(*args, **kwargs)`
  # (jupyter.py:100). `get_console()` is not yet exposed in the Nim port and
  # `**kwargs` has no Nim equivalent, so the template is a no-op placeholder
  # until `get_console` and a `**kwargs`-capable `Console.print` land.
  discard
