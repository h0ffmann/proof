{-# OPTIONS --safe --without-K #-}

-- More of the Joint Competitive Share (JCS) model of `tv-audience/python/experiment.py`, on the
-- definitions of `TvAudience.Jcs` (a channel enters by its weight w = exp(u) ≥ 0, the outside
-- option by the weight 1):
--
-- * `jcs-odds`: a channel's share over the outside share is its weight, so the log-odds that the
--   features `logodds`, `lo_lag7` and `lo_lag_mean` read is the utility u.
-- * `jcs-stable`: `_softmax_out` subtracts the slot's largest utility before the exponential, so
--   it computes w·k / (k + Σ w·k) with k = exp(-max u) > 0. That is the same share.
-- * `jcs-invert`: any shares with a sum below 1 come from one set of weights, w = s / s₀. The
--   logit layer can fit every coherent slot exactly, and the weights are unique (`jcs-odds`).
-- * `jcs-diversion`: when a channel leaves the slot, each other channel's share becomes
--   s / (1 - s_a): its viewers go to the rest in proportion to their shares, the outside option
--   included (the independence of irrelevant alternatives, again).
-- * `jcs-own`, `jcs-cross`: a larger weight raises the channel's own share and lowers every
--   rival's.
-- * `jcs-accounting`: the channel forecasts and the outside audience add up to the pool forecast.
-- * `jcs-pool-scale`: an error of the pool forecast by a factor c moves every channel's forecast
--   by c, and leaves the shares and the winner (`TvAudience.Winner.jcs-winner`) as they were.
--
-- The derivative ∂s/∂u = s (1 - s) of the logit's gradient needs the exponential and stays out.
module TvAudience.JcsTheory where

open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; <⇒≤; *-identityˡ; *-identityʳ; *-zeroʳ; _<?_; +-inverseʳ; +-monoˡ-<)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample
  using (sum; inv₀; _/₀_; inv₀-inverse; inv₀-pos; inv₀-unique; inv₀-*; *≢0; div-cancelˡ;
         <⇒≢0; +-nonneg; +-pos; *-nonneg)
open import OceanWaves.Order using (by-diff; div-le-div-of-cross; ≤⇒0≤-)
open import TvAudience.Jcs
  using (denom; jcsShare; jcsShares; jcsOutside; jcsForecast; NonNeg; sum-nonneg; denom-pos;
         jcs-sum; sum-jcsForecast)

-- ---------------------------------------------------------------------------------------------
-- Inverses

private
  inv₀-inv₀ : ∀ {n} → n ≢ 0ℚ → inv₀ (inv₀ n) ≡ n
  inv₀-inv₀ {n} hn =
    inv₀-unique {inv₀ n} {n} (trans (solve 2 (λ i x → i :* x := x :* i) refl (inv₀ n) n) (inv₀-inverse n hn))

  inv₀≢0 : ∀ {n} → n ≢ 0ℚ → inv₀ n ≢ 0ℚ
  inv₀≢0 {n} hn eq = hn (trans (sym (inv₀-inv₀ hn)) (cong inv₀ eq))

  denom≢0 : ∀ ws → NonNeg ws → denom ws ≢ 0ℚ
  denom≢0 ws h = <⇒≢0 (denom-pos ws h)

-- ---------------------------------------------------------------------------------------------
-- Odds against the outside option

jcs-odds : ∀ ws w → NonNeg ws → jcsShare ws w /₀ jcsOutside ws ≡ w
jcs-odds ws w h =
  trans (cong (λ q → (w * i) * q) (trans (cong inv₀ (*-identityˡ i)) (inv₀-inv₀ (denom≢0 ws h))))
    (trans (solve 3 (λ x j d → (x :* j) :* d := x :* (d :* j)) refl w i (denom ws))
      (trans (cong (w *_) (inv₀-inverse (denom ws) (denom≢0 ws h))) (*-identityʳ w)))
  where
  i = inv₀ (denom ws)

-- ---------------------------------------------------------------------------------------------
-- The stable form of `_softmax_out`

-- With k = exp(-max u): the channel's term w·k and the denominator k + Σ w·k.
stableShare : ℚ → List ℚ → ℚ → ℚ
stableShare k ws w = (w * k) /₀ (k + sum (map (_* k) ws))

stableOutside : ℚ → List ℚ → ℚ
stableOutside k ws = k /₀ (k + sum (map (_* k) ws))

private
  sum-map-*ʳ : ∀ k ws → sum (map (_* k) ws) ≡ sum ws * k
  sum-map-*ʳ k []       = sym (solve 1 (λ x → con 0ℚ :* x := con 0ℚ) refl k)
  sum-map-*ʳ k (w ∷ ws) rewrite sum-map-*ʳ k ws =
    solve 3 (λ x a s → a :* x :+ s :* x := (a :+ s) :* x) refl k w (sum ws)

  stable-den : ∀ k ws → k + sum (map (_* k) ws) ≡ k * denom ws
  stable-den k ws = trans (cong (k +_) (sum-map-*ʳ k ws))
                          (solve 2 (λ x s → x :+ s :* x := x :* (con 1ℚ :+ s)) refl k (sum ws))

jcs-stable : ∀ {k} ws w → 0ℚ < k → stableShare k ws w ≡ jcsShare ws w
jcs-stable {k} ws w hk =
  trans (cong₂ _/₀_ (solve 2 (λ x y → x :* y := y :* x) refl w k) (stable-den k ws))
        (div-cancelˡ w (denom ws) (<⇒≢0 hk))

jcs-stable-outside : ∀ {k} ws → 0ℚ < k → stableOutside k ws ≡ jcsOutside ws
jcs-stable-outside {k} ws hk =
  trans (cong₂ _/₀_ (sym (*-identityʳ k)) (stable-den k ws)) (div-cancelˡ 1ℚ (denom ws) (<⇒≢0 hk))

-- ---------------------------------------------------------------------------------------------
-- From shares back to weights

-- The weight of each share: s / s₀, with s₀ = 1 - Σ s.
invert : List ℚ → List ℚ
invert ss = map (λ s → s * inv₀ (1ℚ - sum ss)) ss

private
  sum-invert : ∀ j ss → sum (map (λ s → s * j) ss) ≡ sum ss * j
  sum-invert j ss = sum-map-*ʳ j ss

  -- With m = 1 - S and j = 1/m, the denominator of the inverted weights is j.
  denom-invert : ∀ ss → 1ℚ - sum ss ≢ 0ℚ → denom (invert ss) ≡ inv₀ (1ℚ - sum ss)
  denom-invert ss hm =
    trans (cong (1ℚ +_) (sum-invert j ss))
      (trans (cong (_+ sum ss * j) (sym (inv₀-inverse m hm)))
        (trans (solve 2 (λ s i → (con 1ℚ :- s) :* i :+ s :* i := i) refl (sum ss) j) refl))
    where
    m = 1ℚ - sum ss
    j = inv₀ m

  shares-of : ∀ W j m → inv₀ (denom W) ≡ m → m * j ≡ 1ℚ →
              ∀ ss → map (jcsShare W) (map (λ s → s * j) ss) ≡ ss
  shares-of W j m hd hmj []       = refl
  shares-of W j m hd hmj (s ∷ ss) =
    cong₂ _∷_ (trans (cong ((s * j) *_) hd)
                (trans (solve 3 (λ x y z → (x :* y) :* z := x :* (z :* y)) refl s j m)
                  (trans (cong (s *_) hmj) (*-identityʳ s))))
              (shares-of W j m hd hmj ss)

  gap-pos : ∀ ss → sum ss < 1ℚ → 0ℚ < 1ℚ - sum ss
  gap-pos ss h = subst (_< 1ℚ - sum ss) (+-inverseʳ (sum ss)) (+-monoˡ-< (- sum ss) h)

  gap≢0 : ∀ ss → sum ss < 1ℚ → 1ℚ - sum ss ≢ 0ℚ
  gap≢0 ss h = <⇒≢0 (gap-pos ss h)

-- Shares with a sum below 1 are the JCS shares of their inverted weights, and the outside share
-- is what the channels leave.
jcs-invert : ∀ ss → sum ss < 1ℚ → jcsShares (invert ss) ≡ ss
jcs-invert ss hs =
  shares-of (invert ss) (inv₀ m) m
    (trans (cong inv₀ (denom-invert ss hm)) (inv₀-inv₀ hm)) (inv₀-inverse m hm) ss
  where
  m  = 1ℚ - sum ss
  hm = gap≢0 ss hs

jcs-invert-outside : ∀ ss → sum ss < 1ℚ → jcsOutside (invert ss) ≡ 1ℚ - sum ss
jcs-invert-outside ss hs =
  trans (*-identityˡ (inv₀ (denom (invert ss))))
        (trans (cong inv₀ (denom-invert ss (gap≢0 ss hs))) (inv₀-inv₀ (gap≢0 ss hs)))

-- ---------------------------------------------------------------------------------------------
-- A channel leaves the slot

jcs-diversion : ∀ a rest b → NonNeg (a ∷ rest) →
                jcsShare rest b ≡ jcsShare (a ∷ rest) b /₀ (1ℚ - jcsShare (a ∷ rest) a)
jcs-diversion a rest b (ha ∷ h) =
  sym (trans (cong ((b * iD) *_) inv-gap)
        (trans (solve 4 (λ x i j d → (x :* i) :* (j :* d) := (x :* j) :* (d :* i)) refl b iD (inv₀ E) D)
          (trans (cong (jcsShare rest b *_) (inv₀-inverse D hD)) (*-identityʳ (jcsShare rest b)))))
  where
  D  = denom (a ∷ rest)
  E  = denom rest
  iD = inv₀ D
  hD : D ≢ 0ℚ
  hD = denom≢0 (a ∷ rest) (ha ∷ h)
  hE : E ≢ 0ℚ
  hE = denom≢0 rest h
  -- 1 - a/D = E/D, so its inverse is D/E.
  gap : 1ℚ - a * iD ≡ E * iD
  gap = trans (cong (_- a * iD) (sym (inv₀-inverse D hD)))
              (solve 3 (λ x s i → (con 1ℚ :+ (x :+ s)) :* i :- x :* i := (con 1ℚ :+ s) :* i) refl a (sum rest) iD)
  inv-gap : inv₀ (1ℚ - a * iD) ≡ inv₀ E * D
  inv-gap = trans (cong inv₀ gap) (trans (inv₀-* hE (inv₀≢0 hD)) (cong (inv₀ E *_) (inv₀-inv₀ hD)))

-- ---------------------------------------------------------------------------------------------
-- Own and cross effects of a weight

-- A larger weight a′ ≥ a raises the channel's own share.
jcs-own : ∀ rest {a a′} → NonNeg rest → 0ℚ ≤ a → a ≤ a′ → jcsShare (a ∷ rest) a ≤ jcsShare (a′ ∷ rest) a′
jcs-own rest {a} {a′} h ha aa′ =
  div-le-div-of-cross {a} {denom (a ∷ rest)} {a′} {denom (a′ ∷ rest)}
    (denom-pos (a ∷ rest) (ha ∷ h)) (denom-pos (a′ ∷ rest) (≤-trans′ ha aa′ ∷ h))
    (by-diff ((a′ - a) * (1ℚ + sum rest))
      (solve 3 (λ x y s → y :* (con 1ℚ :+ (x :+ s)) :- x :* (con 1ℚ :+ (y :+ s)) := (y :- x) :* (con 1ℚ :+ s)) refl a a′ (sum rest))
      (*-nonneg (≤⇒0≤- aa′) (<⇒≤ (denom-pos rest h))))
  where open import Data.Rational.Properties using () renaming (≤-trans to ≤-trans′)

-- The same larger weight lowers every rival's share.
jcs-cross : ∀ rest {a a′ w} → NonNeg rest → 0ℚ ≤ a → a ≤ a′ → 0ℚ ≤ w →
            jcsShare (a′ ∷ rest) w ≤ jcsShare (a ∷ rest) w
jcs-cross rest {a} {a′} {w} h ha aa′ hw =
  div-le-div-of-cross {w} {denom (a′ ∷ rest)} {w} {denom (a ∷ rest)}
    (denom-pos (a′ ∷ rest) (≤-trans′ ha aa′ ∷ h)) (denom-pos (a ∷ rest) (ha ∷ h))
    (by-diff (w * (a′ - a))
      (solve 4 (λ z x y s → z :* (con 1ℚ :+ (y :+ s)) :- z :* (con 1ℚ :+ (x :+ s)) := z :* (y :- x)) refl w a a′ (sum rest))
      (*-nonneg hw (≤⇒0≤- aa′)))
  where open import Data.Rational.Properties using () renaming (≤-trans to ≤-trans′)

-- ---------------------------------------------------------------------------------------------
-- The pool

-- The channel forecasts and the outside audience add up to the pool forecast.
jcs-accounting : ∀ pool ws → NonNeg ws → sum (jcsForecast pool ws) + pool * jcsOutside ws ≡ pool
jcs-accounting pool ws h =
  trans (cong (_+ pool * jcsOutside ws) (sum-jcsForecast pool ws))
    (trans (solve 3 (λ p s o → p :* s :+ p :* o := p :* (s :+ o)) refl pool (sum (jcsShares ws)) (jcsOutside ws))
      (trans (cong (pool *_) (jcs-sum ws h)) (*-identityʳ pool)))

-- A pool forecast off by a factor c moves every channel's forecast by c.
jcs-pool-scale : ∀ c pool ws → jcsForecast (c * pool) ws ≡ map (c *_) (jcsForecast pool ws)
jcs-pool-scale c pool ws = go ws
  where
  go : ∀ vs → map (λ w → (c * pool) * jcsShare ws w) vs ≡ map (c *_) (map (λ w → pool * jcsShare ws w) vs)
  go []       = refl
  go (v ∷ vs) = cong₂ _∷_ (solve 3 (λ x p s → (x :* p) :* s := x :* (p :* s)) refl c pool (jcsShare ws v)) (go vs)
