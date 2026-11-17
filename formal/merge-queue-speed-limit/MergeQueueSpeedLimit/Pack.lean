/-
  MergeQueueSpeedLimit.Pack: the counting lemma every capacity ceiling rests on.

  If you cut a stretch of time of length `W` into pieces that cannot overlap
  and are each at least `T` long, you get at most `W / T` pieces. That is the
  whole reason a queue that validates one candidate at a time cannot merge
  faster than one per validation time. Everything else in Serial.lean and
  Coordination.lean is bookkeeping around this one fact.

  Time is in whole units (minutes, or any finer tick: Reuse.lean uses a finer
  tick to carry a fraction). No Mathlib.
-/
namespace MergeQueueSpeedLimit

/-- An interval of time, `s` to `f`, half-open in spirit: two intervals are
    compatible when one ends no later than the other starts. -/
structure Iv where
  s : Nat
  f : Nat
deriving Repr, DecidableEq

/-- Two intervals do not overlap: one finishes no later than the other starts. -/
def Disj (p q : Iv) : Prop := p.f ≤ q.s ∨ q.f ≤ p.s

theorem filter_len_add (p : α → Bool) (l : List α) :
    (l.filter p).length + (l.filter (fun a => !p a)).length = l.length := by
  induction l with
  | nil => simp
  | cons a l ih =>
    cases h : p a <;> simp [h] <;> omega

/-- THE PACKING LEMMA. Pairwise-disjoint intervals, each at least `T` long,
    all inside the window `[a, a + W]`, number at most `W / T`
    (stated multiplied out: `length * T ≤ W`, so no division by zero to worry
    about). -/
theorem pack (T : Nat) :
    ∀ (n : Nat) (l : List Iv) (a W : Nat), l.length = n → l.Pairwise Disj →
      (∀ p ∈ l, p.s + T ≤ p.f ∧ a ≤ p.s ∧ p.f ≤ a + W) → l.length * T ≤ W := by
  intro n
  induction n using Nat.strongRecOn with
  | _ n ih =>
    intro l a W hn hd hb
    match l, hn with
    | [], _ => simp
    | p :: rest, hn =>
      rw [List.pairwise_cons] at hd
      obtain ⟨hdp, hdr⟩ := hd
      have hp := hb p (List.mem_cons_self ..)
      -- split the rest into what ends before p starts, and what starts after p ends
      let L := rest.filter (fun q => decide (q.f ≤ p.s))
      let R := rest.filter (fun q => !decide (q.f ≤ p.s))
      have hlen : L.length + R.length = rest.length := filter_len_add _ rest
      have hLsub : L.Pairwise Disj := hdr.sublist List.filter_sublist
      have hRsub : R.Pairwise Disj := hdr.sublist List.filter_sublist
      have hL : L.length * T ≤ p.s - a := by
        refine ih L.length (by simp only [List.length_cons] at hn; omega) L a (p.s - a) rfl hLsub ?_
        intro q hq
        have hq' := List.mem_filter.1 hq
        have hbq := hb q (List.mem_cons_of_mem _ hq'.1)
        have := of_decide_eq_true hq'.2
        omega
      have hR : R.length * T ≤ a + W - p.f := by
        refine ih R.length (by simp only [List.length_cons] at hn; omega) R p.f (a + W - p.f) rfl hRsub ?_
        intro q hq
        have hq' := List.mem_filter.1 hq
        have hbq := hb q (List.mem_cons_of_mem _ hq'.1)
        have hn' : ¬ (q.f ≤ p.s) := by
          have := hq'.2
          simpa using this
        have hdq := hdp q hq'.1
        unfold Disj at hdq
        omega
      simp only [List.length_cons]
      have : (rest.length + 1) * T = L.length * T + R.length * T + T := by
        rw [← hlen]; rw [Nat.add_mul, Nat.add_mul, Nat.one_mul]
      omega

/-- Corollary in division form. -/
theorem pack_div (T : Nat) (hT : 0 < T) (l : List Iv) (a W : Nat) (hd : l.Pairwise Disj)
    (hb : ∀ p ∈ l, p.s + T ≤ p.f ∧ a ≤ p.s ∧ p.f ≤ a + W) : l.length ≤ W / T :=
  (Nat.le_div_iff_mul_le hT).2 (pack T l.length l a W rfl hd hb)

end MergeQueueSpeedLimit
