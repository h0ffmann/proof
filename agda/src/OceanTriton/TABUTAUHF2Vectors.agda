{-# OPTIONS --safe --without-K #-}

-- The test cases of TABU_TAUHF2's program: tables of IUSTAR = 3, IALPHA = 2, ILEVTAIL = 2 with
-- JTOT = 30, the constants of ww3_ts1 (AALPHA, BBETA, ZZALP) and SIGMAX = 2π 0.71 Hz.
--
--     ts1      DELTAIL = ALPHAM/ILEVTAIL as in WW3, every plane
--     floor    DELTAIL forty times larger, so that TAUW falls below 0.0001 at more steps than the
--              K = 0 entries, where it starts there (574 steps against 345, counted in float64)
--     slice    the planes 1 and 2 alone (BASE = 12), as the replay takes them
module OceanTriton.TABUTAUHF2Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat using (ℕ; _+_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.LanesVectors
open import OceanTriton.TABUTAUHF2 using (Inputs; module Routine)

private
  base : F.Float → ℕ → Inputs F.Float
  base dt b = record
    { sigmax = 4.461 ; delust = 1.6666666 ; delalp = 0.095 ; deltail = dt ; aalpha = 0.0095 ; bbeta = 1.43
    ; zzalp = 0.006 ; iustar = 3 ; ialpha = 2 ; jtot = 30 ; base = b }

  case : String → ℕ → Inputs F.Float → String
  case name n2 x = caseJson name [] []
    (("sigmax" , sigmax) ∷ ("delust" , delust) ∷ ("delalp" , delalp) ∷ ("deltail" , deltail)
     ∷ ("aalpha" , aalpha) ∷ ("bbeta" , bbeta) ∷ ("zzalp" , zzalp) ∷ [])
    (("iustar" , iustar) ∷ ("ialpha" , ialpha) ∷ ("ntab" , 12) ∷ ("ntab2" , n2) ∷ ("jtot" , jtot)
     ∷ ("nplane" , 3) ∷ ("base" , Inputs.base x) ∷ [])
    (("TAUHFT" , floats 12 (λ t → Routine.T floatModel x (t + Inputs.base x)))
     ∷ ("TAUHFT2" , floats n2 (λ t → Routine.T2 floatModel x (t + Inputs.base x))) ∷ [])
    where open Inputs x

tauhf2Cases : String × List String
tauhf2Cases = "tabu_tauhf2" ,
  ( case "ts1" 36 (base 0.095 0)
  ∷ case "floor" 36 (base 3.8 0)
  ∷ case "slice" 24 (base 0.095 12)
  ∷ [])
