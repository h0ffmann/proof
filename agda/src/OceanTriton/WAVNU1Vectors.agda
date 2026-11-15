{-# OPTIONS --safe --without-K #-}

-- The test cases of WAVNU1's program: tables in the shape DISTAB gives them (here the deep-water
-- K = SI²/GRAV and CG = GRAV/(2 SI) at depth 1, on 21 entries), so that the interpolation is
-- exercised in the middle of the table, at its last entry and outside it.
--
--     shallow  depth 5 m: most bins are inside the table
--     deep     depth 400 m: SIX/DSIE is past N1MAX for most bins, the deep-water branch
module OceanTriton.WAVNU1Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.LanesVectors
open import OceanTriton.WAVNU1 using (Inputs; module Routine)

private
  n : ℕ → F.Float
  n = F.fromℕ

  nK n1 : ℕ
  nK = 8 ; n1 = 20

  g twoπ ds : F.Float
  g = 9.806 ; twoπ = 6.283185307179586
  ds = 0.31

  sig : ℕ → F.Float
  sig ik = twoπ F.* (0.04 F.* (1.25 F.** n ik))

  base : F.Float → Inputs F.Float
  base h = record
    { SIG = sig
    ; EWN1 = λ i → (n i F.* ds) F.* (n i F.* ds) F.÷ g F.+ 0.01 F.÷ (1.0 F.+ n i)
    ; ECG1 = λ i → g F.÷ (2.0 F.* (0.05 F.+ n i F.* ds))
    ; h = h ; dsie = ds ; nk = nK ; n1max = n1 }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("SIG" , floats nk SIG) ∷ ("EWN1" , floats (n1max ℕ.+ 2) EWN1) ∷ ("ECG1" , floats (n1max ℕ.+ 2) ECG1) ∷ [])
    []
    (("h" , h) ∷ ("dsie" , dsie) ∷ [])
    (("nk" , nk) ∷ ("n1max" , n1max) ∷ [])
    (("K" , floats nk (Routine.K floatModel x)) ∷ ("CG" , floats nk (Routine.CG floatModel x)) ∷ [])
    where open Inputs x

wavnu1Cases : String × List String
wavnu1Cases = "wavnu1" ,
  ( case "shallow" (base 5.0)
  ∷ case "deep" (base 400.0)
  ∷ [])
