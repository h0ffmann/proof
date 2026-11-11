{-# OPTIONS --safe --without-K #-}

-- The share layer of the Joint Competitive Share (JCS) model of `tv-audience/python/experiment.py`
-- (`_softmax_out`): in a slot with channels c = 1..C and an outside option of utility 0,
--
--   s_c = exp(u_c) / (1 + Σ_k exp(u_k)),   s_0 = 1 / (1 + Σ_k exp(u_k)),   audience_c = pool · s_c.
--
-- ℚ has no exponential, so a channel enters by its weight w_c = exp(u_c), a number ≥ 0; the
-- Python computes the weights, Agda the rest. The neurosymbolic JCS changes only how u_c is
-- learned, so every theorem here holds for it too.
--
-- The theorems: the shares and the outside share add up to 1, so the channels' shares add up to
-- less than 1 and the C forecasts of a slot never add up to more than its pool forecast (the
-- coherence the paper claims for JCS); a channel with a larger weight has a larger share; the
-- ratio of two shares does not depend on the other channels (the logit's independence of
-- irrelevant alternatives); and a new rival never raises a channel's share.
module TvAudience.Jcs where

open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Product using (_×_; _,_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; <⇒≤; *-identityʳ; *-monoʳ-≤-nonNeg; _<?_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample
  using (sum; inv₀; _/₀_; inv₀-inverse; inv₀-nonneg; inv₀-pos; <⇒≢0; +-nonneg; +-pos; *-nonneg)
open import OceanWaves.Order using (by-diff; by-diff<; div-le-div-of-cross; div-monoˡ-≤)
open import TvAudience.Panel using (Slot; Coherent; countOver; countOver-coherent)

denom : List ℚ → ℚ
denom ws = 1ℚ + sum ws

jcsShare : List ℚ → ℚ → ℚ
jcsShare ws w = w /₀ denom ws

jcsShares : List ℚ → List ℚ
jcsShares ws = map (jcsShare ws) ws

jcsOutside : List ℚ → ℚ
jcsOutside ws = 1ℚ /₀ denom ws

-- The forecasts of a slot: its pool forecast times each channel's share.
jcsForecast : ℚ → List ℚ → List ℚ
jcsForecast pool ws = map (λ w → pool * jcsShare ws w) ws

NonNeg : List ℚ → Set
NonNeg = All (0ℚ ≤_)

-- ---------------------------------------------------------------------------------------------

sum-nonneg : ∀ ws → NonNeg ws → 0ℚ ≤ sum ws
sum-nonneg []       []       = ≤-refl
sum-nonneg (w ∷ ws) (h ∷ hs) = +-nonneg h (sum-nonneg ws hs)

denom-pos : ∀ ws → NonNeg ws → 0ℚ < denom ws
denom-pos ws h = +-pos (from-yes (0ℚ <? 1ℚ)) (sum-nonneg ws h)

private
  sum-map-* : ∀ c k ws → sum (map (λ w → c * (w * k)) ws) ≡ c * (sum ws * k)
  sum-map-* c k []       = solve 2 (λ x y → con 0ℚ := x :* (con 0ℚ :* y)) refl c k
  sum-map-* c k (w ∷ ws) rewrite sum-map-* c k ws =
    solve 4 (λ x y a s → x :* (a :* y) :+ x :* (s :* y) := x :* ((a :+ s) :* y)) refl c k w (sum ws)

sum-jcsShares : ∀ ws → sum (jcsShares ws) ≡ sum ws /₀ denom ws
sum-jcsShares ws =
  trans (cong sum (map-cong ws)) (trans (sum-map-* 1ℚ (inv₀ (denom ws)) ws)
                                        (solve 2 (λ s i → con 1ℚ :* (s :* i) := s :* i) refl (sum ws) (inv₀ (denom ws))))
  where
  map-cong : ∀ vs → map (jcsShare ws) vs ≡ map (λ w → 1ℚ * (w * inv₀ (denom ws))) vs
  map-cong []       = refl
  map-cong (v ∷ vs) = cong₂ _∷_ (solve 2 (λ x i → x :* i := con 1ℚ :* (x :* i)) refl v (inv₀ (denom ws))) (map-cong vs)

jcs-sum : ∀ ws → NonNeg ws → sum (jcsShares ws) + jcsOutside ws ≡ 1ℚ
jcs-sum ws h =
  trans (cong (_+ jcsOutside ws) (sum-jcsShares ws))
    (trans (solve 2 (λ s i → s :* i :+ con 1ℚ :* i := (con 1ℚ :+ s) :* i) refl (sum ws) (inv₀ (denom ws)))
      (inv₀-inverse (denom ws) (<⇒≢0 (denom-pos ws h))))

jcsOutside-pos : ∀ ws → NonNeg ws → 0ℚ < jcsOutside ws
jcsOutside-pos ws h =
  subst (0ℚ <_) (solve 1 (λ i → i := con 1ℚ :* i) refl (inv₀ (denom ws))) (inv₀-pos (denom-pos ws h))

-- The channels together never hold the whole pool: the outside option keeps a share.
jcs-inside-lt-one : ∀ ws → NonNeg ws → sum (jcsShares ws) < 1ℚ
jcs-inside-lt-one ws h =
  by-diff< (jcsOutside ws)
    (trans (cong (_- sum (jcsShares ws)) (sym (jcs-sum ws h)))
           (solve 2 (λ s o → (s :+ o) :- s := o) refl (sum (jcsShares ws)) (jcsOutside ws)))
    (jcsOutside-pos ws h)

sum-jcsForecast : ∀ pool ws → sum (jcsForecast pool ws) ≡ pool * sum (jcsShares ws)
sum-jcsForecast pool ws =
  trans (sum-map-* pool (inv₀ (denom ws)) ws) (cong (pool *_) (sym (sum-jcsShares ws)))

-- The C forecasts of a slot add up to at most its pool forecast.
jcs-coherent : ∀ pool ws → 0ℚ ≤ pool → NonNeg ws → Coherent (pool , jcsForecast pool ws)
jcs-coherent pool ws hp h =
  subst (_≤ pool) (sym (sum-jcsForecast pool ws))
    (subst (pool * sum (jcsShares ws) ≤_) (*-identityʳ pool)
      (*-monoˡ-≤′ hp (<⇒≤ (jcs-inside-lt-one ws h))))
  where
  open import Data.Rational.Properties using () renaming (*-monoˡ-≤-nonNeg to *-monoˡ′)
  *-monoˡ-≤′ : ∀ {c a b} → 0ℚ ≤ c → a ≤ b → c * a ≤ c * b
  *-monoˡ-≤′ {c} hc ab = *-monoˡ′ c {{nonNegative hc}} ab

-- So the coherence count of JCS against its own pool forecasts is 0.
jcs-countOver : ∀ (slots : List (ℚ × List ℚ)) → All (λ { (p , ws) → 0ℚ ≤ p × NonNeg ws }) slots →
                countOver (map (λ { (p , ws) → (p , jcsForecast p ws) }) slots) ≡ 0ℚ
jcs-countOver slots h = countOver-coherent _ (go slots h)
  where
  go : ∀ ss → All (λ { (p , ws) → 0ℚ ≤ p × NonNeg ws }) ss →
       All Coherent (map (λ { (p , ws) → (p , jcsForecast p ws) }) ss)
  go []              []              = []
  go ((p , ws) ∷ ss) ((hp , hw) ∷ hs) = jcs-coherent p ws hp hw ∷ go ss hs

-- ---------------------------------------------------------------------------------------------
-- Order, independence of irrelevant alternatives, rivals

jcsShare-mono : ∀ ws {w v} → NonNeg ws → w ≤ v → jcsShare ws w ≤ jcsShare ws v
jcsShare-mono ws h wv = div-monoˡ-≤ wv (<⇒≤ (denom-pos ws h))

jcs-iia : ∀ ws a b → jcsShare ws a * b ≡ jcsShare ws b * a
jcs-iia ws a b = solve 3 (λ x y i → (x :* i) :* y := (y :* i) :* x) refl a b (inv₀ (denom ws))

-- A rival with weight r ≥ 0 added to the slot never raises a channel's share.
jcs-rival : ∀ ws {r w} → NonNeg ws → 0ℚ ≤ r → 0ℚ ≤ w → jcsShare (r ∷ ws) w ≤ jcsShare ws w
jcs-rival ws {r} {w} h hr hw =
  div-le-div-of-cross {w} {denom (r ∷ ws)} {w} {denom ws} (denom-pos (r ∷ ws) (hr ∷ h)) (denom-pos ws h)
    (by-diff (w * r) (solve 3 (λ x y s → x :* (con 1ℚ :+ (y :+ s)) :- x :* (con 1ℚ :+ s) := x :* y) refl w r (sum ws))
                     (*-nonneg hw hr))
