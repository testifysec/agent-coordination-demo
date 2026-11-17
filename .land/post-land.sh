#!/usr/bin/env bash
# Test main. Red: binary-search the first-parent commits since the last green run, then open a
# revert PR for the first bad one. Green: the run's success is the new "last green" marker.
set -u
REPO=$GITHUB_REPOSITORY
HEAD=$(git rev-parse HEAD)

LAST_GREEN=$(gh run list --repo "$REPO" --workflow post-land.yml --status success --limit 1 \
  --json headSha --jq '.[0].headSha // empty')
if [ -z "$LAST_GREEN" ] || ! git cat-file -e "${LAST_GREEN}^{commit}" 2>/dev/null; then
  LAST_GREEN=$(git rev-list --max-parents=0 HEAD | tail -1)
fi
if [ "$LAST_GREEN" = "$HEAD" ]; then echo "main unchanged since the last green run"; exit 0; fi

start=$(date +%s)
if go test ./...; then echo "main is green at ${HEAD:0:10} ($(( $(date +%s) - start ))s)"; exit 0; fi
echo "::error::main is RED at ${HEAD:0:10}; bisecting ${LAST_GREEN:0:10}..${HEAD:0:10}"

mapfile -t C < <(git rev-list --first-parent --reverse "$LAST_GREEN..$HEAD")
lo=-1; hi=$(( ${#C[@]} - 1 ))          # C[hi] is red; index -1 stands for LAST_GREEN
while [ $((hi - lo)) -gt 1 ]; do
  mid=$(( (lo + hi) / 2 ))
  git checkout -q --detach "${C[$mid]}"
  if go test ./... > /dev/null 2>&1; then lo=$mid; else hi=$mid; fi
  echo "bisect: ${C[$mid]:0:10} -> $([ $lo = $mid ] && echo green || echo red)"
done
BAD=${C[$hi]}
SUBJECT=$(git log -1 --format=%s "$BAD")
echo "::error::first bad commit on main: ${BAD:0:10} ($SUBJECT)"

BR="revert-${BAD:0:10}"
if [ -n "$(gh pr list --repo "$REPO" --head "$BR" --state open --json number --jq '.[0].number')" ]; then
  echo "revert PR already open for $BR"; exit 1
fi
git config user.name  "post-land"
git config user.email "post-land@users.noreply.github.com"
git checkout -q --detach "$HEAD"
git switch -q -c "$BR"
if [ "$(git rev-list --parents -n1 "$BAD" | wc -w)" -gt 2 ]; then git revert --no-edit -m 1 "$BAD"; else git revert --no-edit "$BAD"; fi
git push -q origin "HEAD:refs/heads/$BR"
gh pr create --repo "$REPO" --base main --head "$BR" --title "Revert: $SUBJECT (main red after it landed)" \
  --body "post-land found main red at ${HEAD:0:10}. Bisecting the first-parent commits since the last green run (${LAST_GREEN:0:10}) names ${BAD:0:10} as the first bad one. This PR reverts it. It carries no evidence, so it cannot land until someone tests it under cilock and pushes the evidence."
exit 1
