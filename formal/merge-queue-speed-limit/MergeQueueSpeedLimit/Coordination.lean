/-
  MergeQueueSpeedLimit.Coordination: claim 5, the coordination bound.

  Changes are partitioned into `k` regions. A change holds the regions in
  its footprint while it validates, and two changes that share a region
  cannot overlap, with a gap `L` (the coordination latency: the time for a
  claim to become visible) between them. Each run takes at least `T`.

  What is proved, all inside `Valid k T L` (Occupancy.lean):
    * landings in a window of length W  <=  k * ((W + L) / (T + L)).
    * if EVERY pair of changes overlaps (o = 1) the bound is the serial one,
      whatever k is: coordination cannot beat serial.
    * a hub (a change holding all k regions) excludes every other change for
      its whole duration, and h hubs cost every region h attempts' worth of
      its `(W + L) / (T + L)` slots.
    * latency never helps: `(W + L) / (T + L) <= W / T`.

  The model takes the partition and the footprints as given. That a real
  change's footprint is what the plan board says it is, is the "test reads
  only its footprint" trust hypothesis in Staleness.lean, not proved here.
-/
import MergeQueueSpeedLimit.Occupancy

namespace MergeQueueSpeedLimit

/-- Claim 5: `k` regions, each serial with runs at least `T` and gap `L`. -/
theorem coordination_ceiling {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) :
    js.length ≤ k * ((W + L) / (T + L)) :=
  ceiling_contained hT hv a W hw

/-- Latency never helps: the padded bound is at most the unpadded one. -/
theorem latency_never_helps (T L W : Nat) (hT : 0 < T) : (W + L) / (T + L) ≤ W / T := by
  refine (Nat.le_div_iff_mul_le hT).2 ?_
  have hq : (W + L) / (T + L) * (T + L) ≤ W + L := Nat.div_mul_le_self _ _
  rcases Nat.eq_zero_or_pos ((W + L) / (T + L)) with h0 | hpos
  · rw [h0]; omega
  · rw [Nat.mul_add] at hq
    have : L ≤ (W + L) / (T + L) * L := Nat.le_mul_of_pos_left L hpos
    omega

/-- `o = 1`: every pair of changes overlaps. Then k is irrelevant and the bound
    is the serial one, `(W + L) / (T + L)`, which is `W / T` at zero latency.
    Coordination cannot beat serial when everything overlaps. -/
theorem all_overlap_is_serial {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (hall : js.Pairwise Occ.shares) (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) :
    js.length ≤ (W + L) / (T + L) := by
  let js' := js.map (fun j => ({ j with res := [0] } : Occ))
  have hv' : Valid 1 T L js' := by
    refine ⟨?_, ?_, ?_, ?_⟩
    · intro j hj
      obtain ⟨x, _, rfl⟩ := List.mem_map.1 hj
      simp
    · intro j hj r hr
      obtain ⟨x, _, rfl⟩ := List.mem_map.1 hj
      simp at hr; omega
    · intro j hj
      obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hj
      exact hv.long x hx
    · simp only [js']
      rw [List.pairwise_map]
      refine (hv.excl.and hall).imp ?_
      intro x y ⟨h1, h2⟩ _
      exact h1 h2
  have hw' : ∀ j ∈ js', InWin a W j := by
    intro j hj
    obtain ⟨x, hx, rfl⟩ := List.mem_map.1 hj
    exact hw x hx
  have := ceiling_contained hT hv' a W hw'
  simpa [js'] using this

/-- A hub holds every region: it shares one with every job. -/
def Hub (k : Nat) (j : Occ) : Prop := ∀ r, r < k → r ∈ j.res

/-- A hub excludes everything else for its whole duration: any other job in
    the schedule finishes (plus the gap) before the hub starts, or starts
    after the hub ends (plus the gap). -/
theorem hub_excludes {k T L : Nat} {pre post : List Occ} {h : Occ}
    (hv : Valid k T L (pre ++ h :: post)) (hh : Hub k h) :
    ∀ j ∈ pre ++ post, h.f + L ≤ j.s ∨ j.f + L ≤ h.s := by
  have hex := hv.excl
  rw [List.pairwise_append, List.pairwise_cons] at hex
  obtain ⟨_, ⟨hpost, _⟩, hcross⟩ := hex
  intro j hj
  have hjmem : j ∈ pre ++ h :: post := by
    rcases List.mem_append.1 hj with h1 | h1
    · exact List.mem_append_left _ h1
    · exact List.mem_append_right _ (List.mem_cons_of_mem _ h1)
  obtain ⟨r, hr⟩ := List.exists_mem_of_ne_nil _ (hv.nonempty j hjmem)
  have hsh : j.shares h := ⟨r, hr, hh r (hv.inRange j hjmem r hr)⟩
  have hsh' : h.shares j := ⟨r, hh r (hv.inRange j hjmem r hr), hr⟩
  rcases List.mem_append.1 hj with h1 | h1
  · have := hcross j h1 h (List.mem_cons_self ..) hsh
    omega
  · exact hpost j h1 hsh'

/-- The cost of hubs. In any region `r`, the hubs and the non-hub changes that
    hold `r` together fit in `(W + L) / (T + L)` slots. So `h` hubs take `h` of
    every region's slots, not of one. -/
theorem hub_cost {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) (H : Occ → Bool) (hH : ∀ j, H j = true → Hub k j)
    (r : Nat) (hr : r < k) :
    ((js.filter (fun j => decide (r ∈ j.res) && !H j)).length + (js.filter H).length)
      ≤ (W + L) / (T + L) := by
  refine (Nat.le_div_iff_mul_le (by omega)).2 ?_
  let ws := js.filter (fun j => decide (r ∈ j.res))
  have hws : ws.length * (T + L) ≤ W + L :=
    region_pack hv a W hw r ws List.filter_sublist
      (fun j hj => of_decide_eq_true (List.mem_filter.1 hj).2)
  have hsplit := filter_len_add H ws
  have h1 : ws.filter H = js.filter H := by
    simp only [ws, List.filter_filter]
    apply List.filter_congr
    intro x hx
    cases hxH : H x
    · simp
    · simp [hH x hxH r hr]
  have h2 : ws.filter (fun a => !H a) = js.filter (fun j => decide (r ∈ j.res) && !H j) := by
    simp only [ws, List.filter_filter]
    apply List.filter_congr
    intro x hx
    cases H x <;> simp
  rw [h1, h2] at hsplit
  have : ((js.filter H).length + (js.filter (fun j => decide (r ∈ j.res) && !H j)).length) =
      ws.length := hsplit
  rw [Nat.add_comm, this]
  exact hws

/-- Total landings with hubs: the non-hub changes number at most
    `k * (cap - h)` where `cap = (W + L) / (T + L)` and `h` is the number of
    hubs. Every hub costs every region a slot. -/
theorem hubs_total {k T L : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid k T L js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) (H : Occ → Bool) (hH : ∀ j, H j = true → Hub k j) :
    js.length ≤ (js.filter H).length +
      k * ((W + L) / (T + L) - (js.filter H).length) := by
  let N := js.filter (fun j => !H j)
  have hN : N.length ≤ k * ((W + L) / (T + L) - (js.filter H).length) := by
    refine peel _ k N ?_ ?_
    · intro j hj
      have hj' := (List.mem_filter.1 hj).1
      exact ⟨hv.nonempty j hj', hv.inRange j hj'⟩
    · intro r hr ys hys hall
      have hys' : ys.Sublist js := hys.trans List.filter_sublist
      have hsub : ys.Sublist (js.filter (fun j => decide (r ∈ j.res) && !H j)) := by
        have := hys'.filter (fun j => decide (r ∈ j.res) && !H j)
        have heq : ys.filter (fun j => decide (r ∈ j.res) && !H j) = ys := by
          rw [List.filter_eq_self]
          intro x hx
          have hxN := (List.mem_filter.1 (hys.subset hx)).2
          simpa [hall x hx] using hxN
        rwa [heq] at this
      have := hub_cost hT hv a W hw H hH r hr
      have := hsub.length_le
      omega
  have := filter_len_add H js
  have hNe : N.length = (js.filter (fun a => !H a)).length := rfl
  omega

/-! ### k regions are reachable; k = 1 is exactly the serial case. -/

/-- Three regions, each running two back-to-back 2-minute changes. -/
def threeLanes : List Occ :=
  [⟨[0], 0, 2, 1⟩, ⟨[0], 2, 4, 1⟩, ⟨[1], 0, 2, 1⟩, ⟨[1], 2, 4, 1⟩, ⟨[2], 0, 2, 1⟩, ⟨[2], 2, 4, 1⟩]

theorem threeLanes_valid : Valid 3 2 0 threeLanes :=
  ⟨by decide, by decide, by decide, by decide⟩

/-- Tight: window `[0, 4]`, `T = 2`: `3 * (4 / 2) = 6` landings. -/
theorem coordination_ceiling_tight :
    (∀ j ∈ threeLanes, InWin 0 4 j) ∧ threeLanes.length = 3 * ((4 + 0) / (2 + 0)) := by
  refine ⟨?_, by decide⟩
  intro j hj
  simp only [threeLanes, List.mem_cons, List.not_mem_nil, or_false] at hj
  rcases hj with rfl | rfl | rfl | rfl | rfl | rfl <;> simp [InWin]

end MergeQueueSpeedLimit
