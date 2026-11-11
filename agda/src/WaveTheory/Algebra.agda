{-# OPTIONS --safe --without-K #-}

-- Small lemmas over exact rationals that the wave-theory modules share: monotone sums,
-- cancellation of a positive factor in an equality, natural powers and the squared norm.
-- They add to `OceanWaves.Order` and `OceanWaves.Sums`, which they re-use.
module WaveTheory.Algebra where

open import Data.Nat as ℕ using (ℕ; zero; suc)
import Data.Nat.Properties as ℕP
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Base using (positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; ≤-antisym; +-mono-≤; *-cancelʳ-≤-pos)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; cong)

open import OceanWaves.Order
open import OceanWaves.Sums

-- A sum grows with its terms.
sumTo-mono : ∀ n (f g : ℕ → ℚ) → (∀ i → i ℕ.< n → f i ≤ g i) → sumTo n f ≤ sumTo n g
sumTo-mono zero    f g h = ≤-refl
sumTo-mono (suc n) f g h =
  +-mono-≤ (sumTo-mono n f g (λ i i<n → h i (ℕP.m<n⇒m<1+n i<n))) (h n (ℕP.n<1+n n))

-- A positive factor cancels from an equality.
*-cancelʳ-≡ : ∀ {a b c} → 0ℚ < c → a * c ≡ b * c → a ≡ b
*-cancelʳ-≡ {a} {b} {c} hc eq =
  ≤-antisym (*-cancelʳ-≤-pos c {{positive hc}} (≤-reflexive eq))
            (*-cancelʳ-≤-pos c {{positive hc}} (≤-reflexive (sym eq)))

-- x to a natural power.
pow : ℚ → ℕ → ℚ
pow x zero    = 1ℚ
pow x (suc p) = x * pow x p
