{-# OPTIONS --safe --without-K #-}

-- The kernels of one model step of `OceanWaves`, written in the language of `OceanTriton.Expr`,
-- and for each one a soundness theorem: its exact meaning is the `OceanWaves` kernel, for every
-- input. Most proofs are `refl`: the meaning unfolds to the same term. So every theorem that
-- `OceanWaves` proves about a kernel (conservation, positivity, the maximum principle) holds for
-- the meaning of the code that `OceanTriton.Emit` prints; three are restated at the end.
--
-- What this does not prove: that Triton computes the meaning. Triton works in float32, so its
-- results are rounded (AGENTS.md rule 7), and the printer in `OceanTriton.Emit` is trusted.
-- `ocean-triton/check.py` runs the printed kernels and compares them with the exact values that
-- `OceanTriton.Vectors` computes from the same terms.
module OceanTriton.Kernels where

open import Data.Fin using (#_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _≤?_)

open import Data.Vec using (Vec; []; _∷_)
open import Relation.Nullary using (Dec; yes; no; does)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong)
open import Data.Bool using (if_then_else_)

open import OceanWaves.Order using (_/₀_; lit; 2ℚ)
open import OceanWaves.Advection using (advect; CFL; advect-nonneg)
open import OceanWaves.ActionBalance using (transportRHS; advect-is-euler)
open import OceanWaves.Dispersion using (Medium; padeModel; padeT; pade; clamp; sigma2; groupSpeed)
open import OceanWaves.Sources
  using (WindParams; windRate; windRate-nonneg; DsParams; dsRate; Spectrum; Etot;
         linStep; eulerStep; limit; snl; sourceStep; sourceStep-nonneg)
open import OceanTriton.Expr

open WindParams using (cIn; rhoRatio; ustar)
open DsParams using (cDs; delta; alphaPM)

-- ---------------------------------------------------------------------------------------------
-- Propagation

-- One upwind step in flux form: N' i = N i + μ i N (i - 1) - μ (i + 1) N i, with N (-1) = b.
advectK : Kernel
advectK = record
  { name = "advect" ; na = 2 ; ns = 1
  ; arrays = "mu" ∷ "N" ∷ [] ; scalars = "b" ∷ [] ; shape = map
  ; body = at N 0 ⊕ at mu 0 ⊗ up N b ⊖ at mu 1 ⊗ at N 0
  ; doc = "one upwind step (OceanWaves.Advection.advect); mu has n + 1 faces" }
  where mu = # 0 ; N = # 1 ; b = # 0

advectK-sound : ∀ μ b N i → runMap advectK (store (μ ∷ N ∷ []) (b ∷ [])) i ≡ advect μ b N i
advectK-sound μ b N i = refl

-- The same step with the Courant number computed in the kernel, μ f = c_g f Δt / Δx.
advectCgK : Kernel
advectCgK = record
  { name = "advect_cg" ; na = 2 ; ns = 3
  ; arrays = "cg" ∷ "N" ∷ [] ; scalars = "b" ∷ "dt" ∷ "dx" ∷ [] ; shape = map
  ; body = at N 0 ⊕ μ 0 ⊗ up N b ⊖ μ 1 ⊗ at N 0
  ; doc = "one upwind step with mu = cg dt / dx; cg has n + 1 faces" }
  where
  cg = # 0 ; N = # 1 ; b = # 0 ; dt = # 1 ; dx = # 2
  μ : ℕ → Expr 2 3
  μ k = at cg k ⊗ par dt ⊘ par dx

advectCgK-sound : ∀ cg b Δt Δx N i →
  runMap advectCgK (store (cg ∷ N ∷ []) (b ∷ Δt ∷ Δx ∷ [])) i ≡ advect (λ f → cg f * Δt /₀ Δx) b N i
advectCgK-sound cg b Δt Δx N i = refl

-- So the kernel is one forward-Euler step of the semi-discrete transport equation.
advectCgK-euler : ∀ cg b Δt Δx N i →
  runMap advectCgK (store (cg ∷ N ∷ []) (b ∷ Δt ∷ Δx ∷ [])) i ≡ N i + Δt * transportRHS Δx cg b N i
advectCgK-euler = advect-is-euler′
  where
  advect-is-euler′ : ∀ cg b Δt Δx N i → advect (λ f → cg f * Δt /₀ Δx) b N i ≡ N i + Δt * transportRHS Δx cg b N i
  advect-is-euler′ cg b Δt Δx N i = advect-is-euler Δt Δx cg b N i

-- ---------------------------------------------------------------------------------------------
-- Dispersion, with the clamped Padé tanh of `OceanWaves.Dispersion`

-- T x = pade x when x ≤ 3, else 1.
tanhE : ∀ {na ns} → Expr na ns → Expr na ns
tanhE x = ifLe x (con (lit 3)) (x ⊗ (con (lit 27) ⊕ x ⊗ x) ⊘ (con (lit 27) ⊕ con (lit 9) ⊗ (x ⊗ x))) (con 1ℚ)

private
  clamp≡ : ∀ x (d : Dec (x ≤ lit 3)) → (if does d then pade x else 1ℚ) ≡ clamp x d
  clamp≡ x (yes _) = refl
  clamp≡ x (no  _) = refl

tanhE-sound : ∀ {na ns} (x : Expr na ns) st i → eval (tanhE x) st i ≡ padeT (eval x st i)
tanhE-sound x st i = clamp≡ (eval x st i) (eval x st i ≤? lit 3)

-- σ²(k) = g k T(k h).
sigma2K : Kernel
sigma2K = record
  { name = "sigma2" ; na = 1 ; ns = 2
  ; arrays = "k" ∷ [] ; scalars = "g" ∷ "h" ∷ [] ; shape = map
  ; body = par g ⊗ at k 0 ⊗ tanhE (at k 0 ⊗ par h)
  ; doc = "the squared frequency g k T(k h) (OceanWaves.Dispersion.sigma2, Pade tanh)" }
  where k = # 0 ; g = # 0 ; h = # 1

sigma2K-sound : ∀ W k i →
  runMap sigma2K (store (k ∷ []) (Medium.g W ∷ Medium.h W ∷ [])) i ≡ sigma2 padeModel W (k i)
sigma2K-sound W k i =
  cong (λ t → Medium.g W * k i * t)
       (tanhE-sound (at (# 0) 0 ⊗ par (# 1)) (store (k ∷ []) (Medium.g W ∷ Medium.h W ∷ [])) i)

-- The group velocity c_g = n c, with n = ½ (1 + x (1 - T² x) / T x), x = k h, c = σ / k.
groupSpeedK : Kernel
groupSpeedK = record
  { name = "group_speed" ; na = 2 ; ns = 1
  ; arrays = "sigma" ∷ "k" ∷ [] ; scalars = "h" ∷ [] ; shape = map
  ; body = (con 1ℚ ⊕ x ⊗ (con 1ℚ ⊖ tanhE x ⊗ tanhE x) ⊘ tanhE x) ⊘ con 2ℚ ⊗ (at σ 0 ⊘ at k 0)
  ; doc = "the group velocity (OceanWaves.Dispersion.groupSpeed, Pade tanh)" }
  where
  σ = # 0 ; k = # 1 ; h = # 0
  x : Expr 2 1
  x = at k 0 ⊗ par h

groupSpeedK-sound : ∀ W σ k i →
  runMap groupSpeedK (store (σ ∷ k ∷ []) (Medium.h W ∷ [])) i ≡ groupSpeed padeModel W (σ i) (k i)
groupSpeedK-sound W σ k i =
  cong (λ t → (1ℚ + x * (1ℚ - t * t) /₀ t) /₀ 2ℚ * (σ i /₀ k i))
       (tanhE-sound (at (# 1) 0 ⊗ par (# 0)) (store (σ ∷ k ∷ []) (Medium.h W ∷ [])) i)
  where x = k i * Medium.h W

-- ---------------------------------------------------------------------------------------------
-- Source terms

-- Wind input β = max(0, c_in ρ_a/ρ_w (28 u* cos / c - 1)) σ.
windK : Kernel
windK = record
  { name = "wind_rate" ; na = 3 ; ns = 3
  ; arrays = "sigma" ∷ "c" ∷ "cos" ∷ [] ; scalars = "c_in" ∷ "rho_ratio" ∷ "ustar" ∷ [] ; shape = map
  ; body = max (con 0ℚ) (par cin ⊗ par rho ⊗ (con (lit 28) ⊗ par us ⊗ at cs 0 ⊘ at c 0 ⊖ con 1ℚ)) ⊗ at σ 0
  ; doc = "the wind input rate (OceanWaves.Sources.windRate)" }
  where σ = # 0 ; c = # 1 ; cs = # 2 ; cin = # 0 ; rho = # 1 ; us = # 2

windStore : WindParams → (σ c cs : ℕ → ℚ) → Store 3 3
windStore P σ c cs = store (σ ∷ c ∷ cs ∷ []) (cIn P ∷ rhoRatio P ∷ ustar P ∷ [])

windK-sound : ∀ P σ c cs i → runMap windK (windStore P σ c cs) i ≡ windRate P (σ i) (c i) (cs i)
windK-sound P σ c cs i = refl

-- The sums of the spectrum that whitecapping needs: E = Σ w σ N, Σ w E/σ and Σ w E/k.
etotK dsigK dkK : Kernel
etotK = record
  { name = "energy_total" ; na = 3 ; ns = 0
  ; arrays = "sigma" ∷ "N" ∷ "w" ∷ [] ; scalars = [] ; shape = reduce
  ; body = at (# 2) 0 ⊗ (at (# 0) 0 ⊗ at (# 1) 0)
  ; doc = "the total energy, the sum of w sigma N (OceanWaves.Sources.Etot)" }
dsigK = record
  { name = "energy_over_sigma" ; na = 3 ; ns = 0
  ; arrays = "sigma" ∷ "N" ∷ "w" ∷ [] ; scalars = [] ; shape = reduce
  ; body = at (# 2) 0 ⊗ (at (# 0) 0 ⊗ at (# 1) 0) ⊘ at (# 0) 0
  ; doc = "the sum of w E / sigma, the denominator of the mean frequency" }
dkK = record
  { name = "energy_over_k" ; na = 4 ; ns = 0
  ; arrays = "sigma" ∷ "N" ∷ "w" ∷ "k" ∷ [] ; scalars = [] ; shape = reduce
  ; body = at (# 2) 0 ⊗ (at (# 0) 0 ⊗ at (# 1) 0) ⊘ at (# 3) 0
  ; doc = "the sum of w E / k, the denominator of the mean wavenumber" }

spectrumStore3 : Spectrum → Store 3 0
spectrumStore3 S = store (Spectrum.σ S ∷ Spectrum.N S ∷ Spectrum.w S ∷ []) []

spectrumStore4 : Spectrum → Store 4 0
spectrumStore4 S = store (Spectrum.σ S ∷ Spectrum.N S ∷ Spectrum.w S ∷ Spectrum.k S ∷ []) []

etotK-sound : ∀ S → runReduce etotK (Spectrum.n S) (spectrumStore3 S) ≡ Etot S
etotK-sound S = refl

-- Whitecapping γ_i = c_ds σ̄ (α̂ / α_PM)² ((1 - δ) q + δ q²), q = k_i / k̄. The three sums come in
-- as scalars: E, Σ w E/σ and Σ w E/k.
dsK : Kernel
dsK = record
  { name = "ds_rate" ; na = 1 ; ns = 6
  ; arrays = "k" ∷ [] ; scalars = "c_ds" ∷ "delta" ∷ "alpha_pm" ∷ "e_tot" ∷ "e_sigma" ∷ "e_k" ∷ []
  ; shape = map
  ; body = par cds ⊗ σm ⊗ (r ⊗ r) ⊗ ((con 1ℚ ⊖ par δ) ⊗ q ⊕ par δ ⊗ (q ⊗ q))
  ; doc = "the whitecapping rate (OceanWaves.Sources.dsRate); the sums from the reduce kernels" }
  where
  cds = # 0 ; δ = # 1 ; α = # 2 ; e = # 3 ; es = # 4 ; ek = # 5
  σm km r q : Expr 1 6
  σm = par e ⊘ par es
  km = par e ⊘ par ek
  r  = par e ⊗ (km ⊗ km) ⊘ par α
  q  = at (# 0) 0 ⊘ km

dsStore : DsParams → Spectrum → Store 1 6
dsStore P S = store (Spectrum.k S ∷ [])
  (cDs P ∷ delta P ∷ alphaPM P
   ∷ runReduce etotK (Spectrum.n S) (spectrumStore3 S)
   ∷ runReduce dsigK (Spectrum.n S) (spectrumStore3 S)
   ∷ runReduce dkK (Spectrum.n S) (spectrumStore4 S) ∷ [])

-- The reduce kernels, then the map kernel, give the whitecapping rate of every bin.
dsK-sound : ∀ P S i → runMap dsK (dsStore P S) i ≡ dsRate P S i
dsK-sound P S i = refl

-- The semi-implicit linear step N* = N (1 + Δt β) / (1 + Δt γ).
linStepK : Kernel
linStepK = record
  { name = "lin_step" ; na = 3 ; ns = 1
  ; arrays = "beta" ∷ "gamma" ∷ "N" ∷ [] ; scalars = "dt" ∷ [] ; shape = map
  ; body = linE
  ; doc = "the semi-implicit source step (OceanWaves.Sources.linStep)" }
  where
  linE : Expr 3 1
  linE = at (# 2) 0 ⊗ (con 1ℚ ⊕ par (# 0) ⊗ at (# 0) 0) ⊘ (con 1ℚ ⊕ par (# 0) ⊗ at (# 1) 0)

linStepK-sound : ∀ Δt β γ N i →
  runMap linStepK (store (β ∷ γ ∷ N ∷ []) (Δt ∷ [])) i ≡ linStep Δt (β i) (γ i) (N i)
linStepK-sound Δt β γ N i = refl

-- The explicit step N + Δt (β - γ) N.
eulerK : Kernel
eulerK = record
  { name = "euler_step" ; na = 3 ; ns = 1
  ; arrays = "beta" ∷ "gamma" ∷ "N" ∷ [] ; scalars = "dt" ∷ [] ; shape = map
  ; body = at (# 2) 0 ⊕ par (# 0) ⊗ (at (# 0) 0 ⊖ at (# 1) 0) ⊗ at (# 2) 0
  ; doc = "the explicit source step (OceanWaves.Sources.eulerStep)" }

eulerK-sound : ∀ Δt β γ N i →
  runMap eulerK (store (β ∷ γ ∷ N ∷ []) (Δt ∷ [])) i ≡ eulerStep Δt (β i) (γ i) (N i)
eulerK-sound Δt β γ N i = refl

-- The full source step: N* plus the nonlinear increment Δt S_nl, clipped to [-N*, L].
sourceK : Kernel
sourceK = record
  { name = "source_step" ; na = 4 ; ns = 2
  ; arrays = "beta" ∷ "gamma" ∷ "N" ∷ "snl" ∷ [] ; scalars = "dt" ∷ "L" ∷ [] ; shape = map
  ; body = lin ⊕ max (neg lin) (min (par (# 1)) (par (# 0) ⊗ at (# 3) 0))
  ; doc = "the source step with the limiter (OceanWaves.Sources.sourceStep); snl is S_nl per bin" }
  where
  lin : Expr 4 2
  lin = at (# 2) 0 ⊗ (con 1ℚ ⊕ par (# 0) ⊗ at (# 0) 0) ⊘ (con 1ℚ ⊕ par (# 0) ⊗ at (# 1) 0)

sourceStore : ℚ → ℚ → (β γ : ℕ → ℚ) → ℕ → (d N : ℕ → ℚ) → Store 4 2
sourceStore Δt L β γ n d N = store (β ∷ γ ∷ N ∷ snl n d ∷ []) (Δt ∷ L ∷ [])

sourceK-sound : ∀ Δt L β γ n d N i →
  runMap sourceK (sourceStore Δt L β γ n d N) i ≡ sourceStep Δt L β γ n d N i
sourceK-sound Δt L β γ n d N i = refl

-- ---------------------------------------------------------------------------------------------
-- The theorems of OceanWaves, for the meaning of the printed kernels

-- Positivity of the upwind kernel under the CFL condition.
advectK-nonneg : ∀ n μ b N → CFL n μ → 0ℚ ≤ b → (∀ i → i ℕ.< n → 0ℚ ≤ N i) →
                 ∀ i → i ℕ.< n → 0ℚ ≤ runMap advectK (store (μ ∷ N ∷ []) (b ∷ [])) i
advectK-nonneg = advect-nonneg

-- The wind kernel never takes energy out.
windK-nonneg : ∀ P σ c cs i → 0ℚ ≤ σ i → 0ℚ ≤ runMap windK (windStore P σ c cs) i
windK-nonneg P σ c cs i hσ = windRate-nonneg P (c i) (cs i) hσ

-- The source kernel keeps N ≥ 0 for every Δt.
sourceK-nonneg : ∀ Δt L β γ n d N i → 0ℚ ≤ runMap sourceK (sourceStore Δt L β γ n d N) i
sourceK-nonneg = sourceStep-nonneg

-- Every kernel that `OceanTriton.Emit` prints.
kernels : Vec Kernel 12
kernels = advectK ∷ advectCgK ∷ sigma2K ∷ groupSpeedK ∷ windK ∷ etotK ∷ dsigK ∷ dkK ∷ dsK
        ∷ linStepK ∷ eulerK ∷ sourceK ∷ []
