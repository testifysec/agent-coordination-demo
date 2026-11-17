# Land on evidence (no merge queue)

A second way to run the same model. Instead of a merge queue that tests every merged result, an Action lands a pull request when signed evidence says its tests passed on its head, and nothing touching the same module landed since its base. Testing moves to after the landing.

## The flow

1. The agent claims its modules (`SKILL.md`), tests under `cilock`, publishes `refs/evidence/<sha>`, and pushes. A draft PR is "not ready" and is ignored. Opening or pushing a ready PR is the signal.
2. `.github/workflows/land-on-evidence.yml` fires on `pull_request_target` (it runs the copy on main, never the PR's, and executes nothing from the PR). `.land/plan.sh` verifies the evidence with `cilock verify` against the policy on main and computes the PR's modules.
3. `.land/land.sh`, inside a concurrency group per module, lists the files that landed on main since the PR's merge base. If any is in the same module, it reports a failed `land-on-evidence` check: `overlapping change landed since base; re-run on the new base or stack`. Otherwise it reports a successful check and merges exactly the verified head with `PUT /pulls/{n}/merge` (`merge_method=merge`, `sha=<head>`). No tests run.
4. `.github/workflows/post-land.yml` tests main on a schedule (and on dispatch). Red: it bisects the first-parent commits since the last green run and opens a revert PR. It never pushes to main.

A module is the top-level directory of a changed file. Edit `modules_of` in `.land/plan.sh` and `.land/land.sh` if your layout differs.

## Settings

`ruleset.land.json`: pull request required, required check `land-on-evidence` (pinned to the GitHub Actions app, id 15368), no merge queue, no bypass actors, "require branches up to date" off. Repository auto-merge is off. Apply with `gh api repos/OWNER/REPO/rulesets --method POST --input ruleset.land.json`. Turn on Settings > Actions > General > "Allow GitHub Actions to create and approve pull requests" for the revert PRs.

## Measured here (GitHub-hosted runners, default GITHUB_TOKEN, 2026-11-17)

All times are wall clock from GitHub's timestamps. The repository is tiny (30 independent modules, `go test ./...` in about a second), so these numbers are the cost of the machinery, not of your tests.

| Case | Result |
| --- | --- |
| One ready PR, evidence attached | Opened to merged in 25 s (PR #4), 21 s (#50). |
| 20 disjoint PRs opened in a 41 s loop (#30 to #49) | 20 of 20 landed. Opened to merged: median 27 s, p90 36 s, max 76 s. First open to last merge: 95 s, about 760 landings an hour while the burst lasted. |
| Merge contention in that burst | 12 of 20 needed a retry: `405 Base branch was modified`. The worst took 7 attempts against a cap of 8, which is why the cap is now 15 with jitter. Landings in one repository are serialised by GitHub itself at roughly 2 to 3 s each. |
| 2 PRs in one module, opened 2 s apart (#50, #51) | The first landed in 21 s. The second failed `land-on-evidence` after 28 s: `overlapping change landed since base (m21); re-run on the new base or stack`. |
| 3 PRs in one module (#52, #53, #54) | The first landed. The second was **cancelled** by the concurrency group (one pending slot) and neither landed nor reported a check; it sits open. The third failed with the overlap message. |
| Cross-module break (#55 lib, #56 api) | Both verified, both disjoint, both landed (23 s and 26 s). Main was red at 18:03:01. A manual dispatch of `post-land` at 18:03:41 found it, bisected to #56, and opened revert PR #57 at 18:04:05 (22 s run). Evidence for the revert and a dispatch of the land workflow: merged 18:04:57. Main green again at the next `post-land` run, 18:06:18. About 2 minutes from break to revert merged, with a person-or-agent doing the dispatches. |
| `post-land` on the schedule | The `*/15` cron fired once at 17:50:04 in the first 25 minutes (the 17:45 slot ran 5 minutes late; the 18:00 slot had not run by 18:05). Treat the schedule as a backstop, not a detector. |

### Problems found while measuring

- A rename's old path was not in the footprint (fixed in #5).
- A PR opened as a draft and marked ready never landed with the default token. 22 of 22 PRs that went through draft then ready were refused at merge with `Required status check "land-on-evidence" is expected`, although the check run existed and was green. Every PR opened ready and not overlapping landed. The failing heads all carried two workflow runs (one from `opened`, one from `ready_for_review`) and so two check suites. I did not establish that this is the cause, so the workflow no longer claims it. A GitHub App posting the check would not involve those suites.
- A merge made by the workflow does not start `push` workflows, as documented. `post-land` therefore ran on a schedule and on dispatch only.

## What it cannot do

- **Production setup needs a GitHub App.** The merge here uses the workflow's `GITHUB_TOKEN`. A merge made with it does not trigger other workflows (so `post-land` runs on its schedule, not on the push), and the required check is pinned only to "the GitHub Actions app", which any workflow in the repository can post as. A GitHub App installation token fixes both: pin the check to the App's id, and its merges trigger `push`. Creating the App and storing its private key is a human step. Nothing here does it.
- **Concurrency groups hold one lock.** A PR touching two modules is serialised on the first one alphabetically only. Two PRs that share only the second module can race. GitHub keeps one running and one pending run per group, so a third PR waiting on one module cancels the second; it never lands and must be re-triggered.
- **Module overlap is not semantic overlap.** Two PRs in different modules can pass their own tests and break each other. Only the post-land test finds that, after the fact.
- **Evidence still names a commit.** A new push needs new evidence.
