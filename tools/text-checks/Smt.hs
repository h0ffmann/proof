-- The question every text check asks Z3, through SBV: given the measured value of each unit
-- (a file, a sentence, a cell of a table) as a constant, is there a unit that breaks the rule?
-- "unsat" means none does. "sat" gives a model, and the units it marks as broken are reported.
-- The decision layer itself is proved for every input in agda/src/TextChecks/.
module Smt (brokenInts, brokenXor) where

import Control.Monad (forM, forM_)
import Data.SBV

-- | Units i with x[i] > limit, where x[i] is the measure. Nothing when Z3 answers unsat.
brokenInts :: Integer -> [Integer] -> IO (Maybe [Int])
brokenInts limit xs = do
  r <- sat $ do
    l <- sInteger "limit"
    constrain (l .== literal limit)
    vs <- forM (zip [0 :: Int ..] xs) $ \(i, x) -> do
      v <- sInteger ("x" ++ show i)
      constrain (v .== literal x)
      pure v
    pure (sOr [v .> l | v <- vs])
  pure $ if not (modelExists r) then Nothing else Just
    [ i | (i, _) <- zip [0 :: Int ..] xs
        , Just v <- [getModelValue ("x" ++ show i) r :: Maybe Integer]
        , Just l <- [getModelValue "limit" r :: Maybe Integer]
        , v > l ]

-- | Units i where p[i] xor m[i]. Nothing when Z3 answers unsat.
brokenXor :: [(Bool, Bool)] -> IO (Maybe [Int])
brokenXor pms = do
  r <- sat $ do
    pairs <- forM (zip [0 :: Int ..] pms) $ \(i, (p, m)) -> do
      sp <- sBool ("p" ++ show i)
      sm <- sBool ("m" ++ show i)
      constrain (sp .== literal p)
      constrain (sm .== literal m)
      pure (sp .<+> sm)
    forM_ [()] pure
    pure (sOr pairs)
  pure $ if not (modelExists r) then Nothing else Just
    [ i | (i, _) <- zip [0 :: Int ..] pms
        , Just p <- [getModelValue ("p" ++ show i) r :: Maybe Bool]
        , Just m <- [getModelValue ("m" ++ show i) r :: Maybe Bool]
        , p /= m ]
