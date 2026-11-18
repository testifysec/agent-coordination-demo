"""usage: contention.py <tag>  -> adds merge_attempts_failed and lock_wait stats to out/<tag>.metrics.json
Reads each land run's log once (gh run view --log)."""
import json, os, re, subprocess, sys
TAG = sys.argv[1]
V = os.environ["EXP_DIR"]
R = "testifysec/agent-coordination-demo"
d = json.load(open(f"{V}/out/{TAG}.raw.json"))
m = json.load(open(f"{V}/out/{TAG}.metrics.json"))
retries, waits, per = 0, [], []
for r in d["runs"]:
    if r["event"] != "pull_request_target":
        continue
    log = subprocess.run(["gh", "run", "view", str(r["databaseId"]), "--repo", R, "--log"],
                         capture_output=True, text=True).stdout
    k = len(re.findall(r"merge attempt \d+: ", log))
    retries += k; per.append(k)
    for w in re.findall(r"locked \[[^\]]*\] after (\d+)s", log):
        waits.append(int(w))
waits.sort()
m["merge_405_retries_total"] = retries
m["merge_runs_with_retry"] = sum(1 for k in per if k)
m["lock_wait_s_p50_p90_max"] = [waits[len(waits) // 2], waits[int(len(waits) * .9) - 1], waits[-1]] if waits else None
m["window_utc_epoch"] = [d["t0"], max([p["merged"] or 0 for p in d["prs"]] + [0])]
json.dump(m, open(f"{V}/out/{TAG}.metrics.json", "w"), indent=1)
print(TAG, "retries", retries, "waits", m["lock_wait_s_p50_p90_max"])
