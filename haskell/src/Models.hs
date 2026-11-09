-- | Three ways to plug a probabilistic model into the decision layer.
--
-- 1. 'betaBernoulli': conjugate model for 0/1 rewards and discrete contexts.
-- 2. 'bayesLinear': Bayesian linear regression per arm on context features.
--    With 'ucb' this is LinUCB; with 'thompsonArm' it is linear Thompson sampling.
-- 3. 'fromPredictor': wrap any external model (a trained classifier, a GP,
--    a PyMC/Stan posterior, an ensemble) that can return a predictive mean and
--    standard deviation for each arm.
module Models
  ( betaBernoulli, BetaBelief
  , bayesLinear, LinBelief
  , fromPredictor
  ) where

import qualified Data.Map.Strict as M
import ContextualBandit

------------------------------------------------------------------------
-- 1. Beta-Bernoulli

-- | (alpha, beta) per (context, arm). Missing entries mean the prior Beta(1,1).
type BetaBelief c = M.Map (c, Arm) (Double, Double)

-- | A Beta count: the prior's 1 plus the rewards seen, so at least 1.
{-@ type Count = {n:Double | n >= 1} @-}

-- | Not checked as a whole: 'Obs' lets a reward be any 'Double', and a reward outside
-- [0, 1] takes a count below 1 (then 'sqrt' gets a negative number). The two
-- helpers below are checked, under the condition that the reward is in [0, 1].
{-@ ignore betaBernoulli @-}
betaBernoulli :: Ord c => Int -> RewardModel c (BetaBelief c)
betaBernoulli k = RewardModel
  { numArms  = k
  , prior    = M.empty
  , update   = \b (Obs c a r) ->
      let (al, be) = M.findWithDefault (1, 1) (c, a) b
      in M.insert (c, a) (betaUpdate al be r) b
  , estimate = \b c a ->
      let (al, be) = M.findWithDefault (1, 1) (c, a) b
      in betaEstimate al be
  , sample   = \b c a -> let (al, be) = M.findWithDefault (1, 1) (c, a) b in beta al be
  }

-- | A 0/1 reward (or any reward in [0, 1]) keeps both counts at 1 or more.
{-@ betaUpdate :: Count -> Count -> {r:Double | 0 <= r && r <= 1} -> (Count, Count) @-}
betaUpdate :: Double -> Double -> Double -> (Double, Double)
betaUpdate al be r = (al + r, be + 1 - r)

-- | Posterior mean, a probability, and posterior std, not negative.
{-@ betaEstimate :: Count -> Count -> {e:Estimate | 0 <= mean e && mean e <= 1 && width e >= 0} @-}
betaEstimate :: Double -> Double -> Estimate
betaEstimate al be =
  let n = al + be
  in Estimate (al / n) (sqrt (al * be / (n * n * (n + 1))))   -- posterior std

------------------------------------------------------------------------
-- 2. Bayesian linear regression per arm (LinUCB / LinTS)

-- Small dense linear algebra on lists. That's enough for a handful of features.
type Vec = [Double]
type Mat = [[Double]]

dot :: Vec -> Vec -> Double
dot u v = sum (zipWith (*) u v)

mulMV :: Mat -> Vec -> Vec
mulMV m v = map (`dot` v) m

identity :: Int -> Mat
identity d = [[if i == j then 1 else 0 | j <- [1 .. d]] | i <- [1 .. d]]

scaleM :: Double -> Mat -> Mat
scaleM s = map (map (* s))

-- | Sherman-Morrison: (A + x xᵀ)⁻¹ from A⁻¹.
-- Not checked: denom is at least 1 only when A⁻¹ is positive semi-definite, which a
-- refinement over lists cannot state.
{-@ ignore shermanMorrison @-}
shermanMorrison :: Mat -> Vec -> Mat
shermanMorrison ainv x =
  let ax = mulMV ainv x
      denom = 1 + dot x ax
  in [[aij - ai * aj / denom | (aij, aj) <- zip row ax] | (row, ai) <- zip ainv ax]

-- | Cholesky factor L with L Lᵀ = M (M symmetric positive definite).
-- Not checked: LiquidHaskell does not see the length of @[0 .. n - 1]@, so it cannot
-- bound the indices of (!!), and ls refers to itself lazily.
{-@ ignore cholesky @-}
cholesky :: Mat -> Mat
cholesky m = ls
  where
    n = length m
    ls = [[entry i j | j <- [0 .. n - 1]] | i <- [0 .. n - 1]]
    l i j = ls !! i !! j
    entry i j
      | j > i     = 0
      | i == j    = sqrt (max 1e-12 (m !! i !! i - sum [l i k ^ (2 :: Int) | k <- [0 .. j - 1]]))
      | otherwise = (m !! i !! j - sum [l i k * l j k | k <- [0 .. j - 1]]) / l j j

-- | Per arm: A⁻¹ and b = Σ r x.
type LinBelief = [(Mat, Vec)]

-- Not checked: @bs !! a@ needs @a < k@, which 'Obs' and 'estimate' do not say, and
-- the width needs @x · A⁻¹ x >= 0@ (A⁻¹ positive semi-definite).
{-@ ignore bayesLinear @-}

-- | @bayesLinear k d phi lambda noise@: @d@-dimensional features @phi c@,
-- ridge / prior precision @lambda@, observation noise std @noise@ (which
-- scales the posterior covariance; for LinUCB fold the confidence scale into β).
bayesLinear :: Int -> Int -> (c -> Vec) -> Double -> Double -> RewardModel c LinBelief
bayesLinear k d phi lambda noise = RewardModel
  { numArms  = k
  , prior    = replicate k (scaleM (1 / lambda) (identity d), replicate d 0)
  , update   = \bs (Obs c a r) ->
      let x = phi c
      in [ if i == a then (shermanMorrison ainv x, zipWith (+) bv (map (* r) x)) else ab
         | (i, ab@(ainv, bv)) <- zip [0 ..] bs ]
  , estimate = \bs c a ->
      let (ainv, bv) = bs !! a
          x = phi c
          theta = mulMV ainv bv
      in Estimate (dot x theta) (noise * sqrt (dot x (mulMV ainv x)))
  , sample   = \bs c a -> do
      let (ainv, bv) = bs !! a
          theta = mulMV ainv bv
          l = cholesky (scaleM (noise * noise) ainv)
      z <- mapM (const (normal 0 1)) theta
      pure (dot (phi c) (zipWith (+) theta (mulMV l z)))
  }

------------------------------------------------------------------------
-- 3. Any external predictive model

-- | Wrap a model you already have. @predict c a@ returns its predictive
-- (mean, std) for arm @a@ in context @c@. @retrain@ folds in new data. Pass
-- @const@ for a frozen, offline-trained model. Sampling assumes a Gaussian
-- predictive.
fromPredictor
  :: Int
  -> s                          -- ^ model state, e.g. weights or a handle
  -> (s -> Obs c -> s)          -- ^ online update (use @const@ if frozen)
  -> (s -> c -> Arm -> (Double, Double))  -- ^ predictive mean and std
  -> RewardModel c s
fromPredictor k s0 retrain predict = RewardModel
  { numArms  = k
  , prior    = s0
  , update   = retrain
  , estimate = \s c a -> let (m, sd) = predict s c a in Estimate m sd
  , sample   = \s c a -> let (m, sd) = predict s c a in normal m sd
  }
