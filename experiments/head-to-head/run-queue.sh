#!/usr/bin/env bash
# usage: run-queue.sh <tag> <N> <allgreen|headgreen> <pool_ci> <pool_mq> [timeout_s]
# Arm A. N pairwise-disjoint PRs on main-queue, all opened as fast as the API allows, each set to auto-merge.
# Every PR CI job and every merge-queue build job holds a token (pool ci / pool mq) for T seconds.
set -u
TAG=$1; N=$2; VAR=$3; PCI=$4; PMQ=$5; TMO=${6:-5400}
V=${EXP_DIR:?set EXP_DIR to a work directory}
W=$V/work; R=testifysec/agent-coordination-demo
export RUNTAG=$TAG
cd "$W/repo"
bash "$V/harness/queue-ruleset.sh" "$VAR" > /dev/null
gh variable set POOL_CI --repo $R --body "$PCI"; gh variable set POOL_MQ --repo $R --body "$PMQ"; gh variable set RUNTAG --repo $R --body "$TAG"
for r in $(git ls-remote origin 'refs/tokens/ci/*' 'refs/tokens/mq/*' | awk '{print $2}'); do git push -q origin ":$r" 2>/dev/null; done
git fetch -q origin main-queue; BASE=$(git rev-parse origin/main-queue)
git config user.email exp@users.noreply.github.com; git config user.name exp
# N branches, each in its own new directory
specs=()
for i in $(seq -w 1 "$N"); do
  git switch -q --detach "$BASE"; mkdir -p "$TAG-$i"; echo "$TAG $i" > "$TAG-$i/f.txt"; git add -A
  git commit -q -m "$TAG change $i"; git branch -q -f "rt-$TAG-$i" HEAD; specs+=("rt-$TAG-$i:refs/heads/rt-$TAG-$i")
done
git push -q origin "${specs[@]}" 2>/dev/null
t0=$(date +%s); echo "$t0" > "$V/out/$TAG.t0"; echo "$BASE" > "$V/out/$TAG.base"
echo "run $TAG start $(date -u +%T) N=$N $VAR split ci=$PCI mq=$PMQ"
: > "$V/out/$TAG.prs"
for i in $(seq -w 1 "$N"); do
  url=$(gh pr create --repo $R --base main-queue --head "rt-$TAG-$i" --title "$TAG $i" --body "experiment $TAG" 2>/dev/null)
  n=${url##*/}
  gh pr merge "$n" --repo $R --auto > /dev/null 2>&1 || echo "auto-merge failed for $n"
  echo "$TAG-$i pr=$n opened=$(date +%s)" >> "$V/out/$TAG.prs"
done
echo "all opened $(date -u +%T) ($(( $(date +%s) - t0 )) s)"
deadline=$(( $(date +%s) + TMO ))
while :; do
  git fetch -q origin main-queue 2>/dev/null
  n=$(git rev-list --count --first-parent "$BASE..origin/main-queue" 2>/dev/null || echo 0)
  [ "$n" -ge "$N" ] && break
  [ "$(date +%s)" -ge "$deadline" ] && { echo "TIMEOUT with $n of $N landed"; break; }
  sleep 15
done
echo "run $TAG end $(date -u +%T): $n of $N landed"
