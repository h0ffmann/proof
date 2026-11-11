{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- Decision rules
--
-- Each rule takes the model's per-arm estimates est : Arm K → Estimate
-- and returns a probability for every arm.
--
-- * greedy:        argmax of the mean (pure exploitation).
-- * ucb β:         argmax of mean + β * width (optimism under
--                  uncertainty). With a Bayesian linear model it is LinUCB.
-- * epsGreedy ε:   with probability ε a uniform arm, else the greedy arm.
-- * thompsonArm:   greedy on means sampled from the posterior. The sample
--                  is the model's job; the rule is the argmax of it.
------------------------------------------------------------------------

module ContextualBandit.Policies where

open import Data.Bool.Base using (if_then_else_)
open import Data.Fin.Properties using (_≟_)
open import Data.List.Base using (List; tabulate; foldr)
open import Data.Nat.Base using (ℕ; NonZero)
open import Data.Product.Base using (_×_)
open import Data.Rational.Base using (ℚ; 0ℚ; 1ℚ; _+_; _*_; _-_; _≤_)
open import Relation.Binary.PropositionalEquality using (_≡_)
open import Relation.Nullary.Decidable.Core using (does)

open import ContextualBandit.Interface
open import ContextualBandit.Argmax using (argmax)

-- Point mass on one arm.
point : ∀ {K} → Arm K → Decision K
point b a = if does (a ≟ b) then 1ℚ else 0ℚ

-- Uniform over all K arms.
uniform : (K : ℕ) → Decision K
uniform K _ = invK K

-- Mixture w * d₁ + (1 - w) * d₂.
mix : ∀ {K} → ℚ → Decision K → Decision K → Decision K
mix w d₁ d₂ a = w * d₁ a + (1ℚ - w) * d₂ a

-- UCB score of an estimate.
ucbScore : ℚ → Estimate → ℚ
ucbScore β e = mean e + β * width e

module _ {K : ℕ} {{_ : NonZero K}} where

  greedyArm : (Arm K → Estimate) → Arm K
  greedyArm est = argmax (λ a → mean (est a))

  ucbArm : ℚ → (Arm K → Estimate) → Arm K
  ucbArm β est = argmax (λ a → ucbScore β (est a))

  -- Thompson sampling: the argmax of one sampled mean per arm.
  thompsonArm : (Arm K → ℚ) → Arm K
  thompsonArm sample = argmax sample

  greedy : DecisionRule K
  greedy est = point (greedyArm est)

  ucb : ℚ → DecisionRule K
  ucb β est = point (ucbArm β est)

  epsGreedy : ℚ → DecisionRule K
  epsGreedy ε est = mix ε (uniform K) (point (greedyArm est))

-- The sum of a list of rationals.
sumℚ : List ℚ → ℚ
sumℚ = foldr _+_ 0ℚ

-- Total probability mass of a decision: the sum over the arms 0, ..., K-1.
-- tabulate d is the list d 0 ∷ d 1 ∷ ... (the Lean original maps d over
-- List.finRange K; it is the same list).
mass : ∀ {K} → Decision K → ℚ
mass d = sumℚ (tabulate d)

-- A decision is a valid probability distribution.
Valid : ∀ {K} → Decision K → Set
Valid d = (∀ a → 0ℚ ≤ d a) × mass d ≡ 1ℚ
