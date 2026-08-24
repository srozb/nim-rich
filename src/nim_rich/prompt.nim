## Port of `rich.prompt` (rich/prompt.py, 400 lines).
##
## `prompt` provides interactive terminal prompts: the abstract
## `PromptBase[T]` (a `Generic[PromptType]` class driving the ask/validate
## loop, prompt.py:30-301) plus the four concrete subclasses `Prompt` (str),
## `IntPrompt` (int), `FloatPrompt` (float) and `Confirm` (bool)
## (prompt.py:304-363), and the `PromptError`/`InvalidResponse` exceptions
## (prompt.py:11-27).
##
## Import graph (rich/prompt.py:1-7): runtime sibling imports are `from
## typing import Any, Generic, List, Optional, TextIO, TypeVar, Union,
## overload` (prompt.py:1), `from . import get_console` (prompt.py:5),
## `from .console import Console` (prompt.py:6), `from .text import Text,
## TextType` (prompt.py:7). `get_console` is a `rich.__init__` top-level helper
## (mirrored by the umbrella, not a sibling module); the `self.console =
## console or get_console()` call (prompt.py:62) is a BODY-only dep — deferred
## to body. `TextIO` (`typing.TextIO`, the optional `stream` param) has no
## Nim equivalent in scope → a provisional `TextStream* = ref object of
## RootObj` forward handle (mirrors the `IoStream` placeholder in `live.nim`
## for `IO[str]`); removed when a real IO handle lands.
##
## wiring (this file):
##   `import std/options` — `Option[seq[string]]`/`Option[RenderableValue]`/
##                         `Option[TextStream]`/`Option[float]` params.
##   `import segment`      — re-exports `richbase` (`ConsoleHandle`,
##                         `ConsoleOptions`, `RenderResult`, `RenderableType`,
##                         `RenderableBase`, …) + `Style`.
##   `import console`       — `Console` (prompt.py:6,62; the real console type,
##                         now present post-— used for the
##                         `console` field/param and the `getInput` classmethod,
##                         matching `file_proxy.nim`'s use of the real
##                         `Console`).
##   `import text`          — `Text`, `TextType` (prompt.py:7).
##   `import api_types`     — `RenderableValue` (the non-narrowing storable
##                         handle for `Any`/`DefaultType`/`RenderableType` —
##                         the `default`/`message` params carry `Any`/
##                         `RenderableType`, which round-trip through
##                         `RenderableValue`).
##
## `PromptError(Exception)` → `ref object of CatchableError` (Python
## `Exception` → Nim `CatchableError`; `ref` so it is raisable and its
## `message` field is reachable). `InvalidResponse(PromptError)` (prompt.py:15-
## 27) → `ref object of PromptError`; `__init__(message: TextType)` →
## `initInvalidResponse(message: TextType)` (the param keeps the `TextType`
## typeclass; the field stores a `Text` — a `str` message is wrapped via
## `Text(message)` in the Body, so `__rich__` returns a `Text`); `__rich__
## -> TextType` → `richCast*(self): Text` (returns `self.message`; `Text` is a
## `RenderableBase` so the `RichCast` concept holds).
##
## `PromptBase(Generic[PromptType])` (prompt.py:30-301) → `PromptBase*[T] =
## ref object of RootObj` (Nim generic; `RootObj` base — `PromptBase` has no
## rich base class). Public fields mirror the `__init__` assignments
## (prompt.py:62-76); the Python *class attributes* (`response_type`, the three
## message strings, `choices`) become overridable *fields* (so subclasses
## `IntPrompt`/`Confirm` can override them via their `init` procs). `response_type:
## type` (prompt.py:33, a callable converting a `str` to `PromptType`) →
## `responseType*: proc(x: string): T {.closure.}` — faithful to the usage
## `self.response_type(value)` (prompt.py:243). The `@overload`-decorated
## `ask`/`__call__` classmethods/methods collapse to their single runtime impl
## (prompt.py:112-149 / 280-301) — Nim has no `@overload`; the `default: Any =
## ...` (Ellipsis "no default" sentinel) → `Option[RenderableValue]` (`none` =
## no default). `__call__` → `call*` (Nim dunder mapping). The `stream:
## Optional[TextIO]` param → `Option[TextStream]`. The `default: DefaultType`
## param (where `DefaultType` is a distinct TypeVar) → `RenderableValue` (the
## non-narrowing `Any`/`RenderableType` handle).
##
## `Prompt(PromptBase[str])`/`IntPrompt(PromptBase[int])`/`FloatPrompt(
## PromptBase[float])`/`Confirm(PromptBase[bool])` (prompt.py:304-363) →
## `ref object of PromptBase[string/int/float/bool]` (Nim subclasses fixing
## `T`); `Confirm` overrides `render_default`/`process_response` and the
## `choices` default. Naming: `__init__`→`initPrompt`/`initIntPrompt`/
## `initFloatPrompt`/`initConfirm`; `render_default`→`renderDefault`;
## `make_prompt`→`makePrompt`; `get_input`→`getInput` (classmethod → a
## standalone proc taking `Console`); `check_choice`→`checkChoice`;
## `process_response`→`processResponse`; `on_validate_error`→`onValidateError`;
## `pre_prompt`→`prePrompt`; `__call__`→`call`; `__rich__`→`richCast`. Proc
## bodies are ports (`discard` ⇒ `default(T)`).

import std/options
import std/strutils # strip, toLowerAscii, parseInt, parseFloat (process_response,
                    # check_choice, Confirm.process_response).

import segment      # richbase (ConsoleHandle, ConsoleOptions, RenderResult,
                    # RenderableType, RenderableBase, …) + Style.
import console      # Console (prompt.py:6,62; real console type, post-).
import text except bool  # Text, TextType (prompt.py:7). `except bool`:
                    # `text.nim` exports a `bool*(Span): bool` proc
                    # (text.py:60-61 `Span.__bool__`) which shadows/ambiguates
                    # `system.bool` in every type position here (`PromptBase[bool]`,
                    # field/param/return `bool`). `prompt.nim` never calls the
                    # `text.bool` proc, so excluding it restores `bool`⇒`system.bool`
                    # unambiguously. (This module was a never-compiled Phase-0
                    # stub; the ambiguity only surfaces once it is imported.)
import api_types     # RenderableValue (the storable Any/RenderableType handle).

type
  TextStream* = ref object of RootObj
    ## [NON-NARROWING PROVISIONAL FORWARD HANDLE] for `typing.TextIO`
    ## (prompt.py:1, the optional `stream` param of `ask`/`__call__`/`get_input`).
    ## `TextIO` is a stdlib protocol with no Nim equivalent in scope; this
    ## `ref object of RootObj` placeholder lets the `stream: Optional[TextIO]`
    ## params declare their type now. Removed/replaced when a real IO handle
    ## lands (body). NOT a faithful port of `TextIO`.

  PromptError* = ref object of CatchableError
    ## rich prompt.py:11-12 — `class PromptError(Exception)`: base class for
    ## prompt-related errors. `ref object of CatchableError` (Python `Exception`
    ## → Nim `CatchableError`; `ref` so it is raisable and subtyped).

  InvalidResponse* = ref object of PromptError
    ## rich prompt.py:15-27 — `class InvalidResponse(PromptError)`: raised within
    ## `process_response` to indicate an invalid response, carrying the error
    ## `message` (prompt.py:23-24). A subtype of `PromptError` so
    ## `except InvalidResponse` (prompt.py:251) catches it. The `message` field
    ## stores a `Text` (a `str` message is wrapped in body); `__rich__`
    ## (prompt.py:26-27) returns it.
    message*: Text
      ## rich prompt.py:23-24 — `self.message = message` (`TextType = Union[str,
      ## Text]`; stored as `Text` — a `str` is wrapped via `Text(message)` in
      ## the body `initInvalidResponse` body; faithful to `__rich__` returning
      ## `self.message`).

  PromptBase*[T] = ref object of RootObj
    ## rich prompt.py:30-301 — `class PromptBase(Generic[PromptType])`: drives
    ## the ask/validate loop. `ref object of RootObj` (no rich base class).
    ## Public fields mirror `__init__` (prompt.py:62-76); the Python *class
    ## attributes* (`response_type`, `validate_error_message`,
    ## `illegal_choice_message`, `prompt_suffix`, `choices`) become overridable
    ## *fields* so subclasses (`IntPrompt`/`Confirm`) can override them.
    prompt*: Text
      ## rich prompt.py:63-65 — `self.prompt = Text.from_markup(prompt, style="prompt") if isinstance(prompt, str) else prompt` (`Text`; a `str` is wrapped in body).
    console*: Console
      ## rich prompt.py:62-62 — `self.console = console or get_console()` (`Console`; default `nil` ⇒ body uses `get_console()`).
    password*: bool
      ## rich prompt.py:66-66 — `self.password = password` (`bool`; default `False`).
    choices*: Option[seq[string]]
      ## rich prompt.py:67-68 — `self.choices = choices` if not None else the class attr `None` (`Optional[List[str]]`; `Option[seq[string]]`, default `none(seq[string])`; `Confirm` overrides to `@["y","n"]`).
    caseSensitive*: bool
      ## rich prompt.py:69-69 — `self.case_sensitive = case_sensitive` (`bool`; default `True`).
    showDefault*: bool
      ## rich prompt.py:70-70 — `self.show_default = show_default` (`bool`; default `True`).
    showChoices*: bool
      ## rich prompt.py:71-71 — `self.show_choices = show_choices` (`bool`; default `True`).
    responseType*: proc(x: string): T {.closure.}
      ## rich prompt.py:33-33 — `response_type: type = str` (class attr): a callable converting a `str` to `PromptType` — `self.response_type(value)` (prompt.py:243). Modelled as a closure proc `proc(x: string): T`; the per-subclass default (`str`/`int`/`float`/`bool` converter) is set in the body `init` body.
    validateErrorMessage*: string
      ## rich prompt.py:34-36 — `validate_error_message = "[prompt.invalid]Please enter a valid value"` (class attr; `IntPrompt`/`FloatPrompt`/`Confirm` override).
    illegalChoiceMessage*: string
      ## rich prompt.py:37-39 — `illegal_choice_message = "[prompt.invalid.choice]Please select one of the available options"` (class attr).
    promptSuffix*: string
      ## rich prompt.py:40-40 — `prompt_suffix = ": "` (class attr).

  Prompt* = ref object of PromptBase[string]
    ## rich prompt.py:304-313 — `class Prompt(PromptBase[str])`: a prompt
    ## returning a `str` (`response_type = str`, prompt.py:312).

  IntPrompt* = ref object of PromptBase[int]
    ## rich prompt.py:316-325 — `class IntPrompt(PromptBase[int])`: a prompt
    ## returning an `int` (`response_type = int`, prompt.py:324; overrides
    ## `validate_error_message`, prompt.py:325).

  FloatPrompt* = ref object of PromptBase[float]
    ## rich prompt.py:328-337 — `class FloatPrompt(PromptBase[float])`: a prompt
    ## returning a `float` (`response_type = float`, prompt.py:336; overrides
    ## `validate_error_message`, prompt.py:337).

  Confirm* = ref object of PromptBase[bool]
    ## rich prompt.py:340-363 — `class Confirm(PromptBase[bool])`: a yes/no
    ## confirmation prompt (`response_type = bool`, prompt.py:349; overrides
    ## `validate_error_message`, `choices = ["y","n"]`, `render_default` and
    ## `process_response`, prompt.py:350-363).

proc initInvalidResponse*(message: TextType): InvalidResponse =
  ## rich prompt.py:23-24 — `InvalidResponse.__init__(self, message: TextType)
  ## -> None`: `self.message = message` (prompt.py:24). The param keeps the
  ## `TextType` typeclass (`string or Text`); the field stores a `Text` — a
  ## `str` message is wrapped via `Text(message)` in the Body (so
  ## `richCast` returns a `Text`).
  new(result)
  when typeof(message) is Text:
    result.message = message
  else:
    # a `str` message is wrapped via `Text(message)` (prompt.py:24); `initText`
    # is a Phase-1 stub ⇒ `result.message` stays nil until Text lands.
    result.message = initText(message)

proc richCast*(self: InvalidResponse): Text =
  ## rich prompt.py:26-27 — `InvalidResponse.__rich__(self) -> TextType`:
  ## `return self.message` (prompt.py:27). Dunder mapping `__rich__`→`richCast`
  ## (the richbase `RichCast` bridge); returns `self.message` (a `Text`, a
  ## `RenderableBase` — satisfies `RichCast`).
  result = self.message

proc initPromptBase*[T](prompt: TextType = "", console: Console = nil,
                         password: bool = false,
                         choices: Option[seq[string]] = none(seq[string]),
                         caseSensitive: bool = true, showDefault: bool = true,
                         showChoices: bool = true): PromptBase[T] =
  ## rich prompt.py:54-76 — `PromptBase.__init__(self, prompt: TextType = "",
  ## *, console: Optional[Console] = None, password: bool = False, choices:
  ## Optional[List[str]] = None, case_sensitive: bool = True, show_default: bool
  ## = True, show_choices: bool = True) -> None`: build `self.prompt` (wrap a
  ## `str` via `Text.from_markup(prompt, style="prompt")`), set `console`
  ## (`console or get_console()`), `password`, `choices` (if not None),
  ## `case_sensitive`, `show_default`, `show_choices` (prompt.py:62-76).
  ## Keyword-only after `prompt` (Python `*`, prompt.py:55). `prompt:
  ## TextType = ""` → typeclass param (default `""`), stored as `Text`;
  ## `console: Optional[Console] = None` → `Console = nil`; `choices:
  ## Optional[List[str]] = None` → `Option[seq[string]]`.
  new(result)
  when typeof(prompt) is Text:
    result.prompt = prompt
  else:
    result.prompt = fromMarkup(Text, prompt, "prompt")  # Phase-1 stub → nil
  result.console = console  # `console or get_console()` (prompt.py:62):
                            # `get_console` is absent ⇒ `nil` until the
                            # umbrella helper lands.
  result.password = password
  result.choices = choices
  result.caseSensitive = caseSensitive
  result.showDefault = showDefault
  result.showChoices = showChoices
  result.validateErrorMessage = "[prompt.invalid]Please enter a valid value"
  result.illegalChoiceMessage = "[prompt.invalid.choice]Please select one of the available options"
  result.promptSuffix = ": "

proc ask*[T](prompt: TextType = "", console: Console = nil,
             password: bool = false,
             choices: Option[seq[string]] = none(seq[string]),
             caseSensitive: bool = true, showDefault: bool = true,
             showChoices: bool = true,
             default: Option[RenderableValue] = none(RenderableValue),
             stream: Option[TextStream] = none(TextStream)): RenderableValue =
  ## rich prompt.py:112-149 — `PromptBase.ask(cls, prompt: TextType = "", *,
  ## console=None, password=False, choices=None, case_sensitive=True,
  ## show_default=True, show_choices=True, default: Any = ..., stream=None) ->
  ## Any` (classmethod; the runtime impl of the 3 `@overload` variants,
  ## prompt.py:80-109): construct `cls(...)` and run `_prompt(default=default,
  ## stream=stream)` (prompt.py:147-148). `T` identifies the subclass
  ## (`Prompt`⇒`string`, `IntPrompt`⇒`int`, …); `default: Any = ...` (the
  ## Ellipsis "no default" sentinel) → `Option[RenderableValue]` (`none` = no
  ## default); `stream: Optional[TextIO]` → `Option[TextStream]`; returns
  ## `RenderableValue` (the non-narrowing `Any`/`RenderableType` handle). Phase
  ## 0 stub.
  when T is string:
    let p = initPrompt(prompt, console, password, choices, caseSensitive,
                       showDefault, showChoices)
    result = call[T](p, default, stream)
  elif T is int:
    let p = initIntPrompt(prompt, console, password, choices, caseSensitive,
                          showDefault, showChoices)
    result = call[T](p, default, stream)
  elif T is float:
    let p = initFloatPrompt(prompt, console, password, choices, caseSensitive,
                            showDefault, showChoices)
    result = call[T](p, default, stream)
  elif T is bool:
    let p = initConfirm(prompt, console, password, choices, caseSensitive,
                        showDefault, showChoices)
    result = call[T](p, default, stream)
  else:
    let p = initPromptBase[T](prompt, console, password, choices,
                              caseSensitive, showDefault, showChoices)
    result = call[T](p, default, stream)

proc renderDefault*[T](self: PromptBase[T], default: RenderableValue): Text =
  ## rich prompt.py:151-160 — `PromptBase.render_default(self, default:
  ## DefaultType) -> Text`: `Text(f"({default})", "prompt.default")`
  ## (prompt.py:159). `default: DefaultType` → `RenderableValue` (the
  ## non-narrowing handle). Returns `Text`.
  # Python: Text(f"({default})", "prompt.default") (prompt.py:159).
  # `default: RenderableValue` carries the value as a tagged union; only the
  # `rvString` arm has a plain textual form (the `RenderableBase` arms would
  # require rendering, deferred). `initText` is a Phase-1 stub ⇒ `nil`.
  if default.kind == rvString:
    result = initText("(" & default.textStr & ")", "prompt.default")
  else:
    result = initText("(...)", "prompt.default")

proc makePrompt*[T](self: PromptBase[T], default: RenderableValue): Text =
  ## rich prompt.py:162-191 — `PromptBase.make_prompt(self, default:
  ## DefaultType) -> Text`: copy `self.prompt`, append choices (if shown),
  ## the default (if shown and not `...`), and `self.prompt_suffix`
  ## (prompt.py:172-190). `default: DefaultType` → `RenderableValue`. Returns
  ## `Text`.
  let prompt = self.prompt.copy()  # Text.copy is implemented (text.nim:1254) —
                                    # always non-nil; `isNil` (built-in ref
                                    # check) avoids instantiating the generic
                                    # `Text.==` (which accesses `spansData`
                                    # across module boundaries) that a bare
                                    # `!= nil` would trigger.
  if not prompt.isNil:
    prompt.`end` = ""
    if self.showChoices and self.choices.isSome:
      let cs = self.choices.get
      if cs.len > 0:
        var choicesStr = "["
        for i, c in cs:
          if i > 0: choicesStr.add("/")
          choicesStr.add(c)
        choicesStr.add("]")
        discard prompt.append(" ")
        discard prompt.append(choicesStr, "prompt.choices")
    # `default != ... and self.show_default and isinstance(default, (str,
    # self.response_type))` (prompt.py:178-181): the frozen `default:
    # RenderableValue` (no Ellipsis sentinel) makes "a default was supplied"
    # best-effort (non-empty `rvString` arm); the `isinstance` check cannot be
    # done on the opaque handle, so the default is rendered whenever
    # `showDefault` and the handle is not the empty-`rvString` sentinel.
    if self.showDefault and not (default.kind == rvString and default.textStr == ""):
      discard prompt.append(" ")
      let defText = self.renderDefault(default)
      discard prompt.append(defText)
    discard prompt.append(self.promptSuffix)
  result = prompt

proc getInput*(console: Console, prompt: TextType, password: bool,
               stream: Option[TextStream] = none(TextStream)): string =
  ## rich prompt.py:194-211 — `PromptBase.get_input(cls, console: Console,
  ## prompt: TextType, password: bool, stream: Optional[TextIO] = None) -> str`
  ## (classmethod): `console.input(prompt, password=password, stream=stream)`
  ## (prompt.py:210). A standalone proc taking `Console` (the classmethod `cls`
  ## is unused). `prompt: TextType` keeps the typeclass; `stream:
  ## Optional[TextIO]` → `Option[TextStream]`. Body needs
  ## `Console.input`.
  # Python: console.input(prompt, password=password, stream=stream)
  # (prompt.py:210). `Console.input` is a Phase-0 stub (`discard` ⇒ "");
  # `stream: Option[TextStream]` is a provisional handle with no `FileHandle`
  # converter, so it is omitted (uses `input`'s default `none(FileHandle)`).
  # Returns "" until Console.input lands.
  result = console.input(prompt, password = password)

proc checkChoice*[T](self: PromptBase[T], value: string): bool =
  ## rich prompt.py:213-225 — `PromptBase.check_choice(self, value: str) ->
  ## bool`: `value.strip() in self.choices` (case-sensitive) or the
  ## lower-cased membership test (prompt.py:221-225).
  assert self.choices.isSome  # Python: assert self.choices is not None
  let cs = self.choices.get
  let stripped = value.strip()
  result = false
  if self.caseSensitive:
    for c in cs:
      if c == stripped:
        result = true
        break
  else:
    let lowered = stripped.toLowerAscii()
    for c in cs:
      if c.toLowerAscii() == lowered:
        result = true
        break

proc processResponse*[T](self: PromptBase[T], value: string): T =
  ## rich prompt.py:227-256 — `PromptBase.process_response(self, value: str) ->
  ## PromptType`: strip `value`, convert via `self.response_type(value)`
  ## (raising `InvalidResponse` on `ValueError`), validate against `choices`
  ## if set (prompt.py:236-254). Returns `T` (the faithful `PromptType`).
  ## Body needs `responseType` + `checkChoice`.
  ## (`discard` ⇒ `default(T)`).
  let stripped = value.strip()
  try:
    result = self.responseType(stripped)
  except ValueError:
    raise initInvalidResponse(self.validateErrorMessage)
  if self.choices.isSome:
    if not self.checkChoice(stripped):
      raise initInvalidResponse(self.illegalChoiceMessage)
    if not self.caseSensitive:
      # return the original choice, not the lower-cased version (prompt.py:253)
      let cs = self.choices.get
      let lowered = stripped.toLowerAscii()
      var idx = -1
      for i, c in cs:
        if c.toLowerAscii() == lowered:
          idx = i
          break
      if idx >= 0:
        result = self.responseType(cs[idx])

proc onValidateError*[T](self: PromptBase[T], value: string,
                         error: InvalidResponse) =
  ## rich prompt.py:258-265 — `PromptBase.on_validate_error(self, value: str,
  ## error: InvalidResponse) -> None`: `self.console.print(error, markup=True)`
  ## (prompt.py:264). `error: InvalidResponse` (a `ref`). Body needs
  ## `Console.print`.
  # Python: self.console.print(error, markup=True) (prompt.py:264). `error`
  # rich-casts to a `Text` (a `RenderableBase`) via `richCast`, then converts
  # to `RenderableValue` for `Console.print` (a Phase-0 stub). `value` is
  # unused in Python too.
  self.console.print(@[toRenderableValue(richCast(error))], markup = some(true))

proc prePrompt*[T](self: PromptBase[T]) =
  ## rich prompt.py:267-268 — `PromptBase.pre_prompt(self) -> None`: a hook to
  ## display something before the prompt (empty by default).
  # Python `pre_prompt` is an empty hook (prompt.py:267-268); no-op.
  discard

proc call*[T](self: PromptBase[T],
              default: Option[RenderableValue] = none(RenderableValue),
              stream: Option[TextStream] = none(TextStream)): RenderableValue =
  ## rich prompt.py:280-301 — `PromptBase.__call__(self, *, default: Any = ...,
  ## stream: Optional[TextIO] = None) -> Any` (the runtime impl of the 3
  ## `@overload` variants, prompt.py:271-278): the prompt loop — `pre_prompt`,
  ## `make_prompt`, `get_input`, return `default` on empty input, else
  ## `process_response` (retrying on `InvalidResponse`) (prompt.py:285-301).
  ## Dunder mapping `__call__`→`call`; `default: Any = ...` →
  ## `Option[RenderableValue]` (`none` = no default); `stream` →
  ## `Option[TextStream]`; returns `RenderableValue`.
  while true:
    self.prePrompt()
    var defVal = RenderableValue(kind: rvString, textStr: "")
    if default.isSome:
      defVal = default.get
    let promptText = self.makePrompt(defVal)
    let value = getInput(self.console, promptText, self.password, stream)
    if value == "" and default.isSome:
      return default.get
    try:
      let returnValue = self.processResponse(value)
      when T is string:
        # `string` has a `toRenderableValue` converter (api_types) ⇒ the
        # processed value round-trips into the `RenderableValue` return.
        result = returnValue
        return
      else:
        # DEFERRED: only `string` (and `RenderableBase`) have a
        # `toRenderableValue` converter; `int`/`float`/`bool` cannot be stored
        # in a `RenderableValue` until a per-type converter lands. The value is
        # computed (`returnValue`) but cannot be returned as a
        # `RenderableValue`; return the default-init handle.
        discard returnValue
        return
    except InvalidResponse as error:
      self.onValidateError(value, error)
      # Python: `continue` (prompt.py:299) — re-prompt.

proc initPrompt*(prompt: TextType = "", console: Console = nil,
                 password: bool = false,
                 choices: Option[seq[string]] = none(seq[string]),
                 caseSensitive: bool = true, showDefault: bool = true,
                 showChoices: bool = true): Prompt =
  ## rich prompt.py:304-313 — `Prompt(PromptBase[str])` construction: same
  ## params as `PromptBase.__init__` with `T = string`; sets `response_type =
  ## str` (prompt.py:312).
  let base = initPromptBase[string](prompt, console, password, choices, caseSensitive, showDefault, showChoices)
  new(result)
  result.prompt = base.prompt
  result.console = base.console
  result.password = base.password
  result.choices = base.choices
  result.caseSensitive = base.caseSensitive
  result.showDefault = base.showDefault
  result.showChoices = base.showChoices
  result.validateErrorMessage = base.validateErrorMessage
  result.illegalChoiceMessage = base.illegalChoiceMessage
  result.promptSuffix = base.promptSuffix
  result.responseType = proc(x: string): string = x

proc initIntPrompt*(prompt: TextType = "", console: Console = nil,
                    password: bool = false,
                    choices: Option[seq[string]] = none(seq[string]),
                    caseSensitive: bool = true, showDefault: bool = true,
                    showChoices: bool = true): IntPrompt =
  ## rich prompt.py:316-325 — `IntPrompt(PromptBase[int])` construction: sets
  ## `response_type = int` and `validate_error_message =
  ## "[prompt.invalid]Please enter a valid integer number"` (prompt.py:324-325).
  let base = initPromptBase[int](prompt, console, password, choices, caseSensitive, showDefault, showChoices)
  new(result)
  result.prompt = base.prompt
  result.console = base.console
  result.password = base.password
  result.choices = base.choices
  result.caseSensitive = base.caseSensitive
  result.showDefault = base.showDefault
  result.showChoices = base.showChoices
  result.validateErrorMessage = "[prompt.invalid]Please enter a valid integer number"
  result.illegalChoiceMessage = base.illegalChoiceMessage
  result.promptSuffix = base.promptSuffix
  result.responseType = proc(x: string): int = parseInt(x)

proc initFloatPrompt*(prompt: TextType = "", console: Console = nil,
                      password: bool = false,
                      choices: Option[seq[string]] = none(seq[string]),
                      caseSensitive: bool = true, showDefault: bool = true,
                      showChoices: bool = true): FloatPrompt =
  ## rich prompt.py:328-337 — `FloatPrompt(PromptBase[float])` construction:
  ## sets `response_type = float` and `validate_error_message =
  ## "[prompt.invalid]Please enter a number"` (prompt.py:336-337). port
  ## stub.
  let base = initPromptBase[float](prompt, console, password, choices, caseSensitive, showDefault, showChoices)
  new(result)
  result.prompt = base.prompt
  result.console = base.console
  result.password = base.password
  result.choices = base.choices
  result.caseSensitive = base.caseSensitive
  result.showDefault = base.showDefault
  result.showChoices = base.showChoices
  result.validateErrorMessage = "[prompt.invalid]Please enter a number"
  result.illegalChoiceMessage = base.illegalChoiceMessage
  result.promptSuffix = base.promptSuffix
  result.responseType = proc(x: string): float = parseFloat(x)

proc initConfirm*(prompt: TextType = "", console: Console = nil,
                  password: bool = false,
                  choices: Option[seq[string]] = none(seq[string]),
                  caseSensitive: bool = true, showDefault: bool = true,
                  showChoices: bool = true): Confirm =
  ## rich prompt.py:340-363 — `Confirm(PromptBase[bool])` construction: sets
  ## `response_type = bool`, `validate_error_message = "[prompt.invalid]Please
  ## enter Y or N"` and `choices = ["y","n"]` (prompt.py:349-351). port
  ## stub.
  let base = initPromptBase[bool](prompt, console, password, choices, caseSensitive, showDefault, showChoices)
  new(result)
  result.prompt = base.prompt
  result.console = base.console
  result.password = base.password
  # `Confirm` overrides the `choices` class attr to `["y","n"]` (prompt.py:351)
  # when not supplied.
  result.choices = if choices.isSome: choices else: some(@["y", "n"])
  result.caseSensitive = base.caseSensitive
  result.showDefault = base.showDefault
  result.showChoices = base.showChoices
  result.validateErrorMessage = "[prompt.invalid]Please enter Y or N"
  result.illegalChoiceMessage = base.illegalChoiceMessage
  result.promptSuffix = base.promptSuffix
  result.responseType = proc(x: string): bool = (x != "")

proc renderDefault*(self: Confirm, default: RenderableValue): Text =
  ## rich prompt.py:353-356 — `Confirm.render_default(self, default:
  ## DefaultType) -> Text`: render the default as `(y)` or `(n)` rather than
  ## `True/False` — `Text(f"({yes})" if default else f"({no})", style="prompt.default")`
  ## (prompt.py:355). Overrides `PromptBase[bool].renderDefault`. port
  ## stub.
  # Python: yes,no = self.choices; Text(f"({yes})" if default else f"({no})",
  # style="prompt.default") (prompt.py:355). `default` is a `bool` in Python,
  # which has no `RenderableValue` arm (no bool→RenderableValue converter), so
  # the truthiness test is best-effort via the `rvString` arm (parsing
  # "true"/"y"/"1" as truthy). `initText` is a Phase-1 stub ⇒ `nil`.
  let cs = self.choices.get
  let yes = if cs.len > 0: cs[0] else: "y"
  let no = if cs.len > 1: cs[1] else: "n"
  var truthy = false
  if default.kind == rvString:
    let s = default.textStr.toLowerAscii()
    truthy = (s == "true" or s == "y" or s == "1")
  result = initText("(" & (if truthy: yes else: no) & ")", "prompt.default")

proc processResponse*(self: Confirm, value: string): bool =
  ## rich prompt.py:358-363 — `Confirm.process_response(self, value: str) ->
  ## bool`: strip/lower `value`, raise `InvalidResponse` if not in `choices`,
  ## return `value == self.choices[0]` (prompt.py:361-362). Overrides
  ## `PromptBase[bool].processResponse`.
  let stripped = value.strip().toLowerAscii()
  let cs = self.choices.get
  var found = false
  for c in cs:
    if c == stripped:
      found = true
      break
  if not found:
    raise initInvalidResponse(self.validateErrorMessage)
  result = (stripped == (if cs.len > 0: cs[0] else: ""))
