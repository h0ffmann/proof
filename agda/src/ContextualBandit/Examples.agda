{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- A concrete model, checked by computation
--
-- tabular keeps, for each (context, arm), a reward sum and a pull count.
-- * mean  = sum / count (0 if the arm was never pulled)
-- * width = 1 / (count + 1), a rational stand-in for 1/√n: Data.Rational
--   has no square root. The Haskell port uses the real 1/√n.
--
-- Each statement below holds by refl: Agda computes the decision and
-- compares the exact rationals. These are the numbers of the Lean
-- original and of z3-scala/src/main/scala/bandit/domain/Examples.scala.
------------------------------------------------------------------------

module ContextualBandit.Examples where

open import Data.Bool.Base using (Bool; true; false; if_then_else_; _∧_)
open import Data.Fin.Base using (zero; suc)
open import Data.Fin.Properties using (_≟_)
open import Data.Integer.Base using (+_)
open import Data.List.Base using (List; []; _∷_; tabulate)
open import Data.Nat.Base using (ℕ; zero; suc)
open import Data.Product.Base using (_×_; _,_; proj₁; proj₂)
open import Data.Rational.Base using (ℚ; 0ℚ; 1ℚ; _+_; _*_; _/_; _≤_)
open import Data.Rational.Properties using (_≤?_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Nullary.Decidable.Core using (does)

open import ContextualBandit.Interface
open import ContextualBandit.Policies
open import ContextualBandit.Theorems using (epsGreedy-valid)

data Ctx : Set where
  morning evening : Ctx

_==_ : Ctx → Ctx → Bool
morning == morning = true
evening == evening = true
_       == _       = false

-- Belief: a function from (context, arm) to (reward sum, count).
Tab : ℕ → Set
Tab K = Ctx → Arm K → ℚ × ℕ

-- sum / count, as 0 when count = 0.
average : ℚ × ℕ → ℚ
average (s , zero)  = 0ℚ
average (s , suc n) = s * (+ 1 / suc n)

tabular : (K : ℕ) → RewardModel Ctx K (Tab K)
tabular K = record
  { prior    = λ _ _ → (0ℚ , 0)
  ; update   = λ b o c a →
      if (c == Obs.context o) ∧ does (a ≟ Obs.arm o)
      then (proj₁ (b c a) + Obs.reward o , suc (proj₂ (b c a)))
      else b c a
  ; estimate = λ b c a → estimate⟨ average (b c a) , + 1 / suc (proj₂ (b c a)) ⟩
  }

-- Three arms; in the morning arm 1 pays off, in the evening arm 2.
history : List (Obs Ctx 3)
history =
  obs morning zero 0ℚ ∷ obs morning (suc zero) 1ℚ ∷ obs morning (suc zero) 1ℚ ∷
  obs morning (suc (suc zero)) 0ℚ ∷
  obs evening zero 0ℚ ∷ obs evening (suc zero) 0ℚ ∷ obs evening (suc (suc zero)) 1ℚ ∷ []

show3 : Decision 3 → List ℚ
show3 = tabulate

ε : ℚ
ε = + 1 / 10

greedy-morning : show3 (policy (tabular 3) greedy history morning) ≡ 0ℚ ∷ 1ℚ ∷ 0ℚ ∷ []
greedy-morning = refl

greedy-evening : show3 (policy (tabular 3) greedy history evening) ≡ 0ℚ ∷ 0ℚ ∷ 1ℚ ∷ []
greedy-evening = refl

epsGreedy-morning :
  show3 (policy (tabular 3) (epsGreedy ε) history morning) ≡
    + 1 / 30 ∷ + 14 / 15 ∷ + 1 / 30 ∷ []
epsGreedy-morning = refl

-- UCB with β = 1 in the evening: arm 2 has the best mean and the same width.
ucb-evening : show3 (policy (tabular 3) (ucb 1ℚ) history evening) ≡ 0ℚ ∷ 0ℚ ∷ 1ℚ ∷ []
ucb-evening = refl

-- The general theorem, applied: this decision is a distribution too.
epsGreedy-morning-valid : Valid (policy (tabular 3) (epsGreedy ε) history morning)
epsGreedy-morning-valid =
  epsGreedy-valid ε (from-yes (0ℚ ≤? ε)) (from-yes (ε ≤? 1ℚ))
    (estimate (tabular 3) (posterior (tabular 3) history) morning)
