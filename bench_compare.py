#!/usr/bin/env python3
"""bench_compare.py — porównuje wyniki bench_full (Nim) i bench_python (Python)

Uruchom:
  ./bench_full > /tmp/nim.txt
  python3 bench_python.py > /tmp/py.txt
  python3 bench_compare.py /tmp/nim.txt /tmp/py.txt
"""
import re
import sys

def parse(path):
    results = {}
    with open(path) as f:
        for line in f:
            # 42s} 0.0001 ms/render
            m = re.match(r'^\s+(.+?)\s+(\d+\.\d+)\s+ms/render', line)
            if m:
                results[m.group(1).strip()] = float(m.group(2))
    return results

def main():
    if len(sys.argv) < 3:
        print("Usage: bench_compare.py <nim.txt> <python.txt>")
        sys.exit(1)
    nim = parse(sys.argv[1])
    py = parse(sys.argv[2])

    print("=" * 78)
    print(" BENCHMARK PORÓWNANIE — nim-rich vs Python rich 15.0.0")
    print("=" * 78)
    print(f"{'Renderable':44s} {'Nim (ms)':>10s} {'Python (ms)':>12s} {'Speedup':>10s}")
    print("-" * 78)

    labels = [
        "Text (plain, 100 chars)",
        "Text (styled, single)",
        "Table (3 cols, 4 rows)",
        "Panel (simple)",
        "Panel (styled, title)",
        "Tree (3 levels, 5 nodes)",
        "Rule (80 chars)",
        "Markdown (20 lines)",
        "JSON (nested, 10 keys)",
        "Bar (50%)",
        "Align (center, width 80)",
    ]

    speedups = []
    for label in labels:
        n = nim.get(label)
        p = py.get(label)
        if n is None or p is None:
            print(f"  {label:42s}  {'?':>10s} {'?':>12s} {'?':>10s}")
            continue
        speedup = p / n if n > 0 else float('inf')
        speedups.append(speedup)
        print(f"  {label:42s}  {n:10.4f} {p:12.4f} {speedup:8.1f}×")

    print("-" * 78)
    if speedups:
        avg = sum(speedups) / len(speedups)
        mn = min(speedups)
        mx = max(speedups)
        print(f"  {'ŚREDNIO':42s}  {'':>10s} {'':>12s} {avg:8.1f}×")
        print(f"  {'MIN':42s}  {'':>10s} {'':>12s} {mn:8.1f}×")
        print(f"  {'MAX':42s}  {'':>10s} {'':>12s} {mx:8.1f}×")
    print("=" * 78)

if __name__ == "__main__":
    main()
