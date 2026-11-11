{-# OPTIONS --safe --without-K #-}

-- The rival line-up features of `tv-audience/python/experiment.py` (`build_features`), for one
-- slot. A slot is the list of its channels' programmes; each programme has a genre, a hype (0 for
-- a regular episode) and a big-show flag. The schedules are published a week ahead, so these
-- features are known when the forecast is made.
--
--   n_same_genre   = channels of the slot with the same genre, the channel itself left out
--   slot_sum_hype  = Σ hype over the slot        rival_sum_hype = slot_sum_hype - own hype
--   slot_max_hype  = max hype over the slot      rival_max_hype = max hype of the others
--   rival_big      = some other channel shows a big show
--
-- `picks` pairs each programme with the others of its slot (the Python's `np.delete(h, i)`). The
-- theorems: every channel gets one row, its rivals are the slot minus itself, the own hype plus the
-- rivals' is the slot's sum, the rivals' maximum is at most the slot's, and at most C - 1 rivals
-- share a genre. `rival_lag_sum` (log Σ exp) needs logarithms and stays out.
module TvAudience.Features where

open import Data.Bool using (Bool; true; false; if_then_else_; _∨_)
open import Data.List using (List; []; _∷_; map; length)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.List.Relation.Unary.All.Properties using (map⁺)
open import Data.Nat as ℕ using (ℕ; zero; suc; _≡ᵇ_)
open import Data.Nat.Properties as ℕP using (≤-refl; m≤n⇒m≤1+n)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.Rational using (ℚ; 0ℚ; _+_; _≤_; _⊔_)
open import Data.Rational.Properties
  using (≤-trans; p≤p⊔q; p≤q⊔p; ⊔-lub; ⊔-mono-≤)
  renaming (≤-refl to ≤ℚ-refl)
open import Data.Rational.Solver using (module +-*-Solver)
open +-*-Solver using (solve; _:=_; _:+_; con)
open import Relation.Binary.PropositionalEquality
  using (_≡_; refl; sym; trans; cong; cong₂)

record Programme : Set where
  constructor prog
  field
    genre : ℕ
    hype  : ℚ
    big   : Bool
open Programme public

Slot : Set
Slot = List Programme

-- Each programme with the other programmes of its slot.
picks : ∀ {A : Set} → List A → List (A × List A)
picks []       = []
picks (x ∷ xs) = (x , xs) ∷ map (λ { (y , ys) → (y , x ∷ ys) }) (picks xs)

sumHype maxHype : Slot → ℚ
sumHype []       = 0ℚ
sumHype (p ∷ ps) = hype p + sumHype ps
maxHype []       = 0ℚ
maxHype (p ∷ ps) = hype p ⊔ maxHype ps

nSameGenre : Programme → Slot → ℕ
nSameGenre p []       = 0
nSameGenre p (q ∷ qs) = if genre p ≡ᵇ genre q then suc (nSameGenre p qs) else nSameGenre p qs

anyBig : Slot → Bool
anyBig []       = false
anyBig (q ∷ qs) = big q ∨ anyBig qs

-- One channel's rival features, from its programme and its rivals'.
record Rival : Set where
  constructor rival
  field
    sameGenre : ℕ
    rivalSum  : ℚ
    rivalMax  : ℚ
    rivalBig  : Bool
open Rival public

rivalFeatures : Programme → Slot → Rival
rivalFeatures p others = rival (nSameGenre p others) (sumHype others) (maxHype others) (anyBig others)

-- The rival features of every channel of a slot, in its order.
slotFeatures : Slot → List Rival
slotFeatures s = map (λ { (p , others) → rivalFeatures p others }) (picks s)

-- ---------------------------------------------------------------------------------------------

length-map : ∀ {A B : Set} (f : A → B) xs → length (map f xs) ≡ length xs
length-map f []       = refl
length-map f (x ∷ xs) = cong suc (length-map f xs)

picks-length : ∀ {A : Set} (xs : List A) → length (picks xs) ≡ length xs
picks-length []       = refl
picks-length (x ∷ xs) = cong suc (trans (length-map _ (picks xs)) (picks-length xs))

-- Every channel has C - 1 rivals.
picks-rivals : ∀ {A : Set} (xs : List A) → All (λ { (_ , ys) → suc (length ys) ≡ length xs }) (picks xs)
picks-rivals []       = []
picks-rivals (x ∷ xs) = refl ∷ map⁺ (go (picks xs) (picks-rivals xs))
  where
  go : ∀ ps → All (λ { (_ , ys) → suc (length ys) ≡ length xs }) ps →
       All (λ { (_ , ys) → suc (length (x ∷ ys)) ≡ length (x ∷ xs) }) ps
  go []             []       = []
  go ((y , ys) ∷ ps) (h ∷ hs) = cong suc h ∷ go ps hs

-- Own hype plus the rivals' hype is the slot's: rival_sum_hype = slot_sum_hype - hype.
picks-sum : ∀ s → All (λ { (p , others) → hype p + sumHype others ≡ sumHype s }) (picks s)
picks-sum []       = []
picks-sum (x ∷ xs) = refl ∷ map⁺ (go (picks xs) (picks-sum xs))
  where
  go : ∀ ps → All (λ { (p , others) → hype p + sumHype others ≡ sumHype xs }) ps →
       All (λ { (p , others) → hype p + sumHype (x ∷ others) ≡ sumHype (x ∷ xs) }) ps
  go []             []       = []
  go ((y , ys) ∷ ps) (h ∷ hs) =
    trans (solve 3 (λ a b c → a :+ (b :+ c) := b :+ (a :+ c)) refl (hype y) (hype x) (sumHype ys))
          (cong (hype x +_) h) ∷ go ps hs

-- The rivals' largest hype is at most the slot's: rival_max_hype ≤ slot_max_hype.
picks-max : ∀ s → All (λ { (p , others) → maxHype others ≤ maxHype s }) (picks s)
picks-max []       = []
picks-max (x ∷ xs) = p≤q⊔p (hype x) (maxHype xs) ∷ map⁺ (go (picks xs) (picks-max xs))
  where
  go : ∀ ps → All (λ { (p , others) → maxHype others ≤ maxHype xs }) ps →
       All (λ { (p , others) → maxHype (x ∷ others) ≤ maxHype (x ∷ xs) }) ps
  go []             []       = []
  go ((y , ys) ∷ ps) (h ∷ hs) = ⊔-mono-≤ (ℚ-refl′ (hype x)) h ∷ go ps hs
    where
    ℚ-refl′ : ∀ q → q ≤ q
    ℚ-refl′ q = ≤ℚ-refl

-- At most all the rivals share the channel's genre.
nSameGenre-le : ∀ p qs → nSameGenre p qs ℕ.≤ length qs
nSameGenre-le p []       = ℕ.z≤n
nSameGenre-le p (q ∷ qs) with genre p ≡ᵇ genre q
... | true  = ℕ.s≤s (nSameGenre-le p qs)
... | false = m≤n⇒m≤1+n (nSameGenre-le p qs)

-- A slot of one channel has no rival: every rival feature is 0.
alone : ∀ p → slotFeatures (p ∷ []) ≡ rival 0 0ℚ 0ℚ false ∷ []
alone p = refl
