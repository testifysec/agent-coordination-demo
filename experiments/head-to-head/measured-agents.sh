#!/usr/bin/env bash
set -u
V=${EXP_DIR:?set EXP_DIR to a work directory}; H=$V/harness
[ -f "$V/predictions-minimal.sha256" ] || { echo "no predictions-minimal.sha256"; exit 3; }
run() { local tag=$1 arm=$2; shift 2; "$@" >> "$V/out/measured-agents.log" 2>&1
  python3 -I "$H/collect.py" "$tag" "$arm" >> "$V/out/measured-agents.log" 2>&1
  python3 -I "$H/metrics.py" "$tag" > /dev/null 2>&1; echo "done $tag $(date -u +%T)" >> "$V/out/measured-agents.log"; }
: > "$V/out/measured-agents.log"
run m1c agents bash "$H/run-agents.sh" m1c 40 4 disjoint 4800
run m2a agents bash "$H/run-agents.sh" m2a 30 4 samemodule 8400
run m2b agents bash "$H/run-agents.sh" m2b 30 8 samemodule 8400
echo "AGENTS DONE" >> "$V/out/measured-agents.log"
