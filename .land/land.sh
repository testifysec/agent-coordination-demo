#!/usr/bin/env bash
# usage: land.sh check | merge | release | all
#
#   check    lock every module the PR touches, then look for an overlapping change on main.
#            The job running this IS the required check `land-on-evidence`: exit 0 = green.
#            On success the locks stay held for the merge job.
#   merge    PUT /pulls/{n}/merge for exactly the verified head, then release the locks.
#   release  delete the locks this run holds (the merge job's backstop, run with if: always()).
#   all      check + a REST check run + merge in one process. Used for dispatch and push runs,
#            which have no pull_request event whose job could be the check.
#
# Lock: an atomic git-ref create, `git push --atomic --force-with-lease=<ref>:` per module (empty
# expected value = must not exist). All modules in one atomic push or none, so no hold-and-wait and
# no deadlock. Held from the overlap check through the merge. Each lock carries an expiry; a crashed
# run's lock is taken over by compare-and-swap on the sha that was read. Contention waits with
# jitter up to LOCK_WAIT seconds, then fails. Nothing is cancelled silently.
set -uf   # -f: module names are never globbed
LOCK_WAIT=${LOCK_WAIT:-300}    # seconds to wait for the modules
LOCK_LEASE=${LOCK_LEASE:-120}  # seconds a lock stays valid; a landing takes about 10
export GIT_AUTHOR_NAME=land GIT_AUTHOR_EMAIL=land@users.noreply.github.com
export GIT_COMMITTER_NAME=land GIT_COMMITTER_EMAIL=land@users.noreply.github.com
HOLDER="$RUN_URL pr=$PR"

fail() { # title message   (the message is the annotation on the check)
  echo "::error title=$1::$2"
  printf '%s' "$2" > "${RUNNER_TEMP:-/tmp}/land-fail.txt"
  { echo "### $1"; echo "$2"; } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 1
}

report() { # conclusion title summary   (REST check run; only for mode `all`)
  gh api "repos/$REPO/check-runs" -f name=land-on-evidence -f head_sha="$HEAD_SHA" \
    -f status=completed -f conclusion="$1" -f "output[title]=$2" -f "output[summary]=$3" \
    -f details_url="$RUN_URL" > /dev/null
}

modules_of() { awk -F/ '{ if (NF > 1) print $1; else print "(root)" }' | sort -u; }

lock_ref() { printf 'refs/locks/m-%s' "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')"; }

lock_commit() { # module -> sha of a one-off commit recording who holds the lock and until when
  git commit-tree "$(git hash-object -t tree -w /dev/null)" -m "lock $1
holder: $HOLDER
expires-epoch: $(( $(date +%s) + LOCK_LEASE ))"
}

acquire() { # modules (sorted, space separated) -> 0 held, 1 timed out (BLOCKED_BY set)
  local deadline=$(( $(date +%s) + LOCK_WAIT )) m ref cur exp leases args blocked
  while :; do
    git fetch -q --prune origin '+refs/locks/*:refs/remotes/locks/*' 2>/dev/null || true
    leases=(); args=(); blocked=""
    for m in $1; do
      ref=$(lock_ref "$m")
      cur=$(git rev-parse -q --verify "refs/remotes/locks/${ref#refs/locks/}" 2>/dev/null || true)
      if [ -n "$cur" ]; then
        exp=$(git log -1 --format=%B "$cur" | sed -n 's/^expires-epoch: //p')
        if [ "${exp:-0}" -gt "$(date +%s)" ]; then
          blocked="$blocked $m($(git log -1 --format=%B "$cur" | sed -n 's/^holder: //p'))"; continue
        fi
      fi
      leases+=(--force-with-lease="$ref:$cur")   # empty $cur: must not exist; else compare-and-swap over the expired holder
      args+=("$(lock_commit "$m"):$ref")
    done
    if [ -z "$blocked" ] && git push -q --atomic "${leases[@]}" origin "${args[@]}" 2>/dev/null; then return 0; fi
    BLOCKED_BY=${blocked:-"a concurrent claim"}
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep $((1 + RANDOM % 3))
  done
}

release_mine() { # delete every lock whose holder line is this run + PR, with a lease on the sha we read
  git fetch -q --prune origin '+refs/locks/*:refs/remotes/locks/*' 2>/dev/null || true
  local l=() a=() sha ref
  while read -r sha ref; do
    git log -1 --format=%B "$sha" | grep -qxF "holder: $HOLDER" || continue
    l+=(--force-with-lease="refs/locks/${ref#refs/remotes/locks/}:$sha"); a+=(":refs/locks/${ref#refs/remotes/locks/}")
  done < <(git for-each-ref --format='%(objectname) %(refname)' refs/remotes/locks)
  [ ${#a[@]} -eq 0 ] && return 0
  git push -q --atomic "${l[@]}" origin "${a[@]}" 2>/dev/null || echo "::warning::lock release failed; it expires on its own"
}

merge_head() {
  local attempts=0 resp
  until [ $attempts -ge 15 ]; do
    attempts=$((attempts + 1))
    if resp=$(gh api -X PUT "repos/$REPO/pulls/$PR/merge" -f merge_method=merge -f sha="$HEAD_SHA" 2>&1); then
      echo "LANDED pr=$PR attempts=$attempts at=$(date -u +%FT%TZ)"; return 0
    fi
    echo "merge attempt $attempts: $(printf '%s' "$resp" | head -c 200)"
    sleep $((1 + RANDOM % 4))
  done
  return 1
}

check() { # sets nothing; exit 0 = this head may land, locks held
  [ "${DRAFT:-false}" != true ] || fail "Draft" "A draft is not ready to land. Mark it ready for review."
  cur=$(gh pr view "$PR" --repo "$REPO" --json headRefOid,state --jq '.state + " " + .headRefOid')
  case "$cur" in
    "OPEN $HEAD_SHA") ;;
    MERGED*) echo "PR #$PR is already merged"; echo "proceed=false" >> "${GITHUB_OUTPUT:-/dev/null}"; exit 0 ;;
    *) fail "Head moved" "The head changed (now: $cur). A newer run owns this PR." ;;
  esac
  [ "$VERIFIED" = true ] || fail "No verified evidence" \
    "No signed test evidence for ${HEAD_SHA:0:10} verified against the policy on main. Run the tests under cilock, publish refs/evidence/<sha>, push."

  mods_sorted=$(printf '%s\n' $MODULES | sort -u | tr '\n' ' ' | sed 's/ $//')
  t_lock=$(date +%s)
  acquire "$mods_sorted" || fail "Could not take the landing lock" \
    "Waited ${LOCK_WAIT}s for module lock(s) held by:${BLOCKED_BY}. Nothing was merged. Push again or re-run."
  echo "locked [$mods_sorted] after $(( $(date +%s) - t_lock ))s"

  main_mods=$(gh api "repos/$REPO/compare/${HEAD_SHA}...main" --paginate \
    --jq '.files[] | .filename, (.previous_filename // empty)' | modules_of)
  overlap=$(comm -12 <(printf '%s\n' $mods_sorted) <(printf '%s\n' "$main_mods") | tr '\n' ' ' | sed 's/ $//')
  if [ -n "$overlap" ]; then
    release_mine
    fail "Overlapping change landed" "overlapping change landed since base ($overlap); re-run on the new base or stack"
  fi
  echo "proceed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "verified evidence, no overlap in [$mods_sorted]"
}

case "${1:-}" in
  check)   check ;;
  merge)   trap release_mine EXIT; merge_head || fail "Merge failed" "Verified, but the merge failed after 15 attempts." ;;
  release) release_mine ;;
  all)
    trap release_mine EXIT
    ( check ) && rc=0 || rc=$?
    if [ $rc -ne 0 ]; then report failure "Not landed" "$(cat "${RUNNER_TEMP:-/tmp}/land-fail.txt" 2>/dev/null || echo "see $RUN_URL")"; exit 1; fi
    [ "$(gh pr view "$PR" --repo "$REPO" --json state --jq .state)" = OPEN ] || exit 0
    report success "Evidence verified, no overlap" "Verified evidence for ${HEAD_SHA:0:10}; modules [$MODULES] untouched on main since the merge base."
    merge_head || fail "Merge failed" "Verified, but the merge failed after 15 attempts."
    ;;
  *) echo "usage: land.sh check|merge|release|all" >&2; exit 2 ;;
esac
