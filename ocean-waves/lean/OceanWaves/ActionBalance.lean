import OceanWaves.Bisection
import OceanWaves.Advection
import OceanWaves.Sources

/-!
# The wave action balance equation and one model time step

WAVEWATCH III solves the spectral action balance equation for the action
density `N(k, θ; x, t) = E / σ`:

    ∂N/∂t + ∇ₓ·((c_g + U) N) + ∂ₖ(k̇ N) + ∂_θ(θ̇ N) = S / σ,
    S = S_in + S_nl + S_ds (+ bottom friction, depth breaking, …)

Action, not energy, is the conserved quantity when currents `U` are present
(Bretherton and Garrett 1968). WW3 integrates the equation by **fractional
steps**: propagation in geographic space, then in spectral space (`k̇`, `θ̇`:
refraction and shoaling), then the local source terms.

## What is in this file

We keep one geographic dimension, a fixed depth (so `k̇ = θ̇ = 0`), no current,
and a periodic domain. A field `F x j` holds the action of bin `j` in cell `x`.
One step is:

1. for each frequency `σ_j`, solve the dispersion relation for `k_j`
   (`waveNumber`) and get `c_g,j` (`groupSpeed`);
2. advect each bin with Courant number `μ_j = c_g,j Δt / Δx` (`advectPeriodic`);
3. apply the source step in each cell (`sourceStep`).

Proved for this step:

* every `μ_j ∈ [0, 1]` as soon as `g h Δt² ≤ Δx²` (**depth-based CFL**), for
  any frequency grid and any number of bisection iterations;
* propagation conserves the total action of every bin;
* the full step keeps the spectrum non-negative;
* if the limiter does not clip, the total action changes only through wind
  input and whitecapping (the nonlinear transfer moves action, never makes it).

Only specified, not proved: the continuous PDE above (core Lean has no real
numbers or derivatives), refraction and shoaling, currents, convergence of the
scheme to the PDE, and anything about floating-point behaviour.
-/

namespace OW

/-! ## The discrete transport term is forward Euler of the flux-form equation -/

/-- Semi-discrete right-hand side of `∂N/∂t + ∂(c_g N)/∂x = 0`, upwind fluxes,
face speeds `cg`. -/
def transportRHS (Δx : Rat) (cg : Nat → Rat) (b : Rat) (N : Nat → Rat) (i : Nat) : Rat :=
  -(cg (i + 1) * N i - cg i * (if i = 0 then b else N (i - 1))) / Δx

/-- `advect` with `μ = c_g Δt / Δx` is exactly one forward-Euler step of the
semi-discrete equation. This ties the kernel to the equation it solves. -/
theorem advect_is_euler (Δt Δx : Rat) (cg : Nat → Rat) (b : Rat) (N : Nat → Rat)
    (i : Nat) :
    advect (fun f => cg f * Δt / Δx) b N i = N i + Δt * transportRHS Δx cg b N i := by
  rw [advect_eq]
  unfold transportRHS
  generalize (if i = 0 then b else N (i - 1)) = p
  grind

/-! ## One model step -/

/-- Everything a time step needs. Source rates are functions of the local
spectrum (a cell's `Nat → Rat`) so that any parameterisation can be plugged in. -/
structure StepConfig where
  M : TanhModel
  W : Medium
  /-- Number of cells and of spectral bins. -/
  nx : Nat
  nb : Nat
  /-- Frequency grid. -/
  σ : Nat → Rat
  Δt : Rat
  Δx : Rat
  /-- Bisection iterations of the dispersion solver. -/
  iters : Nat
  /-- Limiter bound. -/
  L : Rat
  β : (Nat → Rat) → Nat → Rat
  γ : (Nat → Rat) → Nat → Rat
  d : (Nat → Rat) → Nat → Rat

variable (C : StepConfig)

def StepConfig.k (j : Nat) : Rat := waveNumber C.M C.W (C.σ j) C.iters
def StepConfig.cg (j : Nat) : Rat := groupSpeed C.M C.W (C.σ j) (C.k j)
def StepConfig.μ (j : Nat) : Rat := C.cg j * C.Δt / C.Δx

/-- Step 2: propagate every bin. -/
def propagate (F : Nat → Nat → Rat) : Nat → Nat → Rat :=
  fun x j => advectPeriodic C.nx (C.μ j) (fun x' => F x' j) x

/-- Step 3: sources, cell by cell. -/
def sources (F : Nat → Nat → Rat) : Nat → Nat → Rat :=
  fun x j => sourceStep C.Δt C.L (C.β (F x)) (C.γ (F x)) C.nb (C.d (F x)) (F x) j

/-- One full time step. -/
def step (F : Nat → Nat → Rat) : Nat → Nat → Rat := sources C (propagate C F)

/-- Total action in the domain. -/
def totalAction (F : Nat → Nat → Rat) : Rat :=
  sumTo C.nx (fun x => sumTo C.nb (fun j => F x j))

/-- The conditions under which the theorems below hold. -/
structure StepConfig.Valid : Prop where
  σ_nonneg : ∀ j, 0 ≤ C.σ j
  Δt_nonneg : 0 ≤ C.Δt
  Δx_pos : 0 < C.Δx
  /-- Depth-based CFL condition: `√(g h) Δt ≤ Δx`, squared. -/
  cfl : C.W.g * C.W.h * (C.Δt * C.Δt) ≤ C.Δx * C.Δx
  nx_pos : 0 < C.nx

/-- **Every bin satisfies CFL** under the depth-based condition. -/
theorem courant_bins (hC : C.Valid) (j : Nat) : 0 ≤ C.μ j ∧ C.μ j ≤ 1 :=
  courant_le_one C.M C.W (hC.σ_nonneg j) (waveNumber_pos C.M C.W _ _)
    (waveNumber_upper C.M C.W _ _) hC.Δt_nonneg hC.Δx_pos hC.cfl

/-- **Propagation conserves the action of every bin.** -/
theorem propagate_bin_sum (hC : C.Valid) (F : Nat → Nat → Rat) (j : Nat) :
    sumTo C.nx (fun x => propagate C F x j) = sumTo C.nx (fun x => F x j) :=
  advectPeriodic_sum C.nx hC.nx_pos (C.μ j) (fun x' => F x' j)

/-- **Propagation conserves total action.** -/
theorem propagate_total (hC : C.Valid) (F : Nat → Nat → Rat) :
    totalAction C (propagate C F) = totalAction C F := by
  unfold totalAction
  rw [sumTo_comm, sumTo_comm C.nx C.nb (fun x j => F x j)]
  apply sumTo_congr; intro j _
  exact propagate_bin_sum C hC F j

/-- **Propagation keeps the spectrum non-negative.** -/
theorem propagate_nonneg (hC : C.Valid) (F : Nat → Nat → Rat)
    (hF : ∀ x j, x < C.nx → 0 ≤ F x j) : ∀ x j, x < C.nx → 0 ≤ propagate C F x j := by
  intro x j hx
  have hμ := courant_bins C hC j
  exact advect_nonneg C.nx _ _ (fun x' => F x' j) (fun _ _ => hμ)
    (hF _ j (by have := hC.nx_pos; omega)) (fun i hi => hF i j hi) x hx

/-- **The full step keeps the spectrum non-negative.** -/
theorem step_nonneg (F : Nat → Nat → Rat) : ∀ x j, 0 ≤ step C F x j := by
  intro x j
  exact sourceStep_nonneg _ _ _ _ _ _ _ j

/-- **Action budget of one step.** If the limiter does not clip anywhere, the
total action after the step equals the total after propagation and the linear
(wind and whitecapping) terms. The nonlinear transfer contributes nothing. -/
theorem step_total (F : Nat → Nat → Rat)
    (hfree : ∀ x, x < C.nx → ∀ j, j < C.nb →
      -(linStep C.Δt (C.β (propagate C F x) j) (C.γ (propagate C F x) j) (propagate C F x j))
          ≤ C.Δt * snl C.nb (C.d (propagate C F x)) j ∧
        C.Δt * snl C.nb (C.d (propagate C F x)) j ≤ C.L) :
    totalAction C (step C F)
      = sumTo C.nx (fun x => sumTo C.nb (fun j =>
          linStep C.Δt (C.β (propagate C F x) j) (C.γ (propagate C F x) j) (propagate C F x j))) := by
  unfold totalAction step sources
  apply sumTo_congr; intro x hx
  exact sourceStep_sum (hfree x hx)

/-! ## A fast step that provably agrees with `step` -/

/-- `step` with every intermediate field tabulated, so each value is computed
once. This is the kernel to run; `step` is the one to reason about. -/
def stepFast (F : Nat → Nat → Rat) : Nat → Nat → Rat :=
  let μt := tabulate C.nb C.μ
  let P := tabulate2 C.nx C.nb (fun x j => advectPeriodic C.nx (μt j) (fun x' => F x' j) x)
  tabulate2 C.nx C.nb (fun x j =>
    sourceStep C.Δt C.L (C.β (P x)) (C.γ (P x)) C.nb (C.d (P x)) (P x) j)

/-- The source parameterisations read only the `nb` bins of a cell. -/
def StepConfig.Local : Prop :=
  ∀ N N' : Nat → Rat, (∀ j, j < C.nb → N j = N' j) →
    C.β N = C.β N' ∧ C.γ N = C.γ N' ∧ C.d N = C.d N'

theorem propagate_row (F : Nat → Nat → Rat) (x : Nat) (hx : x < C.nx) :
    ∀ j, j < C.nb →
      tabulate2 C.nx C.nb (fun x j => advectPeriodic C.nx (tabulate C.nb C.μ j) (fun x' => F x' j) x) x j
        = propagate C F x j := by
  intro j hj
  rw [tabulate2_eq _ _ _ _ _ hx hj, tabulate_eq _ _ _ hj]
  rfl

/-- **The fast kernel computes exactly `step`** on the grid. -/
theorem stepFast_eq (hL : C.Local) (F : Nat → Nat → Rat) (x j : Nat) (hx : x < C.nx) (hj : j < C.nb) :
    stepFast C F x j = step C F x j := by
  unfold stepFast step sources
  rw [tabulate2_eq _ _ _ _ _ hx hj]
  have hrow := propagate_row C F x hx
  obtain ⟨hβ, hγ, hd⟩ := hL _ _ hrow
  rw [hβ, hγ, hd]
  unfold sourceStep
  simp only
  rw [hrow j hj]

end OW
