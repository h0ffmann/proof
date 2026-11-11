{-# OPTIONS --safe --without-K #-}

-- The baselines of `tv-audience/python/experiment.py`, for one channel and slot. A series is the
-- audience of day t, `s : ℕ → ℚ`. The seasonal naive forecast for day t is the audience of the
-- same channel and slot 7 days before (`np.exp(te.lag7)`). The four-week level is the mean of
-- the lags 7, 14, 21 and 28 (`lag_mean`); XGBoost and the MLP predict the change from it.
--
-- The theorems say that the forecasts read no day of the last 7 (`HORIZON = 7`, so a forecast
-- made 7 days ahead uses only what was known), that the naive forecast is exact on a weekly
-- series, and that the four-week level stays between the smallest and the largest lag.
--
-- The Python takes `lag_mean` over log audiences and forecasts `exp(lag_mean + f(x))`. ℚ has no
-- logarithm and no exponential, so here the level is the mean of whatever the series holds.
module TvAudience.Baselines where

open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _≤_)
  renaming (_+_ to _+ℕ_)
open import Data.Nat.Properties as ℕP
  using (m∸n+n≡m; m+n∸n≡m; m∸n≤m; +-monoʳ-≤; ≤-trans; ≤-reflexive)
open import Data.Rational as ℚ using (ℚ; _+_; _*_; _/_)
open import Data.Integer using (+_)
open import Data.Rational.Properties as ℚP
  using (+-mono-≤; *-monoʳ-≤-nonNeg)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:*_; con)
open import Relation.Nullary.Decidable using (from-yes)
open import Data.Product using (_×_; _,_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂; subst)

-- The forecast horizon, in days.
horizon : ℕ
horizon = 7

Series : Set
Series = ℕ → ℚ

-- The value k days before t. Before day k the series starts at day 0; the experiment drops the
-- rows whose lags do not exist (`df.date >= TRAIN_START`, 35 days after the start).
lag : ℕ → Series → ℕ → ℚ
lag k s t = s (t ∸ k)

seasonalNaive : Series → ℕ → ℚ
seasonalNaive = lag 7

quarter : ℚ
quarter = + 1 / 4

lagMean : Series → ℕ → ℚ
lagMean s t = (lag 7 s t + lag 14 s t + lag 21 s t + lag 28 s t) * quarter

-- ---------------------------------------------------------------------------------------------
-- No look at the last 7 days

-- Two series that agree up to day t - 7 give the same forecast for day t.
AgreeUpTo : ℕ → Series → Series → Set
AgreeUpTo t s s′ = ∀ u → u +ℕ horizon ≤ t → s u ≡ s′ u

-- The day t - k, for 7 ≤ k ≤ t, is known 7 days before t.
private
  known : ∀ {k t} → horizon ≤ k → k ≤ t → (t ∸ k) +ℕ horizon ≤ t
  known {k} {t} h7 hk = ≤-trans (+-monoʳ-≤ (t ∸ k) h7) (≤-reflexive (m∸n+n≡m hk))

lag-causal : ∀ {k t s s′} → horizon ≤ k → k ≤ t → AgreeUpTo t s s′ → lag k s t ≡ lag k s′ t
lag-causal {k} {t} h7 hk h = h (t ∸ k) (known h7 hk)

seasonalNaive-causal : ∀ {t s s′} → horizon ≤ t → AgreeUpTo t s s′ →
                       seasonalNaive s t ≡ seasonalNaive s′ t
seasonalNaive-causal h7 h = lag-causal ℕP.≤-refl h7 h

-- From day 28 on, the four-week level reads only days at least 7 old.
lagMean-causal : ∀ {t s s′} → 28 ≤ t → AgreeUpTo t s s′ → lagMean s t ≡ lagMean s′ t
lagMean-causal {t} h28 h =
  cong (_* quarter)
    (cong₂ _+_ (cong₂ _+_ (cong₂ _+_ (lag-causal (from-yes (7 ℕ.≤? 7)) (≤-trans (from-yes (7 ℕ.≤? 28)) h28) h)
                                    (lag-causal (from-yes (7 ℕ.≤? 14)) (≤-trans (from-yes (14 ℕ.≤? 28)) h28) h))
                          (lag-causal (from-yes (7 ℕ.≤? 21)) (≤-trans (from-yes (21 ℕ.≤? 28)) h28) h))
               (lag-causal (from-yes (7 ℕ.≤? 28)) h28 h))

-- ---------------------------------------------------------------------------------------------
-- Exact cases

-- A weekly series: the same audience every 7 days.
Weekly : Series → Set
Weekly s = ∀ u → s (u +ℕ 7) ≡ s u

seasonalNaive-weekly : ∀ s → Weekly s → ∀ u → seasonalNaive s (u +ℕ 7) ≡ s (u +ℕ 7)
seasonalNaive-weekly s w u = trans (cong s (m+n∸n≡m u 7)) (sym (w u))

-- The level of a flat series is that value.
lagMean-const : ∀ c t → lagMean (λ _ → c) t ≡ c
lagMean-const c t = solve 1 (λ x → (x :+ x :+ x :+ x) :* con quarter := x) refl c

-- ---------------------------------------------------------------------------------------------
-- Bounds

-- When every lag is between lo and hi, the level is between them too.
lagMean-between : ∀ {lo hi} s t →
  (∀ k → lo ℚ.≤ lag k s t × lag k s t ℚ.≤ hi) → lo ℚ.≤ lagMean s t × lagMean s t ℚ.≤ hi
lagMean-between {lo} {hi} s t h =
  subst (ℚ._≤ lagMean s t) (solve 1 (λ x → (x :+ x :+ x :+ x) :* con quarter := x) refl lo)
        (*-monoʳ-≤-nonNeg quarter {{nonNegative (from-yes (ℚ.0ℚ ℚP.≤? quarter))}}
          (+-mono-≤ (+-mono-≤ (+-mono-≤ (proj₁ (h 7)) (proj₁ (h 14))) (proj₁ (h 21))) (proj₁ (h 28))))
  , subst (lagMean s t ℚ.≤_) (solve 1 (λ x → (x :+ x :+ x :+ x) :* con quarter := x) refl hi)
        (*-monoʳ-≤-nonNeg quarter {{nonNegative (from-yes (ℚ.0ℚ ℚP.≤? quarter))}}
          (+-mono-≤ (+-mono-≤ (+-mono-≤ (proj₂ (h 7)) (proj₂ (h 14))) (proj₂ (h 21))) (proj₂ (h 28))))
  where
  open import Data.Product using (proj₁; proj₂)
