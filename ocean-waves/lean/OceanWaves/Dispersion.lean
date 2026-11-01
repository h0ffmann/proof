import OceanWaves.RatLemmas

/-!
# Linear dispersion relation, phase speed and group velocity

Linear (Airy) theory for surface gravity waves on water of depth `h` gives

    σ² = g k tanh(k h)                         (dispersion relation)
    c  = σ / k                                 (phase speed)
    c_g = n c,  n = ½ (1 + 2kh / sinh(2kh))    (group velocity)

Here `σ` is the intrinsic radian frequency and `k` the wavenumber magnitude.
In WAVEWATCH III the wavenumber of each spectral bin varies in space with the
depth. We fix a grid of frequencies `σ_j` and solve the dispersion relation
for `k_j` at the local depth.

## No real numbers, no `tanh`

This package uses core Lean only, so there is no `ℝ` and no `tanh`. We work in
`Rat` and make `tanh` a parameter: a `TanhModel` is any function with the
properties of `tanh` on `[0, ∞)` that the proofs need. Every theorem in this
file holds for every model. The true `tanh` has all these properties except
`sat` (it never reaches 1); `pade` below is a concrete rational model that has
all of them and is close to `tanh`.

We avoid `sinh` with the identity `2x / sinh(2x) = x (1 - tanh² x) / tanh x`.
-/

namespace OW

/-- The properties of `tanh` on `[0, ∞)` that the dispersion proofs use. -/
structure TanhModel where
  T : Rat → Rat
  zero : T 0 = 0
  /-- `T` is positive for positive arguments. -/
  pos : ∀ x, 0 < x → 0 < T x
  /-- `T` is monotone on `[0, ∞)`. -/
  mono : ∀ x y, 0 ≤ x → x ≤ y → T x ≤ T y
  /-- `T x ≤ x` (true for `tanh`: shallow water is the fastest limit). -/
  le_id : ∀ x, 0 ≤ x → T x ≤ x
  /-- `T x ≤ 1` (deep-water limit). -/
  le_one : ∀ x, 0 ≤ x → T x ≤ 1
  /-- `x (1 - T² x) ≤ T x`, the same as `2x ≤ sinh 2x` for `tanh`.
      It gives `n ≤ 1`, so the group velocity is at most the phase speed. -/
  sech_bound : ∀ x, 0 < x → x * (1 - T x * T x) ≤ T x
  /-- A depth-scaled argument after which `T = 1`. The true `tanh` does not have
      this; it is a modelling choice that gives the dispersion solver a
      guaranteed starting bracket. -/
  sat : Rat
  sat_pos : 0 < sat
  T_sat : ∀ x, sat ≤ x → T x = 1

theorem TanhModel.nonneg (M : TanhModel) (x : Rat) (hx : 0 ≤ x) : 0 ≤ M.T x := by
  by_cases h : x = 0
  · subst h; rw [M.zero]; exact Rat.le_refl
  · exact Rat.le_of_lt (M.pos x (by grind))

/-- Physical setting: gravity and water depth, both positive. -/
structure Medium where
  g : Rat
  h : Rat
  g_pos : 0 < g
  h_pos : 0 < h

variable (M : TanhModel) (W : Medium)

/-- `σ²(k) = g k T(k h)`, the square of the dispersion relation. We keep `σ²`
because `Rat` has no square root. -/
def sigma2 (k : Rat) : Rat := W.g * k * M.T (k * W.h)

theorem sigma2_nonneg {k : Rat} (hk : 0 ≤ k) : 0 ≤ sigma2 M W k := by
  unfold sigma2
  exact Rat.mul_nonneg (Rat.mul_nonneg (Rat.le_of_lt W.g_pos) hk)
    (M.nonneg _ (Rat.mul_nonneg hk (Rat.le_of_lt W.h_pos)))

/-- **Dispersion is strictly increasing in `k`.** So each frequency has at most
one wavenumber, and bisection finds it. -/
theorem sigma2_strictMono {k₁ k₂ : Rat} (h0 : 0 ≤ k₁) (h12 : k₁ < k₂) :
    sigma2 M W k₁ < sigma2 M W k₂ := by
  unfold sigma2
  have hh := W.h_pos
  have hT : M.T (k₁ * W.h) ≤ M.T (k₂ * W.h) :=
    M.mono _ _ (Rat.mul_nonneg h0 (Rat.le_of_lt hh))
      (Rat.mul_le_mul_of_nonneg_right (Rat.le_of_lt h12) (Rat.le_of_lt hh))
  have hT2 : 0 < M.T (k₂ * W.h) := M.pos _ (Rat.mul_pos (by grind) hh)
  have hT1 := M.nonneg (k₁ * W.h) (Rat.mul_nonneg h0 (Rat.le_of_lt hh))
  have hgk : 0 ≤ W.g * k₁ := Rat.mul_nonneg (Rat.le_of_lt W.g_pos) h0
  have a := Rat.mul_le_mul_of_nonneg_left hT hgk
  have b := Rat.mul_lt_mul_of_pos_right (Rat.mul_lt_mul_of_pos_left h12 W.g_pos) hT2
  grind

/-- Deep-water bound: `σ² ≤ g k`. -/
theorem sigma2_le_deep {k : Rat} (hk : 0 ≤ k) : sigma2 M W k ≤ W.g * k := by
  unfold sigma2
  have := Rat.mul_le_mul_of_nonneg_left
    (M.le_one _ (Rat.mul_nonneg hk (Rat.le_of_lt W.h_pos)))
    (Rat.mul_nonneg (Rat.le_of_lt W.g_pos) hk)
  grind

/-- Shallow-water bound: `σ² ≤ g h k²`. -/
theorem sigma2_le_shallow {k : Rat} (hk : 0 ≤ k) : sigma2 M W k ≤ W.g * W.h * (k * k) := by
  unfold sigma2
  have := Rat.mul_le_mul_of_nonneg_left
    (M.le_id _ (Rat.mul_nonneg hk (Rat.le_of_lt W.h_pos)))
    (Rat.mul_nonneg (Rat.le_of_lt W.g_pos) hk)
  grind

/-- In the saturated regime (`k h ≥ sat`) dispersion is exactly the deep-water law. -/
theorem sigma2_deep_exact {k : Rat} (hk : M.sat ≤ k * W.h) : sigma2 M W k = W.g * k := by
  unfold sigma2; rw [M.T_sat _ hk]; grind

/-! ## Phase speed and group velocity -/

/-- Phase speed `c = σ / k`. -/
def phaseSpeed (σ k : Rat) : Rat := σ / k

/-- `n(x) = ½ (1 + x (1 - T² x) / T x)` with `x = k h`. For `tanh` this is the
usual `½ (1 + 2kh / sinh 2kh)`. -/
def nFactor (x : Rat) : Rat := (1 + x * (1 - M.T x * M.T x) / M.T x) / 2

/-- Group velocity `c_g = n c`. -/
def groupSpeed (σ k : Rat) : Rat := nFactor M (k * W.h) * phaseSpeed σ k

theorem nFactor_ge_half {x : Rat} (hx : 0 < x) : 1 / 2 ≤ nFactor M x := by
  unfold nFactor
  have hT := M.pos x hx
  have h1 := M.le_one x (Rat.le_of_lt hx)
  have hTT : M.T x * M.T x ≤ 1 := by
    have := mul_le_mul' h1 h1 (Rat.le_of_lt hT) (Rat.le_of_lt hT); grind
  have : 0 ≤ x * (1 - M.T x * M.T x) / M.T x :=
    div_nonneg' (Rat.mul_nonneg (Rat.le_of_lt hx) (by grind)) (Rat.le_of_lt hT)
  generalize x * (1 - M.T x * M.T x) / M.T x = y at *
  have := half_mul_two (1 + y); have := half_mul_two 1
  grind

theorem nFactor_le_one {x : Rat} (hx : 0 < x) : nFactor M x ≤ 1 := by
  unfold nFactor
  have hT := M.pos x hx
  have : x * (1 - M.T x * M.T x) / M.T x ≤ 1 :=
    div_le_of_le_mul hT (by have := M.sech_bound x hx; grind)
  generalize x * (1 - M.T x * M.T x) / M.T x = y at *
  have := half_mul_two (1 + y)
  grind

theorem phaseSpeed_nonneg {σ k : Rat} (hσ : 0 ≤ σ) (hk : 0 < k) : 0 ≤ phaseSpeed σ k :=
  div_nonneg' hσ (Rat.le_of_lt hk)

/-- **`c/2 ≤ c_g ≤ c`**: group velocity lies between half the phase speed (deep
water) and the phase speed (shallow water). -/
theorem groupSpeed_bounds {σ k : Rat} (hσ : 0 ≤ σ) (hk : 0 < k) :
    phaseSpeed σ k / 2 ≤ groupSpeed M W σ k ∧ groupSpeed M W σ k ≤ phaseSpeed σ k := by
  have hx : 0 < k * W.h := Rat.mul_pos hk W.h_pos
  have hc := phaseSpeed_nonneg hσ hk
  have lo := Rat.mul_le_mul_of_nonneg_right (nFactor_ge_half M hx) hc
  have hi := Rat.mul_le_mul_of_nonneg_right (nFactor_le_one M hx) hc
  unfold groupSpeed
  constructor <;> grind

theorem groupSpeed_nonneg {σ k : Rat} (hσ : 0 ≤ σ) (hk : 0 < k) : 0 ≤ groupSpeed M W σ k := by
  have := groupSpeed_bounds M W hσ hk
  have := phaseSpeed_nonneg hσ hk
  have := half_mul_two (phaseSpeed σ k)
  grind

/-- **No wave outruns the shallow-water speed.** If `k` is at or above the root
of the dispersion relation for `σ` (that is `σ² ≤ σ²(k)`), then `c² ≤ g h`.
For the exact root this is the textbook `c ≤ √(g h)`. -/
theorem phaseSpeed_sq_le {σ k : Rat} (hk : 0 < k) (hd : σ * σ ≤ sigma2 M W k) :
    phaseSpeed σ k * phaseSpeed σ k ≤ W.g * W.h := by
  have hs := sigma2_le_shallow M W (Rat.le_of_lt hk)
  unfold phaseSpeed
  have hkk : 0 < k * k := Rat.mul_pos hk hk
  have e : σ / k * (σ / k) = (σ * σ) / (k * k) := by grind
  rw [e]
  exact div_le_of_le_mul hkk (by grind)

/-- Deep-water version: `c² ≤ g / k`, written as `c² k ≤ g`. -/
theorem phaseSpeed_sq_le_deep {σ k : Rat} (hk : 0 < k) (hd : σ * σ ≤ sigma2 M W k) :
    phaseSpeed σ k * phaseSpeed σ k * k ≤ W.g := by
  have hs := sigma2_le_deep M W (Rat.le_of_lt hk)
  unfold phaseSpeed
  have e : σ / k * (σ / k) * k = (σ * σ) / k := by grind
  rw [e]
  exact div_le_of_le_mul hk (by grind)

/-- **Depth-based CFL condition.** If `g h Δt² ≤ Δx²`, the Courant number
`μ = c_g Δt / Δx` of every frequency is in `[0, 1]`. So a time step chosen from
the depth alone is safe for the whole spectrum. -/
theorem courant_le_one {σ k Δt Δx : Rat} (hσ : 0 ≤ σ) (hk : 0 < k)
    (hd : σ * σ ≤ sigma2 M W k) (ht : 0 ≤ Δt) (hx : 0 < Δx)
    (hcfl : W.g * W.h * (Δt * Δt) ≤ Δx * Δx) :
    0 ≤ groupSpeed M W σ k * Δt / Δx ∧ groupSpeed M W σ k * Δt / Δx ≤ 1 := by
  have hcg := groupSpeed_nonneg M W hσ hk
  have hb := (groupSpeed_bounds M W hσ hk).2
  have hc := phaseSpeed_nonneg hσ hk
  have hcc := phaseSpeed_sq_le M W hk hd
  have hμ0 : 0 ≤ groupSpeed M W σ k * Δt / Δx :=
    div_nonneg' (Rat.mul_nonneg hcg ht) (Rat.le_of_lt hx)
  refine ⟨hμ0, le_one_of_sq_le_one ?_⟩
  -- (c_g Δt / Δx)² ≤ c² Δt² / Δx² ≤ g h Δt² / Δx² ≤ 1
  have hgg : groupSpeed M W σ k * groupSpeed M W σ k ≤ W.g * W.h :=
    Rat.le_trans (mul_le_mul' hb hb hcg hcg) hcc
  have hxx : 0 < Δx * Δx := Rat.mul_pos hx hx
  have e : groupSpeed M W σ k * Δt / Δx * (groupSpeed M W σ k * Δt / Δx)
      = (groupSpeed M W σ k * groupSpeed M W σ k) * (Δt * Δt) / (Δx * Δx) := by grind
  rw [e]
  refine div_le_of_le_mul hxx ?_
  have := Rat.mul_le_mul_of_nonneg_right hgg (sq_nonneg' Δt)
  grind

/-! ## A concrete rational `tanh`

`pade x = x (27 + x²) / (27 + 9 x²)` is the [3/2] Padé approximant of `tanh`.
It is exactly 1 at `x = 3`, so we clamp it there. The largest error against
`tanh` is about 0.02 (near `x ≈ 2`); this is a model for the proofs and the
examples, not a replacement for a double-precision `tanh`. -/

def pade (x : Rat) : Rat := x * (27 + x * x) / (27 + 9 * (x * x))

/-- The clamped Padé model. -/
def padeT (x : Rat) : Rat := if x ≤ 3 then pade x else 1

theorem pade_den_pos (x : Rat) : 0 < 27 + 9 * (x * x) := by
  have := sq_nonneg' x; grind

theorem pade_three : pade 3 = 1 := by unfold pade; grind

/-- The Padé approximant is monotone on all of `Rat`. The key identity is
`b p(a)… − a p(b)… = (b − a) (9 (9 − ab)² + 27 (a − b)²)`. -/
theorem pade_mono {a b : Rat} (hab : a ≤ b) : pade a ≤ pade b := by
  unfold pade
  apply div_le_div_of_cross (pade_den_pos a) (pade_den_pos b)
  have key : b * (27 + b * b) * (27 + 9 * (a * a)) - a * (27 + a * a) * (27 + 9 * (b * b))
      = (b - a) * (9 * ((9 - a * b) * (9 - a * b)) + 27 * ((a - b) * (a - b))) := by grind
  have : 0 ≤ (b - a) * (9 * ((9 - a * b) * (9 - a * b)) + 27 * ((a - b) * (a - b))) :=
    Rat.mul_nonneg (by grind)
      (by have := sq_nonneg' (9 - a * b); have := sq_nonneg' (a - b); grind)
  grind

theorem pade_pos {x : Rat} (hx : 0 < x) : 0 < pade x := by
  unfold pade
  exact div_pos' (Rat.mul_pos hx (by have := sq_nonneg' x; grind)) (pade_den_pos x)

theorem pade_le_id {x : Rat} (hx : 0 ≤ x) : pade x ≤ x := by
  unfold pade
  apply div_le_of_le_mul (pade_den_pos x)
  have : 0 ≤ x * (x * x) := Rat.mul_nonneg hx (sq_nonneg' x)
  grind

/-- `x (1 - p²/q²) ≤ p/q`. The gap is `x · x² · ((x² − 9)² + 432) / q²`. -/
theorem pade_sech_bound {x : Rat} (hx : 0 < x) : x * (1 - pade x * pade x) ≤ pade x := by
  have hq := pade_den_pos x
  have hq0 : (27 + 9 * (x * x)) ≠ 0 := by grind
  -- write `pade x = p / q`
  have hp : pade x * (27 + 9 * (x * x)) = x * (27 + x * x) := by unfold pade; grind
  have hqq : 0 < (27 + 9 * (x * x)) * (27 + 9 * (x * x)) := Rat.mul_pos hq hq
  -- multiply the goal by q²
  suffices h : x * (1 - pade x * pade x) * ((27 + 9 * (x * x)) * (27 + 9 * (x * x)))
      ≤ pade x * ((27 + 9 * (x * x)) * (27 + 9 * (x * x))) by
    exact le_of_mul_le_mul_right' h hqq
  have l : x * (1 - pade x * pade x) * ((27 + 9 * (x * x)) * (27 + 9 * (x * x)))
      = x * ((27 + 9 * (x * x)) * (27 + 9 * (x * x)))
        - x * ((pade x * (27 + 9 * (x * x))) * (pade x * (27 + 9 * (x * x)))) := by grind
  have r : pade x * ((27 + 9 * (x * x)) * (27 + 9 * (x * x)))
      = (pade x * (27 + 9 * (x * x))) * (27 + 9 * (x * x)) := by grind
  rw [l, r, hp]
  have gap : 0 ≤ x * ((x * x) * ((x * x - 9) * (x * x - 9) + 432)) :=
    Rat.mul_nonneg (Rat.le_of_lt hx)
      (Rat.mul_nonneg (sq_nonneg' x) (by have := sq_nonneg' (x * x - 9); grind))
  grind

theorem padeT_le_one {x : Rat} : padeT x ≤ 1 := by
  unfold padeT
  split
  · have := pade_mono (by assumption : x ≤ 3); rw [pade_three] at this; exact this
  · exact Rat.le_refl

/-- The clamped Padé function satisfies every `TanhModel` property. -/
def padeModel : TanhModel where
  T := padeT
  zero := by unfold padeT pade; rw [if_pos (by grind)]; grind
  pos := fun x hx => by
    unfold padeT; split
    · exact pade_pos hx
    · grind
  mono := fun x y _ hxy => by
    unfold padeT
    split <;> split
    · exact pade_mono hxy
    · have := pade_mono (by assumption : x ≤ 3); rw [pade_three] at this; exact this
    · grind
    · exact Rat.le_refl
  le_id := fun x hx => by
    unfold padeT; split
    · exact pade_le_id hx
    · grind
  le_one := fun x _ => padeT_le_one
  sech_bound := fun x hx => by
    unfold padeT; split
    · exact pade_sech_bound hx
    · grind
  sat := 3
  sat_pos := by grind
  T_sat := fun x hx => by
    unfold padeT; split
    · have : x = 3 := by grind
      subst this; exact pade_three
    · rfl

end OW
