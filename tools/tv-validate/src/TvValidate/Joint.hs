-- The definitions of agda/src/TvAudience/Joint.agda, with the same names and argument order.
-- A row is (actual audience y, independent forecast f).
module TvValidate.Joint
  ( Row, err, sse, total, fsum, bias, poolErr, gap, step, shiftRow, reconcile ) where

import qualified TvAudience as A

type Row a = (a, a)

err :: Num a => Row a -> a
err (y, f) = f - y

sse, total, fsum :: Num a => [Row a] -> a
sse = A.sumL . map (\r -> err r * err r)
total = A.sumL . map fst
fsum = A.sumL . map snd

-- S: how far the independent forecasts are from the actual total.
bias :: Num a => [Row a] -> a
bias rs = fsum rs - total rs

-- ε: how far the pool forecast p is from the actual total.
poolErr :: Num a => a -> [Row a] -> a
poolErr p rs = p - total rs

gap :: Num a => a -> [Row a] -> a
gap p rs = fsum rs - p

step :: (Eq a, Fractional a) => a -> [Row a] -> a
step p rs = gap p rs `A.divZ` A.size rs

shiftRow :: Num a => a -> Row a -> Row a
shiftRow k (y, f) = (y, f - k)

-- The joint estimate: every forecast moved by the same step, so that they add up to p.
reconcile :: (Eq a, Fractional a) => a -> [Row a] -> [Row a]
reconcile p rs = map (shiftRow (step p rs)) rs
