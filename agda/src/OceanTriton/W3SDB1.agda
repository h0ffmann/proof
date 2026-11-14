{-# OPTIONS --safe --without-K #-}

-- WAVEWATCH III's depth-induced breaking W3SDB1 (Battjes and Janssen 1978), read from
-- model/src/w3sdb1md.F90 of MetOcean's fork at tag 7.14.mos-92e2cf6, commit 92e2cf66, and
-- written here line by line (the branch IWB = 1, the one the routine sets at :197).
--
--     w3sdb1md.F90:223   IF ( FDONLY ) THEN  HM = DBLE(SDBC2) * DBLE(DEPTH)
--     w3sdb1md.F90:226   ELSE  HM = DBLE(SDBC2) / DBLE(WNMEAN) * TANH ( DBLE(WNMEAN) * MAX(DEPTH,0.) )
--     w3sdb1md.F90:230   HRMS = DSQRT (8.d0 * DBLE(EMEAN))
--     w3sdb1md.F90:231   IF ( HM .GT. THR ) THEN  BB = HRMS * HRMS / ( HM * HM ) ; B = DSQRT(BB)
--     w3sdb1md.F90:234   ELSE  BB = 0.d0 ; B = 0.d0
--     w3sdb1md.F90:241   IF ( B .LE. 0.5d0 ) THEN  Q0 = 0.d0
--     w3sdb1md.F90:243   ELSE IF ( B .LE. 1.d0 ) THEN  Q0 = ( 2.d0 * B - 1.d0 ) ** 2
--     w3sdb1md.F90:247   IF ( B .LE. 0.2d0 ) THEN  QB = 0.d0
--     w3sdb1md.F90:249   ELSE IF ( B .LT. 1.d0 ) THEN
--     w3sdb1md.F90:254     ARG = EXP (( Q0 - 1.d0 ) / BB )
--     w3sdb1md.F90:255     QB  = Q0 - BB * ( Q0 - ARG ) / ( BB - ARG )
--     w3sdb1md.F90:256     DO IS=1, 3 ;  QB = EXP((QB-1.)/BB) ;  END DO
--     w3sdb1md.F90:259   ELSE  QB = 1.0 - THR
--     w3sdb1md.F90:270   IF ( ( BB .GT. THR) .AND. ( ABS ( BB - QB ) .GT. THR) ) THEN
--     w3sdb1md.F90:271     IF ( BB .LT. 1.0) THEN  CBJ = 2 * DBLE(SDBC1) * QB * DBLE(FMEAN) / BB
--     w3sdb1md.F90:274     ELSE  CBJ = 2 * DBLE(SDBC1) * DBLE(FMEAN) * BB
--     w3sdb1md.F90:277   ELSE  CBJ = 0.d0
--     w3sdb1md.F90:279   D = - CBJ ;  S = D * A                                   (:279-280)
--
-- THR is DBLE(1.E-15) (:195): the float32 nearest 1e-15, widened. HM … CBJ are REAL*8
-- (:177); A, S, D, EMEAN, FMEAN, WNMEAN, DEPTH, SDBC1 and SDBC2 are REAL, widened by DBLE where
-- the routine says so. ETOT, FMEAN2 and EB (:206-221) do not reach S or D in this branch, so they
-- are not here. The routine returns early when SUM(A) < THR (:198), leaving S and D as they were;
-- that case is not here either, and the replay checks that the captured A is above it.
--
-- Where B > 1, the routine leaves Q0 unset; only the branch B < 1 reads it, so Q0 here is
-- (2B - 1)² there too, which nothing reads. `.AND.` is two nested IFs, as both sides are pure.
--
-- The arithmetic is a `Model`: any type with the operations, constants and tests the routine
-- uses, EXP, TANH and DSQRT among them. The kernel is a straight-line program in `Prog`, one
-- statement per name above, and `sdb-cbj` says, by refl, that it computes the routine's CBJ in
-- every model; `sdb-D` and `sdb-S` that the lanes store D and S. The Triton printer reads the
-- model as IEEE double (tl.exp, tl.sqrt, a tanh from tl.exp) with a float32 D, as gfortran does;
-- `floatModel` is the same model in Agda's Float, which computes the exact values of `vectors`.
module OceanTriton.W3SDB1 where

open import Data.Bool using (Bool; true; false; if_then_else_)
import Data.Float as F
open import Data.Fin using (Fin; toℕ; #_)
open import Data.List as L using (List; []; _∷_)
open import Data.Nat using (ℕ; zero; suc)
open import Data.Nat.Show using () renaming (show to showℕ)
open import Data.String using (String; _++_; unlines)
import Data.String as S
open import Data.Vec as V using (Vec; []; _∷_; _∷ʳ_; lookup)
open import Data.Product using (_×_; _,_)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- ---------------------------------------------------------------------------------------------
-- The arithmetic

-- The literals of the routine, as the Fortran writes them: 0.d0, 1.d0 (and 1.0, 1.), 2.d0 (and
-- the integer 2), 8.d0, 0.5d0, 0.2d0, and THR.
data Lit : Set where
  l0 l1 l2 l8 lhalf lfifth lthr : Lit

data Fun : Set where
  fexp ftanh fsqrt fabs : Fun

record Model (R : Set) : Set where
  field
    _+_ _-_ _*_ _/_ : R → R → R
    max             : R → R → R          -- MAX(DEPTH, 0.)
    fun             : Fun → R → R        -- EXP, TANH, DSQRT, ABS
    lit             : Lit → R
    _<ᵇ_ _≤ᵇ_       : R → R → Bool
    neg             : R → R
    real            : R → R              -- REAL*8 to REAL, in D = - CBJ
    mul32           : R → R → R          -- REAL times REAL, in S = D * A
  infixl 6 _+_ _-_
  infixl 7 _*_ _/_

-- ---------------------------------------------------------------------------------------------
-- The transcription

-- The routine's REAL inputs, as the model's numbers (DBLE of each).
record Inputs (R : Set) : Set where
  field emean fmean wnmean depth sdbc1 sdbc2 : R

module Routine {R : Set} (M : Model R) (fdonly : Bool) (x : Inputs R) where
  open Model M
  open Inputs x

  thr = lit lthr

  hm : R
  hm = if fdonly then sdbc2 * depth else sdbc2 / wnmean * fun ftanh (wnmean * max depth (lit l0))

  cbj : R
  cbj =
    let hrms = fun fsqrt (lit l8 * emean)
        bb   = if thr <ᵇ hm then hrms * hrms / (hm * hm) else lit l0
        b    = if thr <ᵇ hm then fun fsqrt bb else lit l0
        t    = lit l2 * b - lit l1
        q0   = if b ≤ᵇ lit lhalf then lit l0 else t * t
        arg  = fun fexp ((q0 - lit l1) / bb)
        qa   = q0 - bb * (q0 - arg) / (bb - arg)
        q1   = fun fexp ((qa - lit l1) / bb)
        q2   = fun fexp ((q1 - lit l1) / bb)
        q3   = fun fexp ((q2 - lit l1) / bb)
        qb   = if b ≤ᵇ lit lfifth then lit l0 else (if b <ᵇ lit l1 then q3 else lit l1 - thr)
    in if thr <ᵇ bb
       then (if thr <ᵇ fun fabs (bb - qb)
             then (if bb <ᵇ lit l1 then lit l2 * sdbc1 * qb * fmean / bb else lit l2 * sdbc1 * fmean * bb)
             else lit l0)
       else lit l0

  D : R
  D = real (neg cbj)

  S : R → R
  S a = mul32 D a

-- ---------------------------------------------------------------------------------------------
-- The kernel language: expressions over n named numbers, and straight-line programs that name
-- one more number per statement (indices are positions from the first, the six inputs).

data E (n : ℕ) : Set where
  var          : Fin n → E n
  lit          : Lit → E n
  _⊕_ _⊖_ _⊗_ _⊘_ : E n → E n → E n
  max          : E n → E n → E n
  fun          : Fun → E n → E n
  ifLt ifLe    : E n → E n → E n → E n → E n   -- if a < b (a ≤ b) then t else e

infixl 6 _⊕_ _⊖_
infixl 7 _⊗_ _⊘_

data Prog (n : ℕ) : Set where
  ret   : E n → Prog n
  _≔_   : E n → Prog (suc n) → Prog n
infixr 4 _≔_

module Eval {R : Set} (M : Model R) where
  open Model M renaming (max to maxM; fun to funM; lit to litM)

  ev : ∀ {n} → Vec R n → E n → R
  ev ρ (var i)        = lookup ρ i
  ev ρ (lit l)        = litM l
  ev ρ (p ⊕ q)        = ev ρ p + ev ρ q
  ev ρ (p ⊖ q)        = ev ρ p - ev ρ q
  ev ρ (p ⊗ q)        = ev ρ p * ev ρ q
  ev ρ (p ⊘ q)        = ev ρ p / ev ρ q
  ev ρ (max p q)      = maxM (ev ρ p) (ev ρ q)
  ev ρ (fun f p)      = funM f (ev ρ p)
  ev ρ (ifLt a b t e) = if ev ρ a <ᵇ ev ρ b then ev ρ t else ev ρ e
  ev ρ (ifLe a b t e) = if ev ρ a ≤ᵇ ev ρ b then ev ρ t else ev ρ e

  run : ∀ {n} → Vec R n → Prog n → R
  run ρ (ret e)   = ev ρ e
  run ρ (e ≔ p)   = run (ρ ∷ʳ ev ρ e) p

  inputs : Inputs R → Vec R 6
  inputs x = emean ∷ fmean ∷ wnmean ∷ depth ∷ sdbc1 ∷ sdbc2 ∷ []
    where open Inputs x

-- The names of the inputs, in the order of `inputs`.
inputNames : Vec String 6
inputNames = "emean" ∷ "fmean" ∷ "wnmean" ∷ "depth" ∷ "sdbc1" ∷ "sdbc2" ∷ []

-- CBJ as a program: statement k names the number k + 6.
--   0 emean  1 fmean  2 wnmean  3 depth  4 sdbc1  5 sdbc2
--   6 hm  7 hrms  8 bb  9 b  10 t  11 q0  12 arg  13 qa  14 q1  15 q2  16 q3  17 qb
cbjP : Bool → Prog 6
cbjP fd =
     hmE fd
  ≔ fun fsqrt (lit l8 ⊗ var (# 0))
  ≔ ifLt thr (var (# 6)) (var (# 7) ⊗ var (# 7) ⊘ (var (# 6) ⊗ var (# 6))) (lit l0)
  ≔ ifLt thr (var (# 6)) (fun fsqrt (var (# 8))) (lit l0)
  ≔ lit l2 ⊗ var (# 9) ⊖ lit l1
  ≔ ifLe (var (# 9)) (lit lhalf) (lit l0) (var (# 10) ⊗ var (# 10))
  ≔ fun fexp ((var (# 11) ⊖ lit l1) ⊘ var (# 8))
  ≔ var (# 11) ⊖ var (# 8) ⊗ (var (# 11) ⊖ var (# 12)) ⊘ (var (# 8) ⊖ var (# 12))
  ≔ fun fexp ((var (# 13) ⊖ lit l1) ⊘ var (# 8))
  ≔ fun fexp ((var (# 14) ⊖ lit l1) ⊘ var (# 8))
  ≔ fun fexp ((var (# 15) ⊖ lit l1) ⊘ var (# 8))
  ≔ ifLe (var (# 9)) (lit lfifth) (lit l0) (ifLt (var (# 9)) (lit l1) (var (# 16)) (lit l1 ⊖ thr))
  ≔ ret (ifLt thr (var (# 8))
          (ifLt thr (fun fabs (var (# 8) ⊖ var (# 17)))
            (ifLt (var (# 8)) (lit l1) (lit l2 ⊗ var (# 4) ⊗ var (# 17) ⊗ var (# 1) ⊘ var (# 8)) (lit l2 ⊗ var (# 4) ⊗ var (# 1) ⊗ var (# 8)))
            (lit l0))
          (lit l0))
  where
  thr : ∀ {n} → E n
  thr = lit lthr
  hmE : Bool → E 6
  hmE true  = var (# 5) ⊗ var (# 3)
  hmE false = var (# 5) ⊘ var (# 2) ⊗ fun ftanh (var (# 2) ⊗ max (var (# 3)) (lit l0))

-- ---------------------------------------------------------------------------------------------
-- Soundness: in every model, the program is the routine's CBJ, and the lanes store D and S.

module _ {R : Set} (M : Model R) where
  open Eval M
  open Model M using (real; neg; mul32)

  sdb-cbj : ∀ fd (x : Inputs R) → run (inputs x) (cbjP fd) ≡ Routine.cbj M fd x
  sdb-cbj true  x = refl
  sdb-cbj false x = refl

  -- Lane i of the kernel: D = REAL(-CBJ), S = D * A(i).
  laneD : Bool → Inputs R → R
  laneD fd x = real (neg (run (inputs x) (cbjP fd)))

  laneS : Bool → Inputs R → R → R
  laneS fd x a = mul32 (laneD fd x) a

  sdb-D : ∀ fd x → laneD fd x ≡ Routine.D M fd x
  sdb-D true  x = refl
  sdb-D false x = refl

  sdb-S : ∀ fd x a → laneS fd x a ≡ Routine.S M fd x a
  sdb-S true  x a = refl
  sdb-S false x a = refl

-- ---------------------------------------------------------------------------------------------
-- The Triton printer. Like `OceanTriton.Emit`, it is trusted: nothing proves that the Python
-- means what `run` means. It reads the model as IEEE double: each literal is a float64 constant
-- (a Python float in a Triton kernel would be float32, and 0.2 is not one), each statement a
-- float64 scalar, `fun` tl.exp, tl.sqrt, tl.abs and `_tanh`, a tanh from tl.exp (Triton's CPU
-- interpreter has no libdevice.tanh), `max` tl.maximum, `ifLt`/`ifLe` tl.where (both sides are
-- computed; the one not taken may be inf or NaN, which nothing reads), `real` .to(tl.float32)
-- and `mul32` a float32 product.

litPy : Lit → String
litPy l0     = "0.0"
litPy l1     = "1.0"
litPy l2     = "2.0"
litPy l8     = "8.0"
litPy lhalf  = "0.5"
litPy lfifth = "0.2"
litPy lthr   = "1.0000000036274937e-15"

litName : Lit → String
litName l0     = "c0"
litName l1     = "c1"
litName l2     = "c2"
litName l8     = "c8"
litName lhalf  = "chalf"
litName lfifth = "cfifth"
litName lthr   = "thr"

lits : List Lit
lits = l0 ∷ l1 ∷ l2 ∷ l8 ∷ lhalf ∷ lfifth ∷ lthr ∷ []

pyE : ∀ {n} → Vec String n → E n → String
pyE ns (var i)        = lookup ns i
pyE ns (lit l)        = litName l
pyE ns (p ⊕ q)        = "(" ++ pyE ns p ++ " + " ++ pyE ns q ++ ")"
pyE ns (p ⊖ q)        = "(" ++ pyE ns p ++ " - " ++ pyE ns q ++ ")"
pyE ns (p ⊗ q)        = "(" ++ pyE ns p ++ " * " ++ pyE ns q ++ ")"
pyE ns (p ⊘ q)        = "(" ++ pyE ns p ++ " / " ++ pyE ns q ++ ")"
pyE ns (max p q)      = "tl.maximum(" ++ pyE ns p ++ ", " ++ pyE ns q ++ ")"
pyE ns (fun fexp p)   = "tl.exp(" ++ pyE ns p ++ ")"
pyE ns (fun ftanh p)  = "_tanh(" ++ pyE ns p ++ ")"
pyE ns (fun fsqrt p)  = "tl.sqrt(" ++ pyE ns p ++ ")"
pyE ns (fun fabs p)   = "tl.abs(" ++ pyE ns p ++ ")"
pyE ns (ifLt a b t e) = "tl.where(" ++ pyE ns a ++ " < " ++ pyE ns b ++ ", " ++ pyE ns t ++ ", " ++ pyE ns e ++ ")"
pyE ns (ifLe a b t e) = "tl.where(" ++ pyE ns a ++ " <= " ++ pyE ns b ++ ", " ++ pyE ns t ++ ", " ++ pyE ns e ++ ")"

pyP : ∀ {n} → Vec String n → Prog n → List String
pyP {n} ns (ret e) = ("    cbj = " ++ pyE ns e) ∷ []
pyP {n} ns (e ≔ p) = ("    " ++ name ++ " = " ++ pyE ns e) ∷ pyP (ns ∷ʳ name) p
  where name = "v" ++ showℕ n

kernelPy : String → Bool → String
kernelPy name fd = unlines (
  "@triton.jit" ∷
  ("def " ++ name ++ "(A_ptr, p_ptr, s_ptr, d_ptr, n, BLOCK: tl.constexpr):") ∷
  ("    \"\"\"D and S of WAVEWATCH III's W3SDB1 with FDONLY " ++ (if fd then "true" else "false")
     ++ " (w3sdb1md.F90:223-280); p is emean, fmean, wnmean, depth, sdbc1, sdbc2 in float64.\"\"\"") ∷
  "    i = tl.program_id(0) * BLOCK + tl.arange(0, BLOCK)" ∷
  "    m = i < n" ∷
  L.map (λ l → "    " ++ litName l ++ " = tl.full([], " ++ litPy l ++ ", tl.float64)") lits L.++
  inputLines L.++
  pyP inputNames (cbjP fd) L.++
  "    d = (-cbj).to(tl.float32)" ∷
  "    tl.store(d_ptr + i, tl.zeros([BLOCK], dtype=tl.float32) + d, mask=m)" ∷
  "    tl.store(s_ptr + i, d * tl.load(A_ptr + i, mask=m, other=0.0), mask=m)" ∷ [])
  where
  inputLines = L.zipWith (λ k nm → "    " ++ nm ++ " = tl.load(p_ptr + " ++ showℕ k ++ ")")
                 (L.upTo 6) (V.toList inputNames)

sdbModule : String
sdbModule = unlines (
  "# Generated by tools/ocean-triton/ from agda/src/OceanTriton/W3SDB1.agda. Do not edit: change" ∷
  "# the Agda and run `just ocean-triton`." ∷
  "\"\"\"WAVEWATCH III's depth-induced breaking W3SDB1, one kernel for each value of FDONLY.\"\"\"" ∷
  "" ∷
  "import triton" ∷
  "import triton.language as tl" ∷
  "" ∷
  "" ∷
  "@triton.jit" ∷
  "def _tanh(x):" ∷
  "    \"\"\"tanh in float64 from tl.exp: sign(x) (1 - e) / (1 + e), e = exp(-2 |x|).\"\"\"" ∷
  "    e = tl.exp(-2.0 * tl.abs(x))" ∷
  "    t = (1.0 - e) / (1.0 + e)" ∷
  "    return tl.where(x < 0.0, -t, t)" ∷
  "" ∷
  "" ∷
  kernelPy "w3sdb1" false ∷
  "" ∷
  "" ∷
  kernelPy "w3sdb1_fdonly" true ∷
  "" ∷
  "" ∷
  "# FDONLY to its kernel; the inputs of p in order." ∷
  "KERNELS = {False: w3sdb1, True: w3sdb1_fdonly}" ∷
  ("INPUTS = (" ++ S.concat (L.map (λ nm → "\"" ++ nm ++ "\", ") (V.toList inputNames)) ++ ")") ∷ [])

-- ---------------------------------------------------------------------------------------------
-- The exact values: the routine in Agda's Float (IEEE double, with the host's exp, tanh and
-- sqrt), for D and S unrounded; check_sdb.py allows the float32 budget of check.py around them.

floatModel : Model F.Float
floatModel = record
  { _+_ = F._+_ ; _-_ = F._-_ ; _*_ = F._*_ ; _/_ = F._÷_
  ; max = λ a b → if b F.<ᵇ a then a else b
  ; fun = λ { fexp x → F.e^ x ; ftanh x → F.tanh x ; fsqrt x → F.sqrt x
            ; fabs x → if x F.<ᵇ 0.0 then F.- x else x }
  ; lit = λ { l0 → 0.0 ; l1 → 1.0 ; l2 → 2.0 ; l8 → 8.0 ; lhalf → 0.5 ; lfifth → 0.2
            ; lthr → 1.0000000036274937e-15 }
  ; _<ᵇ_ = F._<ᵇ_ ; _≤ᵇ_ = F._≤ᵇ_ ; neg = F.-_ ; real = λ x → x ; mul32 = F._*_ }

private
  mk : F.Float → F.Float → F.Float → F.Float → Inputs F.Float
  mk e f k d = record { emean = e ; fmean = f ; wnmean = k ; depth = d ; sdbc1 = 1.0 ; sdbc2 = 0.73 }

  -- name, FDONLY, inputs; the B of each, from HRMS = sqrt (8 emean) and HM = 0.73 d (FDONLY),
  -- says which branch it reaches.
  cases : List (String × Bool × Inputs F.Float)
  cases =
      ("deep, B ≈ 0.0005"           , true  , mk 0.1    0.12 0.004 2500.0)
    ∷ ("B ≈ 0.35, Q0 = 0"           , true  , mk 0.0326 0.12 0.5   2.0)
    ∷ ("B ≈ 0.8, Q0 > 0"            , true  , mk 0.1705 0.12 0.5   2.0)
    ∷ ("B ≈ 1.37, BB ≥ 1"           , true  , mk 0.5    0.12 0.5   2.0)
    ∷ ("FDONLY false, B ≈ 0.83"     , false , mk 0.15   0.12 0.5   3.0)
    ∷ ("FDONLY false, B ≈ 0.25"     , false , mk 0.003  0.12 1.2   4.0)
    ∷ ("FDONLY false, depth < 0"    , false , mk 0.15   0.12 0.5   (F.- 1.0))
    ∷ []

  As : List F.Float
  As = 1.0 ∷ 0.5 ∷ 0.25 ∷ 2.0 ∷ 3.0 ∷ []

  q : String → String
  q s = "\"" ++ s ++ "\""

  fl : F.Float → String
  fl x = q (F.show x)

  arr : List String → String
  arr xs = "[" ++ S.intersperse ", " xs ++ "]"

  caseJson : String × Bool × Inputs F.Float → String
  caseJson (nm , fd , x) =
    "  {\"name\": " ++ q nm ++ ", \"fdonly\": " ++ (if fd then "true" else "false")
    ++ ", \"inputs\": " ++ arr (V.toList (V.map fl (Eval.inputs floatModel x)))
    ++ ", \"A\": " ++ arr (L.map fl As)
    ++ ", \"D\": " ++ fl (laneD floatModel fd x)
    ++ ", \"S\": " ++ arr (L.map (λ a → fl (laneS floatModel fd x a)) As) ++ "}"

sdbVectors : String
sdbVectors = "[\n" ++ S.intersperse ",\n" (L.map caseJson cases) ++ "\n]\n"
