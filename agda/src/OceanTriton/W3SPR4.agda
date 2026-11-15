{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's ST4 means W3SPR4 and the friction velocity CALC_USTAR, read from
-- model/src/w3src4md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66:
--
--     w3src4md.F90:294-302   DO IK, DO ITH: EB(IK) += A ; ELCS += A*ECOS*DDEN/CG ; ELSN the same
--                            with ESIN ; IF (LLWS(IS)) EB2(IK) += A ; AMAX = MAX(AMAX, A)
--     w3src4md.F90:307       DLWMEAN = ATAN2(ELSN, ELCS)
--     w3src4md.F90:311-319   DO IK: EB, EB2 times DDEN/CG ; EMEAN, FMEAN (EB/SIG), FMEAN1
--                            (EB SIG**(2 WWNMEANPTAIL)), WNMEAN (EB WN**WWNMEANP), EMEANWS, FMEANWS
--     w3src4md.F90:325-332   the tail beyond the last bin: EBAND = EB(NK)/DDEN(NK) times FTE, FTF,
--                            SSTXFTFTAIL, SSTXFTWN
--     w3src4md.F90:336-350   FMEAN, FMEAN1, WNMEAN, FMEANWS as means, with their floors at 1E-7
--     w3src4md.F90:355-364   TAUW = SQRT(TAUWX**2+TAUWY**2), CALC_USTAR, CD = (USTAR/UNZ)**2
--     w3src4md.F90:1738-1840 CALC_USTAR: USTAR bilinear in TAUT(SQRT(TAUW)/DELTAUW, U/DELU),
--                            Z0 = ZZWND EXP(-KAPPA MIN(U/USTAR, 100)), CHARN = GRAV Z0/USTAR**2
--
-- The arithmetic is gfortran -O3's (the GIMPLE of -fdump-tree-optimized at the pin). Each sum is a
-- left fold in the Fortran's order: the vectoriser keeps the order of a float reduction. The
-- real powers of :316-319 are vectorised four bins at a time from the first, so those bins take
-- libmvec's powf (`vpow`) and the last NK mod 4 take powf (`pow`), as in W3SDS4; the powers of
-- :336-350 are scalar powf. GRAV and KAPPA are the literals the compiler folds and TPIINV comes as a value (a quotient of two
-- literals would be folded in double by the printed Python); 1/(2 W)
-- is computed as 1/(W*2). Indices start at 0, and TAUT(I,J) is taut(i + 201 j).
--
-- `spr4-OUT`: the three launches give the routine's eleven scalars, by refl, in every model.
module OceanTriton.W3SPR4 where

open import Data.Bool using (Bool; true; false; if_then_else_)
open import Data.Fin using (Fin; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat as ℕ using (ℕ; suc; _∸_; _<ᵇ_)
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
    A CG WN SIG DDEN ECOS ESIN LLWS TAUT : ℕ → R
    u tauwx tauwy wwnmeanptail wwnmeanp fte ftf sstxftftail sstxftwn deltauw delu zzwnd aalpha tauwmax tpiinv : R
    nth nk nspec itaumax jumax : ℕ

module Routine {R : Set} (M : Model R) (x : Inputs R) where
  open Model M
  open Inputs x

  infixl 6 _+_ _-_
  infixl 7 _*_ _÷_
  _+_ _-_ _*_ _÷_ : R → R → R
  _+_ = op add ; _-_ = op sub ; _*_ = op mul ; _÷_ = op div
  ℓ : ℚ → R
  ℓ = lit
  z eps : R
  z = ℓ (+ 0 / 1) ; eps = ℓ (+ 1 / 10000000)
  g : R
  g = ℓ (+ 4903 / 500)

  -- :294-302
  ebA eb2A : ℕ → R
  ebA ik  = foldN nth z (λ j r → r + A (ik ℕ.* nth ℕ.+ j))
  eb2A ik = foldN nth z (λ j r → if cmp ne (LLWS (ik ℕ.* nth ℕ.+ j)) z then r + A (ik ℕ.* nth ℕ.+ j) else r)

  amax elcs elsn : R
  amax = foldN nspec z (λ is r → op max r (A is))
  elcs = foldN nspec z (λ is r → r + A is * ECOS is * DDEN (idiv is nth) ÷ CG (idiv is nth))
  elsn = foldN nspec z (λ is r → r + A is * ESIN is * DDEN (idiv is nth) ÷ CG (idiv is nth))

  -- :311-314
  eb eb2 : ℕ → R
  eb ik  = ebA ik * DDEN ik ÷ CG ik
  eb2 ik = eb2A ik * DDEN ik ÷ CG ik

  rpow : ℕ → R → R → R
  rpow ik b e = if ik <ᵇ nk ∸ imod nk 4 then vpow b e else pow b e

  powS powW : ℕ → R
  powS ik = rpow ik (SIG ik) (wwnmeanptail * ℓ (+ 2 / 1))
  powW ik = rpow ik (WN ik) wwnmeanp

  sum : (ℕ → R) → R
  sum f = foldN nk z (λ k r → r + f k)

  eband eband2 : R
  eband  = eb (nk ∸ 1) ÷ DDEN (nk ∸ 1)
  eband2 = eb2 (nk ∸ 1) ÷ DDEN (nk ∸ 1)

  emean fmeanT fmean1T wnmeanT emeanws fmeanwsT : R
  emean    = sum eb + eband * fte
  fmeanT   = sum (λ k → eb k ÷ SIG k) + eband * ftf
  fmean1T  = sum (λ k → eb k * powS k) + eband * sstxftftail
  wnmeanT  = sum (λ k → eb k * powW k) + eband * sstxftwn
  emeanws  = sum eb2 + eband2 * fte
  fmeanwsT = sum (λ k → eb2 k * powS k) + eband2 * sstxftftail

  -- :336-350
  fmean fmean1 wnmean fmeanws : R
  fmean  = emean * tpiinv ÷ op max eps fmeanT
  fmean1 = if cmp lt fmean1T eps then tpiinv * SIG (nk ∸ 1)
           else pow (op max eps fmean1T ÷ op max eps emean) (ℓ (+ 1 / 1) ÷ (wwnmeanptail * ℓ (+ 2 / 1))) * tpiinv
  wnmean = pow (op max eps wnmeanT ÷ op max eps emean) (ℓ (+ 1 / 1) ÷ wwnmeanp)
  fmeanws = if cmp lt fmeanwsT eps then tpiinv * SIG (nk ∸ 1)
            else (if cmp lt emeanws eps then tpiinv * SIG (nk ∸ 1)
            else pow (op max eps fmeanwsT ÷ op max eps emeanws) (ℓ (+ 1 / 1) ÷ (wwnmeanptail * ℓ (+ 2 / 1))) * tpiinv)

  -- CALC_USTAR (:1738-1840) with TAUW = SQRT(TAUWX**2+TAUWY**2) (:355).
  tauw xi xj : R
  tauw = fun fsqrt (tauwx * tauwx + tauwy * tauwy)
  xi = fun fsqrt (op max (op min tauw tauwmax) z) ÷ deltauw
  xj = u ÷ delu

  ind j : ℕ
  ind = ℕ._⊓_ (itaumax ∸ 1) (trunc xi)
  j   = ℕ._⊓_ (jumax ∸ 1) (trunc xj)

  T : ℕ → ℕ → R
  T a b = TAUT (a ℕ.+ b ℕ.* (itaumax ℕ.+ 1))

  ustar : R
  ustar = let d1 = op min (ℓ (+ 1 / 1)) (xi - fromℕ ind) ; d2 = ℓ (+ 1 / 1) - d1
              e1 = op min (ℓ (+ 1 / 1)) (xj - fromℕ j)   ; e2 = ℓ (+ 1 / 1) - e1
          in (T ind j * d2 + T (ind ℕ.+ 1) j * d1) * e2 + (T ind (j ℕ.+ 1) * d2 + T (ind ℕ.+ 1) (j ℕ.+ 1) * d1) * e1

  z0a z0 charn cd : R
  z0a   = zzwnd * fun fexp (fun fneg (op min (u ÷ ustar) (ℓ (+ 100 / 1)) * ℓ (+ 2 / 5)))
  z0    = if cmp lt (ℓ (+ 1 / 1000)) ustar then z0a
          else (if cmp lt z ustar then z0a else aalpha * ℓ (+ 1 / 1000) * ℓ (+ 1 / 1000) ÷ g)
  charn = if cmp lt (ℓ (+ 1 / 1000)) ustar then z0a * g ÷ (ustar * ustar) else aalpha
  cd    = let q = ustar ÷ op max u (ℓ (+ 1 / 100)) in q * q

  -- The eleven scalars, one lane each.
  OUT : ℕ → R
  OUT i = if i <ᵇ 1 then emean else (if i <ᵇ 2 then fmean else (if i <ᵇ 3 then fmean1
          else (if i <ᵇ 4 then wnmean else (if i <ᵇ 5 then amax else (if i <ᵇ 6 then ustar
          else (if i <ᵇ 7 then z0 else (if i <ᵇ 8 then charn else (if i <ᵇ 9 then cd
          else (if i <ᵇ 10 then fmeanws else op atan2 elsn elcs)))))))))

-- ---------------------------------------------------------------------------------------------
-- The program

spr4Sig : Sig
spr4Sig = record { nf = 12 ; ni = 0 ; nfp = 15 ; nip = 6 }

open Syntax spr4Sig

private
  A CG WN SIG DDEN ECOS ESIN LLWS TAUT EB EB2 OUTB : Fin 12
  A = # 0 ; CG = # 1 ; WN = # 2 ; SIG = # 3 ; DDEN = # 4 ; ECOS = # 5 ; ESIN = # 6 ; LLWS = # 7
  TAUT = # 8 ; EB = # 9 ; EB2 = # 10 ; OUTB = # 11

  u tauwx tauwy wtail wp fte ftf sftail sftwn deltauw delu zzwnd aalpha tauwmax tpiinv : ∀ {v a} → FE v a
  u = fpar (# 0) ; tauwx = fpar (# 1) ; tauwy = fpar (# 2) ; wtail = fpar (# 3) ; wp = fpar (# 4)
  fte = fpar (# 5) ; ftf = fpar (# 6) ; sftail = fpar (# 7) ; sftwn = fpar (# 8) ; deltauw = fpar (# 9)
  delu = fpar (# 10) ; zzwnd = fpar (# 11) ; aalpha = fpar (# 12) ; tauwmax = fpar (# 13) ; tpiinv = fpar (# 14)

  NTH NK NSPEC N11 ITM JUM : Fin 6
  NTH = # 0 ; NK = # 1 ; NSPEC = # 2 ; N11 = # 3 ; ITM = # 4 ; JUM = # 5

  nth nk nspec itm jum : ∀ {v} → IE v
  nth = ipar NTH ; nk = ipar NK ; nspec = ipar NSPEC ; itm = ipar ITM ; jum = ipar JUM

  infixl 6 _⊕_ _⊖_
  infixl 7 _⊗_ _⊘_
  _⊕_ _⊖_ _⊗_ _⊘_ : ∀ {v a} → FE v a → FE v a → FE v a
  _⊕_ = op add ; _⊖_ = op sub ; _⊗_ = op mul ; _⊘_ = op div

  c : ∀ {v a} → ℚ → FE v a
  c = lit

  zf eps one g : ∀ {v a} → FE v a
  zf = c (+ 0 / 1) ; eps = c (+ 1 / 10000000) ; one = c (+ 1 / 1) ; g = c (+ 4903 / 500)

  v0 : ∀ {v} → IE (suc v)
  v0 = var (# 0)

  ebB eb2B : FE 0 0
  ebB  = fold NTH nth zf (acc (# 0) ⊕ ld A (lane *ᵢ nth +ᵢ v0)) ⊗ ld DDEN lane ⊘ ld CG lane
  eb2B = fold NTH nth zf (sel ne (ld LLWS (lane *ᵢ nth +ᵢ v0)) zf (acc (# 0) ⊕ ld A (lane *ᵢ nth +ᵢ v0)) (acc (# 0)))
         ⊗ ld DDEN lane ⊘ ld CG lane

  -- A sum over the bins of a term of bin k (var 0).
  sumB : FE 1 1 → FE 0 0
  sumB t = fold NK nk zf (acc (# 0) ⊕ t)

  rpowB : FE 1 1 → FE 1 1 → FE 1 1
  rpowB b e = isel v0 (nk ∸ᵢ rem nk (nat 4)) (vpow b e) (pow b e)

  powS powW : FE 1 1
  powS = rpowB (ld SIG v0) (wtail ⊗ c (+ 2 / 1))
  powW = rpowB (ld WN v0) wp

  ebk eb2k : FE 1 1
  ebk = ld EB v0 ; eb2k = ld EB2 v0

  lastI : ∀ {v} → IE v
  lastI = nk ∸ᵢ nat 1

  eband eband2 emean fmeanT fmean1T wnmeanT emeanws fmeanwsT : FE 0 0
  eband    = ld EB lastI ⊘ ld DDEN lastI
  eband2   = ld EB2 lastI ⊘ ld DDEN lastI
  emean    = sumB ebk ⊕ eband ⊗ fte
  fmeanT   = sumB (ebk ⊘ ld SIG v0) ⊕ eband ⊗ ftf
  fmean1T  = sumB (ebk ⊗ powS) ⊕ eband ⊗ sftail
  wnmeanT  = sumB (ebk ⊗ powW) ⊕ eband ⊗ sftwn
  emeanws  = sumB eb2k ⊕ eband2 ⊗ fte
  fmeanwsT = sumB (eb2k ⊗ powS) ⊕ eband2 ⊗ sftail

  fmean fmean1 wnmean fmeanws : FE 0 0
  fmean  = emean ⊗ tpiinv ⊘ op max eps fmeanT
  fmean1 = sel lt fmean1T eps (tpiinv ⊗ ld SIG lastI)
             (pow (op max eps fmean1T ⊘ op max eps emean) (one ⊘ (wtail ⊗ c (+ 2 / 1))) ⊗ tpiinv)
  wnmean = pow (op max eps wnmeanT ⊘ op max eps emean) (one ⊘ wp)
  fmeanws = sel lt fmeanwsT eps (tpiinv ⊗ ld SIG lastI)
              (sel lt emeanws eps (tpiinv ⊗ ld SIG lastI)
                (pow (op max eps fmeanwsT ⊘ op max eps emeanws) (one ⊘ (wtail ⊗ c (+ 2 / 1))) ⊗ tpiinv))

  amaxB elcsB elsnB : FE 0 0
  amaxB = fold NSPEC nspec zf (op max (acc (# 0)) (ld A v0))
  elcsB = fold NSPEC nspec zf (acc (# 0) ⊕ ld A v0 ⊗ ld ECOS v0 ⊗ ld DDEN (quot v0 nth) ⊘ ld CG (quot v0 nth))
  elsnB = fold NSPEC nspec zf (acc (# 0) ⊕ ld A v0 ⊗ ld ESIN v0 ⊗ ld DDEN (quot v0 nth) ⊘ ld CG (quot v0 nth))

  tauw xi xj : ∀ {v a} → FE v a
  tauw = fn fsqrt (tauwx ⊗ tauwx ⊕ tauwy ⊗ tauwy)
  xi = fn fsqrt (op max (op min tauw tauwmax) zf) ⊘ deltauw
  xj = u ⊘ delu

  -- USTAR with var 1 = INT(XI) and var 0 = INT(XJ).
  ustarIn : FE 2 0
  ustarIn = (T ind j ⊗ d2 ⊕ T (ind +ᵢ nat 1) j ⊗ d1) ⊗ e2 ⊕ (T ind (j +ᵢ nat 1) ⊗ d2 ⊕ T (ind +ᵢ nat 1) (j +ᵢ nat 1) ⊗ d1) ⊗ e1
    where
      ind j : IE 2
      ind = minᵢ (itm ∸ᵢ nat 1) (var (# 1))
      j   = minᵢ (jum ∸ᵢ nat 1) (var (# 0))
      T : IE 2 → IE 2 → FE 2 0
      T a b = ld TAUT (a +ᵢ b *ᵢ (itm +ᵢ nat 1))
      d1 d2 e1 e2 : FE 2 0
      d1 = op min one (xi ⊖ real ind) ; d2 = one ⊖ d1
      e1 = op min one (xj ⊖ real j)   ; e2 = one ⊖ e1

  ustarB : FE 0 0
  ustarB = ix xi (ix xj ustarIn)

  -- A body with USTAR as accumulator 0.
  withU : FE 0 1 → FE 0 0
  withU = bind ustarB

  z0a : FE 0 1
  z0a = zzwnd ⊗ fn fexp (fn fneg (op min (u ⊘ acc (# 0)) (c (+ 100 / 1)) ⊗ c (+ 2 / 5)))

  z0B charnB cdB : FE 0 0
  z0B    = withU (sel lt (c (+ 1 / 1000)) (acc (# 0)) z0a
             (sel lt zf (acc (# 0)) z0a (aalpha ⊗ c (+ 1 / 1000) ⊗ c (+ 1 / 1000) ⊘ g)))
  charnB = withU (sel lt (c (+ 1 / 1000)) (acc (# 0)) (z0a ⊗ g ⊘ (acc (# 0) ⊗ acc (# 0))) aalpha)
  cdB    = withU (bind (acc (# 0) ⊘ op max u (c (+ 1 / 100))) (acc (# 0) ⊗ acc (# 0)))

  outB : FE 0 0
  outB = isel lane (nat 1) emean (isel lane (nat 2) fmean (isel lane (nat 3) fmean1
         (isel lane (nat 4) wnmean (isel lane (nat 5) amaxB (isel lane (nat 6) ustarB
         (isel lane (nat 7) z0B (isel lane (nat 8) charnB (isel lane (nat 9) cdB
         (isel lane (nat 10) fmeanws (op atan2 elsnB elcsB))))))))))

spr4Launches : List Launch
spr4Launches =
    launch "w3spr4_eb"  ebB  NK  EB   "EB, the energy of a bin (w3src4md.F90:294-312)"
  ∷ launch "w3spr4_eb2" eb2B NK  EB2  "EB2, the energy of a bin where the wind blows (w3src4md.F90:294-313)"
  ∷ launch "w3spr4_out" outB N11 OUTB "EMEAN FMEAN FMEAN1 WNMEAN AMAX USTAR Z0 CHARN CD FMEANWS DLWMEAN (w3src4md.F90:294-364, 1738-1840)"
  ∷ []

spr4 : ProgL
spr4 = record
  { name = "w3spr4"
  ; farrays = "A" ∷ "CG" ∷ "WN" ∷ "SIG" ∷ "DDEN" ∷ "ECOS" ∷ "ESIN" ∷ "LLWS" ∷ "TAUT" ∷ "EB" ∷ "EB2" ∷ "OUT" ∷ []
  ; iarrays = []
  ; fparams = "u" ∷ "tauwx" ∷ "tauwy" ∷ "wwnmeanptail" ∷ "wwnmeanp" ∷ "fte" ∷ "ftf" ∷ "sstxftftail"
              ∷ "sstxftwn" ∷ "deltauw" ∷ "delu" ∷ "zzwnd" ∷ "aalpha" ∷ "tauwmax" ∷ "tpiinv" ∷ []
  ; iparams = "nth" ∷ "nk" ∷ "nspec" ∷ "n11" ∷ "itaumax" ∷ "jumax" ∷ []
  ; launches = L.map single spr4Launches
  ; results = (OUTB , N11) ∷ []
  ; doc = "WAVEWATCH III's ST4 means W3SPR4 with CALC_USTAR, in three launches" }

-- ---------------------------------------------------------------------------------------------
-- Soundness

module _ {R : Set} (M : Model R) (x : Inputs R) where
  module I = Inputs x
  open Eval {spr4Sig} M

  env₀ : Env spr4Sig R
  env₀ = env (I.A ∷ I.CG ∷ I.WN ∷ I.SIG ∷ I.DDEN ∷ I.ECOS ∷ I.ESIN ∷ I.LLWS ∷ I.TAUT ∷ z₀ ∷ z₀ ∷ z₀ ∷ [])
             []
             (I.u ∷ I.tauwx ∷ I.tauwy ∷ I.wwnmeanptail ∷ I.wwnmeanp ∷ I.fte ∷ I.ftf ∷ I.sstxftftail
              ∷ I.sstxftwn ∷ I.deltauw ∷ I.delu ∷ I.zzwnd ∷ I.aalpha ∷ I.tauwmax ∷ I.tpiinv ∷ [])
             (I.nth ∷ I.nk ∷ I.nspec ∷ 11 ∷ I.itaumax ∷ I.jumax ∷ []) 0
    where z₀ = λ _ → Model.lit M (+ 0 / 1)

  out : Env spr4Sig R
  out = runL (ProgL.launches spr4) env₀

  spr4-OUT : ∀ i → lookup (Env.farr out) (# 11) i ≡ Routine.OUT M x i
  spr4-OUT i = refl
