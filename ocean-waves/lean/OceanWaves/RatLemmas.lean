/-!
# Small facts about `Rat` and finite sums

Core Lean has no `Finset.sum` and few order lemmas for `Rat`. `grind` does the
linear arithmetic, but it treats a product of two unknowns as an opaque atom.
So every nonlinear step is a named lemma here, and the physics files call them.

A grid field is a function `Nat → Rat`; only the first `n` values matter.
`sumTo n f` is `f 0 + … + f (n-1)`.
-/

namespace OW

/-! ## Order and division -/

theorem inv_nonneg' {a : Rat} (h : 0 ≤ a) : 0 ≤ a⁻¹ := by
  by_cases h0 : a = 0
  · subst h0; simp; exact Rat.le_refl
  · exact Rat.le_of_lt (Rat.inv_pos.mpr (by grind))

theorem div_nonneg' {a b : Rat} (ha : 0 ≤ a) (hb : 0 ≤ b) : 0 ≤ a / b := by
  rw [Rat.div_def]; exact Rat.mul_nonneg ha (inv_nonneg' hb)

theorem div_pos' {a b : Rat} (ha : 0 < a) (hb : 0 < b) : 0 < a / b := by
  rw [Rat.div_def]; exact Rat.mul_pos ha (Rat.inv_pos.mpr hb)

theorem mul_le_mul' {a b c d : Rat} (hab : a ≤ b) (hcd : c ≤ d) (ha : 0 ≤ a) (hc : 0 ≤ c) :
    a * c ≤ b * d := by
  have h1 := Rat.mul_le_mul_of_nonneg_right hab hc
  have h2 := Rat.mul_le_mul_of_nonneg_left hcd (Rat.le_trans ha hab)
  grind

theorem sq_nonneg' (a : Rat) : 0 ≤ a * a := by
  by_cases h : 0 ≤ a
  · exact Rat.mul_nonneg h h
  · have : 0 ≤ -a := by grind
    have := Rat.mul_nonneg this this
    grind

/-- Compare two fractions by cross multiplication. -/
theorem div_le_div_of_cross {a b c d : Rat} (hb : 0 < b) (hd : 0 < d) (h : a * d ≤ c * b) :
    a / b ≤ c / d := by
  have hbd : 0 ≤ (b * d)⁻¹ := Rat.le_of_lt (Rat.inv_pos.mpr (Rat.mul_pos hb hd))
  have := Rat.mul_le_mul_of_nonneg_right h hbd
  have e1 : a * d * (b * d)⁻¹ = a / b := by grind
  have e2 : c * b * (b * d)⁻¹ = c / d := by grind
  grind

theorem div_le_of_le_mul {a b c : Rat} (hb : 0 < b) (h : a ≤ c * b) : a / b ≤ c := by
  have := div_le_div_of_cross (d := 1) hb (by grind) (by grind : a * 1 ≤ c * b)
  have e : c / 1 = c := by grind
  grind

theorem le_div_of_mul_le {a b c : Rat} (hb : 0 < b) (h : c * b ≤ a) : c ≤ a / b := by
  have := div_le_div_of_cross (b := 1) (a := c) (c := a) (by grind) hb (by grind)
  have e : c / 1 = c := by grind
  grind

theorem le_of_mul_le_mul_right' {a b c : Rat} (h : a * c ≤ b * c) (hc : 0 < c) : a ≤ b := by
  by_cases hab : a ≤ b
  · exact hab
  · have := Rat.mul_lt_mul_of_pos_right (Rat.not_le.mp hab) hc; grind

theorem le_max_left' (a b : Rat) : a ≤ max a b := by
  show a ≤ (if a ≤ b then b else a)
  split <;> grind

theorem le_max_right' (a b : Rat) : b ≤ max a b := by
  show b ≤ (if a ≤ b then b else a)
  split <;> grind

theorem half_mul_two (a : Rat) : a / 2 * 2 = a := by grind

theorem div_mul_cancel' {a b : Rat} (hb : b ≠ 0) : a / b * b = a := by grind

/-- If `x * x ≤ 1` then `x ≤ 1`. Used to turn a squared CFL bound
into the CFL bound (there is no square root on `Rat`). -/
theorem le_one_of_sq_le_one {x : Rat} (h : x * x ≤ 1) : x ≤ 1 := by
  by_cases h1 : x ≤ 1
  · exact h1
  · have h1' : 1 < x := by grind
    have := Rat.mul_lt_mul_of_pos_left h1' (by grind : (0:Rat) < x)
    grind

/-! ## Finite sums -/

/-- `sumTo n f = f 0 + f 1 + … + f (n-1)`. -/
def sumTo (n : Nat) (f : Nat → Rat) : Rat :=
  match n with
  | 0 => 0
  | n + 1 => sumTo n f + f n

@[simp] theorem sumTo_zero (f : Nat → Rat) : sumTo 0 f = 0 := rfl
@[simp] theorem sumTo_succ (n : Nat) (f : Nat → Rat) : sumTo (n + 1) f = sumTo n f + f n := rfl

theorem sumTo_add (n : Nat) (f g : Nat → Rat) :
    sumTo n (fun i => f i + g i) = sumTo n f + sumTo n g := by
  induction n with
  | zero => simp; grind
  | succ n ih => simp [ih]; grind

theorem sumTo_sub (n : Nat) (f g : Nat → Rat) :
    sumTo n (fun i => f i - g i) = sumTo n f - sumTo n g := by
  induction n with
  | zero => simp; grind
  | succ n ih => simp [ih]; grind

theorem sumTo_mul_left (n : Nat) (c : Rat) (f : Nat → Rat) :
    sumTo n (fun i => c * f i) = c * sumTo n f := by
  induction n with
  | zero => simp only [sumTo_zero]; grind
  | succ n ih => simp only [sumTo_succ, ih]; grind

theorem sumTo_zero_fn (n : Nat) : sumTo n (fun _ => 0) = 0 := by
  induction n with
  | zero => rfl
  | succ n ih => simp only [sumTo_succ, ih]; grind

/-- Sums only look at indices below `n`. -/
theorem sumTo_congr (n : Nat) (f g : Nat → Rat) (h : ∀ i, i < n → f i = g i) :
    sumTo n f = sumTo n g := by
  induction n with
  | zero => rfl
  | succ n ih =>
    simp only [sumTo_succ]
    rw [ih (fun i hi => h i (by omega)), h n (by omega)]

/-- Peel off the first term. -/
theorem sumTo_succ_left (n : Nat) (f : Nat → Rat) :
    sumTo (n + 1) f = f 0 + sumTo n (fun i => f (i + 1)) := by
  induction n with
  | zero => simp; grind
  | succ n ih => rw [sumTo_succ, ih, sumTo_succ]; grind

theorem sumTo_nonneg (n : Nat) (f : Nat → Rat) (h : ∀ i, i < n → 0 ≤ f i) : 0 ≤ sumTo n f := by
  induction n with
  | zero => simp; exact Rat.le_refl
  | succ n ih =>
    simp only [sumTo_succ]
    have := ih (fun i hi => h i (by omega))
    have := h n (by omega)
    grind

/-- Telescoping sum. -/
theorem sumTo_telescope (n : Nat) (f : Nat → Rat) :
    sumTo n (fun i => f i - f (i + 1)) = f 0 - f n := by
  induction n with
  | zero => simp; grind
  | succ n ih => simp only [sumTo_succ, ih]; grind

/-- A sum of an indicator picks out one value. -/
theorem sumTo_ite_eq (n a : Nat) (w : Nat → Rat) (ha : a < n) :
    sumTo n (fun j => if j = a then w j else 0) = w a := by
  induction n with
  | zero => omega
  | succ n ih =>
    simp only [sumTo_succ]
    by_cases han : a = n
    · subst han
      have : sumTo a (fun j => if j = a then w j else 0) = 0 := by
        rw [sumTo_congr a _ (fun _ => 0) (fun i hi => by simp; omega)]
        exact sumTo_zero_fn a
      simp [this]; grind
    · rw [ih (by omega)]; simp [Ne.symm han]; grind

/-- Swap the order of a finite double sum. -/
theorem sumTo_comm (m n : Nat) (f : Nat → Nat → Rat) :
    sumTo m (fun i => sumTo n (fun j => f i j)) = sumTo n (fun j => sumTo m (fun i => f i j)) := by
  induction m with
  | zero => simp [sumTo_zero_fn]
  | succ m ih =>
    simp only [sumTo_succ]
    rw [ih, ← sumTo_add]

/-! ## Turning a grid field into a list, for `#eval` -/

def toList (n : Nat) (f : Nat → Rat) : List Rat := (List.range n).map f

/-! ## Tabulation

A field `Nat → Rat` is a function, so composing kernels recomputes everything
on every lookup. `tabulate` stores the first `n` values in an array once.
The fast kernels use it; the theorems show they agree with the plain ones. -/

def tabulate (n : Nat) (f : Nat → Rat) : Nat → Rat :=
  let a := ((List.range n).map f).toArray
  fun i => a.getD i 0

theorem tabulate_eq (n : Nat) (f : Nat → Rat) (i : Nat) (h : i < n) : tabulate n f i = f i := by
  simp [tabulate, Array.getD, h]

/-- Tabulate a 2-D field (rows `x < m`, columns `j < n`). -/
def tabulate2 (m n : Nat) (f : Nat → Nat → Rat) : Nat → Nat → Rat :=
  let rows := ((List.range m).map (fun x => tabulate n (f x))).toArray
  fun x => rows.getD x (fun _ => 0)

theorem tabulate2_eq (m n : Nat) (f : Nat → Nat → Rat) (x j : Nat) (hx : x < m) (hj : j < n) :
    tabulate2 m n f x j = f x j := by
  simp [tabulate2, Array.getD, hx]
  exact tabulate_eq n (f x) j hj

end OW
