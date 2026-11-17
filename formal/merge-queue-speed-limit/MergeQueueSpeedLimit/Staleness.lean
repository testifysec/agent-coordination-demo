/-
  MergeQueueSpeedLimit.Staleness: claim 4, agent-loop staleness.

  An agent validates a change against a base `X` and then tries to land it.
  The landing is a compare-and-swap: it succeeds only if the base has not
  moved in a way that matters.

  Proved:
    * `commute`: two changes with disjoint footprints give the same tree in
      either order.
    * `verdict_stable_seq`: a test that reads only footprint `F` keeps its
      verdict across any sequence of landings whose footprints miss `F`.
    * `main_cas_implies_region_cas`: whole-main CAS succeeding implies
      region CAS succeeding, and `region_cas_strictly_weaker` shows the
      converse fails. So the rule "lands if nothing overlapping landed" is
      strictly more permissive than "lands if main is still X".
    * `overlap_can_invalidate`: a landing that overlaps CAN flip a verdict.
    * `agent_starved`: if overlapping landings arrive at least once per run
      duration D, no run started after the first one ever lands (this is
      Queue.starved_never_completes).

  TRUST HYPOTHESES (named so the README can point at them, never proved):
    * `Change.reads_fp`: a change's new value for a region depends only on the
      old values in its own footprint. This is "the change is local".
    * `Test.reads`: a test's verdict depends only on the values in its
      footprint F. This is "the test reads only its footprint". Real tests
      read the whole tree (a type checker, a linker, a shared fixture), so for
      a real repository this hypothesis is the load-bearing, false-in-general
      assumption of the agent-coordination design: the plan board's
      footprints are only as good as it is. A wrong footprint breaks
      `verdict_stable_seq`, not the algebra.
-/
import MergeQueueSpeedLimit.Queue

namespace MergeQueueSpeedLimit

/-- A tree: one value per region. -/
abbrev Tree := Nat → Nat

/-- A change: a footprint, and for each region what it writes given the old
    tree. `reads_fp` is the trust hypothesis: the writes depend only on the old
    values inside the footprint. -/
structure Change where
  fp : List Nat
  upd : Tree → Nat → Nat
  reads_fp : ∀ t t' : Tree, (∀ r ∈ fp, t r = t' r) → ∀ r ∈ fp, upd t r = upd t' r

/-- Apply a change: inside the footprint the new value, outside nothing moves. -/
def Change.apply (c : Change) (t : Tree) : Tree := fun r => if r ∈ c.fp then c.upd t r else t r

/-- Footprints are disjoint. -/
def Disjoint (a b : List Nat) : Prop := ∀ r, r ∈ a → r ∉ b

theorem Disjoint.symm {a b : List Nat} (h : Disjoint a b) : Disjoint b a :=
  fun r hb ha => h r ha hb

/-- COMMUTATION: changes with disjoint footprints land in either order to the same
    tree. -/
theorem commute (c d : Change) (h : Disjoint c.fp d.fp) (t : Tree) :
    d.apply (c.apply t) = c.apply (d.apply t) := by
  funext r
  unfold Change.apply
  by_cases hc : r ∈ c.fp
  · have hd : r ∉ d.fp := h r hc
    simp only [hc, hd, ite_true, ite_false]
    apply c.reads_fp _ _ _ r hc
    intro x hx
    have : x ∉ d.fp := h x hx
    simp [this]
  · by_cases hd : r ∈ d.fp
    · simp only [hc, hd, ite_true, ite_false]
      apply d.reads_fp _ _ _ r hd
      intro x hx
      have : x ∉ c.fp := h.symm x hx
      simp [this]
    · simp [hc, hd]

/-- A test with footprint `F`: it reads only the values in `F`. The trust
    hypothesis `reads`. -/
structure Test where
  fp : List Nat
  run : Tree → Bool
  reads : ∀ t t' : Tree, (∀ r ∈ fp, t r = t' r) → run t = run t'

/-- A change that misses a test's footprint cannot change the test's verdict. -/
theorem miss_keeps_verdict (c : Change) (T : Test) (h : Disjoint c.fp T.fp) (t : Tree) :
    T.run (c.apply t) = T.run t := by
  apply T.reads
  intro r hr
  have : r ∉ c.fp := h.symm r hr
  simp [Change.apply, this]

/-- Land a sequence of changes, in order. -/
def landAll : List Change → Tree → Tree
  | [], t => t
  | l :: ls, t => landAll ls (l.apply t)

/-- NON-OVERLAPPING LANDINGS NEVER INVALIDATE. `c` is validated by `T` on base
    `X`; its footprint lies inside the test's. Any sequence of landings whose
    footprints miss the test's footprint leaves the verdict on `c` applied to
    the NEW main exactly what it was on `X`. -/
theorem verdict_stable_seq (c : Change) (T : Test) (hc : ∀ r ∈ c.fp, r ∈ T.fp) :
    ∀ (L : List Change), (∀ l ∈ L, Disjoint l.fp T.fp) → ∀ X : Tree,
      T.run (c.apply (landAll L X)) = T.run (c.apply X) := by
  intro L
  induction L with
  | nil => intro _ X; rfl
  | cons l ls ih =>
    intro h X
    have hl : Disjoint l.fp T.fp := h l (List.mem_cons_self ..)
    have hlc : Disjoint l.fp c.fp := fun r hr hrc => hl r hr (hc r hrc)
    simp only [landAll]
    rw [ih (fun x hx => h x (List.mem_cons_of_mem _ hx)) (l.apply X)]
    rw [commute l c hlc X]
    exact miss_keeps_verdict l T hl (c.apply X)

/-! ### What the compare-and-swap checks. -/

/-- Region CAS: no landing since the base overlaps the change's footprint. -/
def RegionCas (c : Change) (L : List Change) : Prop := ∀ l ∈ L, Disjoint c.fp l.fp

/-- Whole-main CAS: nothing landed at all (main is still `X`). -/
def MainCas (L : List Change) : Prop := L = []

theorem main_cas_implies_region_cas (c : Change) (L : List Change) (h : MainCas L) :
    RegionCas c L := by
  subst h; intro l hl; simp at hl

/-- The converse fails: a disjoint landing breaks whole-main CAS but not region CAS.
    That gap is the whole benefit of footprints. -/
theorem region_cas_strictly_weaker (c l : Change) (h : Disjoint c.fp l.fp) :
    RegionCas c [l] ∧ ¬ MainCas [l] := by
  refine ⟨?_, by simp [MainCas]⟩
  intro x hx; simp at hx; subst hx; exact h

/-- The tree the landing produced is the same whether `c` lands before or after a
    region-CAS-passing sequence (so passing the CAS loses nothing). -/
theorem region_cas_commutes (c : Change) (L : List Change) (h : RegionCas c L) (X : Tree) :
    c.apply (landAll L X) = landAll L (c.apply X) := by
  induction L generalizing X with
  | nil => rfl
  | cons l ls ih =>
    have hl : Disjoint c.fp l.fp := h l (List.mem_cons_self ..)
    simp only [landAll]
    rw [ih (fun x hx => h x (List.mem_cons_of_mem _ hx)) (l.apply X)]
    rw [commute c l hl X]

/-! ### An overlapping landing can flip the verdict. -/

def inc0 : Change where
  fp := [0]
  upd := fun t r => t r + 1
  reads_fp := by
    intro t t' h r hr
    have hr0 : r = 0 := by simpa using hr
    subst hr0
    simp [h 0 (by simp)]

def isOne : Test where
  fp := [0]
  run := fun t => decide (t 0 = 1)
  reads := by
    intro t t' h
    have := h 0 (by simp)
    simp [this]

/-- From an all-zero base, `inc0` passes `isOne`; after another `inc0` lands first
    (overlapping), it fails. Overlap CAN invalidate, which is why the
    footprint hypothesis matters. -/
theorem overlap_can_invalidate :
    isOne.run (inc0.apply (fun _ => 0)) = true ∧
    isOne.run (inc0.apply (landAll [inc0] (fun _ => 0))) = false := by
  constructor <;> simp [isOne, inc0, Change.apply, landAll]

/-! ### Starvation. -/

/-- A run started at `s` and lasting `D` lands iff no overlapping landing falls in
    `[s, s + D]`: that is `Completes` over the stream of overlapping landings.
    If those arrive at least once per run duration, no run started after the
    first lands, however many agents retry. -/
theorem agent_starved (mv : Moves) (D : Nat) (h : mv.gap ≤ D) :
    ∀ s, mv.m 0 ≤ s → ¬ Completes mv D s :=
  starved_never_completes mv D h

end MergeQueueSpeedLimit
