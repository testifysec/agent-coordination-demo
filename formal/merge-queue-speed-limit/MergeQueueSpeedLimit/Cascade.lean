/-
  MergeQueueSpeedLimit.Cascade: claim 2 (the speculation cascade and in-order
  merging), claim 6 (stacks) and the HEADGREEN admission rule.

  A pipeline is a list of builds, head first. Build k is built on top of
  entries 1..k-1 ahead of it, so its result is only meaningful for that
  prefix. Merges happen strictly in order from the head.

  What is modelled and what is not:
    * Modelled: which builds are discarded when an entry fails, who may
      merge, and a timing identity for in-order merging.
    * Not modelled: the lane limit (only C builds run at once; entries past
      C wait for a lane), arrivals, and random failure. The stochastic part
      (how often an entry fails) is a hypothesis of the post, not a
      theorem here.
-/
import MergeQueueSpeedLimit.Serial

namespace MergeQueueSpeedLimit

/-- A build in the pipeline: how many minutes of work it has done, and whether
    it has finished. -/
structure Build where
  work : Nat
  done : Bool
deriving Repr, DecidableEq

/-- A build that has just (re)started on a new prefix. -/
def Build.fresh : Build := ⟨0, false⟩

def workOf (q : List Build) : Nat := (q.map Build.work).sum

/-- Entry `failed` fails. The builds `ahead` of it keep their state, the
    failed entry leaves, and every build `behind` it is cancelled and restarts
    on the new prefix. -/
def cascade (ahead behind : List Build) : List Build :=
  ahead ++ behind.map (fun _ => Build.fresh)

theorem cascade_length (ahead behind : List Build) :
    (cascade ahead behind).length = ahead.length + behind.length := by
  simp [cascade]

/-- Builds ahead of the failure are untouched. -/
theorem cascade_ahead_kept (ahead behind : List Build) :
    (cascade ahead behind).take ahead.length = ahead := by
  simp [cascade]

/-- Every build behind the failure starts over: no work, not done. -/
theorem cascade_behind_fresh (ahead behind : List Build) :
    ∀ b ∈ (cascade ahead behind).drop ahead.length, b = Build.fresh := by
  intro b hb
  simp [cascade] at hb
  obtain ⟨x, _, rfl⟩ := hb
  rfl

theorem workOf_fresh (behind : List Build) : workOf (behind.map (fun _ => Build.fresh)) = 0 := by
  induction behind with
  | nil => simp [workOf]
  | cons x rest ih => simp [workOf, Build.fresh] at ih ⊢; exact ih

/-- THE WASTE LEMMA, accounting form. Work in the pipeline before the
    failure is the work after it, plus the failed entry's work, plus ALL the
    work of the builds behind it. -/
theorem cascade_waste (ahead : List Build) (failed : Build) (behind : List Build) :
    workOf (ahead ++ failed :: behind) =
      workOf (cascade ahead behind) + (failed.work + workOf behind) := by
  have h0 : workOf (cascade ahead behind) = workOf ahead := by
    have := workOf_fresh behind
    simp only [cascade, workOf] at this ⊢
    rw [List.map_append, List.sum_append, this]; simp
  rw [h0]
  simp only [workOf, List.map_append, List.sum_append, List.map_cons, List.sum_cons] <;> omega

/-- How many builds, counted from the head, are done in an unbroken run:
    the number that can merge now, in order. -/
def mergePrefix (q : List Build) : Nat := (q.takeWhile Build.done).length

/-- In-order merging: an unfinished build blocks everything behind it. At most
    `pre.length` builds merge, so a finished build in `post` cannot. -/
theorem merge_blocked (pre : List Build) (b : Build) (post : List Build) (hb : b.done = false) :
    mergePrefix (pre ++ b :: post) ≤ pre.length := by
  unfold mergePrefix
  induction pre with
  | nil => simp [hb]
  | cons x rest ih =>
    cases hx : x.done <;> simp [hx] <;> omega

/-- A finished build behind an unfinished one cannot merge: if build `j` is
    done and some earlier build is not, the number that merge is at most the
    position of that earlier build, so `j` is not among them. -/
theorem finished_behind_unfinished_waits (pre mid : List Build) (b c : Build) (post : List Build)
    (hb : b.done = false) :
    mergePrefix (pre ++ b :: (mid ++ c :: post)) ≤ pre.length := by
  have := merge_blocked pre b (mid ++ c :: post) hb
  exact this

/-- After a failure nothing behind it can merge yet: the merge count is at most
    the number of builds ahead. -/
theorem cascade_no_merge_behind (ahead behind : List Build) :
    mergePrefix (cascade ahead behind) ≤ ahead.length := by
  cases behind with
  | nil =>
    simp only [cascade, List.map_nil, List.append_nil, mergePrefix]
    exact (List.takeWhile_prefix _).length_le
  | cons b rest =>
    have := merge_blocked ahead Build.fresh (rest.map (fun _ => Build.fresh)) rfl
    simpa [cascade, mergePrefix] using this

/-- The work a merge consumes: the work of the builds that merge now. -/
def usedWork (q : List Build) : Nat := workOf (q.take (mergePrefix q))

/-- After a failure, the only work any merge can use is work done ahead of
    the failure. Everything behind restarted from zero, and a restarted build
    that later merges has only post-restart work. -/
theorem cascade_used_le (ahead behind : List Build) :
    usedWork (cascade ahead behind) ≤ workOf ahead := by
  unfold usedWork
  have h := cascade_no_merge_behind ahead behind
  generalize mergePrefix (cascade ahead behind) = m at *
  have e : (cascade ahead behind).take m = ahead.take m := by
    simp only [cascade]; exact List.take_append_of_le_length h
  rw [e]
  have := List.take_append_drop m ahead
  have hw : workOf ahead = workOf (ahead.take m) + workOf (ahead.drop m) := by
    unfold workOf
    rw [← List.sum_append, ← List.map_append, List.take_append_drop]
  omega

/-! ### The head-of-line wait.

  All builds start together; build `k` finishes at `fin k`. It merges when it
  and every build ahead of it are done: at the running maximum `pmax fin k`.
  The "waiting in line" loss is `pmax fin k - fin k`.
-/

/-- Merge time of entry `k`: the latest finish among entries `0..k`. -/
def pmax (fin : Nat → Nat) : Nat → Nat
  | 0 => fin 0
  | k + 1 => max (pmax fin k) (fin (k + 1))

theorem le_pmax (fin : Nat → Nat) : ∀ k, fin k ≤ pmax fin k := by
  intro k
  cases k with
  | zero => simp [pmax]
  | succ k => simp only [pmax]; exact Nat.le_max_right _ _

theorem le_pmax_of_le (fin : Nat → Nat) : ∀ k j, j ≤ k → fin j ≤ pmax fin k := by
  intro k
  induction k with
  | zero =>
    intro j hj
    have : j = 0 := by omega
    subst this; simp [pmax]
  | succ k ih =>
    intro j hj
    rcases Nat.lt_or_ge j (k + 1) with h | h
    · have := ih j (by omega)
      simp only [pmax]; exact Nat.le_trans this (Nat.le_max_left _ _)
    · have : j = k + 1 := by omega
      subst this; simp only [pmax]; exact Nat.le_max_right _ _

/-- In-order merging: entry `k` cannot merge before every entry ahead of it has
    finished. -/
theorem merge_after_all_ahead (fin : Nat → Nat) (k j : Nat) (h : j ≤ k) :
    fin j ≤ pmax fin k := le_pmax_of_le fin k j h

/-- Merge times are in order. -/
theorem pmax_mono (fin : Nat → Nat) (k : Nat) : pmax fin k ≤ pmax fin (k + 1) := by
  simp only [pmax]; exact Nat.le_max_left _ _

/-- The running maximum is attained by some entry at or before `k`. -/
theorem pmax_attained (fin : Nat → Nat) : ∀ k, ∃ j, j ≤ k ∧ pmax fin k = fin j := by
  intro k
  induction k with
  | zero => exact ⟨0, Nat.le_refl _, by simp [pmax]⟩
  | succ k ih =>
    rcases Nat.le_total (pmax fin k) (fin (k + 1)) with h | h
    · exact ⟨k + 1, Nat.le_refl _, by simp only [pmax]; exact Nat.max_eq_right h⟩
    · obtain ⟨j, hj, hj2⟩ := ih
      exact ⟨j, by omega, by simp only [pmax]; rw [Nat.max_eq_left h]; exact hj2⟩

/-- The loss exists exactly when some entry ahead finishes later. -/
theorem hol_loss_iff (fin : Nat → Nat) (k : Nat) :
    fin k < pmax fin k ↔ ∃ j, j ≤ k ∧ fin k < fin j := by
  constructor
  · intro h
    obtain ⟨j, hj, hj2⟩ := pmax_attained fin k
    exact ⟨j, hj, by omega⟩
  · rintro ⟨j, hj, hlt⟩
    have := le_pmax_of_le fin k j hj
    omega

/-- No head-of-line loss for any entry iff finishing times never decrease down
    the queue. Different durations alone do NOT cause the loss: a queue whose
    builds finish in the order they merge loses nothing. -/
theorem no_hol_loss_iff_monotone (fin : Nat → Nat) :
    (∀ k, pmax fin k = fin k) ↔ (∀ j k, j ≤ k → fin j ≤ fin k) := by
  constructor
  · intro h j k hjk
    have := le_pmax_of_le fin k j hjk
    rw [h k] at this; exact this
  · intro h k
    induction k with
    | zero => simp [pmax]
    | succ k ih =>
      simp only [pmax, ih]
      exact Nat.max_eq_right (h k (k + 1) (by omega))

/-! ### Claim 6: stacks. -/

/-- A central build of a stack of layers: it merges every layer when all pass
    and none when any fails (the group is ejected). -/
def stackMerged (layers : List Bool) : Nat := if layers.all id then layers.length else 0

/-- Layers ejected by that build. -/
def stackEjected (layers : List Bool) : Nat := if layers.all id then 0 else layers.length

/-- The ejection rule: a stack is all-or-nothing. -/
theorem stack_all_or_nothing (layers : List Bool) :
    stackMerged layers = 0 ∨ stackMerged layers = layers.length := by
  unfold stackMerged; split <;> simp

/-- Per-build bound: a build of `k` layers merges at most `k`. -/
theorem stackMerged_le (layers : List Bool) : stackMerged layers ≤ layers.length := by
  unfold stackMerged; split <;> omega

/-- If any layer fails, all layers are ejected and none merge. -/
theorem stack_fail_ejects_all (layers : List Bool) (h : layers.all id = false) :
    stackMerged layers = 0 ∧ stackEjected layers = layers.length := by
  simp [stackMerged, stackEjected, h]

/-- Every layer is either merged or ejected. -/
theorem stack_conserves (layers : List Bool) :
    stackMerged layers + stackEjected layers = layers.length := by
  unfold stackMerged stackEjected; split <;> omega

/-- Over any set of builds each carrying at most `k` layers, merges are at most
    `k` per build. With the serial ceiling, `k` is the batch factor `B`:
    a stack of `k` layers lifts the ceiling by at most `k`, and by exactly `k`
    only if every build passes. -/
theorem stacks_merged_le (k : Nat) : ∀ bs : List (List Bool), (∀ b ∈ bs, b.length ≤ k) →
    (bs.map stackMerged).sum ≤ k * bs.length := by
  intro bs
  induction bs with
  | nil => simp
  | cons b rest ih =>
    intro h
    have h1 := Nat.le_trans (stackMerged_le b) (h b (List.mem_cons_self ..))
    have h2 := ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
    simp only [List.map_cons, List.sum_cons, List.length_cons]
    rw [Nat.mul_succ]
    omega

/-- Stacks under the serial ceiling: if each job's landed count is what its stack
    merges, and no stack has more than `k` layers, the landed total in a
    window is at most `k * C * ⌊W / T⌋`. -/
theorem stack_ceiling {k C T : Nat} (hT : 0 < T) {js : List Occ} (hv : Valid C T 0 js)
    (a W : Nat) (hw : ∀ j ∈ js, InWin a W j) (layers : Occ → List Bool)
    (hl : ∀ j ∈ js, j.w = stackMerged (layers j)) (hk : ∀ j ∈ js, (layers j).length ≤ k) :
    (js.map Occ.w).sum ≤ k * C * (W / T) :=
  batched_ceiling hT hv a W hw (fun j hj => by
    rw [hl j hj]; exact Nat.le_trans (stackMerged_le _) (hk j hj))

/-- Agent stacks. `v i` says layer `i` (0 is the bottom) has a passing verdict.
    When layer `l` fails, every layer above it was validated against a base
    that included `l`, so its verdict is void: it must re-run. -/
def afterFailure (v : Nat → Bool) (l : Nat) : Nat → Bool := fun i => if i < l then v i else false

theorem afterFailure_below (v : Nat → Bool) (l i : Nat) (h : i < l) : afterFailure v l i = v i := by
  simp [afterFailure, h]

theorem afterFailure_above (v : Nat → Bool) (l i : Nat) (h : l ≤ i) : afterFailure v l i = false := by
  simp [afterFailure]; omega

/-- How many layers must re-run: those above the failure, `n - l - 1` of an
    `n`-layer stack. -/
def rerun (n l : Nat) : Nat := n - (l + 1)

theorem rerun_eq (n l : Nat) (h : l < n) : rerun n l + (l + 1) = n := by
  unfold rerun; omega

/-- Length of the unbroken passing run from the bottom (the layers that can
    land, in order). -/
def landedPrefix (v : Nat → Bool) : Nat → Nat
  | 0 => 0
  | n + 1 => if landedPrefix v n = n ∧ v n = true then n + 1 else landedPrefix v n

theorem landedPrefix_le (v : Nat → Bool) : ∀ n, landedPrefix v n ≤ n := by
  intro n
  induction n with
  | zero => simp [landedPrefix]
  | succ n ih => simp only [landedPrefix]; split <;> omega

/-- A failed layer caps the landing run: at most the `l` layers below it land. -/
theorem failure_caps_landing (v : Nat → Bool) (l : Nat) (hl : v l = false) :
    ∀ n, l < n → landedPrefix v n ≤ l := by
  intro n
  induction n with
  | zero => intro h; omega
  | succ n ih =>
    intro h
    simp only [landedPrefix]
    rcases Nat.lt_or_ge l n with h1 | h1
    · have := ih h1
      have h3 := landedPrefix_le v n
      split <;> omega
    · have : l = n := by omega
      subst this
      split
      · rename_i hc; simp [hl] at hc
      · have := landedPrefix_le v l; omega

/-! ### HEADGREEN.

  Entry `i` is in a cumulative build `i` that contains entries `0..i`. A REAL
  failure of entry `j` (a bug in the change) breaks every build `k ≥ j`. An
  INFRASTRUCTURE failure of build `k` (a flaky runner, a missing image)
  breaks only build `k`.
-/

structure Run where
  real : Nat → Bool
  infra : Nat → Bool

/-- Build `k` passes: no real failure in entries `0..k`, and its own run did
    not flake. -/
def Run.passes (r : Run) (k : Nat) : Prop := (∀ j, j ≤ k → r.real j = false) ∧ r.infra k = false

/-- ALLGREEN: entry `i` merges only when its own build passes. -/
def Run.allGreen (r : Run) (i : Nat) : Prop := r.passes i

/-- HEADGREEN with `depth` builds in flight: entry `i` merges when some build
    at or behind it, within the depth, passes, because that build tested its
    combined tree. -/
def Run.headGreen (r : Run) (depth i : Nat) : Prop := ∃ k, i ≤ k ∧ k < depth ∧ r.passes k

/-- Whatever ALLGREEN merges, HEADGREEN merges. -/
theorem allGreen_headGreen (r : Run) (depth i : Nat) (hi : i < depth) (h : r.allGreen i) :
    r.headGreen depth i := ⟨i, Nat.le_refl _, hi, h⟩

/-- One passing build at depth `k` admits every entry ahead of it. -/
theorem passing_build_admits_prefix (r : Run) (depth k : Nat) (hk : k < depth) (h : r.passes k) :
    ∀ i, i ≤ k → r.headGreen depth i := fun i hi => ⟨k, hi, hk, h⟩

/-- Safety: HEADGREEN never admits an entry with a real failure at or ahead of
    it. -/
theorem headGreen_sound (r : Run) (depth i : Nat) (h : r.headGreen depth i) :
    ∀ j, j ≤ i → r.real j = false := by
  obtain ⟨k, hik, _, hp, _⟩ := h
  exact fun j hj => hp j (by omega)

/-- THE POINT OF HEADGREEN. An infrastructure failure on entry `i` ejects it under
    ALLGREEN (its own build fails) but not under HEADGREEN when a deeper
    build `k` passes. -/
theorem infra_failure_no_longer_ejects (r : Run) (depth i k : Nat) (hik : i < k) (hk : k < depth)
    (hinfra : r.infra i = true) (hpass : r.passes k) :
    ¬ r.allGreen i ∧ r.headGreen depth i := by
  refine ⟨?_, ⟨k, by omega, hk, hpass⟩⟩
  intro h
  have := h.2
  rw [hinfra] at this
  exact Bool.noConfusion this

/-- A real failure is still ejected under both rules. -/
theorem real_failure_still_ejected (r : Run) (depth i : Nat) (hr : r.real i = true) :
    ¬ r.allGreen i ∧ ¬ r.headGreen depth i := by
  refine ⟨fun h => ?_, fun h => ?_⟩
  · have := h.1 i (Nat.le_refl _); rw [hr] at this; exact Bool.noConfusion this
  · have := headGreen_sound r depth i h i (Nat.le_refl _); rw [hr] at this; exact Bool.noConfusion this

end MergeQueueSpeedLimit
