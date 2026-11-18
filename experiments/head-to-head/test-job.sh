#!/usr/bin/env bash
# The "test": hold a token for T seconds (a constant sleep). Runs inside an Actions job.
set -u
# shellcheck source=/dev/null
. .exp/sem.sh
HOLDER="$GITHUB_RUN_ID-$GITHUB_JOB-$RANDOM"
t_job=$(date +%s)
sem_acquire "$POOL" "$SIZE"
sleep "${T:-120}"
sem_release
rec "kind=$KIND" "pool=$POOL" "job_start=$t_job" "acq=$SEM_ACQ" "rel=$SEM_REL" "wait=$((SEM_ACQ - t_job))" "held=$((SEM_REL - SEM_ACQ))" "run=$GITHUB_RUN_ID"
echo "token $SEM_REF waited $((SEM_ACQ - t_job))s held $((SEM_REL - SEM_ACQ))s"
