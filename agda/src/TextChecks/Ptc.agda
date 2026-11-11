{-# OPTIONS --safe --without-K #-}

-- The PTC rules of the video script (`z3-scala/src/main/scala/ptc/domain/Ptc.scala`,
-- `z3-scala/z3.sh ptc`), the part that Agda can state: the eight checks of `CHECKS`, their
-- limits and their status at level `leve`, and the verdict over the units of the script.
--
-- What is not here, and why. A check measures each unit of the script with Java regular
-- expressions: the words of a sentence (PTC-5), the hits of a pattern of spelling (PTC-8),
-- numbers (PTC-7), noise (PTC-9), clitics (PTC-1) and frozen names (PTC-6). Agda proves while it
-- type-checks, and a type-checker does not read the files of the repository, so the measures
-- stay in Scala, and this module takes them as functions. To state the patterns themselves
-- would need a model of Java's regular expressions, lookbehind included, and a proof that a
-- matcher follows it; Z3 trusts Java's matcher in the same way. The rules that `--review`
-- lists (a pronoun's reference, the scope of a condition, the meaning of a modal) need the
-- meaning of a sentence, which no formula over the text gives (z3-scala/README.md, "PTC rules
-- that Z3 cannot prove").
module TextChecks.Ptc where

open import Data.Bool using (Bool; true; false)
open import Data.List using (List; []; _∷_; map)
open import Data.List.Relation.Unary.All using (All)
open import Data.Nat using (ℕ; _≤_; z≤n)
open import Data.Nat.Properties using (n≤0⇒n≡0)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import TextChecks.Verdict

-- 00-como-ler.md, line 6: at most 35 words in a sentence (PTC-5 at level leve).
MAX-WORDS : ℕ
MAX-WORDS = 35

-- At most 6 sentences in a paragraph (recommended at level leve).
MAX-SENTENCES : ℕ
MAX-SENTENCES = 6

-- What a check is measured over.
data Over : Set where
  sentence paragraph : Over

-- A check of `CHECKS`: its rule, its status at level leve, its unit and its limit.
record Check : Set where
  constructor check
  field
    rule   : String
    status : Status
    over   : Over
    limit  : ℕ

-- `CHECKS`, in its order. A check of hits (PTC-7, -8, -9, -1, -6) has the limit 0.
CHECKS : List Check
CHECKS =
  check "PTC-5" required    sentence  MAX-WORDS ∷
  check "PTC-7" required    sentence  0 ∷
  check "PTC-8" required    sentence  0 ∷
  check "PTC-9" required    sentence  0 ∷
  check "PTC-1" required    sentence  0 ∷
  check "PTC-6" required    sentence  0 ∷
  check "PTC-9" recommended sentence  0 ∷
  check "PTC"   recommended paragraph MAX-SENTENCES ∷
  []

-- A check of hits holds exactly when no unit has a hit.
hits-holds : ∀ {U : Set} (hits : U → ℕ) us →
  Limit.holds hits 0 us ≡ true → All (λ u → hits u ≡ 0) us
hits-holds hits us h = Data.List.Relation.Unary.All.map n≤0⇒n≡0 (Limit.holds-within hits 0 us h)

-- The run of `ptc`: each check with its measure over its units. The exit code is 0 exactly
-- when every required check holds (`exit-zero`, `zero-exit`); the two recommended checks only
-- give NOTE lines.
run : ∀ {S P : Set} (sentences : List S) (paragraphs : List P)
      (measureS : String → S → ℕ) (measureP : P → ℕ) → List (Status × Bool)
run sentences paragraphs measureS measureP = map line CHECKS
  where
  line : Check → Status × Bool
  line (check r s sentence  l) = s , Limit.holds (measureS r) l sentences
  line (check r s paragraph l) = s , Limit.holds measureP l paragraphs

-- A text with no sentence passes every check.
empty-passes : ∀ {S P : Set} (mS : String → S → ℕ) (mP : P → ℕ) → exit (run [] [] mS mP) ≡ 0
empty-passes mS mP = refl
