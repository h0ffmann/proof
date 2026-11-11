-- Runs the definitions of agda/src/FatTails/ (FatTails.hs) in two checks:
--
--   1. spec: on Rational, every number of agda/src/FatTails/Examples.agda, exactly;
--   2. data: on Double, the S&P 500, Nasdaq 100 and Nikkei 225 log returns of fat-tails/data/,
--      against the numbers that fat-tails/python/fat_tails.py wrote to fat-tails/results.json,
--      within a relative tolerance of 1e-9 (NumPy sums in another order).
--
-- The data check uses Double where the Agda has no counterpart: the logarithm of the returns
-- and of the Hill order statistics, the square root of the EWMA variance, and κ's two logarithms.
-- Every line says OK or FAIL; the exit code is 1 when one line fails. `--self-test` changes one
-- expected number and needs that line to fail.
module Main (main) where

import Data.List (sortBy)
import Data.Ord (Down (..), comparing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Text.Printf (printf)

import FatTails
import qualified Json as J

data Line = Line String Bool String

report :: Line -> IO Bool
report (Line name ok detail) = do
  putStrLn ((if ok then "OK   " else "FAIL ") ++ name ++ "  " ++ detail)
  pure ok

-- Spec check -----------------------------------------------------------------------------------

returns :: [Rational]
returns = [1, -1, 2, -1, 1, -12, 2, 0]

twoDays, fourDays :: [[Rational]]
twoDays = [[1, -1], [2, -1], [1, -12], [2, 0]]
fourDays = [[1, -1, 2, -1], [1, -12, 2, 0]]

exact :: String -> Rational -> Rational -> Line
exact name want got = Line name (want == got) (show got)

specLines :: Rational -> [Line]
specLines kurt =
  [ exact "mean-returns" (-1) (mean returns)
  , exact "mad-returns" (11 / 4) (mad returns)
  , exact "kurtosis-returns" kurt (kurtosis returns)
  , exact "kurtosis-two-points" 1 (kurtosis [1, -1])
  , exact "kurtosis-bp" (7418 / 1369) (kurtosis (map (100 *) returns))
  , exact "ms1" (3 / 5) (msRatio 1 returns)
  , exact "ms2" (12 / 13) (msRatio 2 returns)
  , exact "ms3" (432 / 437) (msRatio 3 returns)
  , exact "top-share" (576 / 577) (topShare returns)
  , exact "ms-flat" (1 / 5) (msRatio 4 (replicate 5 3))
  , Line "two-day-sums" (blockSums twoDays == [0, 1, -11, 2]) (show (blockSums twoDays))
  , exact "M2" (9 / 2) (madOfSums twoDays)
  , exact "ratio-2" (18 / 11) (kappaRatio twoDays)
  , exact "ratio-4" (20 / 11) (kappaRatio fourDays)
  , exact "hill-gap" (7 / 6) (hillGap [3, 2, 3 / 2] 1)
  , exact "hill-alpha" (6 / 7) (hillAlpha [3, 2, 3 / 2] 1)
  , exact "es-3·75" (15 / 11) (esFactor (15 / 4))
  , Line "beyond-0" (exceed 0 (map negate returns) == 3) (show (exceed 0 (map negate returns)))
  , Line "beyond-5" (exceed 5 (map negate returns) == 1) (show (exceed 5 (map negate returns)))
  , Line "ewma-3" (ewma riskMetricsLambda 4 [1, -3, 2 :: Rational] == [4, 191 / 50, 10327 / 2500, 515369 / 125000])
      (show (ewma riskMetricsLambda 4 [1, -3, 2 :: Rational]))
  ]

-- Data check -----------------------------------------------------------------------------------

-- (date, close) rows of a CSV with a header line.
readCloses :: FilePath -> IO [(String, Double)]
readCloses path = do
  rows <- drop 1 . lines <$> readFile path
  pure [ (d, read c) | row <- rows, not (null row), let (d, rest) = break (== ',') row, let c = drop 1 rest ]

-- Daily log returns, dated by the second day of each pair (`np.log(s).diff().dropna()`).
logReturns :: [(String, Double)] -> [(String, Double)]
logReturns cs = zipWith (\(_, a) (d, b) -> (d, log b - log a)) cs (drop 1 cs)

-- The sample variance with n - 1 (pandas' `.var()`), the start of the EWMA.
sampleVar :: [Double] -> Double
sampleVar xs = devSq (mean xs) xs / (size xs - 1)

-- `hill(x, k)`: the Hill α from the k largest of x and the next one, on their logarithms.
hill :: [Double] -> Int -> Double
hill xs k = let s = sortBy (comparing Down) xs in hillAlpha (map log (take k s)) (log (s !! k))

-- Non-overlapping blocks of n, the rest dropped (`x[: m * n].reshape(m, n)`).
blocks :: Int -> [a] -> [[a]]
blocks n xs = go (take (length xs `div` n * n) xs)
  where go [] = []
        go ys = let (b, r) = splitAt n ys in b : go r

-- κ(1, n) = 2 - log n / log (M(n) / M(1)), with M(1) over the whole sample as Python takes it.
kappa :: [Double] -> Int -> Double
kappa x n = 2 - log (fromIntegral n) / log (madOfSums (blocks n x) / mad x)

near :: String -> Double -> Double -> Line
near name want got = Line name (abs (got - want) <= 1e-9 * max 1 (abs want)) (printf "%.12g (Python %.12g)" got want)

num :: J.Value -> Double
num (J.Num d) = d
num v = error ("fat-tails: not a number: " ++ show v)

at :: [String] -> J.Value -> J.Value
at ks v = foldl (flip J.field) v ks

dataLines :: J.Value -> [Double] -> [Line]
dataLines res x =
  [ near (tag "kurtosis") (num (at ["kurtosis", "kurtosis"] res)) (kurtosis x)
  , near (tag "share_of_4th_moment_top_day") (num (at ["kurtosis", "share_of_4th_moment_top_day"] res)) (topShare x)
  ]
  ++ [ near (tag ("ms_final p" ++ show p)) (num (at ["ms_final", 'p' : show p] res)) (msRatio p x) | p <- [1 .. 4] ]
  ++ [ near (tag ("kappa " ++ h)) (num (at ["kappa", h, "value"] res)) (kappa x b)
     | (h, b) <- [("1,2", 2), ("1,10", 10), ("1,30", 30), ("1,100", 100)], isNum (at ["kappa", h, "value"] res) ]
  ++ [ near (tag ("hill_raw_losses " ++ q)) (num (at ["hill_raw_losses", q] res)) (hill loss (frac f n))
     | (q, f) <- fracs ]
  ++ [ near (tag ("hill_devol_losses " ++ q)) (num (at ["hill_devol_losses", q] res)) (hill zloss (frac f (length z)))
     | (q, f) <- fracs ]
  ++ [ near (tag ("hill_devol_gains " ++ q)) (num (at ["hill_devol_gains", q] res)) (hill zgain (frac f (length z)))
     | (q, f) <- fracs ]
  ++ [ near (tag "alpha_used") (num (J.field "alpha_used" res)) alpha
     , near (tag "daily_sd_ewma_now") (num (J.field "daily_sd_ewma_now" res)) (sqrt (last vars))
     ]
  ++ [ Line (tag ("exceedances " ++ s)) (fromIntegral got == want) (show got)
     | k <- [3 .. 6 :: Int], let s = show k ++ "sigma", let want = num (at ["exceedances", s, "observed"] res)
     , let got = exceed (fromIntegral k) (map negate z) ]
  ++ [ near (tag ("esFactor " ++ l)) (num (at [l, "evt_es_fhs"] risk) / num (at [l, "evt_var_fhs"] risk)) (esFactor alpha)
     | l <- ["0.99", "0.999", "0.9999"] ]
  where
    tag s = J.str (J.field "name" res) ++ ": " ++ s
    risk = J.field "one_day_risk_now" res
    n = length x
    fracs = [("0.010", 0.01), ("0.025", 0.025), ("0.050", 0.05)] :: [(String, Double)]
    frac :: Double -> Int -> Int
    frac f m = floor (f * fromIntegral m)
    loss = [ -v | v <- x, v < 0 ]
    vars = ewma riskMetricsLambda (sampleVar (take 250 x)) x
    z = drop 250 (zipWith (\v s -> v / sqrt s) x vars)
    zloss = [ -v | v <- z, v < 0 ]
    zgain = [ v | v <- z, v > 0 ]
    alpha = hill zloss (frac 0.025 (length z))
    isNum (J.Num _) = True
    isNum _ = False

-- The four samples of results.json, in its order.
samples :: IO [[Double]]
samples = do
  sp <- logReturns <$> readCloses "fat-tails/data/sp500.csv"
  ndx <- logReturns <$> readCloses "fat-tails/data/ndx.csv"
  n225 <- logReturns <$> readCloses "fat-tails/data/n225.csv"
  pure [map snd sp, [ r | (d, r) <- sp, d >= "2015-01-01" ], map snd ndx, map snd n225]

main :: IO ()
main = do
  args <- getArgs
  let selfTest = args == ["--self-test"]
  putStrLn "Spec check against agda/src/FatTails/Examples.agda (Rational)"
  spec <- mapM report (specLines (if selfTest then 7417 / 1369 else 7418 / 1369))
  if selfTest
    then if and spec
      then putStrLn "fat-tails: self-test: a wrong kurtosis passed" >> exitFailure
      else putStrLn "fat-tails: self-test OK (a wrong kurtosis fails)"
    else do
      putStrLn "Data check against fat-tails/results.json (Double)"
      res <- J.list . J.parse <$> readFile "fat-tails/results.json"
      xs <- samples
      oks <- mapM report (concat (zipWith dataLines res xs))
      let total = length spec + length oks
          bad = length (filter not (spec ++ oks))
      if bad == 0
        then printf "fat-tails: OK (%d lines)\n" total
        else printf "fat-tails: %d of %d lines FAIL\n" bad total >> exitFailure
