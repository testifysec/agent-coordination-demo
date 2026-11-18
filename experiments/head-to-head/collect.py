"""usage: collect.py <tag> <arm: queue|agents>
Pull everything a run produced: PRs (created/merged), workflow runs and their jobs (one `run view` per run),
token records (refs/rec/<tag>/*). Writes out/<tag>.raw.json."""
import json, os, subprocess, sys, datetime as dt, os

TAG, ARM = sys.argv[1], sys.argv[2]
V = os.environ["EXP_DIR"]
R = "testifysec/agent-coordination-demo"
REPO = f"{V}/work/repo"
t0 = int(open(f"{V}/out/{TAG}.t0").read())


def sh(args, cwd=None):
    return subprocess.run(args, capture_output=True, text=True, cwd=cwd).stdout


def ts(s):
    return int(dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()) if s else None


prs = json.loads(sh(["gh", "pr", "list", "--repo", R, "--state", "all", "--limit", "1000",
                     "--json", "number,headRefName,state,createdAt,mergedAt"]))
prs = [p for p in prs if p["headRefName"].startswith(f"rt-{TAG}-")]
for p in prs:
    p["created"] = ts(p.pop("createdAt")); p["merged"] = ts(p.pop("mergedAt"))

wf = "queue-ci.yml" if ARM == "queue" else "land-on-evidence.yml"
created = dt.datetime.fromtimestamp(t0 - 30, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
runs = json.loads(sh(["gh", "run", "list", "--repo", R, "--workflow", wf, "--limit", "400",
                      "--json", "databaseId,event,createdAt,conclusion,headBranch,displayTitle"]))
runs = [r for r in runs if ts(r["createdAt"]) >= t0 - 30]
for r in runs:
    j = json.loads(sh(["gh", "api", f"repos/{R}/actions/runs/{r['databaseId']}/jobs", "--paginate", "--jq", "{jobs: .jobs}"]) or "{}")
    r["jobs"] = [{"name": x["name"], "created": ts(x.get("created_at")), "started": ts(x.get("started_at")),
                  "completed": ts(x.get("completed_at")), "conclusion": x.get("conclusion")} for x in j.get("jobs", [])]
    r["created"] = ts(r.pop("createdAt")); r["url"] = f"https://github.com/{R}/actions/runs/{r['databaseId']}"

sh(["git", "fetch", "-q", "origin", f"+refs/rec/{TAG}/*:refs/rec/{TAG}/*"], cwd=REPO)
recs = []
for line in sh(["git", "for-each-ref", "--format=%(refname)", f"refs/rec/{TAG}"], cwd=REPO).split():
    msg = sh(["git", "log", "-1", "--format=%B", line], cwd=REPO)
    d = dict(kv.split("=", 1) for kv in msg.split() if "=" in kv)
    recs.append(d)

json.dump({"tag": TAG, "arm": ARM, "t0": t0, "prs": prs, "runs": runs, "recs": recs},
          open(f"{V}/out/{TAG}.raw.json", "w"), indent=1)
print(f"{TAG}: {len(prs)} PRs ({sum(1 for p in prs if p['merged'])} merged), {len(runs)} runs, {len(recs)} token records")
