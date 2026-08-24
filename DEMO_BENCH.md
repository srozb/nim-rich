# nim-rich — Demo & Benchmarks

## Demo

The demo is a port of `python -m rich` — a colorized showcase printed to the
terminal: colors (4-bit/8-bit/truecolor), styles (bold/dim/italic/underline/
strike/reverse/blink), text justification (left/center/right/full), markup
(bbcode + emoji), tables, syntax highlighting, markdown, and panels.

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./demo demo.nim
./demo
```

To compare against the Python original side by side:

```bash
python -m rich > /tmp/demo_py.txt
./demo > /tmp/demo_nim.txt
diff /tmp/demo_py.txt /tmp/demo_nim.txt
```

The demo auto-detects the terminal width (from `COLUMNS` or the TTY), matching
Python rich's behavior.

## Benchmarks

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./bench_full bench_full.nim
./bench_full > /tmp/nim.txt
python3 bench_python.py > /tmp/py.txt
python3 bench_compare.py /tmp/nim.txt /tmp/py.txt
```

### Results (1000 iterations, warm, in-process, ORC, median of 5 runs)

| Renderable                | Nim (ms) | Python (ms) | Speedup  |
|---------------------------|----------|-------------|----------|
| Text (plain, 100 chars)   | 0.0003   | 0.1183      | **394×** |
| Text (styled, single)      | 0.0021   | 0.1015      | **48×**  |
| Table (3 cols, 4 rows)     | 0.52     | 1.76        | **3.4×** |
| Panel (simple)             | 0.11     | 0.15        | **1.3×** |
| Panel (styled, title)      | 0.10     | 0.26        | **2.5×** |
| Tree (3 levels, 5 nodes)   | 0.051    | 0.46        | **9.0×** |
| Rule (80 chars)            | 0.094    | 0.15        | **1.6×** |
| Markdown (20 lines)        | 0.19     | 1.39        | **7.2×** |
| JSON (nested, 10 keys)      | 0.27     | 0.76        | **2.8×** |
| Bar (50%)                  | 0.048    | 0.051       | **1.1×** |
| Align (center, width 80)   | 0.054    | 0.18        | **3.4×** |
| **GEOMEAN**                |          |             | **5.7×** |

### Notes on the speedup

- **Text (394×)**: Nim renders plain text in ~0.3µs — essentially zero-cost
  (object + string copy). Python pays for Console construction + IO + style
  parsing on every call.
- **Tree (9×)**, **Markdown (7×)**: complex renderables where Nim benefits from
  no GC overhead and direct segment manipulation.
- **Table (3.4×)**: the most complex renderable (column measurement, padding,
  box drawing) — Nim is still over 3× faster.
- **Bar (1.1×)**, **Rule (1.6×)**: simple renderables where both implementations
  sit close to the measurement overhead, so the speedup is minimal.

### Methodology

- 1000 iterations per benchmark, 10 warmup iterations
- In-process (Nim) vs in-process (Python) — fair comparison, no subprocess
  overhead
- Warm cache — measures pure rendering, not construction
- `force_terminal=True`, `width=80`, `truecolor` — deterministic output
- Python: `process_time()` (CPU), Nim: `cpuTime()` (CPU)

## Build

```bash
nim c -d:release --path:src --path:../nimgments/src -o:./demo demo.nim
nim c -d:release --path:src --path:../nimgments/src -o:./bench_full bench_full.nim
```
