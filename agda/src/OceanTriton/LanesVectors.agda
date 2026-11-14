{-# OPTIONS --safe --without-K #-}

-- Exact values for the lane programs of `OceanTriton.Lanes`: the model in Agda's Float (IEEE
-- double, with the host's sqrt, exp, log, tanh, cos, sin, atan2 and pow), and the JSON that
-- `ocean-triton/check_lanes.py` reads. A case gives a program's inputs (the float arrays it
-- reads before any launch writes them, the integer arrays, the parameters) and the values of
-- its results. The values are the routine's, computed from its transcription; the kernels run
-- in float32, so the check allows the float32 budget around them.
module OceanTriton.LanesVectors where

open import Data.Bool using (Bool; true; false; if_then_else_; not)
import Data.Float as F
open import Data.Integer using (ℤ)
open import Data.List as L using (List; []; _∷_; upTo)
open import Data.Nat using (ℕ)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.Product using (_×_; _,_)
open import Data.Rational using (ℚ; ↥_; ↧_)
open import Data.String using (String; _++_; intersperse)

open import OceanTriton.Lanes

floatModel : Model F.Float
floatModel = record
  { op = λ { add a b → a F.+ b ; sub a b → a F.- b ; mul a b → a F.* b ; div a b → a F.÷ b
           ; max a b → if b F.<ᵇ a then a else b ; min a b → if a F.<ᵇ b then a else b
           ; atan2 a b → F.atan2 a b }
  ; fun = λ { fsqrt x → F.sqrt x ; fexp x → F.e^ x ; flog x → F.log x ; flog10 x → F.log x F.÷ F.log 10.0
            ; ftanh x → F.tanh x
            ; fcos x → F.cos x ; fsin x → F.sin x ; fabs x → if x F.<ᵇ 0.0 then F.- x else x
            ; fneg x → F.- x }
  ; pow = F._**_
  ; vpow = F._**_
  ; lit = λ q → F.fromRatio (↥ q) (↧ q)
  ; cmp = λ { lt a b → a F.<ᵇ b ; le a b → a F.≤ᵇ b ; ne a b → not (a F.≡ᵇ b) } }

private
  quoted : String → String
  quoted s = "\"" ++ s ++ "\""

  obj : List (String × String) → String
  obj xs = "{" ++ intersperse ", " (L.map (λ { (k , v) → quoted k ++ ": " ++ v }) xs) ++ "}"

-- One float as JSON: its shortest decimal, as a string (Agda's show round-trips a double).
fl : F.Float → String
fl x = quoted (F.show x)

-- n values of a function.
floats : ℕ → (ℕ → F.Float) → String
floats n f = "[" ++ intersperse ", " (L.map (λ i → fl (f i)) (upTo n)) ++ "]"

nats : ℕ → (ℕ → ℕ) → String
nats n f = "[" ++ intersperse ", " (L.map (λ i → showℕ (f i)) (upTo n)) ++ "]"

-- A case: its name, its inputs by kind, and the expected results.
caseJson : String → List (String × String) → List (String × String) → List (String × F.Float) →
           List (String × ℕ) → List (String × String) → String
caseJson name fa ia fp ip ex =
  "    " ++ obj (("name" , quoted name) ∷ ("farrays" , obj fa) ∷ ("iarrays" , obj ia)
                 ∷ ("fparams" , obj (L.map (λ { (k , v) → k , fl v }) fp))
                 ∷ ("iparams" , obj (L.map (λ { (k , v) → k , showℕ v }) ip))
                 ∷ ("expected" , obj ex) ∷ [])

-- The file: each program's cases.
lanesJson : List (String × List String) → String
lanesJson ps = "{\n" ++ intersperse ",\n" (L.map (λ { (p , cs) → "  " ++ quoted p ++ ": [\n" ++ intersperse ",\n" cs ++ "\n  ]" }) ps) ++ "\n}\n"
