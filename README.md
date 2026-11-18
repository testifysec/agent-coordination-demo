# agent-coordination-demo

A working reference for the model in [The merge queue speed limit](https://testifysec.com/blog/merge-queue-speed-limit): agents test their own change once, sign the run with [CI/lock](https://cilock.dev), and CI verifies the signed evidence instead of running the tests again.

In plain words:

1. An agent claims the part of the code it is about to change.
2. It runs the tests once, on its own machine, under `cilock run`. The result is a signed record tied to the exact commit.
3. It pushes the branch and the record together.
4. The land-on-evidence Action verifies the record against a policy on `main`. If it verifies and nothing overlapping landed since the branch started, the Action merges. No merge queue, no CI test run.
5. A check on `main` runs the full suite afterwards, bisects to the first bad commit if it is red, and opens a revert PR.

## Where things are

| What | Where |
| --- | --- |
| Agent skill (paste into Claude Code, Codex, Cursor rules or AGENTS.md) | [`SKILL.md`](SKILL.md) |
| The land-on-evidence Action, its lock, settings, measurements and limits | [`LAND.md`](LAND.md), `.github/workflows/land-on-evidence.yml`, `.land/` |
| The post-land check (test `main`, bisect, revert PR) | `.github/workflows/post-land.yml`, `.land/post-land.sh` |
| Branch ruleset for land on evidence | [`ruleset.land.json`](ruleset.land.json) |
| The policy: the rule, the builder script, and **this demo's** signed policy and public key | `.cilock/` |
| Merge-queue variant: verify-then-skip workflow, its ruleset and settings | [`docs/variants/`](docs/variants/) |
| Lean 4 proofs behind the post's arithmetic | [`formal/merge-queue-speed-limit/`](formal/merge-queue-speed-limit/) |
| Head-to-head experiment: queue vs land on evidence, harness and our results | [`experiments/head-to-head/`](experiments/head-to-head/) |
| Tiny Go packages with real tests (each top-level directory is a "module") | `calc/`, `lib/`, `api/`, `m01/` to `m30/` |

## Quickstart (your own repository)

Needs `cilock` 4.10 or later, Go, `gh`, `openssl`, `jq`.

```sh
# 0. Install cilock (macOS arm64 shown; pick your os-arch from https://cilock.dev/dl/manifest.json
#    and compare the sha256 printed there with `shasum -a 256`).
curl -fsSLO https://cilock.dev/dl/v4.10.0/cilock-4.10.0-darwin-arm64.tar.gz
tar -xzf cilock-4.10.0-darwin-arm64.tar.gz cilock && mv cilock ~/.local/bin/ && cilock version

# 1. Two keys, outside the repository. Never commit a private key.
mkdir -p ~/.config/cilock
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/cilock/agent.key    # signs test evidence; agents hold it
openssl ec -in ~/.config/cilock/agent.key -pubout -out ~/.config/cilock/agent.pub
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/cilock/policy.key   # signs the policy; a human holds it
openssl ec -in ~/.config/cilock/policy.key -pubout -out .cilock/policy.pub

# 2. Build and sign the policy with your agent's public key. This replaces the demo's three policy files.
./.cilock/make-policy.sh ~/.config/cilock/agent.pub .cilock/policy.json
cilock policy validate -p .cilock/policy.json
cilock sign -k ~/.config/cilock/policy.key -f .cilock/policy.json -o .cilock/policy.signed.json

# 3. Commit .github/workflows/land-on-evidence.yml, .github/workflows/post-land.yml, .land/ and .cilock/
#    to your default branch, then apply the settings in LAND.md ("Settings").
```

Edit `.cilock/policy.rego` first if your test command is not `go test ./...`: the policy pins the exact command. `SKILL.md` has the per-change steps an agent follows. Commit the files before applying the ruleset: the ruleset requires a PR and the `land-on-evidence` check, and a base with no policy admits nothing.

This repository's `.cilock/policy.pub` and the agent public key inside its `policy.json` belong to the demo, so they will not accept your evidence. The matching private keys were never committed.

## What this does not prove

A file key shows that someone holding that key ran that command on that commit. It does not say which agent, or on what machine. The git attestor records the commit, not whether the working tree was clean, so an agent could test uncommitted edits. `LAND.md` lists the rest of the limits, including the one human step (a GitHub App) the default token cannot replace.
