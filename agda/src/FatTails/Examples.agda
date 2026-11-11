{-# OPTIONS --safe --without-K #-}

-- Worked examples of the fat-tail metrics, checked by `refl`: Agda computes each exact rational.
--
-- The sample is eight daily returns in percent with one crash day, -12 %, among small moves.
-- The crash gives 3/5 of Σ|x|, 576/577 of Σ x⁴, and a kurtosis of 7418/1369 ≈ 5.42 where a
-- Gaussian gives 3. `tools/fat-tails/` computes every number here again in Haskell, with
-- `Rational`, and stops when one differs.
module FatTails.Examples where

open import Data.List using (List; []; _∷_; map; replicate)
open import Data.Nat using (ℕ)
open import Data.Integer using (+_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; -_; _/_; _≤_; _*_)
open import Data.Rational.Properties using (_≤?_)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import FatTails.Sample
open import FatTails.Moments
open import FatTails.MaxSum
open import FatTails.Kappa
open import FatTails.Tail
open import FatTails.Ewma

r : ℕ → ℚ
r n = + n / 1

returns : List ℚ
returns = r 1 ∷ - r 1 ∷ r 2 ∷ - r 1 ∷ r 1 ∷ - r 12 ∷ r 2 ∷ r 0 ∷ []

-- Blocks of two days and of four days, in order.
twoDays fourDays : List (List ℚ)
twoDays  = (r 1 ∷ - r 1 ∷ []) ∷ (r 2 ∷ - r 1 ∷ []) ∷ (r 1 ∷ - r 12 ∷ []) ∷ (r 2 ∷ r 0 ∷ []) ∷ []
fourDays = (r 1 ∷ - r 1 ∷ r 2 ∷ - r 1 ∷ []) ∷ (r 1 ∷ - r 12 ∷ r 2 ∷ r 0 ∷ []) ∷ []

-- ---------------------------------------------------------------------------------------------
-- Moments

mean-returns : mean returns ≡ - r 1
mean-returns = refl

mad-returns : mad returns ≡ + 11 / 4
mad-returns = refl

kurtosis-returns : kurtosis returns ≡ + 7418 / 1369
kurtosis-returns = refl

-- kurtosis ≥ 1 is sharp: two points of equal size give 1.
kurtosis-two-points : kurtosis (r 1 ∷ - r 1 ∷ []) ≡ 1ℚ
kurtosis-two-points = refl

-- The same returns in basis points (× 100) have the same kurtosis (`kurtosis-scale`).
kurtosis-bp : kurtosis (map (r 100 *_) returns) ≡ + 7418 / 1369
kurtosis-bp = refl

-- ---------------------------------------------------------------------------------------------
-- The MS plot

ms1 : msRatio 1 returns ≡ + 3 / 5
ms1 = refl

ms2 : msRatio 2 returns ≡ + 12 / 13
ms2 = refl

ms3 : msRatio 3 returns ≡ + 432 / 437
ms3 = refl

top-share : topShare returns ≡ + 576 / 577
top-share = refl

-- With all |x| equal, R is 1/n, the lower bound of `msRatio-size-ge-one`.
ms-flat : msRatio 4 (replicate 5 (r 3)) ≡ + 1 / 5
ms-flat = refl

-- ---------------------------------------------------------------------------------------------
-- κ's ratio

two-day-sums : blockSums twoDays ≡ r 0 ∷ r 1 ∷ - r 11 ∷ r 2 ∷ []
two-day-sums = refl

M2 : madOfSums twoDays ≡ + 9 / 2
M2 = refl

ratio-2 : kappaRatio twoDays ≡ + 18 / 11
ratio-2 = refl

ratio-4 : kappaRatio fourDays ≡ + 20 / 11
ratio-4 = refl

-- M(n) / M(1) ≤ n, as `madOfSums-le` says: 18/11 ≤ 2 and 20/11 ≤ 4.
ratio-2-le : kappaRatio twoDays ≤ r 2
ratio-2-le = from-yes (kappaRatio twoDays ≤? r 2)

ratio-4-le : kappaRatio fourDays ≤ r 4
ratio-4-le = from-yes (kappaRatio fourDays ≤? r 4)

-- ---------------------------------------------------------------------------------------------
-- Tails

-- Logarithms 3, 2 and 3/2 above a threshold 1: the gap is 7/6, so α = 6/7.
hill-gap : hillGap (r 3 ∷ r 2 ∷ + 3 / 2 ∷ []) (r 1) ≡ + 7 / 6
hill-gap = refl

hill-alpha : hillAlpha (r 3 ∷ r 2 ∷ + 3 / 2 ∷ []) (r 1) ≡ + 6 / 7
hill-alpha = refl

-- The paper's α = 3.75 gives ES = 15/11 VaR ≈ 1.36 VaR.
es-3·75 : esFactor (+ 15 / 4) ≡ + 15 / 11
es-3·75 = refl

-- Losses (−x) above 0 and above 5 percent.
beyond-0 : exceed 0ℚ (map -_ returns) ≡ 3
beyond-0 = refl

beyond-5 : exceed (r 5) (map -_ returns) ≡ 1
beyond-5 = refl

-- Three RiskMetrics updates from a variance of 4.
ewma-3 : ewma riskMetricsλ (r 4) (r 1 ∷ - r 3 ∷ r 2 ∷ [])
         ≡ r 4 ∷ + 191 / 50 ∷ + 10327 / 2500 ∷ + 515369 / 125000 ∷ []
ewma-3 = refl
