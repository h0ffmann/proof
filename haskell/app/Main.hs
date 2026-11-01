-- | Runnable examples:  runghc -isrc app/Main.hs
module Main (main) where

import qualified Data.Map.Strict as M
import Text.Printf (printf)
import ContextualBandit
import Models

------------------------------------------------------------------------
-- 0. Spec check: reproduce the Lean #eval outputs from Examples.lean

data Ctx = Morning | Evening deriving (Eq, Ord, Show)

-- Same model as Lean's `tabular`: mean = sum/count, width = 1/(count+1).
tabular :: Int -> RewardModel Ctx (M.Map (Ctx, Arm) (Double, Int))
tabular k = RewardModel
  { numArms = k, prior = M.empty
  , update = \b (Obs c a r) -> M.insertWith (\(s1, n1) (s0, n0) -> (s0 + s1, n0 + n1)) (c, a) (r, 1) b
  , estimate = \b c a -> let (s, n) = M.findWithDefault (0, 0) (c, a) b
                         in Estimate (if n == 0 then 0 else s / fromIntegral n) (1 / (fromIntegral n + 1))
  , sample = \b c a -> pure (mean (estimate (tabular k) b c a))
  }

leanHistory :: [Obs Ctx]
leanHistory =
  [ Obs Morning 0 0, Obs Morning 1 1, Obs Morning 1 1, Obs Morning 2 0
  , Obs Evening 0 0, Obs Evening 1 0, Obs Evening 2 1 ]

specCheck :: IO ()
specCheck = do
  putStrLn "== 0. Spec check against Lean #eval =="
  let g  = policy (tabular 3) greedy leanHistory Morning
      g' = policy (tabular 3) greedy leanHistory Evening
      e  = policy (tabular 3) (epsGreedy 0.1) leanHistory Morning
      close xs ys = and (zipWith (\x y -> abs (x - y) < 1e-12) xs ys)
  printf "greedy morning  %s  (Lean: [0, 1, 0])          %s\n" (show g) (ok (g == [0, 1, 0]))
  printf "greedy evening  %s  (Lean: [0, 0, 1])          %s\n" (show g') (ok (g' == [0, 0, 1]))
  printf "eps 0.1 morning %s  (Lean: [1/30, 14/15, 1/30]) %s\n" (show (map (roundTo 4) e))
    (ok (close e [1 / 30, 14 / 15, 1 / 30]))
  where ok b = if b then "OK" else "MISMATCH" :: String

roundTo :: Int -> Double -> Double
roundTo n x = fromIntegral (round (x * 10 ^ n) :: Integer) / 10 ^ n

------------------------------------------------------------------------
-- 1. Discrete contexts, 0/1 rewards (e.g. which banner to show by time of day)

-- True click-through rates: morning favours arm 1, evening favours arm 2.
ctr :: Ctx -> Arm -> Double
ctr Morning a = [0.05, 0.12, 0.08] !! a
ctr Evening a = [0.06, 0.04, 0.15] !! a

bernoulliEnv :: Ctx -> Arm -> Rand Double
bernoulliEnv c a = do u <- uniform01; pure (if u < ctr c a then 1 else 0)

randomCtx :: Rand Ctx
randomCtx = (\u -> if u < 0.5 then Morning else Evening) <$> uniform01

discreteAgents :: [Agent Ctx (BetaBelief Ctx)]
discreteAgents =
  [ Agent "greedy"           m (act m greedy)
  , Agent "eps-greedy 0.1"   m (act m (epsGreedy 0.1))
  , Agent "UCB beta=2"       m (act m (ucb 2))
  , Agent "Thompson"         m (thompsonArm m)
  ]
  where m = betaBernoulli 3

-- | Expected cumulative regret (uses true means, so there's no reward noise in the metric).
regretOf :: (c -> Arm -> Double) -> Int -> [c] -> [(Arm, Double)] -> Double
regretOf mu k cs log' = sum [ maximum [mu c b | b <- [0 .. k - 1]] - mu c a | (c, (a, _)) <- zip cs log' ]

avgRegret :: Int -> Int -> (Rand [c]) -> (c -> Arm -> Double) -> (c -> Arm -> Rand Double)
          -> Agent c b -> Double
avgRegret seeds k genCtxs mu env agent =
  sum [ runRand (fromIntegral s) $ do
          cs <- genCtxs
          (_, lg) <- runAgent agent env cs
          pure (regretOf mu k cs lg)
      | s <- [1 .. seeds] ] / fromIntegral seeds

example1 :: IO ()
example1 = do
  let t = 5000 :: Int
  putStrLn "\n== 1. Beta-Bernoulli model, 2 contexts x 3 arms, T = 5000, avg of 20 runs =="
  mapM_ (\ag -> printf "%-16s regret %7.1f\n" (agentName ag)
                  (avgRegret 20 3 (mapM (const randomCtx) [1 .. t]) ctr bernoulliEnv ag))
        discreteAgents

------------------------------------------------------------------------
-- 2. Linear contextual bandit (LinUCB / linear Thompson sampling)

thetas :: [[Double]]
thetas = [[0.5, 0.1, 0.0], [0.0, 0.6, 0.1], [0.2, 0.0, 0.7], [0.3, 0.3, 0.3]]

linMu :: [Double] -> Arm -> Double
linMu x a = sum (zipWith (*) x (thetas !! a))

linEnv :: [Double] -> Arm -> Rand Double
linEnv x a = normal (linMu x a) 0.3

randomFeatures :: Rand [Double]
randomFeatures = do
  v <- mapM (const uniform01) [1 :: Int, 2, 3]
  let n = sqrt (sum (map (^ (2 :: Int)) v))
  pure (map (/ n) v)

example2 :: IO ()
example2 = do
  let t = 2000 :: Int
      m = bayesLinear 4 3 id 1.0 0.3
      agents =
        [ Agent "greedy"         m (act m greedy)
        , Agent "eps-greedy 0.1" m (act m (epsGreedy 0.1))
        , Agent "LinUCB beta=2"  m (act m (ucb 2))
        , Agent "LinTS"          m (thompsonArm m)
        ]
  putStrLn "\n== 2. Bayesian linear model, d = 3 features, 4 arms, T = 2000, avg of 10 runs =="
  mapM_ (\ag -> printf "%-16s regret %7.1f\n" (agentName ag)
                  (avgRegret 10 4 (mapM (const randomFeatures) [1 .. t]) linMu linEnv ag))
        agents

------------------------------------------------------------------------
-- 3. Plugging in a model you already have

-- Pretend this came from an offline-trained classifier, a GP or a Stan fit.
-- It gives a predictive mean and std for each (user segment, offer).
externalPredict :: () -> (Int, Bool) -> Arm -> (Double, Double)
externalPredict () (age, isMobile) a =
  let base = [0.10, 0.07, 0.12] !! a
      lift = if isMobile && a == 1 then 0.08 else 0
      ageAdj = if age > 40 && a == 2 then -0.05 else 0
  in (base + lift + ageAdj, [0.01, 0.04, 0.02] !! a)

example3 :: IO ()
example3 = do
  let m = fromPredictor 3 () const externalPredict      -- frozen model
      ctxs = [(25, True), (55, False)]
  putStrLn "\n== 3. External predictive model -> decision rules =="
  mapM_ (\c -> do
           let est = [estimate m () c a | a <- [0 .. 2]]
           printf "context %-12s means %-18s greedy -> arm %d, UCB(2) -> arm %d, eps(0.1) -> %s\n"
             (show c) (show (map (roundTo 3 . mean) est))
             (argmax (map mean est)) (argmax (map (ucbScore 2) est))
             (show (map (roundTo 3) (epsGreedy 0.1 est))))
        ctxs
  let draws = runRand 7 (mapM (const (thompsonArm m () (25 :: Int, True))) [1 .. 1000 :: Int])
  printf "Thompson on (25,True), 1000 draws: arm counts %s\n"
    (show [length (filter (== a) draws) | a <- [0 .. 2]])

main :: IO ()
main = specCheck >> example1 >> example2 >> example3
