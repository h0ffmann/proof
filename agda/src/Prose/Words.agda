{-# OPTIONS --safe --without-K #-}

-- Small tests on one word, shared by the STE and PTC rules.
module Prose.Words where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Bool.ListAction using (any; all)
open import Data.Char using (Char; isDigit; isAlpha)
open import Data.List using (List; []; _∷_; reverse; map; length; null)
open import Data.Nat using (ℕ; _<ᵇ_; _≤ᵇ_)
open import Data.String using (String; fromList) renaming (toList to toL)

open import Prose.Text

-- A word without the marks around it: the characters before its first letter or digit and after
-- its last one go.
core : Txt → Txt
core cs = reverse (front (reverse (front cs)))
  where
  front : Txt → Txt
  front []       = []
  front (c ∷ cs) = if alnum c then c ∷ cs else front cs

-- The typographic apostrophe as the plain one.
plainApostrophe : Txt → Txt
plainApostrophe = map (λ c → if c == '’' then '\'' else c)

endsWith : Txt → Txt → Bool
endsWith suffix cs = startsWith (reverse suffix) (reverse cs)

memberOf : Txt → List Txt → Bool
memberOf w = any (_=== w)

-- Text for a report line: the first `n` characters, with a code span shown as a backtick.
snippet : ℕ → Txt → String
snippet n cs = fromList (go n cs)
  where
  go : ℕ → Txt → Txt
  go _       []       = []
  go ℕ.zero  (_ ∷ _)  = toL "…"
  go (ℕ.suc n) (c ∷ cs) = if c == codeMark then '`' ∷ '…' ∷ '`' ∷ go n cs else c ∷ go n cs
