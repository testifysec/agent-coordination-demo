/-
  MergeQueueSpeedLimit.Audit: every theorem in the package, and the axioms it
  rests on. `lake build` prints one `#print axioms` line per theorem; each must
  list only `propext`, `Classical.choice` and `Quot.sound` (or none). A
  `sorryAx` would mean a missing proof.
-/
import MergeQueueSpeedLimit.Pack
import MergeQueueSpeedLimit.Occupancy
import MergeQueueSpeedLimit.Serial
import MergeQueueSpeedLimit.Coordination
import MergeQueueSpeedLimit.Queue
import MergeQueueSpeedLimit.Cascade
import MergeQueueSpeedLimit.Cliff
import MergeQueueSpeedLimit.Staleness
import MergeQueueSpeedLimit.Drain
import MergeQueueSpeedLimit.Dominance
import MergeQueueSpeedLimit.Master
import MergeQueueSpeedLimit.MasterExt

namespace MergeQueueSpeedLimit

-- Pack
#print axioms filter_len_add
#print axioms pack
#print axioms pack_div

-- Occupancy
#print axioms Valid.sublist
#print axioms peel
#print axioms region_pack
#print axioms ceiling_contained
#print axioms ceiling_completions
#print axioms weight_le

-- Serial
#print axioms serial_ceiling
#print axioms serial_completions
#print axioms lanes_ceiling
#print axioms batched_ceiling
#print axioms batched_completions
#print axioms backToBack_valid
#print axioms serial_ceiling_tight
#print axioms completions_fence_post
#print axioms reuse_ceiling
#print axioms reuse_bound_ge
#print axioms reuse_scale_exact
#print axioms count_union_le
#print axioms merges_vs_finishes

-- Coordination
#print axioms coordination_ceiling
#print axioms latency_never_helps
#print axioms all_overlap_is_serial
#print axioms hub_excludes
#print axioms hub_cost
#print axioms hubs_total
#print axioms threeLanes_valid
#print axioms coordination_ceiling_tight

-- Queue
#print axioms move_in_every_window
#print axioms Moves.mono_le
#print axioms starved_never_completes
#print axioms periodic_starves
#print axioms completes_in_long_gap

-- Cascade
#print axioms cascade_length
#print axioms cascade_ahead_kept
#print axioms cascade_behind_fresh
#print axioms workOf_fresh
#print axioms cascade_waste
#print axioms merge_blocked
#print axioms finished_behind_unfinished_waits
#print axioms cascade_no_merge_behind
#print axioms cascade_used_le
#print axioms le_pmax
#print axioms le_pmax_of_le
#print axioms merge_after_all_ahead
#print axioms pmax_mono
#print axioms pmax_attained
#print axioms hol_loss_iff
#print axioms no_hol_loss_iff_monotone
#print axioms stack_all_or_nothing
#print axioms stackMerged_le
#print axioms stack_fail_ejects_all
#print axioms stack_conserves
#print axioms stacks_merged_le
#print axioms stack_ceiling
#print axioms afterFailure_below
#print axioms afterFailure_above
#print axioms rerun_eq
#print axioms landedPrefix_le
#print axioms failure_caps_landing
#print axioms allGreen_headGreen
#print axioms passing_build_admits_prefix
#print axioms headGreen_sound
#print axioms infra_failure_no_longer_ejects
#print axioms real_failure_still_ejected

-- Cliff
#print axioms cliff_zero
#print axioms cliff_fraction
#print axioms slowdown_cliff
#print axioms cliff_lifts
#print axioms long_runs_never_merge
#print axioms restart_eats_timeout
#print axioms starved_groups_never_merge

-- Staleness
#print axioms Disjoint.symm
#print axioms commute
#print axioms miss_keeps_verdict
#print axioms verdict_stable_seq
#print axioms main_cas_implies_region_cas
#print axioms region_cas_strictly_weaker
#print axioms region_cas_commutes
#print axioms overlap_can_invalidate
#print axioms agent_starved

-- Drain
#print axioms outage_backlog
#print axioms drain_closed
#print axioms drain_clears_iff
#print axioms drain_exact
#print axioms drainTime_spec
#print axioms backlog_mono
#print axioms cold_restart_never_faster
#print axioms cold_restart_clears_later
#print axioms straight_line_floor
#print axioms real_drain_not_before_line
#print axioms floor_needs_arrivals

-- Dominance
#print axioms disjointB_iff
#print axioms coordInv_le_queueInv
#print axioms coordInv_single_region
#print axioms coordInv_single_region_false
#print axioms queue_is_a_coordination_policy
#print axioms strictly_less_invalidation
#print axioms Dom.fps
#print axioms forall2_eraseIdx
#print axioms restartAux_dom
#print axioms dom_fail
#print axioms dom_advance
#print axioms dom_play
#print axioms landed_mono
#print axioms coordination_dominates_queue
#print axioms restartAux_ext
#print axioms allOne_map
#print axioms allOne_fail
#print axioms allOne_step
#print axioms coord_emulates_queue
#print axioms restart_unnecessary
#print axioms witness_less_invalidation

-- Master
#print axioms merge_speed_limit_master

-- MasterExt
#print axioms concentration_ceiling
#print axioms nonatomic_safe
#print axioms lock_needed
#print axioms lander_service_ceiling
#print axioms attempts_cover
#print axioms machine_minutes_ceiling
#print axioms machine_minutes_ceiling_div
#print axioms speed_limit_collapsed
#print axioms queue_collapsed
#print axioms merge_speed_limit_master_measured

end MergeQueueSpeedLimit
