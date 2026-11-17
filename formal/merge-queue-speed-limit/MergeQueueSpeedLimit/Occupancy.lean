/-
  MergeQueueSpeedLimit.Occupancy: ceilings for anything that occupies resources.

  A JOB holds one or more RESOURCES for a stretch of time. Resources are the
  serial validator (claim 1), the C build lanes (claim 1 with concurrency),
  or the regions of a repository (claim 5). Two jobs that share a resource
  cannot overlap, and may need a gap `L` between them (the coordination
  latency). Every job is at least `T` long.

  From that alone, in any window of length `W`:

    jobs that run entirely inside the window  <=  k * ((W + L) / (T + L))
    jobs that FINISH inside the window        <=  k * (W / (T + L) + 1)

  where k is the number of resources. The second has a `+ 1` per resource:
  a job that started before the window can still finish in it. That is not
  pedantry. It is the difference between "at most 10 merges in the last
  hour" and "at most 11", and a simulation that counts merge TIMES in a
  trailing window (queueFlowSim's `mergeTimes`) is counting the second thing.

  Trust hypotheses, named here once so the README can point at them:
    * `T` is a LOWER bound on every attempt, not a mean or a median.
      (Valid.long). A distribution with mass below its median breaks a
      bound stated at the median. That step is stochastic and is not proved.
    * Lanes: a schedule with at most C builds running at once can be split
      into C lanes (interval graphs are perfect). The model takes the lane
      assignment as given, as the simulator does (`lane` in queueFlowSim).
-/
import MergeQueueSpeedLimit.Pack

namespace MergeQueueSpeedLimit

/-- A job: the resources it holds, when it starts and finishes, and how many
    changes it lands when it completes (`w`, at most B per build). -/
structure Occ where
  res : List Nat
  s : Nat
  f : Nat
  w : Nat
deriving Repr, DecidableEq

/-- Two jobs share a resource. -/
def Occ.shares (j j' : Occ) : Prop := ∃ r ∈ j.res, r ∈ j'.res

instance (j j' : Occ) : Decidable (j.shares j') := inferInstanceAs (Decidable (∃ r ∈ j.res, r ∈ j'.res))

/-- A valid schedule over `k` resources: every job holds at least one
    resource among the first `k`, lasts at least `T`, and any two jobs that
    share a resource are separated by at least `L`. -/
structure Valid (k T L : Nat) (js : List Occ) : Prop where
  nonempty : ∀ j ∈ js, j.res ≠ []
  inRange : ∀ j ∈ js, ∀ r ∈ j.res, r < k
  long : ∀ j ∈ js, j.s + T ≤ j.f
  excl : js.Pairwise (fun j j' => j.shares j' → j.f + L ≤ j'.s ∨ j'.f + L ≤ j.s)

theorem Valid.sublist {k T L : Nat} {js ys : List Occ} (h : Valid k T L js) (hs : ys.Sublist js) :
    Valid k T L ys :=
  ⟨fun j hj => h.nonempty j (hs.subset hj), fun j hj => h.inRange j (hs.subset hj),
   fun j hj => h.long j (hs.subset hj), h.excl.sublist hs⟩

/-- Counting by resource: if every resource carries at most `cap` of the
    jobs (for every sub-collection that all hold it), then the whole
    collection has at most `k * cap` jobs, because each job holds at least one
    of the `k` resources. -/
theorem peel (cap : Nat) : ∀ (k : Nat) (ws : List Occ),
    (∀ j ∈ ws, j.res ≠ [] ∧ ∀ r ∈ j.res, r < k) →
    (∀ r, r < k → ∀ ys : List Occ, ys.Sublist ws → (∀ j ∈ ys, r ∈ j.res) → ys.length ≤ cap) →
    ws.length ≤ k * cap := by
  intro k
  induction k with
  | zero =>
    intro ws h _
    cases ws with
    | nil => simp
    | cons j rest =>
      obtain ⟨hne, hlt⟩ := h j (List.mem_cons_self ..)
      obtain ⟨r, hr⟩ := List.exists_mem_of_ne_nil _ hne
      have := hlt r hr
      omega
  | succ k ih =>
    intro ws h hreg
    let A := ws.filter (fun j => decide (k ∈ j.res))
    let Bs := ws.filter (fun j => !decide (k ∈ j.res))
    have hA : A.length ≤ cap :=
      hreg k (Nat.lt_succ_self k) A List.filter_sublist
        (fun j hj => of_decide_eq_true (List.mem_filter.1 hj).2)
    have hB : Bs.length ≤ k * cap := by
      refine ih Bs ?_ ?_
      · intro j hj
        have hj' := List.mem_filter.1 hj
        obtain ⟨hne, hlt⟩ := h j hj'.1
        refine ⟨hne, fun r hr => ?_⟩
        have h1 := hlt r hr
        have h2 : k ∉ j.res := by simpa using hj'.2
        have : r ≠ k := fun e => h2 (e ▸ hr)
        omega
      · intro r hr ys hys hall
        exact hreg r (by omega) ys (hys.trans List.filter_sublist) hall
    have : A.length + Bs.length = ws.length := filter_len_add (fun j : Occ => decide (k ∈ j.res)) ws
    rw [Nat.succ_mul]
    omega

/-- Jobs that run ENTIRELY inside `[a, a + W]`. -/
def InWin (a W : Nat) (j : Occ) : Prop := a ≤ j.s ∧ j.f ≤ a + W

/-- THE CEILING. In a valid schedule over `k` resources with minimum length
    `T` and gap `L`, at most `k * ((W + L) / (T + L))` jobs run entirely in
    any window of length `W`. -/
theorem region_pack {k T L : Nat} {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) (r : Nat) (ys : List Occ) (hys : ys.Sublist js)
    (hall : ∀ j ∈ ys, r ∈ j.res) : ys.length * (T + L) ≤ W + L := by
  have hvy := hv.sublist hys
  have hpw : (ys.map (fun j => (⟨j.s, j.f + L⟩ : Iv))).Pairwise Disj := by
    rw [List.pairwise_map]
    refine hvy.excl.imp_of_mem ?_
    intro x y hx hy hxy
    have := hxy ⟨r, hall x hx, hall y hy⟩
    unfold Disj
    simpa using this
  have := pack (T + L) _ _ a (W + L) rfl hpw (by
    intro p hp
    obtain ⟨j, hj, rfl⟩ := List.mem_map.1 hp
    have h1 := hvy.long j hj
    have h2 := hw j (hys.subset hj)
    unfold InWin at h2
    simp only
    omega)
  simpa using this

theorem ceiling_contained {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) :
    js.length ≤ k * ((W + L) / (T + L)) := by
  refine peel _ k js (fun j hj => ⟨hv.nonempty j hj, hv.inRange j hj⟩) ?_
  intro r _ ys hys hall
  exact (Nat.le_div_iff_mul_le (by omega)).2 (region_pack hv a W hw r ys hys hall)

/-- Jobs that FINISH inside `[a, a + W]`, wherever they started. -/
def FinWin (a W : Nat) (j : Occ) : Prop := a ≤ j.f ∧ j.f ≤ a + W

/-- The same ceiling for completions: one extra job per resource, because a
    job that began before the window can finish in it. -/
theorem ceiling_completions {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, FinWin a W j) :
    js.length ≤ k * (W / (T + L) + 1) := by
  refine peel _ k js (fun j hj => ⟨hv.nonempty j hj, hv.inRange j hj⟩) ?_
  intro r _ ys hys hall
  have hvy := hv.sublist hys
  have hpw : (ys.map (fun j => (⟨j.f, j.f + (T + L)⟩ : Iv))).Pairwise Disj := by
    rw [List.pairwise_map]
    refine hvy.excl.imp_of_mem ?_
    intro x y hx hy hxy
    have h := hxy ⟨r, hall x hx, hall y hy⟩
    have hlx := hvy.long x hx
    have hly := hvy.long y hy
    unfold Disj
    simp only
    omega
  have key := pack (T + L) _ _ a (W + (T + L)) rfl hpw (by
    intro p hp
    obtain ⟨j, hj, rfl⟩ := List.mem_map.1 hp
    have h2 := hw j (hys.subset hj)
    unfold FinWin at h2
    simp only
    omega)
  simp only [List.length_map] at key
  have hle : ys.length ≤ (W + (T + L)) / (T + L) := (Nat.le_div_iff_mul_le (by omega)).2 key
  rwa [Nat.add_div_right _ (by omega)] at hle

/-- Weighted: if every job lands at most `B` changes, the landed total is at
    most `B` times the number of jobs. -/
theorem weight_le (B : Nat) : ∀ js : List Occ, (∀ j ∈ js, j.w ≤ B) →
    (js.map Occ.w).sum ≤ B * js.length := by
  intro js
  induction js with
  | nil => simp
  | cons j rest ih =>
    intro h
    have h1 := h j (List.mem_cons_self ..)
    have h2 := ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
    simp only [List.map_cons, List.sum_cons, List.length_cons]
    rw [Nat.mul_succ]
    omega

end MergeQueueSpeedLimit
