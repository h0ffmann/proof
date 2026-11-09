-- | The experiments of the video script (papers/contextual-bandits/roteiro/), in the
-- order of the scenes. @cabal run video@ prints the numbers that the script quotes, as
-- Markdown; the output is committed as papers/contextual-bandits/roteiro/resultados.pt-BR.md.
--
-- The arithmetic of pi is exact ("Pi"). The simulations use 'Double' and the pure RNG
-- of "ContextualBandit", so every run prints the same numbers.
module Main (main) where

import Data.List (foldl')
import qualified Data.Map.Strict as M
import Data.Ratio ((%))
import Text.Printf (printf)

import ContextualBandit
import Pi
import Video

main :: IO ()
main = do
  putStrLn "# Saídas do código do roteiro\n"
  putStrLn "Feito por `cabal run video` (haskell/app/Video.hs). Aritmética exata para π; Double para as simulações."
  section "Cena 1.1 e 3.4: crença atual contra crença nova (`beliefs`)"
  beliefs
  section "Cena 1.3: dígitos certos por termo (`Pi.hs`)"
  digitsTable
  section "Cena 1.3: um braço, Leibniz: aproveitar π(N) ou explorar π(N+1) (`singleArmed`, 20 rodadas, ε = 0,2)"
  singleArmed 20
  section "Cena 1.4: três braços, Leibniz, Gauss-Legendre, Ramanujan (`multiArmed`, 20 rodadas, ε = 0,2)"
  multiArmed 20
  section "Cenas 2.3 e 2.4: teste A/B contra as regras de bandit (`abVsBandit`)"
  abVsBandit
  section "Cena 3.2: o laço de fora escolhe o ε do laço de dentro (`rsiLoop`, 200 episódios de 500 rodadas)"
  rsiLoop

------------------------------------------------------------------------
-- Scenes 1.1 and 3.4: the current belief against the new belief

-- | Beta-Bernoulli, as 'Models.betaBernoulli': (successes + 1, failures + 1) per option.
type Beta = (Double, Double)

betaMean :: Beta -> Double
betaMean (successes, failures) = successes / (successes + failures)

-- | One signal of the user, 1 or 0, moves one count.
observe :: Beta -> Double -> Beta
observe (successes, failures) r = (successes + r, failures + 1 - r)

-- | The option with the highest mean. No tie occurs in this scene.
pick :: [Beta] -> Int
pick = argmax . map betaMean

beliefs :: IO ()
beliefs = do
  let current = [(8, 4), (6, 6)]                              -- short answer, long answer
      new     = [ foldl' observe (8, 4) [0, 0]                 -- two signals against the short one
                , foldl' observe (6, 6) [1, 1, 1, 1] ]         -- four signals for the long one
      line label bs = putStrLn (label ++ "  " ++ decimals 2 (map betaMean bs) ++ " -> escolhe " ++ show (pick bs))
  putStrLn "```text"
  line "crença atual" current
  line "crença nova " new
  putStrLn ("mudou de ideia? " ++ show (pick current /= pick new))
  putStrLn "```"

------------------------------------------------------------------------
-- Scene 1.3: the digits that each series gives

digitsTable :: IO ()
digitsTable = do
  table ["termos", "Leibniz", "Gauss-Legendre", "Ramanujan"]
    [ show n : [ show (digitsCorrect (approximation s n)) | s <- [leibnizSeries, gaussLegendreSeries, ramanujanSeries] ]
    | n <- [1 .. 6] ]
  -- 100.000 terms of Leibniz: exact fractions are slow here, and Double has the 5 digits.
  let leibniz100k = 4 * sum [ (-1) ^ k / (2 * fromIntegral k + 1) | k <- [0 .. 99999 :: Int] ] :: Double
      agree = length (takeWhile id (zipWith (==) digitsOfPi (show leibniz100k))) - 1   -- minus the point
  row ["100.000", show agree, "·", "·"]

------------------------------------------------------------------------
-- Scenes 1.3 and 1.4: pi, with the user as the reward

-- | The simulated user grades by the distance to pi (Lean: @byDistance@). Pi is the
-- 60-digit reference of "Pi", as a rational.
viewer :: User Rational
viewer = byDistance (read (filter (/= '.') digitsOfPi) % 10 ^ (60 :: Int))

-- | Scene 1.3, one arm (Leibniz). Arm 0 exploits: show pi(N) again. Arm 1 explores:
-- compute pi(N+1). The agent learns which action the user rewards.
singleArmed :: Int -> IO ()
singleArmed rounds = do
  let model = tabular 2 :: RewardModel () (Tab ())
      approx = approximation leibnizSeries
      start  = OneArm { terms = 1, shown = approx 1, lastGrade = grade viewer (approx 1) }
      -- Both actions start from the grade of pi(1), so the agent has no preference.
      belief0 = foldl' (update model) (prior model) [ Obs () arm (toDouble (lastGrade start)) | arm <- [0, 1] ]

      round' (agent, belief, history) = do
        arm <- act model (epsGreedy 0.2) belief ()
        let agent' = step approx viewer agent (if arm == 0 then Exploit else Explore)
            reward = toDouble (lastGrade agent')   -- to exploit hears the same grade again
        pure (agent', update model belief (Obs () arm reward), arm : history)

      (agentEnd, beliefEnd, chosen) = runRand 3 (times rounds round' (start, belief0, []))

  table ["ação", "vezes", "média da nota do usuário"]
    [ [label, show (count arm chosen), decimal2 (mean (estimate model beliefEnd () arm))]
    | (arm, label) <- [(0, "aproveitar π(N)"), (1, "explorar π(N+1)")] ]
  printf "\nπ(N) no fim: N = %d, %d dígitos certos\n" (terms agentEnd) (digitsCorrect (shown agentEnd))

-- | Scene 1.4, three arms, one term per pull. The first three rounds pull each arm once.
multiArmed :: Int -> IO ()
multiArmed rounds = do
  let model = tabular 3 :: RewardModel () (Tab ())
      arms  = [leibnizSeries, gaussLegendreSeries, ramanujanSeries]

      round' (pulled, belief, history) = do
        let k = length history
        arm <- if k < length arms then pure k else act model (epsGreedy 0.2) belief ()
        let pulled' = adjust (+ 1) arm pulled
            reward  = toDouble (grade viewer (approximation (arms !! arm) (pulled' !! arm)))
        pure (pulled', update model belief (Obs () arm reward), arm : history)

      (pulledEnd, beliefEnd, chosen) = runRand 3 (times rounds round' (map (const 0) arms, M.empty, []))

  table ["braço", "puxadas", "média da nota do usuário", "dígitos certos no fim"]
    [ [name s, show (count arm chosen), decimal2 (mean (estimate model beliefEnd () arm)), show (digitsCorrect (approximation s n))]
    | (arm, s, n) <- zip3 [0 ..] arms pulledEnd ]

------------------------------------------------------------------------
-- Scenes 2.3 and 2.4: the ice-cream shop, the A/B test against the bandit rules

data Context = Morning | Evening
  deriving (Eq, Ord, Show)

-- | The secret rates of app/Main.hs (@ctr@): in the morning flavour 1 sells best, in
-- the evening flavour 2. The policies never see them.
rate :: Context -> Arm -> Double
rate Morning = ([0.05, 0.12, 0.08] !!)
rate Evening = ([0.06, 0.04, 0.15] !!)

-- | One client: a sale (1) with the probability of the flavour at that hour.
shop :: Context -> Arm -> Rand Double
shop c arm = bernoulli (rate c arm)

randomContext :: Rand Context
randomContext = (\u -> if u < 0.5 then Morning else Evening) <$> uniform01

-- | A policy of the comparison. A contextual one keeps a belief per hour; the other
-- keeps one belief for the whole day.
data Contender = Contender
  { label      :: String
  , contextual :: Bool
  , ruleAt     :: Int -> DecisionRule   -- ^ the rule may depend on the round (A/B: 'etc')
  }

contenders :: Int -> [Contender]
contenders horizon =
  [ Contender "teste A/B (T/2, depois commit)"        True  (etc (horizon `div` 2))
  , Contender "A/B sem contexto (T/2, depois commit)" False (etc (horizon `div` 2))
  , Contender "eps-gulosa 0,1"                        True  (const (epsGreedy 0.1))
  , Contender "UCB beta=2"                            True  (const (ucb 2))
  ]

-- | The regret of one contender over @horizon@ rounds: the sum, round by round, of the
-- best mean at that hour minus the mean of the flavour it showed.
regret :: Int -> Contender -> Int -> Double
regret horizon contender seed = runRand (fromIntegral seed) $ do
  let byHour = tabular 3 :: RewardModel Context (Tab Context)
      byDay  = tabular 3 :: RewardModel ()      (Tab ())
      round' (hourBelief, dayBelief, acc) k = do
        c   <- randomContext
        arm <- if contextual contender
                 then act byHour (ruleAt contender k) hourBelief c
                 else act byDay  (ruleAt contender k) dayBelief  ()
        r   <- shop c arm
        let best = maximum (map (rate c) [0 .. 2])
        pure (update byHour hourBelief (Obs c arm r), update byDay dayBelief (Obs () arm r), acc + best - rate c arm)
  (_, _, total) <- foldM' round' (M.empty, M.empty, 0) [0 .. horizon - 1]
  pure total

abVsBandit :: IO ()
abVsBandit = do
  let horizon = 5000; seeds = 20
  printf "T = %d, média de %d sementes, 2 contextos x 3 braços\n\n" horizon seeds
  table ["política", "arrependimento"]
    [ [label c, decimal1 (average [ regret horizon c seed | seed <- [1 .. seeds] ])] | c <- contenders horizon ]

------------------------------------------------------------------------
-- Scene 3.2: the smallest recursive loop. The arms of the outer bandit are values of
-- ε for the inner bandit; the reward of the outer bandit is the mean gain of an episode.

-- | The inner agent: ε-greedy in the shop for @rounds@ clients, from an empty belief.
-- Returns the total gain.
episode :: Double -> Int -> Rand Double
episode epsilon rounds = do
  let model = tabular 3 :: RewardModel Context (Tab Context)
      client (belief, gain) = do
        c   <- randomContext
        arm <- act model (epsGreedy epsilon) belief c
        r   <- shop c arm
        pure (update model belief (Obs c arm r), gain + r)
  snd <$> times rounds client (M.empty, 0)

rsiLoop :: IO ()
rsiLoop = do
  let epsilons = [1, 0.5, 0.1, 0.01]
      clients  = 500
      model    = tabular (length epsilons) :: RewardModel () (Tab ())
      run (belief, history) = do
        i    <- act model (outer 0.2) belief ()
        gain <- episode (epsilons !! i) clients
        pure (update model belief (Obs () i (gain / fromIntegral clients)), i : history)
      (beliefEnd, chosen) = runRand 2026 (times 200 run (M.empty, []))
  table ["ε do agente de dentro", "vezes escolhido", "ganho médio por rodada"]
    [ [ptBR (printf "%g" e), show (count i chosen), decimal3 (mean (estimate model beliefEnd () i))]
    | (i, e) <- zip [0 ..] epsilons ]

------------------------------------------------------------------------
-- The tabular model of Examples.lean, for any context:
-- mean = sum / count, width = 1 / (count + 1).

type Tab c = M.Map (c, Arm) (Double, Int)   -- ^ (sum of rewards, count) per (context, arm)

tabular :: Ord c => Int -> RewardModel c (Tab c)
tabular k = RewardModel
  { numArms  = k
  , prior    = M.empty
  , update   = \b (Obs c arm r) -> M.insertWith add (c, arm) (r, 1) b
  , estimate = \b c arm ->
      let (total, n) = M.findWithDefault (0, 0) (c, arm) b
      in Estimate (if n == 0 then 0 else total / fromIntegral n) (1 / (fromIntegral n + 1))
  , sample   = \b c arm -> pure (mean (estimate (tabular k) b c arm))
  }
  where add (s1, n1) (s0, n0) = (s0 + s1, n0 + n1)

------------------------------------------------------------------------
-- Small helpers

-- | 1 with probability @p@, else 0.
bernoulli :: Double -> Rand Double
bernoulli p = (\u -> if u < p then 1 else 0) <$> uniform01

-- | Run a monadic step @n@ times.
times :: Monad m => Int -> (s -> m s) -> s -> m s
times n f s0 = foldM' (\s _ -> f s) s0 [1 .. n]

foldM' :: Monad m => (s -> a -> m s) -> s -> [a] -> m s
foldM' _ s []       = pure s
foldM' f s (x : xs) = f s x >>= \s' -> foldM' f s' xs

adjust :: (a -> a) -> Int -> [a] -> [a]
adjust f i xs = [ if j == i then f x else x | (j, x) <- zip [0 ..] xs ]

count :: Eq a => a -> [a] -> Int
count x = length . filter (== x)

average :: [Double] -> Double
average xs = sum xs / fromIntegral (length xs)

toDouble :: Rational -> Double
toDouble = fromRational

-- | A Markdown table: the header, then one row per list.
table :: [String] -> [[String]] -> IO ()
table header rows = do
  row header
  row (map (const "---") header)
  mapM_ row rows

row :: [String] -> IO ()
row cells = putStrLn ("| " ++ foldr1 (\c acc -> c ++ " | " ++ acc) cells ++ " |")

section :: String -> IO ()
section title = putStrLn ("\n## " ++ title ++ "\n")

-- | Numbers as Brazil writes them: a comma before the decimals.
ptBR :: String -> String
ptBR = map (\ch -> if ch == '.' then ',' else ch)

decimal1, decimal2, decimal3 :: Double -> String
decimal1 = ptBR . printf "%.1f"
decimal2 = ptBR . printf "%.2f"
decimal3 = ptBR . printf "%.3f"

-- | A list of numbers with @n@ decimals, as @[0,67, 0,50]@.
decimals :: Int -> [Double] -> String
decimals n xs = "[" ++ foldr1 (\x acc -> x ++ ", " ++ acc) (map (ptBR . printf "%.*f" n) xs) ++ "]"
