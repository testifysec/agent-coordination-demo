"""usage: metrics.py <tag> -> prints and writes out/<tag>.metrics.json"""
import json, os, sys, statistics as st, math

TAG = sys.argv[1]
V = os.environ["EXP_DIR"]
d = json.load(open(f"{V}/out/{TAG}.raw.json"))
merged = sorted(p["merged"] for p in d["prs"] if p["merged"])
n = len(merged)


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return None
    k = (len(xs) - 1) * q
    f, c = math.floor(k), math.ceil(k)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


m = {"tag": TAG, "arm": d["arm"], "landed": n, "prs": len(d["prs"])}
if n >= 5:
    lo = int(0.1 * n)               # drop the first and last 10% of landings
    hi = n - 1 - int(0.1 * n)
    span = merged[hi] - merged[lo]
    m["middle80_landings"] = hi - lo + 1
    m["middle80_span_s"] = span
    m["landed_per_hour_middle80"] = round((hi - lo) / span * 3600, 1) if span else None
    m["landed_per_hour_overall"] = round((n - 1) / (merged[-1] - merged[0]) * 3600, 1) if merged[-1] > merged[0] else None
    m["first_open_to_last_merge_s"] = merged[-1] - d["t0"]

held = [int(r["held"]) for r in d["recs"] if "held" in r]
waits = [int(r["wait"]) for r in d["recs"] if "wait" in r]
m["test_jobs"] = len(held)
m["token_held_minutes"] = round(sum(held) / 60, 2)
m["runner_minutes_per_landed"] = round(sum(held) / 60 / n, 3) if n else None
m["token_wait_s_p50_p90"] = [pct(waits, .5), pct(waits, .9)] if waits else None

lat = []
for r in d["runs"]:
    for j in r["jobs"]:
        if j["created"] and j["started"]:
            lat.append(j["started"] - j["created"])
m["job_start_latency_s_p50_p90"] = [pct(lat, .5), pct(lat, .9)] if lat else None
m["jobs_measured"] = len(lat)
m["workflow_runs"] = len(d["runs"])
m["run_conclusions"] = {}
for r in d["runs"]:
    m["run_conclusions"][r["conclusion"]] = m["run_conclusions"].get(r["conclusion"], 0) + 1
if d["arm"] == "queue":
    mg = [r for r in d["runs"] if r["event"] == "merge_group"]
    pr = [r for r in d["runs"] if r["event"] == "pull_request"]
    m["merge_group_runs"] = len(mg); m["pr_ci_runs"] = len(pr)
    m["restarts"] = max(0, len(mg) - n)            # queue builds beyond one per landed change
    m["merge_group_failed"] = sum(1 for r in mg if r["conclusion"] not in ("success", None))
else:
    m["refusals"] = sum(1 for r in d["runs"] if r["conclusion"] == "failure")
    m["not_landed_agents"] = sum(1 for r in d["recs"] if r.get("kind") == "not_landed")
m["run_urls"] = [r["url"] for r in d["runs"]][:400]
m["pr_numbers"] = sorted(p["number"] for p in d["prs"])
json.dump(m, open(f"{V}/out/{TAG}.metrics.json", "w"), indent=1)
print(json.dumps({k: v for k, v in m.items() if k not in ("run_urls", "pr_numbers")}, indent=1))
