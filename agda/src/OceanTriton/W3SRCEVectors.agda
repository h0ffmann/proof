{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SRCE's step and tail programs: NTH = 4 directions, NK = 8 bins from 0.1 to
-- 0.8 Hz, the logarithmic index of a grid with XFR = 1.1 and FR1 = 0.1 Hz (FACTI1 = 1/LOG(XFR),
-- FACTI2 = 1 - LOG(TPI FR1) FACTI1), so that FHIGH = 1 rad/s keeps the first 6 bins and leaves
-- the last 2 to the tail.
--
--     limited  sources large enough that the dynamic step is cut below DTG - DTTOT
--     shave    DTMIN above the step the sources allow, so SHAVE = 1 and the limiter acts
--     tail     the tail of ww3_ts1's constants (FACHFA = XFR^(-FACHF-2), FACHF = 5)
module OceanTriton.W3SRCEVectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (idiv; imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SRCE using (StepInputs; TailInputs; module Step; module Tail)

private
  n : ℕ → F.Float
  n = F.fromℕ

  nTh nK nSp : ℕ
  nTh = 4 ; nK = 8 ; nSp = 32

  g twoπ fi1 fi2 : F.Float
  g = 9.806 ; twoπ = 6.283185307179586
  fi1 = 10.49205869
  fi2 = 5.876074

  sig : ℕ → F.Float
  sig ik = twoπ F.* (0.1 F.+ 0.1 F.* n ik)

  a : ℕ → F.Float
  a is = 0.002 F.* (1.0 F.+ n ((is ℕ.* 7) % 5)) F.÷ (1.0 F.+ n (idiv is nTh))

  wave : F.Float → (ℕ → F.Float)
  wave s is = s F.* (n ((is ℕ.* 5) % 9) F.- 4.0) F.* 1.0e-5 F.÷ (1.0 F.+ n (idiv is nTh))

  stepIn : F.Float → F.Float → F.Float → StepInputs F.Float
  stepIn s dtmin dttot = record
    { A = a ; SPECINIT = λ is → a is F.* 0.9
    ; VSLN = wave (0.1 F.* s) ; VSIN = wave s ; VDIN = λ is → 1.0e-3 F.* n (imod is nTh)
    ; VSNL = wave (F.- 0.5 F.* s) ; VDNL = λ is → F.- 2.0e-3 F.* n (idiv is nTh)
    ; VSDS = wave (F.- 0.7 F.* s) ; VDDS = λ is → F.- 1.5e-3
    ; VSBT = λ _ → 0.0 ; VDBT = λ _ → 0.0
    ; VSDB = wave (0.01 F.* s) ; VDDB = λ is → F.- 1.0e-4 F.* n (idiv is nTh)
    ; WN = λ ik → sig ik F.* sig ik F.÷ g ; SIG = sig
    ; dtg = 900.0 ; dttot = dttot ; dtmax = 900.0 ; xflt = 0.1 ; amax = 0.01 ; xrel = 0.1
    ; dtmin = dtmin ; fhigh = 1.0 ; facti1 = fi1 ; facti2 = fi2 ; facp = 0.62 F.* 1.0e-4 F.÷ g
    ; nth = nTh ; nk = nK ; nspec = nSp }

  stepCase : String → StepInputs F.Float → String
  stepCase name x = caseJson name
    (("A" , floats nspec A) ∷ ("SPECINIT" , floats nspec SPECINIT) ∷ ("VSLN" , floats nspec VSLN)
     ∷ ("VSIN" , floats nspec VSIN) ∷ ("VDIN" , floats nspec VDIN) ∷ ("VSNL" , floats nspec VSNL)
     ∷ ("VDNL" , floats nspec VDNL) ∷ ("VSDS" , floats nspec VSDS) ∷ ("VDDS" , floats nspec VDDS)
     ∷ ("VSBT" , floats nspec VSBT) ∷ ("VDBT" , floats nspec VDBT) ∷ ("VSDB" , floats nspec VSDB)
     ∷ ("VDDB" , floats nspec VDDB) ∷ ("WN" , floats nk WN) ∷ ("SIG" , floats nk SIG) ∷ [])
    []
    (("dtg" , dtg) ∷ ("dttot" , dttot) ∷ ("dtmax" , dtmax) ∷ ("xflt" , xflt) ∷ ("amax" , amax)
     ∷ ("xrel" , xrel) ∷ ("dtmin" , dtmin) ∷ ("fhigh" , fhigh) ∷ ("facti1" , facti1)
     ∷ ("facti2" , facti2) ∷ ("facp" , facp) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("n4" , 4) ∷ [])
    (("DAM" , floats nspec (Step.DAM floatModel x)) ∷ ("DTB" , floats 4 (Step.DTB floatModel x))
     ∷ ("SPEC" , floats nspec (Step.SPEC floatModel x)) ∷ [])
    where open StepInputs x

  tailIn : F.Float → F.Float → TailInputs F.Float
  tailIn u10 us = record
    { A = a ; SIG = sig
    ; u10 = u10 ; fmeanws = 0.15 ; fmean1 = 0.13 ; ustar = us ; ffxfa = 2.5 ; ffxfm = 2.5 F.* twoπ
    ; ffxpm = 0.25 F.* twoπ F.* g F.÷ 28.0 ; facti1 = fi1 ; facti2 = fi2 ; fachfa = 0.5644739
    ; tpi = twoπ ; grav = g ; fhigh₀ = 1.0
    ; nth = nTh ; nk = nK ; nspec = nSp }

  tailCase : String → TailInputs F.Float → String
  tailCase name x = caseJson name
    (("A" , floats nspec A) ∷ ("SIG" , floats nk SIG) ∷ [])
    []
    (("u10" , u10) ∷ ("fmeanws" , fmeanws) ∷ ("fmean1" , fmean1) ∷ ("ustar" , ustar) ∷ ("ffxfa" , ffxfa)
     ∷ ("ffxfm" , ffxfm) ∷ ("ffxpm" , ffxpm) ∷ ("facti1" , facti1) ∷ ("facti2" , facti2)
     ∷ ("fachfa" , fachfa) ∷ ("tpi" , tpi) ∷ ("grav" , grav) ∷ ("fhigh0" , fhigh₀) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("n2" , 2) ∷ [])
    (("FT" , floats 2 (Tail.FT floatModel x)) ∷ ("SPEC" , floats nspec (Tail.SPEC floatModel x)) ∷ [])
    where open TailInputs x

srceStepCases : String × List String
srceStepCases = "w3srce_step" ,
  ( stepCase "limited" (stepIn 40.0 10.0 0.0)
  ∷ stepCase "shave" (stepIn 400.0 300.0 120.0)
  ∷ [])

srceTailCases : String × List String
srceTailCases = "w3srce_tail" ,
  ( tailCase "ts1" (tailIn 12.0 0.45)
  ∷ tailCase "light" (tailIn 2.0 0.05)
  ∷ [])
