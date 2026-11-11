{-# OPTIONS --safe --without-K #-}

-- Order lemmas and a total division for exact rationals, for the ocean-wave kernels. Ported
-- from the "Order and division" part of `ocean-waves/lean/OceanWaves/RatLemmas.lean`.
--
-- Lean's `Rat` divides by zero and gives zero. The standard library's division needs a proof
-- that the divisor is not zero. `_/₀_` here is Lean's division: `p /₀ q = p * inv₀ q`, with
-- `inv₀ 0 = 0`. The kernels use it, so their definitions read as in Lean.
--
-- Most inequalities here come from one rule: `a ≤ b` when `b - a` is a non-negative
-- expression (`by-diff`). The ring solver shows the equality, and the closure lemmas
-- (`+-nonneg`, `*-nonneg`, `sq-nonneg`) show the sign.
module OceanWaves.Order where

open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; -_; _≤_; _<_; _≟_; 1/_; _⊔_; _⊓_; Positive)
open import Data.Rational.Base using (nonNegative; positive; ≢-nonZero)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-<-trans; <⇒≤; ≤-reflexive; ≤-total; <-irrefl; ≰⇒>;
         +-mono-≤; +-mono-<-≤; +-monoˡ-≤; *-monoʳ-≤-nonNeg; *-monoˡ-≤-nonNeg; *-monoˡ-<-pos;
         *-inverseʳ; *-identityʳ; positive⁻¹; nonNegative⁻¹; pos*pos⇒pos; 1/pos⇒pos;
         *-cancelʳ-≤-pos; ≤-antisym)
  renaming (_≤?_ to _≤?_)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; :-_; con)
open import Data.Integer using () renaming (+_ to ℤ+)
open import Data.Nat using (ℕ)
open import Data.Rational using (_/_)
open import Data.Sum using (inj₁; inj₂)
open import Relation.Nullary using (yes; no; Dec; contradiction)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; subst)

open import OceanWaves.Sums using (*-nonneg; ≤⇒0≤-) public

-- ---------------------------------------------------------------------------------------------
-- Signs

+-nonneg : ∀ {a b} → 0ℚ ≤ a → 0ℚ ≤ b → 0ℚ ≤ a + b
+-nonneg ha hb = +-mono-≤ ha hb

+-pos : ∀ {a b} → 0ℚ < a → 0ℚ ≤ b → 0ℚ < a + b
+-pos ha hb = +-mono-<-≤ ha hb

*-pos : ∀ {a b} → 0ℚ < a → 0ℚ < b → 0ℚ < a * b
*-pos {a} {b} ha hb = positive⁻¹ (a * b) {{pos*pos⇒pos a {{positive ha}} b {{positive hb}}}}

sq-nonneg : ∀ a → 0ℚ ≤ a * a
sq-nonneg a with ≤-total 0ℚ a
... | inj₁ h = *-nonneg h h
... | inj₂ h = subst (0ℚ ≤_) (solve 1 (λ x → (:- x) :* (:- x) := x :* x) refl a)
                 (*-nonneg (neg-nonneg h) (neg-nonneg h))
  where
  neg-nonneg : ∀ {x} → x ≤ 0ℚ → 0ℚ ≤ - x
  neg-nonneg {x} hx = subst (0ℚ ≤_) (solve 1 (λ y → con 0ℚ :- y := :- y) refl x) (≤⇒0≤- hx)

-- ---------------------------------------------------------------------------------------------
-- From a difference to an inequality

by-diff : ∀ {a b} e → b - a ≡ e → 0ℚ ≤ e → a ≤ b
by-diff {a} {b} e eq h =
  subst₂ _≤_ (solve 1 (λ x → x :+ con 0ℚ := x) refl a)
             (trans (cong (a +_) eq') (solve 2 (λ x y → x :+ (y :- x) := y) refl a b))
             (+-mono-≤ (≤-refl {a}) h)
  where
  open import Relation.Binary.PropositionalEquality using (subst₂)
  eq' : e ≡ b - a
  eq' = sym eq

by-diff< : ∀ {a b} e → b - a ≡ e → 0ℚ < e → a < b
by-diff< {a} {b} e eq h =
  subst₂ _<_ (solve 1 (λ x → con 0ℚ :+ x := x) refl a)
             (trans (cong (_+ a) (sym eq)) (solve 2 (λ x y → (y :- x) :+ x := y) refl a b))
             (+-mono-<-≤ h (≤-refl {a}))
  where open import Relation.Binary.PropositionalEquality using (subst₂)

<⇒0<- : ∀ {a b} → a < b → 0ℚ < b - a
<⇒0<- {a} {b} h =
  subst₂ _<_ (solve 1 (λ x → x :- x := con 0ℚ) refl a) refl (+-mono-<-≤ h (≤-refl { - a}))
  where open import Relation.Binary.PropositionalEquality using (subst₂)

-- ---------------------------------------------------------------------------------------------
-- Products

mul-le-mul′ : ∀ {a b c d} → a ≤ b → c ≤ d → 0ℚ ≤ a → 0ℚ ≤ c → a * c ≤ b * d
mul-le-mul′ {a} {b} {c} {d} hab hcd ha hc =
  ≤-trans (*-monoʳ-≤-nonNeg c {{nonNegative hc}} hab)
          (*-monoˡ-≤-nonNeg b {{nonNegative (≤-trans ha hab)}} hcd)

-- If x * x ≤ 1 then x ≤ 1: a squared CFL bound gives the CFL bound with no square root.
le-one-of-sq-le-one : ∀ {x} → x * x ≤ 1ℚ → x ≤ 1ℚ
le-one-of-sq-le-one {x} h with x ≤? 1ℚ
... | yes x≤1 = x≤1
... | no  x≰1 = contradiction (≤-<-trans h 1<xx) (<-irrefl refl)
  where
  1<x = ≰⇒> x≰1
  0<x = <-trans′ (positive⁻¹ 1ℚ) 1<x
    where
    open import Data.Rational.Properties using () renaming (<-trans to <-trans′)
  1<xx : 1ℚ < x * x
  1<xx = <-trans′ 1<x (subst (_< x * x) (solve 1 (λ y → con 1ℚ :* y := y) refl x)
                         (*-monoˡ-<-pos x {{positive 0<x}} 1<x))
    where
    open import Data.Rational.Properties using () renaming (<-trans to <-trans′)

≤∧≢⇒< : ∀ {a b} → a ≤ b → a ≢ b → a < b
≤∧≢⇒< {a} {b} hab ne with b ≤? a
... | yes hba = contradiction (≤-antisym hab hba) ne
... | no  hba = ≰⇒> hba

-- ---------------------------------------------------------------------------------------------
-- Lean's total inverse and division

private
  invD : (q : ℚ) → Dec (q ≡ 0ℚ) → ℚ
  invD q (yes _) = 0ℚ
  invD q (no ne) = (1/ q) {{≢-nonZero ne}}

inv₀ : ℚ → ℚ
inv₀ q = invD q (q ≟ 0ℚ)

infixl 7 _/₀_
_/₀_ : ℚ → ℚ → ℚ
p /₀ q = p * inv₀ q

inv₀-inverse : ∀ q → q ≢ 0ℚ → q * inv₀ q ≡ 1ℚ
inv₀-inverse q ne with q ≟ 0ℚ
... | yes q≡0 = contradiction q≡0 ne
... | no  q≢0 = *-inverseʳ q {{≢-nonZero q≢0}}

inv₀-pos : ∀ {q} → 0ℚ < q → 0ℚ < inv₀ q
inv₀-pos {q} h with q ≟ 0ℚ
... | yes q≡0 = contradiction (subst (0ℚ <_) q≡0 h) (<-irrefl refl)
... | no  q≢0 = positive⁻¹ ((1/ q) {{≢-nonZero q≢0}}) {{1/pos⇒pos q {{positive h}}}}

inv₀-nonneg : ∀ {q} → 0ℚ ≤ q → 0ℚ ≤ inv₀ q
inv₀-nonneg {q} h with q ≟ 0ℚ
... | yes _   = ≤-refl
... | no  q≢0 = <⇒≤ (positive⁻¹ ((1/ q) {{≢-nonZero q≢0}})
                      {{1/pos⇒pos q {{positive (≤∧≢⇒< h (λ eq → q≢0 (sym eq)))}}}})

<⇒≢0 : ∀ {q} → 0ℚ < q → q ≢ 0ℚ
<⇒≢0 h refl = <-irrefl refl h

div-nonneg : ∀ {a b} → 0ℚ ≤ a → 0ℚ ≤ b → 0ℚ ≤ a /₀ b
div-nonneg ha hb = *-nonneg ha (inv₀-nonneg hb)

div-pos : ∀ {a b} → 0ℚ < a → 0ℚ < b → 0ℚ < a /₀ b
div-pos ha hb = *-pos ha (inv₀-pos hb)

div-mul-cancel : ∀ a {b} → b ≢ 0ℚ → a /₀ b * b ≡ a
div-mul-cancel a {b} ne =
  trans (solve 3 (λ x y i → x :* i :* y := x :* (y :* i)) refl a b (inv₀ b))
        (trans (cong (a *_) (inv₀-inverse b ne)) (*-identityʳ a))

mul-div-cancel : ∀ a {b} → b ≢ 0ℚ → b * (a /₀ b) ≡ a
mul-div-cancel a {b} ne =
  trans (solve 3 (λ x y i → y :* (x :* i) := x :* (y :* i)) refl a b (inv₀ b))
        (trans (cong (a *_) (inv₀-inverse b ne)) (*-identityʳ a))

div-le-of-le-mul : ∀ {a b c} → 0ℚ < b → a ≤ c * b → a /₀ b ≤ c
div-le-of-le-mul {a} {b} {c} hb h =
  ≤-trans (*-monoʳ-≤-nonNeg (inv₀ b) {{nonNegative (inv₀-nonneg (<⇒≤ hb))}} h)
          (≤-reflexive (div-mul-cancel′))
  where
  div-mul-cancel′ : c * b * inv₀ b ≡ c
  div-mul-cancel′ =
    trans (solve 3 (λ x y i → x :* y :* i := x :* (y :* i)) refl c b (inv₀ b))
          (trans (cong (c *_) (inv₀-inverse b (<⇒≢0 hb))) (*-identityʳ c))

le-div-of-mul-le : ∀ {a b c} → 0ℚ < b → c * b ≤ a → c ≤ a /₀ b
le-div-of-mul-le {a} {b} {c} hb h =
  ≤-trans (≤-reflexive (sym c-eq))
          (*-monoʳ-≤-nonNeg (inv₀ b) {{nonNegative (inv₀-nonneg (<⇒≤ hb))}} h)
  where
  c-eq : c * b * inv₀ b ≡ c
  c-eq = trans (solve 3 (λ x y i → x :* y :* i := x :* (y :* i)) refl c b (inv₀ b))
               (trans (cong (c *_) (inv₀-inverse b (<⇒≢0 hb))) (*-identityʳ c))

-- Compare two fractions by cross multiplication.
div-le-div-of-cross : ∀ {a b c d} → 0ℚ < b → 0ℚ < d → a * d ≤ c * b → a /₀ b ≤ c /₀ d
div-le-div-of-cross {a} {b} {c} {d} hb hd h =
  subst₂ _≤_ l r (*-monoʳ-≤-nonNeg (inv₀ b * inv₀ d)
                    {{nonNegative (*-nonneg (inv₀-nonneg (<⇒≤ hb)) (inv₀-nonneg (<⇒≤ hd)))}} h)
  where
  open import Relation.Binary.PropositionalEquality using (subst₂)
  l : a * d * (inv₀ b * inv₀ d) ≡ a /₀ b
  l = trans (solve 4 (λ x y i j → x :* y :* (i :* j) := x :* i :* (y :* j)) refl a d (inv₀ b) (inv₀ d))
        (trans (cong (a * inv₀ b *_) (inv₀-inverse d (<⇒≢0 hd))) (*-identityʳ _))
  r : c * b * (inv₀ b * inv₀ d) ≡ c /₀ d
  r = trans (solve 4 (λ x y i j → x :* y :* (i :* j) := x :* j :* (y :* i)) refl c b (inv₀ b) (inv₀ d))
        (trans (cong (c * inv₀ d *_) (inv₀-inverse b (<⇒≢0 hb))) (*-identityʳ _))

div-monoˡ-≤ : ∀ {a b c} → a ≤ b → 0ℚ ≤ c → a /₀ c ≤ b /₀ c
div-monoˡ-≤ {c = c} h hc = *-monoʳ-≤-nonNeg (inv₀ c) {{nonNegative (inv₀-nonneg hc)}} h

le-of-mul-le-mul-right′ : ∀ {a b c} → a * c ≤ b * c → 0ℚ < c → a ≤ b
le-of-mul-le-mul-right′ {c = c} h hc = *-cancelʳ-≤-pos c {{positive hc}} h

-- ---------------------------------------------------------------------------------------------
-- Constants

-- A natural number as a rational: Lean's numeral `(27 : Rat)`.
lit : ℕ → ℚ
lit n = ℤ+ n / 1

2ℚ : ℚ
2ℚ = 1ℚ + 1ℚ

0<1 : 0ℚ < 1ℚ
0<1 = positive⁻¹ 1ℚ

0<2 : 0ℚ < 2ℚ
0<2 = +-pos 0<1 (<⇒≤ 0<1)

half-mul-two : ∀ a → a /₀ 2ℚ * 2ℚ ≡ a
half-mul-two a = div-mul-cancel a (<⇒≢0 0<2)
