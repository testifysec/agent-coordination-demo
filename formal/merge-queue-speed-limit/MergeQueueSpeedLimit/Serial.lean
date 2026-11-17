/-
  MergeQueueSpeedLimit.Serial: claim 1 (the serial ceiling, with concurrency C and
  batch B) and claim 8 (reuse), on top of Occupancy.lean.

  A queue that validates one candidate at a time, each attempt taking at
  least `T` minutes, is `Valid 1 T 0`: one resource, no gap. With C builds in
  flight there are C lanes (`Valid C T 0`). With B changes landed per build
  each job carries weight `w ≤ B`.

  Fence post. "At most ⌊W/T⌋ merges in any window W" is true for attempts
  that run ENTIRELY inside the window and false for merges that merely
  COMPLETE inside it: an attempt that began before the window can finish in
  it, so the completion count is ⌊W/T⌋ + 1 per lane (`serial_completions`,
  tight by `completions_fence_post`). Over a long horizon the +1 per lane
  washes out; over a one-hour window with a 5.7-minute attempt it is 11
  against 10.
-/
import MergeQueueSpeedLimit.Occupancy

namespace MergeQueueSpeedLimit

/-- Claim 1, serial: one validator, attempts at least `T`, entirely inside the
    window: at most `⌊W/T⌋`. -/
theorem serial_ceiling {T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid 1 T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) : js.length ≤ W / T := by
  have := ceiling_contained hT hv a W hw
  simpa using this

/-- Serial, counting completions: `⌊W/T⌋ + 1`. -/
theorem serial_completions {T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid 1 T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, FinWin a W j) : js.length ≤ W / T + 1 := by
  have := ceiling_completions hT hv a W hw
  simpa using this

/-- Claim 1 with `C` concurrent builds (each lane serial): at most `C * ⌊W/T⌋`. -/
theorem lanes_ceiling {C T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid C T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) : js.length ≤ C * (W / T) := by
  have := ceiling_contained hT hv a W hw
  simpa using this

/-- Claim 1 with `B` changes per build: merged changes at most `B * C * ⌊W/T⌋`. -/
theorem batched_ceiling {B C T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid C T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) (hB : ∀ j ∈ js, j.w ≤ B) :
    (js.map Occ.w).sum ≤ B * C * (W / T) := by
  have h1 := weight_le B js hB
  have h2 := lanes_ceiling hT hv a W hw
  calc (js.map Occ.w).sum ≤ B * js.length := h1
    _ ≤ B * (C * (W / T)) := Nat.mul_le_mul_left B h2
    _ = B * C * (W / T) := by rw [Nat.mul_assoc]

/-- The completion-count version of the batched ceiling. -/
theorem batched_completions {B C T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid C T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, FinWin a W j) (hB : ∀ j ∈ js, j.w ≤ B) :
    (js.map Occ.w).sum ≤ B * C * (W / T + 1) := by
  have h1 := weight_le B js hB
  have h2 := by simpa using ceiling_completions hT hv a W hw
  calc (js.map Occ.w).sum ≤ B * js.length := h1
    _ ≤ B * (C * (W / T + 1)) := Nat.mul_le_mul_left B h2
    _ = B * C * (W / T + 1) := by rw [Nat.mul_assoc]

/-! ### The bounds are tight, and the fence post is real. -/

/-- Three back-to-back 3-minute attempts. -/
def backToBack : List Occ := [⟨[0], 0, 3, 1⟩, ⟨[0], 3, 6, 1⟩, ⟨[0], 6, 9, 1⟩]

theorem backToBack_valid : Valid 1 3 0 backToBack :=
  ⟨by decide, by decide, by decide, by decide⟩

/-- Tight: window `[0, 9]` holds `9 / 3 = 3` attempts. -/
theorem serial_ceiling_tight :
    (∀ j ∈ backToBack, InWin 0 9 j) ∧ backToBack.length = 9 / 3 := by
  refine ⟨?_, by decide⟩
  intro j hj
  simp only [backToBack, List.mem_cons, List.not_mem_nil, or_false] at hj
  rcases hj with rfl | rfl | rfl <;> simp [InWin]

/-- The fence post: in the window `[3, 9]` of length 6 with `T = 3`, only two
    attempts run inside (`6 / 3`), but three COMPLETE in it. The claim "at most
    ⌊W/T⌋ merges in any window" is false for completions, and `serial_completions`
    is the corrected, tight statement. -/
theorem completions_fence_post :
    (∀ j ∈ backToBack, FinWin 3 6 j) ∧ backToBack.length = 6 / 3 + 1 ∧
    (backToBack.filter (fun j => decide (3 ≤ j.s))).length = 6 / 3 := by
  refine ⟨?_, by decide, by decide⟩
  intro j hj
  simp only [backToBack, List.mem_cons, List.not_mem_nil, or_false] at hj
  rcases hj with rfl | rfl | rfl <;> simp [FinWin]

/-! ### Claim 8: reuse.

  Skipping a fraction `r = n / d` of validation makes each attempt take
  `T (1 - r)`. Work in ticks of `1 / d` minute: an attempt is at least
  `T * (d - n)` ticks, and the window is `W * d` ticks.
-/

/-- The ceiling with reuse: `len * (T (d-n)) ≤ C * (W d)`, which reads
    `len ≤ C * (W / T) / (1 - r)`. -/
theorem reuse_ceiling {C T n d : Nat} (hT : 0 < T) (hn : n < d) {js : List Occ}
    (hv : Valid C (T * (d - n)) 0 js) (a W : Nat) (hw : ∀ j ∈ js, InWin a (W * d) j) :
    js.length ≤ C * (W * d / (T * (d - n))) := by
  have hpos : 0 < T * (d - n) := Nat.mul_pos hT (by omega)
  have := ceiling_contained hpos hv a (W * d) hw
  simpa using this

/-- Reuse never lowers the per-lane ceiling. -/
theorem reuse_bound_ge (T n d W : Nat) (hT : 0 < T) (hn : n < d) :
    W / T ≤ W * d / (T * (d - n)) := by
  have hpos : 0 < T * (d - n) := Nat.mul_pos hT (by omega)
  refine (Nat.le_div_iff_mul_le hpos).2 ?_
  have h1 : W / T * T ≤ W := Nat.div_mul_le_self W T
  calc W / T * (T * (d - n)) = (W / T * T) * (d - n) := by rw [Nat.mul_assoc]
    _ ≤ W * (d - n) := Nat.mul_le_mul_right _ h1
    _ ≤ W * d := Nat.mul_le_mul_left _ (Nat.sub_le d n)

/-- The scaling is exactly `1 / (1 - r) = d / (d - n)` when `T` divides `W`:
    with `W = q T`, the ceiling per lane is `⌊q d / (d - n)⌋`. -/
theorem reuse_scale_exact (T n d q : Nat) (hT : 0 < T) :
    (T * q) * d / (T * (d - n)) = (q * d) / (d - n) := by
  rw [Nat.mul_assoc]
  exact Nat.mul_div_mul_left (q * d) (d - n) hT

/-! ### In-order merging: merges versus finishes.

  Everything above counts attempts by when they FINISH. A merge queue merges
  in order, so a finished build can wait behind a slower one ahead of it
  (Cascade.lean, `hol_loss_iff`) and merge later. A window's MERGES can then
  exceed its FINISHES, but only by the builds that were finished and waiting
  when the window opened, and those still hold a pipeline slot. If at most
  `C` slots exist, at most `C` of them. (Hypothesis `hpipe` is that slot
  limit: the simulator's finished build holds its lane until it merges, and
  the post says it has not checked GitHub does the same.)
-/

theorem count_union_le {α : Type} (P Q R : α → Bool) :
    ∀ l : List α, (∀ x ∈ l, P x = true → Q x = true ∨ R x = true) →
      (l.filter P).length ≤ (l.filter Q).length + (l.filter R).length := by
  intro l
  induction l with
  | nil => simp
  | cons x rest ih =>
    intro h
    have h1 := ih (fun y hy => h y (List.mem_cons_of_mem _ hy))
    have h2 := h x (List.mem_cons_self ..)
    simp only [List.filter_cons]
    cases hp : P x <;> cases hq : Q x <;> cases hr : R x <;> simp_all <;> omega

/-- Merges in `[a, a + W]` are at most the finishes in it plus the pipeline
    capacity `C`. `m j` is the merge time of attempt `j`, at or after its finish. -/
theorem merges_vs_finishes (js : List Occ) (m : Occ → Nat) (hm : ∀ j ∈ js, j.f ≤ m j)
    (a W C : Nat)
    (hpipe : (js.filter (fun j => decide (j.f < a) && decide (a ≤ m j))).length ≤ C) :
    (js.filter (fun j => decide (a ≤ m j) && decide (m j ≤ a + W))).length ≤
      (js.filter (fun j => decide (a ≤ j.f) && decide (j.f ≤ a + W))).length + C := by
  have := count_union_le (fun j : Occ => decide (a ≤ m j) && decide (m j ≤ a + W))
    (fun j => decide (a ≤ j.f) && decide (j.f ≤ a + W))
    (fun j => decide (j.f < a) && decide (a ≤ m j)) js (by
      intro x hx hp
      have := hm x hx
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hp ⊢
      omega)
  omega

end MergeQueueSpeedLimit
