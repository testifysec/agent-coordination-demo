#!/usr/bin/env bash
# For each candidate PR: is it open, ready, aimed at main? Does its head carry evidence that
# verifies against the policy on main? Which modules does it touch? Writes one JSON array to
# $GITHUB_OUTPUT as prs=[{pr,head,verified,group,modules}].
# A module is the top-level directory of a changed file ("(root)" for files at the top).
set -u

modules_of() { awk -F/ '{ if (NF > 1) print $1; else print "(root)" }' | sort -u; }

if [ -n "${PR_EVENT:-}" ]; then LIST=$PR_EVENT
elif [ -n "${PR_INPUT:-}" ]; then LIST=$PR_INPUT
else LIST=$(gh pr list --repo "$REPO" --state open --base main --json number,isDraft --jq '.[]|select(.isDraft|not)|.number')
fi

out='[]'
for pr in $LIST; do
  info=$(gh pr view "$pr" --repo "$REPO" --json headRefOid,state,isDraft,baseRefName) || continue
  [ "$(jq -r .state <<<"$info")" = OPEN ] || continue
  [ "$(jq -r .isDraft <<<"$info")" = false ] || continue
  [ "$(jq -r .baseRefName <<<"$info")" = main ] || continue
  head=$(jq -r .headRefOid <<<"$info")

  verified=false
  if [ -f .cilock/policy.signed.json ] && git fetch -q --depth=1 origin "refs/evidence/$head" 2>/dev/null; then
    git show FETCH_HEAD:evidence.json > "$RUNNER_TEMP/evidence-$pr.json"
    # Gate on the exit code. Never pipe verify.
    if cilock verify -p .cilock/policy.signed.json -k .cilock/policy.pub \
         -a "$RUNNER_TEMP/evidence-$pr.json" --subjects "sha1:$head" --platform-url "" \
         --format json > "$RUNNER_TEMP/verdict-$pr.json" 2> "$RUNNER_TEMP/verify-$pr.err"; then
      [ "$(jq -r .passed "$RUNNER_TEMP/verdict-$pr.json")" = true ] && verified=true
    else
      grep -E 'collection rejected|no passed collections|failed to' "$RUNNER_TEMP/verify-$pr.err" | head -3 || true
    fi
  fi

  files=$(gh api "repos/$REPO/pulls/$pr/files" --paginate --jq '.[].filename')
  mods=$(modules_of <<<"$files" | tr '\n' ' ' | sed 's/ $//')
  # One concurrency group per module; the alphabetically first module names the group.
  # An empty footprint is unknown, so it serialises on the whole repo.
  group=$(printf '%s' "${mods%% *}" | tr -c 'A-Za-z0-9._-' '_')
  [ -n "$group" ] || group=repo

  echo "PR #$pr head=${head:0:10} verified=$verified modules=[$mods] group=$group"
  out=$(jq -c --arg pr "$pr" --arg head "$head" --arg v "$verified" --arg g "$group" --arg m "$mods" \
        '. + [{pr:$pr,head:$head,verified:$v,group:$g,modules:$m}]' <<<"$out")
done
echo "prs=$out" >> "$GITHUB_OUTPUT"
