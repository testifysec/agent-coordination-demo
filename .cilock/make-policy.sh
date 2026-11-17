#!/usr/bin/env bash
# usage: make-policy.sh <agent-pubkey.pem> <out.json> [step-name]
# Writes the unsigned policy: one step, one trusted file key, policy.rego embedded.
# Then: cilock policy validate -p out.json
#       cilock sign -k policy.key -f out.json -o out.signed.json
# (policy.key is the human-held POLICY key. The pubkey you pass here is the AGENT key.)
set -eu
PUB=$1; OUT=$2; STEP=${3:-test}
HERE=$(cd "$(dirname "$0")" && pwd)
KEYID=$(cilock keyid show -k "$PUB" | cut -d' ' -f1)
EXPIRES=$(python3 -I -c 'import datetime as d;print((d.datetime.now(d.timezone.utc)+d.timedelta(days=365)).strftime("%Y-%m-%dT%H:%M:%SZ"))')
MOD=$(openssl base64 -A < "$HERE/policy.rego")
KEYB64=$(openssl base64 -A < "$PUB")
jq -n --arg id "$KEYID" --arg key "$KEYB64" --arg exp "$EXPIRES" --arg mod "$MOD" --arg step "$STEP" '{
  expires: $exp,
  publickeys: { ($id): { keyid: $id, key: $key } },
  steps: { ($step): {
    name: $step,
    functionaries: [ { type: "publickey", publickeyid: $id } ],
    attestations: [
      { type: "https://aflock.ai/attestations/command-run/v0.2",
        regopolicies: [ { name: "tests-ran-and-passed", module: $mod } ] },
      { type: "https://aflock.ai/attestations/git/v0.1" }
    ]
  } }
}' > "$OUT"
