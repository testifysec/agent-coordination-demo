# Land on evidence (no merge queue)

A second way to run the same model. Instead of a merge queue that tests every merged result, an Action lands a pull request when signed evidence says its tests passed on its head, and nothing touching the same module landed since its base. Testing moves to after the landing.

## The flow

1. The agent claims its modules (`SKILL.md`), tests under `cilock`, publishes `refs/evidence/<sha>`, and pushes. A draft PR is "not ready" and is ignored. Opening or pushing a ready PR is the signal.
2. `.github/workflows/land-on-evidence.yml` fires on `pull_request_target` (it runs the copy on main, never the PR's, and executes nothing from the PR). `.land/plan.sh` verifies the evidence with `cilock verify` against the policy on main and computes the PR's modules. A draft PR fails the check ("not ready"); marking it ready runs the workflow again.
3. The job named `land-on-evidence` **is** the required check. It runs `.land/land.sh check`, which takes a lock on every module the PR touches (below), then lists the files that landed on main since the PR's merge base. If any is in the same module, it reports a failed `land-on-evidence` check: `overlapping change landed since base; re-run on the new base or stack`. Otherwise the check goes green with the locks still held, and a second job, `merge`, merges exactly the verified head with `PUT /pulls/{n}/merge` (`merge_method=merge`, `sha=<head>`) and releases the locks. A third job, `unlock`, frees the locks if the merge job never ran. No tests run.
   Runs started by `workflow_dispatch` or `push` have no pull request event, so a single job does all of it and posts the check as a REST check run (`land-rest`).
4. `.github/workflows/post-land.yml` tests main on a schedule (and on dispatch). Red: it bisects the first-parent commits since the last green run and opens a revert PR. It never pushes to main.

A module is the top-level directory of a changed file. Edit `modules_of` in `.land/plan.sh` and `.land/land.sh` if your layout differs.

## The lock

A lock per module, held from the overlap check through the merge, for every module the PR touches. It is a git ref, not an Actions concurrency group (a group keeps one pending run and cancels the rest, and holds one key).

- Take: `git push --atomic --force-with-lease=refs/locks/m-<module>: origin <commit>:refs/locks/m-<module>`, one lease per module, all modules in one atomic push. The empty expected value means the ref must not exist, so exactly one run wins a module. All or nothing: a run never holds some modules while waiting for others, so there is no deadlock.
- The lock commit's message names the holder and an expiry (120 s; a landing takes about 10). A crashed run's lock is taken over by compare-and-swap on the exact sha that was read.
- Wait: retry with 1 to 3 s jitter for up to 300 s. On timeout the `land-on-evidence` check fails with `Could not take the landing lock ... held by: <run>`. Nothing is cancelled silently.
- Release: delete the refs with a lease on our own sha (also on `EXIT`).
- It still does not see semantic overlap across modules; that is `post-land`'s job.

## Settings

`ruleset.land.json`: pull request required (0 approvals here, because one person cannot approve their own PRs; raise it for a team), required check `land-on-evidence` (pinned to the GitHub Actions app, id 15368), no merge queue, no bypass actors, "require branches up to date" off. Repository auto-merge is off.

```sh
gh api repos/OWNER/REPO/rulesets --method POST --input ruleset.land.json
gh repo edit OWNER/REPO --enable-auto-merge=false
# the post-land check opens revert PRs with the workflow token:
gh api repos/OWNER/REPO/actions/permissions/workflow --method PUT -F can_approve_pull_request_reviews=true -f default_workflow_permissions=read
```

The required check is the **job** `land-on-evidence`, not a check run posted over the API. The job is skipped for PRs that do not target `main`, which is fine because the ruleset does not apply to them. Do not put an `if:` on that job that can skip it for a PR into `main`: a skipped required job counts as passing.

## Measured here (GitHub-hosted runners, default GITHUB_TOKEN, 2026-11-17)

All times are wall clock from GitHub's timestamps. The repository is tiny (30 independent modules, `go test ./...` in about a second), so these numbers are the cost of the machinery, not of your tests.

| Case | Result |
| --- | --- |
| One ready PR, evidence attached | Opened to merged in 25 s (PR #4), 21 s (#50). |
| 20 disjoint PRs opened in a 41 s loop (#30 to #49) | 20 of 20 landed. Opened to merged: median 27 s, p90 36 s, max 76 s. First open to last merge: 95 s, about 760 landings an hour while the burst lasted. |
| Merge contention in that burst | 12 of 20 needed a retry: `405 Base branch was modified`. The worst took 7 attempts against a cap of 8, which is why the cap is now 15 with jitter. Landings in one repository are serialised by GitHub itself at roughly 2 to 3 s each. |
| 3 PRs in one module, git-ref lock (#62, #63, #64) | #62 landed in 24 s from open. #63 and #64 waited 8 s and 10 s for the lock, then failed with `overlapping change landed since base (m29); re-run on the new base or stack`. None cancelled. (With the old concurrency group: the second was cancelled silently.) |
| 2 PRs sharing only their second module (#60 touches m23+m24, #61 touches m24+m25) | #60 landed. #61 waited 9 s for `m24`, then failed with the overlap message. Serialised, no race. (With the old group the two held different keys, m23 and m24, and could race.) |
| 20 disjoint PRs again with the lock (#65 to #84), opened in a 43 s loop | 20 of 20 landed. Opened to merged: median 30 s, p90 47 s, max 58 s; first open to last merge 83 s (about 870 an hour in the burst). Taking the lock cost 1 to 3 s per PR. 12 of 20 still retried the merge (`405 Base branch was modified`), the worst 8 times before landing, under a cap of 15. |
| Cross-module break (#55 lib, #56 api) | Both verified, both disjoint, both landed (23 s and 26 s). Main was red at 18:03:01. A manual dispatch of `post-land` at 18:03:41 found it, bisected to #56, and opened revert PR #57 at 18:04:05 (22 s run). Evidence for the revert and a dispatch of the land workflow: merged 18:04:57. Main green again at the next `post-land` run, 18:06:18. About 2 minutes from break to revert merged, with a person-or-agent doing the dispatches. |
| `post-land` on the schedule | The `*/15` cron fired once at 17:50:04 in the first 25 minutes (the 17:45 slot ran 5 minutes late; the 18:00 slot had not run by 18:05). Treat the schedule as a backstop, not a detector. |

### Validation round on the job-as-check version (2026-11-17, from a clean state)

| Case | Result | Runs |
| --- | --- | --- |
| One ready PR (#90) | Opened 20:29:20, merged 20:29:48: 28 s. | [44169821324](https://github.com/testifysec/agent-coordination-demo/actions/runs/44169821324) |
| 5 disjoint PRs (#91 to #95), opened over 10 s | All 5 landed. Open to merged 29 to 56 s (median 34 s). | [44170019064](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170019064), [44170026413](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170026413), [44170031593](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170031593), [44170041752](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170041752), [44170045403](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170045403) |
| 2 overlapping PRs, `m11` (#96, #97) | #96 landed. #97 waited 12 s for the lock, then failed: `overlapping change landed since base (m11); re-run on the new base or stack`. | [44170056079](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170056079), [44170061750](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170061750) |
| 3 overlapping PRs, `m12` (#98, #99, #100) | #98 landed. #99 and #100 waited 18 s and 16 s, then failed with the overlap message. None cancelled. | [44170068890](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170068890), [44170074102](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170074102), [44170078276](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170078276) |
| 2 PRs sharing only their second module (#101 `m13`+`m14`, #102 `m14`+`m15`) | #101 landed. #102 waited 20 s for `m14` (it held both locks), then failed: `overlapping change landed since base (m14)`. | [44170084717](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170084717), [44170094176](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170094176) |
| Cross-module break (#103 lib, #104 api) | Both landed (30 s and 32 s). `main` red from 20:34:38. `post-land` dispatched 20:35:33 bisected to #104 and opened revert PR #105 at 20:35:55 (22 s run). Evidence for the revert and a dispatch of the land workflow: merged 20:37:10. Green `post-land` run finished 20:38:38. | [44170917379](https://github.com/testifysec/agent-coordination-demo/actions/runs/44170917379), [44171142782](https://github.com/testifysec/agent-coordination-demo/actions/runs/44171142782), [44171275366](https://github.com/testifysec/agent-coordination-demo/actions/runs/44171275366) |
| Draft, then ready (#88) | Draft run: check red (`Draft`). Marked ready 20:24:20; merged 20:24:48 (28 s). | [44168954641](https://github.com/testifysec/agent-coordination-demo/actions/runs/44168954641) |
| Draft marked ready within a second (#89), so two runs on one head | One run merged it; the other run's merge job found it already merged. | [44169177055](https://github.com/testifysec/agent-coordination-demo/actions/runs/44169177055) |

Lock waits grew from 1 to 3 s (uncontended) to 12 to 20 s in the overlap cases, because a waiting run polls every 1 to 3 s until the holder's merge finishes.

### Problems found while measuring

- A rename's old path was not in the footprint (fixed in #5).
- **Fixed: a PR opened as a draft and marked ready never landed.** 22 of 22 were refused at merge with `Required status check "land-on-evidence" is expected` although a green check run existed on the head. Cause, from the check-suite data: a check run posted with `GITHUB_TOKEN` over the REST API attaches to the *first* workflow-run check suite on the head SHA, and the required-check rule reads the *latest* suite for the app. A draft-then-ready PR has two suites (the `opened` run and the `ready_for_review` run), so the check sat in the wrong one. PRs with one suite landed. Fix: the required check is now the workflow job itself, which is always in its own run's suite (PR #88 above). Dispatch and push runs still post a REST check run; a draft-then-ready PR re-evaluated that way could meet the old problem, and I did not test it. A GitHub App posting the check would not involve workflow suites at all, and I could not test that.
- A merge made by the workflow does not start `push` workflows, as documented. `post-land` therefore ran on a schedule and on dispatch only.

## What it cannot do

- **Production setup needs a GitHub App.** The merge here uses the workflow's `GITHUB_TOKEN`. A merge made with it does not trigger other workflows (so `post-land` runs on its schedule, not on the push), and the required check is pinned only to "the GitHub Actions app", which any workflow in the repository can post as. A GitHub App installation token fixes both: pin the check to the App's id, and its merges trigger `push`. Creating the App and storing its private key is a human step. Nothing here does it.
- **The lock is advisory in the same way as every other lock here.** It protects landings made by this workflow. A human with merge rights who merges another way bypasses it; the ruleset's required check is what stops that, and with the default token that check is only pinned to "the GitHub Actions app".
- **Module overlap is not semantic overlap.** Two PRs in different modules can pass their own tests and break each other. Only the post-land test finds that, after the fact.
- **Evidence still names a commit.** A new push needs new evidence.
