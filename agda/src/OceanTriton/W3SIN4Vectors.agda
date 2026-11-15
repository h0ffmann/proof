{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SIN4's program: NTH = 4 (directions at 45°, 135°, 225°, 315°), NK = 5 deep
-- water bins from 0.1 to 0.5 Hz, small tables in the shape INSIN4 and TABU_FW give them
-- (IUSTAR = IALPHA = 4, ILEVTAIL = 3, SIZEFWTABLE = 10), and a wind stress USTAR = 0.45 m/s
-- along 10°, so that some directions have ZLOG < 0 and others not.
--
--     ts1      the configuration of ww3_ts1: FW from FWTABLE (SSWELLF(2) /= 0), the TANH
--              smoothing (SSWELLF(7) > 0), the swell term always (SSWELLF(3) > 0), the 3D table
--              (TTAUWSHELTER > 0)
--     other    FW = |SSWELLF(3)| = 0 (SSWELLF(2) = 0), the sharp change (SSWELLF(7) = 0), the
--              swell term only where DSTAB < 1e-7 SIG2 (SSWELLF(3) = 0), the 2D table
module OceanTriton.W3SIN4Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (Model; idiv; imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SIN4 using (Inputs; module Routine)

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

  base : F.Float → F.Float → F.Float → F.Float → F.Float → Inputs F.Float
  base sw2 sw3 sw7 shelt a0 = record
    { A = λ is → a0 F.* (1.0 F.+ n ((is ℕ.* 7) % 5)) F.÷ (1.0 F.+ n (idiv is nTh))
    ; CG = λ ik → g F.÷ (2.0 F.* sig ik)
    ; K = λ is → sig (idiv is nTh) F.* sig (idiv is nTh) F.÷ g
    ; SIG = sig
    ; SIG2 = λ is → sig (idiv is nTh)
    ; DDEN = λ ik → 0.1 F.* 1.5707963267948966 F.* sig ik
    ; DDEN2 = λ is → 0.1 F.* 1.5707963267948966 F.* sig (idiv is nTh)
    ; ECOS = λ is → F.cos (th is)
    ; ESIN = λ is → F.sin (th is)
    ; FWT = λ q → 0.004 F.+ 0.0013 F.* n q
    ; TH = λ q → 0.3 F.+ 0.011 F.* n ((q ℕ.* 3) % 11)
    ; TH2 = λ q → 0.25 F.+ 0.007 F.* n ((q ℕ.* 5) % 13)
    ; u = 12.0 ; ustar = 0.45 ; usdir = 0.17453292519943295 ; z0 = 0.0005 ; drat = 0.001225
    ; dth = 1.5707963267948966 ; bbeta = 1.43 ; zzalp = 0.006 ; zz0rat = 0.04 ; shelt = shelt
    ; sw1 = 0.66 ; sw2 = sw2 ; sw3 = sw3 ; sw4 = 1.5e5 ; sw5 = 1.2 ; sw6 = 0.0 ; sw7 = sw7 ; sinthp = 2.0
    ; aalpha = 0.0095 ; delust = 0.1213 ; delalp = 0.00453 ; deltail = 0.0517 ; delab = 0.31 ; abmin = -1.0
    ; grav = g ; nuair = 1.4e-5 ; kappa = 0.4 ; tpi = twoπ
    ; nth = nTh ; nk = nK ; nspec = nSp ; iustar = 4 ; ialpha = 4 ; ilevtail = 3 ; sizefw = 10 }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("A" , floats nspec A) ∷ ("CG" , floats nk CG) ∷ ("K" , floats nspec K) ∷ ("SIG" , floats nk SIG)
     ∷ ("SIG2" , floats nspec SIG2) ∷ ("DDEN" , floats nk DDEN) ∷ ("DDEN2" , floats nspec DDEN2)
     ∷ ("ECOS" , floats nspec ECOS) ∷ ("ESIN" , floats nspec ESIN) ∷ ("FWT" , floats (sizefw ℕ.+ 1) FWT)
     ∷ ("TH" , floats ((iustar ℕ.+ 1) ℕ.* (ialpha ℕ.+ 1)) TH)
     ∷ ("TH2" , floats ((iustar ℕ.+ 1) ℕ.* (ialpha ℕ.+ 1) ℕ.* (ilevtail ℕ.+ 1)) TH2) ∷ [])
    []
    (("u" , u) ∷ ("ustar" , ustar) ∷ ("usdir" , usdir) ∷ ("z0" , z0) ∷ ("drat" , drat) ∷ ("dth" , dth)
     ∷ ("bbeta" , bbeta) ∷ ("zzalp" , zzalp) ∷ ("zz0rat" , zz0rat) ∷ ("shelt" , shelt) ∷ ("sw1" , sw1)
     ∷ ("sw2" , sw2) ∷ ("sw3" , sw3) ∷ ("sw4" , sw4) ∷ ("sw5" , sw5) ∷ ("sw6" , sw6) ∷ ("sw7" , sw7)
     ∷ ("sinthp" , sinthp) ∷ ("aalpha" , aalpha) ∷ ("delust" , delust) ∷ ("delalp" , delalp)
     ∷ ("deltail" , deltail) ∷ ("delab" , delab) ∷ ("abmin" , abmin) ∷ ("grav" , grav) ∷ ("nuair" , nuair)
     ∷ ("kappa" , kappa) ∷ ("tpi" , tpi) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("nk1" , ℕ.suc nk) ∷ ("n4" , 4) ∷ ("n6" , 6)
     ∷ ("iustar" , iustar) ∷ ("ialpha" , ialpha) ∷ ("ilevtail" , ilevtail) ∷ ("sizefw" , sizefw) ∷ [])
    (("S" , floats nspec (Routine.S floatModel x)) ∷ ("D" , floats nspec (Routine.D floatModel x))
     ∷ ("LL" , floats nspec (Routine.LLWS floatModel x)) ∷ ("TAU" , floats 4 (Routine.TAU floatModel x)) ∷ [])
    where open Inputs x

sin4Cases : String × List String
sin4Cases = "w3sin4" ,
  ( case "ts1" (base (-0.018) 0.022 360000.0 0.3 0.004)
  ∷ case "other" (base 0.0 0.0 0.0 0.0 0.005)
  ∷ [])
