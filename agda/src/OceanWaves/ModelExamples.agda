{-# OPTIONS --safe --without-K #-}

-- The examples of `ocean-waves/lean/OceanWaves/Examples.lean`, as checks that Agda computes:
-- `refl` on a closed term, `from-yes` on a decidable relation. Lean prints most of them with
-- `#eval` and compares with `Float`; Agda has no `Float` reference here, so each check states
-- the exact rational, or the sign that Lean's theorem states.
module OceanWaves.ModelExamples where

open import Data.Bool using (if_then_else_)
open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _≡ᵇ_)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; _≤_; _<_; _≤?_; _<?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanWaves.Order
open import OceanWaves.Sums
open import OceanWaves.Advection
open import OceanWaves.Dispersion
open import OceanWaves.Bisection
open import OceanWaves.Sources
open import OceanWaves.ActionBalance

-- ---------------------------------------------------------------------------------------------
-- 2. Dispersion: a 10 s wave in 10 m and in 1000 m of water

g : ℚ
g = ℤ+ 981 / 100

shallow deep : Medium
shallow = record { g = g ; h = lit 10   ; g-pos = from-yes (0ℚ <? g) ; h-pos = from-yes (0ℚ <? lit 10) }
deep    = record { g = g ; h = lit 1000 ; g-pos = from-yes (0ℚ <? g) ; h-pos = from-yes (0ℚ <? lit 1000) }

-- σ = 2π / 10 s, with π ≈ 355/113.
σ10 : ℚ
σ10 = lit 2 * (ℤ+ 355 / 113) /₀ lit 10

-- In 10 m of water the 10 s wave is slower than the shallow-water speed √(g h): c² ≤ g h, as
-- `phaseSpeed-sq-le` promises for every bisection count. Here 12 steps.
k-shallow : ℚ
k-shallow = waveNumber padeModel shallow σ10 12

shallow-speed : phaseSpeed padeModel shallow σ10 k-shallow * phaseSpeed padeModel shallow σ10 k-shallow ≤ g * lit 10
shallow-speed = from-yes (phaseSpeed padeModel shallow σ10 k-shallow * phaseSpeed padeModel shallow σ10 k-shallow ≤? g * lit 10)

-- ---------------------------------------------------------------------------------------------
-- 3. Advection: a bump goes round a periodic grid, and the total is kept

bump : ℕ → ℚ
bump i = if i ≡ᵇ 2 then lit 4 else if i ≡ᵇ 3 then lit 2 else 0ℚ

bump-total : sumTo 8 (advectPeriodicN 8 (ℤ+ 1 / 2) 4 bump) ≡ lit 6
bump-total = refl

-- Above CFL (μ = 3/2) one step already makes a negative value.
cfl-violation-negative : advectPeriodic 8 (ℤ+ 3 / 2) bump 2 < 0ℚ
cfl-violation-negative = from-yes (advectPeriodic 8 (ℤ+ 3 / 2) bump 2 <? 0ℚ)

-- ---------------------------------------------------------------------------------------------
-- 4. Sources: semi-implicit against explicit Euler on strong whitecapping

-- Δt γ = 3, no wind: the semi-implicit step damps to N/4; explicit Euler goes negative.
semi-implicit-damps : linStep 1ℚ 0ℚ (lit 3) 1ℚ ≡ ℤ+ 1 / 4
semi-implicit-damps = refl

euler-negative : eulerStep 1ℚ 0ℚ (lit 3) 1ℚ < 0ℚ
euler-negative = from-yes (eulerStep 1ℚ 0ℚ (lit 3) 1ℚ <? 0ℚ)

-- The wind growth rate β for u* = 0.5 m/s along the wind, in deep water. The 10 s wave
-- (c ≈ 15.6 m/s) outruns the wind: 28 u*/c < 1, so β = 0 (`windRate-zero`). A 5 s wave
-- (c ≈ 7.8 m/s) grows.
wind : WindParams
wind = record { cIn = ℤ+ 1 / 4 ; rhoRatio = ℤ+ 1225 / 1025000 ; ustar = ℤ+ 1 / 2
              ; cIn-nonneg = from-yes (0ℚ ≤? ℤ+ 1 / 4) ; rho-nonneg = from-yes (0ℚ ≤? ℤ+ 1225 / 1025000) }

σ5 : ℚ
σ5 = lit 2 * σ10

no-input-10s : windRate wind σ10 (phaseSpeed padeModel deep σ10 (waveNumber padeModel deep σ10 12)) 1ℚ ≡ 0ℚ
no-input-10s = refl

input-5s : 0ℚ < windRate wind σ5 (phaseSpeed padeModel deep σ5 (waveNumber padeModel deep σ5 12)) 1ℚ
input-5s = from-yes (0ℚ <? windRate wind σ5 (phaseSpeed padeModel deep σ5 (waveNumber padeModel deep σ5 12)) 1ℚ)

-- ---------------------------------------------------------------------------------------------
-- 5. Nonlinear transfer: DIA-like exchange amounts; action and energy are kept

spec5 : ℕ → ℚ
spec5 0 = 1ℚ
spec5 1 = lit 3
spec5 2 = lit 5
spec5 3 = lit 3
spec5 4 = lit 2
spec5 5 = 1ℚ
spec5 _ = 0ℚ

-- The exchange amount at centre c, with the DIA shape N_c² (N₋ + N₊) - 2 N₋ N_c N₊.
diaAmount : (ℕ → ℚ) → ℕ → ℚ
diaAmount N c = (N c * N c * (N (c ∸ 1) + N (suc c)) - lit 2 * N (c ∸ 1) * N c * N (suc c)) /₀ lit 100

snl-action : sumTo 6 (snl 6 (diaAmount spec5)) ≡ 0ℚ
snl-action = refl

-- On the uniform grid σ_j = 1 + j/10 the energy is kept too.
snl-energy : sumTo 6 (λ j → (1ℚ + lit j /₀ lit 10) * snl 6 (diaAmount spec5) j) ≡ 0ℚ
snl-energy = refl

-- ---------------------------------------------------------------------------------------------
-- 6. One full model step: 6 cells, 4 frequencies, 10 m of depth

-- A DIA-shaped exchange that reads only the bins below nb.
diaLocal : ℕ → (ℕ → ℚ) → ℕ → ℚ
diaLocal nb N c = if suc c ℕ.<ᵇ nb then diaAmount N c /₀ lit 10 else 0ℚ

cfg : StepConfig
cfg = record
  { M = padeModel ; W = shallow ; nx = 6 ; nb = 4
  ; σ = λ j → (lit 2 + lit j) /₀ lit 5
  ; Δt = lit 100 ; Δx = lit 1000 ; iters = 12 ; L = 1ℚ
  ; β = λ _ _ → ℤ+ 1 / 1000 ; γ = λ _ _ → ℤ+ 1 / 2000 ; d = diaLocal 4 }

F0 : ℕ → ℕ → ℚ
F0 x j = if x ≡ᵇ 1 then lit 4 - lit j else 0ℚ

-- The configuration meets the depth-based CFL condition, so every theorem of
-- `ActionBalance` applies to it.
cfg-valid : Valid cfg
cfg-valid = record
  { σ-nonneg  = λ j → div-nonneg (+-nonneg (from-yes (0ℚ ≤? lit 2)) (lit-nonneg j)) (from-yes (0ℚ ≤? lit 5))
  ; Δt-nonneg = from-yes (0ℚ ≤? lit 100)
  ; Δx-pos    = from-yes (0ℚ <? lit 1000)
  ; cfl       = from-yes (g * lit 10 * (lit 100 * lit 100) ≤? lit 1000 * lit 1000)
  ; nx-pos    = ℕ.s≤s ℕ.z≤n
  }
  where
  lit-nonneg : ∀ j → 0ℚ ≤ lit j
  lit-nonneg j = nonNegative⁻¹ (lit j) {{normalize-nonNeg j 1}}
    where open import Data.Rational.Properties using (nonNegative⁻¹; normalize-nonNeg)

-- Here wind input is larger than whitecapping, so the total action grows in one step.
cfg-grows : totalAction cfg F0 < totalAction cfg (stepFast cfg F0)
cfg-grows = from-yes (totalAction cfg F0 <? totalAction cfg (stepFast cfg F0))

-- Its source terms read only the 4 bins, so `stepFast` computes `step` (`stepFast-eq`).
cfg-local : Local cfg
cfg-local N N′ h = (λ _ → refl) , (λ _ → refl) , d-eq
  where
  open import Data.Nat using (s≤s; z≤n)
  0<4 = s≤s z≤n
  1<4 = s≤s (s≤s z≤n)
  2<4 = s≤s (s≤s (s≤s z≤n))
  3<4 = s≤s (s≤s (s≤s (s≤s z≤n)))
  d-eq : ∀ c → diaLocal 4 N c ≡ diaLocal 4 N′ c
  d-eq 0 rewrite h 0 0<4 | h 1 1<4 = refl
  d-eq 1 rewrite h 0 0<4 | h 1 1<4 | h 2 2<4 = refl
  d-eq 2 rewrite h 1 1<4 | h 2 2<4 | h 3 3<4 = refl
  d-eq (suc (suc (suc c))) = refl
