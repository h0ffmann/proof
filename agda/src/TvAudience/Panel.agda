{-# OPTIONS --safe --without-K #-}

-- The audience measures of one slot (a market, a date, an hour), over exact rationals. The panel
-- measures the pool, the viewers who watch any TV in the slot, and each channel's audience
-- (`tv-audience/python/simulate.py`, `experiment.py`: `share = audience / pool`). The universe
-- is the population the panel stands for.
--
--   rating  = audience / universe       PUT  = pool / universe       share = audience / pool
--
-- The theorems: rating = share × PUT; the channels' shares and the outside share add up to 1;
-- forecasts that do not add up to more than the pool give shares that do not add up to more
-- than 1; and the coherence count of the results table (`slots_over_pool`, the slots whose
-- channel forecasts add up to more than the pool) is 0 when every slot is coherent.
module TvAudience.Panel where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.List using (List; []; _∷_; map)
open import Data.Product using (_×_; _,_)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.Rational
  using (ℚ; 0ℚ; 1ℚ; _+_; _-_; _*_; _≤_; _<_)
open import Data.Rational.Properties
  using (≤-refl; ≤-trans; ≤-reflexive; *-zeroʳ; *-identityʳ; *-monoʳ-≤-nonNeg; _<?_)
open import Data.Rational.Base using (nonNegative)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; _:-_; _:*_; con)
open import Relation.Nullary using (does; ¬_)
open import Relation.Nullary.Decidable using (dec-false)
open import Relation.Binary.PropositionalEquality
  using (_≡_; _≢_; refl; sym; trans; cong; cong₂; subst)

open import FatTails.Sample using (sum; inv₀; _/₀_; inv₀-inverse; inv₀-nonneg)
open import OceanWaves.Order using (div-le-of-le-mul)

rating : ℚ → ℚ → ℚ
rating universe audience = audience /₀ universe

put : ℚ → ℚ → ℚ
put universe pool = pool /₀ universe

share : ℚ → ℚ → ℚ
share pool audience = audience /₀ pool

-- The share of the pool that no listed channel has: other channels and other screens.
outside : ℚ → List ℚ → ℚ
outside pool audiences = (pool - sum audiences) /₀ pool

shares : ℚ → List ℚ → List ℚ
shares pool = map (share pool)

-- ---------------------------------------------------------------------------------------------

rating-share-put : ∀ universe pool audience → pool ≢ 0ℚ →
                   rating universe audience ≡ share pool audience * put universe pool
rating-share-put u p a hp =
  sym (trans (solve 4 (λ x i y j → (x :* i) :* (y :* j) := (x :* j) :* (y :* i)) refl a (inv₀ p) p (inv₀ u))
        (trans (cong ((a * inv₀ u) *_) (inv₀-inverse p hp)) (*-identityʳ (a * inv₀ u))))

sum-shares : ∀ pool as → sum (shares pool as) ≡ sum as /₀ pool
sum-shares pool []       = sym (solve 1 (λ i → con 0ℚ :* i := con 0ℚ) refl (inv₀ pool))
sum-shares pool (a ∷ as) rewrite sum-shares pool as =
  solve 3 (λ x s i → x :* i :+ s :* i := (x :+ s) :* i) refl a (sum as) (inv₀ pool)

shares-outside : ∀ pool as → pool ≢ 0ℚ → sum (shares pool as) + outside pool as ≡ 1ℚ
shares-outside pool as hp =
  trans (cong (_+ outside pool as) (sum-shares pool as))
    (trans (solve 3 (λ s p i → s :* i :+ (p :- s) :* i := p :* i) refl (sum as) pool (inv₀ pool))
      (inv₀-inverse pool hp))

-- Audiences within the pool have shares within 1.
coherent-shares : ∀ pool as → 0ℚ < pool → sum as ≤ pool → sum (shares pool as) ≤ 1ℚ
coherent-shares pool as hp h =
  subst (_≤ 1ℚ) (sym (sum-shares pool as))
    (div-le-of-le-mul hp (subst (sum as ≤_) (sym (solve 1 (λ p → con 1ℚ :* p := p) refl pool)) h))

-- ---------------------------------------------------------------------------------------------
-- The coherence count

-- A slot: its pool and the channels' forecasts.
Slot : Set
Slot = ℚ × List ℚ

overPool : Slot → Bool
overPool (pool , fs) = does (pool <? sum fs)

-- The number of slots over their pool (the results table gives it as a share of the slots).
countOver : List Slot → ℚ
countOver []       = 0ℚ
countOver (s ∷ ss) = (if overPool s then 1ℚ else 0ℚ) + countOver ss

Coherent : Slot → Set
Coherent (pool , fs) = sum fs ≤ pool

countOver-coherent : ∀ ss → All Coherent ss → countOver ss ≡ 0ℚ
countOver-coherent []              []       = refl
countOver-coherent ((p , fs) ∷ ss) (h ∷ hs) =
  trans (cong (λ b → (if b then 1ℚ else 0ℚ) + countOver ss)
              (dec-false (p <? sum fs) (λ p<s → <-irrefl′ (≤-<-trans′ h p<s))))
        (trans (+-identityˡ′ (countOver ss)) (countOver-coherent ss hs))
  where
  open import Data.Rational.Properties using () renaming (+-identityˡ to +-identityˡ′)
  open import Data.Rational.Properties using () renaming (<-irrefl to <-irrefl″; ≤-<-trans to ≤-<-trans′)
  <-irrefl′ : ∀ {x} → ¬ (x < x)
  <-irrefl′ x<x = <-irrefl″ refl x<x
