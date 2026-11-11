{-# OPTIONS --safe --without-K #-}

-- The text of a Markdown file as the prose checks read it: the lines, the paragraphs, the
-- tokens and the sentences. Each function is total and structural on a list of characters, so
-- `agda --compile` gives the same functions that the proofs are about.
--
-- What is prose. A fenced code block, a heading, a table row, an HTML line, a block quote, an
-- image and the front matter are not prose. Each item of a list starts a paragraph. An inline
-- code span counts as one word (`codeMark`). A reference marker such as `[3]` or `[@key]` is not
-- a word. A group in parentheses or in quotation marks is one token: ASD-STE100 counts text in
-- parentheses as one word (rule 8.5), and a quotation is the words of another writer.
module Prose.Text where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; if_then_else_)
open import Data.Char using (Char; isSpace; isAlpha; isDigit; toLower)
open import Data.Char.Properties using (_≟_)
open import Data.List using (List; []; _∷_; _++_; reverse; map; length; filterᵇ; null)
open import Data.Bool.ListAction using (any; all)
open import Data.List.Properties using (≡-dec)
open import Data.Nat using (ℕ; zero; suc; _+_; pred)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Relation.Nullary.Decidable using (⌊_⌋)
open import Data.String using (String) renaming (toList to toL)

Txt : Set
Txt = List Char

-- Character and text equality, from decidable equality, so that a `true` is a proof of `≡`
-- (`Prose.Facts` uses it).
_==_ : Char → Char → Bool
c == d = ⌊ c ≟ d ⌋

_≡?_ : (x y : Txt) → _
_≡?_ = ≡-dec _≟_

_===_ : Txt → Txt → Bool
x === y = ⌊ x ≡? y ⌋

elem : Char → Txt → Bool
elem c = any (_== c)

-- The character that takes the place of an inline code span: a character of Unicode's private
-- use area, so no prose word holds it.
codeMark : Char
codeMark = '\57344'

-- A capital letter: one that `toLower` changes.
isUpper : Char → Bool
isUpper c = not (toLower c == c)

alnum : Char → Bool
alnum c = isAlpha c ∨ isDigit c ∨ (c == codeMark)

startsWith : Txt → Txt → Bool
startsWith []       _        = true
startsWith (p ∷ ps) []       = false
startsWith (p ∷ ps) (c ∷ cs) = (p == c) ∧ startsWith ps cs

dropSpaces : Txt → Txt
dropSpaces []       = []
dropSpaces (c ∷ cs) = if isSpace c then dropSpaces cs else c ∷ cs

dropDigits : Txt → Txt
dropDigits []       = []
dropDigits (c ∷ cs) = if isDigit c then dropDigits cs else c ∷ cs

lower : Txt → Txt
lower = map toLower

------------------------------------------------------------------------------------------------
-- Lines

-- The lines of a text, each with its number from 1.
numbered : Txt → List (ℕ × Txt)
numbered = go 1 []
  where
  go : ℕ → Txt → Txt → List (ℕ × Txt)
  go n acc []       = (n , reverse acc) ∷ []
  go n acc (c ∷ cs) = if c == '\n' then (n , reverse acc) ∷ go (suc n) [] cs else go n (c ∷ acc) cs

-- The front matter: a first line `---` up to the next line `---`.
frontMatter : List (ℕ × Txt) → List (ℕ × Txt)
frontMatter ((n , l) ∷ ls) = if startsWith (toL "---") l then after ls else (n , l) ∷ ls
  where
  after : List (ℕ × Txt) → List (ℕ × Txt)
  after []             = []
  after ((_ , l) ∷ ls) = if startsWith (toL "---") l then ls else after ls
frontMatter [] = []

data Kind : Set where
  kFence kSkip kBlank kItem kOrdered kText : Kind

private
  -- `1. `, `12) `: the rest of the line after the number of an item.
  numberedItem : Txt → Bool
  numberedItem (c ∷ cs) = isDigit c ∧ marker (dropDigits cs)
    where
    marker : Txt → Bool
    marker (m ∷ s ∷ _) = ((m == '.') ∨ (m == ')')) ∧ isSpace s
    marker _           = false
  numberedItem [] = false

  afterMarker : Txt → Txt
  afterMarker cs = dropSpaces (drop1 (dropDigits cs))
    where
    drop1 : Txt → Txt
    drop1 []       = []
    drop1 (_ ∷ cs) = cs

  bullet : Txt → Bool
  bullet (b ∷ s ∷ _) = ((b == '-') ∨ (b == '*') ∨ (b == '+')) ∧ isSpace s
  bullet _           = false

  skipLine : Txt → Bool
  skipLine []      = false
  skipLine (c ∷ _) = (c == '#') ∨ (c == '|') ∨ (c == '<') ∨ (c == '>')

-- What a line is, and its prose.
classify : Txt → Kind × Txt
classify l with dropSpaces l
... | t = if startsWith (toL "```") t ∨ startsWith (toL "~~~") t then kFence , []
          else if null t then kBlank , []
          else if skipLine t ∨ startsWith (toL "![") t ∨ startsWith (toL "[^") t then kSkip , []
          else if bullet t then kItem , dropSpaces (drop2 t)
          else if numberedItem t then kOrdered , afterMarker t
          else kText , t
  where
  drop2 : Txt → Txt
  drop2 (_ ∷ _ ∷ cs) = cs
  drop2 cs           = cs

------------------------------------------------------------------------------------------------
-- Paragraphs

-- A character with the number of its line.
Pos : Set
Pos = ℕ × Char

record Paragraph : Set where
  constructor paragraph
  field
    ordered : Bool       -- an item of a numbered list: a step of a procedure, often
    chars   : List Pos

private
  revTag : ℕ → Txt → List Pos → List Pos
  revTag n []       acc = acc
  revTag n (c ∷ cs) acc = revTag n cs ((n , c) ∷ acc)

  close : Bool → List Pos → List Paragraph → List Paragraph
  close o []        ps = ps
  close o (a ∷ acc) ps = paragraph o (reverse (a ∷ acc)) ∷ ps

  isFence : Txt → Bool
  isFence l = startsWith (toL "```") (dropSpaces l) ∨ startsWith (toL "~~~") (dropSpaces l)

  -- inFence, ordered, the characters so far (reversed), the lines.
  build : Bool → Bool → List Pos → List (ℕ × Txt) → List Paragraph
  build _     o acc []              = close o acc []
  build true  o acc ((n , l) ∷ ls)  = build (not (isFence l)) o acc ls
  build false o acc ((n , l) ∷ ls)  with classify l
  ... | kFence   , _ = close o acc (build true  false [] ls)
  ... | kSkip    , _ = close o acc (build false false [] ls)
  ... | kBlank   , _ = close o acc (build false false [] ls)
  ... | kItem    , c = close o acc (build false false (revTag n c []) ls)
  ... | kOrdered , c = close o acc (build false true  (revTag n c []) ls)
  ... | kText    , c = build false o (revTag n c ((n , ' ') ∷ acc)) ls

paragraphs : Txt → List Paragraph
paragraphs t = build false false [] (frontMatter (numbered t))

------------------------------------------------------------------------------------------------
-- Masks

-- An inline code span becomes one `codeMark`.
maskCode : List Pos → List Pos
maskCode = go false
  where
  go : Bool → List Pos → List Pos
  go _     []             = []
  go false ((n , c) ∷ ps) = if c == '`' then (n , codeMark) ∷ go true ps else (n , c) ∷ go false ps
  go true  ((n , c) ∷ ps) = if c == '`' then go false ps else go true ps

-- A reference marker, `[3]`, `[1, 2]`, `[@key]` or `[-@key]`, is taken out.
maskRefs : List Pos → List Pos
maskRefs = go false
  where
  go : Bool → List Pos → List Pos
  go _     []                         = []
  go true  ((_ , c) ∷ ps)             = if c == ']' then go false ps else go true ps
  go false ((n , c) ∷ (m , d) ∷ ps)   =
    if (c == '[') ∧ ((d == '@') ∨ isDigit d ∨ (d == '-'))
    then go true ps else (n , c) ∷ go false ((m , d) ∷ ps)
  go false (p ∷ [])                   = p ∷ []

------------------------------------------------------------------------------------------------
-- Tokens and sentences

record Token : Set where
  constructor token
  field
    line  : ℕ
    chars : Txt

-- The tokens: runs of characters between spaces, where a space in parentheses or in quotation
-- marks does not end a token. `depth` counts the open parentheses; `quoted` is true inside
-- quotation marks.
tokens : List Pos → List Token
tokens = go 0 false 0 []
  where
  emit : ℕ → Txt → List Token → List Token
  emit l []  ts = ts
  emit l acc ts = token l (reverse acc) ∷ ts

  go : (depth : ℕ) → (quoted : Bool) → (start : ℕ) → (acc : Txt) → List Pos → List Token
  go d q s acc []             = emit s acc []
  go d q s acc ((n , c) ∷ ps) =
    if isSpace c ∧ (d Data.Nat.≡ᵇ 0) ∧ not q
    then emit s acc (go d q n [] ps)
    else go (depth d c) (quoting q c) (if null acc then n else s) (c ∷ acc) ps
    where
    depth : ℕ → Char → ℕ
    depth d c = if c == '(' then suc d else if c == ')' then pred d else d
    quoting : Bool → Char → Bool
    quoting q c = if c == '"' then not q else if c == '“' then true else if c == '”' then false else q

-- A token is a word when it holds a letter, a digit or a code span.
word : Token → Bool
word t = any alnum (Token.chars t)

-- The last character of a token without its closing marks (`*`, `_`, `)`, `]`, quotation marks).
private
  closers : Txt
  closers = toL "*_)]\"”’'"

  lastMark : Txt → Bool
  lastMark cs = go (reverse cs)
    where
    go : Txt → Bool
    go []       = false
    go (c ∷ cs) = if elem c closers then go cs else (c == '.') ∨ (c == '!') ∨ (c == '?') ∨ (c == '…')

  opens : Txt → Bool
  opens []      = false
  opens (c ∷ _) = isUpper c ∨ isDigit c ∨ elem c (toL "*[(\"“⚠π") ∨ (c == codeMark)

  -- Abbreviations whose point does not end a sentence (`abbreviation` in Ptc.hs, and e.g., i.e.).
  abbreviations : List Txt
  abbreviations = map toL ("p." ∷ "ex." ∷ "sr." ∷ "sra." ∷ "dr." ∷ "dra." ∷ "etc." ∷ "vs." ∷ "cf."
                           ∷ "n." ∷ "nº." ∷ "e.g." ∷ "i.e." ∷ [])

  abbreviation : Txt → Bool
  abbreviation cs = any (_=== lower (stripOpen cs)) abbreviations
    where
    stripOpen : Txt → Txt
    stripOpen []       = []
    stripOpen (c ∷ cs) = if elem c (toL "([\"“*_") then stripOpen cs else c ∷ cs

-- A token ends a sentence when it ends with `.`, `!`, `?` or `…` (before its closing marks), is
-- not an abbreviation, and the next token starts with a capital letter, a digit, an emphasis, a
-- bracket, a parenthesis, a quotation mark or a code span.
ends : Token → Token → Bool
ends t u = lastMark (Token.chars t) ∧ not (abbreviation (Token.chars t)) ∧ opens (Token.chars u)

-- The separator of an inline list, `1952 Robbins · 2010 LinUCB`: each item is a unit, as in a list.
dot : Token → Bool
dot t = Token.chars t === ('·' ∷ [])

record Sentence : Set where
  constructor sentence
  field
    ordered : Bool
    toks    : List Token

-- The sentences of a list of tokens.
split : List Token → List (List Token)
split = go []
  where
  out : List Token → List (List Token) → List (List Token)
  out []  ss = ss
  out acc ss = reverse acc ∷ ss
  go : List Token → List Token → List (List Token)
  go acc []           = out acc []
  go acc (t ∷ [])     = if dot t then out acc [] else out (t ∷ acc) []
  go acc (t ∷ u ∷ ts) = if dot t then out acc (go [] (u ∷ ts))
                        else if ends t u then out (t ∷ acc) (go [] (u ∷ ts)) else go (t ∷ acc) (u ∷ ts)

sentencesOf : Paragraph → List Sentence
sentencesOf (paragraph o cs) = map (sentence o) (split (tokens (maskRefs (maskCode cs))))

-- The line where a sentence starts.
lineOf : Sentence → ℕ
lineOf (sentence _ [])      = 0
lineOf (sentence _ (t ∷ _)) = Token.line t

-- The number of words of a sentence (ASD-STE100, rules 8.5 and 8.7: a group in parentheses and a
-- hyphenated word count as one word).
wordCount : Sentence → ℕ
wordCount s = length (filterᵇ word (Sentence.toks s))

-- The plain words of a sentence, a group split again at its spaces: for the rules that look
-- inside parentheses (a semicolon, a contraction, a number).
plain : Sentence → List Token
plain s = Data.List.concatMap inner (Sentence.toks s)
  where
  inner : Token → List Token
  inner (token l cs) = go [] cs
    where
    go : Txt → Txt → List Token
    go []  []       = []
    go acc []       = token l (reverse acc) ∷ []
    go acc (c ∷ cs) = if isSpace c then (if null acc then go [] cs else token l (reverse acc) ∷ go [] cs)
                      else go (c ∷ acc) cs
