/-
  MergeQueueSpeedLimit.Cliff: claim 3, the timeout cliff.

  GitHub's merge queue setting `check_response_timeout_minutes` counts from
  GROUP CREATION, not from the last rebuild, so a group that waits, or is
  rebuilt, burns the same clock. A group whose
  check has not reported by then is ejected as failed.

  Proved (deterministic):
    * if every group's age at completion exceeds the timeout, no group merges;
    * in general merges are at most the number of groups that finish under it
      (so a fraction f passing bounds the merge fraction by f);
    * a slowdown by factor `f` of attempts at least `T` long is a cliff as soon
      as `f * T` exceeds the timeout;
    * the stale-main starvation of Queue.lean is a second, independent route
      to zero merges.

  NOT proved: the fraction. "A fraction f of groups finish under the timeout"
  is the stochastic hypothesis (`Group.age` drawn from a distribution); the
  model bounds merges by the count, whatever generates it.
-/
import MergeQueueSpeedLimit.Queue

namespace MergeQueueSpeedLimit

/-- A group: minutes from group creation to its check completing (`age`), and
    whether the checks themselves are green (`ok`). -/
structure Group where
  age : Nat
  ok : Bool
deriving Repr, DecidableEq

/-- A group merges only if its check reports within the timeout and is green. -/
def merges (timeout : Nat) (gs : List Group) : Nat :=
  (gs.filter (fun g => decide (g.age ≤ timeout) && g.ok)).length

/-- Groups that finish under the timeout, green or not. -/
def inTime (timeout : Nat) (gs : List Group) : Nat :=
  (gs.filter (fun g => decide (g.age ≤ timeout))).length

/-- THE CLIFF. If every group's age exceeds the timeout, nothing merges. -/
theorem cliff_zero (timeout : Nat) (gs : List Group) (h : ∀ g ∈ gs, timeout < g.age) :
    merges timeout gs = 0 := by
  unfold merges
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro g hg
  have := h g hg
  simp; omega

/-- In general: merges are at most the groups that finish under the timeout.
    With `n` groups of which `p` finish in time, merges are at most `p`, so
    the merge fraction is at most `p / n`. -/
theorem cliff_fraction (timeout : Nat) (gs : List Group) : merges timeout gs ≤ inTime timeout gs := by
  unfold merges inTime
  rw [← List.countP_eq_length_filter, ← List.countP_eq_length_filter]
  refine List.countP_mono_left ?_
  intro g _ hg
  simp at hg ⊢
  exact hg.1

/-- Slowdown: attempts of at least `T` minutes slowed by factor `f` take at least
    `f * T` from group creation. If that exceeds the timeout, nothing merges
    whatever the checks say. (The post's incident: `f = 5`, timeout 40, so any
    attempt of more than 8 minutes is a cliff.) -/
theorem slowdown_cliff (timeout f T : Nat) (gs : List Group) (hcliff : timeout < f * T)
    (hslow : ∀ g ∈ gs, f * T ≤ g.age) : merges timeout gs = 0 :=
  cliff_zero timeout gs (fun g hg => Nat.lt_of_lt_of_le hcliff (hslow g hg))

/-- The cliff is a step, not a slope: raising the timeout to `f * T` lets the
    same groups merge (when green). -/
theorem cliff_lifts (f T : Nat) (gs : List Group) (hslow : ∀ g ∈ gs, g.age = f * T)
    (hok : ∀ g ∈ gs, g.ok = true) : merges (f * T) gs = gs.length := by
  unfold merges
  rw [List.filter_eq_self.2]
  intro g hg
  simp [hslow g hg, hok g hg]

/-- A group created at `c`, last (re)started at `s`, run time `D`: it merges iff
    the run completes (no stale-main move in `[s, s + D]`) and finishes inside
    the timeout measured from CREATION, not from the restart. -/
def GroupMerges (mv : Moves) (D timeout c s : Nat) : Prop :=
  c ≤ s ∧ Completes mv D s ∧ s + D ≤ c + timeout

/-- If the run time itself exceeds the timeout, no group ever merges, however
    often it restarts. -/
theorem long_runs_never_merge (mv : Moves) (D timeout : Nat) (h : timeout < D) :
    ∀ c s, ¬ GroupMerges mv D timeout c s := by
  intro c s ⟨h1, _, h3⟩
  omega

/-- Restarts do not reset the clock: the later the last restart, the less of the
    timeout is left. A group restarted at `s` has `c + timeout - s` minutes
    for a run of `D`. -/
theorem restart_eats_timeout (mv : Moves) (D timeout c s : Nat) (h : GroupMerges mv D timeout c s) :
    D + (s - c) ≤ timeout := by
  obtain ⟨h1, _, h3⟩ := h
  omega

/-- Connection to Queue.lean's C4: when stale-main moves arrive at least once per
    run duration, no group started after the first move merges. This is a second
    route to zero, independent of the timeout. -/
theorem starved_groups_never_merge (mv : Moves) (D timeout : Nat) (h : mv.gap ≤ D) :
    ∀ c s, mv.m 0 ≤ s → ¬ GroupMerges mv D timeout c s := by
  intro c s hs ⟨_, hc, _⟩
  exact starved_never_completes mv D h s hs hc

end MergeQueueSpeedLimit
