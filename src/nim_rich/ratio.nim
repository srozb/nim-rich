## Nim port of `rich._ratio` (rich/_ratio.py).
##
## Ratio distribution helpers used by `rich.layout`/`rich.table`:
## `ratio_resolve` (_ratio.py:14), `ratio_reduce` (_ratio.py:75),
## `ratio_distribute` (_ratio.py:107), plus the `Edge` `Protocol` (_ratio.py:6).
## The module is private in Python (leading underscore) but is imported by
## public modules (`from ._ratio import ratio_resolve, …`, table.py:17), so the
## three functions and `Edge` are public (`*`) here — the underscore is a Python
## module-privacy convention, not symbol privacy.
##
## Import graph (rich/_ratio.py:1-3): `from fractions import Fraction`,
## `from math import ceil`, `from typing import cast, List, Optional, Sequence,
## Protocol`. No rich sibling imports — this is a pure leaf. Nim needs
## `std/options` for `Optional[int]`/`Optional[List[int]]` and `std/math` for
## `ceil` (used by the ported `ratioResolve` body); `Fraction`/`cast` are
## body-only (body, not needed in the Nim port). `Sequence[Edge]` →
## `openArray[Edge]`, `List[int]` → `seq[int]`.
##
## wiring (this file): `import std/options` and `import std/math` (for
## `ceil`, used by the ported `ratioResolve`/`ratioDistribute` bodies). `Edge` is a
## `typing.Protocol` (structural) in Python; models it as a concrete
## `ref object of RootObj` — a faithful storage handle whose field defaults
## mirror the Protocol's annotations (_ratio.py:9-11) — and notes that body
## may convert it to a Nim `concept` for structural dispatch once `layout.nim`
## supplies concrete edges. Proc bodies are ported (ratioResolve/ratioReduce/
## ratioDistribute implement _ratio.py:14-141).

import std/options
import std/math

type
  Edge* = ref object of RootObj
    ## rich _ratio.py:6-11 — `class Edge(Protocol)`: any object that defines an
    ## edge (such as a Layout row/column) via `size`/`ratio`/`minimum_size`.
    ## Python models it as a `typing.Protocol` (structural typing); port
    ## models it as a concrete `ref object of RootObj` (a faithful storage
    ## handle — body may convert to a `concept` so `ratioResolve` accepts any
    ## type with these fields). Field defaults mirror the Protocol annotations.
    size*: Option[int] = none(int)   ## rich _ratio.py:9 — `size: Optional[int] = None` (None ⇒ undetermined).
    ratio*: int = 1                 ## rich _ratio.py:10 — `ratio: int = 1`.
    minimumSize*: int = 1           ## rich _ratio.py:11 — `minimum_size: int = 1` (`minimum_size` → `minimumSize`).

proc ratioResolve*(total: int, edges: openArray[Edge]): seq[int] =
  ## rich _ratio.py:14-73 — `ratio_resolve(total: int, edges: Sequence[Edge])
  ## -> List[int]`: divide `total` space to satisfy `size`/`ratio`/
  ## `minimum_size` constraints (the returned list sums to `total` unless the
  ## minimums force overflow, _ratio.py:22-27). `Sequence[Edge]` →
  ## `openArray[Edge]`; `List[int]` → `seq[int]`. (body `discard` ⇒
  ## returns `@[]`).
  # `size` sentinel: -1 ⇒ undetermined (`edge.size or None`, where a size of 0
  # is also treated as undetermined, faithful to `0 or None` → `None`).
  const noneSentinel = -1
  var sizes = newSeq[int](edges.len)
  for i, e in edges:
    let v = e.size.get(0)
    sizes[i] = if e.size.isSome and v != 0: v else: noneSentinel
  while true:
    var hasNone = false
    for s in sizes:
      if s == noneSentinel:
        hasNone = true
        break
    if not hasNone:
      break
    var flexIdx = newSeq[int]()
    var flexEdges = newSeq[Edge]()
    for i, s in sizes:
      if s == noneSentinel:
        flexIdx.add(i)
        flexEdges.add(edges[i])
    var usedSum = 0
    for s in sizes:
      if s != noneSentinel:
        usedSum += s
    let remaining = total - usedSum
    if remaining <= 0:
      for i, s in sizes:
        if s == noneSentinel:
          sizes[i] = (if edges[i].minimumSize == 0: 1 else: edges[i].minimumSize)
      break
    var sRatio = 0
    for e in flexEdges:
      sRatio += (if e.ratio == 0: 1 else: e.ratio)
    var didBreak = false
    for j, e in flexEdges:
      let er = (if e.ratio == 0: 1 else: e.ratio)
      if remaining * er <= e.minimumSize * sRatio:
        sizes[flexIdx[j]] = e.minimumSize
        didBreak = true
        break
    if didBreak:
      continue
    var remainderNum = 0
    for j, e in flexEdges:
      let er = (if e.ratio == 0: 1 else: e.ratio)
      let num = remaining * er + remainderNum
      sizes[flexIdx[j]] = num div sRatio
      remainderNum = num mod sRatio
    break
  result = sizes

proc ratioReduce*(total: int, ratios: openArray[int], maximums: openArray[int],
                  values: openArray[int]): seq[int] =
  ## rich _ratio.py:75-92 — `ratio_reduce(total, ratios, maximums, values)
  ## -> List[int]`: divide an integer total into parts based on ratios,
  ## respecting per-slot maximums. (body `discard` ⇒ returns `@[]`).
  var r = newSeq[int](ratios.len)
  for i in 0..<ratios.len:
    r[i] = if i < maximums.len and maximums[i] != 0: ratios[i] else: 0
  var totalRatio = 0
  for x in r:
    totalRatio += x
  if totalRatio == 0:
    return @values
  var totalRemaining = total
  var totalRatioVar = totalRatio
  result = newSeq[int](ratios.len)
  for i in 0..<ratios.len:
    let ratio = r[i]
    let maximum = if i < maximums.len: maximums[i] else: 0
    let value = if i < values.len: values[i] else: 0
    if ratio != 0 and totalRatioVar > 0:
      let distributed = min(maximum, int(round(ratio * totalRemaining / totalRatioVar)))
      result[i] = value - distributed
      totalRemaining -= distributed
      totalRatioVar -= ratio
    else:
      result[i] = value

proc ratioDistribute*(total: int, ratios: openArray[int],
                      minimums: Option[seq[int]] = none(seq[int])): seq[int] =
  ## rich _ratio.py:107-141 — `ratio_distribute(total, ratios, minimums=None)
  ## -> List[int]`: distribute an integer total into parts based on ratios,
  ## guaranteed to sum to `total` (asserts `sum(ratios) > 0`, _ratio.py:131).
  ## `Optional[List[int]]` → `Option[seq[int]]`, default `none(seq[int])`
  ## (Python `None`). (body `discard` ⇒ returns `@[]`).
  let hasMins = minimums.isSome and minimums.get.len > 0
  var r = newSeq[int](ratios.len)
  if hasMins:
    let mins = minimums.get
    for i in 0..<ratios.len:
      r[i] = if i < mins.len and mins[i] != 0: ratios[i] else: 0
  else:
    for i in 0..<ratios.len:
      r[i] = ratios[i]
  var totalRatio = 0
  for x in r:
    totalRatio += x
  assert totalRatio > 0, "Sum of ratios must be > 0"
  let dummyMins = newSeq[int](ratios.len)
  let mins = if hasMins: minimums.get else: dummyMins
  var totalRemaining = total
  var totalRatioVar = totalRatio
  result = newSeq[int](ratios.len)
  for i in 0..<ratios.len:
    let ratio = r[i]
    let minimum = if i < mins.len: mins[i] else: 0
    let distributed = if totalRatioVar > 0:
      max(minimum, int(ceil(ratio * totalRemaining / totalRatioVar)))
    else:
      totalRemaining
    result[i] = distributed
    totalRatioVar -= ratio
    totalRemaining -= distributed
