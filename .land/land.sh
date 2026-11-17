#!/usr/bin/env bash
# Order: freshness -> evidence -> LOCK every module the PR touches -> overlap -> set the
# land-on-evidence check -> merge -> unlock.
#
# The lock is an atomic git-ref create: `git push --atomic --force-with-lease=<ref>:` per module
# (empty expected value = must not exist). All modules are taken in one atomic push, or none, so
# there is no hold-and-wait and no deadlock. It is held from the overlap check through the merge,
# then deleted with a lease on our own sha. A lock carries an expiry; a crashed run's lock is taken
# over by compare-and-swap on the exact sha that was read. Contention waits with jitter up to
# LOCK_WAIT seconds, then fails the check with a message. Nothing is cancelled silently.
set -u
LOCK_WAIT=${LOCK_WAIT:-300}   # seconds to wait for the modules
LOCK_LEASE=${LOCK_LEASE:-120} # seconds a lock stays valid; a landing takes about 10
export GIT_AUTHOR_NAME=land GIT_AUTHOR_EMAIL=land@users.noreply.github.com
export GIT_COMMITTER_NAME=land GIT_COMMITTER_EMAIL=land@users.noreply.github.com

report() { # conclusion title summary
  gh api "repos/$REPO/check-runs" -f name=land-on-evidence -f head_sha="$HEAD_SHA" \
    -f status=completed -f conclusion="$1" -f "output[title]=$2" -f "output[summary]=$3" \
    -f details_url="$RUN_URL" > /dev/null
}


declare -A MY=()   # lock ref -> the sha of the lock commit we created

lock_ref() { printf 'refs/locks/m-%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; }

lock_commit() { # module -> sha of a one-off commit recording who holds the lock and until when
  git commit-tree "$(git hash-object -t tree -w /dev/null)" -m "lock $1
holder: $RUN_URL pr=$PR
expires-epoch: $(( $(date +%s) + LOCK_LEASE ))"
}

acquire() { # modules (space separated) -> 0 held, 1 timed out (BLOCKED_BY set)
  local deadline=$(( $(date +%s) + LOCK_WAIT )) m ref cur exp leases args blocked
  while :; do
    git fetch -q --prune origin '+refs/locks/*:refs/remotes/locks/*' 2>/dev/null || true
    leases=(); args=(); blocked=""; MY=()
    for m in $1; do   # $1 is already sorted
      ref=$(lock_ref "$m")
      cur=$(git rev-parse -q --verify "refs/remotes/locks/${ref#refs/locks/}" 2>/dev/null || true)
      if [ -n "$cur" ]; then
        exp=$(git log -1 --format=%B "$cur" | sed -n 's/^expires-epoch: //p')
        if [ "${exp:-0}" -gt "$(date +%s)" ]; then
          blocked="$blocked $m($(git log -1 --format=%B "$cur" | sed -n 's/^holder: //p'))"; continue
        fi
      fi
      MY[$ref]=$(lock_commit "$m")
      leases+=(--force-with-lease="$ref:$cur")   # empty $cur: must not exist; else compare-and-swap on the expired holder
      args+=("${MY[$ref]}:$ref")
    done
    if [ -z "$blocked" ] && git push -q --atomic "${leases[@]}" origin "${args[@]}" 2>/dev/null; then return 0; fi
    BLOCKED_BY=${blocked:-"a concurrent claim"}
    if [ "$(date +%s)" -ge "$deadline" ]; then MY=(); return 1; fi
    sleep $((1 + RANDOM % 3))
  done
}

release() {
  [ ${#MY[@]} -gt 0 ] || return 0
  local a=() l=() ref
  for ref in "${!MY[@]}"; do l+=(--force-with-lease="$ref:${MY[$ref]}"); a+=(":$ref"); done
  git push -q --atomic "${l[@]}" origin "${a[@]}" 2>/dev/null || echo "::warning::lock release failed; it expires on its own"
  MY=()
}
trap release EXIT

modules_of() { awk -F/ '{ if (NF > 1) print $1; else print "(root)" }' | sort -u; }

cur=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,state --jq '.state + " " + .headRefOid')
if [ "$cur" != "OPEN $HEAD_SHA" ]; then
  echo "PR #$PR moved on ($cur); a newer event owns it"; exit 0
fi

if [ "$VERIFIED" != true ]; then
  report failure "No verified evidence" "No signed test evidence for ${HEAD_SHA:0:10} verified against the policy on main. Run the tests under cilock, publish refs/evidence/<sha>, push."
  echo "::error::PR #$PR: no verified evidence"; exit 1
fi

# Take every module this PR touches, together, before looking at main.
mods_sorted=$(printf '%s\n' $MODULES | sort -u | tr '\n' ' ' | sed 's/ $//')
t_lock=$(date +%s)
if ! acquire "$mods_sorted"; then
  report failure "Could not take the landing lock" "Waited ${LOCK_WAIT}s for module lock(s) held by:${BLOCKED_BY}. Nothing was merged. Push again or re-run the workflow for this PR."
  echo "::error::PR #$PR: could not lock [$mods_sorted] within ${LOCK_WAIT}s; held by:${BLOCKED_BY}"; exit 1
fi
echo "locked [$mods_sorted] after $(( $(date +%s) - t_lock ))s"

# Files that landed on main since this PR's merge base, as modules (inside the lock).
main_mods=$(gh api "repos/$REPO/compare/${HEAD_SHA}...main" --paginate --jq '.files[] | .filename, (.previous_filename // empty)' | modules_of)
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
until [ $attempts -ge 15 ]; do
  attempts=$((attempts + 1))
  if resp=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=merge -f sha="$HEAD_SHA" 2>&1); then
    echo "LANDED pr=$PR attempts=$attempts at=$(date -u +%FT%TZ)"; exit 0
  fi
  echo "merge attempt $attempts: $(printf '%s' "$resp" | head -c 200)"
  sleep $((1 + RANDOM % 4))
done
echo "::error::PR #$PR verified but the merge failed after $attempts attempts"; exit 1
