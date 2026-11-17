---
name: agent-coordination
description: Rules for an agent working in a repo where tests run once, on the agent's machine, under CI/lock (cilock), and CI verifies the signed record instead of re-running them. Use before starting any change, when pushing, and when a claim overlaps another agent's.
---

# Agent coordination: test once, sign it, claim before you start

Paste this into a Claude Code skill, Codex or Cursor rules, or AGENTS.md. Set these once per repo:

```sh
# Shell variables the commands below use. Adjust the test command to your repo.
REMOTE=origin
ME=$(git config user.name)                 # your handle in claim messages
CILOCK_KEY=$HOME/.config/cilock/agent.key  # your signing key (see SETTINGS.md)
TEST_CMD='go test ./...'                   # must match expected_cmd in .cilock/policy.rego
LEASE_MIN=15                               # about one full test run, rounded up
```

Claims are advisory. Nothing stops an agent that ignores them. What makes them safe is the gate: CI admits a pull request without re-running tests only if the signed evidence names its exact head commit and satisfies the policy. A skipped claim costs you a failed gate and a rerun, never a bad merge.

## 1. Before you start: compute your footprint and claim it

The footprint is the packages (directories) you will change plus the packages whose tests import them.

```sh
git fetch $REMOTE main
CHANGED=$(git diff --name-only $REMOTE/main...HEAD | xargs -n1 dirname | sort -u)   # directories you touch
# Go example: each changed package plus every package whose code or tests import it. Adapt for your language.
go list -f '{{.ImportPath}} {{join .Imports " "}} {{join .TestImports " "}} {{join .XTestImports " "}}' ./... > /tmp/imports.txt
MODPATH=$(go list -m)
for d in $CHANGED; do
  p=$MODPATH/$d; [ "$d" = . ] && p=$MODPATH
  echo "$p"
  awk -v p="$p" '{for(i=2;i<=NF;i++) if($i==p){print $1;break}}' /tmp/imports.txt
done | sort -u
```

Write the footprint as a short list of module names (`pkg/auth`, `cmd/api`). Claim every one, in sorted order. Two stores work; pick one per repo and say which in AGENTS.md.

### Option A: atomic git ref (no GitHub API, no polling)

A claim is a commit on `refs/claims/<module>` whose message says who, which branch, and when the lease ends. Creating the ref is atomic: the push is a compare-and-swap, so exactly one agent wins.

```sh
new_claim() {  # $1=module -> prints the sha of a claim commit
  local tree; tree=$(git hash-object -t tree -w /dev/null)
  git commit-tree "$tree" -m "claim $1
agent: $ME
branch: $(git branch --show-current)
expires: $(python3 -I -c "import datetime as d;print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=$LEASE_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
}

# Claim one or more modules, all or nothing. An empty expected value means "must not exist".
MODS="pkg/auth pkg/session"
ARGS=(); LEASES=()
for m in $MODS; do ARGS+=("$(new_claim $m):refs/claims/$m"); LEASES+=(--force-with-lease="refs/claims/$m:"); done
git push --atomic "${LEASES[@]}" $REMOTE "${ARGS[@]}" && echo GRANTED || echo DENIED
```

On DENIED, read who holds it. Do not retry in a loop.

```sh
m=pkg/auth
git fetch -q $REMOTE "+refs/claims/$m:refs/remotes/claims/$m" && git log -1 --format=%B refs/remotes/claims/$m
```

Take over an expired claim with a lease on the exact value you read, so two takeovers cannot both win:

```sh
OLD=$(git rev-parse refs/remotes/claims/$m)
git push --force-with-lease="refs/claims/$m:$OLD" $REMOTE "$(new_claim $m):refs/claims/$m"
```

Renew by the same command with `OLD` set to your own current claim. Release only your own claim:

```sh
git fetch -q $REMOTE "+refs/claims/$m:refs/remotes/claims/$m"
MINE=$(git rev-parse refs/remotes/claims/$m)       # check the message says agent: $ME first
git push --force-with-lease="refs/claims/$m:$MINE" $REMOTE ":refs/claims/$m"
```

### Option B: GitHub issue per claim (visible to humans, not atomic)

One open issue titled `claim: <module>` with the label `claim` is the claim. Two agents can still create one at the same moment, so check again after you create yours and the lower issue number wins.

```sh
m=pkg/auth
gh label create claim --color BFD4F2 2>/dev/null || true                 # once per repo
gh issue list --label claim --state open --search "claim: $m in:title" --json number,title,body --jq '.[]'
gh issue create --label claim --title "claim: $m" \
  --body "agent: $ME
branch: $(git branch --show-current)
expires: $(python3 -I -c "import datetime as d;print((d.datetime.now(d.timezone.utc)+d.timedelta(minutes=$LEASE_MIN)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
gh issue close <number> --reason completed --comment "landed in <PR url>"   # release
```

Read GitHub once per decision. Do not poll it to wait for a claim to clear.

## 2. If an overlapping claim is in flight: stack, do not race and do not wait

Read the holder's `branch:` line. Branch from it and build on top. Claim your own non-overlapping modules as usual, and note `base: <their branch>` in your PR description.

```sh
git fetch $REMOTE <their-branch>
git switch -c my-change $REMOTE/<their-branch>
```

If their branch fails the gate, or changes after you branched, rebase onto the corrected base and run the tests again. A rebase makes new commits, and evidence for the old commits does not cover them.

```sh
git fetch $REMOTE <their-branch> && git rebase $REMOTE/<their-branch>
```

When theirs lands, rebase onto `main`, run once more, push. Two sequential single runs beat one race and one re-run.

## 3. Test once, under cilock, on a clean commit

Commit first. Evidence names a commit, so uncommitted changes would be tested but not recorded.

```sh
test -z "$(git status --porcelain)" || { echo "commit or stash first"; exit 1; }
SHA=$(git rev-parse HEAD)
cilock run --step test -k "$CILOCK_KEY" -a environment,git --workload manual --platform-url "" \
  -o "/tmp/evidence-$SHA.json" -- $TEST_CMD
```

- `--step test` must equal the step name in `.cilock/policy.json`.
- A failing suite still writes a signed record (the exit code is inside it) and `cilock run` exits 1. That record is the proof of the attempt. The gate will refuse it.
- Never edit, skip, narrow or delete tests to turn a run green, and never change `$TEST_CMD` (`-run`, `-short`, `|| true`). The policy pins the command and refuses runs with no passing test line, so a narrowed run is refused anyway. Fix the code.
- Keep every attempt. Do not delete evidence files and do not rerun the same commit hoping for green. If it is flaky, say so in the PR. A rerun with no code change gets a new record, and you report both.

## 4. Push the branch and the evidence together

Evidence lives in a ref next to the branch, as a one-file commit, so it never changes the commit it describes.

```sh
SHA=$(git rev-parse HEAD)
BLOB=$(git hash-object -w "/tmp/evidence-$SHA.json")
TREE=$(printf '100644 blob %s\tevidence.json\n' "$BLOB" | git mktree)
EV=$(git commit-tree "$TREE" -m "cilock evidence for $SHA")
git update-ref "refs/evidence/$SHA" "$EV"
git push $REMOTE "HEAD:refs/heads/$(git branch --show-current)" "refs/evidence/$SHA:refs/evidence/$SHA"
gh pr create --fill
```

If you push a new commit, the old evidence does not apply. Go back to step 3.

## 5. Land through the normal PR and the evidence check

If the repository lands on evidence (see `LAND.md`), there is no label and no merge queue: opening or pushing a ready PR is the signal, and a draft means "not ready". Push the evidence first, then open the PR ready. Do not open it as a draft and mark it ready later; with the default token that PR never lands. If the check says `overlapping change landed since base`, rebase onto the new base, run step 3 again, and push.

CI verifies the evidence for the head commit and skips its own test job when it passes. If it does not verify, CI runs the tests. Either way the required check is `ci`. The merge queue always runs the full suite once on the merged result.

In a merge-queue repository only (not land on evidence, which merges for you):

```sh
gh pr merge --auto
```

Release every claim when the PR merges, closes, or you give up (commands in step 1). Do not hold a claim past its lease while idle.

## 6. Idle, handoff, and splitting

- Idle or blocked: release your claims, push the branch, and write what is done and what is left in the PR description. Another agent can stack on it.
- Your lease ran out mid-test: renew first, then continue. Renewing is the same push with your own sha as the lease.
- If a module's claim keeps showing up with several agents queued behind it (more than two stacked branches on one claim), propose splitting the module. Open an issue naming the files that change together and the files that do not.

## What this does not do

- It does not make an agent honest. A file key proves "someone holding this key ran this command on this commit", not which agent or on what machine. For a platform-issued agent identity, see SETTINGS.md.
- It does not replace the merge queue. The merged commit is new and is tested once there.
