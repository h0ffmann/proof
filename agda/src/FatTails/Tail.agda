{-# OPTIONS --safe --without-K #-}

-- The tail measures of `fat_tails.py` that are rational functions of their inputs: the Hill
-- estimator, given the logarithms of the order statistics; the expected-shortfall factor of a
-- power-law tail; the mean of a tail; and the count of days beyond k sigmas.
--
-- `hill(x, k)` in Python is 1 / (mean(log x₍₁₎ … log x₍ₖ₎) - log x₍ₖ₊₁₎), with x sorted from the
-- largest down. ℚ has no logarithm, so `hillGap` takes the logarithms as its input: the k
-- largest (`top`) and the next one (`thr`). Multiplying every x by c > 0 adds log c to every
-- logarithm; `hillGap-shift` proves that the estimate does not change, so the Hill α does not
-- depend on the unit of the returns. That log (c x) = log c + log x is the one step that is not
-- in Agda.
--
-- The Weissman quantile x₍ₖ₊₁₎ (k / (n p))^(1/α) has a real power, so it is not here; the
-- expected shortfall it gives, ES = VaR α / (α - 1), is (`esFactor`).
module FatTails.Tail where

open import Data.List using (List; []; _∷_; map; length)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; s≤s; z≤n)
import Data.Nat.Properties as ℕP
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <-≤-trans; ≤-<-trans; <⇒≤; *-identityʳ; *-monoˡ-≤-nonNeg)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary using (Dec; yes; no; contradiction)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import FatTails.Sample
open import OceanWaves.Order using (by-diff<; <⇒0<-; ≤⇒0≤-; div-le-div-of-cross)

-- ---------------------------------------------------------------------------------------------
-- The Hill estimator

-- mean(log of the k largest) - log of the next one. The Hill α is its inverse.
hillGap : List ℚ → ℚ → ℚ
hillGap top thr = mean top - thr

hillAlpha : List ℚ → ℚ → ℚ
hillAlpha top thr = inv₀ (hillGap top thr)

-- Adding log c to every logarithm (multiplying every x by c > 0) does not change the estimate.
hillGap-shift : ∀ c y ys thr → hillGap (map (_+ c) (y ∷ ys)) (thr + c) ≡ hillGap (y ∷ ys) thr
hillGap-shift c y ys thr =
  trans (cong (_- (thr + c)) (mean-shift c y ys))
        (solve 3 (λ m k t → (m :+ k) :- (t :+ k) := m :- t) refl (mean (y ∷ ys)) c thr)

hillAlpha-shift : ∀ c y ys thr → hillAlpha (map (_+ c) (y ∷ ys)) (thr + c) ≡ hillAlpha (y ∷ ys) thr
hillAlpha-shift c y ys thr = cong inv₀ (hillGap-shift c y ys thr)

-- With the k largest at or above the threshold (a sorted sample), the gap is not negative.
hillGap-nonneg : ∀ y ys thr → All (thr ≤_) (y ∷ ys) → 0ℚ ≤ hillGap (y ∷ ys) thr
hillGap-nonneg y ys thr h = ≤⇒0≤- (mean-ge thr y ys h)

-- A positive gap gives a positive α.
hillAlpha-pos : ∀ top thr → 0ℚ < hillGap top thr → 0ℚ < hillAlpha top thr
hillAlpha-pos top thr h = inv₀-pos h

-- ---------------------------------------------------------------------------------------------
-- Expected shortfall of a power-law tail

-- ES / VaR = α / (α - 1) for a Pareto tail with exponent α > 1 (`es_evt = q_evt * a / (a - 1)`).
esFactor : ℚ → ℚ
esFactor α = α /₀ (α - 1ℚ)

expectedShortfall : ℚ → ℚ → ℚ
expectedShortfall var α = var * esFactor α

private
  0<α-1 : ∀ {α} → 1ℚ < α → 0ℚ < α - 1ℚ
  0<α-1 h = <⇒0<- h

-- For α > 1 the shortfall is more than the quantile.
esFactor-gt-one : ∀ {α} → 1ℚ < α → 1ℚ < esFactor α
esFactor-gt-one {α} h =
  by-diff< (inv₀ (α - 1ℚ))
    (trans (solve 2 (λ a i → a :* i :- con 1ℚ := ((a :- con 1ℚ) :* i :- con 1ℚ) :+ i) refl α (inv₀ (α - 1ℚ)))
      (trans (cong (λ t → (t - 1ℚ) + inv₀ (α - 1ℚ)) (inv₀-inverse (α - 1ℚ) (<⇒≢0 (0<α-1 h))))
             (solve 1 (λ i → (con 1ℚ :- con 1ℚ) :+ i := i) refl (inv₀ (α - 1ℚ)))))
    (inv₀-pos (0<α-1 h))

-- A fatter tail (smaller α) gives a larger factor: the factor falls as α grows.
esFactor-antitone : ∀ {α β} → 1ℚ < α → α ≤ β → esFactor β ≤ esFactor α
esFactor-antitone {α} {β} hα hαβ =
  div-le-div-of-cross {β} {β - 1ℚ} {α} {α - 1ℚ} (0<α-1 (<-≤-trans hα hαβ)) (0<α-1 hα)
    (by-diff (β - α) (solve 2 (λ a b → a :* (b :- con 1ℚ) :- b :* (a :- con 1ℚ) := b :- a) refl α β)
             (≤⇒0≤- hαβ))

-- ES ≥ VaR for a loss quantile VaR ≥ 0 and α > 1.
es-ge-var : ∀ {var α} → 0ℚ ≤ var → 1ℚ < α → var ≤ expectedShortfall var α
es-ge-var {var} {α} hv hα =
  ≤-trans (≤-reflexive (sym (*-identityʳ var)))
          (*-monoˡ-≤-nonNeg var {{nonNegative hv}} (<⇒≤ (esFactor-gt-one hα)))

-- The mean of the losses beyond a level is at least the level: an empirical shortfall is never
-- below its quantile.
tailMean-ge : ∀ v y ys → All (v ≤_) (y ∷ ys) → v ≤ mean (y ∷ ys)
tailMean-ge = mean-ge

-- ---------------------------------------------------------------------------------------------
-- Days beyond k sigmas

private
  step : ∀ {P : Set} → Dec P → ℕ → ℕ
  step (yes _) n = suc n
  step (no _)  n = n

-- The number of points strictly above k (`(-zz > k).sum()`, on losses in sigmas).
exceed : ℚ → List ℚ → ℕ
exceed k []       = 0
exceed k (x ∷ xs) = step (k <? x) (exceed k xs)
  where open import Data.Rational.Properties using (_<?_)

private
  step-mono : ∀ {k k′ x n n′} (d′ : Dec (k′ < x)) (d : Dec (k < x)) → k ≤ k′ → n′ ℕ.≤ n →
              step d′ n′ ℕ.≤ step d n
  step-mono (yes _)  (yes _) _ h = s≤s h
  step-mono (yes p′) (no ¬p) k≤k′ h = contradiction (≤-<-trans k≤k′ p′) ¬p
  step-mono (no _)   (yes _) _ h = ℕP.m≤n⇒m≤1+n h
  step-mono (no _)   (no _)  _ h = h

  step-le : ∀ {P : Set} (d : Dec P) {n m} → n ℕ.≤ m → step d n ℕ.≤ suc m
  step-le (yes _) h = s≤s h
  step-le (no _)  h = ℕP.m≤n⇒m≤1+n h

-- A higher level is crossed on no more days.
exceed-antitone : ∀ {k k′} xs → k ≤ k′ → exceed k′ xs ℕ.≤ exceed k xs
exceed-antitone []       _ = z≤n
exceed-antitone (x ∷ xs) h = step-mono _ _ h (exceed-antitone xs h)

exceed-le-length : ∀ k xs → exceed k xs ℕ.≤ length xs
exceed-le-length k []       = z≤n
exceed-le-length k (x ∷ xs) = step-le _ (exceed-le-length k xs)
