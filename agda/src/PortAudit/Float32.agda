{-# OPTIONS --safe --without-K #-}

-- A bit-level model of IEEE 754 binary32 (`f32`), for groups U and S of the port audit of
-- chaceon (`tools/port-audit/Chaceon.hs`, `port-audit/README.md`). Z3 checks those statements in
-- its floating-point theory (SMT-LIB `FloatingPoint 8 24`). This module defines the same
-- operations from the bits, so that Agda can prove the statements for all 2^32 bit patterns of
-- each operand.
--
-- * A float is its 32 bits: a sign bit, 8 exponent bits and 23 fraction bits, most significant
--   bit first (`Float32`, `bits`, `ofBits`). Every bit pattern is a float, NaN payloads too.
-- * `classify` reads the bits as IEEE 754 does: exponent 255 is infinity (fraction 0) or NaN;
--   otherwise the float is finite, with the magnitude `magEF e f` in units of 2^-149, the
--   smallest subnormal. Every finite f32 is an integer number of such units.
-- * `round` is round to nearest, ties to even (RNE), from an exact magnitude in units of 2^-sh,
--   sh ≥ 149, with overflow to infinity. `add`, `sub` and `mul` round the exact result once, as
--   IEEE 754 requires. `fromI32` (Rust `t as f32`) rounds an integer the same way.
-- * `toI32` is Rust's `x as i32` for a finite x in (-2^31, 2^31): truncation toward zero. It
--   gives an integer of ℤ, so it cannot overflow; the premises of each statement keep x in
--   range, as in Z3.
-- * `roundToIntegral` is IEEE 754 roundToIntegral for the two modes the audit uses: RNA (ties
--   away from zero) and RTN (toward minus infinity).
-- * Comparisons are IEEE 754 comparisons: false when an operand is NaN, and -0 = +0.
-- * `fmax` and `fmin` are IEEE 754 maxNum and minNum, which Rust's `f32::max` and `f32::min`
--   follow: a NaN operand gives the other operand. For +0 and -0 SMT-LIB lets either be the
--   answer, and so does Rust; here a Boolean `z` makes that choice, and every statement holds
--   for both values of `z`.
--
-- Only RNE is needed for results that are floats: the code that the audit reads rounds every
-- f32 operation to nearest.
module PortAudit.Float32 where

open import Data.Bool using (Bool; true; false; not; _∧_; _∨_; _xor_; if_then_else_)
open import Data.Integer as ℤ using (ℤ; +_; -[1+_])
open import Data.Maybe using (Maybe; just; nothing)
open import Data.Nat as ℕ using (ℕ; zero; suc; _+_; _*_; _∸_; _^_; _<ᵇ_; _≤ᵇ_; _≡ᵇ_)
import Data.Nat.Properties as ℕₚ
open import Data.Vec using (Vec; []; _∷_; _++_; take; drop)
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

-- ---------------------------------------------------------------------------------------------
-- Bit vectors, most significant bit first

bitN : Bool → ℕ
bitN true  = 1
bitN false = 0

toℕ : ∀ {n} → Vec Bool n → ℕ
toℕ []                = 0
toℕ {suc n} (b ∷ v)   = bitN b * 2 ^ n + toℕ v

fromℕ : ∀ n → ℕ → Vec Bool n
fromℕ-step : ∀ n → ℕ → Bool → Vec Bool (suc n)

fromℕ zero    x = []
fromℕ (suc n) x = fromℕ-step n x (2 ^ n ≤ᵇ x)

fromℕ-step n x true  = true ∷ fromℕ n (x ∸ 2 ^ n)
fromℕ-step n x false = false ∷ fromℕ n x

-- Division by a power of two, with the instance that `_/_` needs.
_/2^_ : ℕ → ℕ → ℕ
n /2^ k = ℕ._/_ n (2 ^ k) {{ℕₚ.m^n≢0 2 k}}

_%2^_ : ℕ → ℕ → ℕ
n %2^ k = ℕ._%_ n (2 ^ k) {{ℕₚ.m^n≢0 2 k}}

-- ---------------------------------------------------------------------------------------------
-- The float and its bits

record Float32 : Set where
  constructor float
  field
    sign : Bool
    exp  : Vec Bool 8
    frac : Vec Bool 23

open Float32 public

Word32 : Set
Word32 = Vec Bool 32

-- Rust's `to_bits`, SBV's `sFloatAsSWord32`.
bits : Float32 → Word32
bits (float s e f) = s ∷ (e ++ f)

-- Rust's `from_bits`.
ofBits : Word32 → Float32
ofBits (s ∷ w) = float s (take 8 w) (drop 8 w)

ofWord : ℕ → Float32
ofWord n = ofBits (fromℕ 32 n)

-- ---------------------------------------------------------------------------------------------
-- What the bits mean

-- One unit is 2^-149. A normal float with exponent field e ≥ 1 is (2^23 + f) * 2^(e - 150),
-- that is (f + 2^23) * 2^(e - 1) units; a subnormal (e = 0) is f units. A literal is written
-- on the right of `+` and `*`: both recurse on their left operand, and a large literal there
-- would unfold into millions of `suc` when Agda compares symbolic terms.
magEF : ℕ → ℕ → ℕ
magEF zero    f = f
magEF (suc e) f = (f + 2 ^ 23) * 2 ^ e

data Kind : Set where
  nan : Kind
  inf : Bool → Kind               -- the sign
  fin : Bool → ℕ → Kind           -- the sign and the magnitude in units of 2^-149

kindB : Bool → ℕ → ℕ → Bool → Bool → Kind
kindB s e f true  true  = inf s
kindB s e f true  false = nan
kindB s e f false _     = fin s (magEF e f)

kindEF : Bool → ℕ → ℕ → Kind
kindEF s e f = kindB s e f (e ≡ᵇ 255) (f ≡ᵇ 0)

classify : Float32 → Kind
classify (float s e f) = kindEF s (toℕ e) (toℕ f)

isNaNK isInfK isZeroK isNegativeK : Kind → Bool
isNaNK nan = true
isNaNK _   = false
isInfK (inf _) = true
isInfK _       = false
isZeroK (fin _ zero) = true
isZeroK _            = false
-- SBV's fpIsNegative: the sign bit of a float that is not NaN, so -0 is negative.
isNegativeK nan       = false
isNegativeK (inf s)   = s
isNegativeK (fin s _) = s

isNaN isInf isZero isNegative : Float32 → Bool
isNaN      x = isNaNK (classify x)
isInf      x = isInfK (classify x)
isZero     x = isZeroK (classify x)
isNegative x = isNegativeK (classify x)

-- fpNeg and fpAbs change the sign bit only, as IEEE 754 negate and abs do.
neg : Float32 → Float32
neg (float s e f) = float (not s) e f

abs : Float32 → Float32
abs (float s e f) = float false e f

mk : Bool → ℕ → ℕ → Float32
mk s e m = float s (fromℕ 8 e) (fromℕ 23 m)

infF : Bool → Float32
infF s = mk s 255 0

-- The quiet NaN that Rust and x86 produce, 0x7fc00000.
nanF : Float32
nanF = mk false 255 (2 ^ 22)

zeroF : Float32
zeroF = mk false 0 0

-- ---------------------------------------------------------------------------------------------
-- Round to nearest, ties to even

-- The first k ≥ k0 with n < 2^k * 2^24: the significand n / 2^k then has at most 24 bits.
-- After 255 steps the exponent is past the largest finite one: `nothing` is overflow.
pick : ℕ → ℕ → ℕ → Maybe ℕ
pickB : ℕ → ℕ → ℕ → Bool → Maybe ℕ

pick zero    k n = nothing
pick (suc f) k n = pickB f k n (n <ᵇ 2 ^ k * 2 ^ 24)

pickB f k n true  = just k
pickB f k n false = pick f (suc k) n

odd : ℕ → Bool
odd n = ℕ._%_ n 2 ≡ᵇ 1

-- Round the quotient q up when the remainder r of a division by 2^k is above half, or exactly
-- half and q odd.
rneUp : ℕ → ℕ → ℕ → Bool
rneUp k q r = (2 ^ k <ᵇ 2 * r) ∨ ((2 ^ k ≡ᵇ 2 * r) ∧ odd q)

-- The float with sign s, significand M (< 2^24) and d steps above the subnormal exponent.
encodeB : Bool → ℕ → ℕ → Bool → Bool → Float32
encodeB s d M true  _     = mk s 0 M
encodeB s d M false true  = mk s (suc d) (M ∸ 2 ^ 23)
encodeB s d M false false = infF s

encode : Bool → ℕ → ℕ → Float32
encode s d M = encodeB s d M (M <ᵇ 2 ^ 23) (d <ᵇ 254)

-- A significand that rounded up to 2^24 moves one exponent up.
finishB : Bool → ℕ → ℕ → Bool → Float32
finishB s d M true  = encode s (suc d) (2 ^ 23)
finishB s d M false = encode s d M

finish : Bool → ℕ → ℕ → Float32
finish s d M = finishB s d M (M ≡ᵇ 2 ^ 24)

roundAt : Bool → ℕ → ℕ → Maybe ℕ → Float32
roundAt s n k0 nothing  = infF s
roundAt s n k0 (just k) = finish s (k ∸ k0) (n /2^ k + bitN (rneUp k (n /2^ k) (n %2^ k)))

-- `round s n sh`: the float nearest to (-1)^s * n * 2^-sh, ties to even, for sh ≥ 149.
round : Bool → ℕ → ℕ → Float32
round s n sh = roundAt s n (sh ∸ 149) (pick 255 (sh ∸ 149) n)

-- ---------------------------------------------------------------------------------------------
-- Arithmetic, rounded to nearest even

-- Two finite operands of opposite signs: the larger magnitude keeps its sign; an exact zero is
-- +0 under RNE.
cancelB : Bool → ℕ → Bool → ℕ → Bool → Bool → Float32
cancelB s m t n true  _     = round s (m ∸ n) 149
cancelB s m t n false true  = round t (n ∸ m) 149
cancelB s m t n false false = zeroF

addFin : Bool → ℕ → Bool → ℕ → Float32
addFin false m false n = round false (m + n) 149
addFin true  m true  n = round true (m + n) 149
addFin s     m t     n = cancelB s m t n (n <ᵇ m) (m <ᵇ n)

addK : Float32 → Float32 → Kind → Kind → Float32
addK x y nan       _         = nanF
addK x y (inf s)   nan       = nanF
addK x y (fin _ _) nan       = nanF
addK x y (inf s)   (inf t)   = if s xor t then nanF else x
addK x y (inf s)   (fin _ _) = x
addK x y (fin _ _) (inf t)   = y
addK x y (fin s m) (fin t n) = addFin s m t n

-- fpAdd sRNE, fpSub sRNE and fpMul sRNE.
add : Float32 → Float32 → Float32
add x y = addK x y (classify x) (classify y)

sub : Float32 → Float32 → Float32
sub x y = add x (neg y)

mulK : Kind → Kind → Float32
mulK nan       _         = nanF
mulK (inf s)   nan       = nanF
mulK (fin _ _) nan       = nanF
mulK (inf s)   (inf t)   = infF (s xor t)
mulK (inf s)   (fin t n) = if n ≡ᵇ 0 then nanF else infF (s xor t)
mulK (fin s m) (inf t)   = if m ≡ᵇ 0 then nanF else infF (s xor t)
mulK (fin s m) (fin t n) = round (s xor t) (m * n) 298   -- units of 2^-149 * 2^-149

mul : Float32 → Float32 → Float32
mul x y = mulK (classify x) (classify y)

-- ---------------------------------------------------------------------------------------------
-- Comparisons

-- Not both zero.
someNonZero : ℕ → ℕ → Bool
someNonZero zero zero = false
someNonZero _    _    = true

-- Two finite values, by sign and magnitude; -0 and +0 are equal.
ltSM : Bool → ℕ → Bool → ℕ → Bool
ltSM false m false n = m <ᵇ n
ltSM true  m true  n = n <ᵇ m
ltSM true  m false n = someNonZero m n
ltSM false m true  n = false

ltK : Kind → Kind → Bool
ltK nan       _         = false
ltK (inf _)   nan       = false
ltK (fin _ _) nan       = false
ltK (inf s)   (inf t)   = s ∧ not t
ltK (inf s)   (fin _ _) = s
ltK (fin _ _) (inf t)   = not t
ltK (fin s m) (fin t n) = ltSM s m t n

-- SBV's .<, .<=, .>, .>= and .== on SFloat.
lt le gt ge feq : Float32 → Float32 → Bool
lt x y  = ltK (classify x) (classify y)
le x y  = not (isNaN x) ∧ not (isNaN y) ∧ not (lt y x)
gt x y  = lt y x
ge x y  = le y x
feq x y = not (isNaN x) ∧ not (isNaN y) ∧ not (lt x y) ∧ not (lt y x)

-- maxNum and minNum. `z` chooses the answer for operands that compare equal (+0 and -0).
fmaxB fminB : Bool → Float32 → Float32 → Bool → Bool → Bool → Bool → Float32
fmaxB z x y true  _     _     _     = y
fmaxB z x y false true  _     _     = x
fmaxB z x y false false true  _     = y
fmaxB z x y false false false true  = x
fmaxB z x y false false false false = if z then x else y
fminB z x y true  _     _     _     = y
fminB z x y false true  _     _     = x
fminB z x y false false true  _     = x
fminB z x y false false false true  = y
fminB z x y false false false false = if z then x else y

fmax fmin : Bool → Float32 → Float32 → Float32
fmax z x y = fmaxB z x y (isNaN x) (isNaN y) (lt x y) (lt y x)
fmin z x y = fminB z x y (isNaN x) (isNaN y) (lt x y) (lt y x)

-- ---------------------------------------------------------------------------------------------
-- Integers

-- One in units of 2^-149. It is opaque: a term such as (suc q) * U would otherwise unfold into
-- 2^149 + q * U when Agda compares terms, and then into 2^149 applications of `suc`. Proofs
-- use `U≡`; computations unfold it (`PortAudit.Float32Examples`).
opaque
  U : ℕ
  U = 2 ^ 149

  U≡ : U ≡ 2 ^ 149
  U≡ = refl

applySign : Bool → ℤ → ℤ
applySign false z = z
applySign true  z = ℤ.- z

-- Rust's `x as i32` (SBV's fromSFloat sRTZ) for a finite x: truncation toward zero. Outside
-- (-2^31, 2^31) Rust saturates; the statements keep x inside, so the other kinds give 0.
toI32K : Kind → ℤ
toI32K (fin s m) = applySign s (+ (m /2^ 149))
toI32K _         = + 0

toI32 : Float32 → ℤ
toI32 x = toI32K (classify x)

-- Rust's `t as f32` (SBV's toSFloat sRNE): an integer rounded to nearest even; 0 is +0.
fromI32 : ℤ → Float32
fromI32 (+ n)      = round false (n * U) 149
fromI32 -[1+ n ]   = round true (suc n * U) 149

data Mode : Set where
  RNA RTN : Mode

-- The integer magnitude of (-1)^s * (q + r / U), 0 ≤ r < U, rounded in the mode.
intRound : Mode → Bool → ℕ → ℕ → ℕ
intRound RNA s     q r = q + bitN (U ≤ᵇ 2 * r)
intRound RTN false q r = q
intRound RTN true  q r = q + bitN (0 <ᵇ r)

-- fpRoundToIntegral: an integer keeps the sign of x, so -0.3 gives -0.
roundToIntegralK : Mode → Float32 → Kind → Float32
roundToIntegralK md x nan       = nanF
roundToIntegralK md x (inf _)   = x
roundToIntegralK md x (fin s m) = round s (intRound md s (m /2^ 149) (m %2^ 149) * U) 149

roundToIntegral : Mode → Float32 → Float32
roundToIntegral md x = roundToIntegralK md x (classify x)
