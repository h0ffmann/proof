-- | The invariants of the video script. This is a port of
-- ../lean/ContextualBandit/Video.lean, name for name. The owner gave the requirements
-- on 2026-11-09:
--
--   R1. The reward is the input of the user ('User').
--   R2. Single-armed: exploitation shows pi(N), exploration computes pi(N+1) ('step').
--   R3. The full A/B test is one decision rule ('etc').
--   R4. RSI is the same rule, applied to itself ('outer', 'inner').
--   R5. The two series of pi have positive terms ('leibnizPair', 'ramTerm').
--
-- The arithmetic is exact ('Rational'), as in the Lean. Thus the spec check compares equal values.
module Video
  ( User (..), byDistance, clip, dist
  , Action (..), SA (..), exploreStep, step
  , etc
  , outer, inner
  , leibniz, leibnizPair, leibnizEven
  , fact, ramTerm, ramSum
  ) where

import Data.Ratio ((%))
import ContextualBandit

------------------------------------------------------------------------
-- R1. The reward is the user's input

-- | A user. The user gives a reward in [0, 1] for each thing shown. The Lean has the proof of the bounds.
newtype User shown = User { reward :: shown -> Rational }

-- | @x@ clipped to [0, 1] (Lean: @clip@).
clip :: Rational -> Rational
clip x | x < 0 = 0
       | 1 < x = 1
       | otherwise = x

-- | The distance between two rationals, without @abs@ (Lean: @dist@).
dist :: Rational -> Rational -> Rational
dist a b = if a <= b then b - a else a - b

-- | A user who gives a grade by the distance to a target (Lean: @byDistance@).
byDistance :: Rational -> User Rational
byDistance target = User (\s -> clip (1 - dist s target))

------------------------------------------------------------------------
-- R2. Single-armed: exploit = show pi(N) again, explore = compute pi(N+1)

data Action = Exploit | Explore deriving (Eq, Show)

-- | The state of the one-armed agent (Lean: @SA@).
data SA = SA { saN :: Int, saShown :: Rational, saLastReward :: Rational } deriving (Eq, Show)

-- | Lean: @exploreStep@. @approx k@ is the approximation with @k@ terms.
exploreStep :: (Int -> Rational) -> User Rational -> SA -> SA
exploreStep approx u s
  | saLastReward s <= r = SA (saN s + 1) c r
  | otherwise           = SA (saN s + 1) (saShown s) (saLastReward s)
  where c = approx (saN s + 1)
        r = reward u c

-- | Lean: @step@. The Lean proves: exploitation changes nothing; exploration adds one
-- term and does not decrease the recorded reward.
step :: (Int -> Rational) -> User Rational -> SA -> Action -> SA
step _ _ s Exploit = s
step approx u s Explore = exploreStep approx u s

------------------------------------------------------------------------
-- R3. Explore-then-commit: the whole A/B test as one rule (Lean: @etc@)

-- | Uniform in the first @t0@ rounds (@epsGreedy 1@). Greedy after them (@epsGreedy 0@).
etc :: Int -> Int -> DecisionRule
etc t0 t = if t < t0 then epsGreedy 1 else epsGreedy 0

------------------------------------------------------------------------
-- R4. RSI: the outer agent picks the inner agent's epsilon with the same rule

-- | Lean: @outer@. Each arm is one candidate epsilon for the inner agent.
outer :: Double -> DecisionRule
outer = epsGreedy

-- | Lean: @inner@. The rule of the inner agent after the outer agent selects arm @i@.
inner :: [Double] -> Arm -> DecisionRule
inner epsilons i = epsGreedy (epsilons !! i)

------------------------------------------------------------------------
-- Leibniz over Rational, exact (Lean: @leibniz@)

leibniz :: Int -> Rational
leibniz 0 = 0
leibniz n = leibniz (n - 1) + 4 * ((-1) ^ (n - 1) % (2 * fromIntegral (n - 1) + 1))

------------------------------------------------------------------------
-- R5. The two series as symbols (Lean: leibnizPair, leibnizEven, fact, ramTerm, ramSum).
-- The Lean proves: each Leibniz pair is positive, so the even sums increase; each
-- Ramanujan term is positive, so the sums increase and the approximation of pi decreases.

-- | One pair of Leibniz terms, times 4: 4/(4k+1) - 4/(4k+3).
leibnizPair :: Int -> Rational
leibnizPair k = 4 / (4 * fromIntegral k + 1) - 4 / (4 * fromIntegral k + 3)

-- | The even partial sums of Leibniz, as a sum of pairs.
leibnizEven :: Int -> Rational
leibnizEven 0 = 0
leibnizEven k = leibnizEven (k - 1) + leibnizPair (k - 1)

fact :: Int -> Integer
fact 0 = 1
fact n = fromIntegral n * fact (n - 1)

-- | One term of Ramanujan's series: (4k)! (1103 + 26390 k) / ((k!)^4 396^(4k)).
ramTerm :: Int -> Rational
ramTerm k = (fact (4 * k) * (1103 + 26390 * fromIntegral k)) % (fact k ^ (4 :: Int) * 396 ^ (4 * k))

-- | The partial sums of Ramanujan's series.
ramSum :: Int -> Rational
ramSum 0 = 0
ramSum n = ramSum (n - 1) + ramTerm (n - 1)
