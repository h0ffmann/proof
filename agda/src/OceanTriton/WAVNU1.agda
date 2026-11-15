{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's dispersion relation from its table, WAVNU1, read from model/src/w3dispmd.F90
-- of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66: the wavenumber K and the group
-- velocity CG of a radian frequency SI in water of depth H, interpolated in the tables EWN1 and
-- ECG1 that DISTAB fills at depth 1 (w3dispmd.F90:551-682), or the deep-water values outside them.
--
--     w3dispmd.F90:182   SQRTH  = SQRT(H)
--     w3dispmd.F90:183   SIX    = SI * SQRTH
--     w3dispmd.F90:184   I1     = INT(SIX/DSIE)
--     w3dispmd.F90:186   IF (I1.LE.N1MAX.AND.I1.GE.1) THEN
--     w3dispmd.F90:187     I2 = I1 + 1
--     w3dispmd.F90:188     R1 = SIX/DSIE - REAL(I1)
--     w3dispmd.F90:189     R2 = 1. - R1
--     w3dispmd.F90:190     K  = ( R2*EWN1(I1) + R1*EWN1(I2) ) / H
--     w3dispmd.F90:191     CG = ( R2*ECG1(I1) + R1*ECG1(I2) ) * SQRTH
--     w3dispmd.F90:192   ELSE
--     w3dispmd.F90:193     K  = SI*SI/GRAV
--     w3dispmd.F90:194     CG = 0.5 * GRAV / SI
--
-- The arithmetic is the optimised code of gfortran -O3 (-fdump-tree-optimized at the pin): SIX/DSIE
-- is computed once, for I1 and for R1; 0.5*GRAV is folded to the float 4.903; there is no fused
-- multiply-add. EWN1 and ECG1 start at index 0 in the Fortran too, so the tables are read as they
-- are. One lane is one frequency bin: W3SRCE's callers fill WN1 and CG1 with WAVNU1 bin by bin
-- (ww3_capture.F90 does as W3WAVE does).
--
-- INT of a negative SIX/DSIE is negative in the Fortran and 0 here (`Model.trunc`); both fail
-- I1 ≥ 1 and take the deep-water branch.
--
-- `wavnu1-K`, `wavnu1-CG`: the two launches give the routine's K and CG at every bin, by refl,
-- in every model of the arithmetic.
module OceanTriton.WAVNU1 where

open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc; _<ᵇ_)
open import Data.Integer using (+_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Data.Bool using (if_then_else_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record Inputs (R : Set) : Set where
  field
    SIG EWN1 ECG1 : ℕ → R
    h dsie : R
    nk n1max : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit

  sqrth : R
  sqrth = fun fsqrt h

  q : ℕ → R
  q ik = SIG ik * sqrth ÷ dsie

  inside : ℕ → ℕ → R → R → R
  inside i1 ik t e = if 0 <ᵇ i1 then (if i1 <ᵇ n1max ℕ.+ 1 then t else e) else e

  interp : (ℕ → R) → ℕ → ℕ → R
  interp T ik i1 = let r1 = q ik - fromℕ i1 in (ℓ (+ 1 / 1) - r1) * T i1 + r1 * T (i1 ℕ.+ 1)

  K CG : ℕ → R
  K ik  = let i1 = trunc (q ik) in
          inside i1 ik (interp EWN1 ik i1 ÷ h) (SIG ik * SIG ik ÷ ℓ (+ 4903 / 500))
  CG ik = let i1 = trunc (q ik) in
          inside i1 ik (interp ECG1 ik i1 * sqrth) (ℓ (+ 4903 / 1000) ÷ SIG ik)

-- ---------------------------------------------------------------------------------------------
-- The program

wavnuSig : Sig
wavnuSig = record { nf = 5 ; ni = 0 ; nfp = 2 ; nip = 2 }

open Syntax wavnuSig

private
  SIG EWN1 ECG1 KB CGB : Fin 5
  SIG = # 0 ; EWN1 = # 1 ; ECG1 = # 2 ; KB = # 3 ; CGB = # 4

  h dsie : ∀ {v a} → FE v a
  h = fpar (# 0) ; dsie = fpar (# 1)

  NK N1MAX : Fin 2
  NK = # 0 ; N1MAX = # 1

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  -- I1 is loop variable 0; SIX/DSIE is accumulator 0.
  q : FE 0 0
  q = ld SIG lane ⊗ fn fsqrt h ⊘ dsie

  inside : FE 1 1 → FE 1 1 → FE 1 1
  inside t e = isel (nat 0) (var (# 0)) (isel (var (# 0)) (ipar N1MAX +ᵢ nat 1) t e) e

  interp : Fin 5 → FE 1 1
  interp T = bind (acc (# 0) ⊖ real (var (# 0)))
               ((c (+ 1 / 1) ⊖ acc (# 0)) ⊗ ld T (var (# 0)) ⊕ acc (# 0) ⊗ ld T (var (# 0) +ᵢ nat 1))

  kB cgB : FE 0 0
  kB  = bind q (ix (acc (# 0)) (inside (interp EWN1 ⊘ h) (ld SIG lane ⊗ ld SIG lane ⊘ c (+ 4903 / 500))))
  cgB = bind q (ix (acc (# 0)) (inside (interp ECG1 ⊗ fn fsqrt h) (c (+ 4903 / 1000) ⊘ ld SIG lane)))

wavnuLaunches : List Launch
wavnuLaunches =
    launch "wavnu1_k"  kB  NK KB  "K, the wavenumber of SIG in depth H (w3dispmd.F90:182-193)"
  ∷ launch "wavnu1_cg" cgB NK CGB "CG, the group velocity of SIG in depth H (w3dispmd.F90:182-194)"
  ∷ []

wavnu1 : ProgL
wavnu1 = record
  { name = "wavnu1"
  ; farrays = "SIG" ∷ "EWN1" ∷ "ECG1" ∷ "K" ∷ "CG" ∷ []
  ; iarrays = []
  ; fparams = "h" ∷ "dsie" ∷ []
  ; iparams = "nk" ∷ "n1max" ∷ []
  ; launches = L.map single wavnuLaunches
  ; results = (KB , NK) ∷ (CGB , NK) ∷ []
  ; doc = "WAVEWATCH III's dispersion relation from its table WAVNU1, one lane per bin" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {wavnuSig} M

  env₀ : Env wavnuSig R
  env₀ = env (I.SIG ∷ I.EWN1 ∷ I.ECG1 ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ [])
             [] (I.h ∷ I.dsie ∷ []) (I.nk ∷ I.n1max ∷ []) 0

  out : Env wavnuSig R
  out = runL (ProgL.launches wavnu1) env₀

  wavnu1-K : ∀ ik → lookup (Env.farr out) (# 3) ik ≡ Routine.K M x ik
  wavnu1-K ik = refl

  wavnu1-CG : ∀ ik → lookup (Env.farr out) (# 4) ik ≡ Routine.CG M x ik
  wavnu1-CG ik = refl
