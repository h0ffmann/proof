import OceanWaves.RatLemmas

/-!
# Propagation: first-order upwind advection in flux form

In geographic space the action balance equation has the transport term
`∂N/∂t + ∂(c_g N)/∂x`. On regular grids WAVEWATCH III offers a first-order
upwind scheme and higher-order ones (second-order UNO, third-order UQ). We use
first-order upwind, because its key properties can be proved with linear
arithmetic.

One spectral component on a 1-D grid of `n` cells, waves moving in `+x`
(`c_g ≥ 0`). Face `i` sits on the left of cell `i`; face `n` is the right edge.
`μ i = c_g(face i) Δt / Δx` is the Courant number on face `i`.

    F i      = μ i * N (i-1)          (upwind flux through face i; N(-1) = b)
    N' i     = N i + F i − F (i+1)

`b` is the boundary value that flows in on the left. A periodic domain uses
`b = N (n-1)`.

What we prove:

* **Conservation**: `Σ N' = Σ N + F 0 − F n` (only the boundary fluxes change
  the total); on a periodic grid with one Courant number, `Σ N' = Σ N`.
* **Positivity** under the CFL condition `0 ≤ μ ≤ 1`.
* **Maximum principle**: no new extrema under the same condition.
-/

namespace OW

/-- Upwind flux through face `i`. -/
def upFlux (μ : Nat → Rat) (b : Rat) (N : Nat → Rat) (i : Nat) : Rat :=
  μ i * (if i = 0 then b else N (i - 1))

/-- One upwind step. -/
def advect (μ : Nat → Rat) (b : Rat) (N : Nat → Rat) (i : Nat) : Rat :=
  N i + upFlux μ b N i - upFlux μ b N (i + 1)

/-- The step as a convex combination: `N' i = (1 − μ(i+1)) N i + μ i · N(i−1)`. -/
theorem advect_eq (μ : Nat → Rat) (b : Rat) (N : Nat → Rat) (i : Nat) :
    advect μ b N i = (1 - μ (i + 1)) * N i + μ i * (if i = 0 then b else N (i - 1)) := by
  unfold advect upFlux
  simp only [Nat.add_one_ne_zero, ↓reduceIte, Nat.add_sub_cancel]
  grind

/-- **Conservation**: the total changes only by the boundary fluxes. -/
theorem advect_sum (n : Nat) (μ : Nat → Rat) (b : Rat) (N : Nat → Rat) :
    sumTo n (advect μ b N) = sumTo n N + upFlux μ b N 0 - upFlux μ b N n := by
  unfold advect
  have h1 := sumTo_add n N (fun i => upFlux μ b N i - upFlux μ b N (i + 1))
  have h2 := sumTo_telescope n (upFlux μ b N)
  have e : (fun i => N i + upFlux μ b N i - upFlux μ b N (i + 1))
      = (fun i => N i + (upFlux μ b N i - upFlux μ b N (i + 1))) := by funext i; grind
  rw [e, h1, h2]; grind

/-- Constant Courant number. -/
def constCourant (c : Rat) : Nat → Rat := fun _ => c

/-- Periodic boundary: what leaves on the right enters on the left. -/
def advectPeriodic (n : Nat) (c : Rat) (N : Nat → Rat) : Nat → Rat :=
  advect (constCourant c) (N (n - 1)) N

/-- **Exact conservation on a periodic grid.** -/
theorem advectPeriodic_sum (n : Nat) (hn : 0 < n) (c : Rat) (N : Nat → Rat) :
    sumTo n (advectPeriodic n c N) = sumTo n N := by
  unfold advectPeriodic
  rw [advect_sum]
  unfold upFlux constCourant
  have : n ≠ 0 := by omega
  simp only [↓reduceIte, this]
  grind

/-- CFL condition on the faces `0 … n`. -/
def CFL (n : Nat) (μ : Nat → Rat) : Prop := ∀ i, i ≤ n → 0 ≤ μ i ∧ μ i ≤ 1

/-- **Positivity**: under CFL, a non-negative field and inflow stay non-negative. -/
theorem advect_nonneg (n : Nat) (μ : Nat → Rat) (b : Rat) (N : Nat → Rat)
    (hcfl : CFL n μ) (hb : 0 ≤ b) (hN : ∀ i, i < n → 0 ≤ N i) :
    ∀ i, i < n → 0 ≤ advect μ b N i := by
  intro i hi
  rw [advect_eq]
  have h1 := hcfl (i + 1) (by omega)
  have h0 := hcfl i (by omega)
  have hprev : 0 ≤ (if i = 0 then b else N (i - 1)) := by
    split
    · exact hb
    · exact hN _ (by omega)
  have := Rat.mul_nonneg (by grind : 0 ≤ 1 - μ (i + 1)) (hN i hi)
  have := Rat.mul_nonneg h0.1 hprev
  grind

/-- **Maximum principle** for a constant Courant number: if the field and the
inflow are at most `M`, so is the new field. (With varying `μ` this fails in
general: converging speeds pile up action, which is shoaling, not an error.) -/
theorem advect_le_max (n : Nat) (c : Rat) (b M : Rat) (N : Nat → Rat)
    (hc : 0 ≤ c ∧ c ≤ 1) (hb : b ≤ M) (hN : ∀ i, i < n → N i ≤ M) :
    ∀ i, i < n → advect (constCourant c) b N i ≤ M := by
  intro i hi
  rw [advect_eq]
  unfold constCourant
  have hprev : (if i = 0 then b else N (i - 1)) ≤ M := by
    split
    · exact hb
    · exact hN _ (by omega)
  have := Rat.mul_le_mul_of_nonneg_left (hN i hi) (by grind : 0 ≤ 1 - c)
  have := Rat.mul_le_mul_of_nonneg_left hprev hc.1
  grind

/-- `k` steps of periodic advection. -/
def advectPeriodicN (n : Nat) (c : Rat) : Nat → (Nat → Rat) → (Nat → Rat)
  | 0, N => N
  | k + 1, N => advectPeriodicN n c k (advectPeriodic n c N)

theorem advectPeriodicN_sum (n : Nat) (hn : 0 < n) (c : Rat) :
    ∀ k N, sumTo n (advectPeriodicN n c k N) = sumTo n N := by
  intro k
  induction k with
  | zero => intro N; rfl
  | succ k ih => intro N; simp only [advectPeriodicN]; rw [ih, advectPeriodic_sum n hn]

theorem advectPeriodicN_nonneg (n : Nat) (hn : 0 < n) (c : Rat) (hc : 0 ≤ c ∧ c ≤ 1) :
    ∀ k N, (∀ i, i < n → 0 ≤ N i) → ∀ i, i < n → 0 ≤ advectPeriodicN n c k N i := by
  intro k
  induction k with
  | zero => intro N h; exact h
  | succ k ih =>
    intro N h
    simp only [advectPeriodicN]
    apply ih
    exact advect_nonneg n _ _ N (fun _ _ => hc) (h _ (by omega)) h

end OW
