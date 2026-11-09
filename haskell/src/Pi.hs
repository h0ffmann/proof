-- | Three ways to compute pi, exactly. They are the arms of the simple example of the
-- video (papers/contextual-bandits/roteiro/, scenes 1.3 and 1.4).
--
--   * Leibniz (Gottfried Wilhelm Leibniz, 1674). About 10^n terms for n digits.
--   * Gauss-Legendre (Carl Friedrich Gauss, "the prince of mathematicians", 1799; the
--     algorithm as Brent and Salamin wrote it, 1976). The digits double at each step.
--   * Ramanujan (Srinivasa Ramanujan, India, 1914; the owner calls him "the King of
--     Mathematicians", 2026-11-09). About 8 digits per term.
--
-- The terms of Leibniz and Ramanujan are the symbols of "Video" (the Lean twin). This
-- module adds what core Lean does not have: a square root, a decimal expansion, and
-- the count of correct digits. Every number is a 'Rational' at a fixed precision, so
-- every digit counted is a true digit. Run @cabal run video@ to see the table.
module Pi
  ( Series (..), leibnizSeries, gaussLegendreSeries, ramanujanSeries
  , approximation
  , digitsOfPi, digitsCorrect, decimal
  , sqrtRational
  ) where

import Data.Ratio (denominator, numerator, (%))
import qualified Video

-- | A series for pi: its name and its approximations, one per number of terms.
-- @approximations !! n@ uses @n@ terms; @approximations !! 0@ is 0, no term yet.
data Series = Series
  { name           :: String
  , approximations :: [Rational]  -- ^ infinite
  }

-- | The approximation of a series with @n@ terms.
approximation :: Series -> Int -> Rational
approximation series n = approximations series !! n

------------------------------------------------------------------------
-- The three series

-- | π = 4 · (1 − 1/3 + 1/5 − 1/7 + …)
leibnizSeries :: Series
leibnizSeries = Series "Leibniz" (partialSums (map Video.leibnizTerm [0 ..]))

-- | 1/π = (2√2 / 9801) · Σ (4k)! (1103 + 26390 k) / ((k!)^4 · 396^(4k))
ramanujanSeries :: Series
ramanujanSeries = Series "Ramanujan" (map invert (partialSums (map Video.ramanujanTerm [0 ..])))
  where
    constant = 2 * sqrtRational 2 / 9801
    invert 0 = 0
    invert s = 1 / (constant * s)

-- | Gauss-Legendre, by the arithmetic-geometric mean:
--
-- >  a₀ = 1,  b₀ = 1/√2,  t₀ = 1/4,  p₀ = 1
-- >  aₙ₊₁ = (aₙ + bₙ) / 2
-- >  bₙ₊₁ = √(aₙ bₙ)
-- >  tₙ₊₁ = tₙ − pₙ (aₙ − aₙ₊₁)²
-- >  pₙ₊₁ = 2 pₙ
-- >  π ≈ (aₙ + bₙ)² / (4 tₙ)
gaussLegendreSeries :: Series
gaussLegendreSeries = Series "Gauss-Legendre" (0 : map piFrom (tail (iterate next start)))
  where
    start = AGM 1 (sqrtRational (1 % 2)) (1 % 4) 1
    next (AGM a b t p) = AGM a' (sqrtRational (a * b)) (t - p * (a - a') ^ (2 :: Int)) (2 * p)
      where a' = (a + b) / 2
    piFrom (AGM a b t _) = (a + b) ^ (2 :: Int) / (4 * t)

-- | The four numbers of the arithmetic-geometric mean: a, b, t, p.
data AGM = AGM Rational Rational Rational Rational

-- | 0, x₀, x₀ + x₁, …
partialSums :: [Rational] -> [Rational]
partialSums = scanl (+) 0

------------------------------------------------------------------------
-- Digits

-- | π to 60 decimals, the reference of 'digitsCorrect'.
digitsOfPi :: String
digitsOfPi = "3.141592653589793238462643383279502884197169399375105820974944"

-- | How many decimal digits 'sqrtRational' and 'decimal' keep.
precision :: Int
precision = 70

-- | √x to 'precision' decimals, by Newton's method on integers.
sqrtRational :: Rational -> Rational
sqrtRational x = integerSqrt (numerator x * scale * scale `div` denominator x) % scale
  where
    scale = 10 ^ precision
    integerSqrt 0 = 0
    integerSqrt n = go n
      where
        go guess
          | better >= guess = guess
          | otherwise       = go better
          where better = (guess + n `div` guess) `div` 2

-- | @x@ as a decimal string with 'precision' digits after the point, truncated.
decimal :: Rational -> String
decimal x = show whole ++ "." ++ padLeft (show fraction)
  where
    (whole, fraction) = floor (x * 10 ^ precision) `divMod` (10 ^ precision :: Integer)
    padLeft s = replicate (precision - length s) '0' ++ s

-- | The number of leading digits of @x@ that agree with π. The 3 counts; the point does not.
digitsCorrect :: Rational -> Int
digitsCorrect x = length (filter (/= '.') agreeing)
  where agreeing = map fst (takeWhile (uncurry (==)) (zip digitsOfPi (decimal x)))
