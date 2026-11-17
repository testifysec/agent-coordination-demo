/-
  MergeQueueSpeedLimit.Dominance: the merge queue is a coordination policy, and a
  coordination policy that knows footprints is never worse than the queue on
  invalidation.

  THE SETTING. A pipeline is a list of entries, head first. Each entry has a
  footprint (the regions its change touches) and `work`, the minutes of
  validation done so far on its current base. An entry is DONE when
  `T ≤ work`. Time advances one tick at a time (`advance`); an entry fails at
  some tick (`fail i`), is vacated, and the policy decides which entries
  behind it must restart. Merging is in order (Cascade.lean); `landed` counts
  the done prefix.

  TWO POLICIES, ONE FOR EACH SIDE.
    * `queueInv`: entry `i` fails, every entry behind it restarts. This is
      what GitHub's queue does (Cascade.cascade), ALLGREEN or HEADGREEN: both
      eject an entry on a real failure, and a speculative build behind it
      was built on the failed entry.
    * `coordInv`: entry `j` restarts only if some entry `k` with `i < k ≤ j`
      shares a region with the failed entry `i`. Conservative on purpose: the
      `any k` clause covers a chain `i - k - j` where `k` writes what `j`
      reads.

  Both run on the same C slots (the pipeline has the same length) and the same
  stacking depth: `QCfg` carries them, and `queue_is_a_coordination_policy`
  shows the queue is `coordPolicy` with every footprint collapsed to a single
  region.

  HYPOTHESES (explicit; the theorems are conditional on all of them).
    H1 Same stream, same fates. Both systems receive the identical sequence of
       ticks and failures (`Ev`). That a change fails is a property of the
       change, not of the system running it. A change that fails is ejected at
       the same event in both.
    H2 Same capacity. Same number of slots and same stacking depth: the two
       pipelines are the same length (`Dom`).
    H3 Footprints are declared correctly, and a test reads only its footprint
       and a change writes only from its own footprint (Staleness.lean
       `Change.reads_fp`, `Test.reads`). H3 is NOT used by the dominance
       theorem `coordination_dominates_queue`, which is about progress and
       holds whatever the footprints say; it is used by
       `restart_unnecessary`, which is why not restarting is SAFE. If H3
       fails the coordination system can land a change whose verdict was
       stale, which is a correctness loss the queue does not have.
    H4 Failures name entries that have not landed. The dominance invariant
       holds regardless, but in a real run a landed change has no failure
       event.
    H5 Only the restart cost is compared. Consensus latency `L`, the claim
       race, hubs and the combined check on main (Coordination.lean,
       Staleness.lean) are NOT modelled here. They are exactly the costs that
       can make agents slower than the queue, and the post says so for latency.
       This theorem says nothing about them.
-/
import MergeQueueSpeedLimit.Cascade
import MergeQueueSpeedLimit.Staleness

namespace MergeQueueSpeedLimit

/-- Slots in flight and stacking depth. The queue ties them together
    (`maxEntriesToBuild` is both), so `queueCfg C = ⟨C, C⟩`. -/
structure QCfg where
  slots : Nat
  depth : Nat
deriving Repr, DecidableEq

def queueCfg (C : Nat) : QCfg := ⟨C, C⟩

/-- A policy: given the footprints of the pipeline and the failed entry `i`,
    does entry `j` have to restart? -/
abbrev Inv := List (List Nat) → Nat → Nat → Bool

structure FpPolicy where
  cfg : QCfg
  inv : Inv

def disjointB (a b : List Nat) : Bool := a.all (fun r => !b.contains r)

theorem disjointB_iff (a b : List Nat) : disjointB a b = true ↔ Disjoint a b := by
  unfold disjointB Disjoint
  simp [List.all_eq_true]

/-- The queue: everything behind the failure restarts. -/
def queueInv : Inv := fun _ i j => decide (i < j)

/-- Coordination: entry `j` restarts only if an entry `k` in `(i, j]` shares a
    region with the failed entry. -/
def coordInv : Inv := fun fps i j =>
  decide (i < j) &&
    (List.range (j + 1)).any (fun k => decide (i < k) && !disjointB (fps.getD i []) (fps.getD k []))

def queuePolicy (C : Nat) : FpPolicy := ⟨queueCfg C, queueInv⟩
def coordPolicy (cfg : QCfg) : FpPolicy := ⟨cfg, coordInv⟩

/-- Coordination restarts a subset of what the queue restarts. -/
theorem coordInv_le_queueInv (fps : List (List Nat)) (i j : Nat) :
    coordInv fps i j = true → queueInv fps i j = true := by
  unfold coordInv queueInv
  intro h
  simp only [Bool.and_eq_true] at h
  exact h.1

/-- With every footprint the same single region, coordination restarts exactly
    what the queue does: every entry behind the failure overlaps it. -/
theorem coordInv_single_region (L i j : Nat) (hij : i < j) (hj : j < L) :
    coordInv (List.replicate L [0]) i j = queueInv (List.replicate L [0]) i j := by
  unfold coordInv queueInv
  simp only [hij, decide_true, Bool.true_and]
  rw [List.any_eq_true]
  refine ⟨j, List.mem_range.2 (by omega), ?_⟩
  have hiL : i < L := by omega
  have h1 : (List.replicate L [0]).getD i [] = [0] := by
    simp [List.getD_eq_getElem?_getD, hiL]
  have h2 : (List.replicate L [0]).getD j [] = [0] := by
    simp [List.getD_eq_getElem?_getD, hj]
  rw [h1, h2]
  simp [disjointB, hij]

theorem coordInv_single_region_false (L i j : Nat) (hij : ¬ i < j) :
    coordInv (List.replicate L [0]) i j = queueInv (List.replicate L [0]) i j := by
  simp [coordInv, queueInv, hij]

/-- THE QUEUE IS A COORDINATION POLICY. The queue (HEADGREEN or ALLGREEN, depth
    `C`) is the coordination policy with `C` slots, stacking depth `C`, and
    every change in one region: on a pipeline of `L` entries all in region 0 it
    restarts exactly the entries the queue restarts. -/
theorem queue_is_a_coordination_policy (C L : Nat) :
    (coordPolicy (queueCfg C)).cfg = (queuePolicy C).cfg ∧
    ∀ i j, j < L →
      (coordPolicy (queueCfg C)).inv (List.replicate L [0]) i j =
        (queuePolicy C).inv (List.replicate L [0]) i j := by
  refine ⟨rfl, fun i j hj => ?_⟩
  show coordInv (List.replicate L [0]) i j = queueInv (List.replicate L [0]) i j
  by_cases h : i < j
  · exact coordInv_single_region L i j h hj
  · exact coordInv_single_region_false L i j h

/-- If every entry in `(i, j]` is disjoint from the failed entry, coordination
    does not restart `j`, and the queue does. -/
theorem strictly_less_invalidation (fps : List (List Nat)) (i j : Nat) (hij : i < j)
    (hd : ∀ k, i < k → k ≤ j → Disjoint (fps.getD i []) (fps.getD k [])) :
    coordInv fps i j = false ∧ queueInv fps i j = true := by
  refine ⟨?_, by simp [queueInv, hij]⟩
  unfold coordInv
  simp only [Bool.and_eq_false_iff]
  right
  rw [Bool.eq_false_iff]
  intro hany
  rw [List.any_eq_true] at hany
  obtain ⟨k, hk, hb⟩ := hany
  have hk' := List.mem_range.1 hk
  simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hb
  have := (disjointB_iff _ _).2 (hd k hb.1 (by omega))
  rw [this] at hb
  exact Bool.noConfusion hb.2

/-! ### The dynamics. -/

/-- A pipeline entry: footprint, and work done on its current base. -/
structure Ent where
  work : Nat
  fp : List Nat
deriving Repr, DecidableEq

/-- Pointwise relation between two pipelines (core has no `Forall₂`). -/
inductive FA (R : Ent → Ent → Prop) : List Ent → List Ent → Prop
  | nil : FA R [] []
  | cons {a b : Ent} {l l' : List Ent} : R a b → FA R l l' → FA R (a :: l) (b :: l')

def Ent.fresh (e : Ent) : Ent := { e with work := 0 }

/-- Restart every entry the policy flags, indices counted from `n`. -/
def restartAux (inv : Nat → Bool) : Nat → List Ent → List Ent
  | _, [] => []
  | n, e :: rest => (if inv n then e.fresh else e) :: restartAux inv (n + 1) rest

/-- Entry `i` fails: the policy restarts what it must, and `i` leaves. -/
def failStep (inv : Inv) (q : List Ent) (i : Nat) : List Ent :=
  (restartAux (inv (q.map Ent.fp) i) 0 q).eraseIdx i

/-- One tick of validation, capped at `T` (a done entry stays done). -/
def advance (T : Nat) (q : List Ent) : List Ent :=
  q.map (fun e => { e with work := min (e.work + 1) T })

inductive Ev where
  | tick : Ev
  | fail : Nat → Ev

def step (inv : Inv) (T : Nat) (q : List Ent) : Ev → List Ent
  | .tick => advance T q
  | .fail i => failStep inv q i

def play (inv : Inv) (T : Nat) : List Ev → List Ent → List Ent
  | [], q => q
  | e :: es, q => play inv T es (step inv T q e)

/-- Entries that have finished validating, in order from the head. -/
def landed (T : Nat) (q : List Ent) : Nat :=
  (q.takeWhile (fun e => decide (T ≤ e.work))).length

/-- `q` (the queue) is no further along than `q'` (coordination) in any entry,
    and both have the same footprints in the same slots. -/
def Dom (q q' : List Ent) : Prop :=
  FA (fun a b => a.fp = b.fp ∧ a.work ≤ b.work) q q'

theorem Dom.fps {q q' : List Ent} (h : Dom q q') : q.map Ent.fp = q'.map Ent.fp := by
  induction h with
  | nil => rfl
  | cons hab _ ih => simp [hab.1, ih]

theorem forall2_eraseIdx {R : Ent → Ent → Prop} {l l' : List Ent} (h : FA R l l') :
    ∀ i, FA R (l.eraseIdx i) (l'.eraseIdx i) := by
  induction h with
  | nil => intro i; exact FA.nil
  | cons hab _ ih =>
    intro i
    cases i with
    | zero => simpa using ‹FA R _ _›
    | succ i => simp only [List.eraseIdx_cons_succ]; exact FA.cons hab (ih i)

theorem restartAux_dom (inv inv' : Nat → Bool) (hinv : ∀ n, inv' n = true → inv n = true) :
    ∀ (n : Nat) {q q' : List Ent}, Dom q q' → Dom (restartAux inv n q) (restartAux inv' n q') := by
  intro n q q' h
  induction h generalizing n with
  | nil => exact FA.nil
  | cons hab _ ih =>
    rename_i a b _ _
    simp only [restartAux]
    refine FA.cons ?_ (ih (n + 1))
    cases hi : inv n
    · have : inv' n = false := by
        cases h' : inv' n
        · rfl
        · have := hinv n h'; rw [hi] at this; exact Bool.noConfusion this
      simp [this, hab.1, hab.2]
    · cases hi' : inv' n
      · simp [Ent.fresh, hab.1]
      · simp [Ent.fresh, hab.1]

/-- One failure preserves dominance: with the same failure, the coordination
    pipeline is still at least as far along. -/
theorem dom_fail {q q' : List Ent} (h : Dom q q') (i : Nat) :
    Dom (failStep queueInv q i) (failStep coordInv q' i) := by
  unfold failStep
  rw [← h.fps]
  exact forall2_eraseIdx
    (restartAux_dom _ _ (fun n => coordInv_le_queueInv _ i n) 0 h) i

theorem dom_advance (T : Nat) {q q' : List Ent} (h : Dom q q') :
    Dom (advance T q) (advance T q') := by
  unfold advance
  induction h with
  | nil => exact FA.nil
  | cons hab _ ih =>
    simp only [List.map_cons]
    exact FA.cons ⟨hab.1, by simp only; have := hab.2; omega⟩ ih

theorem dom_play (T : Nat) :
    ∀ (evs : List Ev) {q q' : List Ent}, Dom q q' →
      Dom (play queueInv T evs q) (play coordInv T evs q') := by
  intro evs
  induction evs with
  | nil => intro q q' h; exact h
  | cons e es ih =>
    intro q q' h
    simp only [play]
    refine ih ?_
    cases e with
    | tick => exact dom_advance T h
    | fail i => exact dom_fail h i

theorem landed_mono (T : Nat) {q q' : List Ent} (h : Dom q q') : landed T q ≤ landed T q' := by
  unfold landed
  induction h with
  | nil => simp
  | @cons a b l l' hab _ ih =>
    by_cases ha : T ≤ a.work
    · have hb : T ≤ b.work := Nat.le_trans ha hab.2
      simp [List.takeWhile_cons, ha, hb]
      exact ih
    · simp [List.takeWhile_cons, ha]

/-- COORDINATION DOMINATES THE QUEUE. Take any pipeline, the same for both, and
    any sequence of ticks and failures (hypotheses H1 and H2 in the header).
    Run the queue policy on one copy and the coordination policy on the other.
    Then at the end of every prefix of events:
      * every entry of the coordination pipeline has done at least as much
        validation on its current base as the same entry in the queue's
        (`Dom`), and
      * the coordination system has landed at least as many changes, in the
        same order, so at least the same set (`landed`).
    Where the footprints are disjoint it does strictly less restarting
    (`strictly_less_invalidation`). -/
theorem coordination_dominates_queue (T : Nat) (q : List Ent) (evs : List Ev) :
    Dom (play queueInv T evs q) (play coordInv T evs q) ∧
    landed T (play queueInv T evs q) ≤ landed T (play coordInv T evs q) := by
  have h0 : Dom q q := by
    unfold Dom
    induction q with
    | nil => exact FA.nil
    | cons e rest ih => exact FA.cons ⟨rfl, Nat.le_refl _⟩ ih
  have := dom_play T evs h0
  exact ⟨this, landed_mono T this⟩

/-! ### The coordination system can always emulate the queue. -/

theorem restartAux_ext (inv inv' : Nat → Bool) :
    ∀ (n : Nat) (q : List Ent), (∀ m, n ≤ m → m < n + q.length → inv m = inv' m) →
      restartAux inv n q = restartAux inv' n q := by
  intro n q
  induction q generalizing n with
  | nil => intro _; rfl
  | cons e rest ih =>
    intro h
    simp only [restartAux]
    rw [h n (Nat.le_refl _) (by simp), ih (n + 1) (fun m h1 h2 => h m (by omega) (by simp at h2 ⊢; omega))]

def AllOne (q : List Ent) : Prop := ∀ e ∈ q, e.fp = [0]

theorem allOne_map {q : List Ent} (h : AllOne q) : q.map Ent.fp = List.replicate q.length [0] := by
  induction q with
  | nil => rfl
  | cons e rest ih =>
    simp only [List.map_cons, List.length_cons, List.replicate_succ]
    rw [h e (List.mem_cons_self ..), ih (fun x hx => h x (List.mem_cons_of_mem _ hx))]

theorem allOne_fail {q : List Ent} (h : AllOne q) (i : Nat) :
    failStep coordInv q i = failStep queueInv q i := by
  unfold failStep
  rw [allOne_map h]
  congr 1
  apply restartAux_ext
  intro m _ hm
  simp only [List.length_replicate, Nat.zero_add] at hm
  have := (queue_is_a_coordination_policy 0 q.length).2 i m (by omega)
  simpa [coordPolicy, queuePolicy] using this

theorem allOne_step (T : Nat) {q : List Ent} (h : AllOne q) (e : Ev) : AllOne (step coordInv T q e) := by
  cases e with
  | tick =>
    intro x hx
    simp only [step, advance, List.mem_map] at hx
    obtain ⟨y, hy, rfl⟩ := hx
    exact h y hy
  | fail i =>
    intro x hx
    simp only [step, failStep] at hx
    have hx' := List.mem_of_mem_eraseIdx hx
    have : ∀ n (r : List Ent), (∀ z ∈ r, z.fp = [0]) → ∀ z ∈ restartAux (coordInv (q.map Ent.fp) i) n r, z.fp = [0] := by
      intro n r
      induction r generalizing n with
      | nil => intro _ z hz; simp [restartAux] at hz
      | cons a rest ih =>
        intro hr z hz
        simp only [restartAux, List.mem_cons] at hz
        rcases hz with rfl | hz
        · have := hr a (List.mem_cons_self ..)
          split <;> simp [Ent.fresh, this]
        · exact ih (n + 1) (fun w hw => hr w (List.mem_cons_of_mem _ hw)) z hz
    exact this 0 q h x hx'

/-- EMULATION. On a pipeline whose entries all share one region, the coordination
    policy produces exactly the queue's schedule, event for event. So the set of
    schedules the coordination system can produce contains the queue's: it can
    always choose to treat every change as overlapping every other. -/
theorem coord_emulates_queue (T : Nat) :
    ∀ (evs : List Ev) (q : List Ent), AllOne q →
      play coordInv T evs q = play queueInv T evs q := by
  intro evs
  induction evs with
  | nil => intro q _; rfl
  | cons e es ih =>
    intro q h
    simp only [play]
    have hs : step coordInv T q e = step queueInv T q e := by
      cases e with
      | tick => rfl
      | fail i => exact allOne_fail h i
    rw [← hs]
    exact ih _ (allOne_step T h e)

/-! ### Why not restarting is safe, and a witness that it happens. -/

/-- If the failed change `ci` is disjoint from every change that lands after it
    in the stack (`cs`) and from the footprint of the test on the last entry,
    then removing `ci` does not change that test's verdict. Hypothesis H3:
    changes are local (`reads_fp`) and the test reads only its footprint. -/
theorem restart_unnecessary (ci : Change) (cs : List Change) (T : Test) (X : Tree)
    (hcs : ∀ l ∈ cs, Disjoint ci.fp l.fp) (hT : Disjoint ci.fp T.fp) :
    T.run (landAll cs (ci.apply X)) = T.run (landAll cs X) := by
  rw [← region_cas_commutes ci cs hcs X]
  exact miss_keeps_verdict ci T hT (landAll cs X)

/-- Footprints `[0], [0], [1]`, 5 minutes of work each. Entry 1 fails. The queue
    restarts entry 2 (works `[5, 0]` after entry 1 leaves); coordination keeps
    its 5 minutes (`[5, 5]`), because entry 2 shares no region with entry 1. -/
theorem witness_less_invalidation :
    let q : List Ent := [⟨5, [0]⟩, ⟨5, [0]⟩, ⟨5, [1]⟩]
    (failStep queueInv q 1).map Ent.work = [5, 0] ∧
    (failStep coordInv q 1).map Ent.work = [5, 5] := by
  decide

end MergeQueueSpeedLimit
