{-# OPTIONS --safe --without-K #-}

-- Joint estimation of the channels of a slot against estimation of each channel alone.
--
-- A slot has C rows, one for each channel (with the outside audience as one more row when the
-- group is the whole pool), and every row is (actual audience y, forecast f). "Alone" is the
-- independent forecasts f₁ … f_C: each channel's model does not see its neighbours. "Joint" adds
-- one step that sees them all: it takes a forecast p of the group's total (the pool), and moves
-- every forecast by the same amount so that the forecasts add up to p,
--
--   f'ᵢ = fᵢ - (Σ f - p) / C.
--
-- This is the Euclidean projection of the forecasts onto the plane Σ f = p. It costs one sum and
-- one division per slot, O(C), which is the "computationally cheap" of the claim.
--
-- With T = Σ y the actual total, S = Σ f - T the bias of the independent forecasts and
-- ε = p - T the error of the pool forecast, the theorems are, for every slot and every number
-- of channels:
--
-- * `joint-gain`: C · (SSE_alone - SSE_joint) = S² - ε². The identity is exact.
-- * `joint-le`, `joint-lt`: when the pool forecast is not worse than the sum of the channel
--   forecasts (|ε| ≤ |S|), the joint squared error is not larger, and it is strictly smaller when
--   |ε| < |S|. `joint-known`: with the actual pool (ε = 0), every incoherent slot (S ≠ 0) gains.
-- * `joint-common-bias`: when every channel is over-forecast by at least δ ≥ 0 (a big show of a
--   rival takes viewers that each channel's own model does not see), the gain is at least
--   (C δ)² - η² over C, for |ε| ≤ η. With an exact pool it is at least C δ²: it grows with the
--   number of channels that contest the slot, and with the square of their common bias.
-- * `channel-no-worse`: per channel, with the actual pool. When every error lies in [lo, hi]
--   with 0 ≤ lo and hi ≤ 2 lo (a common over-forecast of similar size), no channel's absolute
--   error grows. Without that band a channel can get worse (`TvAudience.JointExamples`).
-- * `joint-worth`: with a cost of each method, the joint method has the lower error plus cost
--   whenever C times its extra cost is at most S² - ε².
-- * `joint-total`: over a list of slots, the total squared error of the joint method is not
--   larger, when every slot has |ε| ≤ |S|.
--
-- What stays outside: the theorems are about squared error, not WAPE, and about one slot's
-- numbers, not about a distribution. That the pool is easier to forecast than the sum of the
-- channels (|ε| ≤ |S|) is an assumption here; it is a measurement on data. The JCS model of
-- `TvAudience.Jcs` reconciles by shares (multiplicatively), not by this additive projection.
module TvAudience.Joint where

open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All as All using (All; []; _∷_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Sum using (inj₁; inj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; ∣_∣; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-<-trans; ≤-reflexive; <⇒≤; +-mono-≤; +-monoˡ-<; 0≤∣p∣; 0≤p⇒∣p∣≡p;
         ∣p*q∣≡∣p∣*∣q∣; ∣p∣≡0⇒p≡0; ∣p∣≡p∨∣p∣≡-p; +-inverseʳ; *-comm; *-identityˡ; *-zeroʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst; subst₂)

open import FatTails.Sample using (size; size-cons-pos)
open import OceanWaves.Order
  using (inv₀; _/₀_; inv₀-inverse; inv₀-pos; <⇒≢0; ≤∧≢⇒<; by-diff; by-diff<; ≤⇒0≤-;
         mul-le-mul′; sq-nonneg; *-nonneg; *-pos; +-nonneg; +-pos; mul-div-cancel;
         div-le-of-le-mul; le-div-of-mul-le)

-- ---------------------------------------------------------------------------------------------
-- A slot and the two estimates

-- A row: the actual audience of one channel in the slot, and its independent forecast.
Row : Set
Row = ℚ × ℚ

err : Row → ℚ
err (y , f) = f - y

sumRows : (Row → ℚ) → List Row → ℚ
sumRows g []       = 0ℚ
sumRows g (r ∷ rs) = g r + sumRows g rs

-- The squared error of the slot, the actual total T, and the sum of the forecasts.
sse total fsum : List Row → ℚ
sse   = sumRows (λ r → err r * err r)
total = sumRows proj₁
fsum  = sumRows proj₂

-- S: how far the independent forecasts are from the actual total.
bias : List Row → ℚ
bias rs = fsum rs - total rs

-- ε: how far the pool forecast p is from the actual total.
poolErr : ℚ → List Row → ℚ
poolErr p rs = p - total rs

-- How far the independent forecasts are from the pool forecast, and the step that every
-- channel takes, (Σ f - p) / C.
gap : ℚ → List Row → ℚ
gap p rs = fsum rs - p

step : ℚ → List Row → ℚ
step p rs = gap p rs /₀ size rs

shiftRow : ℚ → Row → Row
shiftRow k (y , f) = (y , f - k)

-- The joint estimate: every forecast moved by the same step.
reconcile : ℚ → List Row → List Row
reconcile p rs = map (shiftRow (step p rs)) rs

-- ---------------------------------------------------------------------------------------------
-- Sums after a shift

private
  sse-shift : ∀ k rs →
    sse (map (shiftRow k) rs) ≡ sse rs - (k + k) * sumRows err rs + k * k * size rs
  sse-shift k [] = solve 1 (λ k → con 0ℚ := con 0ℚ :- (k :+ k) :* con 0ℚ :+ k :* k :* con 0ℚ) refl k
  sse-shift k ((y , f) ∷ rs) =
    trans (cong (((f - k) - y) * ((f - k) - y) +_) (sse-shift k rs))
      (solve 6 (λ k y f s e n →
                  ((f :- k) :- y) :* ((f :- k) :- y) :+ (s :- (k :+ k) :* e :+ k :* k :* n)
                  := ((f :- y) :* (f :- y) :+ s) :- (k :+ k) :* ((f :- y) :+ e)
                     :+ k :* k :* (con 1ℚ :+ n))
        refl k y f (sse rs) (sumRows err rs) (size rs))

  fsum-shift : ∀ k rs → fsum (map (shiftRow k) rs) ≡ fsum rs - k * size rs
  fsum-shift k [] = solve 1 (λ k → con 0ℚ := con 0ℚ :- k :* con 0ℚ) refl k
  fsum-shift k ((y , f) ∷ rs) =
    trans (cong ((f - k) +_) (fsum-shift k rs))
      (solve 4 (λ k f s n → (f :- k) :+ (s :- k :* n) := (f :+ s) :- k :* (con 1ℚ :+ n))
        refl k f (fsum rs) (size rs))

  errs-bias : ∀ rs → sumRows err rs ≡ bias rs
  errs-bias [] = refl
  errs-bias ((y , f) ∷ rs) =
    trans (cong ((f - y) +_) (errs-bias rs))
      (solve 4 (λ y f a b → (f :- y) :+ (b :- a) := (f :+ b) :- (y :+ a)) refl y f (total rs) (fsum rs))

  sumRows-ge : ∀ t rs → All (λ r → t ≤ err r) rs → t * size rs ≤ sumRows err rs
  sumRows-ge t []       []         = ≤-reflexive (*-zeroʳ t)
  sumRows-ge t (r ∷ rs) (h ∷ hs) =
    ≤-trans (≤-reflexive (solve 2 (λ k n → k :* (con 1ℚ :+ n) := k :+ k :* n) refl t (size rs)))
            (+-mono-≤ h (sumRows-ge t rs hs))

  sumRows-le : ∀ t rs → All (λ r → err r ≤ t) rs → sumRows err rs ≤ t * size rs
  sumRows-le t []       []         = ≤-reflexive (sym (*-zeroʳ t))
  sumRows-le t (r ∷ rs) (h ∷ hs) =
    ≤-trans (+-mono-≤ h (sumRows-le t rs hs))
            (≤-reflexive (solve 2 (λ k n → k :+ k :* n := k :* (con 1ℚ :+ n)) refl t (size rs)))

  -- Order facts
  pos-diff : ∀ {a b} → a < b → 0ℚ < b - a
  pos-diff {a} {b} h = subst (_< b - a) (+-inverseʳ a) (+-monoˡ-< (- a) h)

  sq-abs : ∀ x → ∣ x ∣ * ∣ x ∣ ≡ x * x
  sq-abs x = trans (sym (∣p*q∣≡∣p∣*∣q∣ x x)) (0≤p⇒∣p∣≡p (sq-nonneg x))

  sq-le : ∀ {a b} → ∣ a ∣ ≤ ∣ b ∣ → a * a ≤ b * b
  sq-le {a} {b} h = subst₂ _≤_ (sq-abs a) (sq-abs b) (mul-le-mul′ h h (0≤∣p∣ a) (0≤∣p∣ a))

  sq-lt : ∀ {a b} → ∣ a ∣ < ∣ b ∣ → 0ℚ < b * b - a * a
  sq-lt {a} {b} h =
    subst (0ℚ <_) eq (*-pos (pos-diff h) (+-pos (≤-<-trans (0≤∣p∣ a) h) (0≤∣p∣ a)))
    where
    eq : (∣ b ∣ - ∣ a ∣) * (∣ b ∣ + ∣ a ∣) ≡ b * b - a * a
    eq = trans (solve 2 (λ x y → (y :- x) :* (y :+ x) := y :* y :- x :* x) refl ∣ a ∣ ∣ b ∣)
               (cong₂ _-_ (sq-abs b) (sq-abs a))

  inv-cancel : ∀ c x → 0ℚ < c → inv₀ c * (c * x) ≡ x
  inv-cancel c x hc =
    trans (solve 3 (λ i c x → i :* (c :* x) := (c :* i) :* x) refl (inv₀ c) c x)
      (trans (cong (_* x) (inv₀-inverse c (<⇒≢0 hc))) (*-identityˡ x))

  cancel-nonneg : ∀ {c x} → 0ℚ < c → 0ℚ ≤ c * x → 0ℚ ≤ x
  cancel-nonneg {c} {x} hc h = subst (0ℚ ≤_) (inv-cancel c x hc) (*-nonneg (<⇒≤ (inv₀-pos hc)) h)

  cancel-pos : ∀ {c x} → 0ℚ < c → 0ℚ < c * x → 0ℚ < x
  cancel-pos {c} {x} hc h = subst (0ℚ <_) (inv-cancel c x hc) (*-pos (inv₀-pos hc) h)

-- ---------------------------------------------------------------------------------------------
-- The joint estimate is coherent

reconcile-coherent : ∀ p r rs → fsum (reconcile p (r ∷ rs)) ≡ p
reconcile-coherent p r rs =
  trans (fsum-shift k xs)
    (trans (cong (λ z → fsum xs - z) (trans (*-comm k (size xs)) (mul-div-cancel (gap p xs) (<⇒≢0 (size-cons-pos r rs)))))
      (solve 2 (λ f p → f :- (f :- p) := p) refl (fsum xs) p))
  where
  xs = r ∷ rs
  k  = step p xs

-- ---------------------------------------------------------------------------------------------
-- The gain, exactly

joint-gain : ∀ p r rs →
  size (r ∷ rs) * (sse (r ∷ rs) - sse (reconcile p (r ∷ rs)))
    ≡ bias (r ∷ rs) * bias (r ∷ rs) - poolErr p (r ∷ rs) * poolErr p (r ∷ rs)
joint-gain p r rs =
  trans (cong (λ z → C * (s - z)) (sse-shift k xs))
   (trans (solve 4 (λ c k s e → c :* (s :- (s :- (k :+ k) :* e :+ k :* k :* c))
                              := (c :* k :+ c :* k) :* e :- (c :* k) :* (c :* k)) refl C k s E)
    (trans (cong (λ d → (d + d) * E - d * d) ck)
     (trans (cong (λ e → (d₀ + d₀) * e - d₀ * d₀) (errs-bias xs))
       (solve 3 (λ f t p → ((f :- p) :+ (f :- p)) :* (f :- t) :- (f :- p) :* (f :- p)
                          := (f :- t) :* (f :- t) :- (p :- t) :* (p :- t))
         refl (fsum xs) (total xs) p))))
  where
  xs = r ∷ rs
  C  = size xs
  k  = step p xs
  s  = sse xs
  E  = sumRows err xs
  d₀ = gap p xs
  ck : C * k ≡ d₀
  ck = mul-div-cancel d₀ (<⇒≢0 (size-cons-pos r rs))

-- ---------------------------------------------------------------------------------------------
-- When joint is better

-- Not worse, whenever the pool forecast is not worse than the sum of the channel forecasts.
-- An empty slot has nothing to move, so the statement holds for every list.
joint-le : ∀ p rs → ∣ poolErr p rs ∣ ≤ ∣ bias rs ∣ → sse (reconcile p rs) ≤ sse rs
joint-le p []       _ = ≤-refl
joint-le p (r ∷ rs) h =
  by-diff _ refl (cancel-nonneg (size-cons-pos r rs)
    (subst (0ℚ ≤_) (sym (joint-gain p r rs)) (≤⇒0≤- (sq-le h))))

-- Strictly better, whenever the pool forecast is strictly better.
joint-lt : ∀ p r rs → ∣ poolErr p (r ∷ rs) ∣ < ∣ bias (r ∷ rs) ∣ →
  sse (reconcile p (r ∷ rs)) < sse (r ∷ rs)
joint-lt p r rs h =
  by-diff< _ refl (cancel-pos (size-cons-pos r rs)
    (subst (0ℚ <_) (sym (joint-gain p r rs)) (sq-lt h)))

-- With the actual pool, every slot whose channel forecasts do not add up to it gains.
joint-known : ∀ r rs → bias (r ∷ rs) ≢ 0ℚ →
  sse (reconcile (total (r ∷ rs)) (r ∷ rs)) < sse (r ∷ rs)
joint-known r rs ne = joint-lt (total xs) r rs
  (subst (λ z → ∣ z ∣ < ∣ bias xs ∣) (sym (+-inverseʳ (total xs)))
    (≤∧≢⇒< (0≤∣p∣ (bias xs)) (λ eq → ne (∣p∣≡0⇒p≡0 (bias xs) (sym eq)))))
  where xs = r ∷ rs

-- A common over-forecast of at least δ on every channel: the gain, times C, is at least
-- (C δ)² - η². With an exact pool (η = 0) the gain is at least C δ².
joint-common-bias : ∀ p r rs δ η → 0ℚ ≤ δ → All (λ x → δ ≤ err x) (r ∷ rs) →
  ∣ poolErr p (r ∷ rs) ∣ ≤ η →
  (size (r ∷ rs) * δ) * (size (r ∷ rs) * δ) - η * η
    ≤ size (r ∷ rs) * (sse (r ∷ rs) - sse (reconcile p (r ∷ rs)))
joint-common-bias p r rs δ η hδ hs hη =
  subst (lhs ≤_) (sym (joint-gain p r rs))
    (by-diff _ (solve 4 (λ s q a b → (s :- q) :- (a :- b) := (s :- a) :+ (b :- q))
                  refl (S * S) (ε * ε) (Cδ * Cδ) (η * η))
      (+-nonneg (≤⇒0≤- (mul-le-mul′ hS hS hCδ hCδ))
                (≤⇒0≤- (subst (_≤ η * η) (sq-abs ε) (mul-le-mul′ hη hη (0≤∣p∣ ε) (0≤∣p∣ ε))))))
  where
  xs  = r ∷ rs
  S   = bias xs
  ε   = poolErr p xs
  Cδ  = size xs * δ
  lhs = Cδ * Cδ - η * η
  hCδ : 0ℚ ≤ Cδ
  hCδ = *-nonneg (<⇒≤ (size-cons-pos r rs)) hδ
  hS : Cδ ≤ S
  hS = subst₂ _≤_ (*-comm δ (size xs)) (errs-bias xs) (sumRows-ge δ xs hs)

-- ---------------------------------------------------------------------------------------------
-- Per channel

recErr : ∀ k r → err (shiftRow k r) ≡ err r - k
recErr k (y , f) = solve 3 (λ k y f → (f :- k) :- y := (f :- y) :- k) refl k y f

InBand : ℚ → ℚ → Row → Set
InBand lo hi r = lo ≤ err r × err r ≤ hi

-- With the actual pool, and every channel over-forecast by an amount in [lo, hi] with
-- hi ≤ 2 lo: no row in that band has a larger absolute error after the joint step. Every row
-- of the slot is in the band, so no channel of the slot gets worse.
channel-no-worse : ∀ r rs lo hi → 0ℚ ≤ lo → hi ≤ lo + lo → All (InBand lo hi) (r ∷ rs) →
  ∀ a → InBand lo hi a →
  ∣ err (shiftRow (step (total (r ∷ rs)) (r ∷ rs)) a) ∣ ≤ ∣ err a ∣
channel-no-worse r rs lo hi h0 h2 hs a (alo , ahi) =
  subst₂ _≤_ (cong ∣_∣ (sym (recErr m a))) (sym (0≤p⇒∣p∣≡p e≥0)) core
  where
  xs = r ∷ rs
  C  = size xs
  m  = step (total xs) xs
  e  = err a
  e≥0 : 0ℚ ≤ e
  e≥0 = ≤-trans h0 alo
  m≥lo : lo ≤ m
  m≥lo = le-div-of-mul-le (size-cons-pos r rs)
           (subst (lo * C ≤_) (errs-bias xs) (sumRows-ge lo xs (All.map proj₁ hs)))
  m≤hi : m ≤ hi
  m≤hi = div-le-of-le-mul (size-cons-pos r rs)
           (subst (_≤ hi * C) (errs-bias xs) (sumRows-le hi xs (All.map proj₂ hs)))
  m≤2e : m ≤ e + e
  m≤2e = ≤-trans m≤hi (≤-trans h2 (+-mono-≤ alo alo))
  core : ∣ e - m ∣ ≤ e
  core with ∣p∣≡p∨∣p∣≡-p (e - m)
  ... | inj₁ eq = subst (_≤ e) (sym eq)
                    (by-diff m (solve 2 (λ e m → e :- (e :- m) := m) refl e m) (≤-trans h0 m≥lo))
  ... | inj₂ eq = subst (_≤ e) (sym eq)
                    (by-diff _ (solve 2 (λ e m → e :- (:- (e :- m)) := (e :+ e) :- m) refl e m)
                      (≤⇒0≤- m≤2e))

-- ---------------------------------------------------------------------------------------------
-- When it is cheap enough

-- With a cost of each method in the unit of squared error: the joint method has the lower
-- error plus cost when C times its extra cost is at most S² - ε².
joint-worth : ∀ p r rs cAlone cJoint →
  size (r ∷ rs) * (cJoint - cAlone) ≤ bias (r ∷ rs) * bias (r ∷ rs) - poolErr p (r ∷ rs) * poolErr p (r ∷ rs) →
  sse (reconcile p (r ∷ rs)) + cJoint ≤ sse (r ∷ rs) + cAlone
joint-worth p r rs cA cJ h =
  by-diff _ refl (cancel-nonneg (size-cons-pos r rs) (subst (0ℚ ≤_) eq (≤⇒0≤- h)))
  where
  xs = r ∷ rs
  C  = size xs
  eq : (bias xs * bias xs - poolErr p xs * poolErr p xs) - C * (cJ - cA)
       ≡ C * ((sse xs + cA) - (sse (reconcile p xs) + cJ))
  eq = trans (cong (_- C * (cJ - cA)) (sym (joint-gain p r rs)))
         (solve 5 (λ c s q i j → c :* (s :- q) :- c :* (j :- i) := c :* ((s :+ i) :- (q :+ j)))
           refl C (sse xs) (sse (reconcile p xs)) cA cJ)

-- ---------------------------------------------------------------------------------------------
-- Over many slots

-- A slot of the test set: its pool forecast and its rows.
Slot : Set
Slot = ℚ × List Row

sseAlone sseJoint : List Slot → ℚ
sseAlone []              = 0ℚ
sseAlone ((p , rs) ∷ ss) = sse rs + sseAlone ss
sseJoint []              = 0ℚ
sseJoint ((p , rs) ∷ ss) = sse (reconcile p rs) + sseJoint ss

PoolNotWorse : Slot → Set
PoolNotWorse (p , rs) = ∣ poolErr p rs ∣ ≤ ∣ bias rs ∣

joint-total : ∀ ss → All PoolNotWorse ss → sseJoint ss ≤ sseAlone ss
joint-total []              []       = ≤-refl
joint-total ((p , rs) ∷ ss) (h ∷ hs) = +-mono-≤ (joint-le p rs h) (joint-total ss hs)
