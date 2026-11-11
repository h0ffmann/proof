{-# OPTIONS --safe --without-K #-}

-- A prose check as a list of rules over units (a sentence or a paragraph of a file), and the
-- report of a run: one line per rule, the units that break it, and the exit code. The verdict and
-- the exit code are the ones of `TextChecks.Verdict`, so its theorems hold here: a rule is OK
-- exactly when no unit breaks it, the report lists every unit that breaks it and no other, and
-- the exit code is 0 exactly when every required rule is OK.
module Prose.Report where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.List using (List; []; _∷_; map; _++_; concatMap; length)
open import Data.List.Relation.Unary.All using (All)
open import Data.Nat using (ℕ)
open import Data.Nat.Show using (show)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String) renaming (_++_ to _⊕_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import TextChecks.Verdict public using (Status; required; recommended; off; Tag; OK; FAIL; NOTE; OFF; tag; exit; exit-zero; zero-exit)
open import TextChecks.Verdict using (module Rule)

-- A rule: its name in the standard, what it asks, its status, the test of a unit, and the line
-- that the report gives for a unit that breaks it.
record Check (U : Set) : Set where
  constructor check
  field
    rule   : String
    name   : String
    status : Status
    bad    : U → Bool
    show-u : U → String

-- The verdict of a rule on the units. A rule that is off has no verdict and never fails.
verdict : ∀ {U} → Check U → List U → Status × Bool
verdict (check _ _ off _ _) us = off , false
verdict (check _ _ s bad _) us = s , Rule.holds bad us

tagText : Tag → String
tagText OK   = "OK    "
tagText FAIL = "FAIL  "
tagText NOTE = "NOTE  "
tagText OFF  = "OFF   "

-- The lines of a rule: the tag line, then one line for each unit that breaks it.
lines : ∀ {U} → Check U → List U → List String
lines c@(check r n s bad sh) us with verdict c us
... | s′ , h = (tagText (tag s′ h) ⊕ r ⊕ ": " ⊕ n) ∷ units s′
  where
  units : Status → List String
  units off = []
  units _   = map (λ u → "        " ⊕ sh u) (Rule.broken bad us)

-- A rule applied to its units: the input of `report`.
record Applied : Set₁ where
  constructor _over_
  field
    {U}   : Set
    rule  : Check U
    units : List U

verdicts : List Applied → List (Status × Bool)
verdicts = map (λ { (c over us) → verdict c us })

-- The report of a run and its exit code.
report : List Applied → List String × ℕ
report as = concatMap (λ { (c over us) → lines c us }) as , exit (verdicts as)

-- A required rule that is OK has no unit that breaks it (`Rule.holds-sound`).
required-ok : ∀ {U} (r n : String) (bad : U → Bool) sh us →
  verdict (check r n required bad sh) us ≡ (required , true) → All (λ u → bad u ≡ false) us
required-ok r n bad sh us eq with Rule.holds bad us in h
required-ok r n bad sh us refl | true = Rule.holds-sound bad us h

-- A rule that is off never fails the run.
off-never-fails : ∀ {U} (r n : String) (bad : U → Bool) sh us →
  verdict (check r n off bad sh) us ≡ (off , false)
off-never-fails r n bad sh us = refl
