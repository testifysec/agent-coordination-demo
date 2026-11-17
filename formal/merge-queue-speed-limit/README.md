# merge-queue-speed-limit

Machine-checked arithmetic behind the post [Your Merge Queue Has a Speed Limit](https://testifysec.com/blog/merge-queue-speed-limit).
It is a standalone [Lean 4](https://lean-lang.org) package: core Lean only, no
Mathlib, no dependencies. Lean accepts a theorem only when it is proved from the
definitions, so each statement below is checked, not argued.

The package proves the **deterministic** part of the argument: how many changes
a merge queue, or a set of coordinating agents, can possibly land in a window of
time, given a lower bound on how long one validation takes. Anything that needs
probabilities is stated as a hypothesis, never proved (see "Not proved").

## Build and audit

```bash
# install elan (https://github.com/leanprover/elan), then:
lake build
```

The build prints one `#print axioms` line per theorem (126 of them). Each must
list only `propext`, `Classical.choice` and `Quot.sound`, or "does not depend on
any axioms". `sorryAx` would mean a missing proof. To list only the odd ones:

```bash
lake build 2>&1 | grep "depends on axioms" | grep -v "propext\|Classical.choice\|Quot.sound"
```

No output means the audit is clean. The toolchain is pinned in `lean-toolchain`.

## Reading the statements

`T` is a lower bound on how long every validation attempt takes, not a mean or a
median. `W` is a window of time, `C` the builds in flight at once, `B` the
changes landed per build, `k` the independent regions of the codebase, `L` the
gap an agent must wait to claim a region, `M` machines, `r` attempts each landed
change consumed. "Inside the window" means an attempt both starts and finishes in
it. Counted by finish time alone, each lane gains one extra (see
`completions_fence_post`).

## What is proved

| Module | Theorem | In plain English |
|---|---|---|
| Pack | `pack`, `pack_div` | Pieces of time that cannot overlap and are each at least `T` long number at most `W/T` in a window of length `W`. Every ceiling below is this one fact |
| Occupancy | `ceiling_contained` | In any valid schedule over `k` resources, attempts that run entirely inside a window number at most `k·⌊(W+L)/(T+L)⌋` |
| | `ceiling_completions` | Counting attempts by when they finish adds one per resource, because an attempt that began before the window can finish in it |
| Serial | `serial_ceiling` | One validator, attempts at least `T`: at most `⌊W/T⌋` attempts fit in a window |
| | `lanes_ceiling`, `batched_ceiling` | `C` builds at once: at most `C·⌊W/T⌋`; landing `B` changes per build: at most `B·C·⌊W/T⌋` |
| | `serial_completions`, `batched_completions` | The same counted by finish time, with `+1` per lane |
| | `completions_fence_post` | That `+1` is real: three back-to-back 3-minute attempts finish three times in a 6-minute window that holds only two |
| | `merges_vs_finishes` | In-order merging can push merges past finishes in a window, by at most the `C` finished builds waiting in the pipeline |
| | `reuse_ceiling`, `reuse_bound_ge`, `reuse_scale_exact` | Skipping a fraction `r` of validation makes each attempt `T(1-r)` long. The ceiling never drops, and scales by exactly `1/(1-r)` when `T` divides `W` |
| Cascade | `cascade_behind_fresh`, `cascade_ahead_kept` | When entry `i` fails, every build behind it restarts from zero; builds ahead are untouched |
| | `cascade_waste` | Work in the pipeline before a failure equals the work after it, plus the failed entry's work, plus all the work behind it |
| | `cascade_used_le` | After a failure, the only work a merge can use is work done ahead of the failure |
| | `merge_blocked`, `finished_behind_unfinished_waits` | Merging is in order: a finished build behind an unfinished one cannot merge |
| | `hol_loss_iff`, `no_hol_loss_iff_monotone` | An entry waits in line exactly when some entry ahead of it finishes later. Nobody waits if finish times never decrease down the queue. Differing durations alone cost nothing |
| | `stack_all_or_nothing`, `stack_fail_ejects_all`, `stack_conserves` | A stack of `k` layers in one build merges all `k` or none; one failure ejects all `k`; every layer is merged or ejected |
| | `stackMerged_le`, `stacks_merged_le`, `stack_ceiling` | A build of `k` layers merges at most `k`, so a stack of `k` is a batch factor `B = k` |
| | `afterFailure_above`, `failure_caps_landing` | A failed layer voids every layer above it, and only the layers below it can land |
| | `allGreen_headGreen`, `passing_build_admits_prefix` | Under "head green" grouping, whatever the older rule merges the new one merges, and one passing build at depth `k` admits every entry ahead of it |
| | `headGreen_sound` | Head-green grouping never admits an entry with a real failure at or ahead of it |
| | `infra_failure_no_longer_ejects` | An infrastructure failure on entry `i` ejects it under the older rule but not under head-green when a deeper build passes |
| | `real_failure_still_ejected` | A real failure is ejected under both |
| Queue | `starved_never_completes`, `periodic_starves` | If `main` moves at least once per run duration, no group started after the first move ever completes |
| | `completes_in_long_gap` | Liveness: a long enough quiet gap lets a rebuilt group finish |
| Cliff | `cliff_zero` | If every group's age at completion exceeds the check timeout, nothing merges |
| | `cliff_fraction` | In general merges are at most the number of groups that finish in time |
| | `slowdown_cliff`, `cliff_lifts` | Attempts slowed by a factor `f` form a cliff once `f·T` exceeds the timeout; raising the timeout to `f·T` lets them merge again |
| | `long_runs_never_merge`, `restart_eats_timeout` | The timeout counts from group creation, so each restart eats what is left of it |
| | `starved_groups_never_merge` | Moves of `main` at least once per run give zero merges: a second route to the same cliff |
| Staleness | `commute` | Changes with disjoint footprints land in either order to the same tree |
| | `verdict_stable_seq` | A test that reads only its footprint keeps its verdict across any run of landings that miss that footprint |
| | `main_cas_implies_region_cas`, `region_cas_strictly_weaker` | "Main is still the base I tested" implies "nothing overlapping landed", never the converse |
| | `overlap_can_invalidate` | A witness: an overlapping landing flips a verdict |
| | `agent_starved` | Overlapping landings at least once per run duration: no run started after the first ever lands |
| Coordination | `coordination_ceiling` | `k` regions, each serial with runs at least `T` and gap `L`: at most `k·⌊(W+L)/(T+L)⌋` landings |
| | `all_overlap_is_serial` | If every pair of changes overlaps the bound is the serial one, whatever `k` is |
| | `latency_never_helps` | `⌊(W+L)/(T+L)⌋ ≤ ⌊W/T⌋`: a claim gap only lowers the ceiling |
| | `hub_excludes`, `hub_cost`, `hubs_total` | A change touching every region excludes all others for its whole run; `h` such hubs cost every region `h` slots |
| Drain | `outage_backlog` | After an outage of `D` at arrival rate `l`, the backlog is `l·D` |
| | `drain_exact`, `drainTime_spec` | After the outage the backlog falls by `m-l` per tick and clears at exactly `t = D·ρ/(1-ρ)`, `ρ = l/m` (stated as `(m-l)·t = l·D`) |
| | `cold_restart_never_faster`, `backlog_mono` | Extra lost capacity during recovery never lowers the backlog at any tick |
| | `straight_line_floor`, `real_drain_not_before_line` | The straight line is a floor only if arrivals are at least `l` every tick, capacity at most `m`, and the starting backlog at least `l·D` |
| | `floor_needs_arrivals` | A witness: if arrivals stop, the real drain beats the line (2 ticks against 6) |
| Dominance | `queue_is_a_coordination_policy` | The merge queue is the coordination policy with `C` slots, stacking depth `C` and every change in one region |
| | `coordination_dominates_queue` | On the same pipeline and the same ticks and failures, every entry of the coordinated pipeline has done at least as much validation as the queue's, and it has landed at least as many changes |
| | `coord_emulates_queue` | On a one-region pipeline the coordination policy produces exactly the queue's schedule |
| | `strictly_less_invalidation`, `witness_less_invalidation` | If no entry between a failed entry and `j` shares a region with it, the queue restarts `j` and coordination does not |
| | `restart_unnecessary` | Why skipping that restart is safe: a test that reads only its footprint keeps its verdict when a disjoint failed change is removed |
| Master | `merge_speed_limit_master` | One statement composing the above: throughput ceilings (queue, agents, serial when everything overlaps), dominance, safety of landed runs, the timeout and starvation cliffs, the cascade, stacks and the exact drain time |
| MasterExt | `concentration_ceiling` | If the busiest region holds at least `num/den` of all landings and no region carries more than `R = ⌊(W+L)/(T+L)⌋`, total landings are at most `R·den/num`. Only concentration appears, not the number of regions or the size of the repository |
| | `nonatomic_safe`, `lock_needed` | A lander that checks at time `tc` and merges at `tl ≥ tc` keeps a passing run passing if overlapping landings lock `[tc, tl]`; without the lock two overlapping landings both pass their checks and the landed tree fails the test |
| | `lander_service_ceiling` | If each landing occupies its serialization group for at least `s` minutes, `g` groups land at most `g·⌊W/s⌋` services that both start and finish inside the window |
| | `machine_minutes_ceiling`, `machine_minutes_ceiling_div` | On `M` machines attempts at least `T` long inside a window number at most `M·⌊W/T⌋`. If each landed change owns at least `r` attempts, credited to it alone, then `r·landings ≤ M·⌊W/T⌋` |
| | `speed_limit_collapsed`, `queue_collapsed` | Agents land at most `min(M·⌊W/T⌋/r, k·⌊(W+L)/(T+L)⌋)`; the queue at most `min(B·C·⌊W/T⌋, M·⌊W/T⌋/r)` |
| | `merge_speed_limit_master_measured` | The whole master theorem plus the extensions above; throughput is at most the least of the validation, service and machine-minute bounds |

## Hypotheses

The theorems are conditional on these. Each is written into a definition or a
premise, so it cannot be missed.

- **T is a lower bound** on every attempt, not an average. A distribution with
  mass below its median can beat a ceiling stated at the median in a given window.
- **H1 same stream, same fates.** Queue and agents see the same ticks and the same
  failures. Whether a change fails is a property of the change.
- **H2 same capacity.** Same slots and stacking depth.
- **H3 correct footprints.** A change writes a region from the values in its own
  footprint (`Change.reads_fp`) and a test reads only its footprint (`Test.reads`).
  Real tests often read the whole tree, so this is the load-bearing assumption of
  coordination. The progress theorem does not use it; the safety theorems do.
- **H4** failure events name entries that have not landed.
- **H5** only restart cost is compared in `coordination_dominates_queue`: claim
  latency, claim races and hubs are not part of that theorem.
- **H6 the evidence names the exact tree.** A landing is checked against the base
  its run used.
- **H7 lock.** Overlapping landings hold a lock over `[tc, tl]`.
- **H8 service time.** Each landing occupies its serialization group for at least
  `s` minutes.
- **H9 ownership.** Each landed change owns at least `r` attempts inside the
  window, credited to it alone. A build validating two changes is credited to one.
- **Pipeline.** Builds hold a slot until they merge, merges are in order, a failed
  entry leaves and everything behind it restarts. This is a model of a speculative
  queue, not a proof about any particular implementation.
- **Lanes.** At most `C` builds run at once and the model takes a lane for each as
  given.

## Not proved

- **Anything probabilistic.** The chance a change fails, how check times are
  distributed, the chance a run is still current (`e^(-λT/60)`), expected waste,
  Kingman's formula, and whether the mean drain sits above the straight line. The
  drain floor is pathwise and needs the hypotheses above.
- **Latency.** Only an explicit gap `L` is modelled. The dominance theorem ignores
  it, so coordinated agents can lose to a queue when claim latency is large.
- **Semantic conflicts across footprints.** Two changes to different files that
  still break each other. `Test.reads` is exactly the assumption that this does not
  happen; a central check on `main` exists for when it does.
- **Trust in who ran the test**: the machine, the identity, and whether the
  record really names the tree.
- **That a larger repository does not reduce concentration.** The concentration
  bound uses the share of landings in the busiest region. That this share stays
  high as repositories grow is an empirical observation, not a theorem.
- **GitHub's implementation.** Whether a finished build really holds its slot
  until everything ahead merges, and exactly how head-green grouping cancels
  builds, is assumed, not checked.

## Layout

```
lakefile.toml, lean-toolchain
MergeQueueSpeedLimit.lean          imports everything, including the audit
MergeQueueSpeedLimit/
  Pack, Occupancy                  the counting argument and the ceilings
  Serial, Coordination             queue lanes, reuse; regions, hubs, latency
  Cascade, Cliff, Queue            failures, stacks, head-green; timeout; starvation
  Staleness, Drain                 footprints and commutation; the outage drain
  Dominance                        the queue is a coordination policy
  Master, MasterExt                the composed theorems
  Audit                            axiom audit, one line per theorem
```
