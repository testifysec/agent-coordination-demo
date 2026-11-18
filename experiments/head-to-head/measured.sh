#!/usr/bin/env bash
# The measured runs, in order. Refuses to start unless the sealed-predictions hash exists.
set -u
V=${EXP_DIR:?set EXP_DIR to a work directory}
H=$V/harness
R=${R:-OWNER/REPO}
[ -f "$V/predictions-minimal.sha256" ] || { echo "no predictions-minimal.sha256: refusing to run measured runs"; exit 3; }
gh variable set T --repo $R --body 120
read AG_CI AG_MQ HG_CI HG_MQ < <(python3 -I - <<'PY'
import json
t=json.load(open("${EXP_DIR}/out/tuning.json"))
print(t["al"]["best"]["pool_ci"], t["al"]["best"]["pool_mq"], t["he"]["best"]["pool_ci"], t["he"]["best"]["pool_mq"])
PY
)
echo "splits: allgreen ci=$AG_CI mq=$AG_MQ ; headgreen ci=$HG_CI mq=$HG_MQ"
run() { # tag arm cmd...
  local tag=$1 arm=$2; shift 2
  "$@" >> "$V/out/measured.log" 2>&1
  python3 -I "$H/collect.py" "$tag" "$arm" >> "$V/out/measured.log" 2>&1
  python3 -I "$H/metrics.py" "$tag" > /dev/null 2>&1
  echo "done $tag $(date -u +%T)" >> "$V/out/measured.log"
}
: > "$V/out/measured.log"
run m1a queue  bash "$H/run-queue.sh"  m1a 40 allgreen  "$AG_CI" "$AG_MQ" 5400
run m1b queue  bash "$H/run-queue.sh"  m1b 40 headgreen "$HG_CI" "$HG_MQ" 5400
echo "QUEUE DONE" >> "$V/out/measured.log"
