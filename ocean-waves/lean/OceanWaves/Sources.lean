import OceanWaves.RatLemmas

/-!
# Source terms and their time integration

The right-hand side of the action balance equation is `S / σ` with

    S = S_in + S_nl + S_ds          (wind input, nonlinear transfer, whitecapping)

We formalise one representative of each, in the forms used by the WAM model
family (WAM Cycle 3 and Cycle 4, also available in WAVEWATCH III as source-term
packages). The constants are parameters: the proofs never depend on their values.

* `S_in = β N`, `β = max(0, c_in (ρ_a/ρ_w) (28 u*/c · cos(θ − θ_w) − 1)) σ`
  (Snyder et al. 1981, as adapted by Komen et al. 1984). Linear in `N`.
* `S_ds = −γ N`, `γ = C_ds σ̄ (α̂/α̂_PM)² ((1 − δ) k/k̄ + δ (k/k̄)²)`, the WAM
  Cycle 4 whitecapping form. Linear in `N` for a fixed mean state.
* `S_nl`: a sum of elementary *quadruplet* exchanges, the structure of the
  Discrete Interaction Approximation (DIA, Hasselmann et al. 1985). Each
  exchange takes `2d` from one bin and gives `d` to each neighbour.

What we prove:

* `β ≥ 0` and `γ ≥ 0` (input never removes energy, whitecapping never adds it);
  no wind input when the wave outruns the wind;
* `S_nl` conserves total action for **any** exchange amounts, and conserves
  total energy `Σ σ N` when the frequency grid is uniform;
* the WAM-style semi-implicit step `N* = N (1 + Δt β) / (1 + Δt γ)` keeps `N ≥ 0`
  for **every** `Δt ≥ 0`, whereas explicit Euler needs `Δt (γ − β) ≤ 1`;
* the limiter keeps `N ≥ 0` and bounds the change, and when it does not clip,
  the nonlinear step conserves action exactly.

What is only specified (not derived): the parameterisations themselves. They are
empirical fits; Lean checks their sign structure, not their physics.
-/

namespace OW

/-! ## Wind input -/

structure WindParams where
  /-- Coefficient `c_in` (0.25 in Snyder et al.). -/
  cIn : Rat
  /-- Density ratio `ρ_a / ρ_w`. -/
  rhoRatio : Rat
  /-- Friction velocity `u*`. -/
  ustar : Rat
  cIn_nonneg : 0 ≤ cIn
  rho_nonneg : 0 ≤ rhoRatio

/-- Growth rate `β` for a component with frequency `σ`, phase speed `c` and
`cosRel = cos(θ − θ_w)`. -/
def windRate (P : WindParams) (σ c cosRel : Rat) : Rat :=
  max 0 (P.cIn * P.rhoRatio * (28 * P.ustar * cosRel / c - 1)) * σ

theorem windRate_nonneg (P : WindParams) {σ : Rat} (c cosRel : Rat) (hσ : 0 ≤ σ) :
    0 ≤ windRate P σ c cosRel := by
  unfold windRate
  exact Rat.mul_nonneg (le_max_left' _ _) hσ

/-- No input when the wave outruns the wind: `28 u* cos / c ≤ 1` gives `β = 0`. -/
theorem windRate_zero (P : WindParams) (σ c cosRel : Rat)
    (h : 28 * P.ustar * cosRel / c ≤ 1) : windRate P σ c cosRel = 0 := by
  unfold windRate
  have h1 : P.cIn * P.rhoRatio * (28 * P.ustar * cosRel / c - 1) ≤ 0 := by
    have := Rat.mul_le_mul_of_nonneg_left (by grind : 28 * P.ustar * cosRel / c - 1 ≤ 0)
      (Rat.mul_nonneg P.cIn_nonneg P.rho_nonneg)
    grind
  have : max 0 (P.cIn * P.rhoRatio * (28 * P.ustar * cosRel / c - 1)) = 0 := by
    show (if (0 : Rat) ≤ _ then _ else 0) = 0
    split <;> grind
  rw [this]; grind

/-! ## Whitecapping (WAM Cycle 4 form) -/

structure DsParams where
  cDs : Rat
  delta : Rat
  alphaPM : Rat
  cDs_nonneg : 0 ≤ cDs
  delta_nonneg : 0 ≤ delta
  delta_le_one : delta ≤ 1

/-- The discrete spectrum on `n` bins: frequency, wavenumber, quadrature weight
(bin width × direction width) and action density. -/
structure Spectrum where
  n : Nat
  σ : Nat → Rat
  k : Nat → Rat
  w : Nat → Rat
  N : Nat → Rat

def Spectrum.energy (S : Spectrum) (i : Nat) : Rat := S.σ i * S.N i
def Spectrum.Etot (S : Spectrum) : Rat := sumTo S.n (fun i => S.w i * S.energy i)
/-- Mean frequency `σ̄ = E / Σ w E/σ` (WAM's `⟨σ⁻¹⟩⁻¹`). -/
def Spectrum.σMean (S : Spectrum) : Rat := S.Etot / sumTo S.n (fun i => S.w i * S.energy i / S.σ i)
/-- Mean wavenumber `k̄ = E / Σ w E/k`. WAM uses the `k^(−1/2)` moment; we use
the `k⁻¹` moment so that no square root is needed. -/
def Spectrum.kMean (S : Spectrum) : Rat := S.Etot / sumTo S.n (fun i => S.w i * S.energy i / S.k i)
/-- Integral steepness `α̂ = E k̄²`. -/
def Spectrum.steep (S : Spectrum) : Rat := S.Etot * (S.kMean * S.kMean)

/-- Whitecapping rate `γ` for bin `i`. -/
def dsRate (P : DsParams) (S : Spectrum) (i : Nat) : Rat :=
  let r := S.steep / P.alphaPM
  let q := S.k i / S.kMean
  P.cDs * S.σMean * (r * r) * ((1 - P.delta) * q + P.delta * (q * q))

/-- A physically admissible spectrum: positive frequencies and wavenumbers,
non-negative weights and action. -/
def Spectrum.Admissible (S : Spectrum) : Prop :=
  ∀ i, i < S.n → 0 < S.σ i ∧ 0 < S.k i ∧ 0 ≤ S.w i ∧ 0 ≤ S.N i

theorem Spectrum.Etot_nonneg (S : Spectrum) (hS : S.Admissible) : 0 ≤ S.Etot := by
  unfold Spectrum.Etot Spectrum.energy
  apply sumTo_nonneg; intro i hi
  have := hS i hi
  exact Rat.mul_nonneg this.2.2.1 (Rat.mul_nonneg (Rat.le_of_lt this.1) this.2.2.2)

theorem Spectrum.σMean_nonneg (S : Spectrum) (hS : S.Admissible) : 0 ≤ S.σMean := by
  unfold Spectrum.σMean
  refine div_nonneg' (S.Etot_nonneg hS) (sumTo_nonneg _ _ fun i hi => ?_)
  have := hS i hi
  exact div_nonneg' (Rat.mul_nonneg this.2.2.1
    (Rat.mul_nonneg (Rat.le_of_lt this.1) this.2.2.2)) (Rat.le_of_lt this.1)

theorem Spectrum.kMean_nonneg (S : Spectrum) (hS : S.Admissible) : 0 ≤ S.kMean := by
  unfold Spectrum.kMean
  refine div_nonneg' (S.Etot_nonneg hS) (sumTo_nonneg _ _ fun i hi => ?_)
  have := hS i hi
  exact div_nonneg' (Rat.mul_nonneg this.2.2.1
    (Rat.mul_nonneg (Rat.le_of_lt this.1) this.2.2.2)) (Rat.le_of_lt this.2.1)

/-- **Whitecapping only dissipates**: `γ ≥ 0` on every admissible spectrum. -/
theorem dsRate_nonneg (P : DsParams) (S : Spectrum) (hS : S.Admissible) (i : Nat) (hi : i < S.n) :
    0 ≤ dsRate P S i := by
  unfold dsRate
  have hq : 0 ≤ S.k i / S.kMean :=
    div_nonneg' (Rat.le_of_lt (hS i hi).2.1) (S.kMean_nonneg hS)
  have hd := P.delta_nonneg; have hd1 := P.delta_le_one
  refine Rat.mul_nonneg (Rat.mul_nonneg (Rat.mul_nonneg P.cDs_nonneg (S.σMean_nonneg hS))
    (sq_nonneg' _)) ?_
  have := Rat.mul_nonneg (by grind : 0 ≤ 1 - P.delta) hq
  have := Rat.mul_nonneg hd (Rat.mul_nonneg hq hq)
  grind

/-! ## Nonlinear transfer: quadruplet exchanges -/

/-- Quadruplet resonance used by the DIA: two waves at `σ` interact with waves at
`σ(1+λ)` and `σ(1−λ)`. The frequency condition `σ₁ + σ₂ = σ₃ + σ₄` holds for every `λ`. -/
theorem dia_resonance (σ lam : Rat) : σ + σ = σ * (1 + lam) + σ * (1 - lam) := by grind

/-- Elementary exchange centred on bin `c`, seen from bin `j`:
`+1` at `c ± 1`, `−2` at `c`. -/
def quad (c j : Nat) : Rat :=
  (if j + 1 = c then 1 else 0) + (if j = c + 1 then 1 else 0) - (if j = c then 2 else 0)

/-- A centre is interior if both neighbours exist. -/
def Interior (n c : Nat) : Prop := 1 ≤ c ∧ c + 1 < n

instance (n c : Nat) : Decidable (Interior n c) := by unfold Interior; infer_instance

/-- Nonlinear source in bin `j` from exchange amounts `d c` at every interior centre. -/
def snl (n : Nat) (d : Nat → Rat) (j : Nat) : Rat :=
  sumTo n (fun c => if Interior n c then d c * quad c j else 0)

/-- `Σ_j w_j · quad c j = w(c−1) + w(c+1) − 2 w(c)` for an interior centre. -/
theorem quad_moment (n c : Nat) (w : Nat → Rat) (hc : Interior n c) :
    sumTo n (fun j => w j * quad c j) = w (c - 1) + w (c + 1) - 2 * w c := by
  unfold quad
  have e : (fun j => w j * ((if j + 1 = c then 1 else 0) + (if j = c + 1 then 1 else 0)
        - (if j = c then 2 else 0)))
      = (fun j => ((if j = c - 1 then w j else 0) + (if j = c + 1 then w j else 0))
        - (if j = c then 2 * w j else 0)) := by
    funext j
    unfold Interior at hc
    by_cases h1 : j = c - 1
    · have : j + 1 = c := by omega
      simp [h1]; have : c - 1 ≠ c + 1 := by omega
      have : c - 1 ≠ c := by omega
      simp [*]; grind
    · have : ¬ j + 1 = c := by omega
      simp only [this, h1, ↓reduceIte]
      split <;> split <;> grind
  rw [e, sumTo_sub, sumTo_add]
  unfold Interior at hc
  rw [sumTo_ite_eq n (c - 1) w (by omega), sumTo_ite_eq n (c + 1) w (by omega),
    sumTo_ite_eq n c (fun j => 2 * w j) (by omega)]

/-- Weighted total of the nonlinear source. -/
theorem snl_moment (n : Nat) (d w : Nat → Rat) :
    sumTo n (fun j => w j * snl n d j)
      = sumTo n (fun c => if Interior n c then d c * (w (c - 1) + w (c + 1) - 2 * w c) else 0) := by
  unfold snl
  have e1 : (fun j => w j * sumTo n (fun c => if Interior n c then d c * quad c j else 0))
      = (fun j => sumTo n (fun c => if Interior n c then d c * (w j * quad c j) else 0)) := by
    funext j
    rw [← sumTo_mul_left]
    congr 1; funext c; split <;> grind
  rw [e1, sumTo_comm]
  apply sumTo_congr; intro c _
  split
  · rename_i hc
    rw [sumTo_congr n _ (fun j => d c * (w j * quad c j)) (fun j _ => by simp),
      sumTo_mul_left, quad_moment n c w hc]
  · exact sumTo_zero_fn n

/-- **Action conservation** of the nonlinear transfer, for any exchange amounts. -/
theorem snl_conserves_action (n : Nat) (d : Nat → Rat) : sumTo n (snl n d) = 0 := by
  have := snl_moment n d (fun _ => 1)
  have e : (fun j => (fun _ => (1 : Rat)) j * snl n d j) = snl n d := by funext j; grind
  rw [e] at this
  rw [this]
  rw [sumTo_congr n _ (fun _ => 0) (fun c _ => by split <;> grind)]
  exact sumTo_zero_fn n

/-- **Energy conservation** `Σ σ_j S_nl,j = 0` on a uniform frequency grid. -/
theorem snl_conserves_energy (n : Nat) (d σ : Nat → Rat)
    (hlin : ∀ c, Interior n c → σ (c - 1) + σ (c + 1) = 2 * σ c) :
    sumTo n (fun j => σ j * snl n d j) = 0 := by
  rw [snl_moment n d σ]
  rw [sumTo_congr n _ (fun _ => 0) (fun c _ => by
    split
    · rename_i hc; rw [hlin c hc]; grind
    · rfl)]
  exact sumTo_zero_fn n

/-! ## Time integration of the sources -/

/-- WAM-style semi-implicit step for the linear part: input explicit, dissipation
implicit, `N* = N (1 + Δt β) / (1 + Δt γ)`. -/
def linStep (Δt β γ N : Rat) : Rat := N * (1 + Δt * β) / (1 + Δt * γ)

/-- **Unconditional positivity** of the semi-implicit step. -/
theorem linStep_nonneg {Δt β γ N : Rat} (ht : 0 ≤ Δt) (hβ : 0 ≤ β) (hγ : 0 ≤ γ) (hN : 0 ≤ N) :
    0 ≤ linStep Δt β γ N := by
  unfold linStep
  have := Rat.mul_nonneg ht hβ; have := Rat.mul_nonneg ht hγ
  exact div_nonneg' (Rat.mul_nonneg hN (by grind)) (by grind)

/-- With no wind, the semi-implicit step only damps: `N* ≤ N`. -/
theorem linStep_damps {Δt γ N : Rat} (ht : 0 ≤ Δt) (hγ : 0 ≤ γ) (hN : 0 ≤ N) :
    linStep Δt 0 γ N ≤ N := by
  unfold linStep
  have := Rat.mul_nonneg ht hγ
  apply div_le_of_le_mul (by grind)
  have := Rat.mul_nonneg hN this
  grind

/-- Explicit Euler for comparison. -/
def eulerStep (Δt β γ N : Rat) : Rat := N + Δt * (β - γ) * N

/-- Explicit Euler is positive only under a time-step restriction. -/
theorem eulerStep_nonneg {Δt β γ N : Rat} (hN : 0 ≤ N) (h : Δt * (γ - β) ≤ 1) :
    0 ≤ eulerStep Δt β γ N := by
  unfold eulerStep
  have := Rat.mul_nonneg (by grind : 0 ≤ 1 - Δt * (γ - β)) hN
  grind

/-- Limiter: clip the increment `x` to `[−N*, L]`. WAM limits `|ΔN|` by a value
`L` from the wind (Hersbach and Janssen 1999); the lower clip `−N*` keeps `N ≥ 0`. -/
def limit (Nstar L x : Rat) : Rat := max (-Nstar) (min L x)

/-- One source step for bin `i`: semi-implicit linear part, then the limited
nonlinear increment. -/
def sourceStep (Δt L : Rat) (β γ : Nat → Rat) (n : Nat) (d N : Nat → Rat) (i : Nat) : Rat :=
  let Nstar := linStep Δt (β i) (γ i) (N i)
  Nstar + limit Nstar L (Δt * snl n d i)

theorem min_le_left' (a b : Rat) : min a b ≤ a := by
  show (if a ≤ b then a else b) ≤ a
  split <;> grind

theorem min_le_right' (a b : Rat) : min a b ≤ b := by
  show (if a ≤ b then a else b) ≤ b
  split <;> grind

/-- **Positivity of the full source step**, for every `Δt`. The lower clip `−N*`
gives this by construction. `linStep_nonneg` is what makes the clip honest: it
shows `N* ≥ 0`, so the clip only trims a removal that is too large; it never
lifts a negative value. -/
theorem sourceStep_nonneg (Δt L : Rat) (β γ : Nat → Rat) (n : Nat) (d N : Nat → Rat) (i : Nat) :
    0 ≤ sourceStep Δt L β γ n d N i := by
  unfold sourceStep limit
  have := le_max_left' (-(linStep Δt (β i) (γ i) (N i))) (min L (Δt * snl n d i))
  grind

/-- The limiter bounds the nonlinear increment from above by `L`. -/
theorem limit_le (Nstar L x : Rat) (hL : -Nstar ≤ L) : limit Nstar L x ≤ L := by
  unfold limit
  show (if -Nstar ≤ min L x then min L x else -Nstar) ≤ L
  have := min_le_left' L x
  split <;> grind

/-- When the limiter does not clip, it is the identity. -/
theorem limit_inactive {Nstar L x : Rat} (h1 : -Nstar ≤ x) (h2 : x ≤ L) : limit Nstar L x = x := by
  unfold limit
  have : min L x = x := by
    show (if L ≤ x then L else x) = x
    split <;> grind
  rw [this]
  show (if -Nstar ≤ x then x else -Nstar) = x
  split <;> grind

/-- **Action budget of the source step.** If the limiter does not clip in any bin,
the total action changes only through the linear terms: the nonlinear transfer
moves action between bins and creates none. -/
theorem sourceStep_sum {Δt L : Rat} {β γ d N : Nat → Rat} {n : Nat}
    (hfree : ∀ i, i < n → -(linStep Δt (β i) (γ i) (N i)) ≤ Δt * snl n d i ∧ Δt * snl n d i ≤ L) :
    sumTo n (sourceStep Δt L β γ n d N) = sumTo n (fun i => linStep Δt (β i) (γ i) (N i)) := by
  have e : sumTo n (sourceStep Δt L β γ n d N)
      = sumTo n (fun i => linStep Δt (β i) (γ i) (N i) + Δt * snl n d i) := by
    apply sumTo_congr; intro i hi
    unfold sourceStep
    simp only
    rw [limit_inactive (hfree i hi).1 (hfree i hi).2]
  rw [e, sumTo_add, sumTo_mul_left, snl_conserves_action]
  grind

end OW
