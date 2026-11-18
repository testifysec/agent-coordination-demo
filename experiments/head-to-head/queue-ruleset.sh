#!/usr/bin/env bash
# usage: queue-ruleset.sh allgreen|headgreen   (create or update the main-queue ruleset)
set -eu
R=${R:-OWNER/REPO}
V=${EXP_DIR:?set EXP_DIR to a work directory}
case "$1" in
  allgreen)  G=ALLGREEN;  MAXM=1 ;;
  headgreen) G=HEADGREEN; MAXM=5 ;;
  *) exit 2 ;;
esac
cat > "$V/out/ruleset-queue.json" <<E
{ "name": "exp: main-queue", "target": "branch", "enforcement": "active", "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/main-queue"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": { "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false } },
    { "type": "merge_queue", "parameters": { "merge_method": "SQUASH", "grouping_strategy": "$G", "max_entries_to_build": 5, "max_entries_to_merge": $MAXM, "min_entries_to_merge": 1, "min_entries_to_merge_wait_minutes": 0, "check_response_timeout_minutes": 60 } },
    { "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": false, "do_not_enforce_on_create": false, "required_status_checks": [ { "context": "ci" } ] } } ] }
E
id=$(gh api repos/$R/rulesets --jq '.[]|select(.name=="exp: main-queue")|.id')
if [ -n "$id" ]; then gh api repos/$R/rulesets/$id --method PUT --input "$V/out/ruleset-queue.json" --jq '{id,name}'
else gh api repos/$R/rulesets --method POST --input "$V/out/ruleset-queue.json" --jq '{id,name}'; fi
