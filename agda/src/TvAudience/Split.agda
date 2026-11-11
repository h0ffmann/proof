{-# OPTIONS --safe --without-K #-}

-- The train/test split of `tv-audience/python/experiment.py`: rows dated before the cut
-- (`TEST_START`, 1 January 2026) train the models, and rows dated on or after it test them
-- (`df[df.date < TEST_START]`, `df[df.date >= TEST_START]`). A date is a day number.
--
-- The theorems: the two parts hold every row once (their lengths add up), every training date is
-- before the cut, every test date is on or after it, so every training date is before every test
-- date: no test row trains a model. Each test forecast still reads audiences of the test period
-- that are at least 7 days old (`TvAudience.Baselines`): the test is a rolling 7-day backtest.
module TvAudience.Split where

open import Data.Bool using (true; false; if_then_else_)
open import Data.List using (List; []; _∷_; length)
open import Data.List.Relation.Unary.All using (All; []; _∷_; lookup)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.Nat using (ℕ; suc; _<_; _≤_; _<ᵇ_; _+_)
open import Data.Nat.Properties using (<ᵇ⇒<; <⇒<ᵇ; ≮⇒≥; <-≤-trans; +-suc)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; subst)

-- The rows whose date is before the cut, and the others.
train test : ℕ → List ℕ → List ℕ
train cut []       = []
train cut (d ∷ ds) = if d <ᵇ cut then d ∷ train cut ds else train cut ds
test  cut []       = []
test  cut (d ∷ ds) = if d <ᵇ cut then test cut ds else d ∷ test cut ds

split-length : ∀ cut ds → length (train cut ds) + length (test cut ds) ≡ length ds
split-length cut []       = refl
split-length cut (d ∷ ds) with d <ᵇ cut
... | true  = cong suc (split-length cut ds)
... | false = trans (+-suc (length (train cut ds)) (length (test cut ds))) (cong suc (split-length cut ds))

train-before : ∀ cut ds → All (_< cut) (train cut ds)
train-before cut []       = []
train-before cut (d ∷ ds) with d <ᵇ cut in eq
... | true  = <ᵇ⇒< d cut (subst Data.Bool.T (sym eq) _) ∷ train-before cut ds
... | false = train-before cut ds

test-after : ∀ cut ds → All (cut ≤_) (test cut ds)
test-after cut []       = []
test-after cut (d ∷ ds) with d <ᵇ cut in eq
... | true  = test-after cut ds
... | false = ≮⇒≥ (λ d<cut → subst Data.Bool.T eq (<⇒<ᵇ d<cut)) ∷ test-after cut ds

-- Every training date is before every test date, for any two lists of rows split at one cut.
train-before-test : ∀ cut ds es {d e} → d ∈ train cut ds → e ∈ test cut es → d < e
train-before-test cut ds es d∈ e∈ =
  <-≤-trans (lookup (train-before cut ds) d∈) (lookup (test-after cut es) e∈)
