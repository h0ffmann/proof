{-# OPTIONS --safe --without-K #-}

-- The rounding facts of group D of the port audit of chaceon
-- (`z3-scala/src/main/scala/portaudit/domain/Chaceon.scala`, `just port-audit`), over ℚ. The
-- names follow Z3, with `-` for `_`.
--
-- * same_side: an f64 quotient r within ε q of the exact quotient q, which keeps a distance
--   δ m from the f32 midpoint m, is on the same side of m as q. So rounding r to f32 gives the
--   f32 rounding of q. Z3 checks it for δ = 2^-49 and ε = 5/2 * 2^-52 (Vulkan's 2.5 ULP on
--   f64). Agda proves it for every δ > 0 and 0 ≤ ε ≤ 1 with (1 - δ)(1 + ε) < 1 and
--   1 < (1 + δ)(1 - ε), and then reads it at Z3's numbers.
-- * same_side_8ulp_fails: with ε = 8 * 2^-52 = δ the statement fails. A witness.
-- * closer_lo: round to nearest between two adjacent grid points is the comparison with the
--   midpoint.
--
-- Z3 writes m / 2^49 and q * 5 / 2 / 2^52. Here they are m * δ and q * ε, with δ and ε the
-- rational constants.
module PortAudit.Rounding where

open import Data.Integer using (+_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _/_; _+_; _-_; _*_; _≤_; _<_; Positive; NonNegative)
open import Data.Rational.Base using (positive; nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-<-trans; <⇒≤; ≮⇒≥; <⇒≢; <-irrefl; <-asym; _<?_; _≤?_;
         *-monoˡ-≤-nonNeg; *-monoʳ-≤-nonNeg; *-monoʳ-<-pos; *-identityʳ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Function using (_⇔_; mk⇔)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl; sym; trans; subst)
open import Relation.Nullary using (Dec; yes; no; ¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes)

open import OceanWaves.Order using (by-diff; by-diff<; ≤⇒0≤-; <⇒0<-; *-nonneg)

private
  -- From a bound on a difference to a bound on the value.
  below : ∀ m q d → m * d ≤ m - q → q ≤ m * (1ℚ - d)
  below m q d h = by-diff (m - q - m * d) (solve 3 (λ m q d → m :* (con 1ℚ :- d) :- q
                                                    := m :- q :- m :* d) refl m q d) (≤⇒0≤- h)

  above : ∀ m q d → m * d ≤ q - m → m * (1ℚ + d) ≤ q
  above m q d h = by-diff (q - m - m * d) (solve 3 (λ m q d → q :- m :* (con 1ℚ :+ d)
                                                    := q :- m :- m :* d) refl m q d) (≤⇒0≤- h)

  up-to : ∀ q r e → r - q ≤ q * e → r ≤ q * (1ℚ + e)
  up-to q r e h = by-diff (q * e - (r - q)) (solve 3 (λ q r e → q :* (con 1ℚ :+ e) :- r
                                                       := q :* e :- (r :- q)) refl q r e) (≤⇒0≤- h)

  down-to : ∀ q r e → q - r ≤ q * e → q * (1ℚ - e) ≤ r
  down-to q r e h = by-diff (q * e - (q - r)) (solve 3 (λ q r e → r :- q :* (con 1ℚ :- e)
                                                         := q :* e :- (q :- r)) refl q r e) (≤⇒0≤- h)

  scale< : ∀ m c → 0ℚ < m → c < 1ℚ → m * c < m
  scale< m c 0<m c<1 = subst (m * c <_) (*-identityʳ m) (*-monoʳ-<-pos m {{positive 0<m}} c<1)

  scale> : ∀ m c → 0ℚ < m → 1ℚ < c → m < m * c
  scale> m c 0<m 1<c = subst (_< m * c) (*-identityʳ m) (*-monoʳ-<-pos m {{positive 0<m}} 1<c)

  nonneg : ∀ {x} → 0ℚ ≤ x → NonNegative x
  nonneg = nonNegative

  grow : ∀ q e → 0ℚ ≤ q → 0ℚ ≤ e → q ≤ q * (1ℚ + e)
  grow q e 0≤q 0≤e = by-diff (q * e) (solve 2 (λ q e → q :* (con 1ℚ :+ e) :- q := q :* e) refl q e)
                       (*-nonneg 0≤q 0≤e)

  shrink : ∀ q e → 0ℚ ≤ q → 0ℚ ≤ e → q * (1ℚ - e) ≤ q
  shrink q e 0≤q 0≤e = by-diff (q * e) (solve 2 (λ q e → q :- q :* (con 1ℚ :- e) := q :* e) refl q e)
                         (*-nonneg 0≤q 0≤e)

-- The premises of same_side, for error bounds δ (the margin) and ε (the f64 error).
record Bounds (δ ε : ℚ) : Set where
  field
    0≤ε    : 0ℚ ≤ ε
    ε≤1    : ε ≤ 1ℚ
    lower  : (1ℚ - δ) * (1ℚ + ε) < 1ℚ
    upper  : 1ℚ < (1ℚ + δ) * (1ℚ - ε)

module _ {δ ε : ℚ} (b : Bounds δ ε) {q m r : ℚ} (0<q : 0ℚ < q) (0<m : 0ℚ < m)
         (apart : m * δ ≤ q - m ⊎ m * δ ≤ m - q)
         (err₁ : r - q ≤ q * ε) (err₂ : q - r ≤ q * ε) where
  open Bounds b

  private
    0≤1+ε : 0ℚ ≤ 1ℚ + ε
    0≤1+ε = ≤-trans 0≤ε (by-diff 1ℚ (solve 1 (λ e → con 1ℚ :+ e :- e := con 1ℚ) refl ε)
                                     (from-yes (0ℚ ≤? 1ℚ)))
    0≤1-ε : 0ℚ ≤ 1ℚ - ε
    0≤1-ε = ≤⇒0≤- ε≤1

    -- q below the midpoint: r < m and q < m.
    left : m * δ ≤ m - q → r < m × q < m
    left h = r<m , q<m
      where
      q≤ : q ≤ m * (1ℚ - δ)
      q≤ = below m q δ h
      rq : r ≤ q * (1ℚ + ε)
      rq = up-to q r ε err₁
      bound : m * (1ℚ - δ) * (1ℚ + ε) < m
      bound = subst (_< m) (solve 3 (λ m d e → m :* ((con 1ℚ :- d) :* (con 1ℚ :+ e))
                                    := m :* (con 1ℚ :- d) :* (con 1ℚ :+ e)) refl m δ ε)
                (scale< m _ 0<m lower)
      r<m : r < m
      r<m = ≤-<-trans rq (≤-<-trans (*-monoʳ-≤-nonNeg (1ℚ + ε) {{nonneg 0≤1+ε}} q≤) bound)
      q<m : q < m
      q<m = ≤-<-trans (grow q ε (<⇒≤ 0<q) 0≤ε)
                      (≤-<-trans (*-monoʳ-≤-nonNeg (1ℚ + ε) {{nonneg 0≤1+ε}} q≤) bound)

    -- q above the midpoint: m < r and m < q.
    right : m * δ ≤ q - m → m < r × m < q
    right h = m<r , m<q
      where
      q≥ : m * (1ℚ + δ) ≤ q
      q≥ = above m q δ h
      rq : q * (1ℚ - ε) ≤ r
      rq = down-to q r ε err₂
      bound : m < m * (1ℚ + δ) * (1ℚ - ε)
      bound = subst (m <_) (solve 3 (λ m d e → m :* ((con 1ℚ :+ d) :* (con 1ℚ :- e))
                                    := m :* (con 1ℚ :+ d) :* (con 1ℚ :- e)) refl m δ ε)
                (scale> m _ 0<m upper)
      m<q′ : m < q * (1ℚ - ε)
      m<q′ = <-≤-trans bound (*-monoʳ-≤-nonNeg (1ℚ - ε) {{nonneg 0≤1-ε}} q≥)
      m<r : m < r
      m<r = <-≤-trans m<q′ rq
      m<q : m < q
      m<q = <-≤-trans m<q′ (shrink q ε (<⇒≤ 0<q) 0≤ε)

  private
    sides : m * δ ≤ q - m ⊎ m * δ ≤ m - q → (r < m) ⇔ (q < m)
    sides (inj₂ h) = mk⇔ (λ _ → proj₂ (left h)) (λ _ → proj₁ (left h))
    sides (inj₁ h) = mk⇔ (λ r<m → contradiction r<m (<-asym (proj₁ (right h))))
                         (λ q<m → contradiction q<m (<-asym (proj₂ (right h))))

    apart′ : m * δ ≤ q - m ⊎ m * δ ≤ m - q → r ≢ m × q ≢ m
    apart′ (inj₂ h) = <⇒≢ (proj₁ (left h)) , <⇒≢ (proj₂ (left h))
    apart′ (inj₁ h) = (λ eq → <⇒≢ (proj₁ (right h)) (sym eq)) , (λ eq → <⇒≢ (proj₂ (right h)) (sym eq))

  same-side : (r < m) ⇔ (q < m)
  same-side = sides apart

  same-side-not-tie : r ≢ m × q ≢ m
  same-side-not-tie = apart′ apart

-- ---------------------------------------------------------------------------------------------
-- At Z3's numbers: δ = 2^-49 (the margin of `margin`) and ε = 5/2 * 2^-52 (Vulkan's 2.5 ULP
-- on f64).

δ₄₉ : ℚ
δ₄₉ = + 1 / 2 ^ 49
  where open import Data.Nat using (_^_)

ε-vulkan : ℚ
ε-vulkan = + 5 / 2 ^ 53
  where open import Data.Nat using (_^_)

z3-bounds : Bounds δ₄₉ ε-vulkan
z3-bounds = record
  { 0≤ε   = from-yes (0ℚ ≤? ε-vulkan)
  ; ε≤1   = from-yes (ε-vulkan ≤? 1ℚ)
  ; lower = from-yes ((1ℚ - δ₄₉) * (1ℚ + ε-vulkan) <? 1ℚ)
  ; upper = from-yes (1ℚ <? (1ℚ + δ₄₉) * (1ℚ - ε-vulkan))
  }

-- same_side and same_side_not_tie, as Z3 states them.
same-side-z3 : ∀ {q m r} → 0ℚ < q → 0ℚ < m → (m * δ₄₉ ≤ q - m ⊎ m * δ₄₉ ≤ m - q) →
  r - q ≤ q * ε-vulkan → q - r ≤ q * ε-vulkan → (r < m) ⇔ (q < m)
same-side-z3 = same-side z3-bounds

same-side-not-tie-z3 : ∀ {q m r} → 0ℚ < q → 0ℚ < m → (m * δ₄₉ ≤ q - m ⊎ m * δ₄₉ ≤ m - q) →
  r - q ≤ q * ε-vulkan → q - r ≤ q * ε-vulkan → r ≢ m × q ≢ m
same-side-not-tie-z3 = same-side-not-tie z3-bounds

-- same_side_8ulp_fails, as a witness: an error of 8 * 2^-52 = 2^-49 reaches the margin and can
-- cross the midpoint. With m = 1 and q = 1 + 2^-49, r = q (1 - 2^-49) = 1 - 2^-98 is below m,
-- and q is above it.
ε-8ulp : ℚ
ε-8ulp = + 8 / 2 ^ 52
  where open import Data.Nat using (_^_)

same-side-8ulp-fails :
  let m = 1ℚ ; q = 1ℚ + δ₄₉ ; r = q * (1ℚ - δ₄₉) in
  (0ℚ < q × 0ℚ < m × m * δ₄₉ ≤ q - m × r - q ≤ q * ε-8ulp × q - r ≤ q * ε-8ulp) ×
  r < m × m < q
same-side-8ulp-fails =
  (from-yes (0ℚ <? q) , from-yes (0ℚ <? 1ℚ) , from-yes (1ℚ * δ₄₉ ≤? q - 1ℚ) ,
   from-yes (r - q ≤? q * ε-8ulp) , from-yes (q - r ≤? q * ε-8ulp)) ,
  from-yes (r <? 1ℚ) , from-yes (1ℚ <? q)
  where
  q = 1ℚ + δ₄₉
  r = q * (1ℚ - δ₄₉)

-- ---------------------------------------------------------------------------------------------
-- closer_lo: between adjacent grid points lo < hi, x is closer to lo exactly when it is below
-- the midpoint.

-- Z3's dist(u, v) = ite(u >= v, u - v, v - u), as a function of the answer.
distD : (u v : ℚ) → Dec (v ≤ u) → ℚ
distD u v (yes _) = u - v
distD u v (no _)  = v - u

dist : ℚ → ℚ → ℚ
dist u v = distD u v (v ≤? u)

½ : ℚ
½ = + 1 / 2

closer-lo : ∀ lo hi x → lo < hi → (dist x lo < dist x hi) ⇔ (x < (lo + hi) * ½)
closer-lo lo hi x lo<hi = go (lo ≤? x) (hi ≤? x)
  where
  open import OceanWaves.Order using (*-pos)
  mid = (lo + hi) * ½
  0<½ : 0ℚ < ½
  0<½ = from-yes (0ℚ <? ½)
  0<hl : 0ℚ < hi - lo
  0<hl = <⇒0<- lo<hi
  lo<mid : lo < mid
  lo<mid = by-diff< ((hi - lo) * ½) (solve 2 (λ l h → (l :+ h) :* con ½ :- l := (h :- l) :* con ½)
                                      refl lo hi) (*-pos 0<hl 0<½)
  mid<hi : mid < hi
  mid<hi = by-diff< ((hi - lo) * ½) (solve 2 (λ l h → h :- (l :+ h) :* con ½ := (h :- l) :* con ½)
                                      refl lo hi) (*-pos 0<hl 0<½)
  go : (d₁ : Dec (lo ≤ x)) (d₂ : Dec (hi ≤ x)) → (distD x lo d₁ < distD x hi d₂) ⇔ (x < mid)
  go (yes _) (yes hi≤x) = mk⇔ (λ p → contradiction p (<-asym far)) (λ p → contradiction p (<-asym mid<x))
    where
    far : x - hi < x - lo
    far = by-diff< (hi - lo) (solve 3 (λ x l h → x :- l :- (x :- h) := h :- l) refl x lo hi) 0<hl
    mid<x : mid < x
    mid<x = <-≤-trans mid<hi hi≤x
  go (yes _) (no _) = mk⇔ to from
    where
    eq : (hi - x - (x - lo)) * ½ ≡ mid - x
    eq = solve 3 (λ x l h → (h :- x :- (x :- l)) :* con ½ := (l :+ h) :* con ½ :- x) refl x lo hi
    to : x - lo < hi - x → x < mid
    to p = by-diff< ((hi - x - (x - lo)) * ½) (sym eq) (*-pos (<⇒0<- p) 0<½)
    from : x < mid → x - lo < hi - x
    from p = by-diff< ((mid - x) * (1ℚ + 1ℚ))
               (solve 3 (λ x l h → h :- x :- (x :- l) := ((l :+ h) :* con ½ :- x) :* (con 1ℚ :+ con 1ℚ))
                  refl x lo hi)
               (*-pos (<⇒0<- p) (from-yes (0ℚ <? 1ℚ + 1ℚ)))
  go (no ¬lo≤x) (yes hi≤x) =
    contradiction (<-≤-trans (<-trans′ (≰⇒>′ ¬lo≤x) lo<hi) hi≤x) (<-irrefl refl)
    where open import Data.Rational.Properties using () renaming (<-trans to <-trans′; ≰⇒> to ≰⇒>′)
  go (no ¬lo≤x) (no _) = mk⇔ (λ _ → <-trans′ x<lo lo<mid) (λ _ → near)
    where
    open import Data.Rational.Properties using () renaming (<-trans to <-trans′; ≰⇒> to ≰⇒>′)
    x<lo : x < lo
    x<lo = ≰⇒>′ ¬lo≤x
    near : lo - x < hi - x
    near = by-diff< (hi - lo) (solve 3 (λ x l h → h :- x :- (l :- x) := h :- l) refl x lo hi) 0<hl
