{-# OPTIONS --safe --without-K #-}

-- The max-to-sum ratio of the MS plot, R = max |x|ᵖ / Σ |x|ᵖ, over exact rationals.
--
-- `ms_ratio(x, p)` in `fat_tails.py` is the running ratio, and the paper quotes its last value
-- (`ms_final`). That last value is `msRatio p xs` of the whole sample. The share of the 4th moment
-- that the largest day gives (`share_of_4th_moment_top_day`, a4[top] / a4.sum() with a4 = x⁴) is
-- `msRatio 4`.
--
-- Taleb's reading, that R → 0 as n grows exactly when E|X|ᵖ is finite, is a law of large
-- numbers for a random sample. It is not proved here. What is proved holds for every finite
-- list: 1/n ≤ R ≤ 1, and R does not change when the sample is multiplied by c ≠ 0, so the
-- units of the returns do not matter.
module FatTails.MaxSum where

open import Data.List using (List; []; _∷_; map)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; ∣_∣; _≟_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; ∣p*q∣≡∣p∣*∣q∣; 0≤∣p∣; ∣p∣≡0⇒p≡0; *-zeroʳ;
         *-identityˡ; *-monoʳ-≤-nonNeg; _≤?_; _<?_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:*_; con)
open import Relation.Nullary using (Dec; yes; no)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import FatTails.Sample
open import OceanWaves.Order using (div-nonneg; *-pos)

-- aᵖ for a natural p.
pow : ℕ → ℚ → ℚ
pow zero    a = 1ℚ
pow (suc p) a = a * pow p a

absPow : ℕ → ℚ → ℚ
absPow p x = pow p ∣ x ∣

-- R = max |x|ᵖ / Σ |x|ᵖ (`ms_ratio(x, p)[-1]`).
msRatio : ℕ → List ℚ → ℚ
msRatio p xs = maxMap (absPow p) xs /₀ sumMap (absPow p) xs

-- The share of Σ x⁴ that the largest |x| gives (`share_of_4th_moment_top_day`).
topShare : List ℚ → ℚ
topShare = msRatio 4

-- ---------------------------------------------------------------------------------------------
-- Powers

pow-nonneg : ∀ p {a} → 0ℚ ≤ a → 0ℚ ≤ pow p a
pow-nonneg zero    h = from-yes (0ℚ ≤? 1ℚ)
pow-nonneg (suc p) h = *-nonneg h (pow-nonneg p h)

pow-pos : ∀ p {a} → 0ℚ < a → 0ℚ < pow p a
pow-pos zero    h = from-yes (0ℚ <? 1ℚ)
pow-pos (suc p) h = *-pos h (pow-pos p h)

pow-* : ∀ p a b → pow p (a * b) ≡ pow p a * pow p b
pow-* zero    a b = refl
pow-* (suc p) a b rewrite pow-* p a b =
  solve 4 (λ x y u v → (x :* y) :* (u :* v) := (x :* u) :* (y :* v)) refl a b (pow p a) (pow p b)

absPow-nonneg : ∀ p x → 0ℚ ≤ absPow p x
absPow-nonneg p x = pow-nonneg p (0≤∣p∣ x)

absPow-scale : ∀ p c x → absPow p (c * x) ≡ absPow p c * absPow p x
absPow-scale p c x = trans (cong (pow p) (∣p*q∣≡∣p∣*∣q∣ c x)) (pow-* p ∣ c ∣ ∣ x ∣)

-- ---------------------------------------------------------------------------------------------
-- Bounds

msRatio-nonneg : ∀ p xs → 0ℚ ≤ msRatio p xs
msRatio-nonneg p xs = div-nonneg (maxMap-nonneg (absPow p) xs) (sumMap-nonneg (absPow p) xs (absPow-nonneg p))

-- R ≤ 1: no single point is more than the whole sum.
msRatio-le-one : ∀ p xs → msRatio p xs ≤ 1ℚ
msRatio-le-one p xs = go (S ≟ 0ℚ)
  where
  M = maxMap (absPow p) xs
  S = sumMap (absPow p) xs
  go : Dec (S ≡ 0ℚ) → M /₀ S ≤ 1ℚ
  go (yes S≡0) = ≤-trans (≤-reflexive (trans (cong (λ t → M * inv₀ t) S≡0) (*-zeroʳ M)))
                         (from-yes (0ℚ ≤? 1ℚ))
  go (no S≢0) =
    div-le-of-le-mul (≤∧≢⇒< (sumMap-nonneg (absPow p) xs (absPow-nonneg p)) (λ eq → S≢0 (sym eq)))
      (≤-trans (maxMap-le-sumMap (absPow p) xs (absPow-nonneg p)) (≤-reflexive (sym (*-identityˡ S))))

-- n R ≥ 1 when some point is not zero: R is at least 1/n, its value when all |x| are equal.
msRatio-size-ge-one : ∀ p xs → 0ℚ < sumMap (absPow p) xs → 1ℚ ≤ size xs * msRatio p xs
msRatio-size-ge-one p xs 0<S =
  ≤-trans (≤-reflexive (sym (inv₀-inverse S (<⇒≢0 0<S))))
    (≤-trans (*-monoʳ-≤-nonNeg (inv₀ S) {{nonNegative (inv₀-nonneg (sumMap-nonneg (absPow p) xs (absPow-nonneg p)))}}
               (sumMap-le-size*maxMap (absPow p) xs))
             (≤-reflexive (solve 3 (λ n m i → (n :* m) :* i := n :* (m :* i)) refl (size xs) M (inv₀ S))))
  where
  M = maxMap (absPow p) xs
  S = sumMap (absPow p) xs

-- ---------------------------------------------------------------------------------------------
-- Scale invariance

-- R does not change when every point is multiplied by the same c ≠ 0 (percent or fraction,
-- dollars or yen).
msRatio-scale : ∀ p {c} xs → c ≢ 0ℚ → msRatio p (map (c *_) xs) ≡ msRatio p xs
msRatio-scale p {c} xs c≢0 =
  trans (cong₂ _/₀_ max′ sum′) (div-cancelˡ (maxMap (absPow p) xs) (sumMap (absPow p) xs) k≢0)
  where
  k = absPow p c
  0<∣c∣ : 0ℚ < ∣ c ∣
  0<∣c∣ = ≤∧≢⇒< (0≤∣p∣ c) (λ eq → c≢0 (∣p∣≡0⇒p≡0 c (sym eq)))
  k≢0 : k ≢ 0ℚ
  k≢0 = <⇒≢0 (pow-pos p 0<∣c∣)
  max′ : maxMap (absPow p) (map (c *_) xs) ≡ k * maxMap (absPow p) xs
  max′ = trans (maxMap-map (absPow p) (c *_) xs)
           (trans (maxMap-cong _ (λ x → k * absPow p x) xs (absPow-scale p c))
                  (maxMap-scale (absPow p) xs (absPow-nonneg p c)))
  sum′ : sumMap (absPow p) (map (c *_) xs) ≡ k * sumMap (absPow p) xs
  sum′ = trans (sumMap-map (absPow p) (c *_) xs)
           (trans (sumMap-cong _ (λ x → k * absPow p x) xs (absPow-scale p c))
                  (sumMap-scale k (absPow p) xs))
