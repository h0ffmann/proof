{-# OPTIONS --safe --without-K #-}

-- The PTC rules (português técnico controlado, level `leve`) of the video script that a program
-- decides on the characters of the text, in Agda: PTC-5 (at most 35 words in a sentence), the
-- decimal point, English thousands and the DD/MM/YYYY date of PTC-7, and the recommended limit of
-- 6 sentences in a paragraph. `tools/text-checks/Ptc.hs` keeps the other checks (the units, hours
-- and ranges of PTC-7, PTC-8, PTC-9, PTC-1, PTC-6): each one is a catalogue of patterns, and
-- each could be stated here in the same way, as a test on the tokens of a sentence.
--
-- A number with a point is not a decimal after the name of a thing that is numbered in parts:
-- a scene (`cena 1.2`), a section, a version, a model, and a paragraph of the note
-- (`parágrafo 1.7`), also in a list (`cenas 1.2, 1.3 e 1.4`).
module Prose.Ptc where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Bool.ListAction using (any; all)
open import Data.Char using (Char; isDigit; isAlpha; isSpace)
open import Data.List using (List; []; _∷_; _++_; map; concatMap; length; null; filterᵇ; reverse)
open import Data.Nat using (ℕ; zero; suc; _<ᵇ_; _≤ᵇ_; _≡ᵇ_)
open import Data.Nat.Show using (show)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String; fromList) renaming (toList to toL; _++_ to _⊕_)

open import Prose.Text
open import Prose.Words
open import Prose.Report
open import Prose.Ste using (SUnit; PUnit; units; place; sentenceText; sentenceCheck; hits)

MAX-WORDS MAX-SENTENCES : ℕ
MAX-WORDS     = 35
MAX-SENTENCES = 6

-- PTC counts every word, a group in parentheses too (the STE rule 8.5 is not a PTC rule).
words : Sentence → ℕ
words s = length (filterᵇ word (plain s))

------------------------------------------------------------------------------------------------
-- The shape of a token

private
  digitsThen : Txt → ℕ × Txt     -- the number of leading digits, and the rest
  digitsThen []       = 0 , []
  digitsThen (c ∷ cs) = if isDigit c then step (digitsThen cs) else (0 , c ∷ cs)
    where
    step : ℕ × Txt → ℕ × Txt
    step (n , r) = suc n , r

  openers : Txt
  openers = toL "([\"“*_'‘"

  dropOpeners : Txt → Txt
  dropOpeners []       = []
  dropOpeners (c ∷ cs) = if elem c openers then dropOpeners cs else c ∷ cs

  -- What follows does not continue the number: no digit, point or comma, except one point or
  -- comma that ends the token (the end of a sentence or of an item of a list). Ptc.hs refuses
  -- that point and comma too, so it misses `1.7.` at the end of a sentence.
  free : Txt → Bool
  free []           = true
  free (c ∷ [])     = not (isDigit c)
  free (c ∷ d ∷ cs) = not (isDigit c ∨ (c == '.') ∨ (c == ','))

-- `1.7`, `0.14`, `3.14159`: digits, a point, then 1 or 2 digits or 4 or more (3 digits after a
-- point are Brazilian thousands, `1.000`). The number starts the token, after its openers.
decimal : Txt → Bool
decimal cs = afterInt (digitsThen (dropOpeners cs))
  where
  frac : ℕ × Txt → Bool
  frac (k , rest) = ((1 ≤ᵇ k) ∧ (k ≤ᵇ 2) ∨ (4 ≤ᵇ k)) ∧ free rest
  afterInt : ℕ × Txt → Bool
  afterInt (suc _ , '.' ∷ r) = frac (digitsThen r)
  afterInt _                 = false

-- `1,000,000`: 1 to 3 digits, then two or more groups of a comma and 3 digits.
thousands : Txt → Bool
thousands cs = lead (digitsThen (dropOpeners cs))
  where
  groups : ℕ → Txt → Bool
  groups g (',' ∷ a ∷ b ∷ c ∷ r) =
    if isDigit a ∧ isDigit b ∧ isDigit c ∧ not (startsDigit r) then groups (suc g) r else 2 ≤ᵇ g
    where
    startsDigit : Txt → Bool
    startsDigit []      = false
    startsDigit (d ∷ _) = isDigit d
  groups g _ = 2 ≤ᵇ g
  lead : ℕ × Txt → Bool
  lead (n , r) = (1 ≤ᵇ n) ∧ (n ≤ᵇ 3) ∧ groups 0 r

-- `02/08/2026`: 1 or 2 digits, a slash, 1 or 2 digits, a slash, 2 to 4 digits.
slashDate : Txt → Bool
slashDate cs = day (digitsThen (dropOpeners cs))
  where
  oneTwo : ℕ → Bool
  oneTwo n = (1 ≤ᵇ n) ∧ (n ≤ᵇ 2)
  year : ℕ × Txt → Bool
  year (c , _) = (2 ≤ᵇ c) ∧ (c ≤ᵇ 4)
  month : ℕ × Txt → Bool
  month (b , '/' ∷ r) = oneTwo b ∧ year (digitsThen r)
  month _             = false
  day : ℕ × Txt → Bool
  day (a , '/' ∷ r) = oneTwo a ∧ month (digitsThen r)
  day _             = false

------------------------------------------------------------------------------------------------
-- The context of a number

-- The names after which a number with a point is an identifier (`numberId` in Ptc.hs, and
-- `parágrafo`).
idNames : List Txt
idNames = map toL ("cena" ∷ "cenas" ∷ "scene" ∷ "take" ∷ "takes" ∷ "seção" ∷ "versão" ∷ "v"
  ∷ "sonnet" ∷ "fable" ∷ "opus" ∷ "haiku" ∷ "claude" ∷ "lean" ∷ "z3" ∷ "ghc" ∷ "openvoice"
  ∷ "xtts" ∷ "python" ∷ "pandoc" ∷ "parágrafo" ∷ "parágrafos" ∷ [])

-- The words before a number, nearest first: the number is an identifier when, after other
-- numbers and the words `,`, `e` and `a` of a list, the next word is one of `idNames`.
identifier : List Txt → Bool
identifier []       = false
identifier (w ∷ ws) with lower (core w)
... | c = if listWord w c then identifier ws else memberOf c idNames
  where
  listWord : Txt → Txt → Bool
  listWord w c = null c ∨ memberOf c (map toL ("e" ∷ "a" ∷ [])) ∨ all (λ x → isDigit x ∨ (x == '.')) c

-- The tokens with a decimal point that is not an identifier's.
decimalHits : List Token → List Token
decimalHits = go []
  where
  go : List Txt → List Token → List Token
  go before []       = []
  go before (t ∷ ts) = if decimal (Token.chars t) ∧ not (identifier before)
                       then t ∷ go (Token.chars t ∷ before) ts else go (Token.chars t ∷ before) ts

numberHits : Sentence → List Token
numberHits s = decimalHits (plain s) ++ filterᵇ (λ t → thousands (Token.chars t) ∨ slashDate (Token.chars t)) (plain s)

------------------------------------------------------------------------------------------------
-- The run

hitsLine : (Sentence → List Token) → String → Sentence → String
hitsLine f path s with f s
... | []     = place path (lineOf s)
... | t ∷ ts = place path (Token.line t) ⊕ fromList (join (t ∷ ts))
  where
  join : List Token → Txt
  join []       = []
  join (t ∷ []) = Token.chars t
  join (t ∷ ts) = Token.chars t ++ toL ", " ++ join ts

ptcChecks : List (Check SUnit)
ptcChecks =
  sentenceCheck "PTC-5" ("every sentence has at most " ⊕ show MAX-WORDS ⊕ " words") required
    (λ s → MAX-WORDS <ᵇ words s)
    (λ p s → place p (lineOf s) ⊕ show (words s) ⊕ " words: " ⊕ snippet 70 (sentenceText s)) ∷
  sentenceCheck "PTC-7" "no decimal point, English thousands or DD/MM/YYYY date" required
    (λ s → not (null (numberHits s))) (hitsLine numberHits) ∷ []

paragraphCheck : Check PUnit
paragraphCheck = check "PTC" ("at most " ⊕ show MAX-SENTENCES ⊕ " sentences in a paragraph (recommended)")
  recommended (λ u → MAX-SENTENCES <ᵇ length (proj₂ u))
  (λ u → place (proj₁ u) (first (proj₂ u)) ⊕ show (length (proj₂ u)) ⊕ " sentences")
  where
  first : List Sentence → ℕ
  first []      = 0
  first (s ∷ _) = lineOf s

ptc : List (String × Txt) → List String × ℕ
ptc files with units files
... | ps , ss with report (map (λ c → c over ss) ptcChecks ++ (paragraphCheck over ps) ∷ [])
...   | ls , code = ("PTC, level leve: " ⊕ show (length ss) ⊕ " sentences and " ⊕ show (length ps)
                     ⊕ " paragraphs in " ⊕ show (length files) ⊕ " file(s)") ∷ ls , code
