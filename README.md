# nim-rich

A Nim port of Python [`rich`](https://github.com/Textualize/rich) **15.0.0** — a
terminal rendering library: renderables, tables, panels, trees, progress bars,
columns, alignment, syntax highlighting, JSON, tracebacks, prompts, and more.

The port targets **byte-for-byte identical** terminal output with Python rich
15.0.0 for every covered feature. Equivalence is verified by a golden-comparison
harness that runs the real CPython `rich` package and the Nim port side by side
and compares raw ANSI bytes with **no normalization**.

## Status

- **270/270 golden cases byte-exact** vs Python rich 15.0.0 (raw ANSI bytes,
  `NO_COLOR` neutralized, `force_terminal` + deterministic terminfo).
- **62 modules** porting Python rich 15.0.0 (~33k lines of Nim).
- **~6× faster** than Python rich (geomean 5.7×, min 1.1×, max 394× — see
  `BENCHMARK.md`).

## Covered renderables

| Renderable                 | Status        | Golden cases |
|----------------------------|---------------|--------------|
| Text/Spans/Markup           | byte-exact    | 30+          |
| Table (grid)               | byte-exact    | 15+          |
| Panel                      | byte-exact    | 8            |
| Tree                       | byte-exact    | 12           |
| Markdown                  | byte-exact    | 14           |
| Bar                        | byte-exact    | 10           |
| Align                      | byte-exact    | 13           |
| Columns                    | byte-exact    | 12           |
| Box                        | byte-exact    | 8            |
| Syntax                     | byte-exact    | 7            |
| Spinner                    | byte-exact    | 6            |
| Pretty                     | byte-exact    | 12           |
| Progress                   | byte-exact    | 8            |
| JSON                       | byte-exact    | 13           |
| Traceback                  | byte-exact    | 7            |
| Prompt                     | byte-exact    | 6            |
| Rule                       | byte-exact    | 8            |
| Control                    | byte-exact    | 10           |
| Emoji                      | byte-exact    | 6            |
| Filesize                   | byte-exact    | 7            |
| Live/Group/Layout/Constrain | byte-exact    | 15+          |

## Demo

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./demo demo.nim
./demo
```

The demo prints a colorized showcase (colors, styles, justification, markup,
tables, syntax highlighting, markdown, panels) to the terminal — a port of
`python -m rich`.

## Benchmarks

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./bench_full bench_full.nim
./bench_full > /tmp/nim.txt
python3 bench_python.py > /tmp/py.txt
python3 bench_compare.py /tmp/nim.txt /tmp/py.txt
```

**Results** (1000 iter, warm, in-process, ORC — Nim default): **geomean 5.7×
speedup (min 1.1×, max 394×)**. See `BENCHMARK.md` for the full table.

## Build & test

```bash
# Golden tests (requires nimgments as a sibling at ../nimgments for Syntax
# highlighting, and Python `rich` 15.0.0 installed as the oracle)
nim c -d:release --path:src --path:../nimgments/src -o:./golden_nim golden_nim.nim
python3 golden/golden_compare.py all ./golden_nim   # → 270/270 PASS
```

The golden gate runs the real CPython `rich` 15.0.0 as the reference oracle and
compares raw ANSI bytes. `golden/golden_compare.py` auto-detects the oracle
Python at `../../golden-venv/bin/python` (set `GOLDEN_PY` to override). The
`golden-venv` is a local virtualenv with `pip install rich==15.0.0` — it is not
part of the repo.

ORC is the Nim memory manager default since 2.0 — no `--mm:` flag is needed. Both
ORC and ARC pass the full 270/270 golden gate; ORC is ~20% faster than ARC and is
used for all benchmarks and the demo.
