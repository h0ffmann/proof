{-# OPTIONS --safe --without-K #-}

-- The PTC-9 noise catalogue (`z3-scala/src/main/scala/ptc/domain/NoiseCatalogue.scala`,
-- `just ruido-ia`), the part that Agda can state: the level table of the four sections, the
-- tag of each table line, and the verdict over the pairs of a decided row and a sentence.
--
-- The rows themselves are Java regular expressions with the "O que fica" exceptions, and the
-- hits are measured on the script's text, so they stay in Scala (TextChecks.Ptc says why). A
-- row that is "read" needs the meaning of a sentence, and is listed for a person.
module TextChecks.NoiseCatalogue where

open import Data.Bool using (Bool; true; false)
open import Data.List using (List; []; _∷_; cartesianProduct)
open import Data.List.Relation.Unary.All using (All)
open import Data.Nat using (ℕ)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl)

open import TextChecks.Verdict

data Level : Set where
  leve descritivo estrito : Level

data Section : Set where
  sempre-sai enchimento evasão-de-cópula inflação : Section

-- SECTIONS: the line under each table heading of ruido-ia.md.
status : Section → Level → Status
status sempre-sai _       = required
status enchimento leve    = recommended
status enchimento _       = required
status evasão-de-cópula leve = off
status evasão-de-cópula _    = required
status inflação leve      = off
status inflação _         = required

-- leve ⊑ descritivo ⊑ estrito, and off < recommended < required.
data _⊑_ : Level → Level → Set where
  refl⊑      : ∀ {l} → l ⊑ l
  leve⊑      : ∀ {l} → leve ⊑ l
  descritivo⊑estrito : descritivo ⊑ estrito

data _≼_ : Status → Status → Set where
  refl≼ : ∀ {s} → s ≼ s
  off≼  : ∀ {s} → off ≼ s
  rec≼  : recommended ≼ required

-- "Sempre sai" is required at every level.
sempre-sai-required : ∀ l → status sempre-sai l ≡ required
sempre-sai-required _ = refl

-- A stricter level never relaxes a section.
stricter-never-relaxes : ∀ s {l l′} → l ⊑ l′ → status s l ≼ status s l′
stricter-never-relaxes s refl⊑ = refl≼
stricter-never-relaxes sempre-sai       {l′ = l′} leve⊑ = refl≼
stricter-never-relaxes enchimento       {l′ = leve} leve⊑ = refl≼
stricter-never-relaxes enchimento       {l′ = descritivo} leve⊑ = rec≼
stricter-never-relaxes enchimento       {l′ = estrito} leve⊑ = rec≼
stricter-never-relaxes evasão-de-cópula leve⊑ = off≼
stricter-never-relaxes inflação         leve⊑ = off≼
stricter-never-relaxes sempre-sai       descritivo⊑estrito = refl≼
stricter-never-relaxes enchimento       descritivo⊑estrito = refl≼
stricter-never-relaxes evasão-de-cópula descritivo⊑estrito = refl≼
stricter-never-relaxes inflação         descritivo⊑estrito = refl≼

-- At level leve only "Sempre sai" can fail the run.
leve-fails-only-sempre-sai : ∀ s h → fails (status s leve) h ≡ true → s ≡ sempre-sai
leve-fails-only-sempre-sai sempre-sai false _ = refl

-- One table: Z3 is asked for a (row, sentence) with a hit, over every pair of a decided row of
-- the section and a sentence (`prove`).
module Table {R S : Set} (hits : R → S → ℕ) (rows : List R) (sentences : List S) where
  pairs : List (R × S)
  pairs = cartesianProduct rows sentences

  open Limit (λ p → hits (proj₁ p) (proj₂ p)) 0 public

  verdict : Bool
  verdict = holds pairs

-- The run of `ruido-ia` at a level: one line per section, with its status at that level.
line : Level → Section → Bool → Status × Bool
line l s h = status s l , h
