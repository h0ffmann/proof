{-# OPTIONS --safe --without-K #-}

-- The test cases of W3SRCE's flux programs: NTH = 4 directions, NK = 6 bins, a spectrum, its
-- sources, the stresses of a pass and the means W3SRCE ends with, in the sizes of ww3_ts1
-- (DTG = 900 s, DAIR = 1.225 kg/m³).
--
--     pass     a pass of 300 s: some VSIN negative, so WHITECAP(3) leaves those bins out
--     end      three passes, a spectrum that lost energy and one that gained it in places
module OceanTriton.W3SRCEFluxVectors where

import Data.Float as F
open import Data.List using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _%_)
open import Data.Product using (_×_; _,_)
open import Data.String using (String)

open import OceanTriton.Lanes using (idiv; imod)
open import OceanTriton.LanesVectors
open import OceanTriton.W3SRCEFlux using (PassInputs; EndInputs; module Pass; module End)

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

  a : ℕ → F.Float
  a is = 0.002 F.* (1.0 F.+ n ((is ℕ.* 7) % 5)) F.÷ (1.0 F.+ n (idiv is nTh))

  wave : F.Float → ℕ → F.Float
  wave s is = s F.* (n ((is ℕ.* 5) % 9) F.- 4.0) F.* 1.0e-6 F.÷ (1.0 F.+ n (idiv is nTh))

  passIn : PassInputs F.Float
  passIn = record
    { SPEC = a ; VSIN = wave 3.0 ; VDIN = λ is → 1.0e-4 F.* n (imod is nTh) ; VSBT = wave (F.- 0.2)
    ; VDBT = λ is → F.- 2.0e-5 F.* n (idiv is nTh)
    ; DDEN = λ ik → 0.1 F.* 1.5707963267948966 F.* sig ik ; CG = λ ik → g F.÷ (2.0 F.* sig ik)
    ; dt = 300.0 ; phiaw = 0.0013 ; phibbl = 0.0 ; tauwix = 0.02 ; tauwiy = F.- 0.004 ; tauwnx = 0.001
    ; tauwny = 0.0 ; tauwx = 0.11 ; tauwy = 0.04 ; tauwax = 0.003 ; tauway = F.- 0.0007 ; dair = 1.225
    ; nth = nTh ; nk = nK ; nspec = nSp }

  passCase : String → PassInputs F.Float → String
  passCase name x = caseJson name
    (("SPEC" , floats nspec SPEC) ∷ ("VSIN" , floats nspec VSIN) ∷ ("VDIN" , floats nspec VDIN)
     ∷ ("VSBT" , floats nspec VSBT) ∷ ("VDBT" , floats nspec VDBT) ∷ ("DDEN" , floats nk DDEN)
     ∷ ("CG" , floats nk CG) ∷ [])
    []
    (("dt" , dt) ∷ ("phiaw" , phiaw) ∷ ("phibbl" , phibbl) ∷ ("tauwix" , tauwix) ∷ ("tauwiy" , tauwiy)
     ∷ ("tauwnx" , tauwnx) ∷ ("tauwny" , tauwny) ∷ ("tauwx" , tauwx) ∷ ("tauwy" , tauwy)
     ∷ ("tauwax" , tauwax) ∷ ("tauway" , tauway) ∷ ("dair" , dair) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("n7" , 7) ∷ [])
    (("FX" , floats 7 (Pass.FX floatModel x)) ∷ [])
    where open PassInputs x

  endIn : EndInputs F.Float
  endIn = record
    { SPECINIT = a ; SPEC = λ is → a is F.* (0.9 F.+ 0.05 F.* n (imod (is ℕ.* 3) 5))
    ; ECOS = λ q → F.cos (th q) ; ESIN = λ q → F.sin (th q)
    ; DDEN = λ ik → 0.1 F.* 1.5707963267948966 F.* sig ik ; CG = λ ik → g F.÷ (2.0 F.* sig ik)
    ; WN = λ ik → sig ik F.* sig ik F.÷ g ; SIG = sig
    ; dtg = 900.0 ; tauwix = 0.07 ; tauwiy = F.- 0.01 ; tauwnx = 0.002 ; tauwny = 0.0004
    ; taubbl1 = 0.0 ; taubbl2 = 0.0 ; phiaw = 0.004 ; phibbl = 0.0 ; dair = 1.225 ; coef = 0.0
    ; ustar = 0.45 ; ustdir = 0.17453292519943295 ; dtdyn = 1100.0 ; fhigh = 2.5 ; tpiinv = 0.15915494309189535
    ; nth = nTh ; nk = nK ; nspec = nSp ; nsteps = 3 }

  endCase : String → EndInputs F.Float → String
  endCase name x = caseJson name
    (("SPECINIT" , floats nspec SPECINIT) ∷ ("SPEC" , floats nspec SPEC) ∷ ("ECOS" , floats nth ECOS)
     ∷ ("ESIN" , floats nth ESIN) ∷ ("DDEN" , floats nk DDEN) ∷ ("CG" , floats nk CG)
     ∷ ("WN" , floats nk WN) ∷ ("SIG" , floats nk SIG) ∷ [])
    []
    (("dtg" , dtg) ∷ ("tauwix" , tauwix) ∷ ("tauwiy" , tauwiy) ∷ ("tauwnx" , tauwnx) ∷ ("tauwny" , tauwny)
     ∷ ("taubbl1" , taubbl1) ∷ ("taubbl2" , taubbl2) ∷ ("phiaw" , phiaw) ∷ ("phibbl" , phibbl)
     ∷ ("dair" , dair) ∷ ("coef" , coef) ∷ ("ustar" , ustar) ∷ ("ustdir" , ustdir) ∷ ("dtdyn" , dtdyn)
     ∷ ("fhigh" , fhigh) ∷ ("tpiinv" , tpiinv) ∷ [])
    (("nth" , nth) ∷ ("nk" , nk) ∷ ("nspec" , nspec) ∷ ("nsteps" , nsteps) ∷ ("n15" , 15) ∷ [])
    (("FX" , floats 15 (End.FX floatModel x)) ∷ [])
    where open EndInputs x

srcePassCases : String × List String
srcePassCases = "w3srce_pass" , (passCase "pass" passIn ∷ [])

srceEndCases : String × List String
srceEndCases = "w3srce_end" ,
  ( endCase "end" endIn
  ∷ endCase "coef" (record endIn { coef = 0.01 ; taubbl1 = 0.0003 ; taubbl2 = F.- 0.0001 ; nsteps = 0 })
  ∷ [])
