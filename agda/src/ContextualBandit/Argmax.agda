{-# OPTIONS --safe --without-K #-}

------------------------------------------------------------------------
-- Verified argmax
--
-- Every deterministic rule (greedy, UCB) is "argmax of some score". Here
-- argmax is defined once and proved to be a maximiser. Ties go to the
-- earliest arm: the running best changes only on a strict increase. That
-- is the convention of the Z3 specification and of the Haskell port.
------------------------------------------------------------------------

module ContextualBandit.Argmax where

open import Data.Fin.Base using (Fin; zero)
open import Data.List.Base using (List; []; _∷_; allFin)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Membership.Propositional.Properties using (∈-allFin)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Nat.Base using (ℕ; suc; NonZero)
open import Data.Rational.Base using (ℚ; _≤_; _<_)
open import Data.Rational.Properties using (_<?_; ≤-refl; ≤-trans; <⇒≤; ≮⇒≥)
open import Data.Sum.Base using (_⊎_; inj₁; inj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; trans)
open import Relation.Nullary.Decidable.Core using (Dec; yes; no)

open import ContextualBandit.Interface using (Arm)

private
  variable
    A : Set

-- One step of the fold: keep best unless a scores strictly higher.
choose : {x y : ℚ} → Dec (x < y) → A → A → A
choose (yes _) a best = a
choose (no _)  a best = best

pick : (A → ℚ) → A → A → A
pick f best a = choose (f best <? f a) a best

-- Left fold that keeps the first element with the largest score.
argmaxFrom : (A → ℚ) → A → List A → A
argmaxFrom f best []       = best
argmaxFrom f best (a ∷ as) = argmaxFrom f (pick f best a) as

pick-ge-best : (f : A → ℚ) (best a : A) → f best ≤ f (pick f best a)
pick-ge-best f best a with f best <? f a
... | yes p = <⇒≤ p
... | no  _ = ≤-refl

pick-ge-new : (f : A → ℚ) (best a : A) → f a ≤ f (pick f best a)
pick-ge-new f best a with f best <? f a
... | yes _ = ≤-refl
... | no ¬p = ≮⇒≥ ¬p

argmaxFrom-ge-start : (f : A → ℚ) (l : List A) (best : A) →
                      f best ≤ f (argmaxFrom f best l)
argmaxFrom-ge-start f []       best = ≤-refl
argmaxFrom-ge-start f (a ∷ as) best =
  ≤-trans (pick-ge-best f best a) (argmaxFrom-ge-start f as (pick f best a))

argmaxFrom-ge-mem : (f : A → ℚ) (l : List A) (best x : A) → x ∈ l →
                    f x ≤ f (argmaxFrom f best l)
argmaxFrom-ge-mem f (a ∷ as) best x (here refl) =
  ≤-trans (pick-ge-new f best a) (argmaxFrom-ge-start f as (pick f best a))
argmaxFrom-ge-mem f (a ∷ as) best x (there x∈as) =
  argmaxFrom-ge-mem f as (pick f best a) x x∈as

pick-mem : (f : A → ℚ) (best a : A) → pick f best a ≡ best ⊎ pick f best a ≡ a
pick-mem f best a with f best <? f a
... | yes _ = inj₂ refl
... | no  _ = inj₁ refl

-- The result is the start or an element of the list.
argmaxFrom-mem : (f : A → ℚ) (l : List A) (best : A) →
                 argmaxFrom f best l ≡ best ⊎ argmaxFrom f best l ∈ l
argmaxFrom-mem f []       best = inj₁ refl
argmaxFrom-mem f (a ∷ as) best
  with argmaxFrom-mem f as (pick f best a) | pick-mem f best a
... | inj₂ r∈as | _      = inj₂ (there r∈as)
... | inj₁ r≡p  | inj₁ p≡best = inj₁ (trans r≡p p≡best)
... | inj₁ r≡p  | inj₂ p≡a    = inj₂ (here (trans r≡p p≡a))

-- Equal scores give the same argmax.
pick-cong : (f g : A → ℚ) (best a : A) → f best ≡ g best → f a ≡ g a →
            pick f best a ≡ pick g best a
pick-cong f g best a eb ea rewrite eb | ea = refl

argmaxFrom-cong : (f g : A → ℚ) → (∀ x → f x ≡ g x) → (l : List A) (best : A) →
                  argmaxFrom f best l ≡ argmaxFrom g best l
argmaxFrom-cong f g f≡g []       best = refl
argmaxFrom-cong f g f≡g (a ∷ as) best
  rewrite pick-cong f g best a (f≡g best) (f≡g a) = argmaxFrom-cong f g f≡g as (pick g best a)

------------------------------------------------------------------------
-- Argmax over all K arms (needs at least one arm)

firstArm : (K : ℕ) → {{NonZero K}} → Arm K
firstArm (suc _) = zero

argmax : {K : ℕ} {{_ : NonZero K}} → (Arm K → ℚ) → Arm K
argmax {K} f = argmaxFrom f (firstArm K) (allFin K)

-- Spec of argmax: the chosen arm scores at least as high as every arm.
argmax-spec : {K : ℕ} {{_ : NonZero K}} (f : Arm K → ℚ) (a : Arm K) →
              f a ≤ f (argmax f)
argmax-spec {K} f a = argmaxFrom-ge-mem f (allFin K) (firstArm K) a (∈-allFin a)

argmax-cong : {K : ℕ} {{_ : NonZero K}} (f g : Arm K → ℚ) → (∀ a → f a ≡ g a) →
              argmax f ≡ argmax g
argmax-cong {K} f g f≡g = argmaxFrom-cong f g f≡g (allFin K) (firstArm K)
