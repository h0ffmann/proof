{-# OPTIONS --safe --without-K #-}

-- The fluxes of WAVEWATCH III's source term integration W3SRCE, read from model/src/w3srcemd.F90
-- of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66, for the switch of ww3_ts1 (no ice,
-- srce_direct, OFFSET = 1). Two programs:
--
-- `srcePass`, at the end of each pass of the integration loop, after the new spectrum:
--
--     :1771       WHITECAP(3) = 0.
--     :1780-1792  DO IK: FACTOR = DDEN(IK)/CG1(IK)
--                   DO ITH: PHIAW = PHIAW + (VSIN(IS))*DT*FACTOR / MAX(1., (1.-HDT*VDIN(IS)))
--                           PHIBBL = PHIBBL - (VSBT(IS))*DT*FACTOR / MAX(1., (1.-HDT*VDBT(IS)))
--                           IF (VSIN(IS).GT.0.) WHITECAP(3) = WHITECAP(3) + SPEC(IS)*FACTOR
--     :1794       WHITECAP(3) = 4.*SQRT(WHITECAP(3))
--     :1796-1799  TAUWIX = TAUWIX + TAUWX*DRAT*DT, and so TAUWIY, TAUWNX (TAUWAX), TAUWNY (TAUWAY)
--
-- `srceEnd`, after the loop:
--
--     :1999-2000  DTDYN = DTDYN/REAL(MAX(1,NSTEPS)) ; FCUT = FHIGH*TPIINV
--     :2034-2050  DO IK: EBAND, A1BAND, B1BAND = the sums over ITH of DIFF = SPECINIT-SPEC, DIFF ECOS(ITH),
--                 DIFF ESIN(ITH) ; EFINISH += EBAND*DDEN(IK)/CG1(IK) ;
--                 MWXFINISH += A1BAND*DDEN(IK)/CG1(IK)*WN1(IK)/SIG(IK), and MWYFINISH with B1BAND
--     :2052-2067  TAUOX = (GRAV*MWXFINISH+TAUWIX-TAUBBL(1))/DTG, TAUOY the same in y ;
--                 TAUWIX, TAUWIY, TAUWNX, TAUWNY, TAUBBL divided by DTG ;
--                 TAUOCX = DAIR*COEF*COEF*USTAR*USTAR*COS(USTDIR) + DWAT*(TAUOX-TAUWIX), TAUOCY with SIN ;
--                 PHIOC = DWAT*GRAV*(EFINISH+PHIAW-PHIBBL)/DTG ; PHIAW, PHIBBL times DWAT*GRAV/DTG
--
-- The arithmetic is gfortran -O3's (-fdump-tree-optimized at the pin). PHINL and HSTOT are
-- computed by the source and removed by the compiler, since nothing reads them; DRAT is
-- DAIR/1000.; DWAT*GRAV is the float 9806 and DWAT is 1000; COS and SIN of USTDIR are one
-- sincosf; every sum is in the Fortran's order, IK outer and ITH inner, from the value the pass
-- starts with. Products of two floats are commutative in IEEE arithmetic, so TAUWX*DRAT and
-- DRAT*TAUWX, which the compiler writes, are the same bits.
--
-- `pass-FX`, `end-FX`: the launches give the routine's values, by refl, in every model.
module OceanTriton.W3SRCEFlux where

open import Data.Bool using (if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc; _<ᵇ_; _⊔_)
open import Data.Integer using (+_)
open import Data.Product using (_,_)
open import Data.Rational using (ℚ; _/_)
open import Data.Vec using (Vec; []; _∷_; lookup)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import OceanTriton.Lanes

-- ---------------------------------------------------------------------------------------------
-- The transcription

record PassInputs (R : Set) : Set where
  field
    SPEC VSIN VDIN VSBT VDBT DDEN CG : ℕ → R
    dt phiaw phibbl tauwix tauwiy tauwnx tauwny tauwx tauwy tauwax tauway dair : R
    nth nk nspec : ℕ

module Pass {R : Set} (M : Model R) (x : PassInputs R) where
  open Model M
  open PassInputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  one : R
  one = ℓ (+ 1 / 1)

  factor : ℕ → R
  factor is = DDEN (idiv is nth) ÷ CG (idiv is nth)

  semi : (ℕ → R) → (ℕ → R) → ℕ → R
  semi S D is = S is * dt * factor is ÷ op max (one - D is * dt) one

  drat : R
  drat = dair ÷ ℓ (+ 1000 / 1)

  FX : ℕ → R
  FX i = if i <ᵇ 1 then foldN nspec phiaw (λ is r → r + semi VSIN VDIN is)
    else if i <ᵇ 2 then foldN nspec phibbl (λ is r → r - semi VSBT VDBT is)
    else if i <ᵇ 3 then fun fsqrt (foldN nspec (ℓ (+ 0 / 1))
                          (λ is r → if cmp lt (ℓ (+ 0 / 1)) (VSIN is) then r + SPEC is * factor is else r))
                        * ℓ (+ 4 / 1)
    else if i <ᵇ 4 then tauwix + drat * tauwx * dt
    else if i <ᵇ 5 then tauwiy + drat * tauwy * dt
    else if i <ᵇ 6 then tauwnx + drat * tauwax * dt
    else tauwny + drat * tauway * dt

record EndInputs (R : Set) : Set where
  field
    SPECINIT SPEC ECOS ESIN DDEN CG WN SIG : ℕ → R
    dtg tauwix tauwiy tauwnx tauwny taubbl1 taubbl2 phiaw phibbl dair coef ustar ustdir dtdyn fhigh tpiinv : R
    nth nk nspec nsteps : ℕ

module End {R : Set} (M : Model R) (x : EndInputs R) where
  open Model M
  open EndInputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  z : R
  z = ℓ (+ 0 / 1)

  diff : ℕ → ℕ → R
  diff ik ith = SPECINIT (ith ℕ.+ ik ℕ.* nth) - SPEC (ith ℕ.+ ik ℕ.* nth)

  band : (ℕ → R) → ℕ → R
  band w ik = foldN nth z (λ ith r → r + w ith * diff ik ith)

  eband : ℕ → R
  eband ik = foldN nth z (λ ith r → r + diff ik ith)

  efinish mwx mwy : R
  efinish = foldN nk z (λ ik r → r + DDEN ik * eband ik ÷ CG ik)
  mwx = foldN nk z (λ ik r → r + DDEN ik * band ECOS ik ÷ CG ik * WN ik ÷ SIG ik)
  mwy = foldN nk z (λ ik r → r + DDEN ik * band ESIN ik ÷ CG ik * WN ik ÷ SIG ik)

  tauox tauoy tw : R
  tauox = (tauwix + mwx * ℓ (+ 4903 / 500) - taubbl1) ÷ dtg
  tauoy = (tauwiy + mwy * ℓ (+ 4903 / 500) - taubbl2) ÷ dtg
  tw = dair * coef * coef * ustar * ustar

  -- TAUOX TAUOY TAUWIX TAUWIY TAUWNX TAUWNY TAUBBL(1) TAUBBL(2) TAUOCX TAUOCY PHIOC PHIAW PHIBBL DTDYN FCUT
  FX : ℕ → R
  FX i = if i <ᵇ 1 then tauox
    else if i <ᵇ 2 then tauoy
    else if i <ᵇ 3 then tauwix ÷ dtg
    else if i <ᵇ 4 then tauwiy ÷ dtg
    else if i <ᵇ 5 then tauwnx ÷ dtg
    else if i <ᵇ 6 then tauwny ÷ dtg
    else if i <ᵇ 7 then taubbl1 ÷ dtg
    else if i <ᵇ 8 then taubbl2 ÷ dtg
    else if i <ᵇ 9 then tw * fun fcos ustdir + (tauox - tauwix ÷ dtg) * ℓ (+ 1000 / 1)
    else if i <ᵇ 10 then tw * fun fsin ustdir + (tauoy - tauwiy ÷ dtg) * ℓ (+ 1000 / 1)
    else if i <ᵇ 11 then (phiaw + efinish - phibbl) * ℓ (+ 9806 / 1) ÷ dtg
    else if i <ᵇ 12 then phiaw * ℓ (+ 9806 / 1) ÷ dtg
    else if i <ᵇ 13 then phibbl * ℓ (+ 9806 / 1) ÷ dtg
    else if i <ᵇ 14 then dtdyn ÷ fromℕ (1 ⊔ nsteps)
    else fhigh * tpiinv

-- ---------------------------------------------------------------------------------------------
-- The programs

passSig : Sig
passSig = record { nf = 8 ; ni = 0 ; nfp = 12 ; nip = 4 }

module PassProgram where
  open Syntax passSig public

  SPEC VSIN VDIN VSBT VDBT DDEN CG FXB : Fin 8
  SPEC = # 0 ; VSIN = # 1 ; VDIN = # 2 ; VSBT = # 3 ; VDBT = # 4 ; DDEN = # 5 ; CG = # 6 ; FXB = # 7

  NTH NK NSPEC N7 : Fin 4
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; N7 = # 3

  private
    dt phiaw phibbl tauwix tauwiy tauwnx tauwny tauwx tauwy tauwax tauway dair : ∀ {v a} → FE v a
    dt = fpar (# 0) ; phiaw = fpar (# 1) ; phibbl = fpar (# 2) ; tauwix = fpar (# 3) ; tauwiy = fpar (# 4)
    tauwnx = fpar (# 5) ; tauwny = fpar (# 6) ; tauwx = fpar (# 7) ; tauwy = fpar (# 8) ; tauwax = fpar (# 9)
    tauway = fpar (# 10) ; dair = fpar (# 11)

    nth nspec : ∀ {v} → IE v
    nth = ipar NTH ; nspec = ipar NSPEC

    infixl 6 _⊕_ _⊖_
    infixl 7 _⊗_ _⊘_
    _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
    _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

    c : ∀ {v a} → ℚ → FE v a
    c = lit

    is : ∀ {v} → IE (suc v)
    is = var (# 0)

    factor : FE 1 1
    factor = ld DDEN (quot is nth) ⊘ ld CG (quot is nth)

    semi : Fin 8 → Fin 8 → FE 1 1
    semi S D = ld S is ⊗ dt ⊗ factor ⊘ op max (c (+ 1 / 1) ⊖ ld D is ⊗ dt) (c (+ 1 / 1))

    drat : ∀ {v a} → FE v a
    drat = dair ⊘ c (+ 1000 / 1)

  fxB : FE 0 0
  fxB = isel lane (nat 1) (fold NSPEC nspec phiaw (acc (# 0) ⊕ semi VSIN VDIN))
       (isel lane (nat 2) (fold NSPEC nspec phibbl (acc (# 0) ⊖ semi VSBT VDBT))
       (isel lane (nat 3) (fn fsqrt (fold NSPEC nspec (c (+ 0 / 1))
                             (sel lt (c (+ 0 / 1)) (ld VSIN is) (acc (# 0) ⊕ ld SPEC is ⊗ factor) (acc (# 0))))
                           ⊗ c (+ 4 / 1))
       (isel lane (nat 4) (tauwix ⊕ drat ⊗ tauwx ⊗ dt)
       (isel lane (nat 5) (tauwiy ⊕ drat ⊗ tauwy ⊗ dt)
       (isel lane (nat 6) (tauwnx ⊕ drat ⊗ tauwax ⊗ dt)
       (tauwny ⊕ drat ⊗ tauway ⊗ dt))))))

  LPASS : Launch
  LPASS = launch "w3srce_pass" fxB N7 FXB
    "PHIAW PHIBBL WHITECAP(3) TAUWIX TAUWIY TAUWNX TAUWNY after a pass (w3srcemd.F90:1771-1799)"

srcePass : PassProgram.ProgL
srcePass = record
  { name = "w3srce_pass"
  ; farrays = "SPEC" ∷ "VSIN" ∷ "VDIN" ∷ "VSBT" ∷ "VDBT" ∷ "DDEN" ∷ "CG" ∷ "FX" ∷ []
  ; iarrays = []
  ; fparams = "dt" ∷ "phiaw" ∷ "phibbl" ∷ "tauwix" ∷ "tauwiy" ∷ "tauwnx" ∷ "tauwny" ∷ "tauwx" ∷ "tauwy"
              ∷ "tauwax" ∷ "tauway" ∷ "dair" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "n7" ∷ []
  ; launches = single LPASS ∷ []
  ; results = (FXB , N7) ∷ []
  ; doc = "The fluxes W3SRCE sums at the end of a pass of its integration loop" }
  where open PassProgram

endSig : Sig
endSig = record { nf = 9 ; ni = 0 ; nfp = 16 ; nip = 5 }

module EndProgram where
  open Syntax endSig public

  SPECINIT SPEC ECOS ESIN DDEN CG WN SIG FXB : Fin 9
  SPECINIT = # 0 ; SPEC = # 1 ; ECOS = # 2 ; ESIN = # 3 ; DDEN = # 4 ; CG = # 5 ; WN = # 6 ; SIG = # 7
  FXB = # 8

  NTH NK NSPEC NSTEPS N15 : Fin 5
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; NSTEPS = # 3 ; N15 = # 4

  private
    dtg tauwix tauwiy tauwnx tauwny taubbl1 taubbl2 phiaw phibbl dair coef ustar ustdir dtdyn fhigh tpiinv
      : ∀ {v a} → FE v a
    dtg = fpar (# 0) ; tauwix = fpar (# 1) ; tauwiy = fpar (# 2) ; tauwnx = fpar (# 3) ; tauwny = fpar (# 4)
    taubbl1 = fpar (# 5) ; taubbl2 = fpar (# 6) ; phiaw = fpar (# 7) ; phibbl = fpar (# 8) ; dair = fpar (# 9)
    coef = fpar (# 10) ; ustar = fpar (# 11) ; ustdir = fpar (# 12) ; dtdyn = fpar (# 13) ; fhigh = fpar (# 14)
    tpiinv = fpar (# 15)

    nth nk : ∀ {v} → IE v
    nth = ipar NTH ; nk = ipar NK

    infixl 6 _⊕_ _⊖_
    infixl 7 _⊗_ _⊘_
    _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
    _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

    c : ∀ {v a} → ℚ → FE v a
    c = lit

    -- Inside the IK loop (var 0) and the ITH loop (var 0, IK var 1).
    ik : IE 1
    ik = var (# 0)

    diff : FE 2 2
    diff = ld SPECINIT (var (# 0) +ᵢ var (# 1) *ᵢ nth) ⊖ ld SPEC (var (# 0) +ᵢ var (# 1) *ᵢ nth)

    eband : FE 1 1
    eband = fold NTH nth (c (+ 0 / 1)) (acc (# 0) ⊕ diff)

    band : Fin 9 → FE 1 1
    band w = fold NTH nth (c (+ 0 / 1)) (acc (# 0) ⊕ ld w (var (# 0)) ⊗ diff)

    efinish mwx mwy : FE 0 0
    efinish = fold NK nk (c (+ 0 / 1)) (acc (# 0) ⊕ ld DDEN ik ⊗ eband ⊘ ld CG ik)
    mwx = fold NK nk (c (+ 0 / 1)) (acc (# 0) ⊕ ld DDEN ik ⊗ band ECOS ⊘ ld CG ik ⊗ ld WN ik ⊘ ld SIG ik)
    mwy = fold NK nk (c (+ 0 / 1)) (acc (# 0) ⊕ ld DDEN ik ⊗ band ESIN ⊘ ld CG ik ⊗ ld WN ik ⊘ ld SIG ik)

    tauox tauoy tw : FE 0 0
    tauox = (tauwix ⊕ mwx ⊗ c (+ 4903 / 500) ⊖ taubbl1) ⊘ dtg
    tauoy = (tauwiy ⊕ mwy ⊗ c (+ 4903 / 500) ⊖ taubbl2) ⊘ dtg
    tw = dair ⊗ coef ⊗ coef ⊗ ustar ⊗ ustar

  fxB : FE 0 0
  fxB = isel lane (nat 1) tauox
       (isel lane (nat 2) tauoy
       (isel lane (nat 3) (tauwix ⊘ dtg)
       (isel lane (nat 4) (tauwiy ⊘ dtg)
       (isel lane (nat 5) (tauwnx ⊘ dtg)
       (isel lane (nat 6) (tauwny ⊘ dtg)
       (isel lane (nat 7) (taubbl1 ⊘ dtg)
       (isel lane (nat 8) (taubbl2 ⊘ dtg)
       (isel lane (nat 9) (tw ⊗ fn fcos ustdir ⊕ (tauox ⊖ tauwix ⊘ dtg) ⊗ c (+ 1000 / 1))
       (isel lane (nat 10) (tw ⊗ fn fsin ustdir ⊕ (tauoy ⊖ tauwiy ⊘ dtg) ⊗ c (+ 1000 / 1))
       (isel lane (nat 11) ((phiaw ⊕ efinish ⊖ phibbl) ⊗ c (+ 9806 / 1) ⊘ dtg)
       (isel lane (nat 12) (phiaw ⊗ c (+ 9806 / 1) ⊘ dtg)
       (isel lane (nat 13) (phibbl ⊗ c (+ 9806 / 1) ⊘ dtg)
       (isel lane (nat 14) (dtdyn ⊘ real (maxᵢ (nat 1) (ipar NSTEPS)))
       (fhigh ⊗ tpiinv))))))))))))))

  LEND : Launch
  LEND = launch "w3srce_end" fxB N15 FXB
    "TAUOX TAUOY TAUWIX TAUWIY TAUWNX TAUWNY TAUBBL TAUOCX TAUOCY PHIOC PHIAW PHIBBL DTDYN FCUT (w3srcemd.F90:1999-2067)"

srceEnd : EndProgram.ProgL
srceEnd = record
  { name = "w3srce_end"
  ; farrays = "SPECINIT" ∷ "SPEC" ∷ "ECOS" ∷ "ESIN" ∷ "DDEN" ∷ "CG" ∷ "WN" ∷ "SIG" ∷ "FX" ∷ []
  ; iarrays = []
  ; fparams = "dtg" ∷ "tauwix" ∷ "tauwiy" ∷ "tauwnx" ∷ "tauwny" ∷ "taubbl1" ∷ "taubbl2" ∷ "phiaw" ∷ "phibbl"
              ∷ "dair" ∷ "coef" ∷ "ustar" ∷ "ustdir" ∷ "dtdyn" ∷ "fhigh" ∷ "tpiinv" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "nsteps" ∷ "n15" ∷ []
  ; launches = single LEND ∷ []
  ; results = (FXB , N15) ∷ []
  ; doc = "The fluxes and means W3SRCE returns after its integration loop" }
  where open EndProgram

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : PassInputs R) where
  module I = PassInputs x
  open Eval {passSig} M

  penv₀ : Env passSig R
  penv₀ = env (I.SPEC ∷ I.VSIN ∷ I.VDIN ∷ I.VSBT ∷ I.VDBT ∷ I.DDEN ∷ I.CG ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ [])
              []
              (I.dt ∷ I.phiaw ∷ I.phibbl ∷ I.tauwix ∷ I.tauwiy ∷ I.tauwnx ∷ I.tauwny ∷ I.tauwx ∷ I.tauwy
               ∷ I.tauwax ∷ I.tauway ∷ I.dair ∷ [])
              (I.nth ∷ I.nk ∷ I.nspec ∷ 7 ∷ []) 0

  pout : Env passSig R
  pout = runL (PassProgram.ProgL.launches srcePass) penv₀

  pass-FX : ∀ i → lookup (Env.farr pout) (# 7) i ≡ Pass.FX M x i
  pass-FX i = refl

module _ {R : Set} (M : Model R) (x : EndInputs R) where
  module J = EndInputs x
  open Eval {endSig} M

  eenv₀ : Env endSig R
  eenv₀ = env (J.SPECINIT ∷ J.SPEC ∷ J.ECOS ∷ J.ESIN ∷ J.DDEN ∷ J.CG ∷ J.WN ∷ J.SIG ∷ (λ _ → Model.lit M (+ 0 / 1)) ∷ [])
              []
              (J.dtg ∷ J.tauwix ∷ J.tauwiy ∷ J.tauwnx ∷ J.tauwny ∷ J.taubbl1 ∷ J.taubbl2 ∷ J.phiaw ∷ J.phibbl
               ∷ J.dair ∷ J.coef ∷ J.ustar ∷ J.ustdir ∷ J.dtdyn ∷ J.fhigh ∷ J.tpiinv ∷ [])
              (J.nth ∷ J.nk ∷ J.nspec ∷ J.nsteps ∷ 15 ∷ []) 0

  eout : Env endSig R
  eout = runL (EndProgram.ProgL.launches srceEnd) eenv₀

  end-FX : ∀ i → lookup (Env.farr eout) (# 8) i ≡ End.FX M x i
  end-FX i = refl
