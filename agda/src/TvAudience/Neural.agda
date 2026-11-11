{-# OPTIONS --safe --without-K #-}

-- The neurosymbolic JCS of `tv-audience/python/experiment.py` (`fit_neural_logit`): the utility
-- of a channel is a linear term plus a one-hidden-layer network,
--
--   u = w · z + b + W2 · act(W1 z + b1),    z = (x - μ) / σ (features standardised),
--
-- and the symbolic part (the outside option, one softmax per slot, audience = pool × share) is
-- the share layer of `TvAudience.Jcs`, unchanged. The Python's activation is tanh, which ℚ does
-- not have; here the activation is a parameter, so the theorems hold for tanh and for any other.
--
-- The theorems: with W2 = 0 the network is the linear utility of JCS (the neurosymbolic model
-- nests JCS); with an activation bounded by 1, as tanh is, the network moves a utility by at
-- most Σ |W2|; standardising and the inverse transform of the MLP's target give back the value;
-- and the training signal of the logit layer, the residual s - s_obs that the gradient multiplies
-- (`resid` in the Python), sums over a slot to s₀,obs - s₀ and is 0 at the weights that fit the
-- observed shares (`TvAudience.JcsTheory.jcs-invert`), whatever learns the utility.
module TvAudience.Neural where

open import Data.List using (List; []; _∷_; map; length)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Nat using (ℕ; suc)
open import Data.Nat.Properties using (suc-injective)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; ∣_∣; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; +-mono-≤; ∣p+q∣≤∣p∣+∣q∣; ∣p*q∣≡∣p∣*∣q∣; 0≤∣p∣;
         *-monoˡ-≤-nonNeg; *-identityʳ; *-zeroˡ; +-identityʳ; +-inverseʳ)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample using (sum; inv₀; _/₀_; inv₀-inverse)
open import TvAudience.Jcs using (jcsShares; jcsOutside; NonNeg; jcs-sum)
open import TvAudience.JcsTheory using (invert; jcs-invert)

-- ---------------------------------------------------------------------------------------------
-- Vectors as lists

dot : List ℚ → List ℚ → ℚ
dot (a ∷ as) (h ∷ hs) = a * h + dot as hs
dot _        _        = 0ℚ

absSum : List ℚ → ℚ
absSum []       = 0ℚ
absSum (a ∷ as) = ∣ a ∣ + absSum as

-- A dense layer: one row of weights and one bias per unit.
dense : List (List ℚ) → List ℚ → List ℚ → List ℚ
dense (r ∷ rs) (c ∷ cs) z = (dot r z + c) ∷ dense rs cs z
dense _        _        z = []

-- Standardising one feature, and the inverse transform (`StandardScaler`, `* sd + mu`).
standardise : ℚ → ℚ → ℚ → ℚ
standardise μ σ x = (x - μ) /₀ σ

unstandardise : ℚ → ℚ → ℚ → ℚ
unstandardise μ σ z = z * σ + μ

record NsParams : Set where
  constructor ns
  field
    w  : List ℚ
    b  : ℚ
    W1 : List (List ℚ)
    b1 : List ℚ
    W2 : List ℚ
open NsParams public

linearUtility : List ℚ → ℚ → List ℚ → ℚ
linearUtility w b z = dot w z + b

hidden : (ℚ → ℚ) → NsParams → List ℚ → List ℚ
hidden act P z = map act (dense (W1 P) (b1 P) z)

nsUtility : (ℚ → ℚ) → NsParams → List ℚ → ℚ
nsUtility act P z = linearUtility (w P) (b P) z + dot (W2 P) (hidden act P z)

-- The plain JCS: the same utility with no network.
jcsParams : List ℚ → ℚ → NsParams
jcsParams w b = ns w b [] [] []

-- ---------------------------------------------------------------------------------------------
-- The neurosymbolic model nests JCS

dot-zero : ∀ v h → All (_≡ 0ℚ) v → dot v h ≡ 0ℚ
dot-zero []       h        []       = refl
dot-zero (a ∷ v)  []       (_ ∷ _)  = refl
dot-zero (a ∷ v)  (x ∷ h)  (refl ∷ hs) =
  trans (cong (0ℚ * x +_) (dot-zero v h hs)) (trans (+-identityʳ (0ℚ * x)) (*-zeroˡ x))

ns-nests-jcs : ∀ act P z → All (_≡ 0ℚ) (W2 P) → nsUtility act P z ≡ linearUtility (w P) (b P) z
ns-nests-jcs act P z h =
  trans (cong (linearUtility (w P) (b P) z +_) (dot-zero (W2 P) (hidden act P z) h))
        (+-identityʳ (linearUtility (w P) (b P) z))

ns-jcsParams : ∀ act w b z → nsUtility act (jcsParams w b) z ≡ linearUtility w b z
ns-jcsParams act w b z = ns-nests-jcs act (jcsParams w b) z []

-- ---------------------------------------------------------------------------------------------
-- A bounded activation moves the utility by at most Σ |W2|

private
  absSum-nonneg : ∀ v → 0ℚ ≤ absSum v
  absSum-nonneg []       = ≤-refl
  absSum-nonneg (a ∷ v)  = +-mono-≤ (0≤∣p∣ a) (absSum-nonneg v)

  le-one : ∀ a x → ∣ x ∣ ≤ 1ℚ → ∣ a * x ∣ ≤ ∣ a ∣
  le-one a x hx =
    subst (∣ a * x ∣ ≤_) (*-identityʳ ∣ a ∣)
      (subst (_≤ ∣ a ∣ * 1ℚ) (sym (∣p*q∣≡∣p∣*∣q∣ a x))
        (*-monoˡ-≤-nonNeg ∣ a ∣ {{nonNegative (0≤∣p∣ a)}} hx))

dot-bound : ∀ v h → All (λ t → ∣ t ∣ ≤ 1ℚ) h → ∣ dot v h ∣ ≤ absSum v
dot-bound []      h       _        = ≤-refl
dot-bound (a ∷ v) []      _        = absSum-nonneg (a ∷ v)
dot-bound (a ∷ v) (x ∷ h) (hx ∷ hs) =
  ≤-trans (∣p+q∣≤∣p∣+∣q∣ (a * x) (dot v h)) (+-mono-≤ (le-one a x hx) (dot-bound v h hs))

map-bounded : ∀ (act : ℚ → ℚ) xs → (∀ t → ∣ act t ∣ ≤ 1ℚ) → All (λ t → ∣ t ∣ ≤ 1ℚ) (map act xs)
map-bounded act []       h = []
map-bounded act (x ∷ xs) h = h x ∷ map-bounded act xs h

ns-bounded : ∀ act P z → (∀ t → ∣ act t ∣ ≤ 1ℚ) →
             ∣ nsUtility act P z - linearUtility (w P) (b P) z ∣ ≤ absSum (W2 P)
ns-bounded act P z h =
  subst (_≤ absSum (W2 P))
    (cong ∣_∣ (solve 2 (λ l d → d := (l :+ d) :- l) refl (linearUtility (w P) (b P) z) (dot (W2 P) (hidden act P z))))
    (dot-bound (W2 P) (hidden act P z) (map-bounded act (dense (W1 P) (b1 P) z) h))

-- ---------------------------------------------------------------------------------------------
-- Standardising

unstandardise-standardise : ∀ μ σ x → σ ≢ 0ℚ → unstandardise μ σ (standardise μ σ x) ≡ x
unstandardise-standardise μ σ x hσ =
  trans (solve 4 (λ m s y i → (y :- m) :* i :* s :+ m := (y :- m) :* (s :* i) :+ m) refl μ σ x (inv₀ σ))
    (trans (cong (λ t → (x - μ) * t + μ) (inv₀-inverse σ hσ))
      (solve 2 (λ m y → (y :- m) :* con 1ℚ :+ m := y) refl μ x))

-- ---------------------------------------------------------------------------------------------
-- The training signal of the logit layer

-- s - s_obs, channel by channel.
resid : List ℚ → List ℚ → List ℚ
resid (s ∷ ss) (o ∷ os) = (s - o) ∷ resid ss os
resid _        _        = []

private
  length-map′ : ∀ (f : ℚ → ℚ) xs → length (map f xs) ≡ length xs
  length-map′ f []       = refl
  length-map′ f (x ∷ xs) = cong suc (length-map′ f xs)

sum-resid : ∀ ss os → length ss ≡ length os → sum (resid ss os) ≡ sum ss - sum os
sum-resid []       []       _  = refl
sum-resid (s ∷ ss) (o ∷ os) eq rewrite sum-resid ss os (suc-injective eq) =
  solve 4 (λ a b x y → (a :- b) :+ (x :- y) := (a :+ x) :- (b :+ y)) refl s o (sum ss) (sum os)

-- Over a slot the residuals add up to the outside option's: s₀,obs - s₀.
resid-slot : ∀ ws os → NonNeg ws → length ws ≡ length os →
             sum (resid (jcsShares ws) os) ≡ (1ℚ - sum os) - jcsOutside ws
resid-slot ws os h eq =
  trans (sum-resid (jcsShares ws) os (trans (length-map′ _ ws) eq))
    (trans (cong (_- sum os) (shares≡ (jcs-sum ws h)))
      (solve 2 (λ z o → (con 1ℚ :- z) :- o := (con 1ℚ :- o) :- z) refl (jcsOutside ws) (sum os)))
  where
  shares≡ : sum (jcsShares ws) + jcsOutside ws ≡ 1ℚ → sum (jcsShares ws) ≡ 1ℚ - jcsOutside ws
  shares≡ e = trans (solve 2 (λ s z → s := (s :+ z) :- z) refl (sum (jcsShares ws)) (jcsOutside ws))
                    (cong (_- jcsOutside ws) e)

-- At the weights that reproduce the observed shares, every residual is 0: the fit is a
-- stationary point of the logit loss (before the L2 penalty).
resid-fit : ∀ os → sum os < 1ℚ → All (_≡ 0ℚ) (resid (jcsShares (invert os)) os)
resid-fit os hs = subst (λ xs → All (_≡ 0ℚ) (resid xs os)) (sym (jcs-invert os hs)) (zeros os)
  where
  zeros : ∀ xs → All (_≡ 0ℚ) (resid xs xs)
  zeros []       = []
  zeros (x ∷ xs) = +-inverseʳ x ∷ zeros xs
