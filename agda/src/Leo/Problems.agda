{-# OPTIONS --safe --without-K #-}

-- The five TPTP problems of `z3-scala/leo/`, ported from THF to Agda. Leo-III proves four of
-- them and must not prove the fifth. Each problem here has the name of its file, with `-` for
-- `_`. A conjecture that Leo-III must prove is a theorem. The conjecture that Leo-III must not
-- prove is refuted: Agda gives a function that breaks it.
--
-- Leo-III works in classical higher-order logic with Henkin semantics and choice. Agda is
-- constructive. The differences, problem by problem:
--
-- * `belief.p` and `composition.p` hold by computation (`cong` and `refl`).
-- * `cantor.p` quantifies over the sets of a type, `$i > $o`. A set is a predicate here, in two
--   forms: a Boolean function (`cantor`) and a function into `Set` (`cantor-Set`). Each proof
--   uses the diagonal set and needs no classical step, because the diagonal argument is a
--   proof of a negation.
-- * `choice_inverse.p` needs choice in Leo-III. In Agda, "for every y there is an x" is a
--   dependent pair, so the right inverse is the first projection: choice is a theorem of type
--   theory. A statement with a truncated existence (`∥ Σ ∥`) would need an axiom, and is not
--   made here.
-- * `surjective_not_injective.p` is false. `$i` is any non-empty type, so a counterexample on
--   one type is enough: `pred` on ℕ is onto ℕ, and `pred 0 ≡ pred 1`.
module Leo.Problems where

open import Data.Bool.Base using (Bool; true; false; not)
open import Data.Empty using (⊥)
open import Data.Nat.Base using (ℕ; zero; suc; pred)
open import Data.Product.Base using (Σ; ∃; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; cong; sym; subst)
open import Relation.Nullary using (¬_)

private
  variable
    A B C : Set

Surjective : (A → B) → Set
Surjective {A} {B} f = ∀ (y : B) → Σ A λ x → f x ≡ y

Injective : (A → B) → Set
Injective f = ∀ a b → f a ≡ f b → a ≡ b

-- belief.p: a policy that is a function of the belief gives two histories with the same
-- belief the same action, for every belief map B and every way G of acting on a belief.
through-belief : (b : A → B) (g : B → C) (h₁ h₂ : A) → b h₁ ≡ b h₂ → g (b h₁) ≡ g (b h₂)
through-belief b g h₁ h₂ = cong g

-- cantor.p: no function from a type onto the sets of that type. Sets as Boolean predicates.
cantor : ¬ (Σ (A → A → Bool) λ F → ∀ (Y : A → Bool) → ∃ λ x → F x ≡ Y)
cantor (F , onto) with onto (λ x → not (F x x))
... | x , Fx≡Y = no-fixpoint (F x x) (cong (λ f → f x) Fx≡Y)
  where
  no-fixpoint : ∀ b → b ≡ not b → ⊥
  no-fixpoint true  ()
  no-fixpoint false ()

-- cantor.p with sets as predicates into Set: the diagonal set is ¬ F x x.
cantor-Set : ¬ (Σ (A → A → Set) λ F → ∀ (Y : A → Set) → ∃ λ x → F x ≡ Y)
cantor-Set (F , onto) with onto (λ x → ¬ F x x)
... | x , Fx≡Y = not-in (in′ not-in)
  where
  same : F x x ≡ (¬ F x x)
  same = cong (λ f → f x) Fx≡Y
  in′ : ¬ F x x → F x x
  in′ = subst (λ S → S) (sym same)
  not-in : ¬ F x x
  not-in p = subst (λ S → S) same p p

-- choice_inverse.p: a surjective function has a right inverse.
surj-right-inverse : (f : A → B) → Surjective f → Σ (B → A) λ g → ∀ y → f (g y) ≡ y
surj-right-inverse f onto = (λ y → proj₁ (onto y)) , (λ y → proj₂ (onto y))

-- composition.p: composition is associative. Both sides are the same function by computation.
compose : (f g h : A → A) →
  (λ x → f ((λ y → g (h y)) x)) ≡ (λ x → (λ y → f (g y)) (h x))
compose f g h = refl

-- surjective_not_injective.p, refuted: pred is onto ℕ and is not one to one.
pred-surjective : Surjective pred
pred-surjective y = suc y , refl

surj-injective-refuted : ¬ (∀ (f : ℕ → ℕ) → Surjective f → Injective f)
surj-injective-refuted claim with claim pred pred-surjective 0 1 refl
... | ()
