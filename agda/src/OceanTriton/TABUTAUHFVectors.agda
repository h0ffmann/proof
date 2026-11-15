{-# OPTIONS --safe --without-K #-}

-- The test cases of TABU_TAUHF's program: a table of IUSTAR = 5, IALPHA = 4 with JTOT = 40, the
-- constants of ww3_ts1 (AALPHA, BBETA, ZZALP) and SIGMAX = 2π 0.71 Hz, so that both terms of
-- OMEGACC win somewhere and DELY is 0 at the strong friction velocities.
--
--     free     ZZ0MAX = 0
--     capped   ZZ0MAX = 0.0015
module OceanTriton.TABUTAUHFVectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.LanesVectors
open import OceanTriton.TABUTAUHF using (Inputs; module Routine)

private
  base : F.Float → Inputs F.Float
  base zmax = record
    { sigmax = 4.461 ; delust = 1.0 ; aalpha = 0.0095 ; bbeta = 1.43 ; zzalp = 0.006 ; zz0max = zmax
    ; iustar = 5 ; ialpha = 4 ; jtot = 40 }

  case : String → Inputs F.Float → String
  case name x = caseJson name [] []
    (("sigmax" , sigmax) ∷ ("delust" , delust) ∷ ("aalpha" , aalpha) ∷ ("bbeta" , bbeta) ∷ ("zzalp" , zzalp)
     ∷ ("zz0max" , zz0max) ∷ [])
    (("iustar" , iustar) ∷ ("ialpha" , ialpha) ∷ ("ntab" , 30) ∷ ("jtot" , jtot) ∷ [])
    (("TAUHFT" , floats 30 (Routine.T floatModel x)) ∷ [])
    where open Inputs x

tauhfCases : String × List String
tauhfCases = "tabu_tauhf" ,
  ( case "free" (base 0.0)
  ∷ case "capped" (base 0.0015)
  ∷ [])
