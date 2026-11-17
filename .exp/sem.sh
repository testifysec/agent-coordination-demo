#!/usr/bin/env bash
# Token semaphore on git refs. Source this file from inside a clone whose `origin` is the demo repo.
#   sem_acquire <pool> <size>   blocks (polls with jitter) until one of refs/tokens/<pool>/0..size-1 is created
#   sem_release                 deletes the ref held, with a lease on our own commit
#   rec <key=value>...          appends a record ref refs/rec/$RUNTAG/<unique> (read back after the run)
# A token carries an expiry (SEM_LEASE s); an expired token is taken over by compare-and-swap.
SEM_LEASE=${SEM_LEASE:-600}
export GIT_AUTHOR_NAME=exp GIT_AUTHOR_EMAIL=exp@users.noreply.github.com
export GIT_COMMITTER_NAME=exp GIT_COMMITTER_EMAIL=exp@users.noreply.github.com

sem_commit() {
  git commit-tree "$(git hash-object -t tree -w /dev/null)" -m "token $1
holder: ${HOLDER:-$$}
expires-epoch: $(( $(date +%s) + SEM_LEASE ))"
}

sem_acquire() {
  local pool=$1 size=$2 i ref cur exp c
  SEM_T0=$(date +%s)
  while :; do
    git fetch -q --prune origin "+refs/tokens/$pool/*:refs/remotes/tokens/$pool/*" 2>/dev/null || true
    for i in $(seq 0 $((size - 1))); do
      ref=refs/tokens/$pool/$i
      cur=$(git rev-parse -q --verify "refs/remotes/tokens/$pool/$i" 2>/dev/null || true)
      if [ -n "$cur" ]; then
        exp=$(git log -1 --format=%B "$cur" | sed -n 's/^expires-epoch: //p')
        [ "${exp:-0}" -gt "$(date +%s)" ] && continue
      fi
      c=$(sem_commit "$pool/$i")
      if git push -q --force-with-lease="$ref:$cur" origin "$c:$ref" 2>/dev/null; then
        SEM_REF=$ref; SEM_C=$c; SEM_ACQ=$(date +%s); return 0
      fi
    done
    sleep $((2 + RANDOM % 3))
  done
}

sem_release() {
  git push -q --force-with-lease="$SEM_REF:$SEM_C" origin ":$SEM_REF" 2>/dev/null || echo "warning: token release failed (expires on its own)"
  SEM_REL=$(date +%s)
}

rec() { # key=value ... -> refs/rec/$RUNTAG/<unique>
  local id="$$-$RANDOM-$(date +%s%N 2>/dev/null || date +%s)"
  local c; c=$(git commit-tree "$(git hash-object -t tree -w /dev/null)" -m "rec
$*")
  git push -q origin "$c:refs/rec/$RUNTAG/$id" 2>/dev/null || echo "warning: rec push failed"
}
