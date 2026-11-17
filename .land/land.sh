#!/usr/bin/env bash
# Runs inside the per-module concurrency group, so landings in one module are serial.
# Order: freshness -> evidence -> overlap -> set the land-on-evidence check -> merge.
set -u

report() { # conclusion title summary
  gh api "repos/$REPO/check-runs" -f name=land-on-evidence -f head_sha="$HEAD_SHA" \
    -f status=completed -f conclusion="$1" -f "output[title]=$2" -f "output[summary]=$3" \
    -f details_url="$RUN_URL" > /dev/null
}

modules_of() { awk -F/ '{ if (NF > 1) print $1; else print "(root)" }' | sort -u; }

cur=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,state --jq '.state + " " + .headRefOid')
if [ "$cur" != "OPEN $HEAD_SHA" ]; then
  echo "PR #$PR moved on ($cur); a newer event owns it"; exit 0
fi

if [ "$VERIFIED" != true ]; then
  report failure "No verified evidence" "No signed test evidence for ${HEAD_SHA:0:10} verified against the policy on main. Run the tests under cilock, publish refs/evidence/<sha>, push."
  echo "::error::PR #$PR: no verified evidence"; exit 1
fi

# Files that landed on main since this PR's merge base, as modules.
main_mods=$(gh api "repos/$REPO/compare/${HEAD_SHA}...main" --paginate --jq '.files[].filename' | modules_of)
pr_mods=$(printf '%s\n' $MODULES | sort -u)
overlap=$(comm -12 <(printf '%s\n' "$pr_mods") <(printf '%s\n' "$main_mods") | tr '\n' ' ' | sed 's/ $//')
if [ -n "$overlap" ]; then
  report failure "Overlapping change landed" "overlapping change landed since base ($overlap); re-run on the new base or stack"
  echo "::error::PR #$PR: overlapping change landed since base ($overlap); re-run on the new base or stack"; exit 1
fi

report success "Evidence verified, no overlap" "Verified evidence for ${HEAD_SHA:0:10}; modules [$MODULES] untouched on main since the merge base."

# Merge exactly the verified head. Concurrent merges to main answer 405/409 ("base branch was
# modified" or the check not visible yet); retry a few times.
attempts=0
until [ $attempts -ge 8 ]; do
  attempts=$((attempts + 1))
  if resp=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=merge -f sha="$HEAD_SHA" 2>&1); then
    echo "LANDED pr=$PR attempts=$attempts at=$(date -u +%FT%TZ)"; exit 0
  fi
  echo "merge attempt $attempts: $(printf '%s' "$resp" | head -c 200)"
  sleep $((attempts * 2))
done
echo "::error::PR #$PR verified but the merge failed after $attempts attempts"; exit 1
