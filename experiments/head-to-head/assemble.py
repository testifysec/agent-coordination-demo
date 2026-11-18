"""Assemble results-minimal.json from out/<tag>.metrics.json + tuning.json."""
import json, os, os
V = os.environ["EXP_DIR"]
o = f"{V}/out"
def load(t):
    p = f"{o}/{t}.metrics.json"
    return json.load(open(p)) if os.path.exists(p) else None
tun = json.load(open(f"{o}/tuning.json")) if os.path.exists(f"{o}/tuning.json") else None
keys = ["landed", "prs", "landed_per_hour_middle80", "landed_per_hour_overall", "middle80_landings", "middle80_span_s",
        "first_open_to_last_merge_s", "runner_minutes_per_landed", "token_held_minutes", "test_jobs",
        "job_start_latency_s_p50_p90", "token_wait_s_p50_p90", "refusals", "restarts", "merge_group_runs",
        "pr_ci_runs", "merge_group_failed", "not_landed_agents", "merge_405_retries_total", "merge_runs_with_retry", "lock_wait_s_p50_p90_max", "window_utc_epoch", "run_conclusions", "run_urls", "pr_numbers"]
names = {"m1a": "1a queue ALLGREEN M=4", "m1b": "1b queue HEADGREEN max group 5 M=4", "m1c": "1c agents land-on-evidence M=4",
         "m2a": "2 same-module M=4 (partial, superseded by m2s)", "m2s": "2 same-module claim-waiting agents M=4", "m2r": "2 same-module claim-waiting agents M=8"}
out = {"T_minutes": 2.0, "token_split_chosen_by_tuning": tun, "runs": {}}
for t, label in names.items():
    m = load(t)
    out["runs"][t] = None if m is None else {"label": label, **{k: m.get(k) for k in keys}}
json.dump(out, open(f"{V}/results-minimal.json", "w"), indent=1)
print({t: (r and r["landed_per_hour_middle80"]) for t, r in out["runs"].items()})
