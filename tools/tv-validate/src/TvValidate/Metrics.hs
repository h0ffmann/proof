{-# LANGUAGE OverloadedStrings #-}

-- Every number that `evaluate` of tv-audience/python/experiment.py writes for one model,
-- computed again from the forecasts with the definitions of agda/src/TvAudience/ (TvAudience.hs):
-- `wape`, `winner`, `accuracy`, `countOver`. The bootstrap uses the day resamples that export.py
-- drew from the experiment's generator and seed; the percentile is NumPy's default (linear).
module TvValidate.Metrics (Score (..), scores, slotsOf, percentile) where

import qualified Data.IntMap.Strict as IM
import Data.List (sort)
import qualified Data.Map.Strict as M
import Data.Text (Text)

import qualified TvAudience as A
import TvValidate.Load

data Score = Count Int | Value Double | Interval Double Double deriving (Show)

-- The rows of each slot, in the order of the file (pandas' idxmax takes the first largest).
slotsOf :: [TestRow] -> [[TestRow]]
slotsOf rs = IM.elems (IM.fromListWith (flip (++)) [ (sid r, [r]) | r <- rs ])

-- numpy.percentile(xs, q), method "linear".
percentile :: Double -> [Double] -> Double
percentile q xs = a + (b - a) * (h - fromIntegral i)
  where
    s = sort xs
    h = fromIntegral (length s - 1) * q / 100
    i = floor h :: Int
    a = s !! i
    b = s !! min (i + 1) (length s - 1)

-- Sums of one day: |y - p|, |y| and |y - ref| over all its rows, and over its big shows.
data Sums = Sums !Double !Double !Double !Double !Double !Double

instance Semigroup Sums where
  Sums a b c d e f <> Sums a' b' c' d' e' f' = Sums (a + a') (b + b') (c + c') (d + d') (e + e') (f + f')

instance Monoid Sums where
  mempty = Sums 0 0 0 0 0 0

-- `p` is the model's forecast of a row and `ref` the forecast of XGBoost + rivals.
scores :: [[Int]] -> (TestRow -> Double) -> (TestRow -> Double) -> [TestRow] -> M.Map Text Score
scores picks ref p rs = M.fromList
  [ ("wape_all", Value (w (const True))), ("n_all", Count (n (const True)))
  , ("wape_big_show", Value (w big)), ("n_big_show", Count (n big))
  , ("wape_clash", Value (w clash)), ("n_clash", Count (n clash))
  , ("wape_big_show_ci", ci [ eb / yb | Sums _ _ _ eb yb _ <- boot ])
  , ("diff_vs_xgb_rival_all_ci", ci [ ea / ya - ra / ya | Sums ea ya ra _ _ _ <- boot ])
  , ("diff_vs_xgb_rival_big_ci", ci [ eb / yb - rb / yb | Sums _ _ _ eb yb rb <- boot ])
  , ("winner_acc_all", Value (A.accuracy (map snd wins)))
  , ("winner_acc_event_slots", Value (A.accuracy [ h | (True, h) <- wins ]))
  , ("slots_over_pool", Value (A.countOver [ (pool (firstOf s), map p s) | s <- slots ] / A.size slots))
  ]
  where
    pairs m = [ (audience r, p r) | r <- rs, m r ]
    w = A.wape . pairs
    n = length . pairs
    slots = slotsOf rs
    wins = [ (event (firstOf s), (A.winner (map audience s), A.winner (map p s))) | s <- slots ]
    ci xs = Interval (percentile 2.5 xs) (percentile 97.5 xs)
    byDay = IM.fromListWith (flip (<>)) [ (day r, sums r) | r <- rs ]
    sums r =
      let e = abs (audience r - p r); y = abs (audience r); f = abs (audience r - ref r)
      in if big r then Sums e y f e y f else Sums e y f 0 0 0
    days = IM.elems byDay
    table = IM.fromList (zip [0 ..] days)
    boot = [ foldl' (\acc i -> acc <> table IM.! i) mempty pick | pick <- picks ]
