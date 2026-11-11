-- The fat-tail metrics of agda/src/FatTails/, with the same names and the same argument order.
-- Each function is polymorphic in the number type: the spec check runs it on Rational, where it
-- must give the numbers of agda/src/FatTails/Examples.agda exactly, and the data check runs it on
-- Double, where it must give the numbers of fat-tails/results.json.
module FatTails
  ( inv0, divZ, size, sumMap, mean, maxMap
  , sq, devSq, devQuad, mad, kurtosis
  , pow, absPow, msRatio, topShare
  , blockSums, madOfSums, kappaRatio
  , hillGap, hillAlpha, esFactor, expectedShortfall, exceed
  , riskMetricsLambda, ewmaStep, ewma, zSq
  ) where

-- Sample.agda --------------------------------------------------------------------------------

-- Lean's total inverse, `inv₀` of OceanWaves/Order.agda: the inverse of 0 is 0.
inv0 :: (Eq a, Fractional a) => a -> a
inv0 q = if q == 0 then 0 else 1 / q

divZ :: (Eq a, Fractional a) => a -> a -> a
divZ p q = p * inv0 q

size :: Num a => [b] -> a
size = foldr (\_ n -> 1 + n) 0

sumMap :: Num a => (a -> a) -> [a] -> a
sumMap f = foldr (\x s -> f x + s) 0

mean :: (Eq a, Fractional a) => [a] -> a
mean xs = sum' xs `divZ` size xs
  where sum' = foldr (+) 0

maxMap :: (Ord a, Num a) => (a -> a) -> [a] -> a
maxMap f = foldr (\x m -> max (f x) m) 0

-- Moments.agda -------------------------------------------------------------------------------

sq :: Num a => a -> a
sq a = a * a

devSq, devQuad :: Num a => a -> [a] -> a
devSq m = sumMap (\x -> sq (x - m))
devQuad m = sumMap (\x -> sq (sq (x - m)))

mad :: (Eq a, Fractional a) => [a] -> a
mad xs = let m = mean xs in sumMap (\x -> abs (x - m)) xs `divZ` size xs

kurtosis :: (Eq a, Fractional a) => [a] -> a
kurtosis xs = let m = mean xs in (size xs * devQuad m xs) `divZ` sq (devSq m xs)

-- MaxSum.agda --------------------------------------------------------------------------------

pow :: Num a => Int -> a -> a
pow 0 _ = 1
pow p a = a * pow (p - 1) a

absPow :: Num a => Int -> a -> a
absPow p x = pow p (abs x)

msRatio :: (Ord a, Fractional a) => Int -> [a] -> a
msRatio p xs = maxMap (absPow p) xs `divZ` sumMap (absPow p) xs

topShare :: (Ord a, Fractional a) => [a] -> a
topShare = msRatio 4

-- Kappa.agda ---------------------------------------------------------------------------------

blockSums :: Num a => [[a]] -> [a]
blockSums = map (foldr (+) 0)

madOfSums :: (Eq a, Fractional a) => [[a]] -> a
madOfSums bs = mad (blockSums bs)

kappaRatio :: (Eq a, Fractional a) => [[a]] -> a
kappaRatio bs = madOfSums bs `divZ` mad (concat bs)

-- Tail.agda ----------------------------------------------------------------------------------

hillGap :: (Eq a, Fractional a) => [a] -> a -> a
hillGap top thr = mean top - thr

hillAlpha :: (Eq a, Fractional a) => [a] -> a -> a
hillAlpha top thr = inv0 (hillGap top thr)

esFactor :: (Eq a, Fractional a) => a -> a
esFactor alpha = alpha `divZ` (alpha - 1)

expectedShortfall :: (Eq a, Fractional a) => a -> a -> a
expectedShortfall var alpha = var * esFactor alpha

exceed :: Ord a => a -> [a] -> Int
exceed k = length . filter (k <)

-- Ewma.agda ----------------------------------------------------------------------------------

riskMetricsLambda :: Fractional a => a
riskMetricsLambda = 47 / 50

ewmaStep :: Num a => a -> a -> a -> a
ewmaStep l v x = l * v + (1 - l) * sq x

ewma :: Num a => a -> a -> [a] -> [a]
ewma _ v [] = [v]
ewma l v (x : xs) = v : ewma l (ewmaStep l v x) xs

zSq :: (Eq a, Fractional a) => a -> a -> a
zSq x var = sq x `divZ` var
