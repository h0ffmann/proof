-- The definitions of agda/src/TvAudience/, with the same names and the same argument order. Each
-- function is polymorphic in the number type: the spec check runs it on Rational, where it must
-- give the numbers of agda/src/TvAudience/Examples.agda exactly, and the data check runs it on
-- Double, where it must give the numbers of tv-audience/results.json.
module TvAudience
  ( inv0, divZ, size, sumL
  , Row, absErr, sqErr, errSum, actualSum, wape, mae, mse, scale, perfect
  , lag, seasonalNaive, lagMean, train, test
  , rating, put, share, outside, shares, overPool, countOver
  , denom, jcsShare, jcsShares, jcsOutside, jcsForecast
  , winner, hit, hits, accuracy
  , Tree (..), eval, treeSum, predict, lo, hi
  , stableShare, invert
  , Programme (..), Rival (..), picks, slotFeatures
  , dot, dense, NsParams (..), nsUtility, resid
  , Model (..), SlotIn (..), poolHat, forecastSlot, withoutNetwork, pipelineWape
  ) where

-- FatTails/Sample.agda and OceanWaves/Order.agda ---------------------------------------------

-- Lean's total inverse, `inv₀`: the inverse of 0 is 0.
inv0 :: (Eq a, Fractional a) => a -> a
inv0 q = if q == 0 then 0 else 1 / q

divZ :: (Eq a, Fractional a) => a -> a -> a
divZ p q = p * inv0 q

size :: Num a => [b] -> a
size = foldr (\_ n -> 1 + n) 0

sumL :: Num a => [a] -> a
sumL = foldr (+) 0

-- Wape.agda ----------------------------------------------------------------------------------

type Row a = (a, a)

absErr, sqErr :: Num a => Row a -> a
absErr (y, f) = abs (y - f)
sqErr (y, f) = (y - f) * (y - f)

errSum, actualSum :: Num a => [Row a] -> a
errSum = sumL . map absErr
actualSum = sumL . map (abs . fst)

wape, mae, mse :: (Eq a, Fractional a) => [Row a] -> a
wape rs = errSum rs `divZ` actualSum rs
mae rs = errSum rs `divZ` size rs
mse rs = sumL (map sqErr rs) `divZ` size rs

scale :: Num a => a -> [Row a] -> [Row a]
scale c = map (\(y, f) -> (c * y, c * f))

perfect :: [a] -> [Row a]
perfect = map (\y -> (y, y))

-- Baselines.agda -----------------------------------------------------------------------------

lag :: Int -> (Int -> a) -> Int -> a
lag k s t = s (max 0 (t - k))

seasonalNaive :: (Int -> a) -> Int -> a
seasonalNaive = lag 7

lagMean :: Fractional a => (Int -> a) -> Int -> a
lagMean s t = (lag 7 s t + lag 14 s t + lag 21 s t + lag 28 s t) * (1 / 4)

-- Split.agda ---------------------------------------------------------------------------------

train, test :: Int -> [Int] -> [Int]
train cut = filter (< cut)
test cut = filter (>= cut)

-- Panel.agda ---------------------------------------------------------------------------------

rating, put, share :: (Eq a, Fractional a) => a -> a -> a
rating universe audience = audience `divZ` universe
put universe pool = pool `divZ` universe
share pool audience = audience `divZ` pool

outside :: (Eq a, Fractional a) => a -> [a] -> a
outside pool audiences = (pool - sumL audiences) `divZ` pool

shares :: (Eq a, Fractional a) => a -> [a] -> [a]
shares pool = map (share pool)

overPool :: (Ord a, Num a) => (a, [a]) -> Bool
overPool (pool, fs) = pool < sumL fs

countOver :: (Ord a, Num a) => [(a, [a])] -> a
countOver = sumL . map (\s -> if overPool s then 1 else 0)

-- Jcs.agda -----------------------------------------------------------------------------------

denom :: Num a => [a] -> a
denom ws = 1 + sumL ws

jcsShare :: (Eq a, Fractional a) => [a] -> a -> a
jcsShare ws w = w `divZ` denom ws

jcsShares :: (Eq a, Fractional a) => [a] -> [a]
jcsShares ws = map (jcsShare ws) ws

jcsOutside :: (Eq a, Fractional a) => [a] -> a
jcsOutside ws = 1 `divZ` denom ws

jcsForecast :: (Eq a, Fractional a) => a -> [a] -> [a]
jcsForecast pool ws = map (\w -> pool * jcsShare ws w) ws

-- Winner.agda --------------------------------------------------------------------------------

-- The first largest value wins: the running best changes only on a strict <.
winner :: Ord a => [a] -> Int
winner [] = 0
winner (x : xs) = go 1 0 x xs
  where
    go _ b _ [] = b
    go i b v (y : ys) = if v < y then go (i + 1) i y ys else go (i + 1) b v ys

hit :: Num a => (Int, Int) -> a
hit (a, f) = if a == f then 1 else 0

hits :: Num a => [(Int, Int)] -> a
hits = sumL . map hit

accuracy :: (Eq a, Fractional a) => [(Int, Int)] -> a
accuracy ps = hits ps `divZ` size ps

-- Trees.agda ---------------------------------------------------------------------------------

data Tree a = Leaf a | Node Int a (Tree a) (Tree a)

eval :: Ord a => (Int -> a) -> Tree a -> a
eval _ (Leaf v) = v
eval x (Node j th l r) = if x j < th then eval x l else eval x r

treeSum :: (Ord a, Num a) => (Int -> a) -> [Tree a] -> a
treeSum x = sumL . map (eval x)

predict :: (Ord a, Num a) => a -> [Tree a] -> (Int -> a) -> a
predict base ts x = base + treeSum x ts

lo, hi :: Ord a => Tree a -> a
lo (Leaf v) = v
lo (Node _ _ l r) = min (lo l) (lo r)
hi (Leaf v) = v
hi (Node _ _ l r) = max (hi l) (hi r)

-- JcsTheory.agda -----------------------------------------------------------------------------

stableShare :: (Eq a, Fractional a) => a -> [a] -> a -> a
stableShare k ws w = (w * k) `divZ` (k + sumL (map (* k) ws))

invert :: (Eq a, Fractional a) => [a] -> [a]
invert ss = map (\s -> s * inv0 (1 - sumL ss)) ss

-- Features.agda ------------------------------------------------------------------------------

data Programme a = Prog { genre :: Int, hype :: a, big :: Bool }

data Rival a = Rival Int a a Bool deriving (Eq, Show)

picks :: [b] -> [(b, [b])]
picks [] = []
picks (x : xs) = (x, xs) : map (\(y, ys) -> (y, x : ys)) (picks xs)

slotFeatures :: (Ord a, Num a) => [Programme a] -> [Rival a]
slotFeatures s =
  [ Rival (length (filter ((== genre p) . genre) os)) (sumL (map hype os)) (foldr (max . hype) 0 os) (any big os)
  | (p, os) <- picks s ]

-- Neural.agda --------------------------------------------------------------------------------

dot :: Num a => [a] -> [a] -> a
dot as hs = sumL (zipWith (*) as hs)

dense :: Num a => [[a]] -> [a] -> [a] -> [a]
dense rs cs z = zipWith (\r c -> dot r z + c) rs cs

data NsParams a = Ns { w :: [a], b :: a, w1 :: [[a]], b1 :: [a], w2 :: [a] }

nsUtility :: Num a => (a -> a) -> NsParams a -> [a] -> a
nsUtility act p z = (dot (w p) z + b p) + dot (w2 p) (map act (dense (w1 p) (b1 p) z))

resid :: Num a => [a] -> [a] -> [a]
resid = zipWith (-)

-- Pipeline.agda ------------------------------------------------------------------------------

data Model a = Model { e :: a -> a, act :: a -> a, params :: NsParams a, poolBase :: a, poolTrees :: [Tree a] }

data SlotIn a = SlotIn { level :: a, poolX :: Int -> a, zs :: [[a]] }

poolHat :: (Ord a, Num a) => Model a -> SlotIn a -> a
poolHat m d = e m (level d + predict (poolBase m) (poolTrees m) (poolX d))

forecastSlot :: (Ord a, Fractional a) => Model a -> SlotIn a -> [a]
forecastSlot m d = jcsForecast (poolHat m d) (map (e m . nsUtility (act m) (params m)) (zs d))

withoutNetwork :: Model a -> Model a
withoutNetwork m = m { params = (params m) { w2 = [] } }

pipelineWape :: (Ord a, Fractional a) => Model a -> [(SlotIn a, [a])] -> a
pipelineWape m ss = wape (concat [ zip ys (forecastSlot m d) | (d, ys) <- ss ])
