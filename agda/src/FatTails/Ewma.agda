{-# OPTIONS --safe --without-K #-}

-- The RiskMetrics variance forecast (EWMA) and the devolatilised squared return, over exact
-- rationals.
--
-- `ewma_vol` in `fat_tails.py` runs var[t] = λ var[t-1] + (1 - λ) x[t-1]², with λ = 0.94 and
-- var[0] the variance of the first 250 days, and returns the square root of each var. `ewma l v xs`
-- here is the list of the variances, from v, with the forecast for the day after the last one at
-- the end (`sig.attrs["next"]` squared). ℚ has no square root, so the module works with
-- variances, and the devolatilised return z = x / σ enters as z² = x² / var (`zSq`).
module FatTails.Ewma where

open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Integer using (+_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _/_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; *-monoˡ-≤-nonNeg)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import FatTails.Sample
open import FatTails.Moments using (sq)
open import OceanWaves.Order using (≤⇒0≤-)

-- RiskMetrics' daily decay, 0.94.
riskMetricsλ : ℚ
riskMetricsλ = + 47 / 50

-- One update: λ v + (1 - λ) x².
ewmaStep : ℚ → ℚ → ℚ → ℚ
ewmaStep l v x = l * v + (1ℚ - l) * sq x

-- The variance forecasts from v over the returns xs, the next day's forecast last.
ewma : ℚ → ℚ → List ℚ → List ℚ
ewma l v []       = v ∷ []
ewma l v (x ∷ xs) = v ∷ ewma l (ewmaStep l v x) xs

-- The squared devolatilised return, z² = x² / var.
zSq : ℚ → ℚ → ℚ
zSq x var = sq x /₀ var

-- ---------------------------------------------------------------------------------------------

-- The step is a mean of v and x², weighted by λ and 1 - λ, so it stays between them.
private
  step-le : ∀ {l v x B} → 0ℚ ≤ l → l ≤ 1ℚ → v ≤ B → sq x ≤ B → ewmaStep l v x ≤ B
  step-le {l} {v} {x} {B} h0 h1 hv hx =
    ≤-trans (+-mono-≤ (*-monoˡ-≤-nonNeg l {{nonNegative h0}} hv)
                      (*-monoˡ-≤-nonNeg (1ℚ - l) {{nonNegative (≤⇒0≤- h1)}} hx))
            (≤-reflexive (solve 2 (λ l b → l :* b :+ (con 1ℚ :- l) :* b := b) refl l B))

  step-nonneg : ∀ {l v x} → 0ℚ ≤ l → l ≤ 1ℚ → 0ℚ ≤ v → 0ℚ ≤ ewmaStep l v x
  step-nonneg {l} {v} {x} h0 h1 hv =
    +-nonneg (*-nonneg h0 hv) (*-nonneg (≤⇒0≤- h1) (sq-nonneg x))

-- With 0 ≤ λ ≤ 1 and a start v ≥ 0, every forecast is a variance: not negative.
ewma-nonneg : ∀ {l} v xs → 0ℚ ≤ l → l ≤ 1ℚ → 0ℚ ≤ v → All (0ℚ ≤_) (ewma l v xs)
ewma-nonneg v []       h0 h1 hv = hv ∷ []
ewma-nonneg v (x ∷ xs) h0 h1 hv = hv ∷ ewma-nonneg _ xs h0 h1 (step-nonneg {x = x} h0 h1 hv)

-- No forecast is above the larger of the start and the largest squared return.
ewma-le : ∀ {l B} v xs → 0ℚ ≤ l → l ≤ 1ℚ → v ≤ B → All (λ x → sq x ≤ B) xs → All (_≤ B) (ewma l v xs)
ewma-le v []       h0 h1 hv []         = hv ∷ []
ewma-le v (x ∷ xs) h0 h1 hv (hx ∷ hxs) = hv ∷ ewma-le _ xs h0 h1 (step-le {x = x} h0 h1 hv hx) hxs

-- Returns in other units (c x) give forecasts c² var, from a start c² v.
ewma-scale : ∀ l c v xs → ewma l (sq c * v) (map (c *_) xs) ≡ map (sq c *_) (ewma l v xs)
ewma-scale l c v []       = refl
ewma-scale l c v (x ∷ xs) =
  cong (sq c * v ∷_)
    (trans (cong (λ t → ewma l t (map (c *_) xs))
                 (solve 4 (λ l c v x → l :* (c :* c :* v) :+ (con 1ℚ :- l) :* ((c :* x) :* (c :* x))
                                      := c :* c :* (l :* v :+ (con 1ℚ :- l) :* (x :* x))) refl l c v x))
           (ewma-scale l c (ewmaStep l v x) xs))

-- So z² = x² / var does not depend on the units: (c x)² / (c² var) = x² / var for c ≠ 0.
zSq-scale : ∀ {c} x var → c ≢ 0ℚ → zSq (c * x) (sq c * var) ≡ zSq x var
zSq-scale {c} x var c≢0 =
  trans (cong (_/₀ (sq c * var)) (solve 2 (λ c x → (c :* x) :* (c :* x) := (c :* c) :* (x :* x)) refl c x))
        (div-cancelˡ (sq x) var (*≢0 c≢0 c≢0))
