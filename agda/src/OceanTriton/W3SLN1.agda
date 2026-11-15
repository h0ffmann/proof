{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's linear wind input W3SLN1 (Cavaleri and Malanotte-Rizzoli, 1981, with the filter
-- of Tolman, 1992), read from model/src/w3sln1md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6,
-- commit 92e2cf66, the switch LN1 of ww3_ts1:
--
--     w3sln1md.F90:176   COSU = COS(USDIR) ;  SINU = SIN(USDIR)
--     w3sln1md.F90:180   DIRF(ITH) = MAX ( 0. , (ECOS(ITH)*COSU+ESIN(ITH)*SINU) )**4
--     w3sln1md.F90:183   FAC = SLNC1 * USTAR**4
--     w3sln1md.F90:184   FF1 = FSPM * GRAV/(28.*USTAR)
--     w3sln1md.F90:185   FF2 = FSHF * MIN(SIG(NK),FHIGH)
--     w3sln1md.F90:186   FFILT = MIN ( MAX(FF1,FF2) , 2.*SIG(NK) )
--     w3sln1md.F90:188   RFR = SIG(IK) / FFILT
--     w3sln1md.F90:188-193 IF ( RFR .LT. 0.5 ) THEN WNF(IK) = 0. ELSE WNF(IK) = FAC / K(IK) * EXP(-RFR**(-4))
--     w3sln1md.F90:199   S(:,IK) = WNF(IK) * DIRF(:)
--
-- The arithmetic is the optimised code gfortran -O3 makes of these lines (the GIMPLE of
-- -fdump-tree-optimized at the pin): COS and SIN of one angle are one sincosf, X**4 is
-- (X*X)*(X*X), RFR**(-4) is 1/((RFR*RFR)*(RFR*RFR)) and its negation, GRAV/(28.*USTAR) is
-- (FSPM*GRAV)/(USTAR*28.), and GRAV is the literal 9.806. EXP is scalar expf; no loop of this
-- routine calls libmvec. Indices start at 0: ik = IK - 1, ith = ITH - 1, is = ith + ik NTH.
--
-- `sln1-S`: the launch gives the routine's S at every spectral point, by refl, in every model of
-- the arithmetic.
module OceanTriton.W3SLN1 where

open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc; _∸_)
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
    K SIG ECOS ESIN : ℕ → R
    fhigh ustar usdir slnc1 fspm fshf : R
    nth nk nspec : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_
  infixl 7 _*_ _÷_
  _+_ _*_ _÷_ : R → R → R
  _+_ = op add ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit

  ikOf ithOf : ℕ → ℕ
  ikOf is  = idiv is nth
  ithOf is = imod is nth

  -- DIRF (:180): the positive part of the cosine to the wind, to the fourth.
  dirf : ℕ → R
  dirf ith = let m = op max (ℓ (+ 0 / 1)) (ECOS ith * fun fcos usdir + ESIN ith * fun fsin usdir)
                 p = m * m
             in p * p

  fac ff1 ff2 ffilt : R
  fac   = slnc1 * ((ustar * ustar) * (ustar * ustar))
  ff1   = fspm * ℓ (+ 4903 / 500) ÷ (ustar * ℓ (+ 28 / 1))
  ff2   = fshf * op min (SIG (nk ∸ 1)) fhigh
  ffilt = op min (op max ff1 ff2) (SIG (nk ∸ 1) * ℓ (+ 2 / 1))

  -- WNF (:188-193).
  wnf : ℕ → R
  wnf ik = let rfr = SIG ik ÷ ffilt
               p = rfr * rfr
           in if cmp lt rfr (ℓ (+ 1 / 2)) then ℓ (+ 0 / 1)
              else fac ÷ K ik * fun fexp (fun fneg (ℓ (+ 1 / 1) ÷ (p * p)))

  S : ℕ → R
  S is = wnf (ikOf is) * dirf (ithOf is)

-- ---------------------------------------------------------------------------------------------
-- The program

sln1Sig : Sig
sln1Sig = record { nf = 5 ; ni = 0 ; nfp = 6 ; nip = 3 }

open Syntax sln1Sig

private
  K SIG ECOS ESIN S : Fin 5
  K = # 0 ; SIG = # 1 ; ECOS = # 2 ; ESIN = # 3 ; S = # 4

  fhigh ustar usdir slnc1 fspm fshf : ∀ {v a} → FE v a
  fhigh = fpar (# 0) ; ustar = fpar (# 1) ; usdir = fpar (# 2) ; slnc1 = fpar (# 3)
  fspm = fpar (# 4) ; fshf = fpar (# 5)

  NTH NK NSPEC : Fin 3
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2

  nth nk : ∀ {v} → IE v
  nth = ipar NTH ; nk = ipar NK

  infixl 6 _⊕_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  sB : FE 0 0
  sB = wnfB ⊗ dirfB
    where
      ik ith : IE 0
      ik = quot lane nth ; ith = rem lane nth
      m p fac ff1 ff2 ffilt rfr q wnfB dirfB : FE 0 0
      m     = op max (c (+ 0 / 1)) (ld ECOS ith ⊗ fn fcos usdir ⊕ ld ESIN ith ⊗ fn fsin usdir)
      p     = m ⊗ m
      dirfB = p ⊗ p
      fac   = slnc1 ⊗ ((ustar ⊗ ustar) ⊗ (ustar ⊗ ustar))
      ff1   = fspm ⊗ c (+ 4903 / 500) ⊘ (ustar ⊗ c (+ 28 / 1))
      ff2   = fshf ⊗ op min (ld SIG (nk ∸ᵢ nat 1)) fhigh
      ffilt = op min (op max ff1 ff2) (ld SIG (nk ∸ᵢ nat 1) ⊗ c (+ 2 / 1))
      rfr   = ld SIG ik ⊘ ffilt
      q     = rfr ⊗ rfr
      wnfB  = sel lt rfr (c (+ 1 / 2)) (c (+ 0 / 1))
                (fac ⊘ ld K ik ⊗ fn fexp (fn fneg (c (+ 1 / 1) ⊘ (q ⊗ q))))

sln1Launches : List Launch
sln1Launches =
  launch "w3sln1_s" sB NSPEC S "S = WNF(IK) DIRF(ITH), the linear wind input (w3sln1md.F90:176-199)" ∷ []

sln1 : ProgL
sln1 = record
  { name = "w3sln1"
  ; farrays = "K" ∷ "SIG" ∷ "ECOS" ∷ "ESIN" ∷ "S" ∷ []
  ; iarrays = []
  ; fparams = "fhigh" ∷ "ustar" ∷ "usdir" ∷ "slnc1" ∷ "fspm" ∷ "fshf" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ []
  ; launches = L.map single sln1Launches
  ; results = (S , NSPEC) ∷ []
  ; doc = "WAVEWATCH III's linear wind input W3SLN1, in one launch" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {sln1Sig} M

  env₀ : Env sln1Sig R
  env₀ = env (I.K ∷ I.SIG ∷ I.ECOS ∷ I.ESIN ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ [])
             []
             (I.fhigh ∷ I.ustar ∷ I.usdir ∷ I.slnc1 ∷ I.fspm ∷ I.fshf ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ []) 0

  out : Env sln1Sig R
  out = runL (ProgL.launches sln1) env₀

  sln1-S : ∀ is → lookup (Env.farr out) (# 4) is ≡ Routine.S M x is
  sln1-S is = refl
