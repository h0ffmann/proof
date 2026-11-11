{-# OPTIONS --safe --without-K #-}

-- The command line of the prose checks, as data: what to read and what to run. `Main.agda`
-- (tools/prose-check/) reads the files that `files` and `extra` name and calls `execute`, and
-- does nothing else.
module Prose.Cli where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Bool.ListAction using (all)
open import Data.List using (List; []; _∷_; map; length)
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat using (ℕ)
open import Data.Nat.Show using (show)
open import Data.Product using (_×_; _,_; proj₁; proj₂)
open import Data.String using (String; toList) renaming (_++_ to _⊕_)

open import Prose.Text using (Txt)
import Prose.Ste as Ste
import Prose.Ptc as Ptc
import Prose.Facts as Facts
import Prose.Examples as Examples

data Command : Set where
  ste      : (review : Bool) → (dictionary : Maybe String) → List String → Command
  ptc      : List String → Command
  compare  : String → String → Command
  selfTest : Command
  usage    : Command

parse : List String → Command
parse ("ste" ∷ rest)           = go false nothing rest
  where
  go : Bool → Maybe String → List String → Command
  go r d ("--review" ∷ xs)         = go true d xs
  go r d ("--dictionary" ∷ f ∷ xs) = go r (just f) xs
  go r d xs                        = ste r d xs
parse ("ptc" ∷ fs)             = ptc fs
parse ("compare" ∷ a ∷ b ∷ []) = compare a b
parse ("self-test" ∷ [])       = selfTest
parse _                        = usage

files : Command → List String
files (ste _ _ fs)  = fs
files (ptc fs)      = fs
files (compare a b) = a ∷ b ∷ []
files selfTest      = []
files usage         = []

extra : Command → Maybe String
extra (ste _ d _) = d
extra _           = nothing

usageText : List String
usageText =
  "usage: prose-check ste [--review] [--dictionary WORDS] FILE...   the ASD-STE100 rules" ∷
  "       prose-check ptc FILE...                                    the PTC rules (level leve)" ∷
  "       prose-check compare ORIGINAL EDITION                       the same citations and numbers" ∷
  "       prose-check self-test                                      the cases of Prose.Examples" ∷ []

private
  asTxt : List (String × String) → List (String × Txt)
  asTxt = map (λ { (p , t) → p , toList t })

  selfTestRun : List String × ℕ
  selfTestRun = map line Examples.cases ++′ (summary ∷ []) , (if all proj₂ Examples.cases then 0 else 1)
    where
    open import Data.List using () renaming (_++_ to _++′_)
    line : String × Bool → String
    line (n , true)  = "OK    " ⊕ n
    line (n , false) = "FAIL  " ⊕ n
    summary : String
    summary = "prose-check: " ⊕ show (length Examples.cases) ⊕ " cases"

execute : Command → List (String × String) → Maybe String → List String × ℕ
execute (ste false _ _) texts dict = Ste.ste (dictOf dict) (asTxt texts)
  where
  dictOf : Maybe String → Maybe (List Txt)
  dictOf nothing  = nothing
  dictOf (just t) = just (Ste.dictionary (toList t))
execute (ste true _ _) texts _ = Ste.review (asTxt texts) , 0
execute (ptc _) texts _ = Ptc.ptc (asTxt texts)
execute (compare _ _) ((pa , a) ∷ (pb , b) ∷ _) _ = Facts.compare pa (toList a) pb (toList b)
execute (compare _ _) _ _ = usageText , 2
execute selfTest _ _ = selfTestRun
execute usage _ _ = usageText , 2
