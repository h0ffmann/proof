{-# OPTIONS --safe --without-K #-}

-- The language rule of the repository (`z3-scala/src/main/scala/language/domain/LanguageRule.scala`,
-- `just z3`): every file is in English, except a file whose path carries `pt-BR`, which is in
-- Brazilian Portuguese. For every tracked text file f, portuguese(f) ↔ marked(f).
--
-- `LanguageRule.scala` counts the Portuguese and English stop words of each file, with code
-- left out, and judges the file Portuguese when its Portuguese stop words are more than twice its
-- English ones. A file with fewer than 20 stop words is not judged. The counts come from Java
-- regular expressions on the files, so they stay in Scala (TextChecks.Ptc says why). Here are
-- the judgement on the counts, the rule, and the verdict over the files.
module TextChecks.Language where

open import Data.Bool using (Bool; true; false; if_then_else_; _xor_; not)
open import Data.List using (List)
open import Data.List.Relation.Unary.All using (All)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat using (ℕ; _+_; _*_; _<ᵇ_; _<_)
import Data.Nat.Properties as ℕₚ
open import Data.Product using (_×_; _,_)
open import Data.Sum using (_⊎_; inj₁; inj₂)
open import Relation.Binary.PropositionalEquality using (_≡_; refl; sym; subst)

open import TextChecks.Verdict

-- The number of stop words of both languages below which a file is not judged.
MINIMUM : ℕ
MINIMUM = 20

-- `isPortuguese`: nothing when the file has too few stop words, else whether it is Portuguese.
judge : (pt en : ℕ) → Maybe Bool
judge pt en = if pt + en <ᵇ MINIMUM then nothing else just (2 * en <ᵇ pt)

-- A judged file breaks the rule when it is Portuguese and not marked, or marked and not
-- Portuguese: Z3's `xor(p, m)`.
breaks : (marked : Bool) → Maybe Bool → Bool
breaks marked nothing           = false
breaks marked (just portuguese) = portuguese xor marked

-- A file is its path's mark and its two counts.
record File : Set where
  constructor file
  field
    marked : Bool
    pt en  : ℕ

bad : File → Bool
bad (file m pt en) = breaks m (judge pt en)

open Rule bad public using (broken; holds; holds-sound; holds-complete; broken-sound; broken-complete)

-- A file with fewer than 20 stop words never breaks the rule.
short-not-judged : ∀ m pt en → pt + en < MINIMUM → bad (file m pt en) ≡ false
short-not-judged m pt en lt with pt + en <ᵇ MINIMUM in eq
... | true  = refl
... | false = ⊥-elim (subst T eq (ℕₚ.<⇒<ᵇ lt))
  where
  open import Data.Bool using (T)
  open import Data.Empty using (⊥-elim)

-- A judged file keeps the rule exactly when it is Portuguese and marked, or neither.
judged-rule : ∀ m pt en → (pt + en <ᵇ MINIMUM) ≡ false →
  bad (file m pt en) ≡ false → (2 * en <ᵇ pt) ≡ m
judged-rule m pt en j ok with pt + en <ᵇ MINIMUM | j
... | false | refl with 2 * en <ᵇ pt | m | ok
...   | true  | true  | _ = refl
...   | false | false | _ = refl
