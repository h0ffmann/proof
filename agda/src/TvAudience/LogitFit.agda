{-# OPTIONS --safe --without-K #-}

-- The gradient layer of the JCS logit fit (`fit_logit` in `tv-audience/python/experiment.py`).
-- The loss is the negative log-likelihood of the observed shares with an L2 penalty 2λ on the
-- linear coefficients (none on the intercept), and the Python writes its gradient by hand as
--
--   (Σ resid, Zᵀ resid + 2 λ w) / n,      resid = s - s_obs,
--
-- with `resid` of `TvAudience.Neural` (the multiplier every coordinate of the gradient reads).
-- The derivative of the share s = exp(u) / (1 + Σ exp(u)) needs the exponential, which ℚ does
-- not have, so Agda does not derive the formula; `tools/tv-validate/` checks it against
-- automatic differentiation on the run. What Agda proves, for every slot and every weights:
--
-- * at the weights that fit the observed shares exactly (`jcs-invert`), every residual is 0, so
--   the intercept's coordinate Σ resid and every feature's coordinate Σ resid · z are 0: the
--   exact fit is a stationary point of the unpenalised loss;
-- * with the penalty, one feature's coordinate at the exact fit is the penalty term 2 λ w alone,
--   so if the penalised gradient is 0 there, the coefficient is 0: the L2 moves the fit off the
--   exact shares unless every coefficient is 0 (the experiment's λ is positive);
-- * the exact fit is the only one: weight lists with the same shares are the same weights. The
--   outside share is 1 - Σ shares, so equal shares give equal denominators; the share function
--   is then the same on both lists and injective, because no denominator is 0.
module TvAudience.LogitFit where

open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Properties
  using (<⇒≤; *-identityʳ; *-identityˡ; *-zeroˡ; +-identityʳ; +-identityˡ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample
  using (sum; inv₀; _/₀_; inv₀-inverse; inv₀-unique; inv₀-nonneg; <⇒≢0; *-nonneg)
open import OceanWaves.Order using (2ℚ; 0<2; <⇒0<-; ≤⇒0≤-; *-pos; div-mul-cancel; div-nonneg)
open import TvAudience.Jcs
  using (denom; jcsShare; jcsShares; jcsOutside; NonNeg; denom-pos; jcs-sum; jcs-inside-lt-one)
open import TvAudience.JcsTheory using (invert; jcs-invert; jcs-invert-outside)
open import TvAudience.Neural using (resid; resid-fit; dot; dot-zero)

-- ---------------------------------------------------------------------------------------------
-- The gradient's coordinates of one slot

-- The intercept's coordinate: Σ resid.
gradBias : List ℚ → List ℚ → ℚ
gradBias ss os = sum (resid ss os)

-- One feature's coordinate: Σ resid · z, with z the feature's value on each channel of the slot
-- (one column of Z).
featureGrad : List ℚ → List ℚ → List ℚ → ℚ
featureGrad z ss os = dot (resid ss os) z

-- ---------------------------------------------------------------------------------------------
-- The exact fit is stationary

sum-zero : ∀ xs → All (_≡ 0ℚ) xs → sum xs ≡ 0ℚ
sum-zero []       []       = refl
sum-zero (x ∷ xs) (e ∷ es) =
  trans (cong (_+ sum xs) e) (trans (+-identityˡ (sum xs)) (sum-zero xs es))

gradBias-fit : ∀ os → sum os < 1ℚ → gradBias (jcsShares (invert os)) os ≡ 0ℚ
gradBias-fit os hs = sum-zero (resid (jcsShares (invert os)) os) (resid-fit os hs)

featureGrad-fit : ∀ os z → sum os < 1ℚ → featureGrad z (jcsShares (invert os)) os ≡ 0ℚ
featureGrad-fit os z hs = dot-zero (resid (jcsShares (invert os)) os) z (resid-fit os hs)

-- ---------------------------------------------------------------------------------------------
-- The L2 penalty

-- With the penalty, one feature's coordinate at the exact fit is the penalty term alone.
l2-coordinate : ∀ l2 wj z os → sum os < 1ℚ →
                featureGrad z (jcsShares (invert os)) os + (2ℚ * l2) * wj ≡ (2ℚ * l2) * wj
l2-coordinate l2 wj z os hs =
  trans (cong (_+ (2ℚ * l2) * wj) (featureGrad-fit os z hs)) (+-identityˡ ((2ℚ * l2) * wj))

-- So if the penalised gradient is 0 at an exact fit, the coefficient is 0.
l2-stationary-zero : ∀ l2 wj z os → 0ℚ < l2 → sum os < 1ℚ →
                     featureGrad z (jcsShares (invert os)) os + (2ℚ * l2) * wj ≡ 0ℚ → wj ≡ 0ℚ
l2-stationary-zero l2 wj z os hl2 hs e =
  trans (sym lhs) (trans (cong (_* inv₀ d) p≡0) (*-zeroˡ (inv₀ d)))
  where
  d    = 2ℚ * l2
  hd   = <⇒≢0 (*-pos 0<2 hl2)
  p    = d * wj
  fg+p : featureGrad z (jcsShares (invert os)) os + p ≡ p
  fg+p = trans (cong (_+ p) (featureGrad-fit os z hs)) (+-identityˡ p)
  p≡0  : p ≡ 0ℚ
  p≡0  = trans (sym fg+p) e
  lhs  : (d * wj) * inv₀ d ≡ wj
  lhs  = trans (solve 3 (λ x y i → (x :* y) :* i := y :* (x :* i)) refl d wj (inv₀ d))
               (trans (cong (wj *_) (inv₀-inverse d hd)) (*-identityʳ wj))

-- ---------------------------------------------------------------------------------------------
-- Lists

private
  headQ : List ℚ → ℚ
  headQ []       = 0ℚ
  headQ (x ∷ _)  = x

  tailQ : List ℚ → List ℚ
  tailQ []       = []
  tailQ (_ ∷ xs) = xs

  map-cong₂ : ∀ (f g : ℚ → ℚ) xs → (∀ x → f x ≡ g x) → map f xs ≡ map g xs
  map-cong₂ f g []       h = refl
  map-cong₂ f g (x ∷ xs) h = cong₂ _∷_ (h x) (map-cong₂ f g xs h)

  -- An injective map comes out of an equality of the mapped lists.
  map-inj : ∀ (f : ℚ → ℚ) xs ys → (∀ a b → f a ≡ f b → a ≡ b) →
            map f xs ≡ map f ys → xs ≡ ys
  map-inj f []       []       finj e = refl
  map-inj f []       (y ∷ ys) finj ()
  map-inj f (x ∷ xs) []       finj ()
  map-inj f (x ∷ xs) (y ∷ ys) finj e =
    cong₂ _∷_ (finj x y (cong headQ e)) (map-inj f xs ys finj (cong tailQ e))

-- ---------------------------------------------------------------------------------------------
-- Shares and division

private
  inv₀-inv₀ : ∀ d → d ≢ 0ℚ → inv₀ (inv₀ d) ≡ d
  inv₀-inv₀ d hd =
    inv₀-unique {inv₀ d} {d}
      (trans (solve 2 (λ i x → i :* x := x :* i) refl (inv₀ d) d) (inv₀-inverse d hd))

  -- A common non-zero denominator: the same share gives the same weight.
  share-inj : ∀ d w w' → d ≢ 0ℚ → w /₀ d ≡ w' /₀ d → w ≡ w'
  share-inj d w w' hd e =
    trans (sym (div-mul-cancel w hd)) (trans (cong (_* d) e) (div-mul-cancel w' hd))

  -- The denominator is the inverse of the outside share.
  out-to-den : ∀ ws → denom ws ≢ 0ℚ → inv₀ (jcsOutside ws) ≡ denom ws
  out-to-den ws hd =
    trans (cong inv₀ (*-identityˡ (inv₀ (denom ws)))) (inv₀-inv₀ (denom ws) hd)

-- The shares of non-negative weights are non-negative.
jcsShares-nonneg : ∀ ws → NonNeg ws → NonNeg (jcsShares ws)
jcsShares-nonneg ws h = go ws h
  where
  go : ∀ vs → NonNeg vs → NonNeg (map (jcsShare ws) vs)
  go []       []       = []
  go (v ∷ vs) (hv ∷ hvs) =
    div-nonneg hv (<⇒≤ (denom-pos ws h)) ∷ go vs hvs

-- The inverted weights of non-negative observed shares are non-negative: each one is a share
-- times the inverse of 1 - Σ shares, which is positive.
invert-nonneg : ∀ os → NonNeg os → sum os < 1ℚ → NonNeg (invert os)
invert-nonneg os ho hs = go os ho
  where
  hj : 0ℚ ≤ inv₀ (1ℚ - sum os)
  hj = inv₀-nonneg (≤⇒0≤- (<⇒≤ hs))
  go : ∀ xs → NonNeg xs → NonNeg (map (λ s → s * inv₀ (1ℚ - sum os)) xs)
  go []       []       = []
  go (x ∷ xs) (hx ∷ hxs) = *-nonneg hx hj ∷ go xs hxs

-- ---------------------------------------------------------------------------------------------
-- The exact fit is the only one

fit-unique : ∀ ws os → NonNeg ws → jcsShares ws ≡ os → ws ≡ invert os
fit-unique ws os h ho = map-inj (jcsShare wi) ws wi finj same
  where
  wi = invert os

  honn : NonNeg os
  honn = subst NonNeg ho (jcsShares-nonneg ws h)

  hsum : sum os < 1ℚ
  hsum = subst (_< 1ℚ) (cong sum ho) (jcs-inside-lt-one ws h)

  hinn : NonNeg wi
  hinn = invert-nonneg os honn hsum

  hdw : denom ws ≢ 0ℚ
  hdw = <⇒≢0 (denom-pos ws h)

  hdi : denom wi ≢ 0ℚ
  hdi = <⇒≢0 (denom-pos wi hinn)

  -- Both outsides are 1 - Σ os, so both denominators are its inverse.
  ows : jcsOutside ws ≡ 1ℚ - sum (jcsShares ws)
  ows = trans (solve 2 (λ s o → o := (s :+ o) :- s) refl (sum (jcsShares ws)) (jcsOutside ws))
              (cong (_- sum (jcsShares ws)) (jcs-sum ws h))

  oeq : jcsOutside ws ≡ jcsOutside wi
  oeq = trans ows (trans (cong (1ℚ -_) (cong sum ho)) (sym (jcs-invert-outside os hsum)))

  denEq : denom ws ≡ denom wi
  denEq = trans (sym (out-to-den ws hdw)) (trans (cong inv₀ oeq) (out-to-den wi hdi))

  sharesCong : ∀ w → jcsShare ws w ≡ jcsShare wi w
  sharesCong w = cong (w *_) (cong inv₀ denEq)

  finj : ∀ a b → jcsShare wi a ≡ jcsShare wi b → a ≡ b
  finj a b = share-inj (denom wi) a b hdi

  same : map (jcsShare wi) ws ≡ map (jcsShare wi) wi
  same = trans (sym (map-cong₂ (jcsShare ws) (jcsShare wi) ws sharesCong))
               (trans ho (sym (jcs-invert os hsum)))
