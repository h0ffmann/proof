{-# OPTIONS --safe --without-K #-}

-- Each rule on a bad text and a good one. Every case is checked twice: by `refl` here, when Agda
-- type-checks this file, and by `prose-check self-test`, which runs the same list through the
-- program that `agda --compile` makes (tools/prose-check/). So a fault of the compiled program
-- that the type-checker does not have shows as a failed case.
module Prose.Examples where

open import Data.Bool using (Bool; true; false; _∧_)
open import Data.List using (List; []; _∷_; map; concat; concatMap; replicate)
open import Data.Maybe using (nothing; just)
open import Data.Nat using (ℕ; _≡ᵇ_)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String) renaming (toList to toL)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import Prose.Text
open import Prose.Ste using (ste; dictionary)
open import Prose.Ptc using (ptc; numberHits)
open import Prose.Facts using (same; facts)

sentencesIn : String → List Sentence
sentencesIn t = concatMap sentencesOf (paragraphs (toL t))

counts : String → List ℕ
counts t = map wordCount (sentencesIn t)

steExit : String → ℕ
steExit t = proj₂ (ste nothing (("t.md" , toL t) ∷ []))

dictExit : String → String → ℕ
dictExit d t = proj₂ (ste (just (dictionary (toL d))) (("t.md" , toL t) ∷ []))

ptcExit : String → ℕ
ptcExit t = proj₂ (ptc (("t.md" , toL t) ∷ []))

decimals : String → List (List _)
decimals t = map Token.chars (concatMap numberHits (sentencesIn t))

-- n words and a full stop.
wordsOf : ℕ → String
wordsOf n = Data.String.fromList (concat (replicate n (toL "word ")) Data.List.++ toL "end.")
  where import Data.String

seven : String
seven = "One. Two. Three. Four. Five. Six. Seven."

------------------------------------------------------------------------------------------------
-- The reader

paren-is-one-word : counts "The tool (and its long list of options) runs." ≡ 4 ∷ []
paren-is-one-word = refl

hyphen-is-one-word : counts "A tie-breaking rule keeps the first maximum." ≡ 7 ∷ []
hyphen-is-one-word = refl

code-is-one-word : counts "Run `just agda --self-test` now." ≡ 3 ∷ []
code-is-one-word = refl

reference-is-no-word : counts "The note says so [3]. The script agrees [@key]." ≡ 4 ∷ 3 ∷ []
reference-is-no-word = refl

two-sentences : counts "It stops. **Then** it starts." ≡ 2 ∷ 3 ∷ []
two-sentences = refl

-- A fenced block, a heading and a table row are not prose.
not-prose : steExit "# A heading; with a semicolon\n\n```\na; b\n```\n\n| a; b |\n\nThe tool runs." ≡ 0
not-prose = refl

------------------------------------------------------------------------------------------------
-- STE

ste-25-words : steExit (wordsOf 24) ≡ 0
ste-25-words = refl

ste-26-words : steExit (wordsOf 25) ≡ 1
ste-26-words = refl

ste-semicolon : steExit "The tool reads the file; it writes the report." ≡ 1
ste-semicolon = refl

ste-contraction : steExit "The tool doesn't stop." ≡ 1
ste-contraction = refl

ste-its : steExit "It's the tool." ≡ 1
ste-its = refl

ste-possessive : steExit "The tool's report is short." ≡ 0
ste-possessive = refl

ste-seven-sentences : steExit seven ≡ 1
ste-seven-sentences = refl

ste-six-sentences : steExit "One. Two. Three. Four. Five. Six." ≡ 0
ste-six-sentences = refl

-- A step of 21 words is a NOTE, not a failure.
ste-long-step-is-a-note : steExit ("1. " Data.String.++ wordsOf 20) ≡ 0
ste-long-step-is-a-note = refl

ste-dictionary : dictExit "the\ntool\nruns\n" "The tool runs." ≡ 0
ste-dictionary = refl

ste-not-in-dictionary : dictExit "the\ntool\n" "The tool runs." ≡ 1
ste-not-in-dictionary = refl

------------------------------------------------------------------------------------------------
-- PTC

ptc-decimal : decimals "O custo é 1.7 reais." ≡ toL "1.7" ∷ []
ptc-decimal = refl

ptc-paragraph-of-the-note : decimals "A nota, seção 8, parágrafo 1.7, diz o mesmo. O parágrafo 2.6 também." ≡ []
ptc-paragraph-of-the-note = refl

ptc-scenes : decimals "As cenas 1.2, 1.3 e 1.4 mostram o braço." ≡ []
ptc-scenes = refl

ptc-brazilian-thousands : decimals "São 1.000 pessoas e 3,5 litros." ≡ []
ptc-brazilian-thousands = refl

ptc-long-decimal : decimals "O valor é 3.14159." ≡ toL "3.14159." ∷ []
ptc-long-decimal = refl

ptc-english-thousands : ptcExit "São 1,000,000 pedidos." ≡ 1
ptc-english-thousands = refl

ptc-date : ptcExit "Em 02/08/2026 o take saiu." ≡ 1
ptc-date = refl

ptc-36-words : ptcExit (wordsOf 35) ≡ 1
ptc-36-words = refl

ptc-35-words : ptcExit (wordsOf 34) ≡ 0
ptc-35-words = refl

------------------------------------------------------------------------------------------------
-- Facts

facts-kept : same (facts (toL "The bandit wins in 3 of 4 rounds [@li2010].")) (facts (toL "In 3 rounds of 4 [@li2010], the bandit wins.")) ≡ true
facts-kept = refl

facts-lost : same (facts (toL "The bandit wins in 3 of 4 rounds [@li2010].")) (facts (toL "The bandit wins in 3 rounds.")) ≡ false
facts-lost = refl

------------------------------------------------------------------------------------------------
-- The same cases, for the compiled program

cases : List (String × Bool)
cases =
  ("parenthesis is one word"   , eqs (counts "The tool (and its long list of options) runs.") (4 ∷ [])) ∷
  ("hyphen is one word"        , eqs (counts "A tie-breaking rule keeps the first maximum.") (7 ∷ [])) ∷
  ("code is one word"          , eqs (counts "Run `just agda --self-test` now.") (3 ∷ [])) ∷
  ("not prose"                 , (steExit "# A heading; with a semicolon\n\n```\na; b\n```\n\n| a; b |\n\nThe tool runs." ≡ᵇ 0)) ∷
  ("STE 25 words pass"         , (steExit (wordsOf 24) ≡ᵇ 0)) ∷
  ("STE 26 words fail"         , (steExit (wordsOf 25) ≡ᵇ 1)) ∷
  ("STE semicolon fails"       , (steExit "The tool reads the file; it writes the report." ≡ᵇ 1)) ∷
  ("STE contraction fails"     , (steExit "The tool doesn't stop." ≡ᵇ 1)) ∷
  ("STE possessive passes"     , (steExit "The tool's report is short." ≡ᵇ 0)) ∷
  ("STE 7 sentences fail"      , (steExit seven ≡ᵇ 1)) ∷
  ("STE word list"             , (dictExit "the\ntool\n" "The tool runs." ≡ᵇ 1)) ∷
  ("PTC decimal fails"         , (ptcExit "O custo é 1.7 reais." ≡ᵇ 1)) ∷
  ("PTC parágrafo 1.7 passes"  , (ptcExit "A nota, seção 8, parágrafo 1.7, diz o mesmo." ≡ᵇ 0)) ∷
  ("PTC date fails"            , (ptcExit "Em 02/08/2026 o take saiu." ≡ᵇ 1)) ∷
  ("PTC 36 words fail"         , (ptcExit (wordsOf 35) ≡ᵇ 1)) ∷
  ("facts lost"                , Data.Bool.not (same (facts (toL "3 of 4 [@li2010].")) (facts (toL "3 rounds.")))) ∷
  []
  where
  eqs : List ℕ → List ℕ → Bool
  eqs []       []       = true
  eqs (x ∷ xs) (y ∷ ys) = (x ≡ᵇ y) ∧ eqs xs ys
  eqs _        _        = false

every-case-passes : Data.List.map proj₂ cases ≡ replicate 16 true
every-case-passes = refl
