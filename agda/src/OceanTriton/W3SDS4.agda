{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's ST4 dissipation W3SDS4, read from model/src/w3src4md.F90 of MetOcean's fork at
-- tag 7.14.mos-92e2cf6, commit 92e2cf66, in the configuration that ww3_ts1 runs (the defaults
-- of &SDS4, w3gridmd.F90:2077-2125): SSDSC(1) = 1, the saturation form of Ardhuin et al. (2010),
-- with the integration over SSDSDTH = 80° (< 180), no smoothing (SSDSBRFDF = 0), no straining
-- of B (SSDSC(8) = SSDSC(11) = 0, so FACSTRAINB = 1), then the cumulative, turbulent and viscous
-- terms. The program covers SSDSISO = 1 and ≠ 1 and both forms of MICHE; the replay checks that
-- the captured constants are in this configuration.
--
--     w3src4md.F90:2128   EPSR = SQRT(SSDSBR)
--     w3src4md.F90:2132   DO IK=IK1, NK
--     w3src4md.F90:2133     FACSAT = SIG(IK)*K(IK)**3*DTH
--     w3src4md.F90:2136     ASUM = SUM(A(IS0+1:IS0+NTH)) ;  BTH0(IK) = ASUM*FACSAT
--     w3src4md.F90:2167     BTH(IS) = DOT_PRODUCT(SATWEIGHTS(:,ITH), A(IS0+SATINDICES(:,ITH))) *FACSAT*FACSTRAINB
--     w3src4md.F90:2171     IF (SSDSISO.NE.1) BTH0(IK) = MAXVAL(BTH(IS0+1:IS0+NTH))
--     w3src4md.F90:2235   DO IK=IK1, NK
--     w3src4md.F90:2236     IF (SSDSBM(0).EQ.1) THEN MICHE=1. ELSE X=TANH(MIN(K(IK)*DEPTH,10.))
--     w3src4md.F90:2240       MICHE=(X*(SSDSBM(1)+X*(SSDSBM(2)+X*(SSDSBM(3)+X*SSDSBM(4)))))**2
--     w3src4md.F90:2242     COEF1 = SSDSBR*MICHE
--     w3src4md.F90:2246     SDIAGISO = SSDSC(2)*SIG(IK)*SSDSC(6)*(MAX(0.,BTH0(IK)/COEF1-1.))**2
--     w3src4md.F90:2249     COEF2 = SSDSC(2)*SIG(IK)*(1-SSDSC(6))/(COEF1*COEF1)
--     w3src4md.F90:2252     DDIAG(IK) = SDIAGISO + COEF2*((MAX(0.,BTH(IK)-COEF1))**SSDSP)
--     w3src4md.F90:2258   PB = (MAX(SQRT(BTH)-EPSR,0.))**2 ;  PB = PB*28.16 ;  BRLAMBDA = PB/(2.*PI**2.)
--     w3src4md.F90:2263   SRHS = DDIAG*A
--     w3src4md.F90:2485   IF (SSDSC(3).NE.0. .OR. SSDSC(5).NE.0. .OR. SSDSC(21).NE.0.) THEN DO IK=IK1, NK
--     w3src4md.F90:2487     FACTURB2 = -2.*SIG(IK)*K(IK)*FACTURB   (FACTURB = SSDSC(5)*USTAR**2/GRAV*DAIR/DWAT, :2048)
--     w3src4md.F90:2488     DVISC = -4.*SSDSC(21)*K(IK)*K(IK)
--     w3src4md.F90:2497     IF (SSDSC(3).NE.0 .AND. IK.GT.DIKCUMUL) DO IK2=IK1,IK-DIKCUMUL
--     w3src4md.F90:2499       IF (BTH0(IK2).GT.SSDSBR)
--     w3src4md.F90:2501         RENEWALFREQ = RENEWALFREQ + DOT_PRODUCT(CUMULW(IS2+1:IS2+NTH,IS), BRLAMBDA(IS2+1:IS2+NTH))
--     w3src4md.F90:2505     COSWIND = ECOS(ITH)*COS(USDIR) + ESIN(ITH)*SIN(USDIR)
--     w3src4md.F90:2506     DTURB = FACTURB2*MAX(0.,COSWIND)
--     w3src4md.F90:2509     DIAG2 = SSDSC(3)*RENEWALFREQ + DTURB + DVISC
--     w3src4md.F90:2510     DDIAG(IS) = DDIAG(IS) + DIAG2 ;  SRHS(IS) = SRHS(IS) + A(IS)*DIAG2
--
-- Indices start at 0: ik = IK - 1, ith = ITH - 1, is = IS - 1 = ith + ik NTH, ik1 = IK1 - 1, and
-- SATINDICES and SATWEIGHTS are laid out by direction, sati(ith NSAT + j) = SATINDICES(j+1,ITH) - 1;
-- CUMULW(r+1, c+1) is cumulw(r + c NSPEC), Fortran's column order. The tables are INSIN4's
-- (:1031-1173), DIKCUMUL included, and 2.*PI**2. is a constant the compiler folds, so all of
-- them are inputs. K**3 is K*K*K and X**2 is X*X, as gfortran expands an integer power; X**SSDSP
-- is a real power: gfortran -O3 vectorises that array expression (:2252) four directions at a
-- time from the first, through libmvec's _ZGVbN4vv_powf, `vpow`, and calls powf, `pow`, for
-- the last NTH mod 4 (ocean-triton/libmvec.py). -2.*… is written -(2.*…), which has the same bits. Arrays BTH, BTH0,
-- PB and the rest start at 0 (:2032-2041), so a bin below IK1 keeps D = S = 0.
--
-- The whitecap outputs after :2520 do not reach S or D and are not here.
--
-- `sds4-D`, `sds4-S`: the seven launches give the routine's D and S at every spectral point, by
-- refl, in every model of the arithmetic.
module OceanTriton.W3SDS4 where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; zero; suc; _∸_; _<ᵇ_)
open import Data.Integer using (+_; -_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record Inputs (R : Set) : Set where
  field
    A K CG SIG ECOS ESIN SATW CUMULW : ℕ → R
    SATI : ℕ → ℕ
    dth ssdsbr ssdsc2 ssdsc3 ssdsc5 ssdsc6 ssdsc21 ssdsp : R
    ssdsbm0 ssdsbm1 ssdsbm2 ssdsbm3 ssdsbm4 depth ustar usdir dair grav dwat twopi2 : R
    nth nk nspec nsat ik1 dikcumul iso1 : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  mx : R → R → R
  mx = op max
  mn : R → R → R
  mn = op min
  sqrt : R → R
  sqrt = fun fsqrt
  neg : R → R
  neg = fun fneg
  ℓ : ℚ → R
  ℓ = lit

  ikOf ithOf : ℕ → ℕ
  ikOf is  = idiv is nth
  ithOf is = imod is nth

  facsat : ℕ → R
  facsat ik = SIG ik * (K ik * K ik * K ik) * dth

  -- BTH (:2167): the weighted sum over the SATINDICES of the direction, in its order.
  bth : ℕ → R
  bth is = if ikOf is <ᵇ ik1 then ℓ (+ 0 / 1)
           else foldN nsat (ℓ (+ 0 / 1))
                  (λ j r → r + SATW (ithOf is ℕ.* nsat ℕ.+ j) * A (ikOf is ℕ.* nth ℕ.+ SATI (ithOf is ℕ.* nsat ℕ.+ j)))
                * facsat (ikOf is) * ℓ (+ 1 / 1)

  -- BTH0 (:2136, :2171): the bin's sum times FACSAT when SSDSISO = 1, else the largest BTH of
  -- the bin, the first one first (MAXVAL keeps the first of equal values; equal values have
  -- the same bits).
  bth0 : ℕ → R
  bth0 ik = if ik <ᵇ ik1 then ℓ (+ 0 / 1)
            else (if iso1 <ᵇ 1
                  then foldN (nth ∸ 1) (bth (ik ℕ.* nth)) (λ j r → if cmp lt r (bth (ik ℕ.* nth ℕ.+ (j ℕ.+ 1))) then bth (ik ℕ.* nth ℕ.+ (j ℕ.+ 1)) else r)
                  else foldN nth (ℓ (+ 0 / 1)) (λ j r → r + A (ik ℕ.* nth ℕ.+ j)) * facsat ik)

  miche : ℕ → R
  miche ik = if cmp ne ssdsbm0 (ℓ (+ 1 / 1))
             then (let X = fun ftanh (mn (K ik * depth) (ℓ (+ 10 / 1)))
                       y = X * (ssdsbm1 + X * (ssdsbm2 + X * (ssdsbm3 + X * ssdsbm4)))
                   in y * y)
             else ℓ (+ 1 / 1)

  coef1 : ℕ → R
  coef1 ik = ssdsbr * miche ik

  -- DDIAG after :2252.
  d1 : ℕ → R
  d1 is = if ikOf is <ᵇ ik1 then ℓ (+ 0 / 1)
          else (let ik = ikOf is
                    y  = mx (ℓ (+ 0 / 1)) (bth0 ik ÷ coef1 ik - ℓ (+ 1 / 1))
                in ssdsc2 * SIG ik * ssdsc6 * (y * y)
                   + ssdsc2 * SIG ik * (ℓ (+ 1 / 1) - ssdsc6) ÷ (coef1 ik * coef1 ik)
                     * (if ithOf is <ᵇ nth ∸ imod nth 4 then vpow b ssdsp else pow b ssdsp))
                where b = mx (ℓ (+ 0 / 1)) (bth is - coef1 (ikOf is))

  -- BRLAMBDA (:2258-2260).
  brl : ℕ → R
  brl is = let t = mx (sqrt (bth is) - sqrt ssdsbr) (ℓ (+ 0 / 1)) in t * t * ℓ (+ 704 / 25) ÷ twopi2

  -- SRHS after :2263.
  s1 : ℕ → R
  s1 is = d1 is * A is

  -- RENEWALFREQ (:2495-2504).
  renewal : ℕ → R
  renewal is =
    if cmp ne ssdsc3 (ℓ (+ 0 / 1))
    then (if dikcumul <ᵇ ikOf is ℕ.+ 1
          then foldN (ikOf is ℕ.+ 1 ∸ dikcumul ∸ ik1) (ℓ (+ 0 / 1))
                 (λ k r → if cmp lt ssdsbr (bth0 (ik1 ℕ.+ k))
                          then r + foldN nth (ℓ (+ 0 / 1))
                                     (λ j r′ → r′ + CUMULW ((ik1 ℕ.+ k) ℕ.* nth ℕ.+ j ℕ.+ is ℕ.* nspec) * brl ((ik1 ℕ.+ k) ℕ.* nth ℕ.+ j))
                          else r)
          else ℓ (+ 0 / 1))
    else ℓ (+ 0 / 1)

  -- DIAG2 (:2487-2509).
  diag2 : ℕ → R
  diag2 is =
    let ik = ikOf is ; ith = ithOf is
        facturb = ssdsc5 * (ustar * ustar) ÷ grav * dair ÷ dwat
        dturb = neg (ℓ (+ 2 / 1) * SIG ik * K ik * facturb)
                * mx (ℓ (+ 0 / 1)) (ECOS ith * fun fcos usdir + ESIN ith * fun fsin usdir)
        dvisc = neg (ℓ (+ 4 / 1) * ssdsc21 * K ik * K ik)
    in ssdsc3 * renewal is + dturb + dvisc

  -- The block of :2485 runs when one of the three constants is not zero.
  active : ∀ {A : Set} → A → A → A
  active t e = if cmp ne ssdsc3 (ℓ (+ 0 / 1)) then t
               else (if cmp ne ssdsc5 (ℓ (+ 0 / 1)) then t
               else (if cmp ne ssdsc21 (ℓ (+ 0 / 1)) then t else e))

  D S : ℕ → R
  D is = active (if ikOf is <ᵇ ik1 then d1 is else d1 is + diag2 is) (d1 is)
  S is = active (if ikOf is <ᵇ ik1 then s1 is else s1 is + A is * diag2 is) (s1 is)

-- ---------------------------------------------------------------------------------------------
-- The program

sds4Sig : Sig
sds4Sig = record { nf = 15 ; ni = 1 ; nfp = 20 ; nip = 7 }

open Syntax sds4Sig

private
  -- Float arrays: inputs, then the buffers the launches write.
  A K CG SIG ECOS ESIN SATW CUMULW BTH BTH0 D1 BRL S1 D S : Fin 15
  A = # 0 ; K = # 1 ; CG = # 2 ; SIG = # 3 ; ECOS = # 4 ; ESIN = # 5 ; SATW = # 6 ; CUMULW = # 7
  BTH = # 8 ; BTH0 = # 9 ; D1 = # 10 ; BRL = # 11 ; S1 = # 12 ; D = # 13 ; S = # 14

  dth ssdsbr ssdsc2 ssdsc3 ssdsc5 ssdsc6 ssdsc21 ssdsp ssdsbm0 ssdsbm1 ssdsbm2 ssdsbm3 ssdsbm4
    depth ustar usdir dair grav dwat twopi2 : ∀ {v a} → FE v a
  dth = fpar (# 0) ; ssdsbr = fpar (# 1) ; ssdsc2 = fpar (# 2) ; ssdsc3 = fpar (# 3)
  ssdsc5 = fpar (# 4) ; ssdsc6 = fpar (# 5) ; ssdsc21 = fpar (# 6) ; ssdsp = fpar (# 7)
  ssdsbm0 = fpar (# 8) ; ssdsbm1 = fpar (# 9) ; ssdsbm2 = fpar (# 10) ; ssdsbm3 = fpar (# 11)
  ssdsbm4 = fpar (# 12) ; depth = fpar (# 13) ; ustar = fpar (# 14) ; usdir = fpar (# 15)
  dair = fpar (# 16) ; grav = fpar (# 17) ; dwat = fpar (# 18) ; twopi2 = fpar (# 19)

  NTH NK NSPEC NSAT IK1 DIK ISO1 : Fin 7
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; NSAT = # 3 ; IK1 = # 4 ; DIK = # 5 ; ISO1 = # 6

  nth nspec nsat ik1 dik iso1 : ∀ {v} → IE v
  nth = ipar NTH ; nspec = ipar NSPEC ; nsat = ipar NSAT ; ik1 = ipar IK1 ; dik = ipar DIK ; iso1 = ipar ISO1

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  z0 one : ∀ {v a} → FE v a
  z0 = lit (+ 0 / 1) ; one = lit (+ 1 / 1)

  ik ith : ∀ {v} → IE v
  ik = quot lane nth ; ith = rem lane nth

  facsat : ∀ {v a} → IE v → FE v a
  facsat k = ld SIG k ⊗ (ld K k ⊗ ld K k ⊗ ld K k) ⊗ dth

  miche : ∀ {v a} → IE v → FE v a
  miche k = sel ne ssdsbm0 one (y ⊗ y) one
    where X = fn ftanh (op min (ld K k ⊗ depth) (c (+ 10 / 1)))
          y = X ⊗ (ssdsbm1 ⊕ X ⊗ (ssdsbm2 ⊕ X ⊗ (ssdsbm3 ⊕ X ⊗ ssdsbm4)))

  coef1 : ∀ {v a} → IE v → FE v a
  coef1 k = ssdsbr ⊗ miche k

  v0 v1 : ∀ {v} → IE (suc (suc v))
  v0 = var (# 0) ; v1 = var (# 1)

  bthB : FE 0 0
  bthB = isel ik ik1 z0
    (fold NSAT nsat z0 (acc (# 0) ⊕ ld SATW (rem lane nth *ᵢ nsat +ᵢ var (# 0))
                                   ⊗ ld A (quot lane nth *ᵢ nth +ᵢ iarr (# 0) (rem lane nth *ᵢ nsat +ᵢ var (# 0))))
     ⊗ facsat ik ⊗ one)

  bth0B : FE 0 0
  bth0B = isel lane ik1 z0
    (isel iso1 (nat 1)
      (fold NTH (nth ∸ᵢ nat 1) (ld BTH (lane *ᵢ nth))
        (sel lt (acc (# 0)) (ld BTH (lane *ᵢ nth +ᵢ (var (# 0) +ᵢ nat 1))) (ld BTH (lane *ᵢ nth +ᵢ (var (# 0) +ᵢ nat 1))) (acc (# 0))))
      (fold NTH nth z0 (acc (# 0) ⊕ ld A (lane *ᵢ nth +ᵢ var (# 0))) ⊗ facsat lane))

  d1B : FE 0 0
  d1B = isel ik ik1 z0
    (ssdsc2 ⊗ ld SIG ik ⊗ ssdsc6 ⊗ (y ⊗ y)
     ⊕ ssdsc2 ⊗ ld SIG ik ⊗ (one ⊖ ssdsc6) ⊘ (coef1 ik ⊗ coef1 ik) ⊗ isel (rem lane nth) (nth ∸ᵢ rem nth (nat 4)) (vpow b ssdsp) (pow b ssdsp))
    where y = op max z0 (ld BTH0 ik ⊘ coef1 ik ⊖ one)
          b = op max z0 (ld BTH lane ⊖ coef1 ik)

  brlB : FE 0 0
  brlB = t ⊗ t ⊗ c (+ 704 / 25) ⊘ twopi2
    where t = op max (fn fsqrt (ld BTH lane) ⊖ fn fsqrt ssdsbr) z0

  s1B : FE 0 0
  s1B = ld D1 lane ⊗ ld A lane

  renewalB : FE 0 0
  renewalB = sel ne ssdsc3 z0
    (isel dik (ik +ᵢ nat 1)
      (fold NK ((ik +ᵢ nat 1) ∸ᵢ dik ∸ᵢ ik1) z0
        (sel lt ssdsbr (ld BTH0 (ik1 +ᵢ var (# 0)))
          (acc (# 0) ⊕ fold NTH nth z0
             (acc (# 0) ⊕ ld CUMULW ((ik1 +ᵢ v1) *ᵢ nth +ᵢ v0 +ᵢ lane *ᵢ nspec) ⊗ ld BRL ((ik1 +ᵢ v1) *ᵢ nth +ᵢ v0)))
          (acc (# 0))))
      z0)
    z0

  diag2B : FE 0 0
  diag2B = ssdsc3 ⊗ renewalB ⊕ dturb ⊕ dvisc
    where facturb = ssdsc5 ⊗ (ustar ⊗ ustar) ⊘ grav ⊗ dair ⊘ dwat
          dturb = fn fneg (c (+ 2 / 1) ⊗ ld SIG ik ⊗ ld K ik ⊗ facturb)
                  ⊗ op max z0 (ld ECOS ith ⊗ fn fcos usdir ⊕ ld ESIN ith ⊗ fn fsin usdir)
          dvisc = fn fneg (c (+ 4 / 1) ⊗ ssdsc21 ⊗ ld K ik ⊗ ld K ik)

  active : FE 0 0 → FE 0 0 → FE 0 0
  active t e = sel ne ssdsc3 z0 t (sel ne ssdsc5 z0 t (sel ne ssdsc21 z0 t e))

  dB sB : FE 0 0
  dB = active (isel ik ik1 (ld D1 lane) (ld D1 lane ⊕ diag2B)) (ld D1 lane)
  sB = active (isel ik ik1 (ld S1 lane) (ld S1 lane ⊕ ld A lane ⊗ diag2B)) (ld S1 lane)

sds4Launches : List Launch
sds4Launches =
    launch "w3sds4_bth"  bthB  NSPEC BTH  "BTH, the saturation over SSDSDTH (w3src4md.F90:2133-2167)"
  ∷ launch "w3sds4_bth0" bth0B NK    BTH0 "BTH0, the bin's saturation (w3src4md.F90:2136, 2171), one lane per bin"
  ∷ launch "w3sds4_d1"   d1B   NSPEC D1   "DDIAG of the saturation term (w3src4md.F90:2235-2253)"
  ∷ launch "w3sds4_brl"  brlB  NSPEC BRL  "BRLAMBDA, the breaking crest length (w3src4md.F90:2258-2260)"
  ∷ launch "w3sds4_s1"   s1B   NSPEC S1   "SRHS = DDIAG A (w3src4md.F90:2263)"
  ∷ launch "w3sds4_d"    dB    NSPEC D    "DDIAG with the cumulative, turbulent and viscous terms (w3src4md.F90:2485-2510)"
  ∷ launch "w3sds4_s"    sB    NSPEC S    "SRHS with the cumulative, turbulent and viscous terms (w3src4md.F90:2485-2511)"
  ∷ []

sds4 : ProgL
sds4 = record
  { name = "w3sds4"
  ; farrays = "A" ∷ "K" ∷ "CG" ∷ "SIG" ∷ "ECOS" ∷ "ESIN" ∷ "SATW" ∷ "CUMULW"
              ∷ "BTH" ∷ "BTH0" ∷ "D1" ∷ "BRL" ∷ "S1" ∷ "D" ∷ "S" ∷ []
  ; iarrays = "SATI" ∷ []
  ; fparams = "dth" ∷ "ssdsbr" ∷ "ssdsc2" ∷ "ssdsc3" ∷ "ssdsc5" ∷ "ssdsc6" ∷ "ssdsc21" ∷ "ssdsp"
              ∷ "ssdsbm0" ∷ "ssdsbm1" ∷ "ssdsbm2" ∷ "ssdsbm3" ∷ "ssdsbm4" ∷ "depth" ∷ "ustar" ∷ "usdir"
              ∷ "dair" ∷ "grav" ∷ "dwat" ∷ "twopi2" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "nsat" ∷ "ik1" ∷ "dikcumul" ∷ "iso1" ∷ []
  ; launches = L.map single sds4Launches
  ; results = (D , NSPEC) ∷ (S , NSPEC) ∷ []
  ; doc = "WAVEWATCH III's ST4 dissipation W3SDS4, case 1, in seven launches" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {sds4Sig} M

  env₀ : Env sds4Sig R
  env₀ = env (I.A ∷ I.K ∷ I.CG ∷ I.SIG ∷ I.ECOS ∷ I.ESIN ∷ I.SATW ∷ I.CUMULW ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ z ∷ [])
             (I.SATI ∷ [])
             (I.dth ∷ I.ssdsbr ∷ I.ssdsc2 ∷ I.ssdsc3 ∷ I.ssdsc5 ∷ I.ssdsc6 ∷ I.ssdsc21 ∷ I.ssdsp ∷ I.ssdsbm0 ∷ I.ssdsbm1
              ∷ I.ssdsbm2 ∷ I.ssdsbm3 ∷ I.ssdsbm4 ∷ I.depth ∷ I.ustar ∷ I.usdir ∷ I.dair ∷ I.grav ∷ I.dwat ∷ I.twopi2 ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ I.nsat ∷ I.ik1 ∷ I.dikcumul ∷ I.iso1 ∷ []) 0
    where z = λ _ → Model.lit M (+ 0 / 1)

  out : Env sds4Sig R
  out = runL (ProgL.launches sds4) env₀

  sds4-D : ∀ is → lookup (Env.farr out) (# 13) is ≡ Routine.D M x is
  sds4-D is = refl

  sds4-S : ∀ is → lookup (Env.farr out) (# 14) is ≡ Routine.S M x is
  sds4-S is = refl
