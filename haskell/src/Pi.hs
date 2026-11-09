-- | Three series for pi. They are the arms of the simple example of the video
-- (ROTEIRO.pt-BR.md, scenes 1.3 and 1.4). The arithmetic is exact (Rational) at a
-- fixed precision. Thus each digit is a true digit.
--
--   * Leibniz (Gottfried Wilhelm Leibniz, 1674): pi/4 = 1 - 1/3 + 1/5 - 1/7 + ...
--     The series gives n digits after about 10^n terms.
--   * Gauss-Legendre (Carl Friedrich Gauss, "the prince of mathematicians", 1799;
--     the algorithm is from Brent and Salamin, 1976). The number of digits doubles at
--     each step.
--   * Ramanujan (Srinivasa Ramanujan, India, 1914; the owner calls him "the King of
--     Mathematicians", 2026-11-09): 1/pi = (2 sqrt 2 / 9801) sum (4k)! (1103 + 26390 k) / ((k!)^4 396^(4k)).
--     Each term gives about 8 digits.
--
-- Core Lean has no real numbers. Thus this file has no Lean twin. The Lean file
-- ../../lean/ContextualBandit/Video.lean has the symbolic invariants of the series.
-- Run `cabal run video` to measure the digits.
module Pi
  ( Series (..), leibnizS, gaussLegendreS, ramanujanS
  , piDigits, digitsCorrect, showDigits
  , sqrtRat
  ) where

import Data.Ratio (numerator, denominator, (%))

-- | pi to 60 decimals. 'digitsCorrect' compares with this string.
piDigits :: String
piDigits = "3.141592653589793238462643383279502884197169399375105820974944"

-- | The precision of 'sqrtRat' and of the comparisons, in decimal digits.
precision :: Int
precision = 70

-- | The square root of a rational, to 'precision' digits. It uses the integer square root (Newton).
sqrtRat :: Rational -> Rational
sqrtRat x = isqrt (numerator x * scale * scale `div` denominator x) % scale
  where
    scale = 10 ^ precision
    isqrt :: Integer -> Integer
    isqrt 0 = 0
    isqrt n = go n
      where go g = let g' = (g + n `div` g) `div` 2 in if g' >= g then g else go g'

-- | A series. 'value' is the approximation with 'terms' terms. 'next' adds one term.
data Series = Series
  { seriesName :: String
  , terms      :: Int                 -- ^ the number of terms
  , value      :: Rational            -- ^ the approximation with that many terms
  , next       :: Series              -- ^ one more term
  }

leibnizS :: Series
leibnizS = go 0 0
  where
    go :: Int -> Rational -> Series
    go k s = Series "Leibniz" k (4 * s) (go (k + 1) (s + ((-1) ^ k) % (2 * fromIntegral k + 1)))

-- | Gauss-Legendre. Start: a0 = 1, b0 = 1/sqrt 2, t0 = 1/4, p0 = 1.
-- Step: a' = (a+b)/2, b' = sqrt(a b), t' = t - p (a - a')^2, p' = 2p. Then pi ~ (a+b)^2 / (4t).
gaussLegendreS :: Series
gaussLegendreS = go 0 1 (sqrtRat (1 % 2)) (1 % 4) 1
  where
    go :: Int -> Rational -> Rational -> Rational -> Rational -> Series
    go k a b t p =
      Series "Gauss-Legendre" k (if k == 0 then 0 else (a + b) ^ (2 :: Int) / (4 * t)) (go (k + 1) a' b' t' (2 * p))
      where a' = (a + b) / 2
            b' = sqrtRat (a * b)
            t' = t - p * (a - a') ^ (2 :: Int)

ramanujanS :: Series
ramanujanS = go 0 0
  where
    factor = 2 * sqrtRat 2 / 9801
    go :: Int -> Rational -> Series
    go k s = Series "Ramanujan" k (if k == 0 then 0 else 1 / (factor * s)) (go (k + 1) (s + term k))
    term k = (fact (4 * k) * (1103 + 26390 * fromIntegral k)) % ((fact k ^ (4 :: Int)) * 396 ^ (4 * k))
    fact n = product [1 .. fromIntegral n] :: Integer

-- | The approximation as a decimal string, with 'precision' digits after the point.
showDigits :: Rational -> String
showDigits x = show whole ++ "." ++ pad (show frac)
  where
    scaled = floor (x * 10 ^ precision) :: Integer
    (whole, frac) = scaled `divMod` (10 ^ precision)
    pad s = replicate (precision - length s) '0' ++ s

-- | The number of leading digits that agree with pi. The count includes the 3 and not the point.
digitsCorrect :: Rational -> Int
digitsCorrect x = length [c | (c, _) <- takeWhile (uncurry (==)) (zip piDigits (showDigits x)), c /= '.']
