# Head-to-head: merge queue vs land on evidence

Runs the same fake workload through two arms on your own GitHub runners and measures how many changes land per hour and what each landing costs. The "test" is a constant sleep, so the result is the cost of the machinery (queue, CI, signing, locks), not of your tests.

## What it measures

Two terms of the throughput line: a machine term (how many tests can run at once, M) and a fan-out term (how many changes can be in flight when they all touch one module).

| Run | What | Parameters |
| --- | --- | --- |
| 1a | GitHub merge queue, ALLGREEN, PR CI then queue build | 40 disjoint PRs, M=4 |
| 1b | GitHub merge queue, HEADGREEN, max group 5 | 40 disjoint PRs, M=4 |
| 1c | Agents: test once under `cilock`, land-on-evidence Action, no PR CI | 40 disjoint PRs, M=4 |
| 2 | Agents that wait for a claim, every PR touches one module, land-on-evidence | 30 PRs, M=4 and M=8 |

## The token pool

Every test job (PR CI, merge-queue build, agent test) must hold one token before its sleep of T seconds (default 120) and release it after. Tokens are git refs: `refs/tokens/<pool>/<i>`, created with `git push --force-with-lease=<ref>:` (create-only), released by deleting with a lease on our own commit. A token carries an expiry and an expired one is taken over by compare-and-swap. This caps concurrent tests at M regardless of how many runners GitHub gives you, and the cost is token-held minutes ("runner-minutes").

For the queue arm the M tokens are split between two pools, `ci` (PR CI) and `mq` (queue builds). `tune.sh` tries the splits 1/3, 2/2 and 3/1 on 10 PRs each, for each of ALLGREEN and HEADGREEN, and the measured runs use the best split. Tune on separate PRs from the measured run.

## Files

| File | Purpose |
| --- | --- |
| `sem.sh` | Token semaphore and record helper (sourced). |
| `test-job.sh`, `queue-ci.yml` | The queue arm's test job and workflow (PR CI on `pull_request`, build on `merge_group`). |
| `setup.sh` | One-time: creates the `main-queue` and `land-b` branches, rulesets, repo variables. Edit the key paths at the top. |
| `queue-ruleset.sh` | Applies the merge-queue ruleset (`allgreen` or `headgreen`). |
| `run-queue.sh`, `run-agents.sh` | One measured run each. |
| `tune.sh`, `measured.sh`, `measured-agents.sh` | The sequences. |
| `run-agents2.sh`, `finish.sh`, `contention.py` | The same agent run on a second module and pools (to overlap two cell-2 runs); collect-after-exit helper; adds merge-405 retries and lock waits to a run's metrics. |
| `collect.py`, `metrics.py`, `assemble.py` | Pull timestamps from the API, compute metrics, build one results file. |

The land-on-evidence arm uses the Action in this repository (`LAND.md`) with `LAND_BRANCHES` set to include its branch. Both arms run on their own protected branches so they do not interact.

## Run it

Set `EXP_DIR` to an empty work directory, then put these scripts in `$EXP_DIR/harness/` and create `$EXP_DIR/out` and `$EXP_DIR/work`. `KEY_DIR` (default `~/.config/cilock`) holds `agent.key`, `agent.pub`, `policy.key`. `CILOCK_DIR` (default `~/.local/bin`) is where `cilock` lives. `setup.sh` clones the repository you point it at: edit its `R=` line first.

Needs `cilock` 4.10 or later, `gh`, `git`, `python3`, `jq`, `openssl`, and a repository where you may create branches, rulesets and Actions variables. Do not run it in a repository you care about.

```sh
# keys: see ../../README.md ("Run it on your own repository"); setup.sh expects an agent key and a policy key
bash setup.sh
bash tune.sh                  # about 2.5 hours: 6 runs of 10 PRs
bash measured.sh              # 1a, 1b (needs tuning.json)
bash measured-agents.sh       # 1c, 2 at M=4, 2 at M=8
python3 assemble.py
```

Runs take 20 to 100 minutes each at T=120 s. Total about 6 hours, mostly waiting; the agent runs and the tuning runs can overlap because they use separate pools and branches.

## Reading the metrics

- `landed_per_hour_middle80`: landings an hour between the 10th and 90th percentile landing, so ramp-up and tail are excluded. The ceiling with M tokens and T-second tests is `M * 3600 / T` (120 an hour for M=4, T=120 s).
- `runner_minutes_per_landed`: token-held minutes divided by landings. One test per change is 2.0 at T=120 s; the queue arm pays PR CI plus a queue build, so about 4.0 or more.
- `job_start_latency_s_p50_p90`: GitHub's queue time (`created_at` to `started_at`) per job from the jobs API. If it grows, your runners, not the model, are the limit.
- `token_wait_s_p50_p90`: how long jobs waited for a token. This is the machine term showing up.
- `refusals` (agents): land runs that failed with the overlap message. `restarts` (queue): merge-group builds beyond one per landing.
- `run_urls`: every workflow run involved.

## Costs and limits

- Waiting test jobs occupy a GitHub runner while they wait for a token. 40 queued jobs is 40 concurrent runners; check your plan's concurrency limit, and record start latency so inflation is visible.
- The agent arm's tests run on the machine that runs the script; its Actions jobs are only the landing jobs (about 20 to 60 seconds each, billed).
- GitHub merges one PR at a time per repository, roughly 2 to 3 seconds each, so about 1,200 to 1,800 landings an hour is a hard ceiling on one repository whatever you do.
- The queue's build timeout, `check_response_timeout_minutes`, is 60 in `queue-ruleset.sh`; a long token wait can eject a group.
- Default `GITHUB_TOKEN` merges do not start `push` workflows, and the required check is pinned only to the Actions app; see `LAND.md`.
- It does not simulate failures, flaky tests, semantic breaks, or variable test times.

## Results from our run (2026-11-17, GitHub-hosted runners, T=120 s)

`results-minimal.json` and `tuning.json` are our numbers. Two harness bugs cost us reruns, and are fixed here: an end-of-run counter that counted every merge on a shared branch (two overlapping runs ended each other early), and a PR listing limit that hid old PRs from the collector.
