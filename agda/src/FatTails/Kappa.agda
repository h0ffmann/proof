{-# OPTIONS --safe --without-K #-}

-- The rational part of Taleb's κ: the mean absolute deviation of n-day sums, M(n), and the ratio
-- M(n) / M(1) that κ reads.
--
-- `fat_tails.py` computes κ(1, n) = 2 - log n / log (M(n) / M(1)), where `mad_of_sums(x, n)`
-- cuts the sample into ⌊len / n⌋ blocks of n days that do not overlap and takes the MAD of the
-- block sums. The logarithm is not a rational function, so κ itself is not defined here. Its
-- input, the ratio, is. A sample is given here as its blocks, `List (List ℚ)`: the sample is
-- `concat bs` and the n-day sums are `blockSums bs`. When the length of the sample is a multiple
-- of n, `mad (concat bs)` is the Python M(1); otherwise Python takes M(1) over the whole sample and
-- M(n) over the part that fills whole blocks, and the tool in `tools/fat-tails/` does the same.
--
-- What is proved, for every sample of whole blocks of k points:
--
--   * `kappaRatio-scale`: the ratio, and so κ, does not change when the returns are multiplied by
--     c ≠ 0;
--   * `madOfSums-le`: M(k) ≤ k M(1). So M(k) / M(1) ≤ k, and, when the ratio is above 1, κ(1, k) ≤ 1
--     (log is increasing, a step this module does not take). κ = 1 is the Cauchy-like end of the
--     scale, where the MAD of a sum grows like the sum itself.
module FatTails.Kappa where

open import Data.List using (List; []; _∷_; map; _++_; concat)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; ∣_∣)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; ∣p+q∣≤∣p∣+∣q∣; 0≤∣p∣; ∣p∣≡0⇒p≡0;
         *-identityˡ; *-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample
open import FatTails.Moments using (mad; mad-scale)
open import OceanWaves.Order using (div-monoˡ-≤)

-- The n-day sums of a sample cut into blocks.
blockSums : List (List ℚ) → List ℚ
blockSums = map sum

-- M(n), the MAD of the n-day sums (`mad_of_sums(x, n)`).
madOfSums : List (List ℚ) → ℚ
madOfSums bs = mad (blockSums bs)

-- Every block has k points.
Width : ℚ → List ℚ → Set
Width k b = size b ≡ k

-- M(n) / M(1), the ratio that κ(1, n) = 2 - log n / log ratio reads.
kappaRatio : List (List ℚ) → ℚ
kappaRatio bs = madOfSums bs /₀ mad (concat bs)

-- ---------------------------------------------------------------------------------------------
-- Scale invariance

private
  blockSums-scale : ∀ c bs → blockSums (map (map (c *_)) bs) ≡ map (c *_) (blockSums bs)
  blockSums-scale c []       = refl
  blockSums-scale c (b ∷ bs) = cong₂ _∷_ (sum-scale c b) (blockSums-scale c bs)

  map-++ : ∀ (f : ℚ → ℚ) xs ys → map f (xs ++ ys) ≡ map f xs ++ map f ys
  map-++ f []       ys = refl
  map-++ f (x ∷ xs) ys = cong (f x ∷_) (map-++ f xs ys)

  concat-scale : ∀ c bs → concat (map (map (c *_)) bs) ≡ map (c *_) (concat bs)
  concat-scale c []       = refl
  concat-scale c (b ∷ bs) = trans (cong (map (c *_) b ++_) (concat-scale c bs)) (sym (map-++ (c *_) b (concat bs)))

-- κ's ratio does not change when every return is multiplied by the same c ≠ 0.
kappaRatio-scale : ∀ {c} bs → c ≢ 0ℚ → kappaRatio (map (map (c *_)) bs) ≡ kappaRatio bs
kappaRatio-scale {c} bs c≢0 =
  trans (cong₂ _/₀_ (trans (cong mad (blockSums-scale c bs)) (mad-scale c (blockSums bs)))
                    (trans (cong mad (concat-scale c bs)) (mad-scale c (concat bs))))
        (div-cancelˡ (madOfSums bs) (mad (concat bs)) ∣c∣≢0)
  where
  ∣c∣≢0 : ∣ c ∣ ≢ 0ℚ
  ∣c∣≢0 eq = c≢0 (∣p∣≡0⇒p≡0 c eq)

-- ---------------------------------------------------------------------------------------------
-- M(k) ≤ k M(1)

-- |Σ g| ≤ Σ |g|.
abs-sumMap : ∀ (g : ℚ → ℚ) xs → ∣ sumMap g xs ∣ ≤ sumMap (λ x → ∣ g x ∣) xs
abs-sumMap g []       = ≤-refl
abs-sumMap g (x ∷ xs) = ≤-trans (∣p+q∣≤∣p∣+∣q∣ (g x) (sumMap g xs)) (+-mono-≤ (≤-refl {∣ g x ∣}) (abs-sumMap g xs))

private
  sum-concat : ∀ bs → sum (blockSums bs) ≡ sum (concat bs)
  sum-concat []       = refl
  sum-concat (b ∷ bs) = trans (cong (sum b +_) (sum-concat bs)) (sym (sum-++ b (concat bs)))

  size-concat : ∀ {k} bs → All (Width k) bs → size (concat bs) ≡ k * size bs
  size-concat {k} []       []       = sym (*-zeroʳ′ k)
    where open import Data.Rational.Properties using () renaming (*-zeroʳ to *-zeroʳ′)
  size-concat {k} (b ∷ bs) (h ∷ hs) =
    trans (size-++ b (concat bs))
      (trans (cong₂ _+_ h (size-concat bs hs))
             (solve 2 (λ k m → k :+ k :* m := k :* (con 1ℚ :+ m)) refl k (size bs)))

  -- One block: |Σ x - k c| ≤ Σ |x - c|.
  block-le : ∀ {k} c b → size b ≡ k → ∣ sum b - k * c ∣ ≤ sumMap (λ x → ∣ x - c ∣) b
  block-le {k} c b h =
    subst (λ t → ∣ t ∣ ≤ sumMap (λ x → ∣ x - c ∣) b)
      (trans (sumMap-centre c b) (cong (λ n → sum b - n) (trans (solve 2 (λ a n → a :* n := n :* a) refl c (size b))
                                                                 (cong (_* c) h))))
      (abs-sumMap (λ x → x - c) b)

  blocks-le : ∀ {k} c bs → All (Width k) bs →
              sumMap (λ s → ∣ s - k * c ∣) (blockSums bs) ≤ sumMap (λ x → ∣ x - c ∣) (concat bs)
  blocks-le c []       []       = ≤-refl
  blocks-le c (b ∷ bs) (h ∷ hs) =
    ≤-trans (+-mono-≤ (block-le c b h) (blocks-le c bs hs)) (≤-reflexive (sym (sumMap-++ _ b (concat bs))))

-- For a sample of whole blocks of k > 0 points, M(k) ≤ k M(1).
madOfSums-le : ∀ {k} b bs → 0ℚ < k → All (Width k) (b ∷ bs) →
               madOfSums (b ∷ bs) ≤ k * mad (concat (b ∷ bs))
madOfSums-le {k} b bs 0<k hs =
  ≤-trans (≤-reflexive (cong (λ t → sumMap (λ s → ∣ s - t ∣) sums /₀ size sums) mean-sums))
    (≤-trans (≤-reflexive (cong (λ t → E /₀ t) (size-map sum bss)))
      (≤-trans (div-monoˡ-≤ (blocks-le c bss hs) (size-nonneg bss))
               (≤-reflexive (sym rhs))))
  where
  bss = b ∷ bs
  sums = blockSums bss
  xs = concat bss
  c = mean xs
  m = size bss
  S = sum xs
  E = sumMap (λ s → ∣ s - k * c ∣) sums
  D = sumMap (λ x → ∣ x - c ∣) xs
  k≢0 : k ≢ 0ℚ
  k≢0 = <⇒≢0 0<k
  m≢0 : m ≢ 0ℚ
  m≢0 = <⇒≢0 (size-cons-pos b bs)
  -- k S / (k m) = S / m.
  cancel : ∀ a → k * (a /₀ (k * m)) ≡ a /₀ m
  cancel a =
    trans (cong (λ t → k * (a * t)) (inv₀-* k≢0 m≢0))
      (trans (solve 4 (λ k a i j → k :* (a :* (i :* j)) := (k :* i) :* (a :* j)) refl k a (inv₀ k) (inv₀ m))
        (trans (cong (_* (a /₀ m)) (inv₀-inverse k k≢0)) (*-identityˡ (a /₀ m))))
  mean-sums : mean sums ≡ k * c
  mean-sums =
    trans (cong₂ _/₀_ (sum-concat bss) (size-map sum bss))
      (sym (trans (cong (λ t → k * (S /₀ t)) (size-concat bss hs)) (cancel S)))
  rhs : k * mad xs ≡ D /₀ m
  rhs = trans (cong (λ t → k * (D /₀ t)) (size-concat bss hs)) (cancel D)
