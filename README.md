# agent-coordination-demo

A small repository that runs the model from [The merge queue speed limit](https://testifysec.com/blog/merge-queue-speed-limit) for real.

The model in plain words:

1. An agent (or you) claims the part of the code it is about to change, so two agents do not test the same thing at once.
2. It runs the tests **once**, on its own machine, wrapped in [CI/lock](https://cilock.dev) (`cilock`). That produces a signed record of the exact command, its exit code and its output, tied to the exact commit.
3. It pushes the branch and the record together.
4. CI does not run the tests again. It **verifies the record**. If the record is signed by a trusted key, names this commit, and the policy says the tests ran and passed, the test job is skipped. If anything is missing or wrong, the test job runs. When in doubt, CI runs the tests.
5. The merge queue still runs the full suite once on the merged result, because the merged commit is new and nobody has tested it.

## Two ways to use the model

- **Land on evidence** (what `main` runs now): an Action merges a ready PR when its evidence verifies and no change to the same module landed since its base. No merge queue. See `LAND.md`.
- **Evidence gate + merge queue**: CI verifies the evidence and skips its test job; the queue still tests the merged result. The workflow is kept at `docs/variants/evidence-gate.yml` (it ran in this repository first; see the pull requests #1 to #3).

## What is here

| Path | What it is |
| --- | --- |
| `SKILL.md` | The agent rules. Paste into Claude Code, Codex, Cursor rules or AGENTS.md. |
| `.github/workflows/land-on-evidence.yml`, `.github/workflows/post-land.yml`, `.land/` | Land on evidence, and the check that tests main afterwards. |
| `docs/variants/evidence-gate.yml` | The verify-then-skip workflow for a repository that keeps a merge queue. |
| `.cilock/policy.rego`, `.cilock/make-policy.sh` | The rule and the script that builds the policy. |
| `.cilock/policy.json`, `.cilock/policy.signed.json`, `.cilock/policy.pub` | The policy, its signed copy, and the policy key's public half. |
| `ruleset.json` | The branch ruleset: required check `ci`, merge queue with `HEADGREEN`. |
| `SETTINGS.md` | Every repository setting and what it is for, and what this cannot do. |
| `calc/` | A tiny Go package with real tests, so there is something to run. |

## Run it on your own repository

Needs [`cilock`](https://cilock.dev) v4.10.0 or later and Go.

```sh
# 1. Two keys. Generate them yourself. Never commit a private key.
mkdir -p ~/.config/cilock
openssl ecparam -name prime256v1 -genkey -noout -out ~/.config/cilock/agent.key   # signs test evidence; agents hold it
openssl ec -in ~/.config/cilock/agent.key -pubout -out agent.pub
openssl ecparam -name prime256v1 -genkey -noout -out policy.key                   # signs the policy; a human holds it
openssl ec -in policy.key -pubout -out .cilock/policy.pub

# 2. Build and sign the policy with your agent's public key.
./.cilock/make-policy.sh agent.pub .cilock/policy.json
cilock policy validate -p .cilock/policy.json
cilock sign -k policy.key -f .cilock/policy.json -o .cilock/policy.signed.json

# 3. Commit .github/workflows/evidence-gate.yml and .cilock/ to your default branch, apply ruleset.json (see SETTINGS.md).
```

This repository's `.cilock/policy.pub` and the agent public key inside `policy.json` belong to the demo. They will not accept your evidence. The matching private keys were never committed.

## What this does not prove

A file key shows that someone holding that key ran that command on that commit. It does not say which agent, or on what machine. The git attestor records the commit, not whether the working tree was clean, so an agent could test uncommitted edits. See `SETTINGS.md` for the full list.
