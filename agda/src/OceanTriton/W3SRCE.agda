{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's source term integration W3SRCE, read from model/src/w3srcemd.F90 of MetOcean's
-- fork at tag 7.14.mos-92e2cf6, commit 92e2cf66, as the C preprocessor leaves it for the switch
-- of ww3_ts1 (ST4 NL1 BT1 DB1 LN1, no ice, no IG, no PDLIB). One pass of the dynamic integration
-- loop (:1207-1986), in two programs, around the W3SPR4 that the loop calls on the new spectrum:
--
-- `srceStep`, after the source terms of the pass:
--
--     :966-968    DAM(1+(IK-1)*NTH) = FACP / ( SIG(IK) * WN1(IK)**3 ), the same for every ITH
--     :1396-1406  NKH = MIN(NK, INT(FACTI2+FACTI1*LOG(MAX(1.E-7,FHIGH)))) ; NKH1 = MIN(NK, NKH+1)
--                 NSPECH = NKH1*NTH ; DT = MIN(DTG-DTTOT, DTMAX) ; AFILT = MAX(DAM(NSPEC), XFLT*AMAX)
--     :1447-1490  DO IS=IS1, NSPECH: VS = VSLN+VSIN+VSNL+VSDS+VSBT ; VD = VDIN+VDNL+VDDS+VDBT
--                 DAMAX = MIN(DAM(IS), MAX(XREL*SPECINIT(IS), AFILT))
--                 AFAC = 1./MAX(1.E-10, ABS(VS(IS)/DAMAX))
--                 DT = MIN(DT, AFAC/(MAX(1.E-10, 1.+OFFSET*AFAC*MIN(0.,VD(IS)))))
--     :1498-1523  DT = MAX(0.5, DT) ; IDT = 1+INT(0.99*(DTG-DTTOT)/DT) ; DT = (DTG-DTTOT)/REAL(IDT)
--                 SHAVE = DT.LT.DTMIN .AND. DT.LT.DTG-DTTOT ; DT = MAX(DT, MIN(DTMIN,DTG-DTTOT))
--                 HDT = OFFSET*DT ; DTTOT = DTTOT+DT
--     :1717-1736  eInc1 = VS*DT/MAX(1., (1.-HDT*VD)) ; with SHAVE, eInc2 = SIGN(MIN(DAM,ABS(eInc1)),
--                 eInc1) ; SPEC = MAX(0., SPEC+eInc) ; then the same with VSDB and VDDB, unshaved
--
-- `srceTail`, after W3SPR4 (:1886-1956):
--
--     FAGE = FFXFA*TANH(0.3*U10ABS*FMEANWS*TPI/GRAV) ; FH1 = (FFXFM+FAGE)*FMEAN1
--     USTAR = MAX(0.001, USTAR) ; FH2 = FFXPM/USTAR ; FHIGH = MIN(SIG(NK), MAX(FH1, FH2))
--     NKH = MAX(2, MIN(NKH1, INT(FACTI2+FACTI1*LOG(MAX(1.E-7,FHIGH)))))
--     DO IK=NKH+1, NK: SPEC(ITH+(IK-1)*NTH) = SPEC(ITH+(IK-2)*NTH)*FACHFA + 0.
--
-- The arithmetic is gfortran -O3's (the GIMPLE of -fdump-tree-optimized at the pin): OFFSET is
-- the parameter 1. (:69), so OFFSET*AFAC is AFAC and HDT is DT; WN1**3 is (WN1*WN1)*WN1; the
-- minimum over IS is a minimum, whose value does not depend on the order the vectoriser takes;
-- the literals are the compiler's floats. SIGN(M, E) with M ≥ 0 is copysignf: here -M when E < 0
-- and M otherwise, which differs only when E is -0. ⚠ that case gives +M here and -M in WW3; a
-- -0 increment needs VS = -0, which no capture has reached. INT of a negative number is 0 here
-- (`trunc`), so FHIGH below the first frequency is outside the transcription ⚠.
--
-- The fluxes of :1771-1799 (PHIAW, PHINL, TAUWIX, ...) do not reach the spectrum and are not here.
-- The loop itself (how many passes, the W3SIN4 after the tail, the exit at DTTOT ≥ 0.9999 DTG)
-- is run by the replay, ww3-replay/replay.py, on the printed kernels.
--
-- `step-DAM`, `step-DTB`, `step-SPEC`, `tail-FT`, `tail-SPEC`: the launches give the routine's
-- values, by refl, in every model.
module OceanTriton.W3SRCE where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc; _∸_; _<ᵇ_; _⊓_; _⊔_)
open import Data.Integer using (+_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription of the step

record StepInputs (R : Set) : Set where
  field
    A SPECINIT VSLN VSIN VDIN VSNL VDNL VSDS VDDS VSBT VDBT VSDB VDDB WN SIG : ℕ → R
    dtg dttot dtmax xflt amax xrel dtmin fhigh facti1 facti2 facp : R
    nth nk nspec : ℕ

module Step {R : Set} (M : Model R) (x : StepInputs R) where
  open Model M
  open StepInputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  z one : R
  z = ℓ (+ 0 / 1) ; one = ℓ (+ 1 / 1)

  ikOf : ℕ → ℕ
  ikOf is = idiv is nth

  DAM : ℕ → R
  DAM is = facp ÷ (SIG (ikOf is) * (WN (ikOf is) * WN (ikOf is) * WN (ikOf is)))

  nspech : ℕ
  nspech = (nk ⊓ ((nk ⊓ trunc (facti2 + facti1 * fun flog (op max (ℓ (+ 1 / 10000000)) fhigh))) ℕ.+ 1)) ℕ.* nth

  VS VD : ℕ → R
  VS is = VSLN is + VSIN is + VSNL is + VSDS is + VSBT is
  VD is = VDIN is + VDNL is + VDDS is + VDBT is

  afilt : R
  afilt = op max (DAM (nspec ∸ 1)) (xflt * amax)

  afac : ℕ → R
  afac is = one ÷ op max (ℓ (+ 1 / 10000000000)) (fun fabs (VS is ÷ op min (DAM is) (op max (xrel * SPECINIT is) afilt)))

  dt0 dtA rem dtB dtC shave dttot′ : R
  dt0 = foldN nspech (op min (dtg - dttot) dtmax)
          (λ is r → op min r (afac is ÷ op max (ℓ (+ 1 / 10000000000)) (one + afac is * op min z (VD is))))
  dtA = op max dt0 (ℓ (+ 1 / 2))
  rem = dtg - dttot
  dtB = rem ÷ fromℕ (trunc (rem * ℓ (+ 99 / 100) ÷ dtA) ℕ.+ 1)
  dtC = op max dtB (op min dtmin rem)
  shave = if cmp lt dtB dtmin then (if cmp lt dtB rem then one else z) else z
  dttot′ = dttot + dtC

  -- DT, SHAVE (1 or 0), the new DTTOT, and the DT that DTDYN sums.
  DTB : ℕ → R
  DTB i = if i <ᵇ 1 then dtC else (if i <ᵇ 2 then shave else (if i <ᵇ 3 then dttot′ else dtA))

  sgn : R → R → R
  sgn m e = if cmp lt e z then fun fneg m else m

  inc : R → R → R
  inc s d = dtC * s ÷ op max (one - dtC * d) one

  SPEC : ℕ → R
  SPEC is = if is <ᵇ nspech
            then (let e1 = inc (VS is) (VD is)
                      s1 = if cmp ne shave z then op max (A is + sgn (op min (fun fabs e1) (DAM is)) e1) z
                           else op max (A is + e1) z
                  in op max (s1 + inc (VSDB is) (VDDB is)) z)
            else A is

-- ---------------------------------------------------------------------------------------------
-- The transcription of the tail

record TailInputs (R : Set) : Set where
  field
    A SIG : ℕ → R
    u10 fmeanws fmean1 ustar ffxfa ffxfm ffxpm facti1 facti2 fachfa tpi grav fhigh₀ : R
    nth nk nspec : ℕ

module Tail {R : Set} (M : Model R) (x : TailInputs R) where
  open Model M
  open TailInputs x

  infixl 6 _+_
  infixl 7 _*_ _÷_
  _+_ _*_ _÷_ : R → R → R
  _+_ = op add ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit

  index : R → ℕ
  index f = trunc (facti2 + facti1 * fun flog (op max (ℓ (+ 1 / 10000000)) f))

  fhigh : R
  fhigh = op min (op max ((ffxfm + ffxfa * fun ftanh (u10 * ℓ (+ 3 / 10) * fmeanws * tpi ÷ grav)) * fmean1)
                         (ffxpm ÷ op max ustar (ℓ (+ 1 / 1000))))
                 (SIG (nk ∸ 1))

  nkh1 nkh : ℕ
  nkh1 = nk ⊓ ((nk ⊓ index fhigh₀) ℕ.+ 1)
  nkh  = 2 ⊔ (nkh1 ⊓ index fhigh)

  FT : ℕ → R
  FT i = if i <ᵇ 1 then fhigh else fromℕ nkh

  SPEC : ℕ → R
  SPEC is = if idiv is nth <ᵇ nkh then A is
            else foldN (idiv is nth ∸ (nkh ∸ 1)) (A (imod is nth ℕ.+ (nkh ∸ 1) ℕ.* nth))
                   (λ _ r → r * fachfa + ℓ (+ 0 / 1))

-- ---------------------------------------------------------------------------------------------
-- The programs

stepSig : Sig
stepSig = record { nf = 18 ; ni = 0 ; nfp = 11 ; nip = 4 }

module StepProgram where
  open Syntax stepSig public

  A SPECINIT VSLN VSIN VDIN VSNL VDNL VSDS VDDS VSBT VDBT VSDB VDDB WN SIG DAMB DTBB SPECB : Fin 18
  A = # 0 ; SPECINIT = # 1 ; VSLN = # 2 ; VSIN = # 3 ; VDIN = # 4 ; VSNL = # 5 ; VDNL = # 6
  VSDS = # 7 ; VDDS = # 8 ; VSBT = # 9 ; VDBT = # 10 ; VSDB = # 11 ; VDDB = # 12 ; WN = # 13
  SIG = # 14 ; DAMB = # 15 ; DTBB = # 16 ; SPECB = # 17

  private
    dtg dttot dtmax xflt amax xrel dtmin fhigh facti1 facti2 facp : ∀ {v a} → FE v a
    dtg = fpar (# 0) ; dttot = fpar (# 1) ; dtmax = fpar (# 2) ; xflt = fpar (# 3) ; amax = fpar (# 4)
    xrel = fpar (# 5) ; dtmin = fpar (# 6) ; fhigh = fpar (# 7) ; facti1 = fpar (# 8) ; facti2 = fpar (# 9)
    facp = fpar (# 10)

  NTH NK NSPEC N4 : Fin 4
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; N4 = # 3

  private
    nth nk nspec : ∀ {v} → IE v
    nth = ipar NTH ; nk = ipar NK ; nspec = ipar NSPEC

    infixl 6 _⊕_ _⊖_
    infixl 7 _⊗_ _⊘_
    _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
    _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

    c : ∀ {v a} → ℚ → FE v a
    c = lit

    zf one e10 : ∀ {v a} → FE v a
    zf = c (+ 0 / 1) ; one = c (+ 1 / 1) ; e10 = c (+ 1 / 10000000000)

    -- INT(FACTI2+FACTI1*LOG(MAX(1.E-7,FHIGH))), then NSPECH from it (var 0).
    nkhF : ∀ {v a} → FE v a
    nkhF = facti2 ⊕ facti1 ⊗ fn flog (op max (c (+ 1 / 10000000)) fhigh)
    nspechI : ∀ {v} → IE (suc v)
    nspechI = minᵢ nk (minᵢ nk (var (# 0)) +ᵢ nat 1) *ᵢ nth

    ikI : ∀ {v} → IE v → IE v
    ikI i = quot i nth

    damE : ∀ {v a} → IE v → FE v a
    damE i = facp ⊘ (ld SIG (ikI i) ⊗ (ld WN (ikI i) ⊗ ld WN (ikI i) ⊗ ld WN (ikI i)))

    vsE vdE : ∀ {v a} → IE v → FE v a
    vsE i = ld VSLN i ⊕ ld VSIN i ⊕ ld VSNL i ⊕ ld VSDS i ⊕ ld VSBT i
    vdE i = ld VDIN i ⊕ ld VDNL i ⊕ ld VDDS i ⊕ ld VDBT i

    afilt : ∀ {v a} → FE v a
    afilt = op max (ld DAMB (nspec ∸ᵢ nat 1)) (xflt ⊗ amax)

    afacE : ∀ {v a} → IE v → FE v a
    afacE i = one ⊘ op max e10 (fn fabs (vsE i ⊘ op min (ld DAMB i) (op max (xrel ⊗ ld SPECINIT i) afilt)))

    -- The pass's DT before :1498 (var 0 of the fold is IS, var 1 is INT of NKH's expression).
    dt0 : ∀ {a} → FE 0 a
    dt0 = ix nkhF (fold NSPEC nspechI (op min (dtg ⊖ dttot) dtmax)
            (bind (afacE (var (# 0)))
              (op min (acc (# 1)) (acc (# 0) ⊘ op max e10 (one ⊕ acc (# 0) ⊗ op min zf (vdE (var (# 0))))))))

  damB : FE 0 0
  damB = damE lane

  -- With acc 0 = DT after :1498 and rem = DTG-DTTOT.
  private
    dtAt : ∀ {a} → FE 0 (suc a) → FE 0 a
    dtAt = bind (op max dt0 (c (+ 1 / 2)))
    dtBE : ∀ {a} → FE 0 (suc a)
    dtBE = ix ((dtg ⊖ dttot) ⊗ c (+ 99 / 100) ⊘ acc (# 0)) ((dtg ⊖ dttot) ⊘ real (var (# 0) +ᵢ nat 1))

  dtbB : FE 0 0
  dtbB = isel lane (nat 1) (dtAt (bind dtBE (op max (acc (# 0)) (op min dtmin (dtg ⊖ dttot)))))
         (isel lane (nat 2) (dtAt (bind dtBE (sel lt (acc (# 0)) dtmin (sel lt (acc (# 0)) (dtg ⊖ dttot) one zf) zf)))
         (isel lane (nat 3) (dtAt (bind dtBE (dttot ⊕ op max (acc (# 0)) (op min dtmin (dtg ⊖ dttot)))))
         (op max dt0 (c (+ 1 / 2)))))

  private
    dtR shR : ∀ {v a} → FE v a
    dtR = ld DTBB (nat 0) ; shR = ld DTBB (nat 1)

    incE : ∀ {v a} → FE v a → FE v a → FE v a
    incE s d = dtR ⊗ s ⊘ op max (one ⊖ dtR ⊗ d) one

    sgnE : ∀ {v a} → FE v a → FE v a → FE v a
    sgnE m e = sel lt e zf (fn fneg m) m

  specB : FE 0 0
  specB = ix nkhF (isel lane nspechI
            (bind (incE (vsE lane) (vdE lane))
              (op max (sel ne shR zf (op max (ld A lane ⊕ sgnE (op min (fn fabs (acc (# 0))) (ld DAMB lane)) (acc (# 0))) zf)
                                       (op max (ld A lane ⊕ acc (# 0)) zf)
                       ⊕ incE (ld VSDB lane) (ld VDDB lane)) zf))
            (ld A lane))

  LDAM LDTB LSPEC : Launch
  LDAM  = launch "w3srce_dam"  damB  NSPEC DAMB  "DAM, the largest change (w3srcemd.F90:966-968)"
  LDTB  = launch "w3srce_dt"   dtbB  N4    DTBB  "DT, SHAVE, DTTOT and the DT of DTDYN (w3srcemd.F90:1396-1523)"
  LSPEC = launch "w3srce_spec" specB NSPEC SPECB "SPEC after the pass, limiter and breaking included (w3srcemd.F90:1717-1736)"

srceStep : StepProgram.ProgL
srceStep = record
  { name = "w3srce_step"
  ; farrays = "A" ∷ "SPECINIT" ∷ "VSLN" ∷ "VSIN" ∷ "VDIN" ∷ "VSNL" ∷ "VDNL" ∷ "VSDS" ∷ "VDDS" ∷ "VSBT"
              ∷ "VDBT" ∷ "VSDB" ∷ "VDDB" ∷ "WN" ∷ "SIG" ∷ "DAM" ∷ "DTB" ∷ "SPEC" ∷ []
  ; iarrays = []
  ; fparams = "dtg" ∷ "dttot" ∷ "dtmax" ∷ "xflt" ∷ "amax" ∷ "xrel" ∷ "dtmin" ∷ "fhigh" ∷ "facti1" ∷ "facti2" ∷ "facp" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "n4" ∷ []
  ; launches = L.map single (LDAM ∷ LDTB ∷ LSPEC ∷ [])
  ; results = (DAMB , NSPEC) ∷ (DTBB , N4) ∷ (SPECB , NSPEC) ∷ []
  ; doc = "One pass of W3SRCE's dynamic integration, after the source terms, in three launches" }
  where open StepProgram

tailSig : Sig
tailSig = record { nf = 4 ; ni = 0 ; nfp = 13 ; nip = 4 }

module TailProgram where
  open Syntax tailSig public

  A SIG FTB SPECB : Fin 4
  A = # 0 ; SIG = # 1 ; FTB = # 2 ; SPECB = # 3

  private
    u10 fmeanws fmean1 ustar ffxfa ffxfm ffxpm facti1 facti2 fachfa tpi grav fhigh₀ : ∀ {v a} → FE v a
    u10 = fpar (# 0) ; fmeanws = fpar (# 1) ; fmean1 = fpar (# 2) ; ustar = fpar (# 3) ; ffxfa = fpar (# 4)
    ffxfm = fpar (# 5) ; ffxpm = fpar (# 6) ; facti1 = fpar (# 7) ; facti2 = fpar (# 8) ; fachfa = fpar (# 9)
    tpi = fpar (# 10) ; grav = fpar (# 11) ; fhigh₀ = fpar (# 12)

  NTH NK NSPEC N2 : Fin 4
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; N2 = # 3

  private
    nth nk : ∀ {v} → IE v
    nth = ipar NTH ; nk = ipar NK

    infixl 6 _⊕_
    infixl 7 _⊗_ _⊘_
    _⊕_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
    _⊕_ = op add ; _⊗_ = op mul ; _⊘_ = op div

    c : ∀ {v a} → ℚ → FE v a
    c = lit

    indexF : ∀ {v a} → FE v a → FE v a
    indexF f = facti2 ⊕ facti1 ⊗ fn flog (op max (c (+ 1 / 10000000)) f)

    fhighE : ∀ {v a} → FE v a
    fhighE = op min (op max ((ffxfm ⊕ ffxfa ⊗ fn ftanh (u10 ⊗ c (+ 3 / 10) ⊗ fmeanws ⊗ tpi ⊘ grav)) ⊗ fmean1)
                            (ffxpm ⊘ op max ustar (c (+ 1 / 1000))))
                    (ld SIG (nk ∸ᵢ nat 1))

    -- NKH with var 1 = INT of FHIGH₀'s expression and var 0 = INT of FHIGH's.
    nkhI : ∀ {v} → IE (suc (suc v))
    nkhI = maxᵢ (nat 2) (minᵢ (minᵢ nk (minᵢ nk (var (# 1)) +ᵢ nat 1)) (var (# 0)))

    withNkh : ∀ {a} → FE 2 a → FE 0 a
    withNkh body = ix (indexF fhigh₀) (ix (indexF fhighE) body)

  ftB : FE 0 0
  ftB = isel lane (nat 1) fhighE (withNkh (real nkhI))

  specB : FE 0 0
  specB = withNkh (isel (quot lane nth) nkhI (ld A lane)
            (fold NK (quot lane nth ∸ᵢ (nkhI ∸ᵢ nat 1)) (ld A (rem lane nth +ᵢ (nkhI ∸ᵢ nat 1) *ᵢ nth))
              (acc (# 0) ⊗ fachfa ⊕ c (+ 0 / 1))))

  LFT LTSPEC : Launch
  LFT    = launch "w3srce_fhigh" ftB  N2    FTB   "FHIGH and NKH after the pass (w3srcemd.F90:1886-1896)"
  LTSPEC = launch "w3srce_tail"  specB NSPEC SPECB "SPEC with the tail FACHFA above NKH (w3srcemd.F90:1946-1956)"

srceTail : TailProgram.ProgL
srceTail = record
  { name = "w3srce_tail"
  ; farrays = "A" ∷ "SIG" ∷ "FT" ∷ "SPEC" ∷ []
  ; iarrays = []
  ; fparams = "u10" ∷ "fmeanws" ∷ "fmean1" ∷ "ustar" ∷ "ffxfa" ∷ "ffxfm" ∷ "ffxpm" ∷ "facti1" ∷ "facti2"
              ∷ "fachfa" ∷ "tpi" ∷ "grav" ∷ "fhigh0" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "n2" ∷ []
  ; launches = L.map single (LFT ∷ LTSPEC ∷ [])
  ; results = (FTB , N2) ∷ (SPECB , NSPEC) ∷ []
  ; doc = "The tail of a pass of W3SRCE after W3SPR4: FHIGH, NKH and the spectrum above NKH" }
  where open TailProgram

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : StepInputs R) where
  module I = StepInputs x
  open Eval {stepSig} M

  env₀ : Env stepSig R
  env₀ = env (I.A ∷ I.SPECINIT ∷ I.VSLN ∷ I.VSIN ∷ I.VDIN ∷ I.VSNL ∷ I.VDNL ∷ I.VSDS ∷ I.VDDS ∷ I.VSBT
              ∷ I.VDBT ∷ I.VSDB ∷ I.VDDB ∷ I.WN ∷ I.SIG ∷ z₀ ∷ z₀ ∷ z₀ ∷ [])
             []
             (I.dtg ∷ I.dttot ∷ I.dtmax ∷ I.xflt ∷ I.amax ∷ I.xrel ∷ I.dtmin ∷ I.fhigh ∷ I.facti1 ∷ I.facti2 ∷ I.facp ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ 4 ∷ []) 0
    where z₀ = λ _ → Model.lit M (+ 0 / 1)

  out : Env stepSig R
  out = runL (StepProgram.ProgL.launches srceStep) env₀

  step-DAM : ∀ is → lookup (Env.farr out) (# 15) is ≡ Step.DAM M x is
  step-DAM is = refl

  step-DTB : ∀ i → lookup (Env.farr out) (# 16) i ≡ Step.DTB M x i
  step-DTB i = refl

  step-SPEC : ∀ is → lookup (Env.farr out) (# 17) is ≡ Step.SPEC M x is
  step-SPEC is = refl

module _ {R : Set} (M : Model R) (x : TailInputs R) where
  module J = TailInputs x
  open Eval {tailSig} M

  tenv₀ : Env tailSig R
  tenv₀ = env (J.A ∷ J.SIG ∷ z₀ ∷ z₀ ∷ [])
              []
              (J.u10 ∷ J.fmeanws ∷ J.fmean1 ∷ J.ustar ∷ J.ffxfa ∷ J.ffxfm ∷ J.ffxpm ∷ J.facti1 ∷ J.facti2
               ∷ J.fachfa ∷ J.tpi ∷ J.grav ∷ J.fhigh₀ ∷ [])
              (J.nth ∷ J.nk ∷ J.nspec ∷ 2 ∷ []) 0
    where z₀ = λ _ → Model.lit M (+ 0 / 1)

  tout : Env tailSig R
  tout = runL (TailProgram.ProgL.launches srceTail) tenv₀

  tail-FT : ∀ i → lookup (Env.farr tout) (# 2) i ≡ Tail.FT M x i
  tail-FT i = refl

  tail-SPEC : ∀ is → lookup (Env.farr tout) (# 3) is ≡ Tail.SPEC M x is
  tail-SPEC is = refl
