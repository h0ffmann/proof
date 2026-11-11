{-# OPTIONS --safe --without-K #-}

-- The mean absolute deviation and the kurtosis of a finite sample, over exact rationals, with
-- their invariances and the bound kurtosis ≥ 1.
--
-- `fat_tails.py` uses the same two measures. `mad_of_sums(x, 1)` is `np.mean(np.abs(x -
-- x.mean()))`, which is `mad` here. `stats.kurtosis(x, fisher=False)` is the biased (population)
-- kurtosis m₄ / m₂² with mᵣ = Σ (x - x̄)ʳ / n, which is n Σ d⁴ / (Σ d²)², `kurtosis` here.
--
-- These are statements about a list of numbers. They are not statements about a random variable
-- or its moments: "the 4th moment is infinite" (the MS plot, `MaxSum.agda`) needs a limit as n
-- grows, which this module does not state.
module FatTails.Moments where

open import Data.List using (List; []; _∷_; map)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_; ∣_∣)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; ∣p*q∣≡∣p∣*∣q∣; 0≤∣p∣; *-identityˡ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import FatTails.Sample
open import OceanWaves.Order using (div-nonneg; *-pos; ≤⇒0≤-)

sq : ℚ → ℚ
sq a = a * a

-- Σ (x - m)² and Σ (x - m)⁴ about a centre m.
devSq : ℚ → List ℚ → ℚ
devSq m xs = sumMap (λ x → sq (x - m)) xs

devQuad : ℚ → List ℚ → ℚ
devQuad m xs = sumMap (λ x → sq (sq (x - m))) xs

-- The mean absolute deviation, Σ |x - x̄| / n (`mad_of_sums(x, 1)`).
mad : List ℚ → ℚ
mad xs = sumMap (λ x → ∣ x - mean xs ∣) xs /₀ size xs

-- The kurtosis, n Σ d⁴ / (Σ d²)² with d = x - x̄ (`stats.kurtosis(x, fisher=False)`). It is 3
-- for a Gaussian in the limit, and 0 /₀ 0 = 0 for a sample with no spread.
kurtosis : List ℚ → ℚ
kurtosis xs = (size xs * devQuad (mean xs) xs) /₀ sq (devSq (mean xs) xs)

-- ---------------------------------------------------------------------------------------------
-- The mean absolute deviation

mad-nonneg : ∀ xs → 0ℚ ≤ mad xs
mad-nonneg xs = div-nonneg (sumMap-nonneg _ xs (λ x → 0≤∣p∣ (x - mean xs))) (size-nonneg xs)

-- MAD(c x) = |c| MAD(x).
mad-scale : ∀ c xs → mad (map (c *_) xs) ≡ ∣ c ∣ * mad xs
mad-scale c xs =
  trans (cong₂ _/₀_ inner (size-map (c *_) xs)) (div-scaleˡ ∣ c ∣ _ (size xs))
  where
  m = mean xs
  inner : sumMap (λ y → ∣ y - mean (map (c *_) xs) ∣) (map (c *_) xs)
        ≡ ∣ c ∣ * sumMap (λ x → ∣ x - m ∣) xs
  inner =
    trans (sumMap-map _ (c *_) xs)
      (trans (sumMap-cong _ (λ x → ∣ c ∣ * ∣ x - m ∣) xs
               (λ x → trans (cong (λ t → ∣ c * x - t ∣) (mean-scale c xs))
                        (trans (cong ∣_∣ (solve 3 (λ k y z → k :* y :- k :* z := k :* (y :- z)) refl c x m))
                               (∣p*q∣≡∣p∣*∣q∣ c (x - m)))))
             (sumMap-scale ∣ c ∣ (λ x → ∣ x - m ∣) xs))

-- MAD(x + a) = MAD(x).
mad-shift : ∀ a xs → mad (map (_+ a) xs) ≡ mad xs
mad-shift a []       = refl
mad-shift a (y ∷ ys) =
  cong₂ _/₀_
    (trans (sumMap-map (λ z → ∣ z - mean (map (_+ a) (y ∷ ys)) ∣) (_+ a) (y ∷ ys))
      (sumMap-cong _ _ (y ∷ ys)
        (λ x → trans (cong (λ t → ∣ (x + a) - t ∣) (mean-shift a y ys))
                 (cong ∣_∣ (solve 3 (λ z k t → (z :+ k) :- (t :+ k) := z :- t) refl x a (mean (y ∷ ys)))))))
    (size-map (_+ a) (y ∷ ys))

-- ---------------------------------------------------------------------------------------------
-- The kurtosis

private
  devSq-scale : ∀ c m xs → devSq (c * m) (map (c *_) xs) ≡ sq c * devSq m xs
  devSq-scale c m xs =
    trans (sumMap-map _ (c *_) xs)
      (trans (sumMap-cong _ (λ x → sq c * sq (x - m)) xs
               (λ x → solve 3 (λ k y z → (k :* y :- k :* z) :* (k :* y :- k :* z)
                                         := (k :* k) :* ((y :- z) :* (y :- z))) refl c x m))
             (sumMap-scale (sq c) _ xs))

  devQuad-scale : ∀ c m xs → devQuad (c * m) (map (c *_) xs) ≡ sq (sq c) * devQuad m xs
  devQuad-scale c m xs =
    trans (sumMap-map _ (c *_) xs)
      (trans (sumMap-cong _ (λ x → sq (sq c) * sq (sq (x - m))) xs
               (λ x → solve 3 (λ k y z →
                         ((k :* y :- k :* z) :* (k :* y :- k :* z)) :* ((k :* y :- k :* z) :* (k :* y :- k :* z))
                         := ((k :* k) :* (k :* k)) :* (((y :- z) :* (y :- z)) :* ((y :- z) :* (y :- z))))
                         refl c x m))
             (sumMap-scale (sq (sq c)) _ xs))

  shift-dev : ∀ a m x → (x + a) - (m + a) ≡ x - m
  shift-dev a m x = solve 3 (λ k t z → (z :+ k) :- (t :+ k) := z :- t) refl a m x

-- The kurtosis does not change when every point is multiplied by the same c ≠ 0.
kurtosis-scale : ∀ {c} xs → c ≢ 0ℚ → kurtosis (map (c *_) xs) ≡ kurtosis xs
kurtosis-scale {c} xs c≢0 =
  trans (cong₂ _/₀_ num den) (div-cancelˡ (n * Q) (sq S) c⁴≢0)
  where
  m = mean xs
  n = size xs
  Q = devQuad m xs
  S = devSq m xs
  k = sq (sq c)
  c⁴≢0 : k ≢ 0ℚ
  c⁴≢0 = *≢0 (*≢0 c≢0 c≢0) (*≢0 c≢0 c≢0)
  num : size (map (c *_) xs) * devQuad (mean (map (c *_) xs)) (map (c *_) xs) ≡ k * (n * Q)
  num = trans (cong₂ (λ a b → a * devQuad b (map (c *_) xs)) (size-map (c *_) xs) (mean-scale c xs))
          (trans (cong (n *_) (devQuad-scale c m xs))
                 (solve 3 (λ a b d → a :* (b :* d) := b :* (a :* d)) refl n k Q))
  den : sq (devSq (mean (map (c *_) xs)) (map (c *_) xs)) ≡ k * sq S
  den = trans (cong (λ t → sq (devSq t (map (c *_) xs))) (mean-scale c xs))
          (trans (cong sq (devSq-scale c m xs))
                 (solve 2 (λ a b → (a :* a :* b) :* (a :* a :* b) := ((a :* a) :* (a :* a)) :* (b :* b)) refl c S))

-- The kurtosis does not change when the same a is added to every point.
kurtosis-shift : ∀ a xs → kurtosis (map (_+ a) xs) ≡ kurtosis xs
kurtosis-shift a []       = refl
kurtosis-shift a (y ∷ ys) =
  cong₂ _/₀_
    (cong₂ _*_ (size-map (_+ a) xs)
      (trans (sumMap-map (λ z → sq (sq (z - m′))) (_+ a) xs)
        (sumMap-cong _ _ xs (λ x → trans (cong (λ t → sq (sq ((x + a) - t))) (mean-shift a y ys))
                                          (cong (λ t → sq (sq t)) (shift-dev a m x))))))
    (cong sq (trans (sumMap-map (λ z → sq (z - m′)) (_+ a) xs)
      (sumMap-cong _ _ xs (λ x → trans (cong (λ t → sq ((x + a) - t)) (mean-shift a y ys))
                                         (cong sq (shift-dev a m x))))))
  where
  xs = y ∷ ys
  m = mean xs
  m′ = mean (map (_+ a) xs)

-- ---------------------------------------------------------------------------------------------
-- kurtosis ≥ 1

-- Σ (a - f y)² = n a² - 2 a Σ f + Σ f².
cross : ∀ a (f : ℚ → ℚ) xs →
        sumMap (λ y → sq (a - f y)) xs ≡ size xs * sq a - (a * sumMap f xs + a * sumMap f xs) + sumMap (λ y → sq (f y)) xs
cross a f []       = solve 1 (λ x → con 0ℚ := con 0ℚ :* (x :* x) :- (x :* con 0ℚ :+ x :* con 0ℚ) :+ con 0ℚ) refl a
cross a f (x ∷ xs) rewrite cross a f xs =
  solve 5 (λ a b n s q → (a :- b) :* (a :- b) :+ (n :* (a :* a) :- (a :* s :+ a :* s) :+ q)
                       := (con 1ℚ :+ n) :* (a :* a) :- (a :* (b :+ s) :+ a :* (b :+ s)) :+ (b :* b :+ q))
    refl a (f x) (size xs) (sumMap f xs) (sumMap (λ y → sq (f y)) xs)

-- The Cauchy–Schwarz inequality for a finite sum: (Σ f)² ≤ n Σ f².
cauchy-schwarz : ∀ (f : ℚ → ℚ) xs → sq (sumMap f xs) ≤ size xs * sumMap (λ y → sq (f y)) xs
cauchy-schwarz f []       = ≤-refl
cauchy-schwarz f (x ∷ xs) =
  by-diff ((n * Q - sq S) + sumMap (λ y → sq (a - f y)) xs)
    (trans (solve 4 (λ a n s q → (con 1ℚ :+ n) :* (a :* a :+ q) :- (a :+ s) :* (a :+ s)
                               := (n :* q :- s :* s) :+ (n :* (a :* a) :- (a :* s :+ a :* s) :+ q))
              refl a n S Q)
           (cong ((n * Q - sq S) +_) (sym (cross a f xs))))
    (+-nonneg (≤⇒0≤- (cauchy-schwarz f xs)) (sumMap-nonneg _ xs (λ y → sq-nonneg (a - f y))))
  where
  a = f x
  n = size xs
  S = sumMap f xs
  Q = sumMap (λ y → sq (f y)) xs

-- A sample with some spread has kurtosis at least 1. (The bound is sharp: two points.)
kurtosis-ge-one : ∀ xs → devSq (mean xs) xs ≢ 0ℚ → 1ℚ ≤ kurtosis xs
kurtosis-ge-one xs S≢0 =
  le-div-of-mul-le (*-pos 0<S 0<S)
    (≤-trans (≤-reflexive (*-identityˡ (sq S))) (cauchy-schwarz (λ x → sq (x - mean xs)) xs))
  where
  S = devSq (mean xs) xs
  0<S : 0ℚ < S
  0<S = ≤∧≢⇒< (sumMap-nonneg _ xs (λ x → sq-nonneg (x - mean xs))) (λ eq → S≢0 (sym eq))
