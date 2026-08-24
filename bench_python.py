#!/usr/bin/env python3
"""bench_python.py — Python rich 15.0.0 benchmark (mirror of bench_full.nim)

Mierzy rendering tych samych renderables co Nim benchmark, 1000 iter, warm.
"""
import io
import time
import platform
from rich.console import Console
from rich.text import Text
from rich.table import Table
from rich.panel import Panel
from rich.tree import Tree
from rich.rule import Rule
from rich.markdown import Markdown
from rich.json import JSON
from rich.progress_bar import ProgressBar
from rich.align import Align

ITER = 1000


def make_console():
    return Console(file=io.StringIO(), force_terminal=True, width=80,
                   color_system="truecolor", legacy_windows=False,
                   soft_wrap=False)


def bench(label, body):
    # warmup
    for _ in range(10):
        body()
    t0 = time.process_time()
    for _ in range(ITER):
        body()
    elapsed = (time.process_time() - t0) * 1000.0 / ITER
    print(f"  {label:42s} {elapsed:8.4f} ms/render")


def main():
    print("================================================================")
    print(" nim-rich vs Python rich 15.0.0 — BENCHMARK")
    print("================================================================")
    print(f"Iterations per benchmark: {ITER}")
    print(f"Python version: {platform.python_version()}")
    import importlib.metadata as md
    print(f"rich version: {md.version('rich')}")
    print()

    txt_plain = Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque in metus sed sapien ultricies pretium a at justo.")
    txt_styled = Text("Hello bold red on blue", style="bold red on blue")

    print("--- PYTHON (in-process, warm) ---")

    bench("Text (plain, 100 chars)", lambda: make_console().print(txt_plain))
    bench("Text (styled, single)", lambda: make_console().print(txt_styled))

    def table_bench():
        c = make_console()
        t = Table()
        t.add_column("Date", style="green")
        t.add_column("Title", style="blue")
        t.add_column("Budget", style="cyan")
        t.add_row("Dec 20, 2019", "Star Wars: Rise of Skywalker", "$275,000,000")
        t.add_row("May 25, 2018", "Solo: A Star Wars Story", "$275,000,000")
        t.add_row("Dec 15, 2017", "Star Wars: Last Jedi", "$262,000,000")
        t.add_row("May 19, 1999", "Star Wars Ep I: Phantom Menace", "$115,000,000")
        c.print(t)
    bench("Table (3 cols, 4 rows)", table_bench)

    bench("Panel (simple)", lambda: make_console().print(Panel("Panel content", border_style="green")))
    bench("Panel (styled, title)", lambda: make_console().print(Panel("Styled panel", border_style="cyan", title="My Panel")))

    def tree_bench():
        c = make_console()
        root = Tree("Root")
        child1 = root.add("Child 1")
        child1.add("Grandchild 1")
        child1.add("Grandchild 2")
        root.add("Child 2")
        root.add("Child 3")
        c.print(root)
    bench("Tree (3 levels, 5 nodes)", tree_bench)

    bench("Rule (80 chars)", lambda: make_console().print(Rule()))
    bench("Markdown (20 lines)", lambda: make_console().print(Markdown("# Heading\n\n- item1\n- item2\n\n*italic* **bold** `code`\n\n> quote\n\n1. first\n2. second\n")))
    bench("JSON (nested, 10 keys)", lambda: make_console().print(JSON('{"name":"test","items":[1,2,3],"nested":{"a":true,"b":null,"c":[1.5,2.5]}}')))
    bench("Bar (50%)", lambda: make_console().print(ProgressBar(total=100, completed=50)))
    bench("Align (center, width 80)", lambda: make_console().print(Align("centered", "center", width=80)))


if __name__ == "__main__":
    main()
