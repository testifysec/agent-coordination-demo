/-
  MergeQueueSpeedLimit.MasterExt: three extensions of the master theorem, from
  measurement, from a non-atomic lander, and from the lander's service time.

  (1) LANES FROM MEASUREMENT. The abstract `k` regions of Coordination.lean
      are replaced by one measured number: the share of landings that touch
      the busiest region. If no region can carry more than `R = (W+L)/(T+L)`
      landings in a window (`region_pack`) and the busiest holds at least the
      fraction `num/den` of ALL landings, then in total
          landings <= R * den / num.
      The number of regions, and so the size of the repository, does not
      appear. Only concentration does. (Measured lanes, from the coordinator:
      ours 4, Go 9, Kubernetes 13, Linux 23. That a bigger repository does
      not reduce concentration is EMPIRICAL, not proved here.)

  (2) NON-ATOMIC LANDING. A GitHub Action shim checks at time `tc` and merges
      at `tl >= tc`. Hypothesis H7 (LOCK): any two landings whose claimed
      footprints overlap hold a lock over `[tc, tl]`, so their intervals are
      disjoint. Under H7 the safety of Master part 3 survives; without it an
      explicit counterexample has two overlapping landings both passing their
      checks and the landed tree failing the test.

  (3) LANDER SERVICE CEILING. Hypothesis H8: each landing occupies its
      serialization group for at least `s` minutes (check to merge, lock
      included). With `g` groups the landings in a window number at most
      `g * (W / s)`. Throughput is at most the least of this and the
      validation bound (`merge_speed_limit_master_measured`).

  Variable names: `s` (service time), `g` (groups), `num`/`den` (busiest-region
  fraction), `R` (per-region bound). `a` stays the window start.
-/
import MergeQueueSpeedLimit.Master

namespace MergeQueueSpeedLimit

/-! ### (1) Lanes from measurement. -/

/-- If the busiest region (index `r0`) holds at least `num/den` of all landings,
    landings are at most `R * den / num`, with `R` the per-region bound. `k` does
    not appear in the conclusion. -/
theorem concentration_ceiling {k T L : Nat} (hT : 0 < T) {js : List Occ}
    (hv : Valid k T L js) (a W : Nat) (hw : ∀ j ∈ js, InWin a W j)
    (r0 num den : Nat) (hnum : 0 < num)
    (hbusy : num * js.length ≤ den * (js.filter (fun j => decide (r0 ∈ j.res))).length) :
    js.length ≤ ((W + L) / (T + L)) * den / num := by
  have hn0 : (js.filter (fun j => decide (r0 ∈ j.res))).length * (T + L) ≤ W + L :=
    region_pack hv a W hw r0 _ List.filter_sublist
      (fun j hj => of_decide_eq_true (List.mem_filter.1 hj).2)
  have hR : (js.filter (fun j => decide (r0 ∈ j.res))).length ≤ (W + L) / (T + L) :=
    (Nat.le_div_iff_mul_le (by omega)).2 hn0
  refine (Nat.le_div_iff_mul_le hnum).2 ?_
  have h1 : den * (js.filter (fun j => decide (r0 ∈ j.res))).length ≤ den * ((W + L) / (T + L)) :=
    Nat.mul_le_mul_left den hR
  calc js.length * num = num * js.length := Nat.mul_comm _ _
    _ ≤ den * (js.filter (fun j => decide (r0 ∈ j.res))).length := hbusy
    _ ≤ den * ((W + L) / (T + L)) := h1
    _ = (W + L) / (T + L) * den := Nat.mul_comm _ _

/-! ### (2) Non-atomic landing. -/

/-- A landing: the change, the footprint it claims (the test's footprint, which
    covers the change's), the time the check passed and the time it merged. -/
structure Landing where
  ch : Change
  claim : List Nat
  tc : Nat
  tl : Nat
  cover : ∀ r ∈ ch.fp, r ∈ claim
  ord : tc ≤ tl

/-- H7, the lock: two landings with overlapping claims have disjoint
    `[tc, tl]` intervals. -/
def LockedPair (c l : Landing) : Prop := Disjoint l.claim c.claim ∨ l.tl < c.tc ∨ c.tl < l.tc

/-- SAFETY SURVIVES A NON-ATOMIC LANDER UNDER THE LOCK. `c` passed its test
    `Tst` (footprint = its claim) on base `X`. `Ls` are the landings that
    merged after that base and before `c` does, each with a change inside its
    claim. Two hypotheses: the check at `tc` saw no overlapping landing since
    the base (CAS), and the lock H7 holds. Then the verdict still holds on the
    tree that actually lands. -/
theorem nonatomic_safe (c : Landing) (Tst : Test) (hT : Tst.fp = c.claim) (X : Tree)
    (Ls : List Landing)
    (hbefore : ∀ l ∈ Ls, l.tl < c.tl)
    (hcas : ∀ l ∈ Ls, l.tl ≤ c.tc → Disjoint l.claim c.claim)
    (hlock : ∀ l ∈ Ls, LockedPair c l)
    (hpass : Tst.run (c.ch.apply X) = true) :
    Tst.run (c.ch.apply (landAll (Ls.map Landing.ch) X)) = true := by
  have hdis : ∀ l ∈ Ls, Disjoint l.ch.fp Tst.fp := by
    intro l hl r hr hrT
    have hcl : Disjoint l.claim c.claim := by
      by_cases h : l.tl ≤ c.tc
      · exact hcas l hl h
      · rcases hlock l hl with h1 | h1 | h1
        · exact h1
        · omega
        · have := l.ord; have := hbefore l hl; omega
    rw [hT] at hrT
    exact hcl r (l.cover r hr) hrT
  have hc : ∀ r ∈ c.ch.fp, r ∈ Tst.fp := by
    intro r hr; rw [hT]; exact c.cover r hr
  rw [verdict_stable_seq c.ch Tst hc (Ls.map Landing.ch)
    (by intro l hl; obtain ⟨l', hl', rfl⟩ := List.mem_map.1 hl; exact hdis l' hl') X]
  exact hpass

/-- WITHOUT THE LOCK, two overlapping landings both pass. Two changes `inc0`
    (footprint region 0) check at time 0 against the same base and merge at 1 and
    2. The second's CAS at `tc = 0` sees nothing landed, so it passes; the check
    of each on the base passes; the lock fails; and the landed tree fails the
    test. -/
def lc : Landing := ⟨inc0, [0], 0, 1, by simp [inc0], by omega⟩
def ld : Landing := ⟨inc0, [0], 0, 2, by simp [inc0], by omega⟩

theorem lock_needed :
    -- ld's check passes on the base, and so does lc's
    isOne.run (inc0.apply (fun _ => 0)) = true ∧
    -- the CAS at ld's check time sees no overlapping landing (lc merges at 1 > 0)
    (∀ l ∈ [lc], l.tl ≤ ld.tc → Disjoint l.claim ld.claim) ∧
    -- but the lock fails: the intervals [0,1] and [0,2] overlap, claims overlap
    ¬ LockedPair ld lc ∧
    -- and ld lands on a tree where its test fails
    isOne.run (ld.ch.apply (landAll ([lc].map Landing.ch) (fun _ => 0))) = false := by
  refine ⟨?_, ?_, ?_, ?_⟩
  · simp [isOne, inc0, Change.apply]
  · intro l hl h
    simp [lc, ld] at hl h
    subst hl
    simp [lc, ld] at h
  · simp only [LockedPair, lc, ld, not_or]
    refine ⟨?_, by omega, by omega⟩
    intro h
    have := h 0 (by simp) (by simp)
    exact this
  · simp [isOne, inc0, Change.apply, landAll, ld, lc]

/-! ### (3) The lander's service ceiling. -/

/-- H8: each landing occupies its serialization group (one of `g`) for at least
    `s` minutes. Then at most `g * (W / s)` landings fit in a window, counting
    the services that both START and FINISH inside it (`InWin`): with one group
    and `s = 10`, a service that finishes inside a 5-minute window began before
    it and is not counted. -/
theorem lander_service_ceiling {g s : Nat} (hs : 0 < s) {sv : List Occ} (hv : Valid g s 0 sv)
    (a W : Nat) (hw : ∀ j ∈ sv, InWin a W j) : sv.length ≤ g * (W / s) := by
  have := ceiling_contained hs hv a W hw
  simpa using this

/-! ### (4) Machine minutes and the collapsed speed limit. -/

/-- Attempts are tagged with the change that owns them, and ownership is
    EXCLUSIVE: an attempt is credited to one change. If each of the distinct
    landed changes `ls` owns at least `r` attempts, there are at least `r` times
    as many attempts as landings. A build that validates two changes is credited to
    one of them, so for batches the bound applies only when every landed change has
    `r` separately credited attempts. -/
theorem attempts_cover (r : Nat) : ∀ (ls os : List Nat), ls.Nodup →
    (∀ i ∈ ls, r ≤ os.count i) → r * ls.length ≤ os.length := by
  intro ls
  induction ls with
  | nil => intro os _ _; simp
  | cons i rest ih =>
    intro os hnd hc
    rw [List.nodup_cons] at hnd
    have hsplit : (os.filter (fun x => x == i)).length + (os.filter (fun x => !(x == i))).length
        = os.length := filter_len_add (fun x => x == i) os
    have hcount : os.count i = (os.filter (fun x => x == i)).length := List.count_eq_length_filter
    have hrest := ih (os.filter (fun x => !(x == i))) hnd.2 (by
      intro j hj
      have hji : j ≠ i := fun e => hnd.1 (e ▸ hj)
      have h := List.count_filter (p := fun x => !(x == i)) (a := j) (l := os) (by simp [hji])
      rw [h]; exact hc j (List.mem_cons_of_mem _ hj))
    have hi := hc i (List.mem_cons_self ..)
    simp only [List.length_cons]
    rw [Nat.mul_succ]
    omega

/-- (1) MACHINE MINUTES. On `M` machines every attempt lasts at least `T` and
    runs inside the window, so there are at most `M * (W / T)` attempts. If each
    of the distinct landed changes owned at least `r` attempts (retries and
    restarts included), then `r * landings ≤ M * (W / T)`. -/
theorem machine_minutes_ceiling {M T : Nat} (hT : 0 < T) {ats : List Occ} (hv : Valid M T 0 ats)
    (a W : Nat) (hw : ∀ j ∈ ats, InWin a W j) (own : Occ → Nat) (r : Nat) (ls : List Nat)
    (hnd : ls.Nodup) (hr : ∀ i ∈ ls, r ≤ (ats.map own).count i) :
    r * ls.length ≤ M * (W / T) := by
  have h1 := attempts_cover r ls (ats.map own) hnd hr
  have h2 := lanes_ceiling hT hv a W hw
  simp only [List.length_map] at h1
  omega

/-- The same in division form: `landings ≤ M * ⌊W/T⌋ / r`. -/
theorem machine_minutes_ceiling_div {M T : Nat} (hT : 0 < T) {ats : List Occ} (hv : Valid M T 0 ats)
    (a W : Nat) (hw : ∀ j ∈ ats, InWin a W j) (own : Occ → Nat) (r : Nat) (hr0 : 0 < r)
    (ls : List Nat) (hnd : ls.Nodup) (hr : ∀ i ∈ ls, r ≤ (ats.map own).count i) :
    ls.length ≤ M * (W / T) / r := by
  have := machine_minutes_ceiling hT hv a W hw own r ls hnd hr
  exact (Nat.le_div_iff_mul_le hr0).2 (by rw [Nat.mul_comm]; exact this)

/-- (2) THE COLLAPSED SPEED LIMIT, agents. Landings are at most the least of the
    machine bound `M * ⌊W/T⌋ / r` and the region bound `k * ⌊(W+L)/(T+L)⌋`. -/
theorem speed_limit_collapsed {M k T L : Nat} (hT : 0 < T) {ats js : List Occ}
    (hvm : Valid M T 0 ats) (hvk : Valid k T L js) (a W : Nat)
    (hwa : ∀ j ∈ ats, InWin a W j) (hwj : ∀ j ∈ js, InWin a W j)
    (own : Occ → Nat) (r : Nat) (hr0 : 0 < r) (ls : List Nat) (hnd : ls.Nodup)
    (hr : ∀ i ∈ ls, r ≤ (ats.map own).count i) (hlen : js.length = ls.length) :
    ls.length ≤ min (M * (W / T) / r) (k * ((W + L) / (T + L))) := by
  refine Nat.le_min.2 ⟨machine_minutes_ceiling_div hT hvm a W hwa own r hr0 ls hnd hr, ?_⟩
  rw [← hlen]; exact coordination_ceiling hT hvk a W hwj

/-- The queue form: landings are at most the least of `B * C * ⌊W/T⌋` (C builds,
    B changes each) and the machine bound. `hland`: each landed change is counted in
    some build's `w`. -/
theorem queue_collapsed {M C B T : Nat} (hT : 0 < T) {ats js : List Occ}
    (hvm : Valid M T 0 ats) (hvc : Valid C T 0 js) (a W : Nat)
    (hwa : ∀ j ∈ ats, InWin a W j) (hwj : ∀ j ∈ js, InWin a W j) (hB : ∀ j ∈ js, j.w ≤ B)
    (own : Occ → Nat) (r : Nat) (hr0 : 0 < r) (ls : List Nat) (hnd : ls.Nodup)
    (hr : ∀ i ∈ ls, r ≤ (ats.map own).count i) (hland : ls.length ≤ (js.map Occ.w).sum) :
    ls.length ≤ min (B * C * (W / T)) (M * (W / T) / r) := by
  refine Nat.le_min.2 ⟨?_, machine_minutes_ceiling_div hT hvm a W hwa own r hr0 ls hnd hr⟩
  exact Nat.le_trans hland (batched_ceiling hT hvc a W hwj hB)

/-- THE MEASURED MASTER THEOREM: the master theorem, and the three extensions. -/
theorem merge_speed_limit_master_measured (T k C L W a : Nat) (hT : 0 < T) (s g M r : Nat) (hs : 0 < s) (hr0 : 0 < r) :
    -- the whole master theorem, unchanged
    MasterProp T k C L W a ∧
    -- (1) concentration, not size
    (∀ (js : List Occ) (r0 num den : Nat), Valid k T L js → (∀ j ∈ js, InWin a W j) → 0 < num →
      num * js.length ≤ den * (js.filter (fun j => decide (r0 ∈ j.res))).length →
      js.length ≤ ((W + L) / (T + L)) * den / num) ∧
    -- (2) safety under the lock
    (∀ (c : Landing) (Tst : Test) (X : Tree) (Ls : List Landing), Tst.fp = c.claim →
      (∀ l ∈ Ls, l.tl < c.tl) → (∀ l ∈ Ls, l.tl ≤ c.tc → Disjoint l.claim c.claim) →
      (∀ l ∈ Ls, LockedPair c l) → Tst.run (c.ch.apply X) = true →
      Tst.run (c.ch.apply (landAll (Ls.map Landing.ch) X)) = true) ∧
    -- (3) throughput is at most the least of the validation bound and the service bound
    (∀ js sv : List Occ, sv.length = js.length → Valid k T L js → Valid g s 0 sv →
      (∀ j ∈ js, InWin a W j) → (∀ j ∈ sv, InWin a W j) →
      js.length ≤ min (k * ((W + L) / (T + L))) (g * (W / s))) ∧
    -- (4) machine minutes, and the collapsed speed limit for agents
    (∀ (ats js : List Occ) (own : Occ → Nat) (ls : List Nat), Valid M T 0 ats → Valid k T L js →
      (∀ j ∈ ats, InWin a W j) → (∀ j ∈ js, InWin a W j) → ls.Nodup →
      (∀ i ∈ ls, r ≤ (ats.map own).count i) → js.length = ls.length →
      ls.length ≤ min (M * (W / T) / r) (k * ((W + L) / (T + L)))) := by
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · exact merge_speed_limit_master T k C L W a hT
  · intro js r0 num den hv hw hnum hbusy
    exact concentration_ceiling hT hv a W hw r0 num den hnum hbusy
  · intro c Tst X Ls hT' hb hc hl hp
    exact nonatomic_safe c Tst hT' X Ls hb hc hl hp
  · intro js sv hlen hv1 hv2 hw1 hw2
    refine Nat.le_min.2 ⟨coordination_ceiling hT hv1 a W hw1, ?_⟩
    rw [← hlen] at *
    have := lander_service_ceiling hs hv2 a W hw2
    omega
  · intro ats js own ls hvm hvk hwa hwj hnd hr hlen
    exact speed_limit_collapsed hT hvm hvk a W hwa hwj own r hr0 ls hnd hr hlen

end MergeQueueSpeedLimit
