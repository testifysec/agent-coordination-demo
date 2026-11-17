/-
  MergeQueueSpeedLimit.Drain: claim 7, the fluid drain after an outage.

  Backlog `q` in changes, time in ticks (use minutes with rates per minute, or
  any consistent pair). Arrivals `arr t` and service capacity `cap t` per
  tick. One tick: `q' = q + arr - cap`, truncated at zero (a queue cannot go
  negative: capacity beyond the backlog is wasted).

  Constant arrival `l`, capacity `m` with `l < m`, so utilisation `ρ = l / m`
  is below 1. An outage of `D` ticks has capacity 0.

    * backlog after the outage = `l * D`                      (`outage_backlog`)
    * afterwards the backlog is `l*D - (m-l)*t`, floored at 0 (`drain_closed`)
    * it clears at the first `t` with `(m - l) * t ≥ l * D`, exactly
      `t = l*D / (m-l) = D·ρ/(1-ρ)` when that divides      (`drain_exact`)
      (multiply `t(1-ρ) = Dρ` through by `m`: `t(m-l) = D l`, no fractions.)
    * `drainTime` is that first `t` as a natural number (the ceiling).

  The straight line is a FLOOR, but only under hypotheses stated here:
    * capacity never exceeds `m` while draining, AND
    * arrivals are at least `l` every tick, AND
    * the backlog at the end of the outage is at least `l*D`.
  (`straight_line_floor`.) With random arrivals the second hypothesis is
  false in some ticks, and a lull makes the real backlog clear FASTER than the
  line (`floor_needs_arrivals`). So for a stochastic stream the straight line
  is not a floor tick by tick; that it is one in expectation is NOT proved
  here (it would need expectations, which need Mathlib).
-/
namespace MergeQueueSpeedLimit

/-- One tick of the fluid queue. -/
def tick (q a c : Nat) : Nat := q + a - c

/-- Backlog after `t` ticks, from `q0`, with arrivals `arr` and capacity `cap`. -/
def backlog (arr cap : Nat → Nat) (q0 : Nat) : Nat → Nat
  | 0 => q0
  | t + 1 => tick (backlog arr cap q0 t) (arr t) (cap t)

/-- During the outage nothing is served: backlog is `l * D`. -/
theorem outage_backlog (l D : Nat) : backlog (fun _ => l) (fun _ => 0) 0 D = l * D := by
  induction D with
  | zero => simp [backlog]
  | succ D ih => simp [backlog, tick, ih, Nat.mul_succ]

/-- After the outage (capacity `m ≥ l`): the backlog falls by `m - l` a tick, floored
    at zero. -/
theorem drain_closed (l m : Nat) (h : l ≤ m) (q0 : Nat) :
    ∀ t, backlog (fun _ => l) (fun _ => m) q0 t = q0 - (m - l) * t := by
  intro t
  induction t with
  | zero => simp [backlog]
  | succ t ih =>
    simp only [backlog, tick, ih, Nat.mul_succ]
    omega

/-- The backlog is gone exactly when `(m - l) * t ≥ q0`. -/
theorem drain_clears_iff (l m : Nat) (h : l ≤ m) (q0 t : Nat) :
    backlog (fun _ => l) (fun _ => m) q0 t = 0 ↔ q0 ≤ (m - l) * t := by
  rw [drain_closed l m h]; omega

/-- THE DRAIN TIME. After an outage of `D` ticks at arrival `l`, capacity `m > l`,
    if `t` solves `(m - l) * t = l * D` (that is `t = D ρ / (1 - ρ)` with
    `ρ = l / m`, multiplied through by `m`), the backlog is zero at `t` and
    positive at every earlier tick. -/
theorem drain_exact (l m D t : Nat) (h : l < m) (ht : (m - l) * t = l * D) :
    backlog (fun _ => l) (fun _ => m) (l * D) t = 0 ∧
    ∀ s, s < t → backlog (fun _ => l) (fun _ => m) (l * D) s ≠ 0 := by
  refine ⟨(drain_clears_iff l m (Nat.le_of_lt h) _ _).2 (by omega), ?_⟩
  intro s hs hz
  have := (drain_clears_iff l m (Nat.le_of_lt h) _ _).1 hz
  have h2 : (m - l) * s < (m - l) * t := Nat.mul_lt_mul_of_pos_left hs (by omega)
  omega

/-- The first tick at which the backlog is gone, for any `l*D` (ceiling). -/
def drainTime (l m D : Nat) : Nat := (l * D + (m - l) - 1) / (m - l)

theorem drainTime_spec (l m D : Nat) (h : l < m) :
    backlog (fun _ => l) (fun _ => m) (l * D) (drainTime l m D) = 0 ∧
    ∀ s, s < drainTime l m D → backlog (fun _ => l) (fun _ => m) (l * D) s ≠ 0 := by
  have hd : 0 < m - l := by omega
  have hdm := Nat.div_add_mod (l * D + (m - l) - 1) (m - l)
  have hlt := Nat.mod_lt (l * D + (m - l) - 1) hd
  unfold drainTime
  refine ⟨(drain_clears_iff l m (Nat.le_of_lt h) _ _).2 ?_, ?_⟩
  · omega
  · intro s hs hz
    have := (drain_clears_iff l m (Nat.le_of_lt h) _ _).1 hz
    have hs' : s + 1 ≤ (l * D + (m - l) - 1) / (m - l) := hs
    have h2 : (m - l) * (s + 1) ≤ (m - l) * ((l * D + (m - l) - 1) / (m - l)) :=
      Nat.mul_le_mul_left _ hs'
    rw [Nat.mul_succ] at h2
    omega

/-! ### Extra lost capacity only slows the drain. -/

/-- Monotonicity: more backlog, more arrivals or less capacity never lowers the
    backlog at any tick. -/
theorem backlog_mono (arr arr' cap cap' : Nat → Nat) (q0 q0' : Nat) (hq : q0 ≤ q0')
    (ha : ∀ t, arr t ≤ arr' t) (hc : ∀ t, cap' t ≤ cap t) :
    ∀ t, backlog arr cap q0 t ≤ backlog arr' cap' q0' t := by
  intro t
  induction t with
  | zero => simpa [backlog] using hq
  | succ t ih =>
    simp only [backlog, tick]
    have := ha t; have := hc t
    omega

/-- Capacity after a cold restart: nothing for `r` ticks, then `m`. -/
def coldRestart (r m : Nat) : Nat → Nat := fun t => if t < r then 0 else m

/-- A cold restart of `r` ticks never lowers the backlog at any tick, so it never
    shortens the drain. -/
theorem cold_restart_never_faster (l m r q0 : Nat) :
    ∀ t, backlog (fun _ => l) (fun _ => m) q0 t ≤
      backlog (fun _ => l) (coldRestart r m) q0 t := by
  refine backlog_mono _ _ _ _ q0 q0 (Nat.le_refl _) (fun _ => Nat.le_refl _) ?_
  intro t
  unfold coldRestart; split <;> omega

/-- So if the drain with the restart is done by `t`, the drain without it was. The
    restart can only add to the time. -/
theorem cold_restart_clears_later (l m r q0 t : Nat)
    (h : backlog (fun _ => l) (coldRestart r m) q0 t = 0) :
    backlog (fun _ => l) (fun _ => m) q0 t = 0 := by
  have := cold_restart_never_faster l m r q0 t
  omega

/-- THE FLOOR. If during the drain arrivals are at least `l`, capacity is at most
    `m`, and the starting backlog is at least `l * D`, the real backlog is at
    least the straight line, tick by tick. Hence a real drain cannot finish
    before `l*D ≤ (m - l) * t`. -/
theorem straight_line_floor (l m D : Nat) (hlm : l ≤ m) (arr cap : Nat → Nat) (q0 : Nat)
    (hq : l * D ≤ q0) (ha : ∀ t, l ≤ arr t) (hc : ∀ t, cap t ≤ m) :
    ∀ t, l * D - (m - l) * t ≤ backlog arr cap q0 t := by
  intro t
  have := backlog_mono (fun _ => l) arr (fun _ => m) cap (l * D) q0 hq ha hc t
  rwa [drain_closed l m hlm] at this

theorem real_drain_not_before_line (l m D : Nat) (hlm : l ≤ m) (arr cap : Nat → Nat) (q0 : Nat)
    (hq : l * D ≤ q0) (ha : ∀ t, l ≤ arr t) (hc : ∀ t, cap t ≤ m) (t : Nat)
    (hz : backlog arr cap q0 t = 0) : l * D ≤ (m - l) * t := by
  have := straight_line_floor l m D hlm arr cap q0 hq ha hc t
  omega

/-- The floor needs the arrival hypothesis. With `l = 2`, `m = 3`, `D = 3` the line
    needs 6 ticks to clear `6`; if arrivals stop after the outage it clears in
    2. -/
theorem floor_needs_arrivals :
    backlog (fun _ => 0) (fun _ => 3) 6 2 = 0 ∧
    backlog (fun _ => 2) (fun _ => 3) 6 2 ≠ 0 := by
  decide

end MergeQueueSpeedLimit
