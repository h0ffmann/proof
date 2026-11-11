{-# OPTIONS --safe --without-K #-}

-- The Courant number of a 600 s step on a triangle grid, ported from part 2 of
-- `z3-scala/src/main/scala/grids/domain/Grids.scala` (`just grids`). The names follow Z3, with
-- `-` for `_`.
--
-- The depth rule makes a cell as wide as a wave at the lowest frequency travels in one step of
-- 600 s: hDepth = 600 * cg. Every cell is then at least as fine as that, so its Courant number
-- cg * 600 / size is at least 1, and above 1 wherever another rule is finer. That is the reason
-- the paper steps implicitly. Z3's counterexample `explicit_600s_stable` is a witness here.
module Grids.Courant where

open import Data.Integer using (+_)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; 1ℚ; _/_; _*_; _≤_; _<_; _⊓_; _⊔_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; <-≤-trans; ≤-reflexive; ⊔-lub; p⊓q≤p; *-comm; *-identityˡ; _<?_;
         ≤-<-trans; <-irrefl; ≰⇒>; _≤?_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; subst)
open import Relation.Nullary using (Dec; yes; no; ¬_; contradiction)
open import Relation.Nullary.Decidable using (from-yes; dec-true; dec-false)

open import Grids.SizeRule using (hMin; steep; size; size-floor)
open import OceanWaves.Order
  using (_/₀_; le-div-of-mul-le; div-mul-cancel; *-pos)

-- "an implicit time step of 600 s"
step : ℚ
step = + 600 / 1

-- The Courant number of a cell of width `h` for a wave of group speed `cg`.
courant : (cg h : ℚ) → ℚ
courant cg h = cg * step /₀ h

private
  0<hMin : 0ℚ < hMin
  0<hMin = from-yes (0ℚ <? hMin)

  size-pos : ∀ hd hc sl → 0ℚ < size hd hc sl
  size-pos hd hc sl = <-≤-trans 0<hMin (size-floor hd hc sl)

  -- c < a / b from c * b < a, for b > 0.
  lt-div-of-mul-lt : ∀ {a b c} → 0ℚ < b → c * b < a → c < a /₀ b
  lt-div-of-mul-lt {a} {b} {c} 0<b h with a /₀ b ≤? c
  ... | no  ¬le = ≰⇒> ¬le
  ... | yes le  = contradiction (≤-<-trans (subst (_≤ c * b) (div-mul-cancel a b≢0)
                                  (*-monoʳ-≤-nonNeg′ le)) h) (<-irrefl refl)
    where
    open import Data.Rational.Properties using (<⇒≢; *-monoʳ-≤-nonNeg)
    open import Data.Rational.Base using (nonNegative)
    open import Data.Rational.Properties using (<⇒≤)
    b≢0 = λ b≡0 → <⇒≢ 0<b (sym b≡0)
    *-monoʳ-≤-nonNeg′ : a /₀ b ≤ c → a /₀ b * b ≤ c * b
    *-monoʳ-≤-nonNeg′ = *-monoʳ-≤-nonNeg b {{nonNegative (<⇒≤ 0<b)}}

-- Where the depth rule holds, no rule gives a cell wider than the depth rule.
size-le-depth : ∀ hd hc sl → hMin ≤ hd → size hd hc sl ≤ hd
size-le-depth hd hc sl hd≥ = go (steep <? sl)
  where
  open import Data.Bool using (if_then_else_)
  open import Relation.Nullary using (does)
  go : (d : Dec (steep < sl)) → (if does d then hMin else hMin ⊔ (hd ⊓ hc)) ≤ hd
  go (yes _) = hd≥
  go (no _)  = ⊔-lub hd≥ (p⊓q≤p hd hc)

-- The depth rule, as Z3's premises: cg > 0, hDepth = 600 cg, hDepth ≥ 5 km.
DepthRule : (cg hd : ℚ) → Set
DepthRule cg hd = 0ℚ < cg × hd ≡ step * cg × hMin ≤ hd

courant-at-least-1 : ∀ cg hd hc sl → DepthRule cg hd → 1ℚ ≤ courant cg (size hd hc sl)
courant-at-least-1 cg hd hc sl (_ , hd≡ , hd≥) =
  le-div-of-mul-le (size-pos hd hc sl)
    (subst (λ x → 1ℚ * size hd hc sl ≤ x) (trans hd≡ (*-comm step cg))
      (subst (_≤ hd) (sym (*-identityˡ _)) (size-le-depth hd hc sl hd≥)))

courant-above-1-where-finer : ∀ cg hd hc sl → DepthRule cg hd → size hd hc sl < hd →
  1ℚ < courant cg (size hd hc sl)
courant-above-1-where-finer cg hd hc sl (_ , hd≡ , _) finer =
  lt-div-of-mul-lt (size-pos hd hc sl)
    (subst (λ x → 1ℚ * size hd hc sl < x) (trans hd≡ (*-comm step cg))
      (subst (_< hd) (sym (*-identityˡ _)) finer))

-- explicit_600s_stable, refuted: a cell finer than the depth rule breaks the explicit CFL
-- condition at 600 s. Here cg = 1/60 km/s, so hDepth = 10 km, and the coast rule gives 5 km.
explicit-600s-stable-refuted :
  let cg = + 1 / 60 ; hd = step * cg ; hc = hMin ; sl = 0ℚ in
  DepthRule cg hd × 1ℚ < courant cg (size hd hc sl)
explicit-600s-stable-refuted =
  (from-yes (0ℚ <? + 1 / 60) , refl , from-yes (hMin ≤? step * (+ 1 / 60))) ,
  from-yes (1ℚ <? courant (+ 1 / 60) (size (step * (+ 1 / 60)) hMin 0ℚ))
