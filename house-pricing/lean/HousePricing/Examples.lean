import HousePricing.FFI

/-!
# The trained models, checked

`native_decide` is used only here, to run the certificate checks on the two
large trained models (hundreds of trees each). The theorems they feed are proved
in `Theorems.lean` for every model.
-/

namespace HP.Examples

open HP

theorem chosen_parses : (parseEnsemble F chosenText).isSome = true := by native_decide
theorem monotone_parses : (parseEnsemble F monotoneText).isSome = true := by native_decide

/-- The monotone model passes the certificate for `median_income`. -/
theorem monotone_cert : monotone.monoIn 0 = true := by native_decide

/-- The chosen (unconstrained) model does **not**: somewhere a higher income
lowers its price. That is the cost of the best score. -/
theorem chosen_not_mono : chosen.monoIn 0 = false := by native_decide

/-- For the monotone model: a higher income never gives a lower price, all else equal. -/
theorem monotone_income (r : Raw) (y : Rat) (hy : r.income ≤ y) :
    predictRaw monotone r ≤ predictRaw monotone { r with income := y } :=
  income_monotone monotone monotone_cert r y hy

/-- For the chosen model: every prediction, for any input, lies in `[chosen.lo, chosen.hi]`. -/
theorem chosen_bounds (r : Raw) : chosen.lo ≤ predictRaw chosen r ∧ predictRaw chosen r ≤ chosen.hi :=
  predictRaw_bounds chosen r

/-- The first row of the CSV (Berkeley, NEAR BAY; true value 452 600). -/
def berkeley : Raw :=
  { lon := -12223, lat := 3788, age := 41, rooms := 880, bedrooms := 129,
    population := 322, households := 126, income := 83252, ocean := .nearBay }

#eval s!"chosen: {chosen.trees.length} trees, {chosen.leaves} leaves"
#eval s!"monotone: {monotone.trees.length} trees, {monotone.leaves} leaves"
#eval s!"chosen bounds: [{toFloat chosen.lo}, {toFloat chosen.hi}]"
#eval s!"monotone bounds: [{toFloat monotone.lo}, {toFloat monotone.hi}]"
#eval s!"berkeley: chosen {toFloat (predictRaw chosen berkeley)}, monotone {toFloat (predictRaw monotone berkeley)}"
-- The monotone model on Berkeley's row with income 10 000, 30 000, ..., 110 000 dollars: non-decreasing.
#eval (List.range 6).map fun (k : Nat) =>
  toFloat (predictRaw monotone { berkeley with income := (k : Rat) * 20000 + 10000 })

end HP.Examples
