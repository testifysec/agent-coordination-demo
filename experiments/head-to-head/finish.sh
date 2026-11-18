#!/usr/bin/env bash
# usage: finish.sh <tag> <arm> <pid-to-wait-for|0>  then collect + metrics
V=${EXP_DIR:?set EXP_DIR to a work directory}; H=$V/harness
if [ "$3" != 0 ]; then while kill -0 "$3" 2>/dev/null; do sleep 20; done; fi
python3 -I $H/collect.py "$1" "$2" >> $V/out/measured-agents.log 2>&1
python3 -I $H/metrics.py "$1" > /dev/null 2>&1
echo "done $1 $(date -u +%T)" >> $V/out/measured-agents.log
