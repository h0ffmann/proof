{-# OPTIONS --safe --without-K #-}

-- The tables that WAVEWATCH III's ST4 dissipation W3SDS4 reads (OceanTriton.W3SDS4), made by
-- INSIN4 from model/src/w3src4md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66:
-- the directions over which the saturation is integrated, their weights, and the weights of the
-- cumulative effect. ww3_grid computes them and writes them into mod_def.ww3 (w3iogrmd.F90:1235).
--
--     w3src4md.F90:1032-1048  IF (SSDSDTH.LT.180) THEN SDSNTH = MIN(NINT(SSDSDTH/(DTH*RADE)), NTH/2-1)
--                             SATINDICES = 1 ; SATWEIGHTS = 0
--                             DO ITH, DO I_INT=ITH-SDSNTH, ITH+SDSNTH: J_INT = I_INT, +NTH below 1,
--                             -NTH above NTH ; SATINDICES(I_INT-(ITH-SDSNTH)+1,ITH) = J_INT
--                             SATWEIGHTS(I_INT-(ITH-SDSNTH)+1,ITH) = COS(TH(ITH)-TH(J_INT))**SSDSCOS
--                             ELSE SATINDICES = 1 ; SATWEIGHTS = 1.
--     w3src4md.F90:1144-1172  DIKCUMUL = NINT(SSDSBRF1/(XFR-1.)) ; IF (SSDSC(3).NE.0) THEN
--                             DO IK, ITH, IK2=1,IK-DIKCUMUL, ITH2: C = GRAV/SIG(IK) ; C2 = GRAV/SIG(IK2)
--                             CUMULW(IS2,IS) = SQRT(C**2+C2**2-2*C*C2*ECOS(1+ABS(ITH2-ITH)))*DSIP(IK2)/(0.5*C2)*DTH
--                             with every other entry 0, and all of CUMULW 0 when SSDSC(3) = 0
--
-- The arithmetic is gfortran -O3's (-fdump-tree-optimized at the pin): COS is cosf and the power
-- powf, both scalar; C**2 and C2**2 are products, 2*C*C2 is (C*2)*C2, and the product with ECOS
-- comes before the subtraction; GRAV is the literal 9.806 and 0.5*C2 is C2*0.5. SDSNTH and
-- DIKCUMUL are integers rounded by NINT (`iroundf`) and are inputs here. The two direction tables
-- are allocated with NSAT = 2 (NTH/2-1) + 1 rows (w3gdatmd.F90:2062-2064), more than the
-- 2 SDSNTH + 1 that INSIN4 fills; the other rows keep SATINDICES = 1 and SATWEIGHTS = 0.
--
-- The two IFs of J_INT are a remainder: I_INT - ITH lies within ± SDSNTH, and SDSNTH < NTH, so
-- I_INT is at most one turn below 1 or above NTH, and J_INT - 1 = (I_INT - 1) mod NTH. That step
-- is read by eye, and the replay compares every SATINDICES with WW3's.
--
-- Indices start at 0. SATINDICES and SATWEIGHTS: lane = j + NSAT ith, with j = I_INT-(ITH-SDSNTH);
-- the program writes SATINDICES as the float of J_INT, 1-based as WW3 stores it. CUMULW: lane =
-- is2 + NSPEC is, Fortran's column order, is = ith + NTH ik, is2 = ith2 + NTH ik2.
--
-- `sati-T`, `satw-T`, `cumulw-T`: the three launches give the three tables at every entry, by
-- refl, in every model.
module OceanTriton.INSIN4 where

open import Data.Bool using (if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _∸_; _<ᵇ_)
open import Data.Integer using (+_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record Inputs (R : Set) : Set where
  field
    TH SIG ECOS DSIP : ℕ → R
    ssdsdth ssdscos ssdsc3 dth : R
    nth nk nspec nsat sdsnth dikcumul : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  g one z : R
  g = ℓ (+ 4903 / 500) ; one = ℓ (+ 1 / 1) ; z = ℓ (+ 0 / 1)

  -- SATINDICES and SATWEIGHTS, at lane t: j = t mod NSAT, ith = t div NSAT.
  jOf ithOf jInt : ℕ → ℕ
  jOf t   = imod t nsat
  ithOf t = idiv t nsat
  jInt t  = imod ((ithOf t ℕ.+ jOf t ℕ.+ nth) ∸ sdsnth) nth   -- J_INT - 1

  SATI SATW : ℕ → R
  SATI t = if cmp lt ssdsdth (ℓ (+ 180 / 1))
           then (if jOf t <ᵇ 2 ℕ.* sdsnth ℕ.+ 1 then fromℕ (jInt t ℕ.+ 1) else one) else one
  SATW t = if cmp lt ssdsdth (ℓ (+ 180 / 1))
           then (if jOf t <ᵇ 2 ℕ.* sdsnth ℕ.+ 1 then pow (fun fcos (TH (ithOf t) - TH (jInt t))) ssdscos else z)
           else one

  -- CUMULW at lane t: is2 = t mod NSPEC, is = t div NSPEC.
  is2Of isOf : ℕ → ℕ
  is2Of t = imod t nspec
  isOf t  = idiv t nspec

  CUMULW : ℕ → R
  CUMULW t =
    let ik = idiv (isOf t) nth ; ith = imod (isOf t) nth
        ik2 = idiv (is2Of t) nth ; ith2 = imod (is2Of t) nth
        cc = g ÷ SIG ik ; c2 = g ÷ SIG ik2
    in if cmp ne ssdsc3 z
       then (if ik2 ℕ.+ dikcumul <ᵇ ik ℕ.+ 1
             then fun fsqrt (cc * cc + c2 * c2 - cc * ℓ (+ 2 / 1) * c2 * ECOS ((ith2 ∸ ith) ℕ.+ (ith ∸ ith2)))
                    * DSIP ik2 ÷ (c2 * ℓ (+ 1 / 2)) * dth
             else z)
       else z

-- ---------------------------------------------------------------------------------------------
-- The program

insin4Sig : Sig
insin4Sig = record { nf = 7 ; ni = 0 ; nfp = 4 ; nip = 8 }

open Syntax insin4Sig

private
  TH SIG ECOS DSIP SATI SATW CUMULW : Fin 7
  TH = # 0 ; SIG = # 1 ; ECOS = # 2 ; DSIP = # 3 ; SATI = # 4 ; SATW = # 5 ; CUMULW = # 6

  ssdsdth ssdscos ssdsc3 dth : ∀ {v a} → FE v a
  ssdsdth = fpar (# 0) ; ssdscos = fpar (# 1) ; ssdsc3 = fpar (# 2) ; dth = fpar (# 3)

  NTH NK NSPEC NSAT SDSNTH DIK NSAT2 NCUM : Fin 8
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; NSAT = # 3 ; SDSNTH = # 4 ; DIK = # 5 ; NSAT2 = # 6 ; NCUM = # 7

  nth nsat nspec : ∀ {v} → IE v
  nth = ipar NTH ; nsat = ipar NSAT ; nspec = ipar NSPEC

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  g one z : ∀ {v a} → FE v a
  g = c (+ 4903 / 500) ; one = c (+ 1 / 1) ; z = c (+ 0 / 1)

  ithI jI nsat′ : ∀ {v} → IE v
  nsat′ = nat 2 *ᵢ ipar SDSNTH +ᵢ nat 1
  ithI = quot lane nsat
  jI   = rem (((ithI +ᵢ rem lane nsat) +ᵢ nth) ∸ᵢ ipar SDSNTH) nth

  satiB satwB cumB : FE 0 0
  satiB = sel lt ssdsdth (c (+ 180 / 1)) (isel (rem lane nsat) nsat′ (real (jI +ᵢ nat 1)) one) one
  satwB = sel lt ssdsdth (c (+ 180 / 1)) (isel (rem lane nsat) nsat′ (pow (fn fcos (ld TH ithI ⊖ ld TH jI)) ssdscos) z) one
  cumB  = sel ne ssdsc3 z
            (isel (ik2 +ᵢ ipar DIK) (ik +ᵢ nat 1)
              (fn fsqrt (cc ⊗ cc ⊕ c2 ⊗ c2 ⊖ cc ⊗ c (+ 2 / 1) ⊗ c2 ⊗ ld ECOS ((ith2 ∸ᵢ ith) +ᵢ (ith ∸ᵢ ith2)))
                 ⊗ ld DSIP ik2 ⊘ (c2 ⊗ c (+ 1 / 2)) ⊗ dth)
              z)
            z
    where
      is is2 ik ith ik2 ith2 : IE 0
      is2 = rem lane nspec ; is = quot lane nspec
      ik = quot is nth ; ith = rem is nth ; ik2 = quot is2 nth ; ith2 = rem is2 nth
      cc c2 : FE 0 0
      cc = g ⊘ ld SIG ik ; c2 = g ⊘ ld SIG ik2

insin4Launches : List Launch
insin4Launches =
    launch "insin4_sati" satiB NSAT2 SATI "SATINDICES, as floats (w3src4md.F90:1032-1048)"
  ∷ launch "insin4_satw" satwB NSAT2 SATW "SATWEIGHTS (w3src4md.F90:1032-1048)"
  ∷ launch "insin4_cumulw" cumB NCUM CUMULW "CUMULW, the weights of the cumulative effect (w3src4md.F90:1144-1172)"
  ∷ []

insin4 : ProgL
insin4 = record
  { name = "insin4"
  ; farrays = "TH" ∷ "SIG" ∷ "ECOS" ∷ "DSIP" ∷ "SATI" ∷ "SATW" ∷ "CUMULW" ∷ []
  ; iarrays = []
  ; fparams = "ssdsdth" ∷ "ssdscos" ∷ "ssdsc3" ∷ "dth" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "nsat" ∷ "sdsnth" ∷ "dikcumul" ∷ "nsat2" ∷ "ncum" ∷ []
  ; launches = L.map single insin4Launches
  ; results = (SATI , NSAT2) ∷ (SATW , NSAT2) ∷ (CUMULW , NCUM) ∷ []
  ; doc = "WAVEWATCH III's ST4 tables of INSIN4 that W3SDS4 reads, one lane per entry" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {insin4Sig} M

  z₀ : ℕ → R
  z₀ _ = Model.lit M (+ 0 / 1)

  env₀ : Env insin4Sig R
  env₀ = env (I.TH ∷ I.SIG ∷ I.ECOS ∷ I.DSIP ∷ z₀ ∷ z₀ ∷ z₀ ∷ []) []
             (I.ssdsdth ∷ I.ssdscos ∷ I.ssdsc3 ∷ I.dth ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ I.nsat ∷ I.sdsnth ∷ I.dikcumul ∷ I.nsat ℕ.* I.nth ∷ I.nspec ℕ.* I.nspec ∷ []) 0

  out : Env insin4Sig R
  out = runL (ProgL.launches insin4) env₀

  sati-T : ∀ t → lookup (Env.farr out) (# 4) t ≡ Routine.SATI M x t
  sati-T t = refl

  satw-T : ∀ t → lookup (Env.farr out) (# 5) t ≡ Routine.SATW M x t
  satw-T t = refl

  cumulw-T : ∀ t → lookup (Env.farr out) (# 6) t ≡ Routine.CUMULW M x t
  cumulw-T t = refl
