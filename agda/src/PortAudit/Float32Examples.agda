{-# OPTIONS --safe --without-K #-}

-- Concrete cases of the f32 model (`PortAudit.Float32`), checked by computation (`refl`). Each
-- expected bit pattern is what an x86 or ARM `f32` operation gives, as Python's
-- `struct.pack('<f', ...)` of the exact result shows; they cover rounding at a tie, rounding
-- across a binade, overflow at the largest float, subnormal results and the signs of zero.
module PortAudit.Float32Examples where

open import Data.Bool using (true; false)
open import Data.Integer using (+_; -[1+_])
open import Relation.Binary.PropositionalEquality using (_≡_; refl)

open import PortAudit.Float32
open import PortAudit.Intrinsics using (nint; floor′)

private
  w : _ → Word32
  w n = fromℕ 32 n

-- The unit U is opaque in the model; these computations unfold it.
opaque
  unfolding U

  -- 0.1f + 0.2f = 0.3f (0x3e99999a), and 0.1f * 3 is the same float.
  point-one-plus-point-two : bits (add (ofWord 0x3DCCCCCD) (ofWord 0x3E4CCCCD)) ≡ w 0x3E99999A
  point-one-plus-point-two = refl

  point-one-times-three : bits (mul (ofWord 0x3DCCCCCD) (ofWord 0x40400000)) ≡ w 0x3E99999A
  point-one-times-three = refl

  -- 1 + 2^-24 is a tie and goes to the even neighbour, 1; 1 + 3 * 2^-24 goes up to 1 + 2^-22.
  one-plus-half-ulp : bits (add (ofWord 0x3F800000) (ofWord 0x33800000)) ≡ w 0x3F800000
  one-plus-half-ulp = refl

  one-plus-three-halves-ulp : bits (add (ofWord 0x3F800000) (ofWord 0x34400000)) ≡ w 0x3F800002
  one-plus-three-halves-ulp = refl

  -- 1 - 2^-25 is a tie between 1 - 2^-24 and 1, across the binade: it gives 1.
  one-minus-quarter-ulp : bits (sub (ofWord 0x3F800000) (ofWord 0x33000000)) ≡ w 0x3F800000
  one-minus-quarter-ulp = refl

  -- The largest float plus half its ULP (2^103) overflows; plus a quarter (2^102) it stays.
  max-plus-half-ulp : bits (add (ofWord 0x7F7FFFFF) (ofWord 0x73000000)) ≡ w 0x7F800000
  max-plus-half-ulp = refl

  max-plus-quarter-ulp : bits (add (ofWord 0x7F7FFFFF) (ofWord 0x72800000)) ≡ w 0x7F7FFFFF
  max-plus-quarter-ulp = refl

  -- Subnormal products: 0.5 of the smallest subnormal is a tie and gives +0; 0.75 of it gives it;
  -- 1.5 of it is a tie and gives 2 units.
  tiny-half : bits (mul (ofWord 0x00000001) (ofWord 0x3F000000)) ≡ w 0x00000000
  tiny-half = refl

  tiny-three-quarters : bits (mul (ofWord 0x00000001) (ofWord 0x3F400000)) ≡ w 0x00000001
  tiny-three-quarters = refl

  tiny-three-halves : bits (mul (ofWord 0x00000003) (ofWord 0x3F000000)) ≡ w 0x00000002
  tiny-three-halves = refl

  -- The signs of zero under RNE: -0 + -0 = -0, -0 + +0 = +0, 3 - 3 = +0, -0 * 5 = -0.
  neg-zero-plus-neg-zero : bits (add (ofWord 0x80000000) (ofWord 0x80000000)) ≡ w 0x80000000
  neg-zero-plus-neg-zero = refl

  neg-zero-plus-zero : bits (add (ofWord 0x80000000) (ofWord 0x00000000)) ≡ w 0x00000000
  neg-zero-plus-zero = refl

  three-minus-three : bits (sub (ofWord 0x40400000) (ofWord 0x40400000)) ≡ w 0x00000000
  three-minus-three = refl

  neg-zero-times-five : bits (mul (ofWord 0x80000000) (ofWord 0x40A00000)) ≡ w 0x80000000
  neg-zero-times-five = refl

  -- Infinity minus infinity and infinity times zero are NaN.
  inf-minus-inf : isNaN (sub (ofWord 0x7F800000) (ofWord 0x7F800000)) ≡ true
  inf-minus-inf = refl

  inf-times-zero : isNaN (mul (ofWord 0x7F800000) (ofWord 0x00000000)) ≡ true
  inf-times-zero = refl

  -- Comparisons: -0 < +0 is false, -0 <= +0 is true, NaN is not equal to itself.
  neg-zero-lt-zero : lt (ofWord 0x80000000) (ofWord 0x00000000) ≡ false
  neg-zero-lt-zero = refl

  neg-zero-le-zero : le (ofWord 0x80000000) (ofWord 0x00000000) ≡ true
  neg-zero-le-zero = refl

  nan-ne-nan : feq nanF nanF ≡ false
  nan-ne-nan = refl

  -- Integers: 2^24 + 1 rounds to 2^24; -2.5 truncates to -2, rounds away to -3 and down to -3;
  -- 2.5 rounds away to 3.
  from-2^24+1 : bits (fromI32 (+ 16777217)) ≡ w 0x4B800000
  from-2^24+1 = refl

  to-minus-two-and-a-half : toI32 (ofWord 0xC0200000) ≡ -[1+ 1 ]
  to-minus-two-and-a-half = refl

  rna-minus-two-and-a-half : bits (roundToIntegral RNA (ofWord 0xC0200000)) ≡ w 0xC0400000
  rna-minus-two-and-a-half = refl

  rtn-minus-two-and-a-half : bits (roundToIntegral RTN (ofWord 0xC0200000)) ≡ w 0xC0400000
  rtn-minus-two-and-a-half = refl

  rna-two-and-a-half : bits (roundToIntegral RNA (ofWord 0x40200000)) ≡ w 0x40400000
  rna-two-and-a-half = refl

  -- roundToIntegral keeps the sign of a result that is zero: RNA of -0.25 is -0.
  rna-minus-quarter : bits (roundToIntegral RNA (ofWord 0xBE800000)) ≡ w 0x80000000
  rna-minus-quarter = refl

  -- util.rs's nint and floor: nint(2.5) = 3, nint(-2.5) = -3, floor(-2.5) = -3, and
  -- nint(0.49999997) = 0, where adding 0.5 and truncating would give 1.
  nint-two-and-a-half : nint (ofWord 0x40200000) ≡ + 3
  nint-two-and-a-half = refl

  nint-minus-two-and-a-half : nint (ofWord 0xC0200000) ≡ -[1+ 2 ]
  nint-minus-two-and-a-half = refl

  floor-minus-two-and-a-half : floor′ (ofWord 0xC0200000) ≡ -[1+ 2 ]
  floor-minus-two-and-a-half = refl

  nint-below-half : nint (ofWord 0x3EFFFFFF) ≡ + 0
  nint-below-half = refl
