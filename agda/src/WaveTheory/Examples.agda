{-# OPTIONS --safe --without-K #-}

-- Concrete numbers for the wave-theory modules, checked by Agda: `refl` on a closed term,
-- `from-yes` on a decidable relation. Each number is an exact rational.
module WaveTheory.Examples where

open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Bool using (if_then_else_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; -_; _≤_; _<_; _≤?_; _<?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanWaves.Order
open import OceanWaves.Sums
open import OceanWaves.Dispersion
open import OceanWaves.Bisection
open import WaveTheory.Moments
open import WaveTheory.Shoaling
open import WaveTheory.Refraction
open import WaveTheory.DeepWater
open import WaveTheory.Propagation2D
open import WaveTheory.WaveAction

-- ---------------------------------------------------------------------------------------------
-- A four-bin spectrum

σs : ℕ → ℚ
σs 0 = ℤ+ 1 / 2
σs 1 = 1ℚ
σs 2 = ℤ+ 3 / 2
σs _ = lit 2

Es : ℕ → ℚ
Es 0 = 1ℚ
Es 1 = lit 4
Es 2 = lit 2
Es _ = 1ℚ

spec-m0 : m0 4 σs Es ≡ lit 8
spec-m0 = refl

spec-m1 : m1 4 σs Es ≡ ℤ+ 19 / 2
spec-m1 = refl

spec-m2 : m2 4 σs Es ≡ ℤ+ 51 / 4
spec-m2 = refl

-- H_s² = 16 m_0 = 128 (H_s ≈ 11.3 in the units of √E).
spec-hs2 : hs2 4 σs Es ≡ lit 128
spec-hs2 = refl

-- Cauchy-Schwarz with a margin: m_1² = 361/4 and m_0 m_2 = 102.
spec-width : m0 4 σs Es * m2 4 σs Es - m1 4 σs Es * m1 4 σs Es ≡ ℤ+ 47 / 4
spec-width = refl

-- The mean frequency 19/16 lies in the band [1/2, 2].
spec-mean : ℤ+ 1 / 2 ≤ m1 4 σs Es /₀ m0 4 σs Es
spec-mean = from-yes (ℤ+ 1 / 2 ≤? m1 4 σs Es /₀ m0 4 σs Es)

-- ---------------------------------------------------------------------------------------------
-- Breaking in 2 m of water with γ = 4/5

γ h₂ : ℚ
γ  = ℤ+ 4 / 5
h₂ = lit 2

-- The depth holds E_max = (γ h)² / 16 = 4/25; the sea has m_0 = 8, so it is scaled by 1/50.
cap-emax : emax γ h₂ ≡ ℤ+ 4 / 25
cap-emax = refl

cap-factor : breakFactor γ h₂ (m0 4 σs Es) ≡ ℤ+ 1 / 50
cap-factor = refl

-- After scaling, H_s² = (γ h)² = 64/25: H_s = γ h = 1.6 m.
cap-hs2 : hs2 4 σs (breakScale 4 γ h₂ σs Es) ≡ ℤ+ 64 / 25
cap-hs2 = refl

-- ---------------------------------------------------------------------------------------------
-- Shoaling and refraction

-- The group speed drops from 4 to 1: the energy rises four times.
shoal-four : shoal 1ℚ (lit 4) 1ℚ ≡ lit 4
shoal-four = refl

-- A ray at sin θ = 1/2 into water where it travels at half the speed: sin θ = 1/4.
snell-half : snell (ℤ+ 1 / 2) 2ℚ 1ℚ ≡ ℤ+ 1 / 4
snell-half = refl

-- A 10 s wave goes from 10 m to 5 m of water (12 bisection steps of the Padé model). The wave
-- number grows, the phase speed drops, and a ray at sin θ = 1/2 turns towards the normal.
private
  g = ℤ+ 981 / 100
  0<g = from-yes (0ℚ <? g)
  σ10 = lit 2 * (ℤ+ 355 / 113) /₀ lit 10

  W10 W5 : Medium
  W10 = medium g (lit 10) 0<g (from-yes (0ℚ <? lit 10))
  W5  = medium g (lit 5)  0<g (from-yes (0ℚ <? lit 5))

  k10 k5 : ℚ
  k10 = waveNumber padeModel W10 σ10 12
  k5  = waveNumber padeModel W5  σ10 12

shallower-k : k10 < k5
shallower-k = from-yes (k10 <? k5)

refracted : snell (ℤ+ 1 / 2) (σ10 /₀ k10) (σ10 /₀ k5) < ℤ+ 1 / 2
refracted = from-yes (snell (ℤ+ 1 / 2) (σ10 /₀ k10) (σ10 /₀ k5) <? ℤ+ 1 / 2)

-- ---------------------------------------------------------------------------------------------
-- Deep water: k h = 10 is past the Padé model's saturation at 3

private
  W100 : Medium
  W100 = medium g (lit 100) 0<g (from-yes (0ℚ <? lit 100))

deep-half : groupSpeed padeModel W100 σ10 (ℤ+ 1 / 10) ≡ phaseSpeed padeModel W100 σ10 (ℤ+ 1 / 10) /₀ 2ℚ
deep-half = groupSpeed-deep padeModel W100 σ10 {ℤ+ 1 / 10} (from-yes (lit 3 ≤? ℤ+ 1 / 10 * lit 100))

-- ---------------------------------------------------------------------------------------------
-- Two-dimensional propagation on a 3 × 3 periodic grid

-- A unit pulse in cell (0, 0).
pulse2 : Field
pulse2 x y = if (x ≡ᵇ 0) ∧ (y ≡ᵇ 0) then 1ℚ else 0ℚ
  where open import Data.Bool using (_∧_)

row : Field → ℕ → List ℚ
row F y = F 0 y ∷ F 1 y ∷ F 2 y ∷ []

half : ℚ
half = ℤ+ 1 / 2

quarter : ℚ
quarter = ℤ+ 1 / 4

-- With c_x = c_y = 1/2 the pulse spreads into a 2 × 2 square of quarters.
spread-rows : (row (step2D 3 3 half half pulse2) 0 ∷ row (step2D 3 3 half half pulse2) 1 ∷
               row (step2D 3 3 half half pulse2) 2 ∷ [])
            ≡ ((quarter ∷ quarter ∷ 0ℚ ∷ []) ∷ (quarter ∷ quarter ∷ 0ℚ ∷ []) ∷ (0ℚ ∷ 0ℚ ∷ 0ℚ ∷ []) ∷ [])
spread-rows = refl

-- With c_x = c_y = 1 the scheme is an exact shift: two steps carry the pulse to (2, 2).
diagonal-shift : run2D 3 3 1ℚ 1ℚ 2 pulse2 2 2 ≡ 1ℚ
diagonal-shift = refl

-- Two steps keep the total at 1, as `run2D-total` says for every run. (A field is a function,
-- so each further step computes the earlier ones again; the theorem covers the long runs.)
two-steps-total : total2D 2 2 (run2D 3 3 half half 2 pulse2) ≡ 1ℚ
two-steps-total = refl

-- ---------------------------------------------------------------------------------------------
-- Wave action on an opposing current

-- Station 1: c_g = 4, no current, σ = 1, E = 1. Station 2: an opposing current U = -2, σ = 3/2,
-- c_g = 3. The numbers meet the Doppler relation with k₂ = 1/4 (ω = 1 at both), but they are
-- not a solved dispersion relation.
doppler-pair : absolute (ℤ+ 3 / 2) (ℤ+ 1 / 4) (- lit 2) ≡ 1ℚ
doppler-pair = refl

-- The same action flux, 4, carries six times the energy at station 2.
action-kept : actionFlux (lit 4) 0ℚ 1ℚ 1ℚ ≡ actionFlux (lit 3) (- lit 2) (lit 6) (ℤ+ 3 / 2)
action-kept = refl

-- A current of -5 against waves with c_g = 4 blocks them.
blocking : actionFlux (lit 4) (- lit 5) 1ℚ 1ℚ < 0ℚ
blocking = from-yes (actionFlux (lit 4) (- lit 5) 1ℚ 1ℚ <? 0ℚ)
