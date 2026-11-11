{-# OPTIONS --safe --without-K #-}

-- The rules of ASD-STE100 (Simplified Technical English), Issue 9, that a program can decide on
-- the characters of a text, with the verdict of each one. The rule numbers are the ones of the
-- term checker table for Issue 9 (simplified-english.co.uk/rules-ste9.html, read 2026-11-11); the
-- limits of 20 and 25 words and of 6 sentences come from the summary of the rules in Wikipedia's
-- "Simplified Technical English" (read 2026-11-11). The specification itself was not read ⚠.
--
-- What is decided here, from the text only:
--   STE-6  (descriptive writing) a sentence has at most 25 words, rules 8.5 and 8.7 applied;
--   STE-6  (descriptive writing) a paragraph has at most 6 sentences;
--   STE-8.1 no semicolon;
--   STE-4.2 no contraction;
--   STE-5.1 (procedures) a step of a numbered list has at most 20 words: a recommended rule,
--          because only a reader knows if an item is an instruction.
-- What needs the dictionary: rule 1.1 (approved words only). ASD owns the dictionary, so the
-- repository does not hold it; `dictionary` takes a word list as a parameter, and the rule is off
-- without one. What needs a reader: the meaning and part of speech of a word (1.2 to 1.13), noun
-- clusters (2.1), verb forms (3.1 to 3.7), one topic per sentence (4.1), articles (4.5), the
-- procedure rules (5.2 to 5.5), the safety rules (section 7). `review` lists the sentences to read
-- for the -ing form (3.5) and the passive voice (3.6).
module Prose.Ste where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Bool.ListAction using (any; all)
open import Data.Char using (Char; isDigit; isAlpha)
open import Data.List using (List; []; _∷_; _++_; map; concatMap; length; null; filterᵇ; reverse)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat using (ℕ; _<ᵇ_; _≤ᵇ_; _∸_)
open import Data.Nat.Show using (show)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String; fromList) renaming (toList to toL; _++_ to _⊕_)

open import Prose.Text
open import Prose.Words
open import Prose.Report

DESCRIPTIVE-WORDS PROCEDURE-WORDS PARAGRAPH-SENTENCES : ℕ
DESCRIPTIVE-WORDS   = 25
PROCEDURE-WORDS     = 20
PARAGRAPH-SENTENCES = 6

-- A sentence or a paragraph of a file.
SUnit : Set
SUnit = String × Sentence

PUnit : Set
PUnit = String × List Sentence

place : String → ℕ → String
place path n = path ⊕ ":" ⊕ show n ⊕ ": "

-- The units of a list of files, each a path and its text.
units : List (String × Txt) → List PUnit × List SUnit
units files = concatMap ps files , concatMap ss files
  where
  ps : String × Txt → List PUnit
  ps (p , t) = map (λ q → p , sentencesOf q) (paragraphs t)
  ss : String × Txt → List SUnit
  ss (p , t) = concatMap (λ q → map (p ,_) (sentencesOf q)) (paragraphs t)

sentenceText : Sentence → Txt
sentenceText s = go (Sentence.toks s)
  where
  go : List Token → Txt
  go []       = []
  go (t ∷ []) = Token.chars t
  go (t ∷ ts) = Token.chars t ++ ' ' ∷ go ts

------------------------------------------------------------------------------------------------
-- The rules

long : ℕ → Sentence → Bool
long limit s = limit <ᵇ wordCount s

semicolon : Token → Bool
semicolon t = elem ';' (Token.chars t)

private
  contractions : List Txt
  contractions = map toL ("it's" ∷ "that's" ∷ "there's" ∷ "what's" ∷ "here's" ∷ "let's" ∷ "who's"
                          ∷ "he's" ∷ "she's" ∷ "where's" ∷ [])
  suffixes : List Txt
  suffixes = map toL ("n't" ∷ "'re" ∷ "'ll" ∷ "'ve" ∷ "'m" ∷ "'d" ∷ [])

-- A contraction: a word that ends with n't, 're, 'll, 've, 'm or 'd, or a pronoun with 's.
contraction : Token → Bool
contraction t with lower (plainApostrophe (core (Token.chars t)))
... | w = any (λ x → endsWith x w) suffixes ∨ memberOf w contractions

-- The tokens of a sentence that a rule on one token finds.
hits : (Token → Bool) → Sentence → List Token
hits p s = filterᵇ p (plain s)

hitLine : (Token → Bool) → String → Sentence → String
hitLine p path s with hits p s
... | []      = place path (lineOf s)
... | t ∷ ts  = place path (Token.line t) ⊕ fromList (join (t ∷ ts))
  where
  join : List Token → Txt
  join []       = []
  join (t ∷ []) = Token.chars t
  join (t ∷ ts) = Token.chars t ++ toL ", " ++ join ts

-- Rule 1.1 with a word list: a word is approved when its letters, in lower case, are in the list.
-- A word with a digit or a code span, and each part of a hyphenated word, is judged on its own.
unapproved : List Txt → Token → Bool
unapproved dict t = any bad (parts (lower (plainApostrophe (core (Token.chars t)))))
  where
  parts : Txt → List Txt
  parts cs = go [] cs
    where
    go : Txt → Txt → List Txt
    go acc []       = reverse acc ∷ []
    go acc (c ∷ cs) = if c == '-' then reverse acc ∷ go [] cs else go (c ∷ acc) cs
  possessive : Txt → Txt
  possessive w = if endsWith (toL "'s") w then reverse (drop2 (reverse w)) else w
    where
    drop2 : Txt → Txt
    drop2 (_ ∷ _ ∷ cs) = cs
    drop2 cs           = cs
  bad : Txt → Bool
  bad w = not (null w) ∧ all isAlpha w ∧ not (memberOf (possessive w) dict) ∧ not (memberOf w dict)

-- The words of a dictionary file: one on each line, in lower case.
dictionary : Txt → List Txt
dictionary t = filterᵇ (λ w → not (null w)) (map (λ { (_ , l) → lower (core l) }) (numbered t))

------------------------------------------------------------------------------------------------
-- The run

sentenceCheck : String → String → Status → (Sentence → Bool) → (String → Sentence → String) → Check SUnit
sentenceCheck r n st bad sh = check r n st (λ u → bad (proj₂ u)) (λ u → sh (proj₁ u) (proj₂ u))

words-line : String → Sentence → String
words-line path s = place path (lineOf s) ⊕ show (wordCount s) ⊕ " words: " ⊕ snippet 70 (sentenceText s)

steChecks : Maybe (List Txt) → List (Check SUnit)
steChecks dict =
  sentenceCheck "STE-6" ("a sentence of descriptive writing has at most " ⊕ show DESCRIPTIVE-WORDS ⊕ " words")
    required (long DESCRIPTIVE-WORDS) words-line ∷
  sentenceCheck "STE-8.1" "no semicolon" required (λ s → any semicolon (plain s)) (hitLine semicolon) ∷
  sentenceCheck "STE-4.2" "no contraction" required (λ s → any contraction (plain s)) (hitLine contraction) ∷
  sentenceCheck "STE-5.1" ("a step of a numbered list has at most " ⊕ show PROCEDURE-WORDS ⊕ " words (recommended)")
    recommended (λ s → Sentence.ordered s ∧ long PROCEDURE-WORDS s) words-line ∷
  dictCheck dict ∷ []
  where
  dictCheck : Maybe (List Txt) → Check SUnit
  dictCheck nothing  = sentenceCheck "STE-1.1" "approved words only (no word list given)" off (λ _ → false) (λ p s → p)
  dictCheck (just d) = sentenceCheck "STE-1.1" "approved words only, from the word list given" required
                         (λ s → any (unapproved d) (plain s)) (hitLine (unapproved d))

paragraphCheck : Check PUnit
paragraphCheck = check "STE-6" ("a paragraph has at most " ⊕ show PARAGRAPH-SENTENCES ⊕ " sentences") required
  (λ u → PARAGRAPH-SENTENCES <ᵇ length (proj₂ u))
  (λ u → place (proj₁ u) (first (proj₂ u)) ⊕ show (length (proj₂ u)) ⊕ " sentences")
  where
  first : List Sentence → ℕ
  first []      = 0
  first (s ∷ _) = lineOf s

ste : Maybe (List Txt) → List (String × Txt) → List String × ℕ
ste dict files with units files
... | ps , ss with report (map (λ c → c over ss) (steChecks dict) ++ (paragraphCheck over ps) ∷ [])
...   | ls , code = header ∷ ls , code
  where
  header : String
  header = "STE, ASD-STE100 Issue 9: " ⊕ show (length ss) ⊕ " sentences and " ⊕ show (length ps)
           ⊕ " paragraphs in " ⊕ show (length files) ⊕ " file(s)"

------------------------------------------------------------------------------------------------
-- What a reader must judge

private
  beForms : List Txt
  beForms = map toL ("is" ∷ "are" ∷ "was" ∷ "were" ∷ "be" ∷ "been" ∷ "being" ∷ [])
  participles : List Txt
  participles = map toL ("done" ∷ "made" ∷ "given" ∷ "shown" ∷ "written" ∷ "known" ∷ "seen"
                         ∷ "taken" ∷ "built" ∷ "kept" ∷ "found" ∷ "held" ∷ "proven" ∷ "chosen" ∷ [])
  ingFree : List Txt
  ingFree = map toL ("thing" ∷ "things" ∷ "nothing" ∷ "something" ∷ "anything" ∷ "everything"
                     ∷ "string" ∷ "strings" ∷ "during" ∷ "bring" ∷ "spring" ∷ "ring" ∷ "king" ∷ [])

-- A word in -ing: rule 3.5 allows it only in a technical name.
ingForm : Token → Bool
ingForm t with lower (core (Token.chars t))
... | w = endsWith (toL "ing") w ∧ (4 <ᵇ length w) ∧ not (memberOf w ingFree)

-- A form of "be" before a word in -ed or a common irregular participle: maybe a passive (3.6).
passive : List Token → List Token
passive (t ∷ u ∷ ts) = if pair (lower (core (Token.chars t))) (lower (core (Token.chars u)))
                       then t ∷ u ∷ passive ts else passive (u ∷ ts)
  where
  pair : Txt → Txt → Bool
  pair a b = memberOf a beForms ∧ (endsWith (toL "ed") b ∨ memberOf b participles)
passive _ = []

review : List (String × Txt) → List String
review files = concatMap line (proj₂ (units files))
  where
  join : List Token → Txt
  join []       = []
  join (t ∷ []) = Token.chars t
  join (t ∷ ts) = Token.chars t ++ ' ' ∷ join ts
  line : SUnit → List String
  line (p , s) = ing (hits ingForm s) ++ pas (passive (plain s))
    where
    ing : List Token → List String
    ing []       = []
    ing ts@(_ ∷ _) = ("REVIEW STE-3.5 -ing form: " ⊕ place p (lineOf s) ⊕ fromList (join ts)) ∷ []
    pas : List Token → List String
    pas []       = []
    pas ts@(_ ∷ _) = ("REVIEW STE-3.6 passive?: " ⊕ place p (lineOf s) ⊕ fromList (join ts)) ∷ []
