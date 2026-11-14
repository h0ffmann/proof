{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SDS4's program: NTH = 4, NK = 5, three directions in the saturation
-- integral (SDSNTH = 1), DIKCUMUL = 2, and synthetic tables in the form INSIN4 builds them. The
-- spectrum is chosen so that BTH0 is above SSDSBR in some bins and below in others, so the
-- cumulative sum skips bins.
--
--     ts1      the configuration of ww3_ts1: MICHE = 1, SSDSC(5) = SSDSC(21) = 0, SSDSISO = 2
--     other    MICHE from the polynomial, turbulence and viscosity on, SSDSISO = 1, IK1 = 1
module OceanTriton.W3SDS4Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_; _∸_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (Model; idiv; imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SDS4 using (Inputs; module Routine)

private
  n : ℕ → F.Float
  n = F.fromℕ

  nTh nK nSp nSa : ℕ
  nTh = 4 ; nK = 5 ; nSp = 20 ; nSa = 3

  base : F.Float → F.Float → F.Float → F.Float → ℕ → ℕ → Inputs F.Float
  base bm0 c5 c21 a0 ik1 iso1 = record
    { A = λ is → a0 F.* (1.0 F.+ n ((is ℕ.* 7) % 5))
    ; K = λ ik → 0.5 F.+ 0.5 F.* n ik
    ; CG = λ ik → 1.0 F.÷ (1.0 F.+ n ik)
    ; SIG = λ ik → 1.0 F.+ 0.4 F.* n ik
    ; ECOS = λ ith → F.cos (1.5707963267948966 F.* n ith)
    ; ESIN = λ ith → F.sin (1.5707963267948966 F.* n ith)
    ; SATW = λ q → if′ (imod q nSa)
    ; CUMULW = λ q → 0.05 F.* (1.0 F.+ n ((q ℕ.* 3) % 7))
    ; SATI = λ q → 0
    ; dth = 1.5707963267948966 ; ssdsbr = 0.05 ; ssdsc2 = -2.2e-5 ; ssdsc3 = -0.40344
    ; ssdsc5 = c5 ; ssdsc6 = 0.3 ; ssdsc21 = c21 ; ssdsp = 2.0
    ; ssdsbm0 = bm0 ; ssdsbm1 = 1.2 ; ssdsbm2 = -0.3 ; ssdsbm3 = 0.1 ; ssdsbm4 = 0.02
    ; depth = 3.0 ; ustar = 0.4 ; usdir = 0.3 ; dair = 1.225 ; grav = 9.806 ; dwat = 1000.0
    ; twopi2 = 19.739208802178716
    ; nth = nTh ; nk = nK ; nspec = nSp ; nsat = nSa ; ik1 = ik1 ; dikcumul = 2 ; iso1 = iso1 }
    where
    if′ : ℕ → F.Float
    if′ 1 = 1.0
    if′ _ = 0.25

  -- SATI(ith NSAT + j) = ith - 1 + j, modulo NTH: the direction and its two neighbours.
  withSati : Inputs F.Float → Inputs F.Float
  withSati x = record x { SATI = λ q → imod (idiv q nSa ℕ.+ nTh ℕ.+ imod q nSa ∸ 1) nTh }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("A" , floats nspec A) ∷ ("K" , floats nk K) ∷ ("CG" , floats nk CG) ∷ ("SIG" , floats nk SIG)
     ∷ ("ECOS" , floats nth ECOS) ∷ ("ESIN" , floats nth ESIN) ∷ ("SATW" , floats (nth ℕ.* nsat) SATW)
     ∷ ("CUMULW" , floats (nspec ℕ.* nspec) CUMULW) ∷ [])
    (("SATI" , nats (nth ℕ.* nsat) SATI) ∷ [])
    (("dth" , dth) ∷ ("ssdsbr" , ssdsbr) ∷ ("ssdsc2" , ssdsc2) ∷ ("ssdsc3" , ssdsc3) ∷ ("ssdsc5" , ssdsc5)
     ∷ ("ssdsc6" , ssdsc6) ∷ ("ssdsc21" , ssdsc21) ∷ ("ssdsp" , ssdsp) ∷ ("ssdsbm0" , ssdsbm0)
     ∷ ("ssdsbm1" , ssdsbm1) ∷ ("ssdsbm2" , ssdsbm2) ∷ ("ssdsbm3" , ssdsbm3) ∷ ("ssdsbm4" , ssdsbm4)
     ∷ ("depth" , depth) ∷ ("ustar" , ustar) ∷ ("usdir" , usdir) ∷ ("dair" , dair) ∷ ("grav" , grav)
     ∷ ("dwat" , dwat) ∷ ("twopi2" , twopi2) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("nsat" , nsat) ∷ ("ik1" , ik1)
     ∷ ("dikcumul" , dikcumul) ∷ ("iso1" , iso1) ∷ [])
    (("D" , floats nspec (Routine.D floatModel x)) ∷ ("S" , floats nspec (Routine.S floatModel x)) ∷ [])
    where open Inputs x

sds4Cases : String × List String
sds4Cases = "w3sds4" ,
  ( case "ts1" (withSati (base 1.0 0.0 0.0 0.01 0 0))
  ∷ case "other" (withSati (base 0.0 0.5 1.0e-3 0.012 1 1))
  ∷ [])
