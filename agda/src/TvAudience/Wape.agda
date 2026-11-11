{-# OPTIONS --safe --without-K #-}

-- The forecast errors of `tv-audience/python/experiment.py` over exact rationals: WAPE, the
-- score of every model in the paper (`wape(y, yhat)` = Σ |y - ŷ| / Σ |y|), and the mean absolute
-- and mean squared errors it relates to. A row is one channel-slot: (actual, forecast).
--
-- The theorems say what a reader of the results table may assume: WAPE is not negative, it is 0
-- for a perfect forecast, it does not change with the unit of the audience (millions or
-- thousands), a pooled WAPE is not above the worse of its two parts, and the paired difference
-- of a model against itself is 0 on every resample (the row "XGBoost + rivals" of the bootstrap).
module TvAudience.Wape where

open import Data.List using (List; []; _∷_; map; _++_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; ∣_∣; _≤_; _<_; _⊔_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; *-zeroʳ; *-zeroˡ; *-identityʳ; ∣p*q∣≡∣p∣*∣q∣; 0≤∣p∣;
         +-inverseʳ; p≤p⊔q; p≤q⊔p; *-monoʳ-≤-nonNeg; *-monoˡ-≤-nonNeg)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst; subst₂)

open import FatTails.Sample
  using (size; size-nonneg; size-map; inv₀; _/₀_; inv₀-inverse; inv₀-nonneg; div-cancelˡ;
         div-le-of-le-mul; +-nonneg; *-nonneg; sq-nonneg; inv₀-*; inv₀-unique)

-- A row: the actual audience and its forecast.
Row : Set
Row = ℚ × ℚ

actual forecast : Row → ℚ
actual   = proj₁
forecast = proj₂

absErr : Row → ℚ
absErr (y , ŷ) = ∣ y - ŷ ∣

sqErr : Row → ℚ
sqErr (y , ŷ) = (y - ŷ) * (y - ŷ)

-- Σ g over the rows.
sumRows : (Row → ℚ) → List Row → ℚ
sumRows g []       = 0ℚ
sumRows g (r ∷ rs) = g r + sumRows g rs

errSum actualSum : List Row → ℚ
errSum    = sumRows absErr
actualSum = sumRows (λ r → ∣ actual r ∣)

-- WAPE = Σ |y - ŷ| / Σ |y|; 0 when every actual is 0 (Lean's total division).
wape : List Row → ℚ
wape rs = errSum rs /₀ actualSum rs

mae mse : List Row → ℚ
mae rs = errSum rs /₀ size rs
mse rs = sumRows sqErr rs /₀ size rs

-- Every actual and forecast times c: a change of unit.
scale : ℚ → List Row → List Row
scale c = map (λ { (y , ŷ) → (c * y , c * ŷ) })

-- A forecast that equals the actual on every row.
perfect : List ℚ → List Row
perfect = map (λ y → (y , y))

-- ---------------------------------------------------------------------------------------------
-- Signs

sumRows-nonneg : ∀ g rs → (∀ r → 0ℚ ≤ g r) → 0ℚ ≤ sumRows g rs
sumRows-nonneg g []       h = ≤-refl
sumRows-nonneg g (r ∷ rs) h = +-nonneg (h r) (sumRows-nonneg g rs h)

errSum-nonneg : ∀ rs → 0ℚ ≤ errSum rs
errSum-nonneg rs = sumRows-nonneg absErr rs (λ { (y , ŷ) → 0≤∣p∣ (y - ŷ) })

actualSum-nonneg : ∀ rs → 0ℚ ≤ actualSum rs
actualSum-nonneg rs = sumRows-nonneg (λ r → ∣ actual r ∣) rs (λ r → 0≤∣p∣ (actual r))

wape-nonneg : ∀ rs → 0ℚ ≤ wape rs
wape-nonneg rs = *-nonneg (errSum-nonneg rs) (inv₀-nonneg (actualSum-nonneg rs))

mae-nonneg : ∀ rs → 0ℚ ≤ mae rs
mae-nonneg rs = *-nonneg (errSum-nonneg rs) (inv₀-nonneg (size-nonneg rs))

mse-nonneg : ∀ rs → 0ℚ ≤ mse rs
mse-nonneg rs =
  *-nonneg (sumRows-nonneg sqErr rs (λ { (y , ŷ) → sq-nonneg (y - ŷ) })) (inv₀-nonneg (size-nonneg rs))

-- ---------------------------------------------------------------------------------------------
-- A perfect forecast

errSum-perfect : ∀ ys → errSum (perfect ys) ≡ 0ℚ
errSum-perfect []       = refl
errSum-perfect (y ∷ ys) = trans (cong₂ _+_ (cong ∣_∣ (+-inverseʳ y)) (errSum-perfect ys)) refl

wape-perfect : ∀ ys → wape (perfect ys) ≡ 0ℚ
wape-perfect ys = trans (cong (_* inv₀ (actualSum (perfect ys))) (errSum-perfect ys)) (*-zeroˡ (inv₀ (actualSum (perfect ys))))

mae-perfect : ∀ ys → mae (perfect ys) ≡ 0ℚ
mae-perfect ys = trans (cong (_* inv₀ (size (perfect ys))) (errSum-perfect ys)) (*-zeroˡ (inv₀ (size (perfect ys))))

-- ---------------------------------------------------------------------------------------------
-- A change of unit

errSum-scale : ∀ c rs → errSum (scale c rs) ≡ ∣ c ∣ * errSum rs
errSum-scale c []             = sym (*-zeroʳ ∣ c ∣)
errSum-scale c ((y , ŷ) ∷ rs) =
  trans (cong₂ _+_ (trans (cong ∣_∣ (solve 3 (λ k a b → k :* a :- k :* b := k :* (a :- b)) refl c y ŷ))
                          (∣p*q∣≡∣p∣*∣q∣ c (y - ŷ)))
                   (errSum-scale c rs))
        (solve 3 (λ k a s → k :* a :+ k :* s := k :* (a :+ s)) refl ∣ c ∣ ∣ y - ŷ ∣ (errSum rs))

actualSum-scale : ∀ c rs → actualSum (scale c rs) ≡ ∣ c ∣ * actualSum rs
actualSum-scale c []             = sym (*-zeroʳ ∣ c ∣)
actualSum-scale c ((y , ŷ) ∷ rs) =
  trans (cong₂ _+_ (∣p*q∣≡∣p∣*∣q∣ c y) (actualSum-scale c rs))
        (solve 3 (λ k a s → k :* a :+ k :* s := k :* (a :+ s)) refl ∣ c ∣ ∣ y ∣ (actualSum rs))

-- WAPE in thousands is WAPE in millions: no unit enters it.
wape-scale : ∀ {c} rs → ∣ c ∣ ≢ 0ℚ → wape (scale c rs) ≡ wape rs
wape-scale {c} rs hc =
  trans (cong₂ _/₀_ (errSum-scale c rs) (actualSum-scale c rs))
        (div-cancelˡ (errSum rs) (actualSum rs) hc)

-- ---------------------------------------------------------------------------------------------
-- Pooling

sumRows-++ : ∀ g rs qs → sumRows g (rs ++ qs) ≡ sumRows g rs + sumRows g qs
sumRows-++ g []       qs = solve 1 (λ s → s := con 0ℚ :+ s) refl (sumRows g qs)
sumRows-++ g (r ∷ rs) qs rewrite sumRows-++ g rs qs =
  solve 3 (λ a s t → a :+ (s :+ t) := (a :+ s) :+ t) refl (g r) (sumRows g rs) (sumRows g qs)

-- a / b ≤ m gives a ≤ m b, for b > 0.
private
  le-mul-of-div-le : ∀ {a b m} → 0ℚ < b → a /₀ b ≤ m → a ≤ m * b
  le-mul-of-div-le {a} {b} {m} hb h =
    subst (_≤ m * b) (div-mul-cancel a (λ eq → <⇒≢0 hb eq))
          (*-monoʳ-≤-nonNeg b {{nonNegative (<⇒≤′ hb)}} h)
    where
    open import Data.Rational.Properties using () renaming (<⇒≤ to <⇒≤′)
    open import FatTails.Sample using (<⇒≢0)
    open import OceanWaves.Order using (div-mul-cancel)

-- The WAPE of two parts pooled is at most the larger of the two WAPEs: the WAPE of all slots is
-- never worse than both its big-show and its other slots. Each part has an actual audience.
wape-++-le : ∀ rs qs → 0ℚ < actualSum rs → 0ℚ < actualSum qs →
             wape (rs ++ qs) ≤ wape rs ⊔ wape qs
wape-++-le rs qs hr hq =
  subst₂ (λ e d → e /₀ d ≤ m) (sym (sumRows-++ absErr rs qs)) (sym (sumRows-++ (λ r → ∣ actual r ∣) rs qs))
    (div-le-of-le-mul {errSum rs + errSum qs} {actualSum rs + actualSum qs} {m} (+-pos′ hr hq)
      (≤-trans (+-mono-≤ (le-mul-of-div-le {errSum rs} {actualSum rs} {m} hr (p≤p⊔q (wape rs) (wape qs)))
                         (le-mul-of-div-le {errSum qs} {actualSum qs} {m} hq (p≤q⊔p (wape rs) (wape qs))))
               (≤-reflexive (solve 3 (λ k a b → k :* a :+ k :* b := k :* (a :+ b)) refl
                               m (actualSum rs) (actualSum qs)))))
  where
  m = wape rs ⊔ wape qs
  open import Data.Rational.Properties using () renaming (+-mono-< to +-mono-<′)
  +-pos′ : ∀ {a b} → 0ℚ < a → 0ℚ < b → 0ℚ < a + b
  +-pos′ ha hb = +-mono-<′ ha hb

-- ---------------------------------------------------------------------------------------------
-- The paired difference and WAPE against MAE

-- The bootstrap compares each model with XGBoost + rivals on the same resampled rows. Against
-- itself the difference is 0 on every resample, so its interval is [0, 0].
wape-diff-self : ∀ rs → wape rs - wape rs ≡ 0ℚ
wape-diff-self rs = +-inverseʳ (wape rs)

private
  inv₀-inv₀ : ∀ {n} → n ≢ 0ℚ → inv₀ (inv₀ n) ≡ n
  inv₀-inv₀ {n} hn = inv₀-unique {inv₀ n} {n} (trans (solve 2 (λ i x → i :* x := x :* i) refl (inv₀ n) n) (inv₀-inverse n hn))

  inv₀≢0 : ∀ {n} → n ≢ 0ℚ → inv₀ n ≢ 0ℚ
  inv₀≢0 {n} hn eq = hn (trans (sym (inv₀-inv₀ hn)) (trans (cong inv₀ eq) refl))

-- WAPE is the MAE over the mean absolute actual: WAPE weighs every viewer the same, where a mean
-- of row errors (MAPE) would weigh every row the same.
wape-mae : ∀ rs → actualSum rs ≢ 0ℚ → size rs ≢ 0ℚ → wape rs ≡ mae rs /₀ (actualSum rs /₀ size rs)
wape-mae rs ha hn =
  sym (trans (cong (λ q → (errSum rs * inv₀ n) * q) (trans (inv₀-* ha (inv₀≢0 hn)) (cong (inv₀ a *_) (inv₀-inv₀ hn))))
        (trans (solve 4 (λ e i j m → (e :* i) :* (j :* m) := (e :* j) :* (m :* i)) refl
                  (errSum rs) (inv₀ n) (inv₀ a) n)
          (trans (cong (wape rs *_) (inv₀-inverse n hn)) (*-identityʳ (wape rs)))))
  where
  a = actualSum rs
  n = size rs
