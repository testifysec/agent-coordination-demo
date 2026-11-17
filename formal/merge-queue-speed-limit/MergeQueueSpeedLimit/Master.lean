/-
  MergeQueueSpeedLimit.Master: the post's argument in one statement.

  `merge_speed_limit_master` is a conjunction of five parts, each composed
  from a result proved elsewhere in this model. Its only numeric hypothesis is
  `0 < T`. The other hypotheses are the ones the parts need, written into the
  structures and the statement so they cannot be missed:

    H1 Same stream, same fates: queue and agents see the same ticks and the
       same failures (Dominance.lean).
    H2 Same capacity: same slots and stacking depth (Dominance.lean).
    H3 Footprints are correct: a change writes only from its own footprint
       (`Change.reads_fp`) and a test reads only its footprint (`Test.reads`),
       Staleness.lean. Part 3 is a theorem about runs whose test obeys this.
    H4 Failure events name entries that have not landed (Dominance.lean).
    H5 Only the quantities named are compared: no latency cost beyond the
       explicit gap `L` of Coordination.lean, no hubs unless the footprint
       says so.
    H6 The evidence names the exact tree. A landing is checked against the base
       `X` its run used, and the verdict is `T.run (c.apply X)`: the run is
       about that commit on that tree. Nothing here proves a real signed
       record says so; that is the trust layer the post ends on.
    T  is a lower bound on every attempt (Occupancy.lean), not a mean.

  WHAT IT DOES NOT COVER.
    * Probabilities: the odds a change fails, how check times are distributed,
      the staleness probability, expected waste, Kingman, the mean drain.
    * Latency: the claim race and consensus time. Only an explicit gap `L`
      between landings that share a region is modelled, and the coordination
      advantage in part 2 ignores it (Dominance H5). Agents can lose to the
      queue when it is large.
    * Cross-footprint semantic conflicts: two changes to different regions that
      still break each other. `Test.reads` is exactly the assumption that this
      does not happen; the central check on main exists for when it does.
    * Trust in who ran the test: H6 takes the evidence as naming the right
      tree; whether the agent really ran it, on what machine, with what
      identity, is not modelled.
-/
import MergeQueueSpeedLimit.Dominance
import MergeQueueSpeedLimit.Coordination
import MergeQueueSpeedLimit.Cliff
import MergeQueueSpeedLimit.Drain

namespace MergeQueueSpeedLimit

/-- The conclusion of `merge_speed_limit_master`, named so a later theorem can
    carry it whole. -/
def MasterProp (T k C L W a : Nat) : Prop :=
    -- (1) THROUGHPUT.
    -- the central queue: C lanes, attempts at least T, at most C * floor(W/T)
    (∀ js : List Occ, Valid C T 0 js → (∀ j ∈ js, InWin a W j) → js.length ≤ C * (W / T)) ∧
    -- with B changes per build (a stack of B layers is such a build)
    (∀ (B : Nat) (js : List Occ), Valid C T 0 js → (∀ j ∈ js, InWin a W j) →
      (∀ j ∈ js, j.w ≤ B) → (js.map Occ.w).sum ≤ B * C * (W / T)) ∧
    -- coordinated agents on k independent regions, gap L between sharing landings
    (∀ js : List Occ, Valid k T L js → (∀ j ∈ js, InWin a W j) →
      js.length ≤ k * ((W + L) / (T + L))) ∧
    -- everything overlapping (o = 1): coordination is serial, whatever k is
    (∀ js : List Occ, Valid k T 0 js → js.Pairwise Occ.shares → (∀ j ∈ js, InWin a W j) →
      js.length ≤ W / T) ∧
    -- (2) DOMINANCE.
    (∀ (q : List Ent) (evs : List Ev),
      Dom (play queueInv T evs q) (play coordInv T evs q) ∧
      landed T (play queueInv T evs q) ≤ landed T (play coordInv T evs q)) ∧
    -- the agents can emulate the queue exactly (one region)
    (∀ (evs : List Ev) (q : List Ent), AllOne q →
      play coordInv T evs q = play queueInv T evs q) ∧
    -- and restart strictly less when footprints are disjoint
    (∀ (fps : List (List Nat)) (i j : Nat), i < j →
      (∀ m, i < m → m ≤ j → Disjoint (fps.getD i []) (fps.getD m [])) →
      coordInv fps i j = false ∧ queueInv fps i j = true) ∧
    -- (3) SAFETY. A passing run whose footprint no landing has touched since its
    -- base still passes on the landed tree.
    (∀ (c : Change) (Tst : Test) (X : Tree) (Ls : List Change),
      (∀ r ∈ c.fp, r ∈ Tst.fp) → Tst.run (c.apply X) = true →
      (∀ l ∈ Ls, Disjoint l.fp Tst.fp) →
      Tst.run (c.apply (landAll Ls X)) = true) ∧
    -- with one region (k = 1) the condition forces no landing at all since the
    -- base: the verdict was computed on the exact tree that lands, which is the
    -- queue's safety
    (∀ (c : Change) (Tst : Test) (Ls : List Change),
      0 ∈ c.fp → (∀ r ∈ c.fp, r ∈ Tst.fp) → (∀ l ∈ Ls, 0 ∈ l.fp) →
      (∀ l ∈ Ls, Disjoint l.fp Tst.fp) → Ls = []) ∧
    -- (4) FRAGILITY.
    -- if every build's age exceeds the timeout, nothing merges
    (∀ (timeout : Nat) (gs : List Group), (∀ g ∈ gs, timeout < g.age) → merges timeout gs = 0) ∧
    -- overlapping landings at least once per run duration starve every run
    (∀ (mv : Moves) (D : Nat), mv.gap ≤ D → ∀ s, mv.m 0 ≤ s → ¬ Completes mv D s) ∧
    -- (5) THE REST OF THE ARGUMENT: a failure wastes what is behind it, stacks are
    -- all-or-nothing, and the drain takes exactly D * rho / (1 - rho).
    (∀ ahead behind : List Build,
      mergePrefix (cascade ahead behind) ≤ ahead.length ∧ usedWork (cascade ahead behind) ≤ workOf ahead) ∧
    (∀ layers : List Bool, stackMerged layers = 0 ∨ stackMerged layers = layers.length) ∧
    (∀ l m D t : Nat, l < m → (m - l) * t = l * D →
      backlog (fun _ => l) (fun _ => m) (l * D) t = 0 ∧
      ∀ s, s < t → backlog (fun _ => l) (fun _ => m) (l * D) s ≠ 0)

theorem merge_speed_limit_master (T k C L W a : Nat) (hT : 0 < T) : MasterProp T k C L W a := by
  unfold MasterProp
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · intro js hv hw; exact lanes_ceiling hT hv a W hw
  · intro B js hv hw hB; exact batched_ceiling hT hv a W hw hB
  · intro js hv hw; exact coordination_ceiling hT hv a W hw
  · intro js hv hall hw
    have := all_overlap_is_serial hT hv hall a W hw
    simpa using this
  · intro q evs; exact coordination_dominates_queue T q evs
  · intro evs q h; exact coord_emulates_queue T evs q h
  · intro fps i j hij hd; exact strictly_less_invalidation fps i j hij hd
  · intro c Tst X Ls hc hpass hLs
    rw [verdict_stable_seq c Tst hc Ls hLs X]
    exact hpass
  · intro c Tst Ls h0 hc hL hd
    cases Ls with
    | nil => rfl
    | cons l rest =>
      exfalso
      have hl0 : 0 ∈ l.fp := hL l (List.mem_cons_self ..)
      exact hd l (List.mem_cons_self ..) 0 hl0 (hc 0 h0)
  · intro timeout gs h; exact cliff_zero timeout gs h
  · intro mv D h; exact starved_never_completes mv D h
  · intro ahead behind; exact ⟨cascade_no_merge_behind ahead behind, cascade_used_le ahead behind⟩
  · intro layers; exact stack_all_or_nothing layers
  · intro l m D t hlm ht; exact drain_exact l m D t hlm ht

end MergeQueueSpeedLimit
