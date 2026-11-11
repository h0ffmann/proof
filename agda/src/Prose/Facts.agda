{-# OPTIONS --safe --without-K #-}

-- An STE edition of a text may change words, never facts. This compares the facts of two
-- texts: the citation keys (`@key`) and the numbers, each as a multiset. `same` is true exactly
-- when every fact has the same count in both texts (`same-sound`, `same-complete`). It is the part
-- of the old `ste-check` (Gleam, removed on 2026-11-11) that is a decision on the tokens.
module Prose.Facts where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_; T)
open import Data.Bool.ListAction using (any; all)
open import Data.Char using (Char; isDigit; isAlpha)
open import Data.Empty using (⊥-elim)
open import Data.Unit using (tt)
open import Data.List using (List; []; _∷_; _++_; map; concatMap; null; filterᵇ)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Membership.Propositional.Properties using (∈-++⁺ˡ; ∈-++⁺ʳ)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Nat using (ℕ; zero; suc; _≡ᵇ_)
import Data.Nat.Properties as ℕₚ
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String; fromList) renaming (toList to toL; _++_ to _⊕_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; subst; cong)
open import Relation.Nullary using (yes; no)
open import Relation.Nullary.Decidable using (⌊_⌋)

open import Prose.Text
open import Prose.Words

-- How many times a fact is in a list.
count : Txt → List Txt → ℕ
count f []       = 0
count f (g ∷ gs) = if g === f then suc (count f gs) else count f gs

every : (Txt → Bool) → List Txt → Bool
every p []       = true
every p (x ∷ xs) = p x ∧ every p xs

-- The test of `same`: for each fact of either text, the two counts are equal.
same : List Txt → List Txt → Bool
same a b = every (λ f → count f a ≡ᵇ count f b) (a ++ b)

------------------------------------------------------------------------------------------------
-- Proofs

===-sound : ∀ x y → (x === y) ≡ true → x ≡ y
===-sound x y eq with x ≡? y
... | yes p = p

===-refl : ∀ x → (x === x) ≡ true
===-refl x with x ≡? x
... | yes _  = refl
... | no  ¬p = ⊥-elim (¬p refl)

-- A fact with a count above zero is in the list.
count-∈ : ∀ f gs {n} → count f gs ≡ suc n → f ∈ gs
count-∈ f (g ∷ gs) eq with g === f in e
... | true  = here (sym (===-sound g f e))
... | false = there (count-∈ f gs eq)

every-∈ : ∀ (p : Txt → Bool) xs {x} → every p xs ≡ true → x ∈ xs → p x ≡ true
every-∈ p (y ∷ ys) h (here refl) with p y
... | true = refl
every-∈ p (y ∷ ys) h (there m) with p y
... | true = every-∈ p ys h m

≡ᵇ-refl : ∀ n → (n ≡ᵇ n) ≡ true
≡ᵇ-refl zero    = refl
≡ᵇ-refl (suc n) = ≡ᵇ-refl n

same-at : ∀ a b → same a b ≡ true → ∀ {f} → f ∈ a ++ b → count f a ≡ count f b
same-at a b h m = ℕₚ.≡ᵇ⇒≡ _ _ (subst T (sym (every-∈ _ (a ++ b) h m)) tt)

-- `same` is sound: every fact, of the texts or not, has the same count in both.
same-sound : ∀ a b → same a b ≡ true → ∀ f → count f a ≡ count f b
same-sound a b h f with count f a in ea | count f b in eb
... | zero  | zero  = refl
... | suc m | _     = trans (sym ea) (trans (same-at a b h (∈-++⁺ˡ (count-∈ f a ea))) eb)
... | zero  | suc n = trans (sym ea) (trans (same-at a b h (∈-++⁺ʳ a (count-∈ f b eb))) eb)

-- `same` is complete: equal counts give `true`.
same-complete : ∀ a b → (∀ f → count f a ≡ count f b) → same a b ≡ true
same-complete a b eq = go (a ++ b)
  where
  go : ∀ xs → every (λ f → count f a ≡ᵇ count f b) xs ≡ true
  go []       = refl
  go (x ∷ xs) rewrite eq x | ≡ᵇ-refl (count x b) = go xs

------------------------------------------------------------------------------------------------
-- The facts of a text

-- A citation key (`@key`, `-@key`) or a number (a token that starts with a digit), without the
-- marks around it.
fact : Txt → Bool
fact w with core w
... | []     = false
... | c ∷ _  = isDigit c ∨ citation w
  where
  citation : Txt → Bool
  citation ('@' ∷ d ∷ _)       = isAlpha d
  citation ('-' ∷ '@' ∷ d ∷ _) = isAlpha d
  citation ('[' ∷ cs)          = citation cs
  citation _                   = false

facts : Txt → List Txt
facts t = concatMap (λ q → concatMap (λ s → map key (filterᵇ (λ x → fact (Token.chars x)) (plain s)))
                                     (sentencesOf q)) (paragraphs t)
  where
  key : Token → Txt
  key x = keep (Token.chars x)
    where
    -- `@key` keeps its `@`; a number loses its marks.
    keep : Txt → Txt
    keep cs = at (dropBefore cs)
      where
      dropBefore : Txt → Txt
      dropBefore []        = []
      dropBefore ('@' ∷ r) = '@' ∷ r
      dropBefore (c ∷ r)   = if alnum c then c ∷ r else dropBefore r
      at : Txt → Txt
      at ('@' ∷ r) = '@' ∷ core r
      at r         = core r

-- The facts that one text has more times than the other.
more : List Txt → List Txt → List Txt
more a b = go a []
  where
  go : List Txt → List Txt → List Txt
  go []       seen = []
  go (f ∷ fs) seen = if memberOf f seen then go fs seen
                     else (if count f b Data.Nat.<ᵇ count f a then f ∷ go fs (f ∷ seen) else go fs (f ∷ seen))

compare : String → Txt → String → Txt → List String × ℕ
compare pa a pb b with facts a | facts b
... | fa | fb = if same fa fb then ("OK    " ⊕ pb ⊕ " keeps the citations and numbers of " ⊕ pa) ∷ [] , 0
               else (("FAIL  " ⊕ pb ⊕ " changes the citations or numbers of " ⊕ pa)
                     ∷ ("        lost: " ⊕ shown (more fa fb)) ∷ ("        added: " ⊕ shown (more fb fa)) ∷ []) , 1
  where
  shown : List Txt → String
  shown []       = ""
  shown (f ∷ []) = fromList f
  shown (f ∷ fs) = fromList f ⊕ ", " ⊕ shown fs
