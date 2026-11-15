{-# OPTIONS --safe --without-K #-}

-- The test cases of INSIN4's tables: NTH = 6 directions 60° apart from 15°, NK = 3 bins at 0.1,
-- 0.11 and 0.121 Hz (XFR = 1.1), SSDSCOS = 2 as in ww3_ts1.
--
--     ts1      SSDSDTH = 80°, so SDSNTH = 1, in NSAT = 5 rows as WW3 allocates them (2 (NTH/2-1) + 1);
--              SSDSC(3) = 0.8 and DIKCUMUL = 1
--     wide     SDSNTH = 2, every row, both wraps of J_INT; DIKCUMUL = 0, so IK2 = IK is kept
--     iso      SSDSDTH = 180: SATINDICES and SATWEIGHTS are 1; SSDSC(3) = 0: CUMULW is 0
module OceanTriton.INSIN4Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (imod)
open import OceanTriton.LanesVectors
open import OceanTriton.INSIN4 using (Inputs; module Routine)

private
  n : ℕ → F.Float
  n = F.fromℕ

  twoπ : F.Float
  twoπ = 6.283185307179586

  th : ℕ → F.Float
  th i = 0.2617993877991494 F.+ 1.0471975511965976 F.* n i

  sig : ℕ → F.Float
  sig 0 = twoπ F.* 0.1
  sig 1 = twoπ F.* 0.11
  sig _ = twoπ F.* 0.121

  base : F.Float → F.Float → ℕ → ℕ → ℕ → Inputs F.Float
  base dt c3 ns sn dik = record
    { TH = th ; SIG = sig ; ECOS = λ i → F.cos (th (imod i 6)) ; DSIP = λ ik → sig ik F.* 0.0953
    ; ssdsdth = dt ; ssdscos = 2.0 ; ssdsc3 = c3 ; dth = 1.0471975511965976
    ; nth = 6 ; nk = 3 ; nspec = 18 ; nsat = ns ; sdsnth = sn ; dikcumul = dik }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("TH" , floats nth TH) ∷ ("SIG" , floats nk SIG) ∷ ("ECOS" , floats nth ECOS) ∷ ("DSIP" , floats nk DSIP) ∷ [])
    []
    (("ssdsdth" , ssdsdth) ∷ ("ssdscos" , ssdscos) ∷ ("ssdsc3" , ssdsc3) ∷ ("dth" , dth) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("nsat" , nsat) ∷ ("sdsnth" , sdsnth)
     ∷ ("dikcumul" , dikcumul) ∷ ("nsat2" , nsat ℕ.* nth) ∷ ("ncum" , nspec ℕ.* nspec) ∷ [])
    (("SATI" , floats (nsat ℕ.* nth) (Routine.SATI floatModel x))
     ∷ ("SATW" , floats (nsat ℕ.* nth) (Routine.SATW floatModel x))
     ∷ ("CUMULW" , floats (nspec ℕ.* nspec) (Routine.CUMULW floatModel x)) ∷ [])
    where open Inputs x

insin4Cases : String × List String
insin4Cases = "insin4" ,
  ( case "ts1" (base 80.0 0.8 5 1 1)
  ∷ case "wide" (base 130.0 0.8 5 2 0)
  ∷ case "iso" (base 180.0 0.0 5 2 1)
  ∷ [])
