{-# OPTIONS --safe --without-K #-}

-- The high-frequency stress table of WAVEWATCH III's ST4, TABU_TAUHF, read from
-- model/src/w3src4md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66: TAUHFT(K,L),
-- the stress of the waves above the prognostic range for a friction velocity K DELUST and a
-- Charnock coefficient AALPHA + L DELALP, integrated over JTOT = 250 points of the
-- dimensionless frequency Y by the trapezoidal rule. INSIN4 calls it with SIGMAX = SIG(NK)
-- (w3src4md.F90:1023), and W3SIN4 reads it (OceanTriton.W3SIN4) when TTAUWSHELTER = 0; when
-- TTAUWSHELTER > 0, as in ww3_ts1, TABU_TAUHF2 writes TAUHFT again (OceanTriton.TABUTAUHF2), and
-- the replay compares this program with a call that ww3-replay/ww3_capture.F90 makes itself.
--
--     w3src4md.F90:1426-1430  USTARM = 5. ; ALPHAM = 20.*AALPHA ; DELUST = USTARM/REAL(IUSTAR)
--                             DELALP = ALPHAM/REAL(IALPHA) ; CONST1 = BBETA/KAPPA**2
--     w3src4md.F90:1436-1439  W(2:JTOT-1) = 1. ; W(1) = 0.5 ; W(JTOT) = 0.5 ; X0 = 0.05
--     w3src4md.F90:1443-1449  UST = MAX(REAL(K)*DELUST, 0.000001) ; ZZ00 = UST**2*AALPHA/GRAV
--                             IF (ZZ0MAX.NE.0) ZZ00 = MIN(ZZ00,ZZ0MAX) ; ZZ0 = ZZ00*(1+FLOAT(L)*DELALP/AALPHA)
--                             OMEGACC = MAX(OMEGAC, X0*GRAV/UST) ; YC = OMEGACC*SQRT(ZZ0/GRAV)
--                             DELY = MAX((1.-YC)/REAL(JTOT), 0.)
--     w3src4md.F90:1453-1466  DO J=1,JTOT: Y = YC+REAL(J-1)*DELY ; OMEGA = Y*SQRT(GRAV/ZZ0) ; CM = GRAV/OMEGA
--                               ZX = UST/CM + ZZALP ; ZARG = MIN(KAPPA/ZX, 20.)
--                               ZMU = MIN(GRAV*ZZ0/CM**2*EXP(ZARG), 1.) ; ZLOG = MIN(ALOG(ZMU), 0.)
--                               ZBETA = CONST1*ZMU*ZLOG**4 ; TAUHFT(K,L) = TAUHFT(K,L) + W(J)*ZBETA/Y*DELY
--
-- The arithmetic is gfortran -O3's (-fdump-tree-optimized at the pin): no loop is vectorised and
-- the sum over J is in order; KAPPA**2 is folded to the float 0.16000001132488250732421875 and
-- X0*GRAV to 0.490299999713897705078125; DELUST is the float 0.05 the program stores; SQRT(ZZ0/GRAV),
-- SQRT(GRAV/ZZ0) and GRAV*ZZ0 are computed once per entry; ZLOG**4 is (ZLOG*ZLOG)*(ZLOG*ZLOG).
-- One lane is one entry, lane = K + (IUSTAR+1) L, the order of TAUHFT in memory. JTOT is the
-- parameter `jtot` (250 in WW3), so that Agda does not unfold the sum.
--
-- `tauhf-T`: the launch gives the table at every entry, by refl, in every model.
module OceanTriton.TABUTAUHF where

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
    sigmax delust aalpha bbeta zzalp zz0max : R
    iustar ialpha jtot : ℕ

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

  kOf lOf : ℕ → ℕ
  kOf t = imod t (iustar ℕ.+ 1)
  lOf t = idiv t (iustar ℕ.+ 1)

  ust zz00 zz0 yc dely : ℕ → R
  ust t  = op max (fromℕ (kOf t) * delust) (ℓ (+ 1 / 1000000))
  zz00 t = let a = aalpha * (ust t * ust t) ÷ g in
           if cmp ne zz0max z then op min zz0max a else a
  zz0 t  = (aalpha * ℓ (+ 20 / 1) ÷ ℓ (+ 200 / 1) * fromℕ (lOf t) ÷ aalpha + one) * zz00 t
  yc t   = fun fsqrt (zz0 t ÷ g) * op max sigmax (ℓ (+ 490299999713897705078125 / 1000000000000000000000000) ÷ ust t)
  dely t = op max ((one - yc t) ÷ ℓ (+ 250 / 1)) z

  term : ℕ → ℕ → R
  term t j =
    let y    = fromℕ j * dely t + yc t
        cm   = g ÷ (fun fsqrt (g ÷ zz0 t) * y)
        zmu  = op min (zz0 t * g ÷ (cm * cm) * fun fexp (op min (ℓ (+ 2 / 5) ÷ (ust t ÷ cm + zzalp)) (ℓ (+ 20 / 1)))) one
        zlog = op min (fun flog zmu) z
        w    = if j <ᵇ 1 then ℓ (+ 1 / 2) else (if j <ᵇ jtot ∸ 1 then one else ℓ (+ 1 / 2))
    in w * (bbeta ÷ ℓ (+ 16000001132488250732421875 / 100000000000000000000000000) * zmu * (zlog * zlog * (zlog * zlog))) ÷ y * dely t

  T : ℕ → R
  T t = foldN jtot z (λ j r → r + term t j)

-- ---------------------------------------------------------------------------------------------
-- The program

tauhfSig : Sig
tauhfSig = record { nf = 1 ; ni = 0 ; nfp = 6 ; nip = 4 }

open Syntax tauhfSig

private
  TB : Fin 1
  TB = # 0

  sigmax delust aalpha bbeta zzalp zz0max : ∀ {v a} → FE v a
  sigmax = fpar (# 0) ; delust = fpar (# 1) ; aalpha = fpar (# 2) ; bbeta = fpar (# 3) ; zzalp = fpar (# 4)
  zz0max = fpar (# 5)

  IUS IAL NTAB JTOT : Fin 4
  IUS = # 0 ; IAL = # 1 ; NTAB = # 2 ; JTOT = # 3

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  g one z : ∀ {v a} → FE v a
  g = c (+ 4903 / 500) ; one = c (+ 1 / 1) ; z = c (+ 0 / 1)

  kI lI : ∀ {v} → IE v
  kI = rem lane (ipar IUS +ᵢ nat 1)
  lI = quot lane (ipar IUS +ᵢ nat 1)

  ust zz00 zz0 yc dely : ∀ {v a} → FE v a
  ust  = op max (real kI ⊗ delust) (c (+ 1 / 1000000))
  zz00 = sel ne zz0max z (op min zz0max (aalpha ⊗ (ust ⊗ ust) ⊘ g)) (aalpha ⊗ (ust ⊗ ust) ⊘ g)
  zz0  = (aalpha ⊗ c (+ 20 / 1) ⊘ c (+ 200 / 1) ⊗ real lI ⊘ aalpha ⊕ one) ⊗ zz00
  yc   = fn fsqrt (zz0 ⊘ g) ⊗ op max sigmax (c (+ 490299999713897705078125 / 1000000000000000000000000) ⊘ ust)
  dely = op max ((one ⊖ yc) ⊘ c (+ 250 / 1)) z

  -- The sum over J, var 0 = J - 1, acc 0 = TAUHFT(K,L) so far.
  term : FE 1 1
  term = w ⊗ (bbeta ⊘ c (+ 16000001132488250732421875 / 100000000000000000000000000) ⊗ zmu ⊗ (zlog ⊗ zlog ⊗ (zlog ⊗ zlog)))
         ⊘ y ⊗ dely
    where
      y cm zmu zlog w : FE 1 1
      y    = real (var (# 0)) ⊗ dely ⊕ yc
      cm   = g ⊘ (fn fsqrt (g ⊘ zz0) ⊗ y)
      zmu  = op min (zz0 ⊗ g ⊘ (cm ⊗ cm) ⊗ fn fexp (op min (c (+ 2 / 5) ⊘ (ust ⊘ cm ⊕ zzalp)) (c (+ 20 / 1)))) one
      zlog = op min (fn flog zmu) z
      w    = isel (var (# 0)) (nat 1) (c (+ 1 / 2)) (isel (var (# 0)) (ipar JTOT ∸ᵢ nat 1) one (c (+ 1 / 2)))

  tB : FE 0 0
  tB = fold JTOT (ipar JTOT) z (acc (# 0) ⊕ term)

tauhfLaunches : List Launch
tauhfLaunches =
  launch "tabu_tauhf" tB NTAB TB "TAUHFT(K,L), the trapezoidal sum over JTOT points (w3src4md.F90:1426-1466)" ∷ []

tauhf : ProgL
tauhf = record
  { name = "tabu_tauhf"
  ; farrays = "TAUHFT" ∷ []
  ; iarrays = []
  ; fparams = "sigmax" ∷ "delust" ∷ "aalpha" ∷ "bbeta" ∷ "zzalp" ∷ "zz0max" ∷ []
  ; iparams = "iustar" ∷ "ialpha" ∷ "ntab" ∷ "jtot" ∷ []
  ; launches = L.map single tauhfLaunches
  ; results = (TB , NTAB) ∷ []
  ; doc = "WAVEWATCH III's ST4 high-frequency stress table TABU_TAUHF, one lane per entry" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {tauhfSig} M

  env₀ : Env tauhfSig R
  env₀ = env ((λ _ → Model.lit M (+ 0 / 1)) ∷ []) []
             (I.sigmax ∷ I.delust ∷ I.aalpha ∷ I.bbeta ∷ I.zzalp ∷ I.zz0max ∷ [])
             (I.iustar ∷ I.ialpha ∷ (I.iustar ℕ.+ 1) ℕ.* (I.ialpha ℕ.+ 1) ∷ I.jtot ∷ []) 0

  out : Env tauhfSig R
  out = runL (ProgL.launches tauhf) env₀

  tauhf-T : ∀ t → lookup (Env.farr out) (# 0) t ≡ Routine.T M x t
  tauhf-T t = refl
