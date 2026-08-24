## Port of `rich.diagnose` (rich/diagnose.py, 39 lines).
##
## `diagnose` is a 39-line debugging module exposing a single `report()`
## function (diagnose.py:10-35) that prints a terminal/environment diagnostic:
## it `inspect`s the global `Console` and the Windows console features, then
## prints a `Panel.fit(Pretty(env), title=…)` of relevant environment
## variables and the platform string (diagnose.py:13-35).
##
## Import graph (rich/diagnose.py:1-7): runtime sibling imports are
## `from rich import inspect` (diagnose.py:4), `from rich.console import
## Console, get_windows_console_features` (diagnose.py:5), `from rich.panel
## import Panel` (diagnose.py:6), `from rich.pretty import Pretty`
## (diagnose.py:7). `import os` (diagnose.py:1) and `import platform`
## (diagnose.py:2) are Python stdlib — `os.getenv` (diagnose.py:24) and
## `platform.system` (diagnose.py:35) are BODY-only deps; not imported at
## (no signature references them — `report()` takes no args and returns
## `None`).
##
## wiring (this file):
##   `import console` — `Console` (diagnose.py:13, `Console()`) +
##                         `getWindowsConsoleFeatures` (diagnose.py:14). Both
##                         are runtime-imported in rich; `console.nim` exports
##                         `Console*` and `getWindowsConsoleFeatures*`.
##   `import panel`    — `Panel` (diagnose.py:23, `Panel.fit(...)`). Imported
##                         for graph faithfulness; `Panel.fit` is a BODY-only
##                         dep (a classmethod, panel.py) used only inside
##                         `report()`'s body, which is `discard`  —
##                         so this emits the documented Phase-0 unused-import
##                         warning, exactly as `file_proxy.nim`'s `import text`
##                         does for its body dep.
##   `import pretty`   — `Pretty` (diagnose.py:23, `Pretty(env)`). Same
##                         body-dep rule as `panel` — graph faithfulness, accepts
##                         the unused-import warning.
##
## `inspect` (diagnose.py:4 `from rich import inspect`) and `get_console`
## (rich.__init__) are NOT imported : `inspect` is a top-level
## helper of `rich.__init__` (the umbrella mirrors `rich.__init__`'s public
## API — `get_console`/`inspect`/`print`/`print_json`/`reconfigure` — per
## the umbrella docstring), and there is no sibling `__init__` module to
## import; the `inspect(console)` / `inspect(features)` calls
## (diagnose.py:13-14) are BODY-only. They are deferred to body (when the
## umbrella/`__init__`-mirror `inspect` proc exists). `report()`'s body is
## `discard`, so no `inspect`/`os`/`platform` symbol is referenced .
##
## `report()` (diagnose.py:10-35) is a module-level function (not a method)
## returning `None` → `proc report*()` (no args). Proc body is a stub
## (`discard`).

import console              # Console (diagnose.py:13), getWindowsConsoleFeatures
                            # (diagnose.py:14). [runtime in rich.]
import panel                # Panel (diagnose.py:23, `Panel.fit(...)`); body dep
                            # — graph faithfulness, accepts the Phase-0 unused
                            # warning (as file_proxy.nim's `import text` does).
import pretty               # Pretty (diagnose.py:23, `Pretty(env)`); body dep —
                            # graph faithfulness, accepts the unused warning.

proc report*() =
  ## rich diagnose.py:10-35 — `def report() -> None`: print a terminal/env
  ## diagnostic — `inspect(Console())`, `inspect(get_windows_console_features())`,
  ## then `console.print(Panel.fit(Pretty(env), title="[b]Environment Variables"))`
  ## (diagnose.py:13-34) and `console.print(f'platform="{platform.system()}"')`
  ## (diagnose.py:35). `# pragma: no cover` (diagnose.py:10). Body needs
  ## the umbrella/`__init__`-mirror `inspect` proc, `Console()`, `Panel.fit`,
  ## `Pretty`, `os.getenv`, `platform.system`.
  # DEFERRED(umbrella/console/pretty/os/platform, later batch): the faithful
  # `report` (diagnose.py:10-35) calls `inspect(Console())`/
  # `inspect(getWindowsConsoleFeatures())` (the umbrella `inspect` helper — not
  # ported), then `Console().print(Panel.fit(Pretty(env), title=…))` and
  # `console.print(f'platform="{platform.system()}"')`. Blockers — the
  # umbrella `inspect` proc, `os.environ` (no direct Nim dict),
  # `platform.system` (no Nim equivalent), plus the `Pretty`/`Console.print`/
  # `Panel.fit` plumbing. No-op until the umbrella mirror + `os`/`platform` deps
  # land.
  discard
