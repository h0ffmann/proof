{-# OPTIONS --safe --without-K #-}

-- Concrete checks of the upwind step, by `refl`: Agda computes the exact rationals.
-- Three cells on a periodic grid, all the action in cell 0, Courant number 1/2.
module OceanWaves.Examples where

open import Data.Integer using (+_)
open import Data.List using (List; []; _∷_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanWaves.Sums
open import OceanWaves.Advection

half : ℚ
half = + 1 / 2

-- N = (2, 0, 0).
pulse : ℕ → ℚ
pulse zero = + 2 / 1
pulse _    = 0ℚ

show3 : (ℕ → ℚ) → List ℚ
show3 f = f 0 ∷ f 1 ∷ f 2 ∷ []

-- One step moves half of cell 0 into cell 1.
one-step : show3 (advectPeriodic 3 half pulse) ≡ 1ℚ ∷ 1ℚ ∷ 0ℚ ∷ []
one-step = refl

-- Two steps: (1/2, 1, 1/2).
two-steps : show3 (advectPeriodicN 3 half 2 pulse) ≡ half ∷ 1ℚ ∷ half ∷ []
two-steps = refl

-- Five steps keep the total, 2, as `advectPeriodicN-sum` says for every k.
five-steps-sum : sumTo 3 (advectPeriodicN 3 half 5 pulse) ≡ + 2 / 1
five-steps-sum = refl
