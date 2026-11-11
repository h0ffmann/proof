{-# LANGUAGE OverloadedStrings #-}

-- The lines of the pipeline. Each line is one statement about the run of
-- tv-audience/python/experiment.py that export.py wrote, and says OK, FAIL or NOTE.
--
--   reproduce  tv-audience/results.json against the results.json of this run
--   metrics    every number of this run's results.json, computed again from the forecasts
--   forward    the JCS and neurosymbolic JCS forecasts, computed again from the fitted weights
--   gradient   the fitted logit weights are a stationary point of fit_logit's loss
--   theorems   statements proved in agda/src/TvAudience/, on the numbers of this run
--   joint      agda/src/TvAudience/Joint.agda on the test slots, on exact rationals
--   mint       the MinT reconciliation in closed form
--
-- A NOTE is a measurement, or a comparison that this run cannot make; it never fails.
module TvValidate.Checks
  ( Status (..), Line (..), Ctx, context, groups, selfTests, committedXgboost ) where

import qualified Data.Aeson as J
import Data.Function (on)
import qualified Data.IntMap.Strict as IM
import Data.List (maximumBy)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Text.Printf (printf)

import qualified TvAudience as A
import qualified TvValidate.Joint as Jt
import TvValidate.Load
import TvValidate.Metrics
import TvValidate.Model

data Status = OK | FAIL | NOTE deriving (Eq, Show)

data Line = Line { lineName :: String, lineStatus :: Status, lineDetail :: String }

check :: String -> Bool -> String -> Line
check name ok = Line name (if ok then OK else FAIL)

note :: String -> String -> Line
note name = Line name NOTE

-- The XGBoost release that wrote tv-audience/results.json: with it, every number of that file
-- comes back within 1e-14 (checked on 2026-11-11, NumPy 2.5.4, pandas 3.1.1, scikit-learn 1.9.1).
-- The file does not record its versions, so the pipeline keeps the one that matters here.
committedXgboost :: Text
committedXgboost = "3.4.1"

tolerance :: Double
tolerance = 1e-9

-- The gap between two numbers, relative for a number above 1 and absolute below it (the scores
-- are shares). Two numbers are equal here when their gap is at most the tolerance.
gapOf :: Double -> Double -> Double
gapOf a b = abs (a - b) / max 1 (max (abs a) (abs b))

sci :: Double -> String
sci = printf "%.2e"

pct :: Double -> String
pct x = printf "%.2f%%" (100 * x)

worst :: [Double] -> Double
worst = foldl' max 0

-- What every group shares, computed once.
data Ctx = Ctx
  { run :: Run
  , models :: [Text]                        -- the models that have forecasts in this run
  , std :: ([Double], [Double])             -- mu and sd of the training design
  , trainSlots :: [[(Double, [Double])]]    -- per training slot: (observed share, z)
  , jcsOut, nsOut :: [SlotOut]              -- per test slot, from the fitted weights
  , closedMint :: M.Map Int [Double]        -- per test slot: the closed form of MinT
  }

-- A test slot run through `forecastSlot` of Pipeline.agda.
data SlotOut = SlotOut { soRows :: [TestRow], soU, soForecast :: [Double] }

context :: Run -> Ctx
context r = Ctx r ms st trSlots (out (jcsModel (logit r))) (out (nsModel (ns r))) closed
  where
    ms = M.keys (forecasts (firstOf (testRows r)))
    st = standardiser (shareTrain r)
    trSlots = map (map (\(s, z) -> (sObs s, z))) (bySlot (shareTrain r) (map (standardise st) (shareTrain r)))
    teSlots = bySlot (shareTest r) (zip (testRows r) (map (standardise st) (shareTest r)))
    out m =
      [ SlotOut rows (utilities m zs) (A.forecastSlot m (slotIn (poolHat (firstOf rows)) zs))
      | s <- teSlots, let rows = map (fst . snd) s, let zs = map (snd . snd) s ]
    closed = M.fromList
      [ (sid x, map (\ch -> forecast "xgb_rival" ch + step) s)
      | s <- slotsOf (testRows r)
      , let x = firstOf s
      , let step = (poolHat x - sum (map (forecast "xgb_rival") s) - otherHat x) / 8 ]

groups :: [(String, Ctx -> [Line])]
groups =
  [ ("reproduce", reproduce), ("metrics", metrics), ("forward", forward), ("gradient", gradient)
  , ("theorems", theorems), ("joint", joint), ("mint", mint) ]

-- reproduce ------------------------------------------------------------------------------------

xgboostOf :: Results -> Text
xgboostOf res = fromMaybe "?" $ do
  v <- M.lookup "versions" (meta res)
  m <- case J.fromJSON v of J.Success x -> Just (x :: M.Map Text Text); _ -> Nothing
  M.lookup "xgboost" m

-- A number passes through XGBoost when its model does (its own trees, or the pool model of the
-- two JCS models), or when it is a difference against XGBoost + rivals.
throughXgboost :: Text -> Text -> Bool
throughXgboost model key = model `notElem` ["naive", "dnn"] || "diff_vs_xgb_rival" `T.isPrefixOf` key

-- The largest gap between two models' numbers, with the key that has it.
valueGap :: J.Value -> J.Value -> Double
valueGap a b = case (number a, number b, interval a, interval b) of
  (Just x, Just y, _, _) -> gapOf x y
  (_, _, Just (x, x'), Just (y, y')) -> max (gapOf x y) (gapOf x' y')
  _ -> if a == b then 0 else 1 / 0

reproduce :: Ctx -> [Line]
reproduce c = metaLine : concatMap model (M.toList (results old))
  where
    old = committed (run c)
    new = fresh (run c)
    same = xgboostOf new == committedXgboost
    counts = ["train_rows", "test_rows", "test_big_shows", "test_slots", "seed"]
    metaLine = check "meta" (all (\k -> M.lookup k (meta old) == M.lookup k (meta new)) counts)
      (unwords (map T.unpack counts) ++ " as committed")
    model (m, keys) = case M.lookup m (results new) of
      Nothing -> [note (T.unpack m) "no forecast in this run, nothing to compare"]
      Just got ->
        let gaps = [ (k, valueGap v (M.findWithDefault J.Null k got)) | (k, v) <- M.toList keys ]
            (thru, direct) = (filter (throughXgboost m . fst) gaps, filter (not . throughXgboost m . fst) gaps)
            top xs = maximumBy (compare `on` snd) xs
            say xs = printf "%d numbers, largest gap %s (%s)" (length xs) (sci (snd (top xs))) (T.unpack (fst (top xs)))
        in [ check (T.unpack m ++ " without XGBoost") (all ((<= tolerance) . snd) direct) (say direct) | not (null direct) ]
           ++ [ if same
                  then check (T.unpack m ++ " through XGBoost") (all ((<= tolerance) . snd) thru) (say thru)
                  else note (T.unpack m ++ " through XGBoost")
                         (say thru ++ ": this run has XGBoost " ++ T.unpack (xgboostOf new)
                          ++ ", the committed file comes from " ++ T.unpack committedXgboost)
              | not (null thru) ]

-- metrics --------------------------------------------------------------------------------------

scoreGap :: Score -> J.Value -> Double
scoreGap s v = case (s, number v, interval v) of
  (Count n, Just x, _) -> if fromIntegral n == x then 0 else 1 / 0
  (Value a, Just x, _) -> gapOf a x
  (Interval a b, _, Just (x, y)) -> max (gapOf a x) (gapOf b y)
  _ -> 1 / 0

showScore :: Score -> String
showScore (Count n) = show n
showScore (Value a) = show a
showScore (Interval a b) = "[" ++ show a ++ ", " ++ show b ++ "]"

scoresOf :: Ctx -> (TestRow -> Double) -> M.Map Text Score
scoresOf c p = scores (resamples (run c)) (forecast "xgb_rival") p (testRows (run c))

metrics :: Ctx -> [Line]
metrics c = concatMap model (models c)
  where
    model m =
      let mine = scoresOf c (forecast m)
          theirs = M.findWithDefault M.empty m (results (fresh (run c)))
      in [ check (T.unpack m ++ " " ++ T.unpack k) (scoreGap s (M.findWithDefault J.Null k theirs) <= tolerance) (showScore s)
         | (k, s) <- M.toList mine ]
         ++ [ check (T.unpack m ++ " keys") (M.keys mine == M.keys theirs) (show (M.size theirs) ++ " numbers in results.json") ]

-- forward --------------------------------------------------------------------------------------

forward :: Ctx -> [Line]
forward c =
  [ check "standardisation" (stdGap <= tolerance)
      ("mu and sd of the training design against the ones in the neurosymbolic closure, largest gap " ++ sci stdGap)
  , fwd "jcs" (jcsOut c)
  , fwd "ns_jcs" (nsOut c)
  ]
  where
    (mu, sd) = std c
    stdGap = worst (zipWith gapOf mu (nMu (ns (run c))) ++ zipWith gapOf sd (nSd (ns (run c))))
    fwd m outs =
      let gaps = concat [ zipWith (\r f -> gapOf (forecast m r) f) (soRows s) (soForecast s) | s <- outs ]
      in check (T.unpack m) (worst gaps <= tolerance && length gaps == length (testRows (run c)))
           (printf "forecastSlot of Pipeline.agda on the fitted weights against p_%s, %d rows, largest gap %s"
              (T.unpack m) (length gaps) (sci (worst gaps)))

-- gradient -------------------------------------------------------------------------------------

-- L-BFGS-B stops when the largest component of the projected gradient is below 1e-5 (SciPy's
-- default gtol) or the loss stops falling; the bound here is ten times that default.
stationary :: Double
stationary = 1e-4

gradient :: Ctx -> [Line]
gradient c =
  [ check "ad = residual formula" (worst (zipWith gapOf ad hand) <= tolerance)
      (printf "the gradient of the loss by automatic differentiation against (Σ resid, Zᵀ resid + 2 l2 w) / n, %d weights, largest gap %s"
         (length ad) (sci (worst (zipWith gapOf ad hand))))
  , check "stationary" (worst (map abs ad) <= stationary)
      (printf "largest |∂loss/∂w| at the fitted weights %s (bound %s); the loss is convex, so a zero gradient is its minimum"
         (sci (worst (map abs ad))) (sci stationary))
  , check "resid-slot" (worst slotGaps <= tolerance)
      (printf "Σ resid = (1 - Σ s_obs) - outside share on %d training slots, largest gap %s" (length slotGaps) (sci (worst slotGaps)))
  , check "jcs-invert" (worst invertGaps <= tolerance && not (null invertGaps))
      (printf "the weights s / s₀ give the observed shares back on the %d training slots with Σ s_obs < 1 (%d slots are over the pool), largest gap %s"
         (length fitting) (length (trainSlots c) - length fitting) (sci (worst invertGaps)))
  ]
  where
    w = lW (logit (run c))
    l2 = lL2 (logit (run c))
    ad = logitGradient l2 (trainSlots c) w
    hand = residualGradient l2 (trainSlots c) w
    u z = firstOf w + sum (zipWith (*) (drop 1 w) z)
    slotGaps =
      [ gapOf (A.sumL (A.resid (A.jcsShares ws) os)) ((1 - A.sumL os) - A.jcsOutside ws)
      | s <- trainSlots c, let ws = map (exp . u . snd) s, let os = map fst s ]
    fitting = [ os | s <- trainSlots c, let os = map fst s, A.sumL os < 1 ]
    invertGaps = concat [ zipWith gapOf (A.jcsShares (A.invert os)) os | os <- fitting ]

-- theorems -------------------------------------------------------------------------------------

theorems :: Ctx -> [Line]
theorems c =
  [ check "wape-scale" (worst scaleGaps <= tolerance)
      ("WAPE in thousands = WAPE in millions, every model, largest gap " ++ sci (worst scaleGaps))
  , check "wape-++-le" (and pooled) "WAPE of all rows ≤ the larger of WAPE(big shows) and WAPE(the rest), every model"
  , check "wape-mae" (worst maeGaps <= tolerance) ("WAPE = MAE / mean |y|, every model, largest gap " ++ sci (worst maeGaps))
  , check "seasonalNaive-causal" (worst naiveGaps <= tolerance && length naiveGaps == length rows)
      (printf "p_naive = the audience of the same channel and slot 7 days before, %d rows, largest gap %s" (length naiveGaps) (sci (worst naiveGaps)))
  , check "lagMean-causal" (worst levelGaps <= tolerance)
      (printf "lag_mean = the mean log audience of days t-7, t-14, t-21, t-28, %d rows, largest gap %s" (length levelGaps) (sci (worst levelGaps)))
  , check "split" (length (A.train 0 days) == metaCount "train_rows" && length (A.test 0 days) == length rows)
      (printf "%d panel rows before the test start, %d from it on" (length (A.train 0 days)) (length (A.test 0 days)))
  ]
  ++ concat [ jcsLines m outs | (m, outs) <- [("jcs", jcsOut c), ("ns_jcs", nsOut c)] ]
  ++ [ check "ns-bounded" (and bounded)
         (printf "the network moves the utility by at most Σ|W2| = %.4f, %d rows" w2 (length bounded)) ]
  where
    r = run c
    rows = testRows r
    pairs m = [ (audience x, forecast m x) | x <- rows ]
    scaleGaps = [ gapOf (A.wape (A.scale 1000 (pairs m))) (A.wape (pairs m)) | m <- models c ]
    pooled =
      [ A.wape (bigs ++ rest) <= max (A.wape bigs) (A.wape rest)
      | m <- models c
      , let bigs = [ (audience x, forecast m x) | x <- rows, big x ]
      , let rest = [ (audience x, forecast m x) | x <- rows, not (big x) ] ]
    maeGaps = [ gapOf (A.wape p) (A.mae p `A.divZ` (A.actualSum p `A.divZ` A.size p)) | m <- models c, let p = pairs m ]
    metaCount k = maybe (-1) round (M.lookup k (meta (fresh r)) >>= number)
    days = map pDay (panel r)
    day0 = minimum days
    series = M.fromListWith IM.union
      [ ((pMarket p, pChannel p, pSlot p), IM.singleton (pDay p - day0) (pAudience p)) | p <- panel r ]
    at x t = fromMaybe (0 / 0) (M.lookup (market x, channel x, slot x) series >>= IM.lookup t)
    naiveGaps = [ gapOf (forecast "naive" x) (A.seasonalNaive (at x) (day x - day0)) | x <- rows ]
    levelGaps = [ gapOf (lagMean x) (A.lagMean (log . at x) (day x - day0)) | x <- rows ]
    w2 = sum (map abs (nW2 (ns r)))
    bounded = [ abs (un - ul) <= w2 | (sn, sl) <- zip (nsOut c) linear, (un, ul) <- zip (soU sn) sl ]
    linear = [ utilities (A.withoutNetwork (nsModel (ns r))) zs | zs <- testZ ]
    testZ = map (map snd) (bySlot (shareTest r) (map (standardise (std c)) (shareTest r)))

-- What Jcs.agda, JcsTheory.agda, Winner.agda and Pipeline.agda prove of the share layer, asked
-- of the forecasts that the Python wrote (p) and of the utilities computed here (u).
jcsLines :: Text -> [SlotOut] -> [Line]
jcsLines m outs =
  [ check (name "pipeline-coherent") (A.countOver [ (ph s, ps s) | s <- outs ] == (0 :: Double))
      (printf "no slot's channel forecasts add up to more than its pool forecast, %d slots" (length outs))
  , check (name "jcs-accounting") (worst accountGaps <= tolerance)
      ("channels + pool × outside share = pool forecast, largest gap " ++ sci (worst accountGaps))
  , check (name "jcs-odds") (worst oddsGaps <= tolerance)
      (printf "forecast / outside audience = exp(u), so the log-odds is the utility, %d rows, largest gap %s" (length oddsGaps) (sci (worst oddsGaps)))
  , check (name "pipeline-winner") (and [ A.winner (ps s) == A.winner (soU s) | s <- outs ])
      "the forecast winner of every slot is the channel with the largest utility"
  ]
  where
    name t = T.unpack m ++ " " ++ t
    ph = poolHat . firstOf . soRows
    ps = map (forecast m) . soRows
    accountGaps = [ gapOf (A.sumL (soForecast s) + ph s * A.jcsOutside (map exp (soU s))) (ph s) | s <- outs ]
    oddsGaps = concat [ zipWith (\p u -> gapOf (p / (ph s - A.sumL (ps s))) (exp u)) (ps s) (soU s) | s <- outs ]

-- joint ----------------------------------------------------------------------------------------

-- A test slot as Joint.agda takes it: the pool forecast p, the rows that are channels, and the
-- row of the rest of the pool when the group is the whole pool. The independent forecasts are
-- XGBoost + rivals for a channel and the "other" model for the rest.
type Grouping = [TestRow] -> (Double, [(TestRow, Jt.Row Double)], [Jt.Row Double])

-- The whole pool: 3 channels and the rest, C = 4, p = pool_hat.
wholePool :: Grouping
wholePool s = (poolHat x, channelRows s, [(pool x - sum (map audience s), otherHat x)])
  where x = firstOf s

-- The channels alone: C = 3, p = pool_hat - other_hat.
channelsOnly :: Grouping
channelsOnly s = (poolHat x - otherHat x, channelRows s, [])
  where x = firstOf s

channelRows :: [TestRow] -> [(TestRow, Jt.Row Double)]
channelRows s = [ (ch, (audience ch, forecast "xgb_rival" ch)) | ch <- s ]

joint :: Ctx -> [Line]
joint c = concat
  [ jointLines "pool" "3 channels and the rest of the pool, p = pool_hat" wholePool slots
  , jointLines "channels" "the 3 channels, p = pool_hat - other_hat" channelsOnly slots ]
  where slots = slotsOf (testRows (run c))

jointLines :: String -> String -> Grouping -> [[TestRow]] -> [Line]
jointLines tag what grouping slots =
  [ check (name "reconcile-coherent") (and [ Jt.fsum (Jt.reconcile p rs) == p | (p, rs) <- exact ])
      (printf "%s: the joint forecasts of every slot add up to p, %d slots, on Rational" what (length exact))
  , check (name "joint-gain") (and [ A.size rs * (Jt.sse rs - Jt.sse (Jt.reconcile p rs)) == Jt.bias rs * Jt.bias rs - Jt.poolErr p rs * Jt.poolErr p rs | (p, rs) <- exact ])
      "C · (SSE alone - SSE joint) = S² - ε² in every slot, exactly"
  , check (name "joint-le") (and [ Jt.sse (Jt.reconcile p rs) <= Jt.sse rs | (p, rs) <- holds ])
      (printf "SSE joint ≤ SSE alone in each of the %d slots with |ε| ≤ |S|" (length holds))
  , check (name "joint-total") (sum [ Jt.sse (Jt.reconcile p rs) | (p, rs) <- holds ] <= sum [ Jt.sse rs | (_, rs) <- holds ])
      "and over those slots together"
  , note (name "|ε| ≤ |S|") (printf "the assumption of joint-le holds in %s of the slots, and in %s of the slots with a big show"
      (share holds exact) (share (filter fst3 holdsE) (filter fst3 exactE)))
  , note (name "SSE group") (printf "every row of the group, all %d slots: alone %.1f, joint %.1f (%+.1f%%)" (length exact) alone together (change alone together))
  , note (name "SSE channels") (printf "the channel rows only: alone %.1f, joint %.1f (%+.1f%%)" chAlone chJoint (change chAlone chJoint))
  ]
  ++ [ note (name ("WAPE " ++ label)) (printf "channels alone %s, joint %s" (pct (A.wape a)) (pct (A.wape j)))
     | (label, keep) <- [("all", const True), ("big shows", big), ("contested big shows", clash)]
     , let (a, j) = channelPairs keep ]
  where
    name t = tag ++ " " ++ t
    groupsD = [ (any big s, p, map snd chans ++ rest, map fst chans) | s <- slots, let (p, chans, rest) = grouping s ]
    exactE = [ (e, toRational p, map (\(y, f) -> (toRational y, toRational f)) rs) | (e, p, rs, _) <- groupsD ]
    fst3 (e, _, _) = e
    holdsE = [ x | x@(_, p, rs) <- exactE, abs (Jt.poolErr p rs) <= abs (Jt.bias rs) ]
    exact = [ (p, rs) | (_, p, rs) <- exactE ]
    holds = [ (p, rs) | (_, p, rs) <- holdsE ]
    share xs ys = pct (fromIntegral (length xs) / fromIntegral (length ys))
    change a b = 100 * (b - a) / a :: Double
    alone = fromRational (sum [ Jt.sse rs | (_, rs) <- exact ]) :: Double
    together = fromRational (sum [ Jt.sse (Jt.reconcile p rs) | (p, rs) <- exact ]) :: Double
    sq ps = sum [ (y - f) * (y - f) | (y, f) <- ps ]
    (chAlone, chJoint) = let (a, j) = channelPairs (const True) in (sq a, sq j)
    -- The channels come first in the group, so `zip` pairs each with its joint forecast.
    channelPairs keep = unzip
      [ ((audience x, forecast "xgb_rival" x), (audience x, f))
      | (_, p, rs, chans) <- groupsD, (x, (_, f)) <- zip chans (Jt.reconcile p rs), keep x ]

-- mint -----------------------------------------------------------------------------------------

-- MinTrace(method="wls_struct") on a slot (pool = 3 channels + other) weights the pool by 4 and
-- each bottom series by 1, so every bottom forecast moves by (pool_hat - Σ bottoms) / 8.
mint :: Ctx -> [Line]
mint c =
  [ if "xgb_mint" `elem` models c
      then check "closed form = hierarchicalforecast" (worst rowGaps <= tolerance)
             (printf "XGBoost + rivals + (pool_hat - Σ channels - other) / 8 against p_xgb_mint, %d rows, largest gap %s" (length rowGaps) (sci (worst rowGaps)))
      else note "closed form = hierarchicalforecast" "hierarchicalforecast is not in the pinned nixpkgs: no p_xgb_mint in this run"
  ]
  ++ case M.lookup "xgb_mint" (results (committed r)) of
       Nothing -> []
       Just keys ->
         let gaps = [ scoreGap s (M.findWithDefault J.Null k keys) | (k, s) <- M.toList mine ]
             say = printf "the closed form scored: WAPE all %s, big shows %s, contested %s; largest gap to the committed numbers %s"
                     (val "wape_all") (val "wape_big_show") (val "wape_clash") (sci (worst gaps))
         in [ if xgboostOf (fresh r) == committedXgboost
                then check "closed form scores = committed" (worst gaps <= tolerance) say
                else note "closed form scores = committed" (say ++ ": this run has XGBoost " ++ T.unpack (xgboostOf (fresh r))) ]
  where
    r = run c
    cf = concat (M.elems (closedMint c))
    ordered = concat (slotsOf (testRows r))
    byRow = M.fromList (zip (map key ordered) cf)
    key x = (sid x, channel x)
    closed x = byRow M.! key x
    rowGaps = [ gapOf (forecast "xgb_mint" x) (closed x) | x <- testRows r ]
    mine = scoresOf c closed
    val k = case M.lookup k mine of Just (Value v) -> pct v; _ -> "?"

-- self-test ------------------------------------------------------------------------------------

-- A change to the run that one line must catch: (what changes, the change, group, line).
selfTests :: [(String, Run -> Run, String, String)]
selfTests =
  [ ("one JCS forecast 0.1% higher", onRow 0 (bump "jcs" 1.001), "metrics", "jcs wape_all")
  , ("one JCS forecast 0.1% higher", onRow 0 (bump "jcs" 1.001), "forward", "jcs")
  , ("one naive forecast 0.1% higher", onRow 5 (bump "naive" 1.001), "theorems", "seasonalNaive-causal")
  , ("one logit weight moved by 0.001", \r -> r { logit = (logit r) { lW = nudge 3 0.001 (lW (logit r)) } }, "gradient", "stationary")
  , ("one logit weight moved by 0.001", \r -> r { logit = (logit r) { lW = nudge 3 0.001 (lW (logit r)) } }, "forward", "jcs")
  , ("one output weight of the network moved by 0.001", \r -> r { ns = (ns r) { nW2 = nudge 0 0.001 (nW2 (ns r)) } }, "forward", "ns_jcs")
  , ("one pool forecast halved", onRow 0 (\x -> x { poolHat = poolHat x / 2 }), "theorems", "jcs jcs-odds")
  , ("one committed WAPE changed", \r -> r { committed = poke "naive" "wape_all" (committed r) }, "reproduce", "naive without XGBoost")
  , ("every bootstrap day moved to the next day", \r -> r { resamples = map (map (next (resamples r))) (resamples r) }, "metrics", "dnn wape_big_show_ci")
  ]
  where
    onRow i f r = r { testRows = [ if j == i then f x else x | (j, x) <- zip [0 :: Int ..] (testRows r) ] }
    bump m k x = x { forecasts = M.adjust (* k) m (forecasts x) }
    nudge i d xs = [ if j == i then x + d else x | (j, x) <- zip [0 :: Int ..] xs ]
    next picks i = (i + 1) `mod` (1 + maximum (concat picks))
    poke m k res = res { results = M.adjust (M.insert k (J.toJSON (0.5 :: Double))) m (results res) }
