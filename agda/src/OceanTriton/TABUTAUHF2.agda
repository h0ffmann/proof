{-# OPTIONS --safe --without-K #-}

-- The high-frequency stress tables of WAVEWATCH III's ST4 with the sheltering of the tail,
-- TABU_TAUHF2, read from model/src/w3src4md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6, commit
-- 92e2cf66. INSIN4 calls it after TABU_TAUHF when TTAUWSHELTER > 0 (w3src4md.F90:1021-1026), as in
-- ww3_ts1 (TTAUWSHELTER = 0.3), and it writes TAUHFT again: the TAUHFT that W3SIN4 reads in that
-- run is this routine's, not TABU_TAUHF's. TAUHFT2(K,L,I) is the stress of the tail when the
-- friction velocity is lowered by the stress the tail itself takes, LEVTAIL = I DELTAIL.
--
--     w3src4md.F90:1623-1630  USTARM = 5. ; ALPHAM = 20.*AALPHA ; DELUST = USTARM/REAL(IUSTAR)
--                             DELALP = ALPHAM/REAL(IALPHA) ; DELTAIL = ALPHAM/REAL(ILEVTAIL)
--                             CONST1 = BBETA/KAPPA**2 ; OMEGAC = SIGMAX
--     w3src4md.F90:1645-1652  DO K: UST0 = MAX(REAL(K)*DELUST, 0.000001) ; DO L: UST = UST0
--                             ZZ0 = UST0**2*(AALPHA+FLOAT(L)*DELALP)/GRAV
--                             OMEGACC = MAX(OMEGAC, X0*GRAV/UST) ; YC = OMEGACC*SQRT(ZZ0/GRAV)
--                             DELY = MAX((1.-YC)/REAL(JTOT), 0.)
--     w3src4md.F90:1656-1662  DO I: LEVTAIL = REAL(I)*DELTAIL ; TAUHFT(K,L) = 0. ; TAUHFT2(K,L,I) = 0.
--                             TAUW0 = UST0**2 ; TAUW = TAUW0
--     w3src4md.F90:1663-1683  DO J=1,JTOT: Y = YC+REAL(J-1)*DELY ; OMEGA = Y*SQRT(GRAV/ZZ0) ; CM = GRAV/OMEGA
--                             ZBETA with UST0: TAUHFT(K,L) += W(J)*ZBETA/Y*DELY
--                             ZBETA with UST: TAUHFT2(K,L,I) += W(J)*ZBETA*(UST/UST0)**2/Y*DELY
--                             TAUW = TAUW-W(J)*UST**2*ZBETA*LEVTAIL/Y*DELY ; UST = SQRT(MAX(TAUW,0.0001))
--
-- UST = UST0 is set once per (K,L), before the loop over I (:1648), while TAUW is set again for
-- every I (:1661): the plane I starts from the friction velocity that the plane I-1 left. So an
-- entry of TAUHFT2 depends on every plane below it, and the program folds over the planes below
-- the lane's (`ustStart`) before the plane itself. TAUHFT(K,L) is set to 0 for every I and summed
-- with UST0 only, so its value is that of one plane.
--
-- The arithmetic is gfortran -O3's (-fdump-tree-optimized at the pin): no loop is vectorised and
-- every sum over J is in order; KAPPA**2 is folded to the float 0.16000001132488250732421875 and
-- X0*GRAV to 0.490299999713897705078125; DELUST, DELALP and DELTAIL are the module's floats, which
-- the program takes as values; ZZ0 is ((AALPHA+L DELALP) UST0²)/GRAV; GRAV*ZZ0/CM**2 is
-- (ZZ0*GRAV)/(CM*CM); ZMU*CONST1 comes before ZLOG**4, which is (ZLOG*ZLOG)*(ZLOG*ZLOG); UST**2 is
-- UST*UST and (UST/UST0)**2 is the square of the quotient. The UST of step J is SQRT(MAX(TAUW,
-- 0.0001)) of the TAUW after step J-1 (the same float as the one the loop carries), and the UST
-- the plane starts from at J = 1.
--
-- One lane is one entry, t = lane + BASE, K = t mod (IUSTAR+1), L = (t div (IUSTAR+1)) mod
-- (IALPHA+1), I = t div ((IUSTAR+1)(IALPHA+1)), the order of the tables in memory; BASE lets a
-- replay take a few planes of TAUHFT2. JTOT is the parameter `jtot` (250 in WW3), so that Agda
-- does not unfold the sums.
--
-- `tauhf2-T`, `tauhf2-T2`: the launches give both tables at every entry, by refl, in every model.
module OceanTriton.TABUTAUHF2 where

open import Data.Bool using (if_then_else_)
open import Data.Fin using (Fin; zero; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; _∸_; _<ᵇ_)
open import Data.Integer using (+_)
open import Data.Product using (_,_; proj₁; proj₂)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record Inputs (R : Set) : Set where
  field
    sigmax delust delalp deltail aalpha bbeta zzalp : R
    iustar ialpha jtot base : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  g one z const1 : R
  g = ℓ (+ 4903 / 500) ; one = ℓ (+ 1 / 1) ; z = ℓ (+ 0 / 1)
  const1 = bbeta ÷ ℓ (+ 16000001132488250732421875 / 100000000000000000000000000)

  kOf lOf iOf : ℕ → ℕ
  kOf t = imod t (iustar ℕ.+ 1)
  lOf t = imod (idiv t (iustar ℕ.+ 1)) (ialpha ℕ.+ 1)
  iOf t = idiv t ((iustar ℕ.+ 1) ℕ.* (ialpha ℕ.+ 1))

  ust0 u2 zz0 yc dely s69 s73 : ℕ → R
  ust0 t = op max (fromℕ (kOf t) * delust) (ℓ (+ 1 / 1000000))
  u2 t   = ust0 t * ust0 t
  zz0 t  = (aalpha + fromℕ (lOf t) * delalp) * u2 t ÷ g
  yc t   = fun fsqrt (zz0 t ÷ g) * op max (ℓ (+ 490299999713897705078125 / 1000000000000000000000000) ÷ ust0 t) sigmax
  dely t = op max ((one - yc t) ÷ ℓ (+ 250 / 1)) z
  s69 t  = fun fsqrt (g ÷ zz0 t)
  s73 t  = zz0 t * g

  y cm c74 : ℕ → ℕ → R
  y t j   = fromℕ j * dely t + yc t
  cm t j  = g ÷ (s69 t * y t j)
  c74 t j = s73 t ÷ (cm t j * cm t j)

  -- ZBETA of step j for the friction velocity u.
  zb : ℕ → ℕ → R → R
  zb t j u =
    let zmu  = op min (c74 t j * fun fexp (op min (ℓ (+ 2 / 5) ÷ (u ÷ cm t j + zzalp)) (ℓ (+ 20 / 1)))) one
        zlog = op min (fun flog zmu) z
    in zmu * const1 * (zlog * zlog * (zlog * zlog))

  w : ℕ → R
  w j = if j <ᵇ 1 then ℓ (+ 1 / 2) else (if j <ᵇ jtot ∸ 1 then one else ℓ (+ 1 / 2))

  T : ℕ → R
  T t = foldN jtot z (λ j r → w j * zb t j (ust0 t) ÷ y t j * dely t + r)

  -- The UST of step j: the plane's start u at j = 0, else the root of the TAUW so far.
  us : ℕ → R → R → R
  us j u tw = if j <ᵇ 1 then u else fun fsqrt (op max tw (ℓ (+ 1 / 10000)))

  tauwStep : ℕ → ℕ → ℕ → R → R → R
  tauwStep t i j u tw =
    let s = us j u tw in tw - w j * (s * s) * zb t j s * (fromℕ i * deltail) ÷ y t j * dely t

  ustStart : ℕ → R
  ustStart t = foldN (iOf t) (ust0 t)
    (λ i u → fun fsqrt (op max (foldN jtot (u2 t) (λ j tw → tauwStep t i j u tw)) (ℓ (+ 1 / 10000))))

  T2 : ℕ → R
  T2 t =
    let u = ustStart t in
    proj₂ (foldN jtot (u2 t , z) (λ j p →
      tauwStep t (iOf t) j u (proj₁ p) ,
      w j * zb t j (us j u (proj₁ p)) * ((us j u (proj₁ p) ÷ ust0 t) * (us j u (proj₁ p) ÷ ust0 t))
        ÷ y t j * dely t + proj₂ p))

-- ---------------------------------------------------------------------------------------------
-- The program

tauhf2Sig : Sig
tauhf2Sig = record { nf = 2 ; ni = 0 ; nfp = 7 ; nip = 7 }

open Syntax tauhf2Sig

private
  TB T2B : Fin 2
  TB = # 0 ; T2B = # 1

  sigmax delust delalp deltail aalpha bbeta zzalp : ∀ {v a} → FE v a
  sigmax = fpar (# 0) ; delust = fpar (# 1) ; delalp = fpar (# 2) ; deltail = fpar (# 3)
  aalpha = fpar (# 4) ; bbeta = fpar (# 5) ; zzalp = fpar (# 6)

  IUS IAL NTAB NTAB2 JTOT NPL BASE : Fin 7
  IUS = # 0 ; IAL = # 1 ; NTAB = # 2 ; NTAB2 = # 3 ; JTOT = # 4 ; NPL = # 5 ; BASE = # 6

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  g one z const1 floor : ∀ {v a} → FE v a
  g = c (+ 4903 / 500) ; one = c (+ 1 / 1) ; z = c (+ 0 / 1)
  const1 = bbeta ⊘ c (+ 16000001132488250732421875 / 100000000000000000000000000)
  floor = c (+ 1 / 10000)

  tI kI lI iI : ∀ {v} → IE v
  tI = lane +ᵢ ipar BASE
  kI = rem tI (ipar IUS +ᵢ nat 1)
  lI = rem (quot tI (ipar IUS +ᵢ nat 1)) (ipar IAL +ᵢ nat 1)
  iI = quot tI ((ipar IUS +ᵢ nat 1) *ᵢ (ipar IAL +ᵢ nat 1))

  ust0 u2 zz0 yc dely s69 s73 : ∀ {v a} → FE v a
  ust0 = op max (real kI ⊗ delust) (c (+ 1 / 1000000))
  u2   = ust0 ⊗ ust0
  zz0  = (aalpha ⊕ real lI ⊗ delalp) ⊗ u2 ⊘ g
  yc   = fn fsqrt (zz0 ⊘ g) ⊗ op max (c (+ 490299999713897705078125 / 1000000000000000000000000) ⊘ ust0) sigmax
  dely = op max ((one ⊖ yc) ⊘ c (+ 250 / 1)) z
  s69  = fn fsqrt (g ⊘ zz0)
  s73  = zz0 ⊗ g

  -- Inside a sum over J, var 0 = J - 1.
  y cm c74 w : ∀ {v a} → FE (ℕ.suc v) a
  y   = real (var zero) ⊗ dely ⊕ yc
  cm  = g ⊘ (s69 ⊗ y)
  c74 = s73 ⊘ (cm ⊗ cm)
  w   = isel (var zero) (nat 1) (c (+ 1 / 2)) (isel (var zero) (ipar JTOT ∸ᵢ nat 1) one (c (+ 1 / 2)))

  zb : ∀ {v a} → FE (ℕ.suc v) a → FE (ℕ.suc v) a
  zb u = zmu ⊗ const1 ⊗ (zlog ⊗ zlog ⊗ (zlog ⊗ zlog))
    where
      zmu zlog : FE _ _
      zmu  = op min (c74 ⊗ fn fexp (op min (c (+ 2 / 5) ⊘ (u ⊘ cm ⊕ zzalp)) (c (+ 20 / 1)))) one
      zlog = op min (fn flog zmu) z

  us : ∀ {v a} → FE (ℕ.suc v) a → FE (ℕ.suc v) a → FE (ℕ.suc v) a
  us u tw = isel (var zero) (nat 1) u (fn fsqrt (op max tw floor))

  tauwStep : ∀ {v a} → FE (ℕ.suc v) a → FE (ℕ.suc v) a → FE (ℕ.suc v) a → FE (ℕ.suc v) a
  tauwStep lev u tw = tw ⊖ w ⊗ (us u tw ⊗ us u tw) ⊗ zb (us u tw) ⊗ lev ⊘ y ⊗ dely

  tB : FE 0 0
  tB = fold JTOT (ipar JTOT) z (w ⊗ zb ust0 ⊘ y ⊗ dely ⊕ acc (# 0))

  -- The UST the lane's plane starts from: a fold over the planes below it, var 0 = I, acc 0 = UST;
  -- inside, the sum over J with var 1 = I, acc 0 = TAUW, acc 1 = UST.
  ustStart : FE 0 0
  ustStart = fold NPL iI ust0
    (fn fsqrt (op max (fold JTOT (ipar JTOT) u2 (tauwStep (real (var (# 1)) ⊗ deltail) (acc (# 1)) (acc (# 0))))
                      floor))

  -- acc 0 = TAUW, acc 1 = TAUHFT2 so far, acc 2 = the plane's start.
  t2B : FE 0 0
  t2B = bind ustStart
    (fold2 (# 1) JTOT (ipar JTOT) u2 z
      (tauwStep (real iI ⊗ deltail) (acc (# 2)) (acc (# 0)))
      (w ⊗ zb (us (acc (# 2)) (acc (# 0))) ⊗ ((us (acc (# 2)) (acc (# 0)) ⊘ ust0) ⊗ (us (acc (# 2)) (acc (# 0)) ⊘ ust0))
         ⊘ y ⊗ dely ⊕ acc (# 1)))

tauhf2Launches : List Launch
tauhf2Launches =
    launch "tabu_tauhf2_t"  tB  NTAB  TB  "TAUHFT(K,L), with UST0 (w3src4md.F90:1645-1684)"
  ∷ launch "tabu_tauhf2_t2" t2B NTAB2 T2B "TAUHFT2(K,L,I), after the planes below I (w3src4md.F90:1645-1688)"
  ∷ []

tauhf2 : ProgL
tauhf2 = record
  { name = "tabu_tauhf2"
  ; farrays = "TAUHFT" ∷ "TAUHFT2" ∷ []
  ; iarrays = []
  ; fparams = "sigmax" ∷ "delust" ∷ "delalp" ∷ "deltail" ∷ "aalpha" ∷ "bbeta" ∷ "zzalp" ∷ []
  ; iparams = "iustar" ∷ "ialpha" ∷ "ntab" ∷ "ntab2" ∷ "jtot" ∷ "nplane" ∷ "base" ∷ []
  ; launches = L.map single tauhf2Launches
  ; results = (TB , NTAB) ∷ (T2B , NTAB2) ∷ []
  ; doc = "WAVEWATCH III's ST4 high-frequency stress tables TABU_TAUHF2, one lane per entry" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) (ntab2 nplane : ℕ) where
  module I = Inputs x
  open Eval {tauhf2Sig} M

  env₀ : Env tauhf2Sig R
  env₀ = env ((λ _ → Model.lit M (+ 0 / 1)) ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ []) []
             (I.sigmax ∷ I.delust ∷ I.delalp ∷ I.deltail ∷ I.aalpha ∷ I.bbeta ∷ I.zzalp ∷ [])
             (I.iustar ∷ I.ialpha ∷ (I.iustar ℕ.+ 1) ℕ.* (I.ialpha ℕ.+ 1) ∷ ntab2 ∷ I.jtot ∷ nplane ∷ I.base ∷ []) 0

  out : Env tauhf2Sig R
  out = runL (ProgL.launches tauhf2) env₀

  tauhf2-T : ∀ t → lookup (Env.farr out) (# 0) t ≡ Routine.T M x (t ℕ.+ I.base)
  tauhf2-T t = refl

  tauhf2-T2 : ∀ t → lookup (Env.farr out) (# 1) t ≡ Routine.T2 M x (t ℕ.+ I.base)
  tauhf2-T2 t = refl
