{-# OPTIONS --safe --without-K #-}

-- The size rules of a triangle grid for WAVEWATCH III, ported from parts 1 and 3 of
-- `z3-scala/src/main/scala/grids/domain/Grids.scala` (`just grids`). The names follow Z3, with
-- `-` for `_`. Z3 proves part 3 for a chain of 7 and 8 sizes. Agda proves the bound for a chain
-- of any length, by induction, and then reads it at 6 and 7 steps.
--
-- 1. The size rule: the spacing is the smallest of the local minimums (depth, coast), never
--    below the 5 km floor. A depth gradient over 1/10 gives the floor.
-- 3. A growth rate of 30% between neighbours needs at least 7 steps from 5 km to 30 km.
--
-- Part 2 (the Courant number of a 600 s step) is `Grids.Courant`, part 4 (WAVEWATCH III's ITER)
-- is `Grids.Iter`. Part 5 (the NOTE lines of a measured mesh) prints numbers and is not ported.
module Grids.SizeRule where

open import Data.Bool using (true; false; if_then_else_)
open import Data.Integer using (+_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; 0ℚ; _/_; _*_; _≤_; _<_; _⊓_; _⊔_; _≤?_; _<?_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-<-trans; ≤-reflexive; *-monoˡ-≤-nonNeg; p≤p⊔q; p≤q⇒p⊔q≡q;
         p⊓q≤p; p⊓q≤q; ⊓-glb; ⊓-sel; <-irrefl)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Relation.Nullary using (does; contradiction)
open import Relation.Nullary.Decidable using (from-yes; dec-true; dec-false)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; subst)

-- "a minimum grid spacing of 5 km"
hMin : ℚ
hMin = + 5 / 1

-- The depth gradient above which the floor is used.
steep : ℚ
steep = + 1 / 10

-- "a mesh size growth rate of 30%"
growth : ℚ
growth = + 13 / 10

-- ---------------------------------------------------------------------------------------------
-- 1. The size rule, as `size` in Grids.scala.

size : (hDepth hCoast slope : ℚ) → ℚ
size hDepth hCoast slope = if does (steep <? slope) then hMin else hMin ⊔ (hDepth ⊓ hCoast)

-- The spacing is never below the floor. Z3 needs positive inputs; this holds for all of them.
size-floor : ∀ hDepth hCoast slope → hMin ≤ size hDepth hCoast slope
size-floor hDepth hCoast slope with does (steep <? slope)
... | true  = ≤-refl
... | false = p≤p⊔q hMin (hDepth ⊓ hCoast)

-- A depth gradient over 1/10 gives the floor.
size-steep-is-floor : ∀ hDepth hCoast slope → steep < slope → size hDepth hCoast slope ≡ hMin
size-steep-is-floor hDepth hCoast slope s with does (steep <? slope) in eq
... | true  = refl
... | false = contradiction (trans (sym (dec-true (steep <? slope) s)) eq) λ ()

-- On a gentle slope with both minimums above the floor, the spacing is the smaller of the two.
size-smallest-minimum : ∀ hDepth hCoast slope → slope ≤ steep → hMin ≤ hDepth → hMin ≤ hCoast →
  let h = size hDepth hCoast slope in h ≤ hDepth × h ≤ hCoast × (h ≡ hDepth ⊎ h ≡ hCoast)
size-smallest-minimum hDepth hCoast slope gentle hd hc with does (steep <? slope) in eq
... | true  = contradiction (trans (sym eq) (dec-false (steep <? slope) not-steep)) λ ()
  where not-steep = λ s → <-irrefl refl (≤-<-trans gentle s)
... | false = subst (λ h → h ≤ hDepth × h ≤ hCoast × (h ≡ hDepth ⊎ h ≡ hCoast)) (sym floor≤)
               (p⊓q≤p hDepth hCoast , p⊓q≤q hDepth hCoast , ⊓-sel hDepth hCoast)
  where floor≤ = p≤q⇒p⊔q≡q (⊓-glb hd hc)

-- ---------------------------------------------------------------------------------------------
-- 3. Gradation. A chain of sizes starts at the floor, and each size is at most 1.3 times the
-- size before it.

Chain : (ℕ → ℚ) → Set
Chain h = h 0 ≡ hMin × (∀ i → h (suc i) ≤ growth * h i)

-- The largest size that i steps of 30% can reach from 5 km: 5 * 1.3^i.
reach : ℕ → ℚ
reach zero    = hMin
reach (suc i) = growth * reach i

-- Every chain stays under `reach`, for every number of steps.
chain-le-reach : ∀ h → Chain h → ∀ i → h i ≤ reach i
chain-le-reach h (h0 , _)    zero    = ≤-reflexive h0
chain-le-reach h c@(_ , step) (suc i) =
  ≤-trans (step i) (*-monoˡ-≤-nonNeg growth {{nonNegative (from-yes (0ℚ ≤? growth))}}
                     (chain-le-reach h c i))

-- `reach` is a chain: the bound is the best one.
reach-chain : Chain reach
reach-chain = refl , λ _ → ≤-refl

thirty : ℚ
thirty = + 30 / 1

-- Six steps of 30% from 5 km stay below 30 km (5 * 1.3^6 = 24.13 km).
growth-6-steps-below-30km : ∀ h → Chain h → h 6 < thirty
growth-6-steps-below-30km h c = ≤-<-trans (chain-le-reach h c 6) (from-yes (reach 6 <? thirty))

-- Seven steps can reach 30 km (5 * 1.3^7 = 31.37 km): Z3's counterexample, as a witness.
growth-7-steps-reach-30km : Chain reach × thirty ≤ reach 7
growth-7-steps-reach-30km = reach-chain , from-yes (thirty ≤? reach 7)
