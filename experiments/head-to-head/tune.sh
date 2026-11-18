#!/usr/bin/env bash
# Tuning: 10 PRs per (variant, split). Picks the split with the highest 10 / (last merge - first open).
set -u
V=${EXP_DIR:?set EXP_DIR to a work directory}
H=$V/harness
R=${R:-OWNER/REPO}
gh variable set T --repo $R --body 120
: > "$V/out/tuning.log"
for var in allgreen headgreen; do
  for split in "1 3" "2 2" "3 1"; do
    set -- $split
    tag="tune-${var:0:2}-$1$2"
    bash "$H/run-queue.sh" "$tag" 10 "$var" "$1" "$2" 2400 >> "$V/out/tuning.log" 2>&1
    python3 -I "$H/collect.py" "$tag" queue >> "$V/out/tuning.log" 2>&1
    python3 -I "$H/metrics.py" "$tag" > /dev/null 2>&1
    echo "done $tag" >> "$V/out/tuning.log"
  done
done
python3 -I - <<'PY'
import json
V="${EXP_DIR}"
res={}
for var in ("al","he"):
    best=None
    for ci,mq in ((1,3),(2,2),(3,1)):
        tag=f"tune-{var}-{ci}{mq}"
        try: d=json.load(open(f"{V}/out/{tag}.raw.json"))
        except Exception: continue
        mer=[p["merged"] for p in d["prs"] if p["merged"]]
        if len(mer)<10: score=0
        else: score=10/(max(mer)-d["t0"])*3600
        res.setdefault(var,{})[f"{ci}/{mq}"]=round(score,1)
        if best is None or score>best[0]: best=(score,ci,mq)
    res[var]["best"]={"pool_ci":best[1],"pool_mq":best[2],"landed_per_hour":round(best[0],1)}
json.dump(res,open(f"{V}/out/tuning.json","w"),indent=1); print(json.dumps(res,indent=1))
PY
