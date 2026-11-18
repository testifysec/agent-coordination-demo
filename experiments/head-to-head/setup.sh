#!/usr/bin/env bash
# One-time: create branches main-queue (arm A) and land-b (arm B) from main, their rulesets, repo settings.
set -eu
V=${EXP_DIR:?set EXP_DIR to a work directory}
H=$V/harness; W=$V/work
DK=${KEY_DIR:-$HOME/.config/cilock}
R=${R:-OWNER/REPO}
export PATH="${CILOCK_DIR:-$HOME/.local/bin}:$PATH"
cd "$W"; rm -rf repo; gh repo clone $R repo -- -q; cd repo
git config user.email exp@users.noreply.github.com; git config user.name exp

### arm A branch
git switch -q -c main-queue origin/main
git rm -q .github/workflows/land-on-evidence.yml .github/workflows/post-land.yml
mkdir -p .exp; cp "$H/sem.sh" "$H/test-job.sh" .exp/; chmod +x .exp/*.sh
mkdir -p .github/workflows; cp "$H/queue-ci.yml" .github/workflows/queue-ci.yml
git add -A; git commit -q -m "exp: main-queue branch (queue arm)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -q origin main-queue

### arm B branch
git switch -q -c land-b origin/main
git rm -q .github/workflows/post-land.yml
sed -i '' 's/--base main/--base land-b/; s/baseRefName <<<"$info")" = main/baseRefName <<<"$info")" = land-b/' .land/plan.sh
sed -i '' 's#\${HEAD_SHA}\.\.\.main#${HEAD_SHA}...land-b#' .land/land.sh
sed -i '' "s/base.ref == 'main'/base.ref == 'land-b'/; s/branches: \[main\]/branches: [land-b]/" .github/workflows/land-on-evidence.yml
grep -n "land-b" .land/plan.sh .land/land.sh .github/workflows/land-on-evidence.yml | cut -c1-140
cat > .cilock/policy.rego <<'E'
package coordkit.sleep_ran

# The experiment's "test" is a constant sleep. The policy pins the exact command and a clean exit.
expected_cmd := ["sleep", "120"]

readable_exit { is_number(input.exitcode) }

deny[msg] {
	not readable_exit
	msg := "unreadable evidence: command-run has no numeric exitcode"
}

deny[msg] {
	readable_exit
	input.exitcode != 0
	msg := sprintf("test exited %v, not 0", [input.exitcode])
}

deny[msg] {
	not input.cmd == expected_cmd
	msg := sprintf("step ran %v, expected %v", [input.cmd, expected_cmd])
}
E
./.cilock/make-policy.sh "$DK/agent.pub" .cilock/policy.json
cilock policy validate -p .cilock/policy.json 2>&1 | head -1
cilock sign -k "$DK/policy.key" -f .cilock/policy.json -o .cilock/policy.signed.json 2>&1 | tail -1
openssl ec -in "$DK/policy.key" -pubout -out .cilock/policy.pub 2>/dev/null
actionlint .github/workflows/*.yml
git add -A; git commit -q -m "exp: land-b branch (agents arm), sleep policy

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
git push -q origin land-b

### repo settings and variables
gh repo edit $R --enable-auto-merge
gh variable set T --repo $R --body 120
gh variable set POOL_CI --repo $R --body 2
gh variable set POOL_MQ --repo $R --body 2
gh variable set RUNTAG --repo $R --body none

### rulesets
cat > "$V/out/ruleset-landb.json" <<'E'
{ "name": "exp: land-b", "target": "branch", "enforcement": "active", "bypass_actors": [],
  "conditions": { "ref_name": { "include": ["refs/heads/land-b"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": { "required_approving_review_count": 0, "dismiss_stale_reviews_on_push": false, "require_code_owner_review": false, "require_last_push_approval": false, "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": { "strict_required_status_checks_policy": false, "do_not_enforce_on_create": false, "required_status_checks": [ { "context": "land-on-evidence", "integration_id": 15368 } ] } } ] }
E
gh api repos/$R/rulesets --method POST --input "$V/out/ruleset-landb.json" --jq '{id,name}'
