# Ocean waves: the physics of a spectral wave model in Lean 4

This folder states the theory under spectral wave models such as WAVEWATCH III
(WW3) in Lean 4. It also writes the numerical kernels of one model time step in
pure Lean, and proves what core Lean can prove about them. There is no FFI and no
Fortran. The kernels run in exact `Rat` arithmetic, and `lake build` checks every
proof and prints the examples.

## What "WW3 and WW4" means here

- **WW3** is NOAA's WAVEWATCH III, a third-generation spectral wave model.
- **WW4**: no released model is called WAVEWATCH IV. A search found nothing.
  We read "WW4" as **WAM Cycle 4**, the ECMWF wave-model physics. WW3 ships it
  as its `ST3` source-term package, next to `ST1` (WAM Cycle 3), `ST2`
  (Tolman and Chalikov) and `ST4` (Ardhuin et al.). The source terms here use
  the WAM forms: Snyder-type wind input and the Cycle 4 whitecapping term.

If "WW4" means something else, the theory layer does not change. Only the
choice of parameterisations in `Sources.lean` would change.

## The equation

WW3 solves the action balance equation for the action density
`N(k, θ; x, t) = F(k, θ) / σ`:

```text
∂N/∂t + ∇ₓ·((c_g + U) N) + ∂ₖ(k̇ N) + ∂_θ(θ̇ N) = S / σ
S = S_in + S_nl + S_ds + …
σ² = g k tanh(k h)                     (linear dispersion)
c = σ / k,   c_g = n c,   n = ½ (1 + 2kh / sinh 2kh)
```

WW3 integrates it by fractional steps: propagation, then the local source
terms. This package does the same in a reduced setting. It uses one
geographic dimension, a fixed depth, no current and a periodic domain.

## Layout

```text
lean/                              Lake package `OceanWaves`, core Lean only, toolchain v4.24.0
  OceanWaves/RatLemmas.lean        order lemmas for Rat, finite sums, tabulation
  OceanWaves/Dispersion.lean       tanh as a model, σ²(k), phase/group speed, depth CFL, Padé tanh
  OceanWaves/Bisection.lean        verified bisection; the wavenumber kernel
  OceanWaves/Advection.lean        upwind advection in flux form
  OceanWaves/Sources.lean          wind input, whitecapping, quadruplet transfer, source integration
  OceanWaves/ActionBalance.lean    one model step and its theorems; a fast step proved equal
  OceanWaves/Examples.lean         #eval outputs and two counterexamples
```

Run it:

```bash
cd ocean-waves/lean && lake build      # checks every proof, prints the #evals
```

The same kernels and theorems are also in Agda, in `agda/src/OceanWaves/` (`just agda`). The
port and how it differs from Lean (total division, decisions, no `funext`) are in
[`agda/README.md`](../agda/README.md).

## No real numbers, so `tanh` is a parameter

Core Lean has no `ℝ`, no `tanh` and no derivatives. So:

- `TanhModel` collects the properties of `tanh` on `[0, ∞)` that the proofs use.
  These are `T 0 = 0`, `T > 0`, monotone, `T x ≤ x`, `T x ≤ 1` and
  `x (1 − T²) ≤ T` (that is, `2x ≤ sinh 2x`). The true `tanh` has all of them.
- One extra field, `sat`, says that `T = 1` after some point. The true `tanh`
  does not have it. It gives the solver a starting bracket that is known to be
  valid.
- `padeModel` is a concrete instance: the [3/2] Padé approximant
  `x (27 + x²) / (27 + 9x²)`, clamped to 1 at `x = 3`. All its properties are
  proved. Its largest error against `tanh` is about 0.02, near `x = 2`.
- `Rat` has no square root, so the theory works with `σ²`, and the kernels take
  `σ` from a frequency grid. Then `k`, `c = σ/k` and `c_g` are all rational.

## What is proved

| Area | Theorem | Statement |
|---|---|---|
| Dispersion | `sigma2_strictMono` | `σ²(k)` is strictly increasing, so each `σ` has at most one `k` |
| | `sigma2_le_deep`, `sigma2_le_shallow` | `σ² ≤ g k` and `σ² ≤ g h k²` |
| | `phaseSpeed_sq_le` | if `σ² ≤ σ²(k)`, then `c² ≤ g h`: no wave is faster than `√(gh)` |
| | `groupSpeed_bounds` | `c/2 ≤ c_g ≤ c` |
| | `courant_le_one` | if `g h Δt² ≤ Δx²`, then `0 ≤ c_g Δt/Δx ≤ 1` for every frequency |
| | `padeModel` | the Padé `tanh` meets every `TanhModel` property |
| Solver | `bisect_hi`, `bisect_lo`, `bisect_width` | bracket invariant; width `(hi − lo)/2ⁿ` |
| | `waveNumber_upper` | the returned `k` satisfies `σ² ≤ σ²(k)`, so the CFL theorems apply to it |
| | `waveNumber_error` | `0 ≤ k − r < k_hi0 / 2ⁿ` for any exact root `r` |
| Advection | `advect_sum` | total change = inflow flux − outflow flux |
| | `advectPeriodic_sum` | exact conservation on a periodic grid |
| | `advect_nonneg`, `advect_le_max` | positivity and maximum principle under `0 ≤ μ ≤ 1` |
| | `advect_is_euler` | the kernel is forward Euler of the flux-form equation |
| Sources | `windRate_nonneg`, `windRate_zero` | `β ≥ 0`; `β = 0` when the wave outruns the wind |
| | `dsRate_nonneg` | whitecapping only dissipates (`γ ≥ 0`) |
| | `snl_conserves_action` | quadruplet transfer conserves action, for any exchange amounts |
| | `snl_conserves_energy` | it conserves energy `Σ σ N` on a uniform frequency grid |
| | `linStep_nonneg` | semi-implicit `N (1 + Δt β)/(1 + Δt γ)` is positive for every `Δt` |
| | `eulerStep_nonneg` | explicit Euler is positive only if `Δt (γ − β) ≤ 1` |
| | `sourceStep_sum` | if the limiter does not clip, `S_nl` adds no action |
| Model step | `courant_bins` | the depth CFL makes every bin's Courant number lie in `[0, 1]` |
| | `propagate_total` | propagation conserves total action |
| | `propagate_nonneg`, `step_nonneg` | the step keeps the spectrum non-negative |
| | `step_total` | action budget of one step |
| | `stepFast_eq` | the tabulated (fast) step computes exactly `step` |

There is no `sorry`, `admit` or `axiom`. `native_decide` appears only in
`Examples.lean`, for two concrete counterexamples: upwind with `μ = 3/2` and
explicit Euler with `Δt γ = 3` both give a negative action.

## What is only specified, not proved

- **The PDE itself.** Core Lean cannot state derivatives. The continuous
  equation is in the docstrings. The Lean objects are its discretisation.
  `advect_is_euler` links the kernel to the semi-discrete equation, but there
  is no convergence proof.
- **`tanh`.** The theorems hold for every `TanhModel`. The examples use the
  Padé model. Nothing is proved about the true `tanh`, because it is not in core
  Lean.
- **The physics of the parameterisations.** The forms of `S_in`, `S_ds` and the
  quadruplet exchange are empirical fits. Lean checks their sign structure and
  conservation laws, not that they describe the ocean.
- **Simplifications against WW3 and WAM.**
  - First-order upwind, not the higher-order UQ scheme.
  - No refraction, shoaling, currents or second space dimension.
  - The mean wavenumber `k̄` uses the `k⁻¹` moment, not WAM's `k^(−1/2)` (no square root).
  - The nonlinear transfer is a DIA-shaped exchange between neighbour bins
    on a uniform grid. The real DIA uses `λ = 0.25` and interpolates on a
    logarithmic grid.
  - The wind input is the Snyder/WAM Cycle 3 form, not Janssen's Cycle 4
    quasi-linear input.
- **Floating point.** The kernels run in `Rat`. `Float` appears only in
  `Examples.lean`, as a reference value next to a result.

## Example output

A 10 s wave (`σ = 2π/10`), 30 bisection steps:

| Depth | `k` kernel (rad/m) | `k` true `tanh` (Float Newton) | `c` (m/s) | `c_g` (m/s) |
|---|---|---|---|---|
| 10 m | 0.06751 | 0.06802 | 9.306 | 8.051 |
| 1000 m | 0.04024 | 0.04024 | 15.613 | 7.807 |

At 10 m, `c = 9.31 m/s` is below `√(gh) = 9.90 m/s`, as `phaseSpeed_sq_le`
promises. The 0.75 % error in `k` comes from the Padé `tanh`. In deep water,
`c_g = c/2`. One full step with 6 cells and 4 bins (depth 10 m, `Δt = 100 s`,
`Δx = 1 km`) gives Courant numbers 0.91, 0.82, 0.70 and 0.58. The total action
goes from 10 to 10.476 = 10 × 1.1/1.05, exactly the wind and whitecapping
factor, because the quadruplet transfer adds no action.

## References

These references are from memory and were not opened, except the WW3 manual.
The manual was checked for the switch names (`ST1` to `ST4`), the definition
`N = F/σ` and the dispersion relation.

- The WAVEWATCH III Development Group, *User manual and system documentation of
  WAVEWATCH III version 5.16*, NOAA/NWS/NCEP/MMAB Tech. Note 329, 2016.
  <https://polar.ncep.noaa.gov/waves/wavewatch/manual.v5.16.pdf>
- Komen, G. J., et al., *Dynamics and Modelling of Ocean Waves*, Cambridge University Press, 1994. (WAM Cycle 4.)
- Snyder, R. L., et al., "Array measurements of atmospheric pressure fluctuations above surface gravity waves", *J. Fluid Mech.* 102, 1981.
- Komen, G. J., Hasselmann, S., Hasselmann, K., "On the existence of a fully developed wind-sea spectrum", *J. Phys. Oceanogr.* 14, 1984.
- Hasselmann, S., et al., "Computations and parameterizations of the nonlinear energy transfer in a gravity-wave spectrum. Part II", *J. Phys. Oceanogr.* 15, 1985. (DIA.)
- Hersbach, H., Janssen, P. A. E. M., "Improvement of the short-fetch behavior in the Wave Model (WAM)", *J. Atmos. Oceanic Technol.* 16, 1999. (Limiter.)
- Bretherton, F. P., Garrett, C. J. R., "Wavetrains in inhomogeneous moving media", *Proc. R. Soc. A* 302, 1968. (Wave action.)

## Next steps

- Add the second space dimension and refraction (`θ̇`) on a depth gradient. Prove
  conservation with a varying `c_g` (`advect_sum` already allows per-face speeds).
- Use the real DIA with `λ = 0.25` on a logarithmic grid, and prove energy
  conservation with the interpolation weights.
- Port the kernels to Haskell (`Double`) and check them against these `#eval`s,
  in the same way as the contextual bandit.
- Add Mathlib for real `tanh` and a convergence statement for the scheme.
