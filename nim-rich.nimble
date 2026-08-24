# Package manifest for nim-rich — a Nim port of Python rich (15.0.0).
# See PORT.md / AUDIT_BRIEF.md for scope and parity matrix.
# Format: NimScript (Nimble v2).

version       = "0.4.0"
author        = "srozb"
description   = "Nim port of Python rich 15.0.0 (terminal rich text, tables, trees, syntax highlighting)"
license       = "MIT"
srcDir        = "src"

# nim-rich depends on nimgments (Pygments-compatible lexer toolkit) for
# Syntax highlighting. Path dependency during development — published as a
# proper Nimble dependency once nimgments is published.
requires "nim >= 2.2.0"
requires "nimgments >= 0.1.0"

# nimgments lives at ../nimgments (sibling of this repo under ~/src/rich-rewrite-nim/).
# Nimble resolves path deps via the package directory; this lets `nimble build`
# find it. For a clean checkout, nimgments must be installed (`nimble install`)
# or the path set via NIMBLE_PATH.
before build:
  switch("path", expandFilename("../nimgments/src"))

task golden, "Run golden parity tests (byte-exact vs Python rich 15.0.0)":
  exec "python3 golden/golden_compare.py all ./golden_nim"

task build, "Build golden_nim binary":
  switch("define", "release")
  switch("path", "src")
  exec "nim c -d:release --path:src -o:./golden_nim golden_nim.nim"
