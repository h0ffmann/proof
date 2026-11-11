{-# OPTIONS --safe --without-K #-}

-- What Z3 decides in the text checks of z3-scala (the PTC rules, the PTC-9 noise catalogue and
-- the language rule): the verdict over the measured units.
--
-- Each text check measures a value on every unit of the text (a sentence, a paragraph, a file,
-- a pair of a catalogue row and a sentence), gives the values to Z3 as constants, and asks for
-- a model of "some unit breaks the rule". `unsat` is the verdict OK; `sat` gives the units of
-- the model, which the report lists. Here a rule is a Boolean test `bad` on a unit. `broken`
-- lists the units that break it and `holds` is the verdict. The theorems say that the verdict
-- and the list are right for every text: OK exactly when no unit breaks the rule, and the
-- report lists every unit that breaks it and no other.
module TextChecks.Verdict where

open import Data.Bool using (Bool; true; false; if_then_else_; not; _∧_; _∨_; T)
open import Data.List using (List; []; _∷_; null)
open import Data.List.Membership.Propositional using (_∈_)
open import Data.List.Relation.Unary.All using (All; []; _∷_)
open import Data.List.Relation.Unary.Any using (here; there)
open import Data.Nat using (ℕ; _≤_; _<ᵇ_; _≤ᵇ_)
import Data.Nat.Properties as ℕₚ
open import Data.Product using (_×_; _,_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; trans; subst)
open import Relation.Nullary using (¬_; contradiction)

module Rule {U : Set} (bad : U → Bool) where

  -- The units that break the rule, in the order of the text: the units of Z3's model.
  broken : List U → List U
  broken []       = []
  broken (u ∷ us) = if bad u then u ∷ broken us else broken us

  -- The verdict: no unit breaks the rule (Z3's `unsat`).
  holds : List U → Bool
  holds us = null (broken us)

  Clean : List U → Set
  Clean = All (λ u → bad u ≡ false)

  holds-sound : ∀ us → holds us ≡ true → Clean us
  holds-sound []       _ = []
  holds-sound (u ∷ us) h with bad u in eq
  ... | false = eq ∷ holds-sound us h

  holds-complete : ∀ us → Clean us → holds us ≡ true
  holds-complete []       []         = refl
  holds-complete (u ∷ us) (ok ∷ oks) rewrite ok = holds-complete us oks

  broken-sound : ∀ {u} us → u ∈ broken us → u ∈ us × bad u ≡ true
  broken-sound (v ∷ us) m with bad v in eq
  broken-sound (v ∷ us) (here refl) | true = here refl , eq
  broken-sound (v ∷ us) (there m)   | true with broken-sound us m
  ... | m′ , b = there m′ , b
  broken-sound (v ∷ us) m           | false with broken-sound us m
  ... | m′ , b = there m′ , b

  broken-complete : ∀ {u} us → u ∈ us → bad u ≡ true → u ∈ broken us
  broken-complete (v ∷ us) (here refl) b rewrite b = here refl
  broken-complete (v ∷ us) (there m)   b with bad v
  ... | true  = there (broken-complete us m b)
  ... | false = broken-complete us m b

-- A rule "measure ≤ limit" (Ptc.scala, `Check`): a unit breaks it when its measure is above
-- the limit.
module Limit {U : Set} (measure : U → ℕ) (limit : ℕ) where
  open Rule (λ u → limit <ᵇ measure u) public

  -- OK exactly when every unit is within the limit.
  holds-within : ∀ us → holds us ≡ true → All (λ u → measure u ≤ limit) us
  holds-within us h = map-all (holds-sound us h)
    where
    within : ∀ u → (limit <ᵇ measure u) ≡ false → measure u ≤ limit
    within u eq = ℕₚ.≮⇒≥ (λ lt → subst T eq (ℕₚ.<⇒<ᵇ lt))
    map-all : ∀ {vs} → Clean vs → All (λ u → measure u ≤ limit) vs
    map-all []         = []
    map-all (ok ∷ oks) = within _ ok ∷ map-all oks

  within-holds : ∀ us → All (λ u → measure u ≤ limit) us → holds us ≡ true
  within-holds us all = holds-complete us (map-all all)
    where
    clean : ∀ u → measure u ≤ limit → (limit <ᵇ measure u) ≡ false
    clean u le with limit <ᵇ measure u in eq
    ... | false = refl
    ... | true  = contradiction (ℕₚ.<ᵇ⇒< limit (measure u) (subst T (sym eq) _)) (ℕₚ.≤⇒≯ le)
    map-all : ∀ {vs} → All (λ u → measure u ≤ limit) vs → Clean vs
    map-all []       = []
    map-all (h ∷ hs) = clean _ h ∷ map-all hs

-- ---------------------------------------------------------------------------------------------
-- The run: one line per check, and the exit code.

-- The tag of a report line: OK, FAIL (a required check fails), NOTE (a recommended check
-- fails) and OFF (a table that the level turns off; `NoiseCatalogue.scala` only).
data Tag : Set where
  OK FAIL NOTE OFF : Tag

data Status : Set where
  required recommended off : Status

tag : Status → Bool → Tag
tag _           true  = OK
tag required    false = FAIL
tag recommended false = NOTE
tag off         false = OFF

-- A line fails the run when its tag is FAIL.
fails : Status → Bool → Bool
fails required false = true
fails _        _     = false

-- The exit code is 1 when any line fails the run.
exit : List (Status × Bool) → ℕ
exit []              = 0
exit ((s , h) ∷ ls) = if fails s h then 1 else exit ls

-- The exit code is 0 exactly when every required check holds. A recommended or an off check
-- never fails the run.
exit-zero : ∀ ls → exit ls ≡ 0 → All (λ { (s , h) → s ≡ required → h ≡ true }) ls
exit-zero []                   _ = []
exit-zero ((required , true) ∷ ls) e = (λ _ → refl) ∷ exit-zero ls e
exit-zero ((recommended , h) ∷ ls) e = (λ ()) ∷ exit-zero ls e
exit-zero ((off , h) ∷ ls)         e = (λ ()) ∷ exit-zero ls e

zero-exit : ∀ ls → All (λ { (s , h) → s ≡ required → h ≡ true }) ls → exit ls ≡ 0
zero-exit []                   []       = refl
zero-exit ((required , h) ∷ ls) (p ∷ ps) rewrite p refl = zero-exit ls ps
zero-exit ((recommended , h) ∷ ls) (_ ∷ ps) = zero-exit ls ps
zero-exit ((off , h) ∷ ls)         (_ ∷ ps) = zero-exit ls ps

tag-fail : ∀ s h → tag s h ≡ FAIL → fails s h ≡ true
tag-fail required false _ = refl
