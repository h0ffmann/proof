{-# LANGUAGE DataKinds #-}

-- Z3 checks of chaceon, the Rust port of WAVEWATCH III, through SBV.
--
-- chaceon checks its Rust against the Fortran by `cmp` on whole runs and by captured calls. Those
-- show that the two agree on the inputs that ran. They cannot show a fact for every input, and
-- they cannot see a defect that both sides share. This module states such facts about chaceon's
-- code and asks Z3 for a counterexample. `unsat` means none exists. The audited commit is
-- `chaceonCommit`; every `file:line` below is at that commit.
--
-- Three groups:
--
-- * D. The division rewrite of `rust/tools/spirv_exact/src/main.rs:3-7`. An `f32` division
--   becomes an `f64` division rounded to `f32`, because Vulkan allows 2.5 ULP in `OpFDiv`. Here Z3
--   checks the integer facts over bit-vectors and the rounding facts over the reals;
--   agda/src/PortAudit/Division.agda and Rounding.agda prove them for every exponent and bound.
-- * U. Fortran's intrinsics in `rust/crates/ww3-kernels/src/util.rs`: `nint`, `floor`, `sign`. Z3
--   checks them over IEEE `f32` (its floating-point theory), so the check is about the bits Rust
--   computes.
-- * S. The time step of `W3SRCE` in `rust/crates/ww3-kernels/src/srce.rs`: the dynamic step, its
--   split into equal parts, the limited and implicit increments, and the spectrum that stays
--   non-negative (agda/src/PortAudit/TimeStep.agda has the parts over the reals).
--
-- Some checks expect a counterexample (`refutes`): they show that a hypothesis is needed, or that
-- the code allows more than its comment says. Each one says why.
--
--     tools/port-audit/run.sh chaceon
module Chaceon (chaceonCommit, title, statements) where

import Data.SBV
import Report (Statement (..))

chaceonCommit :: String
chaceonCommit = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe"

title :: String
title = "chaceon (Z3)"

-- Bits: A * 2^25 and M * B fit in 50, and the margin product in 99.
type W = SWord 100

bvs :: [String] -> Symbolic [W]
bvs = mapM sWord

reals :: [String] -> Symbolic [SReal]
reals = mapM sReal

dist :: SReal -> SReal -> SReal
dist u v = ite (u .>= v) (u - v) (v - u)

pow2 :: Num a => Int -> a
pow2 k = 2 ^ k

proves :: String -> Symbolic ([SBool], SBool) -> Statement
proves name = Proves name ""

refutes :: String -> String -> Symbolic ([SBool], SBool) -> Statement
refutes name why = Refutes name why

-- The significands and the odd midpoint of group D.
significands :: W -> W -> [SBool]
significands a b = [a .>= pow2 23, a .< pow2 24, b .>= pow2 23, b .< pow2 24]

oddMidpoint :: W -> [SBool]
oddMidpoint m = [m .>= pow2 24, m .< pow2 25, sTestBit m 0]

gapOf :: W -> W -> W
gapOf l r = ite (l .>= r) (l - r) (r - l)

-- f32 helpers for group U and S: Rust's `x as i32` inside (-2^31, 2^31) is fpToSBV with RTZ, and
-- `t as f32` is fpSignedToFP with RNE.
toI32 :: SFloat -> SInt32
toI32 = fromSFloat sRTZ

fromI32 :: SInt32 -> SFloat
fromI32 = toSFloat sRNE

inI32 :: SFloat -> [SBool]
inI32 x = [x .< big, x .> fpNeg big, sNot (fpIsNaN x)]
  where big = literal (2 ^ (31 :: Int)) :: SFloat

fsign :: SFloat -> SFloat -> SFloat
fsign mag s = ite (fpIsNegative s) (fpNeg (fpAbs mag)) (fpAbs mag)

statements :: [Statement]
statements =
  -- ==========================================================================================
  -- D. spirv_exact: f32 division through f64 (rust/tools/spirv_exact/src/main.rs:3-7, 57-64)
  --
  -- a = A * 2^ea, b = B * 2^eb with 24-bit significands A, B in [2^23, 2^24). The power of two is
  -- exact in the normal range, so the quotient is q = A / B, in (1/2, 2), against the f32 grid
  -- there. Its midpoints are m = M / 2^t with M odd in [2^24, 2^25): t = 25 on [1/2, 1), t = 24
  -- on [1, 2). So two values of t cover every normal quotient.
  concat
    [ [ proves ("no_tie (t = " ++ show t ++ ")") $ do
          [a, b, m] <- bvs ["A", "B", "M"]
          -- q = A/B equals m = M/2^t exactly when A * 2^t = M * B.
          pure (significands a b ++ oddMidpoint m, a * pow2 t ./= m * b)
      , proves ("margin (t = " ++ show t ++ ")") $ do
          [a, b, m] <- bvs ["A", "B", "M"]
          -- |q - m| >= m / 2^49  <=>  2^49 * |A 2^t - M B| >= M B   (divide by B 2^t > 0)
          let (l, r) = (a * pow2 t, m * b)
          pure (significands a b ++ oddMidpoint m, gapOf l r * pow2 49 .>= r)
      ]
    | t <- [24, 25 :: Int] ]
    ++
    -- The margin cannot be doubled: 2^48 in place of 2^49 fails, as in chaceon's Lean log.
    [ refutes "margin_2^48_fails (t = 25)" "the margin 2^-49 cannot be doubled" $ do
        [a, b, m] <- bvs ["A", "B", "M"]
        let (l, r) = (a * pow2 25, m * b)
        pure (significands a b ++ oddMidpoint m, gapOf l r * pow2 48 .>= r)
    -- Subnormal: a midpoint with fewer than 25 bits can be hit exactly (Lean's small_midpoint_ties).
    , refutes "no_tie_needs_normal" "subnormal results are not covered" $ do
        [a1, b1, m1] <- bvs ["a1", "b1", "m1"]
        pure ( [a1 .>= 1, a1 .< pow2 24, b1 .>= 1, b1 .< pow2 24, m1 .< pow2 24, sTestBit m1 0]
             , a1 * 2 ./= m1 * b1 )
    -- same_side: r within 5/2 * 2^-52 of q (Vulkan's 2.5 ULP on f64), and q keeps the margin from m.
    , proves "same_side" $ do
        (side, q, mid, r) <- sameSide (5 / 2)
        pure (side, (r .< mid) .== (q .< mid))
    , proves "same_side_not_tie" $ do
        (side, q, mid, r) <- sameSide (5 / 2)
        pure (side, r ./= mid .&& q ./= mid)
    -- An error of 8 * 2^-52 reaches the margin 2^-49 and can cross the midpoint: the margin is the limit.
    , refutes "same_side_8ulp_fails" "an error of 8 * 2^-52 can reach the midpoint" $ do
        (side, q, mid, r) <- sameSide 8
        pure (side, (r .< mid) .== (q .< mid))
    -- closer_lo: round to nearest between adjacent grid points lo < hi is the comparison with the midpoint.
    , proves "closer_lo" $ do
        [lo, hi, x] <- reals ["lo", "hi", "x"]
        pure ([lo .< hi], (dist x lo .< dist x hi) .== (x .< (lo + hi) / 2))
    ]
    ++
    -- ==========================================================================================
    -- U. Fortran intrinsics (rust/crates/ww3-kernels/src/util.rs), over IEEE f32.
    [ -- util.rs:21-31  nint: t = x as i32; frac = x - t; t+1 if frac >= 0.5, t-1 if frac <= -0.5.
      proves "nint = round half away (util.rs:21)" $ do
        x <- sFloat "x"
        let (t0, frac) = nintParts x
            half = 0.5
            nint = ite (frac .>= half) (t0 + 1) (ite (frac .<= fpNeg half) (t0 - 1) t0)
        pure (inI32 x, nint .== toI32 (fpRoundToIntegral sRNA x))
    , proves "nint_frac_exact (util.rs:24)" $ do
        x <- sFloat "x"
        let (t0, frac) = nintParts x
        pure (inI32 x, fpAdd sRNE (fromI32 t0) frac .== x)
      -- util.rs:34-37  floor: t = x as i32; t-1 if t > x.
    , proves "floor = round down (util.rs:34)" $ do
        x <- sFloat "x"
        let t0 = toI32 x
            floor' = ite (fromI32 t0 .> x) (t0 - 1) t0
        pure (inI32 x, floor' .== toI32 (fpRoundToIntegral sRTN x))
      -- util.rs:41-43  sign: the magnitude bits of a with the sign bit of b, as Fortran SIGN(A, B).
    , proves "sign = SIGN(A, B) (util.rs:41)" $ do
        [a, b] <- mapM sFloat ["a", "b"]
        pure ([sNot (fpIsNaN a), sNot (fpIsNaN b)], signBits a b .== sFloatAsSWord32 (fsign a b))
      -- gfortran keeps the sign of a negative zero B: SIGN(1., -0.) = -1. The bit copy does the same.
    , proves "sign_negative_zero" $ do
        [a, b] <- mapM sFloat ["a", "b"]
        pure ( [fpIsZero b, fpIsNegative b, sNot (fpIsNaN a), a .> 0]
             , sFloatAsSWord32 (fpNeg a) .== signBits a b )
    ]
    ++
    -- ==========================================================================================
    -- S. W3SRCE's time step (rust/crates/ww3-kernels/src/srce.rs), first over f32, then over the reals.
    [ -- srce.rs:619, 624, 629, 742: sp = (sp + einc).max(0.). Rust's f32::max returns the other
      -- operand for a NaN, as IEEE maxNum, so the spectrum stays >= 0 even after an overflow to NaN.
      proves "spectrum_nonneg (srce.rs:619)" $ do
        [sp, einc] <- mapM sFloat ["sp", "einc"]
        let updated = fpMax (fpAdd sRNE sp einc) 0
        pure ([], sNot (fpIsNaN updated) .&& updated .>= 0)
      -- srce.rs:617-618, the limited increment: einc2 = sign(min(dam, |einc1|), einc1). Rust's
      -- f32::min also drops a NaN operand. For dam >= 0 the step is at most dam, with einc1's sign.
    , proves "limited_step_le_dam (srce.rs:618)" $ do
        [einc, dam] <- mapM sFloat ["einc", "dam"]
        pure (damOk dam, fpAbs (limited einc dam) .<= dam)
    , proves "limited_step_sign (srce.rs:618)" $ do
        [einc, dam] <- mapM sFloat ["einc", "dam"]
        let einc2 = limited einc dam
        pure ( damOk dam ++ [sNot (fpIsNaN einc), sNot (fpIsZero einc)]
             , fpIsZero einc2 .|| (fpIsNegative einc2 .== fpIsNegative einc) )
      -- srce.rs:673: the tail sp(ik) = sp(ik-1) * fachfa + 0. The `+ 0.` turns a -0 into +0.
    , proves "tail_no_negative_zero (srce.rs:673)" $ do
        [sp, fachfa] <- mapM sFloat ["sp", "fachfa"]
        let tailV = fpAdd sRNE (fpMul sRNE sp fachfa) 0
        pure ([sp .>= 0, fachfa .>= 0], sNot (fpIsZero tailV .&& fpIsNegative tailV))
      -- --- Over the reals: the semi-implicit increment and the dynamic step.
      -- srce.rs:617, 623: einc1 = vs * dt / max(1, 1 - dt * vd). With dt >= 0 the denominator is
      -- >= 1, so the implicit step never exceeds the explicit one, whatever the sign of vd.
    , proves "implicit_le_explicit (srce.rs:617)" $ do
        [vs, vd, dt] <- reals ["vs", "vd", "dt"]
        let denom = ite (1 - dt * vd .>= 1) (1 - dt * vd) 1
        pure ([dt .>= 0], dist (vs * dt / denom) 0 .<= dist (vs * dt) 0)
      -- srce.rs:598-600: the limiter. afac = 1 / max(|vs / damax|, 1e-10);
      -- dt <= afac / max(1 + afac * min(vd, 0), 1e-10). Without the two clamps of 1e-10, and with
      -- vd <= 0 (the damping sign), the increment of this component is at most damax.
    , proves "limiter_bounds_increment (srce.rs:600)" $ do
        (lim, vs, vd, dt, damax, _) <- limiter
        pure (lim, dist (vs * dt / (1 - dt * vd)) 0 .<= damax)
      -- srce.rs:602: dt = dt.max(0.5). The floor of half a second can exceed the limiter's step.
    , refutes "limiter_vs_floor_0.5 (srce.rs:602)" "the 0.5 s floor wins over the limiter when the limit is smaller" $ do
        (lim, vs, vd, dt, damax, afac) <- limiter
        let limited' = afac / (1 + afac * vd)
        pure ( init lim ++ [dt .== ite (limited' .>= 0.5) limited' 0.5]
             , dist (vs * dt / (1 - dt * vd)) 0 .<= damax )
      -- srce.rs:604-605: idt = 1 + trunc(0.99 * rem / dt); dt' = rem / idt, with rem = dtg - dttot > 0.
    , proves "split_idt_ge_1 (srce.rs:604)" $ do
        (sp', _, _, _, idt) <- split'
        pure (sp', idt .>= 1)
    , proves "split_le_rem (srce.rs:605)" $ do
        (sp', rem', _, dtn, _) <- split'
        pure (sp', dtn .<= rem')
    , proves "split_le_dt/0.99 (srce.rs:605)" $ do
        (sp', _, dtl, dtn, _) <- split'
        pure (sp', dtn .<= dtl / 0.99)
    , refutes "split_le_dt (srce.rs:605)" "the 0.99 lets each equal part exceed the limited step by up to 1/0.99" $ do
        (sp', _, dtl, dtn, _) <- split'
        pure (sp', dtn .<= dtl)
      -- srce.rs:607-612: dt'' = max(dt', min(dtmin, rem)), dttot += dt''. Each pass moves dttot
      -- forward by at least min(dtmin, rem) and never past dtg.
    , proves "step_never_past_dtg (srce.rs:607)" $ do
        (st, rem', dtf, _) <- step
        pure (st, dtf .<= rem')
    , proves "step_progress (srce.rs:607)" $ do
        (st, _, dtf, least) <- step
        pure (st, dtf .>= least)
    ]
  where
    sameSide k = do
      [q, mid, r] <- reals ["q", "m", "r"]
      let margin = q - mid .>= mid / pow2 49 .|| mid - q .>= mid / pow2 49
      pure ( [q .> 0, mid .> 0, margin, r - q .<= q * k / pow2 52, q - r .<= q * k / pow2 52]
           , q, mid, r )
    nintParts x = let t0 = toI32 x in (t0, fpSub sRNE x (fromI32 t0))
    signBits a b = (sFloatAsSWord32 a .&. 0x7fffffff) .|. (sFloatAsSWord32 b .&. 0x80000000)
    damOk dam = [dam .>= 0, sNot (fpIsNaN dam)]
    limited einc dam = fsign (fpMin dam (fpAbs einc)) einc
    limiter = do
      [vs, vd, dt, damax, afac] <- reals ["vs", "vd", "dt", "damax", "afac"]
      pure ( [ damax .> 0, vs ./= 0, vd .<= 0, afac .== damax / dist vs 0, 1 + afac * vd .> 0
             , dt .>= 0, dt * (1 + afac * vd) .<= afac ]
           , vs, vd, dt, damax, afac )
    split' = do
      [rem', dtl, dtn] <- reals ["rem", "dtl", "dtn"]
      idt <- sInteger "idt"
      let ratio = 0.99 * rem' / dtl
          idtR = sFromIntegral idt :: SReal
      pure ( [rem' .> 0, dtl .>= 0.5, idtR - 1 .<= ratio, ratio .< idtR, dtn * idtR .== rem']
           , rem', dtl, dtn, idt )
    step = do
      (sp', rem', _, dtn, _) <- split'
      [dtmin, dtf] <- reals ["dtmin", "dtf"]
      let least = ite (dtmin .<= rem') dtmin rem'
      pure (sp' ++ [dtmin .> 0, dtf .== ite (dtn .>= least) dtn least], rem', dtf, least)
