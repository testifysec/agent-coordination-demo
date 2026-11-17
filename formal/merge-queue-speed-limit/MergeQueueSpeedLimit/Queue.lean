/-
  MergeQueueSpeedLimit.Queue: moves of `main` against a merge group (starvation).

  Every move of `main` re-creates the merge group on the new base, so a
  group's run restarts at the move.

  Time is in minutes. A group run takes `D`. A run started at `s` merges only
  if main does not move in `[s, s + D]` (closed: a move at the completion
  instant still invalidates the fast-forward). A move restarts the group at
  the move.
-/
namespace MergeQueueSpeedLimit

/-- Moves of `main` (for example direct merges that bypass the queue) at `m 0 < m 1 < ...`, each gap at most `gap`. -/
structure Moves where
  m : Nat → Nat
  gap : Nat
  mono : ∀ k, m k < m (k + 1)
  bounded : ∀ k, m (k + 1) ≤ m k + gap

/-- A run started at `s` completes iff no move lands in `[s, s + D]`. -/
def Completes (mv : Moves) (D s : Nat) : Prop := ∀ k, ¬ (s ≤ mv.m k ∧ mv.m k ≤ s + D)

/-- Every window of width `gap` after the first move contains a move. -/
theorem move_in_every_window (mv : Moves) : ∀ s, mv.m 0 ≤ s → ∃ k, s ≤ mv.m k ∧ mv.m k ≤ s + mv.gap := by
  have key : ∀ d, ∃ k, mv.m 0 + d ≤ mv.m k ∧ mv.m k ≤ mv.m 0 + d + mv.gap := by
    intro d
    induction d with
    | zero => exact ⟨0, by omega, by omega⟩
    | succ d ih =>
      obtain ⟨k, h1, h2⟩ := ih
      by_cases he : mv.m 0 + d + 1 ≤ mv.m k
      · exact ⟨k, by omega, by omega⟩
      · have hk : mv.m k = mv.m 0 + d := by omega
        exact ⟨k + 1, by have := mv.mono k; omega, by have := mv.bounded k; omega⟩
  intro s hs
  obtain ⟨k, h1, h2⟩ := key (s - mv.m 0)
  exact ⟨k, by omega, by omega⟩

theorem Moves.mono_le (mv : Moves) (a : Nat) : ∀ d, mv.m a ≤ mv.m (a + d) := by
  intro d
  induction d with
  | zero => exact Nat.le_refl _
  | succ d ih => have := mv.mono (a + d); rw [← Nat.add_assoc]; omega

/-- Starvation: when admin merges come at least once per queue-run
    duration (gap ≤ D, i.e. rate × D ≥ 1), no group started after the first
    one ever completes. -/
theorem starved_never_completes (mv : Moves) (D : Nat) (h : mv.gap ≤ D) :
    ∀ s, mv.m 0 ≤ s → ¬ Completes mv D s := by
  intro s hs hc
  obtain ⟨k, h1, h2⟩ := move_in_every_window mv s hs
  exact hc k ⟨h1, by omega⟩

/-- The periodic case: one admin merge every `p` minutes. -/
def periodic (t0 p : Nat) (hp : 0 < p) : Moves where
  m k := t0 + k * p
  gap := p
  mono k := by rw [Nat.succ_mul]; omega
  bounded k := by rw [Nat.succ_mul]; omega

theorem periodic_starves (t0 p D : Nat) (hp : 0 < p) (h : p ≤ D) :
    ∀ s, t0 ≤ s → ¬ Completes (periodic t0 p hp) D s :=
  fun s hs => starved_never_completes (periodic t0 p hp) D h s (by simp [periodic]; exact hs)

/-- Liveness, the converse: a group rebuilt one minute after the move at
    `m k` completes when the next move is more than `D + 1` later. -/
theorem completes_in_long_gap (mv : Moves) (D k : Nat) (h : mv.m k + 1 + D < mv.m (k + 1)) :
    Completes mv D (mv.m k + 1) := by
  intro j ⟨h1, h2⟩
  by_cases hj : j ≤ k
  · have := mv.mono_le j (k - j); rw [Nat.add_sub_cancel' hj] at this; omega
  · have := mv.mono_le (k + 1) (j - (k + 1)); rw [Nat.add_sub_cancel' (by omega)] at this; omega

end MergeQueueSpeedLimit
