-- Runs the definitions of agda/src/TvAudience/ (TvAudience.hs) in three checks:
--
--   1. spec: on Rational, every number of agda/src/TvAudience/Examples.agda, exactly;
--   2. data: on Double, the seasonal naive forecasts of the test rows (build/test.csv, written by
--      export.py from tv-audience/python as it is), against the numbers that
--      tv-audience/python/experiment.py wrote to tv-audience/results.json for "naive", within a
--      relative tolerance of 1e-9 (NumPy sums in another order); and, for every model, what the
--      Agda theorems say of results.json: counts in the right order, an accuracy and a coherence
--      share that are whole numbers of slots, and a paired difference of 0 against itself;
--   3. table: every number of tv-audience/results.md is its results.json number, rounded.
--
-- The other models need their fitted XGBoost, MLP and logit weights, which the experiment does not
-- write; the tool does not train them. Every line says OK or FAIL; the exit code is 1 when one
-- line fails. `--self-test` changes one expected example and needs that line to fail.
module Main (main) where

import Data.List (groupBy, isPrefixOf)
import Data.Function (on)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import Text.Printf (printf)

import TvAudience
import qualified Json as J

data Line = Line String Bool String

report :: Line -> IO Bool
report (Line name ok detail) = do
  putStrLn ((if ok then "OK   " else "FAIL ") ++ name ++ "  " ++ detail)
  pure ok

-- Spec check -----------------------------------------------------------------------------------

exact :: (Eq a, Show a) => String -> a -> a -> Line
exact name want got = Line name (want == got) (show got)

rows :: [Row Rational]
rows = [(10, 8), (4, 5), (6, 6)]

days, weekday :: Int -> Rational
days = fromIntegral
weekday t = fromIntegral (t `mod` 7)

slotAudiences, weights :: [Rational]
slotAudiences = [6, 4, 2]
weights = [1, 2, 1 / 2]

tree :: Tree Rational
tree = Node 0 (1 / 2) (Leaf (-1)) (Node 1 3 (Leaf 2) (Leaf 4))

row :: Int -> Rational
row 0 = 1
row _ = 2

q :: String -> Rational -> Rational -> Line
q = exact

qs :: String -> [Rational] -> [Rational] -> Line
qs = exact

specLines :: Rational -> [Line]
specLines w =
  [ q "wape-rows" w (wape rows)
  , q "mae-rows" 1 (mae rows)
  , q "mse-rows" (5 / 3) (mse rows)
  , q "wape-thousands" (3 / 20) (wape (scale 1000 rows))
  , q "wape-big" (1 / 5) (wape (take 1 rows))
  , q "wape-rest" (1 / 10) (wape (drop 1 rows))
  , Line "wape-pooled-le" (wape rows <= max (1 / 5) (1 / 10)) (show (wape rows))
  , q "naive-10" 3 (seasonalNaive days 10)
  , q "level-28" (21 / 2) (lagMean days 28)
  , q "naive-weekly" (weekday 12) (seasonalNaive weekday 12)
  , exact "split-train" ([1, 3] :: [Int]) (train 5 [1, 7, 3, 5, 9])
  , exact "split-test" ([7, 5, 9] :: [Int]) (test 5 [1, 7, 3, 5, 9])
  , qs "panel-shares" [3 / 10, 1 / 5, 1 / 10] (shares 20 slotAudiences)
  , q "panel-outside" (2 / 5) (outside 20 slotAudiences)
  , q "panel-rating" (3 / 50) (rating 100 6)
  , q "panel-put" (1 / 5) (put 100 20)
  , q "over-pool" 1 (countOver [(10, [6, 5]), (10, [3])])
  , qs "jcs-shares" [2 / 9, 4 / 9, 1 / 9] (jcsShares weights)
  , q "jcs-outside" (2 / 9) (jcsOutside weights)
  , qs "jcs-forecast" [2, 4, 1] (jcsForecast 9 weights)
  , exact "jcs-winner-9" (1 :: Int) (winner (jcsForecast 9 weights))
  , q "jcs-rival-3/2" (1 / 6) (jcsShare (3 / 2 : weights) 1)
  , exact "winner-tie" (1 :: Int) (winner [3, 5, 5, 1 :: Rational])
  , q "accuracy-4" (3 / 4) (accuracy [(1, 1), (0, 2), (2, 2), (1, 1)])
  , q "tree-eval" 2 (eval row tree)
  , q "tree-lo" (-1) (lo tree)
  , q "tree-hi" 4 (hi tree)
  , q "ensemble" (11 / 4) (predict (1 / 2) [tree, Leaf (1 / 4)] row)
  ]

-- Data check -----------------------------------------------------------------------------------

-- One test row of build/test.csv.
data TestRow = TestRow { sid :: Int, audience, naive, pool :: Double, bigShow, clash, event :: Bool }

readRows :: FilePath -> IO [TestRow]
readRows path = do
  ls <- drop 1 . lines <$> readFile path
  pure [ parse (splitOn ',' l) | l <- ls, not (null l) ]
  where
    parse [s, _, a, n, p, b, c, e] = TestRow (read s) (read a) (read n) (read p) (b == "1") (c == "1") (e == "1")
    parse cs = error ("tv-audience: bad row " ++ show cs)

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, []) -> [a]
  (a, _ : r) -> a : splitOn c r

near :: String -> Double -> Double -> Line
near name want got = Line name (abs (got - want) <= 1e-9 * max 1 (abs want)) (printf "%.12g (Python %.12g)" got want)

num :: J.Value -> Double
num (J.Num d) = d
num v = error ("tv-audience: not a number: " ++ show v)

at :: [String] -> J.Value -> J.Value
at ks v = foldl (flip J.field) v ks

-- A share of n slots is a whole number of slots.
wholeOf :: Int -> Double -> Bool
wholeOf n x = let k = x * fromIntegral n in abs (k - fromIntegral (round k :: Int)) <= 1e-6

models :: [String]
models = ["naive", "xgb", "xgb_rival", "dnn", "timestral", "jcs", "ns_jcs", "xgb_mint"]

naiveLines :: J.Value -> [TestRow] -> [Line]
naiveLines res te =
  [ near "naive: wape_all" (r "wape_all") (wape (pairs te))
  , near "naive: wape_big_show" (r "wape_big_show") (wape (pairs (filter bigShow te)))
  , near "naive: wape_clash" (r "wape_clash") (wape (pairs (filter clash te)))
  , exact "naive: n_all" (round (r "n_all")) (length te)
  , exact "naive: n_big_show" (round (r "n_big_show")) (length (filter bigShow te))
  , exact "naive: n_clash" (round (r "n_clash")) (length (filter clash te))
  , near "naive: winner_acc_all" (r "winner_acc_all") (accuracy (map winners slots))
  , near "naive: winner_acc_event_slots" (r "winner_acc_event_slots")
      (accuracy (map winners (filter (event . fst) slots)))
  , near "naive: slots_over_pool" (r "slots_over_pool")
      (countOver [ (pool t, map naive s) | (t, s) <- slots ] / size slots)
  , exact "meta: test_slots" (round (num (at ["meta", "test_slots"] res))) (length slots)
  , exact "meta: test_rows" (round (num (at ["meta", "test_rows"] res))) (length te)
  ]
  where
    r k = num (at ["results", "naive", k] res)
    pairs = map (\t -> (audience t, naive t))
    slots = [ (t, t : ts) | t : ts <- groupBy ((==) `on` sid) te ]
    winners (_, s) = (winner (map audience s), winner (map naive s))

theoremLines :: J.Value -> [Line]
theoremLines res = concat [ perModel m (at ["results", m] res) | m <- models, present m ]
  where
    present m = case at ["results", m] res of J.Obj _ -> True; _ -> False
    nSlots = round (num (at ["meta", "test_slots"] res)) :: Int
    perModel m v =
      [ Line (m ++ ": n_clash <= n_big_show <= n_all")
          (n "n_clash" <= n "n_big_show" && n "n_big_show" <= n "n_all") (show (n "n_clash", n "n_big_show", n "n_all"))
      , Line (m ++ ": 0 <= wape, winner_acc <= 1")
          (all (>= 0) [f "wape_all", f "wape_big_show", f "wape_clash"] && all (\a -> 0 <= a && a <= 1) [f "winner_acc_all", f "winner_acc_event_slots"])
          ""
      , Line (m ++ ": winner_acc_all is hits / " ++ show nSlots) (wholeOf nSlots (f "winner_acc_all")) (printf "%.6f slots" (f "winner_acc_all" * fromIntegral nSlots))
      , Line (m ++ ": slots_over_pool is a count / " ++ show nSlots) (wholeOf nSlots (f "slots_over_pool")) (printf "%.6f slots" (f "slots_over_pool" * fromIntegral nSlots))
      ]
      ++ [ Line (m ++ ": wape_diff_self, the paired interval against itself is [0, 0]")
             (map num (J.list (J.field "diff_vs_xgb_rival_all_ci" v)) ++ map num (J.list (J.field "diff_vs_xgb_rival_big_ci" v)) == [0, 0, 0, 0]) ""
         | m == "xgb_rival" ]
      where
        f k = num (J.field k v)
        n k = round (f k) :: Int

-- Table check ----------------------------------------------------------------------------------

labels :: [(String, String)]
labels = [ ("naive", "Seasonal naive"), ("xgb", "XGBoost"), ("xgb_rival", "XGBoost + rivals"), ("dnn", "DNN (MLP)")
         , ("timestral", "Mistral Timestral"), ("jcs", "JCS"), ("ns_jcs", "Neurosymbolic JCS")
         , ("xgb_mint", "XGBoost + rivals + MinT") ]

pct :: Double -> String
pct = printf "%.1f" . (100 *)

tableLines :: J.Value -> [String] -> [Line]
tableLines res md =
  [ Line ("results.md: " ++ label) (want `elem` md) want
  | (m, label) <- labels, case at ["results", m] res of J.Obj _ -> True; _ -> False
  , let v = at ["results", m] res
        f k = num (J.field k v)
        (lo', hi') = case map num (J.list (J.field "wape_big_show_ci" v)) of
          [a, b] -> (a, b)
          _ -> error "tv-audience: wape_big_show_ci is not a pair"
        want = "| " ++ label ++ " | " ++ pct (f "wape_all") ++ "% | " ++ pct (f "wape_big_show") ++ "% ("
               ++ pct lo' ++ " to " ++ pct hi' ++ ") | " ++ pct (f "wape_clash") ++ "% | "
               ++ pct (f "winner_acc_all") ++ "% | " ++ pct (f "winner_acc_event_slots") ++ "% | "
               ++ pct (f "slots_over_pool") ++ "% |" ]

main :: IO ()
main = do
  args <- getArgs
  let selfTest = "--self-test" `elem` args
      csv = case [ drop 6 a | a <- args, "--csv=" `isPrefixOf` a ] of (p : _) -> p; [] -> "tools/tv-audience/build/test.csv"
  putStrLn "Spec check against agda/src/TvAudience/Examples.agda (Rational)"
  spec <- mapM report (specLines (if selfTest then 4 / 20 else 3 / 20))
  if selfTest
    then if and spec
      then putStrLn "tv-audience: self-test: a wrong WAPE passed" >> exitFailure
      else putStrLn "tv-audience: self-test OK (a wrong WAPE fails)"
    else do
      res <- J.parse <$> readFile "tv-audience/results.json"
      te <- readRows csv
      putStrLn "Data check against tv-audience/results.json (Double)"
      d <- mapM report (naiveLines res te ++ theoremLines res)
      putStrLn "Table check of tv-audience/results.md"
      md <- lines <$> readFile "tv-audience/results.md"
      t <- mapM report (tableLines res md)
      let oks = spec ++ d ++ t
          bad = length (filter not oks)
      if bad == 0
        then printf "tv-audience: OK (%d lines)\n" (length oks)
        else printf "tv-audience: %d of %d lines FAIL\n" bad (length oks) >> exitFailure
