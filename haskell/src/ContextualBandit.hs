-- | Contextual bandit interface. This is a direct port of the Z3 spec in
-- ../z3-scala/src/main/scala/bandit/domain/Bandit.scala; ../z3-scala/src/main/scala/bandit/domain/Theorems.scala says what Z3 proves about it.
--
-- There are two layers:
--   * 'RewardModel': the probabilistic part (belief, update, estimate, sample)
--   * 'DecisionRule': the bandit part (estimates -> distribution over arms)
--
-- It depends only on GHC's @base@ and @containers@.
--
-- The @{-\@ ... \@-}@ comments are LiquidHaskell refinement types: GHC skips them,
-- and @just liquid@ checks them (../LIQUIDHASKELL.md lists what they prove
-- and what they trust).
module ContextualBandit
  ( -- * Interface (mirrors the two layers of z3-scala/src/main/scala/bandit/domain/Bandit.scala)
    Arm, Obs (..), Estimate (..), RewardModel (..), Decision, DecisionRule
  , posterior, policy
    -- * Decision rules (mirror the rules of z3-scala/src/main/scala/bandit/domain/Bandit.scala)
  , argmax, point, uniform, mix, ucbScore
  , greedy, ucb, epsGreedy
    -- * Thompson sampling (needs the model's posterior sampler)
  , thompsonArm
    -- * Acting in the world
  , act, Agent (..), runAgent
    -- * Randomness
  , Rand, runRand, uniform01, normal, gamma, beta, categorical
  ) where

import Data.Bits (shiftR, xor)
import qualified Data.List as L
import Data.Word (Word64)

------------------------------------------------------------------------
-- Trusted facts about libm, which LiquidHaskell cannot check. Each holds for IEEE
-- doubles with correct rounding, NaN aside.

{-@ assume sqrt :: Floating a => x:{a | x >= 0} -> {v:a | v >= 0 && (x > 0 => v > 0)} @-}
{-@ assume log :: Floating a => x:{a | x > 0} -> {v:a | x <= 1 => v <= 0} @-}
{-@ assume (**) :: Floating a => x:{a | x >= 0} -> a -> {v:a | v >= 0} @-}

------------------------------------------------------------------------
-- Interface

-- | Arms are @0 .. k-1@ (Z3: a Python index @0 .. K-1@).
type Arm = Int

data Obs c = Obs { obsContext :: c, obsArm :: Arm, obsReward :: Double }
  deriving Show

-- | What the model reports for one (context, arm). @width >= 0@.
{-@ data Estimate = Estimate { mean :: Double, width :: Double } @-}
data Estimate = Estimate { mean :: Double, width :: Double }
  deriving Show

-- | A probabilistic reward model with belief state @b@.
--
-- 'sample' draws a plausible mean reward from the posterior. Only Thompson
-- sampling uses it. Models that can't sample can use @\\b c a -> pure (mean ...)@.
data RewardModel c b = RewardModel
  { numArms  :: Int
  , prior    :: b
  , update   :: b -> Obs c -> b
  , estimate :: b -> c -> Arm -> Estimate
  , sample   :: b -> c -> Arm -> Rand Double
  }

-- | Probability of each arm, indexed by arm (Z3: one real per arm).
type Decision = [Double]

-- | A probability. LiquidHaskell reads 'Double' as a real number.
{-@ type Prob = {p:Double | 0 <= p && p <= 1} @-}

-- | A list of estimates with at least one arm.
{-@ type Arms = {est:[Estimate] | len est > 0} @-}

-- | Z3: a function from the list of estimates to the list of probabilities. It never sees context or history.
type DecisionRule = [Estimate] -> Decision

posterior :: RewardModel c b -> [Obs c] -> b
posterior m = L.foldl' (update m) (prior m)

-- | @history -> context -> distribution over arms@ (Z3: @policy@ in Examples.scala).
policy :: RewardModel c b -> DecisionRule -> [Obs c] -> c -> Decision
policy m rule h c = rule [estimate m b c a | a <- [0 .. numArms m - 1]]
  where b = posterior m h

------------------------------------------------------------------------
-- Decision rules

-- | First index with the largest score (same tie-break as Z3's @argmaxFirst@).
{-@ argmax :: xs:{[Double] | len xs > 0} -> {v:Nat | v < len xs} @-}
argmax :: [Double] -> Arm
argmax [] = error "argmax: no arms"
argmax (x : xs) = go 0 x 1 xs
  where
    {-@ go :: best:Nat -> Double -> i:{Nat | best < i} -> ys:[Double]
           -> {v:Nat | v < i + len ys} / [len ys] @-}
    go :: Int -> Double -> Int -> [Double] -> Int
    go best _ _ [] = best
    go best bv i (y : ys)
      | bv < y    = go i y (i + 1) ys
      | otherwise = go best bv (i + 1) ys

{-@ point :: Int -> Arm -> [Prob] @-}
point :: Int -> Arm -> Decision
point k b = [if a == b then 1 else 0 | a <- [0 .. k - 1]]

{-@ uniform :: k:{Int | k > 0} -> {v:[Prob] | len v = k} @-}
uniform :: Int -> Decision
uniform k = replicate k (1 / fromIntegral k)

{-@ mix :: {w:Double | 0 <= w && w <= 1} -> [Prob] -> [Prob] -> [Prob] @-}
mix :: Double -> Decision -> Decision -> Decision
mix w = zipWith (\p q -> w * p + (1 - w) * q)

ucbScore :: Double -> Estimate -> Double
ucbScore b e = mean e + b * width e

{-@ greedy :: Arms -> [Prob] @-}
greedy :: DecisionRule
greedy est = point (length est) (argmax (map mean est))

-- | With a Bayesian linear model this is LinUCB.
{-@ ucb :: Double -> Arms -> [Prob] @-}
ucb :: Double -> DecisionRule
ucb b est = point (length est) (argmax (map (ucbScore b) est))

{-@ epsGreedy :: {eps:Double | 0 <= eps && eps <= 1} -> Arms -> [Prob] @-}
epsGreedy :: Double -> DecisionRule
epsGreedy eps est = mix eps (uniform k) (greedy est)
  where k = length est

-- | Thompson sampling: draw one mean per arm from the posterior, take argmax.
-- Not checked: LiquidHaskell does not see that 'mapM' keeps the length, and nothing
-- stops @numArms m = 0@, where 'argmax' fails.
{-@ ignore thompsonArm @-}
thompsonArm :: RewardModel c b -> b -> c -> Rand Arm
thompsonArm m b c = argmax <$> mapM (sample m b c) [0 .. numArms m - 1]

------------------------------------------------------------------------
-- Acting

-- | An agent is "model + how to pick an arm".
data Agent c b = Agent
  { agentName  :: String
  , agentModel :: RewardModel c b
  , chooseArm  :: b -> c -> Rand Arm
  }

-- | Turn a 'DecisionRule' into an arm choice by sampling its distribution.
act :: RewardModel c b -> DecisionRule -> b -> c -> Rand Arm
act m rule b c = categorical (rule [estimate m b c a | a <- [0 .. numArms m - 1]])

-- | Run an agent for a list of contexts against an environment
-- @env :: c -> Arm -> Rand Double@. Returns the final belief and the
-- per-round (arm, reward) log.
runAgent :: Agent c b -> (c -> Arm -> Rand Double) -> [c] -> Rand (b, [(Arm, Double)])
runAgent (Agent _ m choose) env = go (prior m) []
  where
    go b acc [] = pure (b, reverse acc)
    go b acc (c : cs) = do
      a <- choose b c
      r <- env c a
      go (update m b (Obs c a r)) ((a, r) : acc) cs

------------------------------------------------------------------------
-- A tiny pure RNG (SplitMix64), so there are no package dependencies.

newtype Rand a = Rand { unRand :: Word64 -> (a, Word64) }

instance Functor Rand where
  fmap f (Rand g) = Rand $ \s -> let (a, s') = g s in (f a, s')
instance Applicative Rand where
  pure a = Rand $ \s -> (a, s)
  Rand f <*> Rand g = Rand $ \s -> let (h, s1) = f s; (a, s2) = g s1 in (h a, s2)
instance Monad Rand where
  Rand g >>= k = Rand $ \s -> let (a, s') = g s in unRand (k a) s'

runRand :: Word64 -> Rand a -> a
runRand seed (Rand g) = fst (g seed)

nextWord :: Rand Word64
nextWord = Rand $ \s ->
  let s' = s + 0x9E3779B97F4A7C15
      z1 = (s' `xor` (s' `shiftR` 30)) * 0xBF58476D1CE4E5B9
      z2 = (z1 `xor` (z1 `shiftR` 27)) * 0x94D049BB133111EB
  in (z2 `xor` (z2 `shiftR` 31), s')

-- | Uniform in (0, 1]. The top value is 1 itself: for @w >> 11 = 2^53 - 1@ the sum
-- @2^53 - 0.5@ rounds to the even @2^53@.
-- Trusted: LiquidHaskell does not know the range of 'shiftR'.
{-@ assume uniform01 :: Rand {v:Double | 0 < v && v <= 1} @-}
uniform01 :: Rand Double
uniform01 = (\w -> (fromIntegral (w `shiftR` 11) + 0.5) / 9007199254740992) <$> nextWord

-- | Box-Muller.
{-@ normal :: Double -> Double -> Rand Double @-}
normal :: Double -> Double -> Rand Double
normal mu sigma = do
  u1 <- uniform01
  u2 <- uniform01
  pure (mu + sigma * sqrt (-2 * log u1) * cos (2 * pi * u2))

-- | Marsaglia-Tsang Gamma(shape, 1). The draw is positive when @k >= 1@. When
-- @k < 1@, @u ** (1 / k)@ can underflow to 0 (@0.5 ** 1000@ is about @1e-301@).
{-@ gamma :: k:{Double | k > 0} -> Rand {v:Double | v >= 0 && (k >= 1 => v > 0)}
          / [if k < 1 then 1 else 0] @-}
gamma :: Double -> Rand Double
gamma k
  | k < 1 = do g <- gamma (k + 1); u <- uniform01; pure (g * u ** (1 / k))
  | otherwise =
      -- d and c are bound under the guard, so that LiquidHaskell sees k >= 1 there.
      let d = k - 1 / 3
          c = 1 / sqrt (9 * d)
          -- Rejection sampling ends with probability 1, not after a bounded number of tries.
          {-@ lazy loop @-}
          {-@ loop :: Rand {v:Double | v > 0} @-}
          loop :: Rand Double
          loop = do
            x <- normal 0 1
            u <- uniform01
            let v = (1 + c * x) ^ (3 :: Int)
            -- Two ifs, not (&&): LiquidHaskell needs v > 0 to see that log v is defined.
            if v > 0
              then (if log u < 0.5 * x * x + d - d * v + d * log v then pure (d * v) else loop)
              else loop
      in loop

-- | Shapes of at least 1, so both draws are positive and @x + y@ is not 0.
{-@ beta :: {a:Double | a >= 1} -> {b:Double | b >= 1} -> Rand Prob @-}
beta :: Double -> Double -> Rand Double
beta a b = do x <- gamma a; y <- gamma b; pure (x / (x + y))

-- | Sample an index from a probability vector. It is an arm when the vector is not
-- empty; the last arm takes any mass that rounding leaves above the sum.
{-@ categorical :: ps:[Double]
                -> Rand {v:Int | v < len ps && (len ps > 0 => v >= 0)} @-}
categorical :: [Double] -> Rand Int
categorical ps = do
  u <- uniform01
  let {-@ go :: Double -> i:Nat -> rest:[Double]
             -> {v:Int | v >= i - 1 && v < i + len rest && (len rest > 0 => v >= i)}
             / [len rest] @-}
      go :: Double -> Int -> [Double] -> Int
      go _ i [] = i - 1
      go acc i (p : rest) = if u <= acc + p then i else go (acc + p) (i + 1) rest
  pure (go 0 0 ps)
