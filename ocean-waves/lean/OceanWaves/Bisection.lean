import OceanWaves.Dispersion

/-!
# Solving the dispersion relation by bisection

WAVEWATCH III needs `k` for each discrete frequency `σ` and each depth `h`. We
solve `σ²(k) = σ²` by bisection on `k`, in exact `Rat` arithmetic.

`bisect f target n lo hi` halves the bracket `[lo, hi]` `n` times. The proofs
do not need continuity (there is none in core Lean). They show:

* the bracket invariant `f lo < target ≤ f hi` is kept (one side at a time);
* `lo < hi` is kept, and the width after `n` steps is `(hi - lo) / 2ⁿ`;
* if `f` is strictly increasing, every exact root lies in `(lo, hi]`.

The solver returns the **upper end** `hi`. That choice matters: `σ² ≤ σ²(hi)`
always holds, so the phase speed computed from it provably obeys `c² ≤ g h`
(`phaseSpeed_sq_le`) and the time step from `courant_le_one` is safe, with no
claim that the root was found exactly.
-/

namespace OW

def bisect (f : Rat → Rat) (target : Rat) : Nat → Rat → Rat → Rat × Rat
  | 0, lo, hi => (lo, hi)
  | n + 1, lo, hi =>
    let m := (lo + hi) / 2
    if f m < target then bisect f target n m hi else bisect f target n lo m

variable (f : Rat → Rat) (target : Rat)

theorem bisect_hi (n : Nat) : ∀ lo hi, target ≤ f hi → target ≤ f (bisect f target n lo hi).2 := by
  induction n with
  | zero => intro lo hi h; exact h
  | succ n ih =>
    intro lo hi h
    simp only [bisect]
    split
    · exact ih _ _ h
    · exact ih _ _ (by grind)

theorem bisect_lo (n : Nat) : ∀ lo hi, f lo < target → f (bisect f target n lo hi).1 < target := by
  induction n with
  | zero => intro lo hi h; exact h
  | succ n ih =>
    intro lo hi h
    simp only [bisect]
    split
    · exact ih _ _ (by assumption)
    · exact ih _ _ h

theorem mid_between {lo hi : Rat} (h : lo < hi) : lo < (lo + hi) / 2 ∧ (lo + hi) / 2 < hi := by
  have := half_mul_two (lo + hi); constructor <;> grind

theorem bisect_lt (n : Nat) : ∀ lo hi, lo < hi → (bisect f target n lo hi).1 < (bisect f target n lo hi).2 := by
  induction n with
  | zero => intro lo hi h; exact h
  | succ n ih =>
    intro lo hi h
    have := mid_between h
    simp only [bisect]
    split
    · exact ih _ _ this.2
    · exact ih _ _ this.1

theorem bisect_lo_mono (n : Nat) : ∀ lo hi, lo < hi → lo ≤ (bisect f target n lo hi).1 := by
  induction n with
  | zero => intro lo hi _; exact Rat.le_refl
  | succ n ih =>
    intro lo hi h
    have := mid_between h
    simp only [bisect]
    split
    · exact Rat.le_trans (Rat.le_of_lt this.1) (ih _ _ this.2)
    · exact ih _ _ this.1

/-- **Width halves each step**: `hi_n - lo_n = (hi - lo) / 2ⁿ`. -/
theorem bisect_width (n : Nat) : ∀ lo hi,
    ((bisect f target n lo hi).2 - (bisect f target n lo hi).1) * 2 ^ n = hi - lo := by
  induction n with
  | zero => intro lo hi; simp [bisect]
  | succ n ih =>
    intro lo hi
    have hm := half_mul_two (lo + hi)
    simp only [bisect, Rat.pow_succ]
    split
    · have := ih ((lo + hi) / 2) hi; grind
    · have := ih lo ((lo + hi) / 2); grind

/-- **Any root sits in the final bracket** when `f` is strictly increasing on
`[lo, ∞)`. -/
theorem bisect_root (n : Nat) (lo hi r : Rat)
    (hmono : ∀ a b, lo ≤ a → a < b → f a < f b) (hlohi : lo < hi)
    (hlo : f lo < target) (hhi : target ≤ f hi) (hr0 : lo ≤ r) (hr : f r = target) :
    (bisect f target n lo hi).1 < r ∧ r ≤ (bisect f target n lo hi).2 := by
  have h1 := bisect_lo f target n lo hi hlo
  have h2 := bisect_hi f target n lo hi hhi
  have h3 := bisect_lt f target n lo hi hlohi
  have h4 := bisect_lo_mono f target n lo hi hlohi
  constructor
  · apply Rat.not_le.mp; intro hle
    by_cases heq : r = (bisect f target n lo hi).1
    · rw [← heq] at h1; clear hmono; grind
    · have hlt : r < (bisect f target n lo hi).1 := Rat.lt_of_le_of_ne hle heq
      have := hmono r _ hr0 hlt; clear hmono; grind
  · apply Rat.not_lt.mp; intro hlt
    have hle : lo ≤ (bisect f target n lo hi).2 := Rat.le_trans h4 (Rat.le_of_lt h3)
    have := hmono _ _ hle hlt; clear hmono; grind

theorem two_pow_pos (n : Nat) : (0 : Rat) < 2 ^ n := by
  induction n with
  | zero => simp; grind
  | succ n ih => rw [Rat.pow_succ]; exact Rat.mul_pos ih (by grind)

theorem sq_pos_of_ne {σ : Rat} (h : σ ≠ 0) : 0 < σ * σ := by
  by_cases hs : 0 < σ
  · exact Rat.mul_pos hs hs
  · have : 0 < -σ := by grind
    have := Rat.mul_pos this this; grind

/-! ## The dispersion solver -/

variable (M : TanhModel) (W : Medium)

/-- Starting upper bracket: `max (σ²/g) (sat/h)`. Then `k h ≥ sat`, so the model
is in its deep regime and `σ²(k) = g k ≥ σ²`. -/
def kHi0 (σ : Rat) : Rat := max (σ * σ / W.g) (M.sat / W.h)

theorem kHi0_pos (σ : Rat) : 0 < kHi0 M W σ := by
  unfold kHi0
  have : 0 < M.sat / W.h := div_pos' M.sat_pos W.h_pos
  have : M.sat / W.h ≤ max (σ * σ / W.g) (M.sat / W.h) := le_max_right' _ _
  grind

theorem kHi0_bracket (σ : Rat) : σ * σ ≤ sigma2 M W (kHi0 M W σ) := by
  have hs : M.sat ≤ kHi0 M W σ * W.h := by
    have : M.sat / W.h ≤ kHi0 M W σ := le_max_right' _ _
    have := Rat.mul_le_mul_of_nonneg_right this (Rat.le_of_lt W.h_pos)
    have e : M.sat / W.h * W.h = M.sat := by have := W.h_pos; grind
    grind
  rw [sigma2_deep_exact M W hs]
  have : σ * σ / W.g ≤ kHi0 M W σ := le_max_left' _ _
  have := Rat.mul_le_mul_of_nonneg_left this (Rat.le_of_lt W.g_pos)
  have e : W.g * (σ * σ / W.g) = σ * σ := by have := W.g_pos; grind
  grind

/-- The bracket after `iters` halvings of `[0, kHi0]`. -/
def kBracket (σ : Rat) (iters : Nat) : Rat × Rat :=
  bisect (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ)

/-- **Wavenumber kernel**: the upper end of the final bracket. -/
def waveNumber (σ : Rat) (iters : Nat) : Rat := (kBracket M W σ iters).2

theorem waveNumber_pos (σ : Rat) (iters : Nat) : 0 < waveNumber M W σ iters := by
  have h := bisect_lt (sigma2 M W) (σ * σ) iters 0 _ (kHi0_pos M W σ)
  have h0 := bisect_lo_mono (sigma2 M W) (σ * σ) iters 0 _ (kHi0_pos M W σ)
  unfold waveNumber kBracket; grind

/-- The returned `k` is never below the root: `σ² ≤ σ²(k)`. -/
theorem waveNumber_upper (σ : Rat) (iters : Nat) : σ * σ ≤ sigma2 M W (waveNumber M W σ iters) :=
  bisect_hi _ _ iters _ _ (kHi0_bracket M W σ)

/-- **Error bound**: if `σ ≠ 0` and `r` is a root, then `0 ≤ k − r < kHi0 / 2ⁿ`. -/
theorem waveNumber_error (σ : Rat) (hσ : σ ≠ 0) (iters : Nat) (r : Rat)
    (hr0 : 0 ≤ r) (hr : sigma2 M W r = σ * σ) :
    r ≤ waveNumber M W σ iters ∧
    (waveNumber M W σ iters - r) * 2 ^ iters < kHi0 M W σ := by
  have hpos := sq_pos_of_ne hσ
  have h0 : sigma2 M W 0 = 0 := by unfold sigma2; grind
  have hroot := bisect_root (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ) r
    (fun a b ha hab => sigma2_strictMono M W ha hab) (kHi0_pos M W σ)
    (by grind) (kHi0_bracket M W σ) hr0 hr
  have hw := bisect_width (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ)
  have hp := two_pow_pos iters
  unfold waveNumber kBracket
  refine ⟨hroot.2, ?_⟩
  have := Rat.mul_lt_mul_of_pos_right
    (by grind : (bisect (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ)).2 - r
      < (bisect (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ)).2
        - (bisect (sigma2 M W) (σ * σ) iters 0 (kHi0 M W σ)).1) hp
  grind

end OW
