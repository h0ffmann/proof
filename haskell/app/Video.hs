-- | The experiments of the video script (papers/contextual-bandits/roteiro/), in the
-- order of the scenes. `cabal run video` writes the numbers that the script quotes. The
-- output is committed as papers/contextual-bandits/roteiro/resultados.md.
module Main (main) where

import qualified Data.Map.Strict as M
import Data.List (foldl')
import Data.Ratio ((%))
import Text.Printf (printf)
import ContextualBandit
import Pi
import Video

------------------------------------------------------------------------
-- The tabular model of Examples.lean (Lean), for any context: mean = sum/count, width = 1/(count+1)

type Tab c = M.Map (c, Arm) (Double, Int)

tabular :: Ord c => Int -> RewardModel c (Tab c)
tabular k = RewardModel
  { numArms = k, prior = M.empty
  , update = \b (Obs c a r) -> M.insertWith (\(s1, n1) (s0, n0) -> (s0 + s1, n0 + n1)) (c, a) (r, 1) b
  , estimate = \b c a -> let (s, n) = M.findWithDefault (0, 0) (c, a) b
                         in Estimate (if n == 0 then 0 else s / fromIntegral n) (1 / (fromIntegral n + 1))
  , sample = \b c a -> pure (mean (estimate (tabular k) b c a))
  }

br :: Rational -> Double
br = fromRational

ptBR :: String -> String
ptBR = map (\ch -> if ch == '.' then ',' else ch)

------------------------------------------------------------------------
-- Scenes 1.3 and 1.4: pi, the user is the reward

-- | The reference of the simulated user: pi to 60 digits, as a rational.
piRef :: Rational
piRef = read (filter (/= '.') piDigits) % (10 ^ (60 :: Int))

-- | The user of the script. The grade is the distance to pi, in [0, 1] (Lean: byDistance).
viewer :: User Rational
viewer = byDistance piRef

digitsTable :: IO ()
digitsTable = do
  putStrLn "| termos | Leibniz | Gauss-Legendre | Ramanujan |"
  putStrLn "|---|---|---|---|"
  let row n = printf "| %d | %d | %d | %d |\n" n (d leibnizS n) (d gaussLegendreS n) (d ramanujanS n)
      d s n = digitsCorrect (value (iterate next s !! n))
  mapM_ row [1 .. 6 :: Int]
  -- 100.000 terms of Leibniz: Double is enough for 5 digits, and exact fractions are slow.
  let l100k = 4 * sum [(-1) ^ k / (2 * fromIntegral k + 1) | k <- [0 .. 99999 :: Int]] :: Double
  printf "| 100.000 | %d | · | · |\n" (length (takeWhile id (zipWith (==) piDigits (show l100k))) - 1)

-- | Scene 1.3, one arm (Leibniz): exploit shows pi(N) again, explore computes pi(N+1).
singleArmed :: Int -> IO ()
singleArmed rounds = do
  let approx n = value (iterate next leibnizS !! n)
      s0 = SA 1 (approx 1) (reward viewer (approx 1))
      m = tabular 2 :: RewardModel () (Tab ())
      -- The two actions start with the grade of the user for pi(1). Thus there is no preference.
      b0 = update m (update m (prior m) (Obs () 0 (br (saLastReward s0)))) (Obs () 1 (br (saLastReward s0)))
      go :: Int -> SA -> Tab () -> [Int] -> Rand (SA, Tab (), [Int])
      go 0 s b acc = pure (s, b, reverse acc)
      go k s b acc = do
        a <- act m (epsGreedy 0.2) b ()
        let action = if a == 0 then Exploit else Explore
            s' = step approx viewer s action
            r = br (saLastReward s')   -- exploitation: the user gives the same grade for pi(N)
        go (k - 1) s' (update m b (Obs () a r)) (a : acc)
      (sEnd, bEnd, log') = runRand 3 (go rounds s0 b0 [])
  putStrLn "| ação | vezes | média da nota do usuário |"
  putStrLn "|---|---|---|"
  let count a = length (filter (== a) log')
  putStrLn . ptBR $ printf "| aproveitar π(N) | %d | %.2f |" (count 0) (mean (estimate m bEnd () 0))
  putStrLn . ptBR $ printf "| explorar π(N+1) | %d | %.2f |" (count 1) (mean (estimate m bEnd () 1))
  printf "\nπ(N) no fim: N = %d, %d dígitos certos\n" (saN sEnd) (digitsCorrect (saShown sEnd))

-- | Scene 1.4, three arms: Leibniz, Gauss-Legendre, Ramanujan. One term per pull.
multiArmed :: Int -> IO ()
multiArmed rounds = do
  let m = tabular 3 :: RewardModel () (Tab ())
      arms0 = [leibnizS, gaussLegendreS, ramanujanS]
      go :: Int -> [Series] -> Tab () -> [Int] -> Rand ([Series], Tab (), [Int])
      go 0 ss b acc = pure (ss, b, reverse acc)
      go k ss b acc = do
        a <- if k > rounds - 3 then pure (rounds - k) else act m (epsGreedy 0.2) b ()  -- first, each arm one time
        let ss' = [if i == a then next s else s | (i, s) <- zip [0 ..] ss]
            r = br (reward viewer (value (ss' !! a)))
        go (k - 1) ss' (update m b (Obs () a r)) (a : acc)
      (ssEnd, bEnd, log') = runRand 3 (go rounds arms0 M.empty [])
  putStrLn "| braço | puxadas | média da nota do usuário | dígitos certos no fim |"
  putStrLn "|---|---|---|---|"
  mapM_ (\(i, s) -> putStrLn . ptBR $ printf "| %s | %d | %.2f | %d |" (seriesName s)
            (length (filter (== i) log')) (mean (estimate m bEnd () i)) (digitsCorrect (value s)))
        (zip [0 ..] ssEnd)

------------------------------------------------------------------------
-- Scene 2.3 and 2.4: the ice-cream shop, A/B against the bandit rules

data Ctx = Manha | Noite deriving (Eq, Ord, Show)

-- | The secret rates, the ones of app/Main.hs (`ctr`). In the morning flavour 1 sells best; in the evening, flavour 2.
rate :: Ctx -> Arm -> Double
rate Manha a = [0.05, 0.12, 0.08] !! a
rate Noite a = [0.06, 0.04, 0.15] !! a

shop :: Ctx -> Arm -> Rand Double
shop c a = do u <- uniform01; pure (if u < rate c a then 1 else 0)

randomCtx :: Rand Ctx
randomCtx = (\u -> if u < 0.5 then Manha else Noite) <$> uniform01

-- | The expected regret of one policy in t rounds: the sum of (best mean − mean of the selected arm).
regretRun :: String -> Int -> Int -> Double
regretRun name t seed = runRand (fromIntegral seed) $ do
  let m = tabular 3 :: RewardModel Ctx (Tab Ctx)
      m1 = tabular 3 :: RewardModel () (Tab ())
      go :: Int -> Tab Ctx -> Tab () -> Double -> Rand Double
      go k b b1 acc
        | k == t = pure acc
        | otherwise = do
            c <- randomCtx
            a <- case name of
                   "teste A/B (T/2, depois commit)"        -> act m (etc (t `div` 2) k) b c
                   "A/B sem contexto (T/2, depois commit)" -> act m1 (etc (t `div` 2) k) b1 ()
                   "eps-gulosa 0,1"                        -> act m (epsGreedy 0.1) b c
                   "UCB beta=2"                            -> act m (ucb 2) b c
                   _                                       -> error name
            r <- shop c a
            let best = maximum [rate c x | x <- [0 .. 2]]
            go (k + 1) (update m b (Obs c a r)) (update m1 b1 (Obs () a r)) (acc + best - rate c a)
  go 0 M.empty M.empty 0

abVsBandit :: IO ()
abVsBandit = do
  let t = 5000; seeds = 20 :: Int
  printf "T = %d, média de %d sementes, 2 contextos x 3 braços\n" t seeds
  putStrLn "| política | arrependimento |"
  putStrLn "|---|---|"
  mapM_ (\p -> putStrLn . ptBR $ printf "| %s | %.1f |" p
            (sum [regretRun p t s | s <- [1 .. seeds]] / fromIntegral seeds))
        ["teste A/B (T/2, depois commit)", "A/B sem contexto (T/2, depois commit)", "eps-gulosa 0,1", "UCB beta=2"]

------------------------------------------------------------------------
-- Scene 3.2: the smallest recursive loop. The arms of the outer bandit are epsilons for the inner bandit.

episode :: Double -> Int -> Rand Double
episode eps rounds = do
  let m = tabular 3 :: RewardModel Ctx (Tab Ctx)
      go :: Int -> Tab Ctx -> Double -> Rand Double
      go 0 _ g = pure g
      go k b g = do
        c <- randomCtx
        a <- act m (epsGreedy eps) b c
        r <- shop c a
        go (k - 1) (update m b (Obs c a r)) (g + r)
  go rounds M.empty 0

rsiLoop :: IO ()
rsiLoop = do
  let epsilons = [1, 0.5, 0.1, 0.01]
      mo = tabular 4 :: RewardModel () (Tab ())
      go :: Int -> Tab () -> [Int] -> Rand (Tab (), [Int])
      go 0 b acc = pure (b, reverse acc)
      go k b acc = do
        i <- act mo (outer 0.2) b ()
        g <- episode (epsilons !! i) 500
        go (k - 1) (update mo b (Obs () i (g / 500))) (i : acc)
      (bEnd, log') = runRand 2026 (go 200 M.empty [])
  putStrLn "| ε do agente de dentro | vezes escolhido | ganho médio por rodada |"
  putStrLn "|---|---|---|"
  mapM_ (\(i, e) -> putStrLn . ptBR $ printf "| %g | %d | %.3f |" e (length (filter (== i) log'))
            (mean (estimate mo bEnd () i)))
        (zip [0 ..] epsilons)

------------------------------------------------------------------------
-- Scene 1.1 and 3.4: current belief against new belief (Beta-Bernoulli, as Models.hs)

beliefs :: IO ()
beliefs = do
  let meanB (al, be) = al / (al + be) :: Double
      pick xs = snd (maximum [(meanB x, i) | (i, x) <- zip [0 :: Int ..] xs])  -- no tie occurs here
      atual = [(8, 4), (6, 6)]
      upd (al, be) r = (al + r, be + 1 - r)
      nova = [foldl' upd (8, 4) [0, 0], foldl' upd (6, 6) [1, 1, 1, 1]]
  putStrLn . ptBR $ printf "crença atual  %s -> escolhe %d" (show (map (\x -> fromIntegral (round (meanB x * 100) :: Int) / 100 :: Double) atual)) (pick atual)
  putStrLn . ptBR $ printf "crença nova   %s -> escolhe %d" (show (map (\x -> fromIntegral (round (meanB x * 100) :: Int) / 100 :: Double) nova)) (pick nova)
  printf "mudou de ideia? %s\n" (show (pick atual /= pick nova))

main :: IO ()
main = do
  putStrLn "# Saídas do código do roteiro\n"
  putStrLn "Feito por `cabal run video` (haskell/app/Video.hs). Aritmética exata para π; Double para as simulações.\n"
  putStrLn "## Cena 1.1 e 3.4: crença atual contra crença nova (`beliefs`)\n\n```text"
  beliefs
  putStrLn "```\n\n## Cena 1.3: dígitos certos por termo (`Pi.hs`)\n"
  digitsTable
  putStrLn "\n## Cena 1.3: um braço, Leibniz: aproveitar π(N) ou explorar π(N+1) (`singleArmed`, 20 rodadas, ε = 0,2)\n"
  singleArmed 20
  putStrLn "\n## Cena 1.4: três braços, Leibniz, Gauss-Legendre, Ramanujan (`multiArmed`, 20 rodadas, ε = 0,2)\n"
  multiArmed 20
  putStrLn "\n## Cenas 2.3 e 2.4: teste A/B contra as regras de bandit (`abVsBandit`)\n"
  abVsBandit
  putStrLn "\n## Cena 3.2: o laço de fora escolhe o ε do laço de dentro (`rsiLoop`, 200 episódios de 500 rodadas)\n"
  rsiLoop
