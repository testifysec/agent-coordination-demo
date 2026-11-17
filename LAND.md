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

## What it cannot do

- **Production setup needs a GitHub App.** The merge here uses the workflow's `GITHUB_TOKEN`. A merge made with it does not trigger other workflows (so `post-land` runs on its schedule, not on the push), and the required check is pinned only to "the GitHub Actions app", which any workflow in the repository can post as. A GitHub App installation token fixes both: pin the check to the App's id, and its merges trigger `push`. Creating the App and storing its private key is a human step. Nothing here does it.
- **Concurrency groups hold one lock.** A PR touching two modules is serialised on the first one alphabetically only. Two PRs that share only the second module can race. GitHub keeps one running and one pending run per group, so a third PR waiting on one module cancels the second; it never lands and must be re-triggered.
- **Module overlap is not semantic overlap.** Two PRs in different modules can pass their own tests and break each other. Only the post-land test finds that, after the fact.
- **Evidence still names a commit.** A new push needs new evidence.
