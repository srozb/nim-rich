# nim-rich — Benchmark vs Python rich 15.0.0

## Golden parity — 270 / 270 byte-exact

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./golden_nim golden_nim.nim
python3 golden/golden_compare.py all ./golden_nim
# → 270/270 PASS (raw ANSI bytes, no normalization)
```

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./golden_nim golden_nim.nim
```

## Benchmark — ORC vs ARC vs Python (11 renderables, 1000 iters, warm)

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./bench_orc bench_full.nim
nim c --mm:arc -d:release --path:src --path:../nimgments/src -o:./bench_arc bench_full.nim
/home/slawek/src/rich-rewrite-nim/golden-venv/bin/python bench_python.py
```

Medians of 5 runs (ms/render, lower is better):

| Renderable                  |   ORC |   ARC | Python | ORC/ARC | ORC/Py |
|-----------------------------|------:|------:|-------:|--------:|-------:|
| Text (plain, 100 chars)     | 0.0003| 0.0004| 0.1183 |  0.75×  |  394×  |
| Text (styled, single)       | 0.0021| 0.0025| 0.1015 |  0.84×  |   48×  |
| Table (3 cols, 4 rows)      | 0.52  | 0.67  | 1.76   |  0.78×  |   3.4× |
| Panel (simple)              | 0.11  | 0.08  | 0.15   |  1.35×  |   1.3× |
| Panel (styled, title)       | 0.10  | 0.09  | 0.26   |  1.15×  |   2.5× |
| Tree (3 levels, 5 nodes)    | 0.051 | 0.080 | 0.46   |  0.64×  |   9.0× |
| Rule (80 chars)             | 0.094 | 0.150 | 0.15   |  0.62×  |   1.6× |
| Markdown (20 lines)         | 0.19  | 0.25  | 1.39   |  0.77×  |   7.2× |
| JSON (nested, 10 keys)      | 0.27  | 0.39  | 0.76   |  0.69×  |   2.8× |
| Bar (50%)                   | 0.048 | 0.068 | 0.051  |  0.72×  |   1.1× |
| Align (center, width 80)    | 0.054 | 0.081 | 0.18   |  0.67×  |   3.4× |
| **geomean**                 |       |       |        | **0.79×**| **5.7×** |

### Takeaways

- **ORC vs ARC**: ORC is ~20% faster on average (geomean 0.79×). For nim-rich's
  short-lived renderables (allocate, render, discard), ORC's cycle collector
  has no measurable overhead and the slightly different codegen edges out ARC.
  Use ORC (the Nim default) — no reason to pin `--mm:arc`.
- **ORC vs Python**: geomean **5.7× faster** (min 1.1× for Bar, max 394× for
  plain Text). The smallest speedups are on renderables that are already near
  the floor of per-render work (Bar, Panel) — there Python's overhead is a
  smaller fraction of the total.

## Methodology

- 11 renderables × 1000 iterations, warm (in-process loop, no startup), `cpuTime()`.
- 5 runs each, median reported (high run-to-run variance from background load).
- Same Console config (truecolor, width per-case, height=24, force_terminal) in
  Nim and Python.
- Python: CPython 3.12.13, rich 15.0.0.
- Nim: 2.2.10, `-d:release`.
- All 270 golden cases byte-exact verified in both ORC and ARC builds.
