-- | The invariants of the video script, as Haskell. This module is the twin of
-- ../z3/video.py, name for name, so that the spec check in
-- app/Main.hs can compare the two. The owner gave the requirements on 2026-11-09:
--
--   * R1. The reward is the input of the user: 'User'.
--   * R2. One arm: to exploit shows pi(N) again, to explore computes pi(N+1): 'step'.
--   * R3. The whole A/B test is one decision rule: 'etc'.
--   * R4. RSI is the same rule, applied to itself: 'outer', 'inner'.
--   * R5. The two series of pi have positive terms: 'leibnizPair', 'ramanujanTerm'.
--
-- All arithmetic is exact ('Rational'), as in the Z3. Thus the spec check compares
-- values with (==).
module Video
  ( -- * R1. The user is the reward
    User (..), byDistance, clip, dist
    -- * R2. One arm
  , Action (..), OneArm (..), step
    -- * R3. Explore, then commit
  , etc
    -- * R4. The loop applied to itself
  , outer, inner
    -- * R5. The series of pi, as symbols
  , leibnizTerm, leibniz, leibnizPair, leibnizEven
  , factorial, ramanujanTerm, ramanujanSum
  ) where

import ContextualBandit

------------------------------------------------------------------------
-- R1. The reward is the input of the user

-- | A user grades each thing shown with a number in [0, 1]. (Z3: @by_distance@, which
-- also carries the proof of the bounds.)
newtype User shown = User { grade :: shown -> Rational }

-- | @clip x@ is @x@ brought into [0, 1]. (Z3: @clip@)
clip :: Rational -> Rational
clip = max 0 . min 1

-- | @dist a b@ is |a − b|. (Z3: @dist@, written without @abs@)
dist :: Rational -> Rational -> Rational
dist a b = abs (a - b)

-- | The simulated user of the video: the grade of @x@ is @1 − |x − target|@, clipped.
-- (Z3: @by_distance@)
byDistance :: Rational -> User Rational
byDistance target = User (\x -> clip (1 - dist x target))

------------------------------------------------------------------------
-- R2. One arm: exploit shows pi(N) again, explore computes pi(N+1)

data Action = Exploit | Explore
  deriving (Eq, Show)

-- | The state of the one-armed agent. (Z3: the triple @n, shown, last_reward@)
data OneArm = OneArm
  { terms      :: Int       -- ^ N: how many terms the agent has paid for
  , shown      :: Rational  -- ^ pi(N), the approximation the user has seen
  , lastGrade  :: Rational  -- ^ what the user said about it
  }
  deriving (Eq, Show)

-- | One round. @approx n@ is the approximation of pi with @n@ terms.
--
-- To exploit changes nothing: the agent shows pi(N) again and hears the same grade.
-- To explore pays one term, shows pi(N+1), and keeps the new grade when it is not
-- lower. Z3 proves exactly this: @step_exploit@, @step_explore_n@,
-- @step_explore_reward@, @step_reward_bounded@.
step :: (Int -> Rational) -> User Rational -> OneArm -> Action -> OneArm
step _      _    agent Exploit = agent
step approx user agent Explore
  | newGrade >= lastGrade agent = agent { terms = n, shown = candidate, lastGrade = newGrade }
  | otherwise                   = agent { terms = n }
  where
    n         = terms agent + 1
    candidate = approx n
    newGrade  = grade user candidate

------------------------------------------------------------------------
-- R3. Explore, then commit: the whole A/B test as one rule

-- | @etc horizon t@ is the rule of an A/B test at round @t@: uniform (ε = 1) before
-- the @horizon@, greedy (ε = 0) from it on. (Z3: @etc@, with @etc_before@ and
-- @etc_after@)
etc :: Int -> Int -> DecisionRule
etc horizon t
  | t < horizon = epsGreedy 1
  | otherwise   = epsGreedy 0

------------------------------------------------------------------------
-- R4. RSI: the outer agent selects the ε of the inner agent, with the same rule

-- | The outer agent. Each of its arms is one candidate ε for the inner agent. (Z3: @outer@)
outer :: Double -> DecisionRule
outer = epsGreedy

-- | The inner agent, after the outer agent selected the arm @i@. (Z3: @inner_eps@)
inner :: [Double] -> Arm -> DecisionRule
inner epsilons i = epsGreedy (epsilons !! i)

------------------------------------------------------------------------
-- R5. The series of pi, as symbols. Z3 proves that each Leibniz pair and each
-- Ramanujan term is positive. Thus the even Leibniz sums increase, the Ramanujan sums
-- increase, and the Ramanujan approximation of pi decreases towards pi.

-- | Leibniz (1674):  π = 4 · Σ_{k ≥ 0} (−1)^k / (2k + 1).  This is the k-th term, times 4.
leibnizTerm :: Int -> Rational
leibnizTerm k = 4 * (-1) ^ k / (2 * fromIntegral k + 1)

-- | The first @n@ terms of Leibniz, summed. (Z3: @leibniz@)
leibniz :: Int -> Rational
leibniz n = sum (map leibnizTerm [0 .. n - 1])

-- | Two consecutive terms of Leibniz, times 4:  4/(4k + 1) − 4/(4k + 3) > 0.  (Z3: @leibniz_pair@)
leibnizPair :: Int -> Rational
leibnizPair k = 4 / (4 * k' + 1) - 4 / (4 * k' + 3)
  where k' = fromIntegral k

-- | The even partial sums of Leibniz, as a sum of @k@ pairs. (Z3: @leibniz_even@)
leibnizEven :: Int -> Rational
leibnizEven k = sum (map leibnizPair [0 .. k - 1])

factorial :: Int -> Integer
factorial n = product [1 .. toInteger n]

-- | Ramanujan (1914):
--
-- >  1/π = (2√2 / 9801) · Σ_{k ≥ 0} (4k)! (1103 + 26390 k) / ((k!)^4 · 396^(4k))
--
-- This is the k-th term of the sum, without the constant in front. (Z3: @ramanujan_term@)
ramanujanTerm :: Int -> Rational
ramanujanTerm k = fromInteger numerator' / fromInteger denominator'
  where
    numerator'   = factorial (4 * k) * (1103 + 26390 * toInteger k)
    denominator' = factorial k ^ (4 :: Int) * 396 ^ (4 * k)

-- | The first @n@ terms of Ramanujan's sum. (Z3: @ram_sums@)
ramanujanSum :: Int -> Rational
ramanujanSum n = sum (map ramanujanTerm [0 .. n - 1])
