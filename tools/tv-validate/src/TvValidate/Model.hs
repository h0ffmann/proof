-- The two JCS models of tv-audience/python/experiment.py as values of `Model` of
-- agda/src/TvAudience/Pipeline.agda (TvAudience.hs), with Double, `exp` and `tanh`, and the
-- loss that `fit_logit` minimises, written for any number type so that `ad` differentiates it.
module TvValidate.Model
  ( standardiser, standardise, jcsModel, nsModel, slotIn, utilities
  , logitLoss, logitGradient, residualGradient, bySlot
  ) where

import qualified Data.IntMap.Strict as IM
import Data.List (transpose)
import qualified Data.Vector.Unboxed as U
import Numeric.AD (auto, grad)

import qualified TvAudience as A
import TvValidate.Load

-- `mu, sd = X.mean(0), X.std(0) + 1e-9` of the training design, as fit_logit computes them.
standardiser :: [ShareRow] -> ([Double], [Double])
standardiser rows = (mu, sd)
  where
    n = fromIntegral (length rows)
    d = U.length (sX (firstOf rows))
    zero = U.replicate d 0
    total = foldl' (\acc r -> U.zipWith (+) acc (sX r)) zero rows
    muV = U.map (/ n) total
    sq = foldl' (\acc r -> U.zipWith3 (\a m x -> a + (x - m) * (x - m)) acc muV (sX r)) zero rows
    mu = U.toList muV
    sd = map (\v -> sqrt (v / n) + 1e-9) (U.toList sq)

standardise :: ([Double], [Double]) -> ShareRow -> [Double]
standardise (mu, sd) r = zipWith3 (\m s x -> (x - m) / s) mu sd (U.toList (sX r))

-- JCS: the linear utility w·z + b, the network off (`jcsParams` of Neural.agda).
jcsModel :: Logit -> A.Model Double
jcsModel l = A.Model exp tanh (A.Ns (drop 1 (lW l)) (firstOf (lW l)) [] [] []) 0 []

-- Neurosymbolic JCS. NumPy holds W1 as (features x hidden); `dense` wants one row per unit.
nsModel :: NsWeights -> A.Model Double
nsModel n = A.Model exp tanh (A.Ns (nW n) (nB n) (transpose (nW1 n)) (nB1 n) (nW2 n)) 0 []

-- The pool model enters as its forecast: the level is log(pool_hat), and there are no trees.
slotIn :: Double -> [[Double]] -> A.SlotIn Double
slotIn ph = A.SlotIn (log ph) (const 0)

utilities :: A.Model Double -> [[Double]] -> [Double]
utilities m = map (A.nsUtility (A.act m) (A.params m))

-- The rows of each slot, in the order of the file.
bySlot :: [ShareRow] -> [a] -> [[(ShareRow, a)]]
bySlot rows xs = IM.elems (IM.fromListWith (flip (++)) [ (sSid r, [(r, x)]) | (r, x) <- zip rows xs ])

-- The mean loss of `nll` in fit_logit. With s_out = 1 - Σ s_obs, the loss of a slot is
-- log(1 + Σ exp u) - Σ s_obs u; `k` takes a Double of the data into the number type.
logitLoss :: Floating a => (Double -> a) -> Double -> [[(Double, [Double])]] -> [a] -> a
logitLoss _ _ _ [] = 0
logitLoss k l2 slots (w0 : ws) =
  (sum (map slot slots) + k l2 * sum (map (\x -> x * x) ws)) / k (fromIntegral (length slots))
  where
    u z = w0 + sum (zipWith (\wj zj -> wj * k zj) ws z)
    slot rows =
      let us = map (u . snd) rows
      in log (1 + sum (map exp us)) - sum (zipWith (\(s, _) ui -> k s * ui) rows us)

-- Its gradient by reverse-mode automatic differentiation (`ad`).
logitGradient :: Double -> [[(Double, [Double])]] -> [Double] -> [Double]
logitGradient l2 slots = grad (logitLoss auto l2 slots)

-- The gradient as fit_logit writes it by hand, with `resid` of Neural.agda (s - s_obs):
-- (Σ resid, Zᵀ resid + 2 l2 w) / n.
residualGradient :: Double -> [[(Double, [Double])]] -> [Double] -> [Double]
residualGradient _ _ [] = []
residualGradient l2 slots (w0 : ws) = map (/ n) (sum rs : zipWith (\g wj -> g + 2 * l2 * wj) zr ws)
  where
    n = fromIntegral (length slots)
    u z = w0 + sum (zipWith (*) ws z)
    slotResid rows = A.resid (A.jcsShares (map (exp . u . snd) rows)) (map fst rows)
    rs = concatMap slotResid slots
    zs = concatMap (map snd) slots
    zr = foldl' (\acc (r, z) -> zipWith (\a zj -> a + r * zj) acc z) (map (const 0) ws) (zip rs zs)
