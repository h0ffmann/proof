{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- Contextual bandit interface
--
-- The design splits a contextual bandit into two layers:
--
-- * a reward model (the probabilistic part): a belief B that is updated
--   with observations (context, arm, reward) and that gives, for every
--   context and arm, a predicted mean reward and an uncertainty width;
-- * a decision rule (the bandit part): a function that sees only the
--   model's estimates for the current context and returns a probability
--   for every arm.
--
-- A decision rule never sees the history. It sees it only through the
-- model. This boundary lets you change the model without a change to the
-- decision layer, and the reverse.
--
-- All values are exact rationals (Data.Rational), so the specification
-- runs: Examples.agda checks concrete decisions by refl. The names follow
-- z3-scala/src/main/scala/bandit/domain/Bandit.scala and
-- haskell/src/ContextualBandit.hs.
------------------------------------------------------------------------

module ContextualBandit.Interface where

open import Data.Fin.Base using (Fin)
open import Data.List.Base using (List; foldl)
open import Data.Nat.Base using (ℕ; zero; suc)
open import Data.Rational.Base using (ℚ; 0ℚ; 1ℚ; _+_; 1/_)
import Data.Rational.Base as ℚ
open import Data.Rational.Properties
  using (pos⇒nonZero; _<?_; ≤-refl; <⇒≤; nonNeg+nonNeg⇒nonNeg; pos+nonNeg⇒pos)
open import Relation.Nullary.Decidable using (from-yes)

-- Arms are Fin K: exactly K of them.
Arm : ℕ → Set
Arm = Fin

-- One round of interaction.
record Obs (C : Set) (K : ℕ) : Set where
  constructor obs
  field
    context : C
    arm     : Arm K
    reward  : ℚ

-- What a model reports about one (context, arm) pair.
record Estimate : Set where
  constructor estimate⟨_,_⟩
  field
    mean  : ℚ   -- predicted (posterior or predictive) mean reward
    width : ℚ   -- uncertainty: a standard deviation or a confidence radius, ≥ 0

open Estimate public

-- A probabilistic reward model with belief state B.
record RewardModel (C : Set) (K : ℕ) (B : Set) : Set where
  field
    prior    : B
    update   : B → Obs C K → B
    estimate : B → C → Arm K → Estimate

  -- The belief after a replay of a history (oldest first).
  posterior : List (Obs C K) → B
  posterior = foldl update prior

open RewardModel public

-- A randomised decision: a probability for every arm.
Decision : ℕ → Set
Decision K = Arm K → ℚ

-- A decision rule maps the model's per-arm estimates to a distribution
-- over arms. It does not get the context or the history.
DecisionRule : ℕ → Set
DecisionRule K = (Arm K → Estimate) → Decision K

-- A bandit agent is a model and a decision rule. Its policy is
-- history → context → distribution over arms.
policy : ∀ {C B : Set} {K : ℕ} → RewardModel C K B → DecisionRule K →
         List (Obs C K) → C → Decision K
policy m rule h c = rule (estimate m (posterior m h) c)

------------------------------------------------------------------------
-- The number K as a rational, and 1/K (0 when K = 0)

-- ofℕ n = 1 + 1 + ... + 1 (n times). It is defined by recursion so that
-- the sums of Theorems.agda go by induction on K with no cast lemma.
ofℕ : ℕ → ℚ
ofℕ zero    = 0ℚ
ofℕ (suc n) = 1ℚ + ofℕ n

0<1 : 0ℚ ℚ.< 1ℚ
0<1 = from-yes (0ℚ <? 1ℚ)

ofℕ-nonNeg : ∀ n → ℚ.NonNegative (ofℕ n)
ofℕ-nonNeg zero    = ℚ.nonNegative ≤-refl
ofℕ-nonNeg (suc n) =
  nonNeg+nonNeg⇒nonNeg 1ℚ {{ℚ.nonNegative (<⇒≤ 0<1)}} (ofℕ n) {{ofℕ-nonNeg n}}

ofℕ-pos : ∀ n → ℚ.Positive (ofℕ (suc n))
ofℕ-pos n = pos+nonNeg⇒pos 1ℚ {{ℚ.positive 0<1}} (ofℕ n) {{ofℕ-nonNeg n}}

-- 1/K, as 0 when K = 0 (the same convention as the Lean original).
invK : ℕ → ℚ
invK zero    = 0ℚ
invK (suc n) = (1/ ofℕ (suc n)) {{pos⇒nonZero (ofℕ (suc n)) {{ofℕ-pos n}}}}
