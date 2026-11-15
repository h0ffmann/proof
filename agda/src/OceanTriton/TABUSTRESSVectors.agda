{-# OPTIONS --safe --without-K #-}

-- The test cases of TABU_STRESS's program: a table of ITAUMAX = JUMAX = 6 (DELTAUW = 0.3, so the
-- wave stress reaches 3.24 N/m² over ρ, DELU = UMAX/6), with AALPHA and ZZWND of ww3_ts1.
--
-- The edge of WW3's table, (ITAUMAX DELTAUW)² = TAUWMAX² = 5, is not in these cases: there X = ZTAUW/TAUOLD
-- is close to 1, the Newton step divides by 1 - X and its powf, and float32's rounding is amplified
-- past this comparison's budget against Agda's double (2 of 49 entries, by 2.4e-5, with DELTAUW =
-- TAUWMAX/6). That row is checked against WW3 itself, bit for bit, by the replay of the whole table
-- (ww3-replay/replay.py, TABU_STRESS).
--
--     free     ZZ0MAX = 0: the roughness is not capped
--     capped   ZZ0MAX = 0.0015: the cap acts at the strong winds
module OceanTriton.TABUSTRESSVectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.LanesVectors
open import OceanTriton.TABUSTRESS using (Inputs; module Routine)

private
  base : F.Float → Inputs F.Float
  base zmax = record
    { deltauw = 0.3 ; delu = 8.333333 ; aalpha = 0.0095 ; zz0max = zmax ; zzwnd = 10.0
    ; itaumax = 6 ; jumax = 6 ; niter = 10 }

  case : String → Inputs F.Float → String
  case name x = caseJson name [] []
    (("deltauw" , deltauw) ∷ ("delu" , delu) ∷ ("aalpha" , aalpha) ∷ ("zz0max" , zz0max) ∷ ("zzwnd" , zzwnd) ∷ [])
    (("itaumax" , itaumax) ∷ ("jumax" , jumax) ∷ ("ntaut" , 49) ∷ ("niter" , niter) ∷ [])
    (("TAUT" , floats 49 (Routine.T floatModel x)) ∷ [])
    where open Inputs x

tautCases : String × List String
tautCases = "tabu_stress" ,
  ( case "free" (base 0.0)
  ∷ case "capped" (base 0.0015)
  ∷ [])
