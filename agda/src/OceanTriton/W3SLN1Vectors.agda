{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SLN1's program: NTH = 4 directions at 45°, 135°, 225°, 315°, NK = 5 bins
-- from 0.1 to 0.5 Hz, and the constants of ww3_ts1 (SLNC1 = 80 (RHOA/RHOW GRAV)^2 / TPI,
-- FSPM = 1, FSHF = 1).
--
--     ts1      USTAR = 0.45 m/s along 10°: the filter takes FF1, some bins are below RFR = 0.5
--     strong   USTAR = 1.2 m/s along 200°, FHIGH below SIG(NK): the filter takes FF2
module OceanTriton.W3SLN1Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SLN1 using (Inputs; module Routine)

private
  n : ℕ → F.Float
  n = F.fromℕ

  nTh nK nSp : ℕ
  nTh = 4 ; nK = 5 ; nSp = 20

  g twoπ : F.Float
  g = 9.806 ; twoπ = 6.283185307179586

  sig : ℕ → F.Float
  sig ik = twoπ F.* (0.1 F.+ 0.1 F.* n ik)

  th : ℕ → F.Float
  th q = 0.7853981633974483 F.+ 1.5707963267948966 F.* n (imod q nTh)

  base : F.Float → F.Float → F.Float → Inputs F.Float
  base us dir fh = record
    { K = λ ik → sig ik F.* sig ik F.÷ g ; SIG = sig
    ; ECOS = λ ith → F.cos (th ith) ; ESIN = λ ith → F.sin (th ith)
    ; fhigh = fh ; ustar = us ; usdir = dir ; slnc1 = 2.6e-5 ; fspm = 1.0 ; fshf = 1.0
    ; nth = nTh ; nk = nK ; nspec = nSp }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("K" , floats nk K) ∷ ("SIG" , floats nk SIG) ∷ ("ECOS" , floats nth ECOS) ∷ ("ESIN" , floats nth ESIN) ∷ [])
    []
    (("fhigh" , fhigh) ∷ ("ustar" , ustar) ∷ ("usdir" , usdir) ∷ ("slnc1" , slnc1) ∷ ("fspm" , fspm)
     ∷ ("fshf" , fshf) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ [])
    (("S" , floats nspec (Routine.S floatModel x)) ∷ [])
    where open Inputs x

sln1Cases : String × List String
sln1Cases = "w3sln1" ,
  ( case "ts1" (base 0.45 0.17453292519943295 3.2)
  ∷ case "strong" (base 1.2 3.490658503988659 1.5)
  ∷ [])
