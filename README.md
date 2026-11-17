# agent-coordination-demo

A small repository that runs the model from [The merge queue speed limit](https://testifysec.com/blog/merge-queue-speed-limit) for real.

The model in plain words:

1. An agent (or you) claims the part of the code it is about to change, so two agents do not test the same thing at once.
2. It runs the tests **once**, on its own machine, wrapped in [CI/lock](https://cilock.dev) (`cilock`). That produces a signed record of the exact command, its exit code and its output, tied to the exact commit.
3. It pushes the branch and the record together.
4. CI does not run the tests again. It **verifies the record**. If the record is signed by a trusted key, names this commit, and the policy says the tests ran and passed, the change can land. If anything is missing or wrong, it does not.
5. A check on `main` runs the full suite after landing, bisects to the first bad commit if it is red, and opens a revert PR.

## Two ways to use it

- **Land on evidence** (what `main` runs): an Action merges a ready PR when its evidence verifies and no change to the same module landed since its base. No merge queue. See `LAND.md`.
- **Evidence gate + merge queue**: CI verifies the evidence and skips its test job; the queue still tests the merged result. The workflow is `docs/variants/evidence-gate.yml`, with its own settings in `SETTINGS.md`.

## What is here

| Path | What it is |
| --- | --- |
| `SKILL.md` | The agent rules. Paste into Claude Code, Codex, Cursor rules or AGENTS.md. |
| `LAND.md` | How land-on-evidence works, its lock, its settings, what was measured, what it cannot do. |
| `.github/workflows/land-on-evidence.yml`, `.github/workflows/post-land.yml`, `.land/` | The landing Action and the check that tests `main` afterwards. |
| `.cilock/policy.rego`, `.cilock/make-policy.sh` | The rule, and the script that builds the policy from it. |
| `.cilock/policy.json`, `.cilock/policy.signed.json`, `.cilock/policy.pub` | **The demo's** policy, its signed copy, and the policy key's public half. You replace all three (below). |
| `ruleset.land.json` | The branch ruleset for land-on-evidence: required check `land-on-evidence`, no merge queue, no bypass. |
| `ruleset.json`, `docs/variants/evidence-gate.yml`, `SETTINGS.md` | The merge-queue variant: ruleset (required check `ci`, queue with `HEADGREEN`), workflow, and settings. |
| `formal/merge-queue-speed-limit/` | The Lean 4 proofs behind the post's arithmetic. Standalone; `lake build` checks them. |
| `calc/`, `lib/`, `api/`, `m01/` to `m30/` | Tiny Go packages with real tests, so there is something to run. Each top-level directory is a module. |

## Run it on your own repository

Needs `cilock` v4.10.0 or later, Go, `gh`, `openssl`, `jq`.

```sh
# 0. Install cilock (macOS arm64 shown; pick your os-arch from https://cilock.dev/dl/manifest.json,
#    and compare the sha256 printed there with `shasum -a 256`).
curl -fsSLO https://cilock.dev/dl/v4.10.0/cilock-4.10.0-darwin-arm64.tar.gz
tar -xzf cilock-4.10.0-darwin-arm64.tar.gz cilock && mv cilock ~/.local/bin/ && cilock version

# 1. Two keys. Generate them yourself, outside the repository. Never commit a private key.
mkdir -p ~/.config/cilock
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/cilock/agent.key    # signs test evidence; agents hold it
openssl ec -in ~/.config/cilock/agent.key -pubout -out ~/.config/cilock/agent.pub
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/cilock/policy.key   # signs the policy; a human holds it
openssl ec -in ~/.config/cilock/policy.key -pubout -out .cilock/policy.pub

# 2. Build and sign the policy with your agent's public key. This overwrites the demo's three policy files.
./.cilock/make-policy.sh ~/.config/cilock/agent.pub .cilock/policy.json
cilock policy validate -p .cilock/policy.json
cilock sign -k ~/.config/cilock/policy.key -f .cilock/policy.json -o .cilock/policy.signed.json

# 3. Land-on-evidence: commit .github/workflows/land-on-evidence.yml, .github/workflows/post-land.yml,
#    .land/ and .cilock/ to your default branch, then turn on the repository settings (LAND.md, "Settings").
```

Edit `.cilock/policy.rego` first if your test command is not `go test ./...`: the policy pins the exact command. `SKILL.md` has the per-change steps an agent follows (claim, test under `cilock`, publish evidence, push).

Commit those files to your default branch before you apply the ruleset: the ruleset requires a PR and the `land-on-evidence` check, and a base with no policy admits nothing.

This repository's `.cilock/policy.pub` and the agent public key inside its `policy.json` belong to the demo. They will not accept your evidence. The matching private keys were never committed.

## What this does not prove

A file key shows that someone holding that key ran that command on that commit. It does not say which agent, or on what machine. The git attestor records the commit, not whether the working tree was clean, so an agent could test uncommitted edits. `SETTINGS.md` and `LAND.md` list the rest.
