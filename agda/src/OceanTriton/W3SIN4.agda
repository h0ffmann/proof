{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's ST4 wind input W3SIN4, read from model/src/w3src4md.F90 of MetOcean's fork at
-- tag 7.14.mos-92e2cf6, commit 92e2cf66, without the switch STAB3 (so ISTAB = 3 only), as
-- W3SRCE calls it in a time step (w3srcemd.F90:1236). The program covers every branch of the
-- routine under that switch: SSWELLF(2) zero or not (FW from the table FWTABLE), SSWELLF(4) and
-- SSWELLF(7) of either sign (the smooth or the sharp change between viscous and turbulent
-- swell damping), the swell term on or off, and TTAUWSHELTER above zero (the 3D table TAUHFT2)
-- or not (TAUHFT).
--
--     w3src4md.F90:603-619   UORB, AORB: sums over IK of EB SIG**2 DDEN/CG and EB DDEN/CG
--     w3src4md.F90:621-623   UORB = 2 SQRT(UORB) ; AORB1 = 2 AORB**(1-0.5 SSWELLF(6)) ; RE = 4 UORB AORB1/NU_AIR
--     w3src4md.F90:627-644   PTURB, PVISC (TANH smoothing when SSWELLF(7) > 0)
--     w3src4md.F90:647-660   FW, FU, FUD (FWTABLE when SSWELLF(2) /= 0)
--     w3src4md.F90:680-700   UST = MAX(USTAR,0.0001) ; TAUX, TAUY ; CONST0 = BBETA DRAT/KAPPA**2
--     w3src4md.F90:702-789   DO IK: the stress so far shelters the band (TAUPX, TAUPY, USTP,
--                            USDIRP), then DO ITH: DSTAB, LLWS, the swell term, TEMP2 into
--                            STRESSSTAB (DSTAB >= 0) or STRESSSTABN (DSTAB < 0)
--     w3src4md.F90:791-807   D = DSTAB ; S = D A
--     w3src4md.F90:812-879   the high-frequency stress (TEMP over the last band, the table) and
--                            TAUWX, TAUWY, capped by USTAR**2 - EPS1
--
-- The band loop is the routine's one sequential dependency: band IK sees the stress of the bands
-- below it. That is a fold of a pair (`fold2`): the lane IK of STX and STY is the stress after
-- IK bands, each lane folding the bands below it again, so no lane waits for another.
--
-- Read from gfortran -O3's optimised code of this file at the pin (the GIMPLE of
-- -fdump-tree-optimized, ocean-triton/PLAN.md): no loop of the routine is vectorised; COS and SIN of
-- one angle are one sincosf; X**2, X**3, X**4 and SIG**5 are products, (X*X)*(X*X) for X**4 and
-- (S*(S*S))*(S*S) for S**5; X**0.25, AORB**(...) and COSWIND**SSINTHP call powf; the constants
-- KAPPA**2, 0.1*NU_AIR, 2*NU_AIR, GRAV**2*TPI and EPS2**2 are folded to the float32 that the
-- product gives at run time, so the products are written. FACLN1 and FACLN2 are not used.
--
-- Indices start at 0: ik = IK - 1, ith = ITH - 1, is = ith + ik NTH. TAUHFT(I,J) is
-- TH(I + (IUSTAR+1) J) and TAUHFT2(I,J,K) is TH2(I + (IUSTAR+1) J + (IUSTAR+1)(IALPHA+1) K),
-- Fortran's column order. INT(X) is `Model.trunc`, which may give 0 below 0: every index here is
-- clamped at 0 or 1, or comes from a value that is not negative.
--
-- `sin4-S`, `sin4-D`, `sin4-LLWS`, `sin4-TAU`: the seven launches give the routine's S, D, LLWS
-- (1 for .TRUE.) and TAUWX, TAUWY, TAUWNX, TAUWNY, by refl, in every model of the arithmetic.
module OceanTriton.W3SIN4 where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _<ᵇ_)
open import Data.Integer using (+_)
open import Data.Product using (_,_; proj₁; proj₂)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl; sym; trans; cong; cong₂)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record Inputs (R : Set) : Set where
  field
    A CG K SIG SIG2 DDEN DDEN2 ECOS ESIN FWT TH TH2 : ℕ → R
    u ustar usdir z0 drat dth bbeta zzalp zz0rat shelt sw1 sw2 sw3 sw4 sw5 sw6 sw7 sinthp : R
    aalpha delust delalp deltail delab abmin grav nuair kappa tpi : R
    nth nk nspec iustar ialpha ilevtail sizefw : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  mx mn : R → R → R
  mx = op max ; mn = op min
  ℓ : ℚ → R
  ℓ = lit
  z one half : R
  z = ℓ (+ 0 / 1) ; one = ℓ (+ 1 / 1) ; half = ℓ (+ 1 / 2)

  ikOf ithOf : ℕ → ℕ
  ikOf is  = idiv is nth
  ithOf is = imod is nth

  -- :618-648
  ub : R
  ub = mx ustar (ℓ (+ 1 / 10000))

  eb : ℕ → R
  eb ik = foldN nth z (λ j r → r + A (ik ℕ.* nth ℕ.+ j))

  uorbS aorbS uorb re smooth pturb pvisc : R
  uorbS = foldN nk z (λ ik r → r + eb ik * (SIG ik * SIG ik) * DDEN ik ÷ CG ik)
  aorbS = foldN nk z (λ ik r → r + eb ik * DDEN ik ÷ CG ik)
  uorb  = ℓ (+ 2 / 1) * fun fsqrt uorbS
  re    = ℓ (+ 4 / 1) * uorb * (ℓ (+ 2 / 1) * pow aorbS (one - half * sw6)) ÷ nuair
  smooth = half * fun ftanh ((re - sw4) ÷ sw7)
  pturb = if cmp lt z sw4 then (if cmp lt z sw7 then half + smooth else (if cmp le re sw4 then z else one)) else one
  pvisc = if cmp lt z sw4 then (if cmp lt z sw7 then half - smooth else (if cmp le re sw4 then one else z)) else one

  -- :650-662
  fw fu fud : R
  fw = if cmp ne sw2 z
       then (let xi = (fun flog10 (mx (ℓ (+ 2 / 1) * fun fsqrt aorbS ÷ mx (ℓ (+ 1 / 10) * nuair ÷ ub) (zz0rat * z0)) (ℓ (+ 3 / 1))) - abmin) ÷ delab
                 ind = (sizefw ∸ 1) ℕ.⊓ trunc xi
                 d₁ = mn one (xi - fromℕ ind)
             in FWT ind * (one - d₁) + FWT (ind ℕ.+ 1) * d₁)
       else mx (fun fabs sw3) z
  fu  = if cmp ne sw2 z then fun fabs sw3 else z
  fud = if cmp ne sw2 z then sw2 else z

  -- The six, as the program keeps them: UORB, PTURB, PVISC, FW, FU, FUD. What follows reads them
  -- from sc, so that the proofs can take them from the program's buffer.
  scal : ℕ → R
  scal j = if j <ᵇ 1 then uorb else (if j <ᵇ 2 then pturb else (if j <ᵇ 3 then pvisc
           else (if j <ᵇ 4 then fw else (if j <ᵇ 5 then fu else fud))))

  -- :673-686
  taux tauy const0 shel : R
  taux = ub * ub * fun fcos usdir
  tauy = ub * ub * fun fsin usdir
  const0 = bbeta * drat ÷ (kappa * kappa)
  shel = fun fabs shelt

  -- The band's shelter (:703-707), from the stress sx, sy of the bands below.
  tpx tpy ustpB dirB cosB sinB : R → R → R
  tpx sx sy = taux - shel * sx
  tpy sx sy = tauy - shel * sy
  ustpB sx sy = mn (pow (tpx sx sy * tpx sx sy + tpy sx sy * tpy sx sy) (ℓ (+ 1 / 4))) (mx ub (ℓ (+ 3 / 10)))
  dirB sx sy = op atan2 (tpy sx sy) (tpx sx sy)
  cosB sx sy = fun fcos (dirB sx sy)
  sinB sx sy = fun fsin (dirB sx sy)

  -- The band's constants (:708-728) and one direction (:729-787).
  cw : ℕ → ℕ → R → R → R
  cw ik ith cosu sinu = ECOS (ik ℕ.* nth ℕ.+ ith) * cosu + ESIN (ik ℕ.* nth ℕ.+ ith) * sinu

  ucn : ℕ → R → R
  ucn ik ustp = ustp * (K (ik ℕ.* nth) ÷ SIG2 (ik ℕ.* nth)) + zzalp

  zlog : ℕ → ℕ → R → R → R → R
  zlog ik ith cosu sinu ustp = fun flog (K (ik ℕ.* nth) * z0) + kappa ÷ (cw ik ith cosu sinu * ucn ik ustp)

  dst0 : ℕ → ℕ → R → R → R → R
  dst0 ik ith cosu sinu ustp =
    if cmp lt (ℓ (+ 1 / 100)) (cw ik ith cosu sinu)
    then (let zl = zlog ik ith cosu sinu ustp in
          if cmp lt zl z
          then SIG2 (ik ℕ.* nth) * const0 * fun fexp zl * ((zl * zl) * (zl * zl)) * ucn ik ustp * ucn ik ustp
               * pow (cw ik ith cosu sinu) sinthp
          else z)
    else z

  -- The six scalars come as values, so that a proof can replace them one by one.
  swell6 : R → R → R → R → R → R → ℕ → ℕ → R → R → R → R → R
  swell6 c0 c1 c2 c3 c4 c5 ik ith cosu sinu ustp d =
    let is0 = ik ℕ.* nth
        swv = fun fneg (sw5 * drat * ℓ (+ 2 / 1) * K is0 * fun fsqrt (ℓ (+ 2 / 1) * nuair * SIG2 is0))
        swt = fun fneg (drat * sw1 * ℓ (+ 16 / 1) * (SIG2 is0 * SIG2 is0) ÷ grav)
        add = d + c1 * (swt * (c3 * c0 + (c4 + c5 * cw ik ith cosu sinu) * ustp)) + c2 * swv
    in if cmp lt z sw3 then add
       else (if cmp ne sw1 z then (if cmp lt d (ℓ (+ 1 / 10000000) * SIG2 (is0 ℕ.+ ith)) then add else d) else d)

  swell : (ℕ → R) → ℕ → ℕ → R → R → R → R → R
  swell sc = swell6 (sc 0) (sc 1) (sc 2) (sc 3) (sc 4) (sc 5)

  dst : (ℕ → R) → ℕ → ℕ → R → R → R → R
  dst sc ik ith cosu sinu ustp = swell sc ik ith cosu sinu ustp (dst0 ik ith cosu sinu ustp)

  llws : ℕ → ℕ → R → R → R → R
  llws ik ith cosu sinu ustp =
    if cmp lt (ℓ (+ 1 / 100)) (cw ik ith cosu sinu)
    then (if cmp le one (ℓ (+ 28 / 1) * (K (ik ℕ.* nth) ÷ SIG2 (ik ℕ.* nth)) * ustar * cw ik ith cosu sinu) then one
          else (if cmp lt (zlog ik ith cosu sinu ustp) z then one else z))
    else z

  -- TEMP2 (:779-780), NaN set to 0.
  temp2 : ℕ → ℕ → R → R
  temp2 ik is d =
    let t = DDEN2 (ik ℕ.* nth) ÷ CG ik * grav ÷ (SIG ik ÷ K (ik ℕ.* nth) * drat) * d * A is
    in if cmp ne t t then z else t

  -- STRESSSTAB after the bands below ik (:781-787), in the Fortran's order.
  bandS : (ℕ → R) → (ℕ → R) → ℕ → R → R → R → R
  bandS sc E ik sx sy s0 =
    foldN nth s0 (λ ith r →
      let d = dst sc ik ith (cosB sx sy) (sinB sx sy) (ustpB sx sy)
          t = temp2 ik (ik ℕ.* nth ℕ.+ ith) d
      in if cmp lt d z then r else r + t * E (ik ℕ.* nth ℕ.+ ith))

  shelter : (ℕ → R) → ℕ → Data.Product._×_ R R
  shelter sc n = foldN n (z , z) (λ ik p → bandS sc ECOS ik (proj₁ p) (proj₂ p) (proj₁ p) , bandS sc ESIN ik (proj₁ p) (proj₂ p) (proj₂ p))

  sxA syA : ℕ → R
  sxA k = proj₁ (shelter scal k)
  syA k = proj₂ (shelter scal k)

  -- A point's D and LLWS from the stress below its band (the proofs below go through these).
  Dat6 : R → R → R → R → R → R → ℕ → R → R → R
  Dat6 c0 c1 c2 c3 c4 c5 is sx sy =
    let ik = ikOf is ; ith = ithOf is
    in swell6 c0 c1 c2 c3 c4 c5 ik ith (cosB sx sy) (sinB sx sy) (ustpB sx sy) (dst0 ik ith (cosB sx sy) (sinB sx sy) (ustpB sx sy))
  Dat : (ℕ → R) → ℕ → R → R → R
  Dat sc = Dat6 (sc 0) (sc 1) (sc 2) (sc 3) (sc 4) (sc 5)
  LLat : ℕ → R → R → R
  LLat is sx sy = llws (ikOf is) (ithOf is) (cosB sx sy) (sinB sx sy) (ustpB sx sy)

  D S LLWS : ℕ → R
  D is = Dat scal is (sxA (ikOf is)) (syA (ikOf is))
  S is = D is * A is
  LLWS is = LLat is (sxA (ikOf is)) (syA (ikOf is))

  -- TAUWNX, TAUWNY (:794-795): the negative part, every point in order, from D (d).
  tauwnF : (ℕ → R) → (ℕ → R) → R
  tauwnF E d = foldN nspec z (λ is r → let t = temp2 (ikOf is) is (d is) in if cmp lt (d is) z then r + t * E is else r)

  -- The high-frequency stress and the cap (:812-879), with COSU and SINU of the last band and
  -- the stress X, Y of all bands.
  tauw : R → R → R → R → Data.Product._×_ R R
  tauw cosu sinu X Y =
    let km = nk ∸ 1
        temp = foldN nth z (λ ith r →
                 let m = mx (ECOS (km ℕ.* nth ℕ.+ ith) * cosu + ESIN (km ℕ.* nth ℕ.+ ith) * sinu) z
                     t = r + A (km ℕ.* nth ℕ.+ ith) * (m * m * m)
                 in if cmp ne t t then z else t)
        s = SIG km
        c₀ = dth * (s * (s * s) * (s * s)) ÷ (grav * grav * tpi) * tpi * s ÷ CG km
        px = taux - shel * X ; py = tauy - shel * Y
        us = pow (px * px + py * py) (ℓ (+ 1 / 4))
        dir = op atan2 py px
        xi = us ÷ delust
        i = 1 ℕ.⊔ ((iustar ∸ 1) ℕ.⊓ trunc xi)
        di = mx (mn one (xi - fromℕ i)) z
        xj = mx z ((grav * z0 ÷ (mx us (ℓ (+ 1 / 100000)) * mx us (ℓ (+ 1 / 100000))) - aalpha) ÷ delalp)
        j = 1 ℕ.⊔ ((ialpha ∸ 1) ℕ.⊓ trunc xj)
        dj = mx z (mn one (xj - fromℕ j))
        n₁ = iustar ℕ.+ 1
        n₂ = (iustar ℕ.+ 1) ℕ.* (ialpha ℕ.+ 1)
        tau1 = if cmp lt z shelt
               then (let xk = c₀ * temp ÷ deltail
                         k = (ilevtail ∸ 1) ℕ.⊓ trunc xk
                         dk = mn one (xk - fromℕ k)
                     in ((TH2 (i ℕ.+ n₁ ℕ.* j ℕ.+ n₂ ℕ.* k) * (one - di) + TH2 (i ℕ.+ 1 ℕ.+ n₁ ℕ.* j ℕ.+ n₂ ℕ.* k) * di) * (one - dj)
                         + (TH2 (i ℕ.+ n₁ ℕ.* (j ℕ.+ 1) ℕ.+ n₂ ℕ.* k) * (one - di) + TH2 (i ℕ.+ 1 ℕ.+ n₁ ℕ.* (j ℕ.+ 1) ℕ.+ n₂ ℕ.* k) * di) * dj)
                        * (one - dk)
                        + ((TH2 (i ℕ.+ n₁ ℕ.* j ℕ.+ n₂ ℕ.* (k ℕ.+ 1)) * (one - di) + TH2 (i ℕ.+ 1 ℕ.+ n₁ ℕ.* j ℕ.+ n₂ ℕ.* (k ℕ.+ 1)) * di) * (one - dj)
                         + (TH2 (i ℕ.+ n₁ ℕ.* (j ℕ.+ 1) ℕ.+ n₂ ℕ.* (k ℕ.+ 1)) * (one - di) + TH2 (i ℕ.+ 1 ℕ.+ n₁ ℕ.* (j ℕ.+ 1) ℕ.+ n₂ ℕ.* (k ℕ.+ 1)) * di) * dj)
                        * dk)
               else (TH (i ℕ.+ n₁ ℕ.* j) * (one - di) + TH (i ℕ.+ 1 ℕ.+ n₁ ℕ.* j) * di) * (one - dj)
                    + (TH (i ℕ.+ n₁ ℕ.* (j ℕ.+ 1)) * (one - di) + TH (i ℕ.+ 1 ℕ.+ n₁ ℕ.* (j ℕ.+ 1)) * di) * dj
        tauhf = c₀ * temp * (us * us) * tau1
        twx = X + tauhf * fun fcos dir
        twy = Y + tauhf * fun fsin dir
        tw = fun fsqrt (twx * twx + twy * twy)
        twb = mn tw (mx (mx ustar (ℓ (+ 1 / 1000000)) * mx ustar (ℓ (+ 1 / 1000000)) - ℓ (+ 1 / 100000)) (ℓ (+ 1 / 1000000) * ℓ (+ 1 / 1000000)))
    in (if cmp lt twb tw then twx * twb ÷ tw else twx) , (if cmp lt twb tw then twy * twb ÷ tw else twy)

  -- TAUWX, TAUWY, TAUWNX, TAUWNY.
  TAUat : ℕ → R → R → R → R → R → R → R
  TAUat i sx sy X Y nx ny =
    if i <ᵇ 2 then (if i <ᵇ 1 then proj₁ (tauw (cosB sx sy) (sinB sx sy) X Y) else proj₂ (tauw (cosB sx sy) (sinB sx sy) X Y))
    else (if i <ᵇ 3 then nx else ny)

  TAU : ℕ → R
  TAU i = TAUat i (sxA (nk ∸ 1)) (syA (nk ∸ 1)) (sxA nk) (syA nk) (tauwnF ECOS D) (tauwnF ESIN D)

-- ---------------------------------------------------------------------------------------------
-- The program

sin4Sig : Sig
sin4Sig = record { nf = 19 ; ni = 0 ; nfp = 28 ; nip = 10 }

open Syntax sin4Sig

private
  -- Float arrays: inputs, then the buffers the launches write.
  A CG K SIG SIG2 DDEN DDEN2 ECOS ESIN FWT TH TH2 SC STX STY D S LL TAU : Fin 19
  A = # 0 ; CG = # 1 ; K = # 2 ; SIG = # 3 ; SIG2 = # 4 ; DDEN = # 5 ; DDEN2 = # 6 ; ECOS = # 7
  ESIN = # 8 ; FWT = # 9 ; TH = # 10 ; TH2 = # 11
  SC = # 12 ; STX = # 13 ; STY = # 14 ; D = # 15 ; S = # 16 ; LL = # 17 ; TAU = # 18

  ustar usdir z0 drat dth bbeta zzalp zz0rat shelt sw1 sw2 sw3 sw4 sw5 sw6 sw7 sinthp
    aalpha delust delalp deltail delab abmin grav nuair kappa tpi : ∀ {v a} → FE v a
  ustar = fpar (# 1) ; usdir = fpar (# 2) ; z0 = fpar (# 3) ; drat = fpar (# 4)
  dth = fpar (# 5) ; bbeta = fpar (# 6) ; zzalp = fpar (# 7) ; zz0rat = fpar (# 8) ; shelt = fpar (# 9)
  sw1 = fpar (# 10) ; sw2 = fpar (# 11) ; sw3 = fpar (# 12) ; sw4 = fpar (# 13) ; sw5 = fpar (# 14)
  sw6 = fpar (# 15) ; sw7 = fpar (# 16) ; sinthp = fpar (# 17) ; aalpha = fpar (# 18)
  delust = fpar (# 19) ; delalp = fpar (# 20) ; deltail = fpar (# 21) ; delab = fpar (# 22)
  abmin = fpar (# 23) ; grav = fpar (# 24) ; nuair = fpar (# 25) ; kappa = fpar (# 26) ; tpi = fpar (# 27)

  NTH NK NSPEC NK1 N4 N6 IUSTAR IALPHA ILEVTAIL SIZEFW : Fin 10
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; NK1 = # 3 ; N4 = # 4 ; N6 = # 5
  IUSTAR = # 6 ; IALPHA = # 7 ; ILEVTAIL = # 8 ; SIZEFW = # 9

  nth nk nspec iustar ialpha ilevtail sizefw : ∀ {v} → IE v
  nth = ipar NTH ; nk = ipar NK ; nspec = ipar NSPEC ; iustar = ipar IUSTAR ; ialpha = ipar IALPHA
  ilevtail = ipar ILEVTAIL ; sizefw = ipar SIZEFW

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  z₀ one half : ∀ {v a} → FE v a
  z₀ = lit (+ 0 / 1) ; one = lit (+ 1 / 1) ; half = lit (+ 1 / 2)

  a0 a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 : ∀ {v a} → FE v (13 ℕ.+ a)
  a0 = acc (# 0) ; a1 = acc (# 1) ; a2 = acc (# 2) ; a3 = acc (# 3) ; a4 = acc (# 4) ; a5 = acc (# 5)
  a6 = acc (# 6) ; a7 = acc (# 7) ; a8 = acc (# 8) ; a9 = acc (# 9) ; a10 = acc (# 10)
  a11 = acc (# 11) ; a12 = acc (# 12)

  -- The scalars of :618-662, one lane each: UORB, PTURB, PVISC, FW, FU, FUD.
  ub : ∀ {v a} → FE v a
  ub = op max ustar (c (+ 1 / 10000))

  eb : ∀ {v a} → IE v → FE v a
  eb k = fold NTH nth z₀ (acc (# 0) ⊕ ld A (wkI k *ᵢ nth +ᵢ var (# 0)))

  uorbS aorbS uorb re smooth : ∀ {v a} → FE v a
  uorbS = fold NK nk z₀ (acc (# 0) ⊕ eb (var (# 0)) ⊗ (ld SIG (var (# 0)) ⊗ ld SIG (var (# 0))) ⊗ ld DDEN (var (# 0)) ⊘ ld CG (var (# 0)))
  aorbS = fold NK nk z₀ (acc (# 0) ⊕ eb (var (# 0)) ⊗ ld DDEN (var (# 0)) ⊘ ld CG (var (# 0)))
  uorb = c (+ 2 / 1) ⊗ fn fsqrt uorbS
  re = c (+ 4 / 1) ⊗ uorb ⊗ (c (+ 2 / 1) ⊗ pow aorbS (one ⊖ half ⊗ sw6)) ⊘ nuair
  smooth = half ⊗ fn ftanh ((re ⊖ sw4) ⊘ sw7)

  fwB : FE 0 0
  fwB = sel ne sw2 z₀
    (bind ((fn flog10 (op max (c (+ 2 / 1) ⊗ fn fsqrt aorbS ⊘ op max (c (+ 1 / 10) ⊗ nuair ⊘ ub) (zz0rat ⊗ z0)) (c (+ 3 / 1))) ⊖ abmin) ⊘ delab)
      (ix (acc (# 0))
        (bind (op min one (acc (# 0) ⊖ real ind))
          (ld FWT ind ⊗ (one ⊖ acc (# 0)) ⊕ ld FWT (ind +ᵢ nat 1) ⊗ acc (# 0)))))
    (op max (fn fabs sw3) z₀)
    where ind = minᵢ (sizefw ∸ᵢ nat 1) (var (# 0))

  scB : FE 0 0
  scB = isel lane (nat 1) uorb
       (isel lane (nat 2) (sel lt z₀ sw4 (sel lt z₀ sw7 (half ⊕ smooth) (sel le re sw4 z₀ one)) one)
       (isel lane (nat 3) (sel lt z₀ sw4 (sel lt z₀ sw7 (half ⊖ smooth) (sel le re sw4 one z₀)) one)
       (isel lane (nat 4) fwB
       (isel lane (nat 5) (sel ne sw2 z₀ (fn fabs sw3) z₀) (sel ne sw2 z₀ sw2 z₀)))))

  UORB PTURB PVISC FW FU FUD : ∀ {v a} → FE v a
  UORB = ld SC (nat 0) ; PTURB = ld SC (nat 1) ; PVISC = ld SC (nat 2)
  FW = ld SC (nat 3) ; FU = ld SC (nat 4) ; FUD = ld SC (nat 5)

  taux tauy const0 shel : ∀ {v a} → FE v a
  taux = ub ⊗ ub ⊗ fn fcos usdir
  tauy = ub ⊗ ub ⊗ fn fsin usdir
  const0 = bbeta ⊗ drat ⊘ (kappa ⊗ kappa)
  shel = fn fabs shelt

  -- The band's shelter: binds TAUPX, TAUPY, USTP, USDIRP, COSU, SINU around the body, in which
  -- SINU is acc 0, COSU acc 1, USDIRP acc 2 and USTP acc 3.
  band : ∀ {v a} → FE v a → FE v a → FE v (6 ℕ.+ a) → FE v a
  band sx sy body =
    bind (taux ⊖ shel ⊗ sx)
    (bind (tauy ⊖ shel ⊗ wk sy)
    (bind (op min (pow (acc (# 1) ⊗ acc (# 1) ⊕ acc (# 0) ⊗ acc (# 0)) (c (+ 1 / 4))) (op max ub (c (+ 3 / 10))))
    (bind (op atan2 (acc (# 1)) (acc (# 2)))
    (bind (fn fcos (acc (# 0)))
    (bind (fn fsin (acc (# 1))) body)))))

  cwE : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a
  cwE k ith cosu sinu = ld ECOS (k *ᵢ nth +ᵢ ith) ⊗ cosu ⊕ ld ESIN (k *ᵢ nth +ᵢ ith) ⊗ sinu

  ucnE : ∀ {v a} → IE v → FE v a → FE v a
  ucnE k ustp = ustp ⊗ (ld K (k *ᵢ nth) ⊘ ld SIG2 (k *ᵢ nth)) ⊕ zzalp

  zlogE : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a → FE v a
  zlogE k ith cosu sinu ustp = fn flog (ld K (k *ᵢ nth) ⊗ z0) ⊕ kappa ⊘ (cwE k ith cosu sinu ⊗ ucnE k ustp)

  dst0E : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a → FE v a
  dst0E k ith cosu sinu ustp =
    sel lt (c (+ 1 / 100)) (cwE k ith cosu sinu)
      (bind (zlogE k ith cosu sinu ustp)
        (sel lt (acc (# 0)) z₀
          (ld SIG2 (k *ᵢ nth) ⊗ const0 ⊗ fn fexp (acc (# 0)) ⊗ ((acc (# 0) ⊗ acc (# 0)) ⊗ (acc (# 0) ⊗ acc (# 0)))
           ⊗ ucnE k (wk ustp) ⊗ ucnE k (wk ustp) ⊗ pow (cwE k ith (wk cosu) (wk sinu)) sinthp)
          z₀))
      z₀

  swellE : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a → FE v a → FE v a
  swellE k ith cosu sinu ustp d =
    sel lt z₀ sw3 plus (sel ne sw1 z₀ (sel lt d (c (+ 1 / 10000000) ⊗ ld SIG2 (k *ᵢ nth +ᵢ ith)) plus d) d)
    where swv = fn fneg (sw5 ⊗ drat ⊗ c (+ 2 / 1) ⊗ ld K (k *ᵢ nth) ⊗ fn fsqrt (c (+ 2 / 1) ⊗ nuair ⊗ ld SIG2 (k *ᵢ nth)))
          swt = fn fneg (drat ⊗ sw1 ⊗ c (+ 16 / 1) ⊗ (ld SIG2 (k *ᵢ nth) ⊗ ld SIG2 (k *ᵢ nth)) ⊘ grav)
          plus = d ⊕ PTURB ⊗ (swt ⊗ (FW ⊗ UORB ⊕ (FU ⊕ FUD ⊗ cwE k ith cosu sinu) ⊗ ustp)) ⊕ PVISC ⊗ swv

  dstE : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a → FE v a
  dstE k ith cosu sinu ustp = bind (dst0E k ith cosu sinu ustp) (swellE k ith (wk cosu) (wk sinu) (wk ustp) (acc (# 0)))

  llwsE : ∀ {v a} → IE v → IE v → FE v a → FE v a → FE v a → FE v a
  llwsE k ith cosu sinu ustp =
    sel lt (c (+ 1 / 100)) (cwE k ith cosu sinu)
      (sel le one (c (+ 28 / 1) ⊗ (ld K (k *ᵢ nth) ⊘ ld SIG2 (k *ᵢ nth)) ⊗ ustar ⊗ cwE k ith cosu sinu) one
        (sel lt (zlogE k ith cosu sinu ustp) z₀ one z₀))
      z₀

  temp2E : ∀ {v a} → IE v → IE v → FE v a → FE v a
  temp2E k is d = bind (ld DDEN2 (k *ᵢ nth) ⊘ ld CG k ⊗ grav ⊘ (ld SIG k ⊘ ld K (k *ᵢ nth) ⊗ drat) ⊗ d ⊗ ld A is)
                       (sel ne (acc (# 0)) (acc (# 0)) z₀ (acc (# 0)))

  -- One band of the stress (:781-787): the fold over the directions starts from the component
  -- s0 (acc 6 is SX, acc 7 is SY under `band`).
  bandStep : Fin 19 → Fin 8 → FE 1 2
  bandStep E s0 = band (acc (# 0)) (acc (# 1)) (fold NTH nth (acc s0)
    (bind (dstE (var (# 1)) (var (# 0)) (acc (# 2)) (acc (# 1)) (acc (# 4)))
      (bind (temp2E (var (# 1)) (var (# 1) *ᵢ nth +ᵢ var (# 0)) (acc (# 0)))
        (sel lt (acc (# 1)) z₀ (acc (# 2)) (acc (# 2) ⊕ acc (# 0) ⊗ ld E (var (# 1) *ᵢ nth +ᵢ var (# 0)))))))

  stB : Fin 2 → FE 0 0
  stB w = fold2 w NK lane z₀ z₀ (bandStep ECOS (# 6)) (bandStep ESIN (# 7))

  ik ith : ∀ {v} → IE v
  ik = quot lane nth ; ith = rem lane nth

  dB llB sB : FE 0 0
  dB = band (ld STX ik) (ld STY ik) (dstE ik ith (acc (# 1)) (acc (# 0)) (acc (# 3)))
  llB = band (ld STX ik) (ld STY ik) (llwsE ik ith (acc (# 1)) (acc (# 0)) (acc (# 3)))
  sB = ld D lane ⊗ ld A lane

  tauwnB : Fin 19 → FE 0 0
  tauwnB E = fold NSPEC nspec z₀
    (bind (temp2E (quot (var (# 0)) nth) (var (# 0)) (ld D (var (# 0))))
      (sel lt (ld D (var (# 0))) z₀ (acc (# 1) ⊕ acc (# 0) ⊗ ld E (var (# 0))) (acc (# 1))))

  -- The table's value at (i, j, k), three integers in scope.
  t2 : ∀ {v a} → IE v → IE v → IE v → FE v a
  t2 i j k = ld TH2 (i +ᵢ (iustar +ᵢ nat 1) *ᵢ j +ᵢ (iustar +ᵢ nat 1) *ᵢ (ialpha +ᵢ nat 1) *ᵢ k)

  t1 : ∀ {v a} → IE v → IE v → FE v a
  t1 i j = ld TH (i +ᵢ (iustar +ᵢ nat 1) *ᵢ j)

  clampU clampA : ∀ {v} → IE v → IE v
  clampU x = maxᵢ (nat 1) (minᵢ (iustar ∸ᵢ nat 1) x)
  clampA x = maxᵢ (nat 1) (minᵢ (ialpha ∸ᵢ nat 1) x)

  -- TAU1 (:845-865). In scope: INT(XI) var 1, INT(XJ) var 0; DELJ1 acc 0, DELI1 acc 2, CONST0
  -- acc 10, TEMP acc 11.
  tau1B : FE 2 18
  tau1B = sel lt z₀ shelt
    (bind (acc (# 10) ⊗ acc (# 11) ⊘ deltail)
      (ix (acc (# 0))
        (bind (op min one (acc (# 0) ⊖ real (minᵢ (ilevtail ∸ᵢ nat 1) (var (# 0)))))
          (((t2 i j k ⊗ (one ⊖ di) ⊕ t2 (i +ᵢ nat 1) j k ⊗ di) ⊗ (one ⊖ dj)
            ⊕ (t2 i (j +ᵢ nat 1) k ⊗ (one ⊖ di) ⊕ t2 (i +ᵢ nat 1) (j +ᵢ nat 1) k ⊗ di) ⊗ dj) ⊗ (one ⊖ acc (# 0))
           ⊕ ((t2 i j (k +ᵢ nat 1) ⊗ (one ⊖ di) ⊕ t2 (i +ᵢ nat 1) j (k +ᵢ nat 1) ⊗ di) ⊗ (one ⊖ dj)
            ⊕ (t2 i (j +ᵢ nat 1) (k +ᵢ nat 1) ⊗ (one ⊖ di) ⊕ t2 (i +ᵢ nat 1) (j +ᵢ nat 1) (k +ᵢ nat 1) ⊗ di) ⊗ dj) ⊗ acc (# 0)))))
    ((t1 i′ j′ ⊗ (one ⊖ acc (# 2)) ⊕ t1 (i′ +ᵢ nat 1) j′ ⊗ acc (# 2)) ⊗ (one ⊖ acc (# 0))
     ⊕ (t1 i′ (j′ +ᵢ nat 1) ⊗ (one ⊖ acc (# 2)) ⊕ t1 (i′ +ᵢ nat 1) (j′ +ᵢ nat 1) ⊗ acc (# 2)) ⊗ acc (# 0))
    where i = clampU (var (# 2)) ; j = clampA (var (# 1)) ; k = minᵢ (ilevtail ∸ᵢ nat 1) (var (# 0))
          di = acc (# 4) ; dj = acc (# 2)
          i′ = clampU (var (# 1)) ; j′ = clampA (var (# 0))

  -- :810-879 under `band` of the last bin (SINU acc 0, COSU acc 1); the lane picks TAUWX or TAUWY.
  tailB : FE 0 6
  tailB =
    bind (fold NTH nth z₀
           (bind (op max (ld ECOS (km *ᵢ nth +ᵢ var (# 0)) ⊗ acc (# 2) ⊕ ld ESIN (km *ᵢ nth +ᵢ var (# 0)) ⊗ acc (# 1)) z₀)
             (bind (acc (# 1) ⊕ ld A (km *ᵢ nth +ᵢ var (# 0)) ⊗ (acc (# 0) ⊗ acc (# 0) ⊗ acc (# 0)))
               (sel ne (acc (# 0)) (acc (# 0)) z₀ (acc (# 0))))))                        -- TEMP
    (bind (dth ⊗ (s ⊗ (s ⊗ s) ⊗ (s ⊗ s)) ⊘ (grav ⊗ grav ⊗ tpi) ⊗ tpi ⊗ s ⊘ ld CG km)      -- CONST0
    (bind (ld STX nk)                                                                       -- XSTRESS
    (bind (ld STY nk)                                                                       -- YSTRESS
    (bind (taux ⊖ shel ⊗ acc (# 1))                                                         -- TAUPX
    (bind (tauy ⊖ shel ⊗ acc (# 1))                                                         -- TAUPY
    (bind (pow (acc (# 1) ⊗ acc (# 1) ⊕ acc (# 0) ⊗ acc (# 0)) (c (+ 1 / 4)))               -- UST
    (bind (op atan2 (acc (# 1)) (acc (# 2)))                                                -- USDIRP
    (bind (acc (# 1) ⊘ delust)                                                              -- XI
    (ix (acc (# 0))
    (bind (op max (op min one (acc (# 0) ⊖ real (clampU (var (# 0))))) z₀)                   -- DELI1
    (bind (op max z₀ ((grav ⊗ z0 ⊘ (op max (acc (# 3)) (c (+ 1 / 100000)) ⊗ op max (acc (# 3)) (c (+ 1 / 100000))) ⊖ aalpha) ⊘ delalp))
    (ix (acc (# 0))                                                                         -- XJ
    (bind (op max z₀ (op min one (acc (# 0) ⊖ real (clampA (var (# 0))))))                  -- DELJ1
    (bind tau1B                                                                             -- TAU1
    (bind (acc (# 11) ⊗ acc (# 12) ⊗ (acc (# 6) ⊗ acc (# 6)) ⊗ acc (# 0))                   -- TAUHF
    (bind (acc (# 11) ⊕ acc (# 0) ⊗ fn fcos (acc (# 6)))                                   -- TAUWX
    (bind (acc (# 11) ⊕ acc (# 1) ⊗ fn fsin (acc (# 7)))                                   -- TAUWY
    (bind (fn fsqrt (acc (# 1) ⊗ acc (# 1) ⊕ acc (# 0) ⊗ acc (# 0)))                        -- TAUW
    (bind (op min (acc (# 0)) (op max (u2 ⊖ c (+ 1 / 100000)) (c (+ 1 / 1000000) ⊗ c (+ 1 / 1000000))))   -- TAUWB
      (isel lane (nat 1) (sel lt (acc (# 0)) (acc (# 1)) (acc (# 3) ⊗ acc (# 0) ⊘ acc (# 1)) (acc (# 3)))
                         (sel lt (acc (# 0)) (acc (# 1)) (acc (# 2) ⊗ acc (# 0) ⊘ acc (# 1)) (acc (# 2)))))))))))))))))))))))
   where km : ∀ {v} → IE v
         km = nk ∸ᵢ nat 1
         s : ∀ {v a} → FE v a
         s = ld SIG km
         u2 : ∀ {v a} → FE v a
         u2 = op max ustar (c (+ 1 / 1000000)) ⊗ op max ustar (c (+ 1 / 1000000))

  tauB : FE 0 0
  tauB = isel lane (nat 2) (band (ld STX (nk ∸ᵢ nat 1)) (ld STY (nk ∸ᵢ nat 1)) tailB)
                           (isel lane (nat 3) (tauwnB ECOS) (tauwnB ESIN))

LSC LSTX LSTY LD LS LLL LTAU : Launch
LSC  = launch "w3sin4_sc"  scB         N6    SC  "UORB, PTURB, PVISC, FW, FU, FUD (w3src4md.F90:603-660), one lane each"
LSTX = launch "w3sin4_stx" (stB (# 0)) NK1   STX "STRESSSTAB(3,1) after IK bands, one lane per IK (w3src4md.F90:702-789)"
LSTY = launch "w3sin4_sty" (stB (# 1)) NK1   STY "STRESSSTAB(3,2) after IK bands (w3src4md.F90:702-789)"
LD   = launch "w3sin4_d"   dB          NSPEC D   "D = DSTAB (w3src4md.F90:702-789, 791)"
LS   = launch "w3sin4_s"   sB          NSPEC S   "S = D A (w3src4md.F90:807)"
LLL  = launch "w3sin4_ll"  llB         NSPEC LL  "LLWS, 1 for .TRUE. (w3src4md.F90:745-763)"
LTAU = launch "w3sin4_tau" tauB        N4    TAU "TAUWX, TAUWY, TAUWNX, TAUWNY (w3src4md.F90:794-795, 812-879)"

sin4Launches : List Launch
sin4Launches = LSC ∷ LSTX ∷ LSTY ∷ LD ∷ LS ∷ LLL ∷ LTAU ∷ []

sin4 : ProgL
sin4 = record
  { name = "w3sin4"
  ; farrays = "A" ∷ "CG" ∷ "K" ∷ "SIG" ∷ "SIG2" ∷ "DDEN" ∷ "DDEN2" ∷ "ECOS" ∷ "ESIN" ∷ "FWT" ∷ "TH" ∷ "TH2"
              ∷ "SC" ∷ "STX" ∷ "STY" ∷ "D" ∷ "S" ∷ "LL" ∷ "TAU" ∷ []
  ; iarrays = []
  ; fparams = "u" ∷ "ustar" ∷ "usdir" ∷ "z0" ∷ "drat" ∷ "dth" ∷ "bbeta" ∷ "zzalp" ∷ "zz0rat" ∷ "shelt"
              ∷ "sw1" ∷ "sw2" ∷ "sw3" ∷ "sw4" ∷ "sw5" ∷ "sw6" ∷ "sw7" ∷ "sinthp" ∷ "aalpha" ∷ "delust"
              ∷ "delalp" ∷ "deltail" ∷ "delab" ∷ "abmin" ∷ "grav" ∷ "nuair" ∷ "kappa" ∷ "tpi" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "nk1" ∷ "n4" ∷ "n6" ∷ "iustar" ∷ "ialpha" ∷ "ilevtail" ∷ "sizefw" ∷ []
  ; launches = L.map single sin4Launches
  ; results = (S , NSPEC) ∷ (D , NSPEC) ∷ (LL , NSPEC) ∷ (TAU , N4) ∷ []
  ; doc = "WAVEWATCH III's ST4 wind input W3SIN4, without STAB3, in seven launches" }

-- ---------------------------------------------------------------------------------------------
-- Soundness
--
-- One refl over the whole routine unfolds the stress of the bands below at every use of it, which
-- takes Agda hours. So the proof has three kinds of step, each a refl that Agda checks in
-- seconds: a launch's body read in any environment (`inputsOf` names what it reads), the
-- stress buffers against `shelter`, and the environment the launches build against the inputs.
-- Congruence joins them.

module _ {R : Set} (M : Model R) where
  open Eval {sin4Sig} M

  -- The inputs a launch reads from an environment.
  inputsOf : Env sin4Sig R → Inputs R
  inputsOf ρ = record
    { A = f (# 0) ; CG = f (# 1) ; K = f (# 2) ; SIG = f (# 3) ; SIG2 = f (# 4) ; DDEN = f (# 5)
    ; DDEN2 = f (# 6) ; ECOS = f (# 7) ; ESIN = f (# 8) ; FWT = f (# 9) ; TH = f (# 10) ; TH2 = f (# 11)
    ; u = p (# 0) ; ustar = p (# 1) ; usdir = p (# 2) ; z0 = p (# 3) ; drat = p (# 4) ; dth = p (# 5)
    ; bbeta = p (# 6) ; zzalp = p (# 7) ; zz0rat = p (# 8) ; shelt = p (# 9) ; sw1 = p (# 10)
    ; sw2 = p (# 11) ; sw3 = p (# 12) ; sw4 = p (# 13) ; sw5 = p (# 14) ; sw6 = p (# 15) ; sw7 = p (# 16)
    ; sinthp = p (# 17) ; aalpha = p (# 18) ; delust = p (# 19) ; delalp = p (# 20) ; deltail = p (# 21)
    ; delab = p (# 22) ; abmin = p (# 23) ; grav = p (# 24) ; nuair = p (# 25) ; kappa = p (# 26) ; tpi = p (# 27)
    ; nth = n (# 0) ; nk = n (# 1) ; nspec = n (# 2) ; iustar = n (# 6) ; ialpha = n (# 7)
    ; ilevtail = n (# 8) ; sizefw = n (# 9) }
    where f = lookup (Env.farr ρ) ; p = lookup (Env.fpar ρ) ; n = lookup (Env.ipar ρ)

  private
    module Q (ρ : Env sin4Sig R) = Routine M (inputsOf ρ)
    F : Env sin4Sig R → Fin 19 → ℕ → R
    F ρ = lookup (Env.farr ρ)

  -- The bodies, in any environment.
  sc-body : ∀ ρ j → evF ρ j [] [] scB ≡ Q.scal ρ j
  sc-body ρ j = refl

  d-body : ∀ ρ is → evF ρ is [] [] dB ≡ Q.Dat ρ (F ρ (# 12)) is (F ρ (# 13) (Q.ikOf ρ is)) (F ρ (# 14) (Q.ikOf ρ is))
  d-body ρ is = refl

  s-body : ∀ ρ is → evF ρ is [] [] sB ≡ Model.op M mul (F ρ (# 15) is) (F ρ (# 0) is)
  s-body ρ is = refl

  ll-body : ∀ ρ is → evF ρ is [] [] llB ≡ Q.LLat ρ is (F ρ (# 13) (Q.ikOf ρ is)) (F ρ (# 14) (Q.ikOf ρ is))
  ll-body ρ is = refl

  tau-body : ∀ ρ i → evF ρ i [] [] tauB ≡
    Q.TAUat ρ i (F ρ (# 13) (Inputs.nk (inputsOf ρ) ∸ 1)) (F ρ (# 14) (Inputs.nk (inputsOf ρ) ∸ 1)) (F ρ (# 13) (Inputs.nk (inputsOf ρ))) (F ρ (# 14) (Inputs.nk (inputsOf ρ)))
                (Q.tauwnF ρ (F ρ (# 7)) (F ρ (# 15))) (Q.tauwnF ρ (F ρ (# 8)) (F ρ (# 15)))
  tau-body ρ i = refl

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  module Rt = Routine M x
  open Eval {sin4Sig} M

  env₀ : Env sin4Sig R
  env₀ = env (I.A ∷ I.CG ∷ I.K ∷ I.SIG ∷ I.SIG2 ∷ I.DDEN ∷ I.DDEN2 ∷ I.ECOS ∷ I.ESIN ∷ I.FWT ∷ I.TH ∷ I.TH2
              ∷ zf ∷ zf ∷ zf ∷ zf ∷ zf ∷ zf ∷ zf ∷ [])
             []
             (I.u ∷ I.ustar ∷ I.usdir ∷ I.z0 ∷ I.drat ∷ I.dth ∷ I.bbeta ∷ I.zzalp ∷ I.zz0rat ∷ I.shelt
              ∷ I.sw1 ∷ I.sw2 ∷ I.sw3 ∷ I.sw4 ∷ I.sw5 ∷ I.sw6 ∷ I.sw7 ∷ I.sinthp ∷ I.aalpha ∷ I.delust
              ∷ I.delalp ∷ I.deltail ∷ I.delab ∷ I.abmin ∷ I.grav ∷ I.nuair ∷ I.kappa ∷ I.tpi ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ suc I.nk ∷ 4 ∷ 6 ∷ I.iustar ∷ I.ialpha ∷ I.ilevtail ∷ I.sizefw ∷ []) 0
    where zf = λ _ → Model.lit M (+ 0 / 1)

  out : Env sin4Sig R
  out = runL (ProgL.launches sin4) env₀

  private
    P : Fin 19 → ℕ → R
    P b = lookup (Env.farr out) b

    foldN-cong : ∀ {A : Set} n (e : A) {f g : ℕ → A → A} → (∀ k r → f k r ≡ g k r) → foldN n e f ≡ foldN n e g
    foldN-cong zero    e h = refl
    foldN-cong (suc n) e {f} h = trans (cong (f n) (foldN-cong n e h)) (h n _)

    tauwn-cong : ∀ E {d d′ : ℕ → R} → (∀ is → d is ≡ d′ is) → Rt.tauwnF E d ≡ Rt.tauwnF E d′
    tauwn-cong E {d} {d′} h = foldN-cong I.nspec _ (λ is r → cong (stp′ is r) (h is))
      where stp′ : ℕ → R → R → R
            stp′ is r v = let t = Rt.temp2 (Rt.ikOf is) is v in if Model.cmp M lt v Rt.z then Model.op M add r (Model.op M mul t (E is)) else r

    cong6 : ∀ {a0 a1 a2 a3 a4 a5 b0 b1 b2 b3 b4 b5 : R} (f : R → R → R → R → R → R → R) →
            a0 ≡ b0 → a1 ≡ b1 → a2 ≡ b2 → a3 ≡ b3 → a4 ≡ b4 → a5 ≡ b5 → f a0 a1 a2 a3 a4 a5 ≡ f b0 b1 b2 b3 b4 b5
    cong6 f refl refl refl refl refl refl = refl

    TAU-cong : ∀ i {a b c d e f a′ b′ c′ d′ e′ f′} → a ≡ a′ → b ≡ b′ → c ≡ c′ → d ≡ d′ → e ≡ e′ → f ≡ f′ →
               Rt.TAUat i a b c d e f ≡ Rt.TAUat i a′ b′ c′ d′ e′ f′
    TAU-cong i refl refl refl refl refl refl = refl

  -- A buffer is read through stepL-here and stepL-other, and every environment is written as
  -- runL builds it: Agda then compares two equal environments without evaluating a body.
  private
    sc3 : ∀ j → lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 12) j ≡ Rt.scal j
    sc3 j = trans (stepL-other LSTY (stepL LSTX (stepL LSC env₀)) (# 12) j (λ ()))
              (trans (stepL-other LSTX (stepL LSC env₀) (# 12) j (λ ())) (trans (stepL-here LSC env₀ j) (sc-body M env₀ j)))

    stx3 : ∀ k → lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 13) k ≡ Rt.sxA k
    stx3 k = refl
    sty3 : ∀ k → lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 14) k ≡ Rt.syA k
    sty3 k = refl

    past : ∀ b k → b ≢ # 15 → b ≢ # 16 → b ≢ # 17 → lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) b k ≡ lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) b k
    past b k n15 n16 n17 = trans (stepL-other LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) b k n17) (trans (stepL-other LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))) b k n16) (stepL-other LD (stepL LSTY (stepL LSTX (stepL LSC env₀))) b k n15))

  -- The stress after k bands.
  sin4-STX : ∀ k → P (# 13) k ≡ Rt.sxA k
  sin4-STX k = trans (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 13) k (λ ())) (trans (past (# 13) k (λ ()) (λ ()) (λ ())) (stx3 k))

  sin4-STY : ∀ k → P (# 14) k ≡ Rt.syA k
  sin4-STY k = trans (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 14) k (λ ())) (trans (past (# 14) k (λ ()) (λ ()) (λ ())) (sty3 k))

  d4 : ∀ is → lookup (Env.farr (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) (# 15) is ≡ Rt.D is
  d4 is =
    trans (stepL-here LD (stepL LSTY (stepL LSTX (stepL LSC env₀))) is)
    (trans (d-body M (stepL LSTY (stepL LSTX (stepL LSC env₀))) is)
    (trans (frame (lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 12)) (lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 13) (Routine.ikOf M (inputsOf M (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is)) (lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 14) (Routine.ikOf M (inputsOf M (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is)))
    (trans (cong₂ (Rt.Dat (lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 12)) is) (stx3 (Routine.ikOf M (inputsOf M (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is)) (sty3 (Routine.ikOf M (inputsOf M (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is)))
           (cong6 (λ c0 c1 c2 c3 c4 c5 → Rt.Dat6 c0 c1 c2 c3 c4 c5 is (Rt.sxA (Rt.ikOf is)) (Rt.syA (Rt.ikOf is)))
             (sc3 0) (sc3 1) (sc3 2) (sc3 3) (sc3 4) (sc3 5)))))
    where frame : ∀ s a b → Routine.Dat M (inputsOf M (stepL LSTY (stepL LSTX (stepL LSC env₀)))) s is a b ≡ Rt.Dat s is a b
          frame s a b = refl

  sin4-D : ∀ is → P (# 15) is ≡ Rt.D is
  sin4-D is =
    trans (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 15) is (λ ()))
    (trans (stepL-other LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) (# 15) is (λ ()))
    (trans (stepL-other LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))) (# 15) is (λ ())) (d4 is)))

  sin4-S : ∀ is → P (# 16) is ≡ Rt.S is
  sin4-S is =
    trans (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 16) is (λ ()))
    (trans (stepL-other LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) (# 16) is (λ ()))
    (trans (stepL-here LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is)
    (trans (s-body M (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))) is) (cong₂ (Model.op M mul) (d4 is) aIn))))
    where aIn : lookup (Env.farr (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) (# 0) is ≡ I.A is
          aIn = trans (stepL-other LD (stepL LSTY (stepL LSTX (stepL LSC env₀))) (# 0) is (λ ())) (trans (stepL-other LSTY (stepL LSTX (stepL LSC env₀)) (# 0) is (λ ()))
                 (trans (stepL-other LSTX (stepL LSC env₀) (# 0) is (λ ())) (stepL-other LSC env₀ (# 0) is (λ ()))))

  sin4-LLWS : ∀ is → P (# 17) is ≡ Rt.LLWS is
  sin4-LLWS is =
    trans (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 17) is (λ ()))
    (trans (stepL-here LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) is)
    (trans (ll-body M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))) is)
    (trans (frame (lookup (Env.farr (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 13) (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is)) (lookup (Env.farr (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 14) (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is)))
           (cong₂ (Rt.LLat is) (st (# 13) (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is) (λ ()) (λ ()) (stx3 (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is))) (st (# 14) (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is) (λ ()) (λ ()) (sty3 (Routine.ikOf M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is)))))))
    where frame : ∀ a b → Routine.LLat M (inputsOf M (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) is a b ≡ Rt.LLat is a b
          frame a b = refl
          st : ∀ b k {v} → b ≢ # 15 → b ≢ # 16 → lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) b k ≡ v → lookup (Env.farr (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) b k ≡ v
          st b k n15 n16 h = trans (stepL-other LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))) b _ n16) (trans (stepL-other LD (stepL LSTY (stepL LSTX (stepL LSC env₀))) b _ n15) h)

  sin4-TAU : ∀ i → P (# 18) i ≡ Rt.TAU i
  sin4-TAU i =
    trans (stepL-here LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) i)
    (trans (tau-body M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) i)
    (trans (frame (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 13) ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1)) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 14) ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1)) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 13) (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))))) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 14) (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))))
                  (Routine.tauwnF M (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 7)) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 15)))
                  (Routine.tauwnF M (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 8)) (lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 15))))
      (TAU-cong i (rd (# 13) ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1) (λ ()) (λ ()) (λ ()) (stx3 ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1))) (rd (# 14) ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1) (λ ()) (λ ()) (λ ()) (sty3 ((Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) ∸ 1)))
                  (rd (# 13) (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) (λ ()) (λ ()) (λ ()) (stx3 (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))))) (rd (# 14) (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))))) (λ ()) (λ ()) (λ ()) (sty3 (Inputs.nk (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))))))
                (tauwn-cong I.ECOS d6) (tauwn-cong I.ESIN d6))))
    where frame : ∀ a b c d e f → Routine.TAUat M (inputsOf M (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) i a b c d e f ≡ Rt.TAUat i a b c d e f
          frame a b c d e f = refl
          rd : ∀ b k {v} → b ≢ # 15 → b ≢ # 16 → b ≢ # 17 → lookup (Env.farr (stepL LSTY (stepL LSTX (stepL LSC env₀)))) b k ≡ v → lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) b k ≡ v
          rd b k n15 n16 n17 h = trans (past b k n15 n16 n17) h
          d6 : ∀ is → lookup (Env.farr (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀))))))) (# 15) is ≡ Rt.D is
          d6 is = trans (sym (stepL-other LTAU (stepL LLL (stepL LS (stepL LD (stepL LSTY (stepL LSTX (stepL LSC env₀)))))) (# 15) is (λ ()))) (sin4-D is)
