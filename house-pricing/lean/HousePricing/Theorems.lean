import HousePricing.Features
import HousePricing.Tree

/-!
# What we prove

For **every** tree ensemble (so for every model the Rust trainer can export):

1. `Tree.lo_le_eval`, `Tree.eval_le_hi`, `Ensemble.predict_bounds`: each
   prediction lies in `[m.lo, m.hi]`, two numbers computed from the model
   alone. No input, however odd, gets a prediction outside that range.
2. `Tree.eval_mono`, `Ensemble.predict_mono`: if the certificate
   `m.monoIn j` holds, the prediction never decreases when feature `j` grows
   and the other features stay the same.
3. `income_monotone`: the same, end to end on raw census rows. If the
   certificate holds for `median_income` (feature 0), a block group with a
   higher income never gets a lower price, all else equal.

`Examples.lean` checks which certificates the trained models pass.
-/

namespace HP

theorem Tree.rmin_le_left (a b : Rat) : Tree.rmin a b ≤ a := by
  unfold Tree.rmin; split <;> grind
theorem Tree.rmin_le_right (a b : Rat) : Tree.rmin a b ≤ b := by
  unfold Tree.rmin; split <;> grind
theorem Tree.le_rmax_left (a b : Rat) : a ≤ Tree.rmax a b := by
  unfold Tree.rmax; split <;> grind
theorem Tree.le_rmax_right (a b : Rat) : b ≤ Tree.rmax a b := by
  unfold Tree.rmax; split <;> grind

namespace Tree

variable {n : Nat}

theorem lo_le_eval : ∀ (t : Tree n) (x : Fin n → Rat), t.lo ≤ t.eval x
  | leaf v, _ => by simp [lo, eval]; exact Rat.le_refl
  | node f th l r, x => by
      simp only [lo, eval]
      split
      · exact Rat.le_trans (rmin_le_left _ _) (lo_le_eval l x)
      · exact Rat.le_trans (rmin_le_right _ _) (lo_le_eval r x)

theorem eval_le_hi : ∀ (t : Tree n) (x : Fin n → Rat), t.eval x ≤ t.hi
  | leaf v, _ => by simp [hi, eval]; exact Rat.le_refl
  | node f th l r, x => by
      simp only [hi, eval]
      split
      · exact Rat.le_trans (eval_le_hi l x) (le_rmax_left _ _)
      · exact Rat.le_trans (eval_le_hi r x) (le_rmax_right _ _)

/-- A tree that passes `monoIn j` is monotone in feature `j`. -/
theorem eval_mono (j : Fin n) :
    ∀ (t : Tree n), t.monoIn j = true →
    ∀ (x y : Fin n → Rat), x j ≤ y j → (∀ i, i ≠ j → x i = y i) →
    t.eval x ≤ t.eval y
  | leaf v, _, _, _, _, _ => by simp [eval]; exact Rat.le_refl
  | node f th l r, h, x, y, hj, ho => by
      simp only [monoIn, Bool.and_eq_true, bne_iff_ne, ne_eq, Bool.or_eq_true,
        decide_eq_true_eq] at h
      obtain ⟨⟨hl, hr⟩, hsplit⟩ := h
      have ihl := eval_mono j l hl x y hj ho
      have ihr := eval_mono j r hr x y hj ho
      simp only [eval]
      by_cases hf : f = j
      · subst hf
        have hlr : l.hi ≤ r.lo := by simpa using hsplit
        by_cases hx : x f ≤ th <;> by_cases hy : y f ≤ th <;> simp only [hx, hy, ite_true, ite_false]
        · exact ihl
        · exact Rat.le_trans (eval_le_hi l x) (Rat.le_trans hlr (lo_le_eval r y))
        · exact absurd (Rat.le_trans hj hy) hx
        · exact ihr
      · rw [ho f hf]
        split
        · exact (by rw [← ho f hf] at *; exact ihl)
        · exact ihr

end Tree

/-- Pointwise `≤` survives a list sum. -/
theorem sum_map_le {α : Type} (f g : α → Rat) :
    ∀ l : List α, (∀ a ∈ l, f a ≤ g a) → (l.map f).sum ≤ (l.map g).sum
  | [], _ => by simp; exact Rat.le_refl
  | a :: as, h => by
      simp only [List.map_cons, List.sum_cons]
      have h1 := h a (by simp)
      have h2 := sum_map_le f g as (fun b hb => h b (by simp [hb]))
      grind

namespace Ensemble

variable {n : Nat}

theorem lo_le_predict (m : Ensemble n) (x : Fin n → Rat) : m.lo ≤ m.predict x := by
  unfold lo predict
  have := sum_map_le Tree.lo (·.eval x) m.trees (fun t _ => Tree.lo_le_eval t x)
  grind

theorem predict_le_hi (m : Ensemble n) (x : Fin n → Rat) : m.predict x ≤ m.hi := by
  unfold hi predict
  have := sum_map_le (·.eval x) Tree.hi m.trees (fun t _ => Tree.eval_le_hi t x)
  grind

/-- Every prediction of every model lies in `[m.lo, m.hi]`. -/
theorem predict_bounds (m : Ensemble n) (x : Fin n → Rat) :
    m.lo ≤ m.predict x ∧ m.predict x ≤ m.hi :=
  ⟨lo_le_predict m x, predict_le_hi m x⟩

/-- A model whose trees all pass `monoIn j` is monotone in feature `j`. -/
theorem predict_mono (m : Ensemble n) (j : Fin n) (h : m.monoIn j = true)
    (x y : Fin n → Rat) (hj : x j ≤ y j) (ho : ∀ i, i ≠ j → x i = y i) :
    m.predict x ≤ m.predict y := by
  unfold predict
  have := sum_map_le (·.eval x) (·.eval y) m.trees (fun t ht =>
    Tree.eval_mono j t (List.all_eq_true.mp h t ht) x y hj ho)
  grind

end Ensemble

/-- The model as a function of a raw census row. -/
def predictRaw (m : Ensemble F) (r : Raw) : Rat := m.predict (features r)

/-- Changing only `income` changes only feature 0. -/
theorem features_income (r : Raw) (y : Rat) (i : Fin F) (hi : i ≠ 0) :
    features { r with income := y } i = features r i := by
  obtain ⟨k, hk⟩ := i
  cases k with
  | zero => exact absurd rfl hi
  | succ k => rfl

theorem features_income_zero (r : Raw) (y : Rat) : features { r with income := y } 0 = y := rfl

/-- **End to end.** If the certificate holds for `median_income`, a higher
income never gives a lower predicted price, all else equal. -/
theorem income_monotone (m : Ensemble F) (h : m.monoIn 0 = true) (r : Raw) (y : Rat)
    (hy : r.income ≤ y) : predictRaw m r ≤ predictRaw m { r with income := y } :=
  m.predict_mono 0 h _ _ (by simpa [features_income_zero] using hy)
    (fun i hi => (features_income r y i hi).symm)

/-- Every prediction of a model on raw rows lies in `[m.lo, m.hi]`. -/
theorem predictRaw_bounds (m : Ensemble F) (r : Raw) :
    m.lo ≤ predictRaw m r ∧ predictRaw m r ≤ m.hi :=
  m.predict_bounds _

end HP
