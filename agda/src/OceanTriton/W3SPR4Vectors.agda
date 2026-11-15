{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SPR4's program: NTH = 4 directions, NK = 6 bins from 0.1 to 0.6 Hz (so
-- that NK mod 4 = 2 bins take the scalar power), deep water, the exponents of ww3_ts1
-- (WWNMEANPTAIL = -0.5, WWNMEANP = 0.5) and a small TAUT table of ITAUMAX = JUMAX = 4.
--
--     wind     every bin under the wind (LLWS true where the direction is within 90° of it)
--     calm     no bin under the wind, so FMEANWS falls back to SIG(NK) / TPI
module OceanTriton.W3SPR4Vectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)
open import Data.Bool using (if_then_else_)

open import OceanTriton.Lanes using (idiv; imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SPR4 using (Inputs; module Routine)

private
  n : ℕ → F.Float
  n = F.fromℕ

  nTh nK nSp : ℕ
  nTh = 4 ; nK = 6 ; nSp = 24

  g twoπ : F.Float
  g = 9.806 ; twoπ = 6.283185307179586

  sig : ℕ → F.Float
  sig ik = twoπ F.* (0.1 F.+ 0.1 F.* n ik)

  th : ℕ → F.Float
  th q = 0.7853981633974483 F.+ 1.5707963267948966 F.* n (imod q nTh)

  base : F.Float → (ℕ → F.Float) → Inputs F.Float
  base u ll = record
    { A = λ is → 0.002 F.* (1.0 F.+ n ((is ℕ.* 7) % 5)) F.÷ (1.0 F.+ n (idiv is nTh))
    ; CG = λ ik → g F.÷ (2.0 F.* sig ik) ; WN = λ ik → sig ik F.* sig ik F.÷ g ; SIG = sig
    ; DDEN = λ ik → 0.1 F.* 1.5707963267948966 F.* sig ik
    ; ECOS = λ is → F.cos (th is) ; ESIN = λ is → F.sin (th is) ; LLWS = ll
    ; TAUT = λ q → 0.2 F.+ 0.03 F.* n q F.+ 0.001 F.* n ((q ℕ.* 3) % 7)
    ; u = u ; tauwx = 0.11 ; tauwy = 0.04 ; wwnmeanptail = -0.5 ; wwnmeanp = 0.5
    ; fte = 0.25 F.* 0.6283185307179586 ; ftf = 0.2 ; sstxftftail = 0.3 ; sstxftwn = 0.4
    ; deltauw = 0.559 ; delu = 12.5 ; zzwnd = 10.0 ; aalpha = 0.0095 ; tauwmax = 2.2361
    ; tpiinv = 0.15915494309189535
    ; nth = nTh ; nk = nK ; nspec = nSp ; itaumax = 4 ; jumax = 4 }

  case : String → Inputs F.Float → String
  case name x = caseJson name
    (("A" , floats nspec A) ∷ ("CG" , floats nk CG) ∷ ("WN" , floats nk WN) ∷ ("SIG" , floats nk SIG)
     ∷ ("DDEN" , floats nk DDEN) ∷ ("ECOS" , floats nspec ECOS) ∷ ("ESIN" , floats nspec ESIN)
     ∷ ("LLWS" , floats nspec LLWS) ∷ ("TAUT" , floats ((itaumax ℕ.+ 1) ℕ.* (jumax ℕ.+ 1)) TAUT) ∷ [])
    []
    (("u" , u) ∷ ("tauwx" , tauwx) ∷ ("tauwy" , tauwy) ∷ ("wwnmeanptail" , wwnmeanptail)
     ∷ ("wwnmeanp" , wwnmeanp) ∷ ("fte" , fte) ∷ ("ftf" , ftf) ∷ ("sstxftftail" , sstxftftail)
     ∷ ("sstxftwn" , sstxftwn) ∷ ("deltauw" , deltauw) ∷ ("delu" , delu) ∷ ("zzwnd" , zzwnd)
     ∷ ("aalpha" , aalpha) ∷ ("tauwmax" , tauwmax) ∷ ("tpiinv" , tpiinv) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("n11" , 11) ∷ ("itaumax" , itaumax)
     ∷ ("jumax" , jumax) ∷ [])
    (("OUT" , floats 11 (Routine.OUT floatModel x)) ∷ [])
    where open Inputs x

spr4Cases : String × List String
spr4Cases = "w3spr4" ,
  ( case "wind" (base 12.0 (λ is → if imod is nTh ℕ.<ᵇ 2 then 1.0 else 0.0))
  ∷ case "calm" (base 3.0 (λ _ → 0.0))
  ∷ [])
