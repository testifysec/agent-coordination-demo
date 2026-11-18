#!/usr/bin/env bash
# usage: run-agents.sh <tag> <N> <M> <disjoint|samemodule> [timeout_s]
# Arm B. N local "agents", at most M of them holding a test token at once. Each agent: make a change,
# run `cilock run -- sleep 120` under a token, publish evidence, push, open a PR. land-on-evidence merges.
set -u
TAG=$1; N=$2; M=$3; MODE=$4; TMO=${5:-5400}
V=${EXP_DIR:?set EXP_DIR to a work directory}
W=$V/work; DK=${KEY_DIR:-$HOME/.config/cilock}
R=${R:-OWNER/REPO}; URL=https://github.com/$R.git
export PATH="${CILOCK_DIR:-$HOME/.local/bin}:$PATH"
export RUNTAG=$TAG SEM_POLL=6 SEM_JIT=5
mkdir -p "$W/wt" "$V/out"
cd "$W/repo"
# clean slate for this run's pools
for r in $(git ls-remote origin 'refs/tokens/agent/*' 'refs/tokens/claim/*' | awk '{print $2}'); do git push -q origin ":$r" 2>/dev/null; done
git fetch -q origin land-b
BASE=$(git rev-parse origin/land-b)
t0=$(date +%s); echo "$t0" > "$V/out/$TAG.t0"; echo "$BASE" > "$V/out/$TAG.base"
echo "run $TAG start $(date -u +%T) N=$N M=$M mode=$MODE base=${BASE:0:8}"

agent() {
  local i=$1 d="$W/wt/$TAG-$i" br="rt-$TAG-$i" t_a
  rm -rf "$d"
  t_a=$(date +%s)
  if [ "$MODE" = samemodule ]; then
    git clone -q --depth 1 --branch land-b "$URL" "$d" 2>/dev/null   # placeholder to get a repo for the claim
    cd "$d"; . "$V/harness/sem.sh"
    export HOLDER="agent-$i"; SEM_LEASE=900
    sem_acquire claim 1; CLAIM_REF=$SEM_REF; CLAIM_C=$SEM_C; SEM_LEASE=600
    local t_claim=$(date +%s)
    git fetch -q --depth 1 origin land-b; git reset -q --hard origin/land-b   # fresh tip after the claim
  else
    git clone -q --depth 1 --branch land-b "$URL" "$d" 2>/dev/null
    cd "$d"; . "$V/harness/sem.sh"; export HOLDER="agent-$i"; local t_claim=$t_a
  fi
  git config user.email agent@users.noreply.github.com; git config user.name "agent $i"
  git switch -q -c "$br"
  if [ "$MODE" = samemodule ]; then mkdir -p hot; echo "$TAG $i" > "hot/$TAG-$i.txt"; else mkdir -p "$TAG-$i"; echo "$TAG $i" > "$TAG-$i/f.txt"; fi
  git add -A; git commit -q -m "$TAG change $i

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
  local sha; sha=$(git rev-parse HEAD)
  sem_acquire agent "$M"; local tok_ref=$SEM_REF tok_c=$SEM_C acq=$SEM_ACQ
  cilock run --step test -k "$DK/agent.key" -a environment,git --workload manual --platform-url "" \
    -o "$d/../ev-$TAG-$i.json" -- sleep 120 > "$d/../run-$TAG-$i.log" 2>&1
  sem_release; local rel=$SEM_REL
  rec "kind=agent" "pool=agent" "job_start=$t_claim" "acq=$acq" "rel=$rel" "wait=$((acq - t_claim))" "held=$((rel - acq))"
  local blob tree ev
  blob=$(git hash-object -w "$d/../ev-$TAG-$i.json"); tree=$(printf '100644 blob %s\tevidence.json\n' "$blob" | git mktree)
  ev=$(git commit-tree "$tree" -m "cilock evidence for $sha"); git update-ref "refs/evidence/$sha" "$ev"
  git push -q origin "HEAD:refs/heads/$br" "refs/evidence/$sha:refs/evidence/$sha" 2>/dev/null
  local url; url=$(gh pr create --repo $R --base land-b --head "$br" --title "$TAG $i" --body "experiment $TAG" 2>/dev/null)
  echo "$TAG-$i pr=${url##*/} opened=$(date +%s)" >> "$V/out/$TAG.prs"
  if [ "$MODE" = samemodule ]; then
    local waited=0 landed=0
    while [ $waited -lt 900 ]; do
      git fetch -q --depth 50 origin land-b 2>/dev/null
      if git merge-base --is-ancestor "$sha" origin/land-b 2>/dev/null; then landed=1; break; fi
      sleep 3; waited=$((waited + 3))
    done
    [ $landed = 1 ] || rec "kind=not_landed" "agent=$i"
    SEM_REF=$CLAIM_REF; SEM_C=$CLAIM_C; sem_release     # release the claim
  fi
}

PIDS=()
for i in $(seq -w 1 "$N"); do agent "$i" & PIDS+=($!); sleep 0.3; done

# wait until N merge commits are on land-b, or timeout
deadline=$(( $(date +%s) + TMO ))
while :; do
  git fetch -q origin land-b 2>/dev/null
  n=$(git log --first-parent --format=%s "$BASE..origin/land-b" 2>/dev/null | grep -c "rt-$TAG-")
  [ "$n" -ge "$N" ] && break
  [ "$(date +%s)" -ge "$deadline" ] && { echo "TIMEOUT with $n of $N landed"; break; }
  sleep 15
done
echo "run $TAG end $(date -u +%T): $n of $N landed"
kill "${PIDS[@]}" 2>/dev/null; wait 2>/dev/null
