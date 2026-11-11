{-# OPTIONS --safe --without-K #-}

-- The linear dispersion relation, phase speed and group velocity. Ported from
-- `ocean-waves/lean/OceanWaves/Dispersion.lean`. The names follow Lean, with `-` for `_`.
--
-- Linear (Airy) theory for surface gravity waves on water of depth h gives
--
--     σ² = g k tanh(k h)                         (dispersion relation)
--     c  = σ / k                                 (phase speed)
--     c_g = n c,  n = ½ (1 + 2kh / sinh(2kh))    (group velocity)
--
-- There are no real numbers and no tanh here, as in Lean. A `TanhModel` is any function with
-- the properties of tanh on [0, ∞) that the proofs use, and every theorem holds for every
-- model. `padeModel` is a concrete rational model: the clamped [3/2] Padé approximant.
-- `sinh` is avoided with the identity 2x / sinh(2x) = x (1 - tanh² x) / tanh x.
--
-- Differences from Lean: `σ / k` is `σ /₀ k` (Lean's total division, `Order.agda`), and an
-- equality of fractions such as (σ/k)² = σ²/k² is not used: the proofs multiply by the
-- inverse and cancel it, because inv₀ (k * k) and inv₀ k * inv₀ k are not equal by the ring
-- solver.
module OceanWaves.Dispersion where

open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_; _≟_; _≤?_; _<?_)
open import Data.Rational.Base using (nonNegative; positive)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-<-trans; <⇒≤; ≤-reflexive; ≤-antisym; ≰⇒>; <-irrefl;
         *-monoʳ-≤-nonNeg; *-monoˡ-≤-nonNeg; *-monoˡ-<-pos; *-monoʳ-<-pos; *-identityʳ;
         *-identityˡ)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary using (Dec; yes; no; contradiction)
open import Relation.Nullary.Decidable using (from-yes)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; subst; subst₂)

open import OceanWaves.Order

-- The properties of tanh on [0, ∞) that the dispersion proofs use.
record TanhModel : Set where
  field
    T        : ℚ → ℚ
    T-zero   : T 0ℚ ≡ 0ℚ
    -- T is positive for positive arguments.
    pos      : ∀ x → 0ℚ < x → 0ℚ < T x
    -- T is monotone on [0, ∞).
    mono     : ∀ x y → 0ℚ ≤ x → x ≤ y → T x ≤ T y
    -- T x ≤ x (true for tanh: shallow water is the fastest limit).
    le-id    : ∀ x → 0ℚ ≤ x → T x ≤ x
    -- T x ≤ 1 (the deep-water limit).
    le-one   : ∀ x → 0ℚ ≤ x → T x ≤ 1ℚ
    -- x (1 - T² x) ≤ T x, the same as 2x ≤ sinh 2x for tanh. It gives n ≤ 1.
    sech-bound : ∀ x → 0ℚ < x → x * (1ℚ - T x * T x) ≤ T x
    -- A depth-scaled argument after which T = 1. The true tanh does not have it; it gives
    -- the dispersion solver a starting bracket.
    sat      : ℚ
    sat-pos  : 0ℚ < sat
    T-sat    : ∀ x → sat ≤ x → T x ≡ 1ℚ

  nonneg : ∀ x → 0ℚ ≤ x → 0ℚ ≤ T x
  nonneg x hx with x ≟ 0ℚ
  ... | yes refl = ≤-reflexive (sym T-zero)
  ... | no  x≢0  = <⇒≤ (pos x (≤∧≢⇒< hx (λ eq → x≢0 (sym eq))))

-- The physical setting: gravity and water depth, both positive.
record Medium : Set where
  field
    g     : ℚ
    h     : ℚ
    g-pos : 0ℚ < g
    h-pos : 0ℚ < h

module _ (M : TanhModel) (W : Medium) where
  open TanhModel M
  open Medium W

  -- σ²(k) = g k T(k h). σ² is kept, because ℚ has no square root.
  sigma2 : ℚ → ℚ
  sigma2 k = g * k * T (k * h)

  sigma2-nonneg : ∀ {k} → 0ℚ ≤ k → 0ℚ ≤ sigma2 k
  sigma2-nonneg {k} hk = *-nonneg (*-nonneg (<⇒≤ g-pos) hk) (nonneg _ (*-nonneg hk (<⇒≤ h-pos)))

  -- Dispersion is strictly increasing in k. So each frequency has at most one wavenumber, and
  -- bisection finds it.
  sigma2-strictMono : ∀ {k₁ k₂} → 0ℚ ≤ k₁ → k₁ < k₂ → sigma2 k₁ < sigma2 k₂
  sigma2-strictMono {k₁} {k₂} h0 h12 =
    ≤-<-trans (*-monoˡ-≤-nonNeg (g * k₁) {{nonNegative (*-nonneg (<⇒≤ g-pos) h0)}} hT)
              (*-monoˡ-<-pos (T (k₂ * h)) {{positive hT2}} (*-monoʳ-<-pos g {{positive g-pos}} h12))
    where
    0≤k₂ = ≤-trans h0 (<⇒≤ h12)
    hT : T (k₁ * h) ≤ T (k₂ * h)
    hT = mono _ _ (*-nonneg h0 (<⇒≤ h-pos)) (*-monoʳ-≤-nonNeg h {{nonNegative (<⇒≤ h-pos)}} (<⇒≤ h12))
    hT2 : 0ℚ < T (k₂ * h)
    hT2 = pos _ (*-pos (≤-<-trans h0 h12) h-pos)

  -- The deep-water bound: σ² ≤ g k.
  sigma2-le-deep : ∀ {k} → 0ℚ ≤ k → sigma2 k ≤ g * k
  sigma2-le-deep {k} hk =
    ≤-trans (*-monoˡ-≤-nonNeg (g * k) {{nonNegative (*-nonneg (<⇒≤ g-pos) hk)}}
               (le-one _ (*-nonneg hk (<⇒≤ h-pos))))
            (≤-reflexive (*-identityʳ (g * k)))

  -- The shallow-water bound: σ² ≤ g h k².
  sigma2-le-shallow : ∀ {k} → 0ℚ ≤ k → sigma2 k ≤ g * h * (k * k)
  sigma2-le-shallow {k} hk =
    ≤-trans (*-monoˡ-≤-nonNeg (g * k) {{nonNegative (*-nonneg (<⇒≤ g-pos) hk)}}
               (le-id _ (*-nonneg hk (<⇒≤ h-pos))))
            (≤-reflexive (solve 3 (λ g k h → g :* k :* (k :* h) := g :* h :* (k :* k)) refl g k h))

  -- In the saturated regime (k h ≥ sat) dispersion is exactly the deep-water law.
  sigma2-deep-exact : ∀ {k} → sat ≤ k * h → sigma2 k ≡ g * k
  sigma2-deep-exact {k} hk = trans (cong (g * k *_) (T-sat _ hk)) (*-identityʳ (g * k))

  -- -------------------------------------------------------------------------------------------
  -- Phase speed and group velocity

  -- The phase speed c = σ / k.
  phaseSpeed : ℚ → ℚ → ℚ
  phaseSpeed σ k = σ /₀ k

  -- n(x) = ½ (1 + x (1 - T² x) / T x) with x = k h.
  nFactor : ℚ → ℚ
  nFactor x = (1ℚ + x * (1ℚ - T x * T x) /₀ T x) /₀ 2ℚ

  -- The group velocity c_g = n c.
  groupSpeed : ℚ → ℚ → ℚ
  groupSpeed σ k = nFactor (k * h) * phaseSpeed σ k

  private
    TT≤1 : ∀ {x} → 0ℚ < x → T x * T x ≤ 1ℚ
    TT≤1 {x} hx = ≤-trans (mul-le-mul′ h1 h1 hT hT) (≤-reflexive (*-identityʳ 1ℚ))
      where
      h1 = le-one x (<⇒≤ hx)
      hT = nonneg x (<⇒≤ hx)

    two-halves : 2ℚ /₀ 2ℚ ≡ 1ℚ
    two-halves = inv₀-inverse 2ℚ (<⇒≢0 0<2)

  nFactor-ge-half : ∀ {x} → 0ℚ < x → 1ℚ /₀ 2ℚ ≤ nFactor x
  nFactor-ge-half {x} hx = div-monoˡ-≤ {a = 1ℚ} {b = 1ℚ + y} (by-diff {a = 1ℚ} {b = 1ℚ + y} y (solve 2 (λ o y → o :+ y :- o := y) refl 1ℚ y) hy)
                                       (<⇒≤ 0<2)
    where
    y = x * (1ℚ - T x * T x) /₀ T x
    hy : 0ℚ ≤ y
    hy = div-nonneg (*-nonneg (<⇒≤ hx) (≤⇒0≤- (TT≤1 hx))) (nonneg x (<⇒≤ hx))

  nFactor-le-one : ∀ {x} → 0ℚ < x → nFactor x ≤ 1ℚ
  nFactor-le-one {x} hx =
    ≤-trans (div-monoˡ-≤ (+-mono-≤′ hy) (<⇒≤ 0<2)) (≤-reflexive two-halves)
    where
    open import Data.Rational.Properties using (+-monoʳ-≤)
    hy : x * (1ℚ - T x * T x) /₀ T x ≤ 1ℚ
    hy = div-le-of-le-mul (pos x hx) (≤-trans (sech-bound x hx) (≤-reflexive (sym (*-identityˡ (T x)))))
    +-mono-≤′ = +-monoʳ-≤ 1ℚ

  phaseSpeed-nonneg : ∀ {σ k} → 0ℚ ≤ σ → 0ℚ < k → 0ℚ ≤ phaseSpeed σ k
  phaseSpeed-nonneg hσ hk = div-nonneg hσ (<⇒≤ hk)

  -- c/2 ≤ c_g ≤ c: the group velocity lies between half the phase speed (deep water) and the
  -- phase speed (shallow water).
  groupSpeed-bounds : ∀ {σ k} → 0ℚ ≤ σ → 0ℚ < k →
    phaseSpeed σ k /₀ 2ℚ ≤ groupSpeed σ k × groupSpeed σ k ≤ phaseSpeed σ k
  groupSpeed-bounds {σ} {k} hσ hk =
    ≤-trans (≤-reflexive (solve 2 (λ c i → c :* i := con 1ℚ :* i :* c) refl c (inv₀ 2ℚ)))
            (*-monoʳ-≤-nonNeg c {{nonNegative hc}} (nFactor-ge-half hx)) ,
    ≤-trans (*-monoʳ-≤-nonNeg c {{nonNegative hc}} (nFactor-le-one hx)) (≤-reflexive (*-identityˡ c))
    where
    c  = phaseSpeed σ k
    hx = *-pos hk h-pos
    hc = phaseSpeed-nonneg hσ hk

  groupSpeed-nonneg : ∀ {σ k} → 0ℚ ≤ σ → 0ℚ < k → 0ℚ ≤ groupSpeed σ k
  groupSpeed-nonneg hσ hk =
    ≤-trans (div-nonneg (phaseSpeed-nonneg hσ hk) (<⇒≤ 0<2)) (proj₁ (groupSpeed-bounds hσ hk))

  -- No wave outruns the shallow-water speed. If k is at or above the root of the dispersion
  -- relation for σ (σ² ≤ σ²(k)), then c² ≤ g h. For the exact root this is c ≤ √(g h).
  phaseSpeed-sq-le : ∀ {σ k} → 0ℚ < k → σ * σ ≤ sigma2 k → phaseSpeed σ k * phaseSpeed σ k ≤ g * h
  phaseSpeed-sq-le {σ} {k} hk hd =
    subst₂ _≤_ (solve 2 (λ s i → s :* s :* (i :* i) := s :* i :* (s :* i)) refl σ i)
               (trans (solve 4 (λ g h k i → g :* h :* (k :* k) :* (i :* i) := g :* h :* ((k :* i) :* (k :* i)))
                         refl g h k i)
                      (trans (cong (λ u → g * h * (u * u)) (inv₀-inverse k (<⇒≢0 hk)))
                             (trans (cong (g * h *_) (*-identityʳ 1ℚ)) (*-identityʳ (g * h)))))
               (*-monoʳ-≤-nonNeg (i * i) {{nonNegative (sq-nonneg i)}}
                  (≤-trans hd (sigma2-le-shallow (<⇒≤ hk))))
    where i = inv₀ k

  -- The deep-water version: c² ≤ g / k, written as c² k ≤ g.
  phaseSpeed-sq-le-deep : ∀ {σ k} → 0ℚ < k → σ * σ ≤ sigma2 k →
    phaseSpeed σ k * phaseSpeed σ k * k ≤ g
  phaseSpeed-sq-le-deep {σ} {k} hk hd =
    subst₂ _≤_ (sym (trans (solve 3 (λ s k i → s :* i :* (s :* i) :* k := s :* s :* i :* (k :* i)) refl σ k i)
                           (trans (cong (σ * σ * i *_) (inv₀-inverse k (<⇒≢0 hk))) (*-identityʳ _))))
               (trans (solve 3 (λ g k i → g :* k :* i := g :* (k :* i)) refl g k i)
                      (trans (cong (g *_) (inv₀-inverse k (<⇒≢0 hk))) (*-identityʳ g)))
               (*-monoʳ-≤-nonNeg i {{nonNegative (inv₀-nonneg (<⇒≤ hk))}}
                  (≤-trans hd (sigma2-le-deep (<⇒≤ hk))))
    where i = inv₀ k

  -- The depth-based CFL condition. If g h Δt² ≤ Δx², the Courant number μ = c_g Δt / Δx of
  -- every frequency is in [0, 1]. So a time step chosen from the depth alone is safe for the
  -- whole spectrum.
  courant-le-one : ∀ {σ k Δt Δx} → 0ℚ ≤ σ → 0ℚ < k → σ * σ ≤ sigma2 k → 0ℚ ≤ Δt → 0ℚ < Δx →
    g * h * (Δt * Δt) ≤ Δx * Δx →
    0ℚ ≤ groupSpeed σ k * Δt /₀ Δx × groupSpeed σ k * Δt /₀ Δx ≤ 1ℚ
  courant-le-one {σ} {k} {Δt} {Δx} hσ hk hd ht hx hcfl =
    div-nonneg (*-nonneg hcg ht) (<⇒≤ hx) , le-one-of-sq-le-one μμ≤1
    where
    cg  = groupSpeed σ k
    j   = inv₀ Δx
    hcg = groupSpeed-nonneg hσ hk
    hgg : cg * cg ≤ g * h
    hgg = ≤-trans (mul-le-mul′ (proj₂ (groupSpeed-bounds hσ hk)) (proj₂ (groupSpeed-bounds hσ hk)) hcg hcg)
                  (phaseSpeed-sq-le {σ = σ} hk hd)
    step1 : cg * cg * (Δt * Δt) ≤ Δx * Δx
    step1 = ≤-trans (*-monoʳ-≤-nonNeg (Δt * Δt) {{nonNegative (sq-nonneg Δt)}} hgg) hcfl
    μμ≤1 : cg * Δt /₀ Δx * (cg * Δt /₀ Δx) ≤ 1ℚ
    μμ≤1 = subst₂ _≤_
      (solve 3 (λ c t j → c :* c :* (t :* t) :* (j :* j) := c :* t :* j :* (c :* t :* j)) refl cg Δt j)
      (trans (solve 2 (λ x j → x :* x :* (j :* j) := (x :* j) :* (x :* j)) refl Δx j)
             (trans (cong (λ u → u * u) (inv₀-inverse Δx (<⇒≢0 hx))) (*-identityʳ 1ℚ)))
      (*-monoʳ-≤-nonNeg (j * j) {{nonNegative (sq-nonneg j)}} step1)

-- ---------------------------------------------------------------------------------------------
-- A concrete rational tanh
--
-- pade x = x (27 + x²) / (27 + 9 x²) is the [3/2] Padé approximant of tanh. It is exactly 1 at
-- x = 3, so it is clamped there. Its largest error against tanh is about 0.02 (near x ≈ 2).

private
  27ℚ 9ℚ 3ℚ : ℚ
  27ℚ = lit 27
  9ℚ  = lit 9
  3ℚ  = lit 3

  0<27 : 0ℚ < 27ℚ
  0<27 = from-yes (0ℚ <? 27ℚ)

  0≤9 : 0ℚ ≤ 9ℚ
  0≤9 = from-yes (0ℚ ≤? 9ℚ)

pade : ℚ → ℚ
pade x = x * (27ℚ + x * x) /₀ (27ℚ + 9ℚ * (x * x))

-- The clamped Padé model. `clamp x d` takes the answer d to "x ≤ 3?"; the theorems below match
-- on d, so each case reduces.
clamp : (x : ℚ) → Dec (x ≤ 3ℚ) → ℚ
clamp x (yes _) = pade x
clamp x (no  _) = 1ℚ

padeT : ℚ → ℚ
padeT x = clamp x (x ≤? 3ℚ)

pade-den-pos : ∀ x → 0ℚ < 27ℚ + 9ℚ * (x * x)
pade-den-pos x = +-pos 0<27 (*-nonneg 0≤9 (sq-nonneg x))

pade-three : pade 3ℚ ≡ 1ℚ
pade-three = refl

-- The Padé approximant is monotone on all of ℚ. The key identity is
-- b (27 + b²)(27 + 9a²) - a (27 + a²)(27 + 9b²) = (b - a) (9 (9 - ab)² + 27 (a - b)²).
pade-mono : ∀ {a b} → a ≤ b → pade a ≤ pade b
pade-mono {a} {b} hab =
  div-le-div-of-cross {a = a * (27ℚ + a * a)} {c = b * (27ℚ + b * b)} (pade-den-pos a) (pade-den-pos b)
    (by-diff {a = a * (27ℚ + a * a) * (27ℚ + 9ℚ * (b * b))} {b = b * (27ℚ + b * b) * (27ℚ + 9ℚ * (a * a))}
       e (solve 2 (λ a b →
        b :* (con 27ℚ :+ b :* b) :* (con 27ℚ :+ con 9ℚ :* (a :* a))
          :- a :* (con 27ℚ :+ a :* a) :* (con 27ℚ :+ con 9ℚ :* (b :* b))
        := (b :- a) :* (con 9ℚ :* ((con 9ℚ :- a :* b) :* (con 9ℚ :- a :* b))
                        :+ con 27ℚ :* ((a :- b) :* (a :- b)))) refl a b)
       (*-nonneg (≤⇒0≤- hab) (+-nonneg (*-nonneg 0≤9 (sq-nonneg (9ℚ - a * b))) (*-nonneg (<⇒≤ 0<27) (sq-nonneg (a - b))))))
  where
  e = (b - a) * (9ℚ * ((9ℚ - a * b) * (9ℚ - a * b)) + 27ℚ * ((a - b) * (a - b)))

pade-pos : ∀ {x} → 0ℚ < x → 0ℚ < pade x
pade-pos {x} hx = div-pos (*-pos hx (+-pos 0<27 (sq-nonneg x))) (pade-den-pos x)

pade-le-id : ∀ {x} → 0ℚ ≤ x → pade x ≤ x
pade-le-id {x} hx =
  div-le-of-le-mul (pade-den-pos x)
    (by-diff {a = x * (27ℚ + x * x)} {b = x * (27ℚ + 9ℚ * (x * x))} (lit 8 * (x * (x * x)))
       (solve 1 (λ x → x :* (con 27ℚ :+ con 9ℚ :* (x :* x)) :- x :* (con 27ℚ :+ x :* x)
                       := con (lit 8) :* (x :* (x :* x))) refl x)
       (*-nonneg (from-yes (0ℚ ≤? lit 8)) (*-nonneg hx (sq-nonneg x))))

-- x (1 - p²/q²) ≤ p/q. The gap is x · x² · ((x² - 9)² + 432) / q².
pade-sech-bound : ∀ {x} → 0ℚ < x → x * (1ℚ - pade x * pade x) ≤ pade x
pade-sech-bound {x} hx = le-of-mul-le-mul-right′ goal (*-pos (pade-den-pos x) (pade-den-pos x))
  where
  P = x * (27ℚ + x * x)
  Q = 27ℚ + 9ℚ * (x * x)
  p = pade x
  pQ : p * Q ≡ P
  pQ = div-mul-cancel P (<⇒≢0 (pade-den-pos x))
  gap : 0ℚ ≤ x * ((x * x) * ((x * x - 9ℚ) * (x * x - 9ℚ) + lit 432))
  gap = *-nonneg (<⇒≤ hx) (*-nonneg (sq-nonneg x)
          (+-nonneg (sq-nonneg (x * x - 9ℚ)) (from-yes (0ℚ ≤? lit 432))))
  poly : x * (Q * Q) - x * (P * P) ≤ P * Q
  poly = by-diff {a = x * (Q * Q) - x * (P * P)} {b = P * Q} (x * ((x * x) * ((x * x - 9ℚ) * (x * x - 9ℚ) + lit 432))) (solve 1 (λ x →
            x :* (con 27ℚ :+ x :* x) :* (con 27ℚ :+ con 9ℚ :* (x :* x))
              :- (x :* ((con 27ℚ :+ con 9ℚ :* (x :* x)) :* (con 27ℚ :+ con 9ℚ :* (x :* x)))
                  :- x :* ((x :* (con 27ℚ :+ x :* x)) :* (x :* (con 27ℚ :+ x :* x))))
            := x :* ((x :* x) :* ((x :* x :- con 9ℚ) :* (x :* x :- con 9ℚ) :+ con (lit 432)))) refl x)
           gap
  goal : x * (1ℚ - p * p) * (Q * Q) ≤ p * (Q * Q)
  goal = subst₂ _≤_
    (sym (trans (solve 3 (λ x p q → x :* (con 1ℚ :- p :* p) :* (q :* q)
                                    := x :* (q :* q) :- x :* ((p :* q) :* (p :* q))) refl x p Q)
                (cong (λ u → x * (Q * Q) - x * (u * u)) pQ)))
    (sym (trans (solve 2 (λ p q → p :* (q :* q) := (p :* q) :* q) refl p Q) (cong (_* Q) pQ)))
    poly

private
  pade≤1 : ∀ {x} → x ≤ 3ℚ → pade x ≤ 1ℚ
  pade≤1 h = ≤-trans (pade-mono h) (≤-reflexive pade-three)

  clamp-le-one : ∀ x d → clamp x d ≤ 1ℚ
  clamp-le-one x (yes h) = pade≤1 h
  clamp-le-one x (no  _) = ≤-refl

  clamp-pos : ∀ x d → 0ℚ < x → 0ℚ < clamp x d
  clamp-pos x (yes _) hx = pade-pos hx
  clamp-pos x (no  _) hx = 0<1

  clamp-mono : ∀ x y dx dy → x ≤ y → clamp x dx ≤ clamp y dy
  clamp-mono x y (yes _)  (yes _)  hxy = pade-mono hxy
  clamp-mono x y (yes hx) (no _)   hxy = pade≤1 hx
  clamp-mono x y (no hx)  (yes hy) hxy = contradiction (≤-trans hxy hy) hx
  clamp-mono x y (no _)   (no _)   hxy = ≤-refl

  clamp-le-id : ∀ x d → 0ℚ ≤ x → clamp x d ≤ x
  clamp-le-id x (yes _) hx = pade-le-id hx
  clamp-le-id x (no h)  hx = <⇒≤ (<-trans′ (from-yes (1ℚ <? 3ℚ)) (≰⇒> h))
    where open import Data.Rational.Properties using () renaming (<-trans to <-trans′)

  clamp-sech : ∀ x d → 0ℚ < x → x * (1ℚ - clamp x d * clamp x d) ≤ clamp x d
  clamp-sech x (yes _) hx = pade-sech-bound hx
  clamp-sech x (no  _) hx =
    ≤-trans (≤-reflexive (solve 1 (λ x → x :* (con 1ℚ :- con 1ℚ :* con 1ℚ) := con 0ℚ) refl x)) (<⇒≤ 0<1)

  clamp-sat : ∀ x d → 3ℚ ≤ x → clamp x d ≡ 1ℚ
  clamp-sat x (yes h) hx = trans (cong pade (≤-antisym h hx)) pade-three
  clamp-sat x (no  _) hx = refl

padeT-le-one : ∀ x → padeT x ≤ 1ℚ
padeT-le-one x = clamp-le-one x (x ≤? 3ℚ)

-- The clamped Padé function has every property of a `TanhModel`.
padeModel : TanhModel
padeModel = record
  { T          = padeT
  ; T-zero     = refl
  ; pos        = λ x → clamp-pos x (x ≤? 3ℚ)
  ; mono       = λ x y _ → clamp-mono x y (x ≤? 3ℚ) (y ≤? 3ℚ)
  ; le-id      = λ x → clamp-le-id x (x ≤? 3ℚ)
  ; le-one     = λ x _ → padeT-le-one x
  ; sech-bound = λ x → clamp-sech x (x ≤? 3ℚ)
  ; sat        = 3ℚ
  ; sat-pos    = from-yes (0ℚ <? 3ℚ)
  ; T-sat      = λ x → clamp-sat x (x ≤? 3ℚ)
  }
