# WaveTheory

New ocean-wave statements in Agda. The `OceanWaves` root is a port of the Lean package in `ocean-waves/lean/`. `WaveTheory` goes past it and reuses its kernels: the dispersion relation of a `TanhModel`, the bisection solver, upwind advection, the source terms and one model step.

Every file starts with `{-# OPTIONS --safe --without-K #-}`, and no file has a postulate. `checks/agda.sh` type-checks the root `WaveTheory.agda` with the other roots.

## What the statements are about

- **Exact rationals, not real numbers.** Every quantity is in `Data.Rational`. ℚ has no square root, no sine and no exponential, so:
  - the significant wave height is stated squared (H_s² = 16 m_0);
  - Green's law is stated squared (E₁² h₁ = E₂² h₂, not H ∝ h^(-1/4));
  - the sine of a ray angle is a rational s, with no angle behind it.
- **Finite sums, not integrals.** A spectrum is a list of n bins with a frequency and an energy each. The moments are sums over the bins, the quadrature a spectral model uses. Nothing here is a theorem about a continuous spectrum.
- **A `TanhModel`, not tanh.** The dispersion statements hold for every function with the properties of tanh that `OceanWaves.Dispersion` lists. One of those properties is that the model reaches 1 at a finite argument `sat`. The true tanh does not. So the deep-water equalities (c_g = c/2, c σ = g) hold exactly in the model's saturated regime, and only in the limit for tanh. The examples use the clamped Padé model.
- **Linear theory, in one direction at a time.** Refraction is over straight, parallel depth contours. A current has one component, along the wave. 2-D propagation splits into an x sweep and a y sweep with constant, non-negative Courant numbers.

## Modules

| Module | What it proves |
|---|---|
| [`Algebra`](Algebra.agda) | `sumTo-mono`, `*-cancelʳ-≡` (a positive factor cancels from an equality), `pow` |
| [`Moments`](Moments.agda) | the moments m_p and the forms m0, m1, m2 that the proofs use. `moment-add` and `moment-scale` (moments are linear), `moment-mono`, `moment-nonneg`. `hs2` (H_s² = 16 m_0) with `hs2-superpose` (wind sea plus swell: H_s² adds) and `hs2-mono`. `m1-in-band` (the mean frequency stays in the band). `spread-eq`, and `cauchy-schwarz`: m_1² ≤ m_0 m_2 for every non-negative spectrum, by induction on the number of bins. So the spectral width is never negative (`width-nonneg`), and it is zero for one bin (`width-one-bin`) |
| [`Shoaling`](Shoaling.agda) | `shoal` (E₂ = E₁ c_g₁ / c_g₂) with `shoal-flux`, `shoal-grows`, `shoal-decays`, `shoal-compose`. `greens-law`: with c_g² = g h at both stations and the same flux, E₁² h₁ = E₂² h₂. Depth-limited breaking: `emax` (γ² h² / 16), `emax-mono`, `emax-height`. `breakCap` for one bin (`-le`, `-le-max`, `-nonneg`, `-inactive`, `-idem`, `-depth`). `breakScale` for a whole spectrum: it keeps the shape and gives `breakScale-hs` (H_s ≤ γ h after scaling), `breakScale-le`, `breakScale-nonneg`, `breakScale-inactive` |
| [`DeepWater`](DeepWater.agda) | in the saturated regime of every `TanhModel`: `nFactor-deep` (n = 1/2), `groupSpeed-deep` (c_g = c/2). At the exact root of σ² = g k: `phaseSpeed-deep` (c σ = g), `phaseSpeed-sq-deep` (c² k = g), `groupSpeed-deep-σ` (c_g σ = g/2) |
| [`Refraction`](Refraction.agda) | Snell's law `snell` (s₂ = s₁ c₂ / c₁) with `snell-invariant`, `snell-toward-normal`, `snell-stays-sine`, `snell-away`, `snell-compose`. `total-reflection` is a witness that s₂ can pass 1. With the dispersion relation: `alongshore-k` (k sin θ is constant), `shallower-shorter` (for the same σ, shallower water gives a larger k), `shoaling-turns-to-normal` (a wave that comes into shallower water turns towards the normal) |
| [`Propagation2D`](Propagation2D.agda) | the split step `step2D` (x sweep, then y sweep) and `run2D` for k steps on a periodic grid, for every k: `run2D-total` (the total is kept exactly), `run2D-nonneg`, `run2D-le` (the discrete maximum principle) and `run2D-bounded` (stability in the maximum norm) |
| [`WaveAction`](WaveAction.agda) | the Doppler relation (`absolute`, `intrinsic`, `doppler-round`, `doppler-still`, `intrinsic-following`). Action and its flux (`action-energy`, `actionFlux`). `energy-from-action`: a kept action flux fixes the energy at a second station. `no-current-energy-flux`: with no current, the action flux is the energy flux of `Shoaling`. `blocked`: a current with c_g + U ≤ 0 carries no action forward |
| [`TimeLoop`](TimeLoop.agda) | `run`, k steps of `OceanWaves.ActionBalance.step`. `run-nonneg`: the spectrum stays non-negative for every k and every Δt. `linStep-le` and `step-total-le`; `run-total-le`: when whitecapping is at least the wind input, the total action never grows (stability in the ℓ¹ norm). `linStep-le-growth`, `step-total-growth` and `run-total-growth`: with the input at most B, total(k) ≤ (1 + Δt B)^k total(0), a discrete Grönwall bound |
| [`Examples`](Examples.agda) | numbers checked by `refl` or `from-yes`. A four-bin spectrum (m_0 = 8, m_1 = 19/2, m_2 = 51/4, H_s² = 128, width 47/4). Breaking in 2 m with γ = 4/5 (factor 1/50, H_s² = 64/25). Shoaling and Snell. A 10 s wave from 10 m to 5 m (k grows, the ray turns). c_g = c/2 at k h = 10. A 3 × 3 pulse (a square of quarters, an exact diagonal shift at Courant 1, the total kept). An opposing current that carries the same action flux with six times the energy, and blocking |

## Assumptions to know

- `run-total-le` and `run-total-growth` need the limiter to be inactive (`Free`) on the fields that the run reaches. They take this as a premise for each step of the run itself, not for every field. When the limiter clips, the budget is not exact, and these theorems say nothing.
- `shallower-shorter` and `shoaling-turns-to-normal` take exact roots of the dispersion relation as premises. The bisection solver gives a root only to within its bracket width (`OceanWaves.Bisection.waveNumber-error`). The 10 m to 5 m example checks the bisection numbers directly.
- `greens-law` takes c_g² = g h as a premise. A `TanhModel` gives only c_g² ≤ c² ≤ g h (`OceanWaves.Dispersion`).
- The opposing-current example meets the Doppler relation, but its σ, k and c_g are not a solved dispersion relation.
