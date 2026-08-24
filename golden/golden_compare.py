#!/usr/bin/env python3
## golden_compare.py — byte-exact golden gate.
##
## Compares RAW ANSI bytes of Python rich 15.0.0 vs the Nim port — with NO
## normalization (width=80 fixed via force_terminal → cursor moves are
## deterministic; stripping CSI would mask control_home/control_clear as
## 0B-vs-0B false-MATCH).
##
## Design:
##  - capture: checks exit code + stderr (Nim crash/segfault = FAIL, not silent 0B)
##  - NO_COLOR is neutralized (del from env) — Python rich respects NO_COLOR,
##    Nim does not; without forcing, the ref renders colorless → false DIFF
##    or false MATCH
##  - RAW bytes (no normalization) — a real byte-exact gate
##  - absolute path to golden_ref.py (independent of cwd)
##
## Usage:
##   golden_compare.py <case> <nim_binary> [args...]   # one case
##   golden_compare.py all <nim_binary> [args...]      # all cases, reports N/M
import sys, subprocess, os

HERE = os.path.dirname(os.path.abspath(__file__))
REF = os.path.join(HERE, "golden_ref.py")
LOCAL_GOLDEN_PY = os.path.abspath(
    os.path.join(HERE, "..", "..", "golden-venv", "bin", "python")
)
GOLDEN_PY = os.environ.get("GOLDEN_PY") or (
    LOCAL_GOLDEN_PY if os.path.isfile(LOCAL_GOLDEN_PY) else "python3"
)


def clean_env():
    # Force colored output on both sides — remove NO_COLOR and related vars.
    e = dict(os.environ)
    for k in ("NO_COLOR", "CLICOLOR_FORCE", "CLICOLOR", "FORCE_COLOR", "TERM"):
        e.pop(k, None)
    e["TERM"] = "xterm-256color"  # deterministic terminfo
    return e


def capture(cmd):
    """Returns (stdout_bytes) or raises on non-zero exit / stderr / timeout."""
    r = subprocess.run(cmd, capture_output=True, timeout=30, env=clean_env())
    if r.returncode != 0:
        raise RuntimeError(f"exit {r.returncode}: {r.stderr.decode('utf-8','replace')[:200]}")
    if r.stderr and r.stderr.strip():
        # Non-empty stderr = warning/stacktrace — not a silent PASS
        raise RuntimeError(f"stderr: {r.stderr.decode('utf-8','replace')[:200]}")
    return r.stdout


def run_case(case, nim_bin):
    py_cmd = [GOLDEN_PY, REF, case]
    nim_cmd = nim_bin + [case]
    ref = capture(py_cmd)
    cand = capture(nim_cmd)
    return ref, cand


def compare_one(case, nim_bin):
    try:
        ref, cand = run_case(case, nim_bin)
    except RuntimeError as ex:
        print(f"  ✗ {case}: ERROR ({ex})")
        return False
    if ref == cand:
        print(f"  ✓ {case}: MATCH ({len(ref)} bytes)")
        return True
    print(f"  ✗ {case}: DIFF (ref={len(ref)}B nim={len(cand)}B)")
    import difflib
    for line in difflib.unified_diff(
        ref.decode("utf-8", "replace").splitlines(),
        cand.decode("utf-8", "replace").splitlines(),
        fromfile="python_rich", tofile="nim_port", lineterm=""):
        print("   ", line)
    return False


def main():
    if len(sys.argv) < 3:
        print("usage: golden_compare.py <case|all> <nim_binary> [args...]", file=sys.stderr)
        sys.exit(2)
    target = sys.argv[1]
    nim_bin = sys.argv[2:]
    if target == "all":
        sys.path.insert(0, HERE)
        from golden_cases import case_names
        cases = case_names()
        ok = sum(compare_one(c, nim_bin) for c in cases)
        print(f"\n  === {ok}/{len(cases)} PASS ===")
        sys.exit(0 if ok == len(cases) else 1)
    else:
        sys.exit(0 if compare_one(target, nim_bin) else 1)


if __name__ == "__main__":
    main()
