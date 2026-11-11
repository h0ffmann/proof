{-# OPTIONS --safe --without-K #-}

-- Finite sums and order lemmas over exact rationals, for the ocean-wave kernels. Ported from
-- the part of `ocean-waves/lean/OceanWaves/RatLemmas.lean` that `Advection.agda` uses.
module OceanWaves.Sums where

open import Data.Nat using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; _+_; _-_; _*_; -_; _≤_)
open import Data.Rational.Properties
  using (nonNegative⁻¹; nonNeg*nonNeg⇒nonNeg; +-monoˡ-≤; +-inverseʳ; ≤-reflexive; ≤-trans)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym)

-- `sumTo n f` is f 0 + f 1 + ... + f (n - 1).
sumTo : ℕ → (ℕ → ℚ) → ℚ
sumTo zero    f = 0ℚ
sumTo (suc n) f = sumTo n f + f n

-- A telescoping sum keeps only its two ends.
sumTo-telescope : ∀ n (f : ℕ → ℚ) → sumTo n (λ i → f i - f (suc i)) ≡ f 0 - f n
sumTo-telescope zero    f = sym (+-inverseʳ (f 0))
sumTo-telescope (suc n) f
  rewrite sumTo-telescope n f =
    solve 3 (λ a b c → (a :- b) :+ (b :- c) := a :- c) refl (f 0) (f n) (f (suc n))

-- The product of two non-negative rationals is non-negative.
*-nonneg : ∀ {p q} → 0ℚ ≤ p → 0ℚ ≤ q → 0ℚ ≤ p * q
*-nonneg {p} {q} hp hq =
  nonNegative⁻¹ (p * q) {{nonNeg*nonNeg⇒nonNeg p {{nonNegative hp}} q {{nonNegative hq}}}}

-- p ≤ q gives 0 ≤ q - p.
≤⇒0≤- : ∀ {p q} → p ≤ q → 0ℚ ≤ q - p
≤⇒0≤- {p} {q} h = ≤-trans (≤-reflexive (sym (+-inverseʳ p))) (+-monoˡ-≤ (- p) h)
