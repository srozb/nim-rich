#!/usr/bin/env bash
# fanout.sh — spawn N parallel pi children to implement independent .nim modules.
#
# Used by the executor in Phase 1. The MANAGER decides the partition and writes
# the per-child task files; this script just launches them in parallel and waits.
#
# Usage:
#   fanout.sh <child_tasks_dir>
#     <child_tasks_dir>/child_1.txt child_2.txt child_3.txt child_4.txt ...
#   Each file = a self-contained prompt for one pi child.
#
# Output: each child's pi stdout → <child_tasks_dir>/child_N.out
# Exit: 0 if all children exited 0, else first non-zero.
set -uo pipefail

DIR="${1:?usage: fanout.sh <child_tasks_dir>}"
PI=/usr/local/bin/pi
MODEL="${LH_HARNESS_FANOUT_MODEL:-cert b200/glm-5.2}"
MCP="${LH_HARNESS_PI_MCP_CONFIG:-}"
CHILD_TIMEOUT="${LH_HARNESS_CHILD_TIMEOUT:-900}"  # 15 min max na jedno dziecko fanout

pids=()
rc=0
i=0
for task in "$DIR"/child_*.txt; do
  [[ -f "$task" ]] || continue
  i=$((i+1))
  out="${task%.txt}.out"
  echo ">> [fanout] launch child $i: $(basename "$task")"
  args=(timeout "$CHILD_TIMEOUT" "$PI" --no-session --model "$MODEL" -p "$(cat "$task")")
  "${args[@]}" >"$out" 2>&1 &
  pids+=($!)
done

echo ">> [fanout] waiting for ${#pids[@]} children..."
for pid in "${pids[@]}"; do
  wait "$pid" || rc=$?
done

echo ">> [fanout] done (rc=$rc, $i children)"
# print a one-line summary of each child's output tail
for task in "$DIR"/child_*.txt; do
  [[ -f "$task" ]] || continue
  out="${task%.txt}.out"
  echo ">> [fanout] $(basename "$task") → $(basename "$out"): $(tail -1 "$out" 2>/dev/null | head -c 80)"
done
exit $rc
