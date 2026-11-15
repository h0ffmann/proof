{-# OPTIONS --safe --without-K #-}

-- The friction velocity table of WAVEWATCH III's ST4, TABU_STRESS, read from model/src/w3src4md.F90
-- of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66: TAUT(I,J), the square root of the
-- total stress for a wave stress (I DELTAUW)² and a wind J DELU, by ten Newton steps on Charnock's
-- law with the roughness of the waves. W3SPR4's CALC_USTAR reads it (OceanTriton.W3SPR4).
--
--     w3src4md.F90:1258-1259  NITER = 10 ; XM = 0.50 ; EPS1 = 0.00001
--     w3src4md.F90:1272-1273  DELU = UMAX/FLOAT(JUMAX) ; DELTAUW = TAUWMAX/FLOAT(ITAUMAX)
--     w3src4md.F90:1275       ZTAUW = (REAL(I)*DELTAUW)**2
--     w3src4md.F90:1277-1281  UTOP = FLOAT(J)*DELU ; CDRAG = 0.0012875 ; WCD = SQRT(CDRAG)
--                             USTOLD = UTOP*WCD ; TAUOLD = MAX(USTOLD**2, ZTAUW+EPS1)
--     w3src4md.F90:1282-1296  DO ITER=1,NITER
--                               X = ZTAUW/TAUOLD ; UST = SQRT(TAUOLD) ; ZZ00 = AALPHA*TAUOLD/GRAV
--                               IF (ZZ0MAX.NE.0) ZZ00 = MIN(ZZ00,ZZ0MAX) ; ZZ0 = ZZ00/(1.-X)**XM
--                               F = UST-KAPPA*UTOP/(ALOG(ZZWND/ZZ0))
--                               DELF = 1.-KAPPA*UTOP/(ALOG(ZZWND/ZZ0))**2*2./UST*(1.-(XM+1)*X)/(1.-X)
--                               UST = UST-F/DELF ; TAUOLD = MAX(UST**2., ZTAUW+EPS1)
--     w3src4md.F90:1297       TAUT(I,J) = SQRT(TAUOLD)
--     w3src4md.F90:1305-1307  TAUT(I,0) = 0.0
--
-- The arithmetic is gfortran -O3's (-fdump-tree-optimized at the pin): no loop is vectorised;
-- SQRT(CDRAG) is folded to the float 0.035881750285625457763671875 and XM+1 to 1.5; (1.-X)**XM is
-- powf(1.-X, 0.5), USTOLD**2 and UST**2. are products, the logarithm is computed once for F and
-- DELF; KAPPA*UTOP is UTOP*KAPPA. DELTAUW and DELU are the floats the program stores (the
-- parameters `deltauw` and `delu`). One lane is one entry, lane = I + (ITAUMAX+1) J, the order
-- of TAUT in memory.
--
-- NITER is the parameter `niter` (10 in WW3): with a literal count Agda would unfold the ten steps
-- and compare terms that grow as 6^10, since each step reads TAUOLD six times.
--
-- `taut-T`: the launch gives the table at every entry, by refl, in every model and for every NITER.
module OceanTriton.TABUSTRESS where

open import Data.Bool using (if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _<ᵇ_)
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
    deltauw delu aalpha zz0max zzwnd : R
    itaumax jumax niter : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  one : R
  one = ℓ (+ 1 / 1)

  wcd eps1 κ : R
  wcd  = ℓ (+ 35881750285625457763671875 / 1000000000000000000000000000)
  eps1 = ℓ (+ 1 / 100000)
  κ    = ℓ (+ 2 / 5)

  ztauw utop : ℕ → R
  ztauw t = let s = fromℕ (imod t (itaumax ℕ.+ 1)) * deltauw in s * s
  utop t  = fromℕ (idiv t (itaumax ℕ.+ 1)) * delu

  -- One Newton step from TAUOLD = r.
  newton : ℕ → R → R
  newton t r =
    let ust = fun fsqrt r
        p   = pow (one - ztauw t ÷ r) (ℓ (+ 1 / 2))
        x   = ztauw t ÷ r
        z00 = aalpha * r ÷ ℓ (+ 4903 / 500)
        z0  = (if cmp ne zz0max (ℓ (+ 0 / 1)) then op min zz0max z00 else z00) ÷ p
        l   = fun flog (zzwnd ÷ z0)
        ku  = utop t * κ
        f   = ust - ku ÷ l
        df  = one - (one - x * ℓ (+ 3 / 2)) * (ku ÷ (l * l) * ℓ (+ 2 / 1) ÷ ust) ÷ (one - x)
        u′  = ust - f ÷ df
    in op max (ztauw t + eps1) (u′ * u′)

  T : ℕ → R
  T t = if idiv t (itaumax ℕ.+ 1) <ᵇ 1 then ℓ (+ 0 / 1)
        else fun fsqrt (foldN niter (op max (utop t * wcd * (utop t * wcd)) (ztauw t + eps1)) (λ _ r → newton t r))

-- ---------------------------------------------------------------------------------------------
-- The program

tautSig : Sig
tautSig = record { nf = 1 ; ni = 0 ; nfp = 5 ; nip = 4 }

open Syntax tautSig

private
  TB : Fin 1
  TB = # 0

  deltauw delu aalpha zz0max zzwnd : ∀ {v a} → FE v a
  deltauw = fpar (# 0) ; delu = fpar (# 1) ; aalpha = fpar (# 2) ; zz0max = fpar (# 3) ; zzwnd = fpar (# 4)

  ITM JUM NTAUT NIT : Fin 4
  ITM = # 0 ; JUM = # 1 ; NTAUT = # 2 ; NIT = # 3

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  one : ∀ {v a} → FE v a
  one = c (+ 1 / 1)

  row col : ∀ {v} → IE v
  row = quot lane (ipar ITM +ᵢ nat 1)
  col = rem lane (ipar ITM +ᵢ nat 1)

  ztauw utop : ∀ {v a} → FE v a
  ztauw = (real col ⊗ deltauw) ⊗ (real col ⊗ deltauw)
  utop  = real row ⊗ delu

  wcd eps1 : ∀ {v a} → FE v a
  wcd  = c (+ 35881750285625457763671875 / 1000000000000000000000000000)
  eps1 = c (+ 1 / 100000)

  -- The step, acc 0 = TAUOLD.
  newton : FE 1 1
  newton =
    op max (ztauw ⊕ eps1) (u′ ⊗ u′)
    where
      r ust p x z00 z0 l ku f df u′ : FE 1 1
      r   = acc (# 0)
      ust = fn fsqrt r
      p   = pow (one ⊖ ztauw ⊘ r) (c (+ 1 / 2))
      x   = ztauw ⊘ r
      z00 = aalpha ⊗ r ⊘ c (+ 4903 / 500)
      z0  = sel ne zz0max (c (+ 0 / 1)) (op min zz0max z00) z00 ⊘ p
      l   = fn flog (zzwnd ⊘ z0)
      ku  = utop ⊗ c (+ 2 / 5)
      f   = ust ⊖ ku ⊘ l
      df  = one ⊖ (one ⊖ x ⊗ c (+ 3 / 2)) ⊗ (ku ⊘ (l ⊗ l) ⊗ c (+ 2 / 1) ⊘ ust) ⊘ (one ⊖ x)
      u′  = ust ⊖ f ⊘ df

  tB : FE 0 0
  tB = isel row (nat 1) (c (+ 0 / 1))
         (fn fsqrt (fold NIT (ipar NIT) (op max (utop ⊗ wcd ⊗ (utop ⊗ wcd)) (ztauw ⊕ eps1)) newton))

tautLaunches : List Launch
tautLaunches =
  launch "tabu_stress" tB NTAUT TB "TAUT(I,J), ten Newton steps per entry (w3src4md.F90:1258-1307)" ∷ []

taut : ProgL
taut = record
  { name = "tabu_stress"
  ; farrays = "TAUT" ∷ []
  ; iarrays = []
  ; fparams = "deltauw" ∷ "delu" ∷ "aalpha" ∷ "zz0max" ∷ "zzwnd" ∷ []
  ; iparams = "itaumax" ∷ "jumax" ∷ "ntaut" ∷ "niter" ∷ []
  ; launches = L.map single tautLaunches
  ; results = (TB , NTAUT) ∷ []
  ; doc = "WAVEWATCH III's ST4 friction velocity table TABU_STRESS, one lane per entry" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {tautSig} M

  env₀ : Env tautSig R
  env₀ = env ((λ _ → Model.lit M (+ 0 / 1)) ∷ []) []
             (I.deltauw ∷ I.delu ∷ I.aalpha ∷ I.zz0max ∷ I.zzwnd ∷ [])
             (I.itaumax ∷ I.jumax ∷ (I.itaumax ℕ.+ 1) ℕ.* (I.jumax ℕ.+ 1) ∷ I.niter ∷ []) 0

  out : Env tautSig R
  out = runL (ProgL.launches taut) env₀

  taut-T : ∀ t → lookup (Env.farr out) (# 0) t ≡ Routine.T M x t
  taut-T t = refl
