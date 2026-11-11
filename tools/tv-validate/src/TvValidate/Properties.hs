-- Theorems of agda/src/TvAudience/ as Hedgehog properties of the Haskell definitions, on
-- Rational, where the two sides must be equal and not only close. Agda proves each statement
-- for every input; a property here shows that the Haskell definition is the one Agda means.
-- Each property has the name of its theorem and asks for the same hypotheses.
module TvValidate.Properties (properties) where

import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import qualified TvAudience as A
import TvValidate.Joint

type Q = Rational

q, nonneg, pos :: Gen Q
q = (/) <$> (fromIntegral <$> Gen.int (Range.linearFrom 0 (-60) 60)) <*> (fromIntegral <$> Gen.int (Range.linear 1 12))
nonneg = abs <$> q
pos = Gen.filter (> 0) nonneg

list :: Gen a -> Gen [a]
list = Gen.list (Range.linear 0 7)

some :: Gen a -> Gen [a]
some = Gen.list (Range.linear 1 7)

rows :: Gen [A.Row Q]
rows = list ((,) <$> q <*> q)

-- Rows with a positive sum of |actual|, as `wape-++-le` asks.
weighty :: Gen [A.Row Q]
weighty = Gen.filter ((> 0) . A.actualSum) (some ((,) <$> q <*> q))

-- A tree that Hedgehog can print; `grow` gives the tree of Trees.agda.
data Shape = L Q | N Int Q Shape Shape deriving (Show)

grow :: Shape -> A.Tree Q
grow (L v) = A.Leaf v
grow (N j th l r) = A.Node j th (grow l) (grow r)

tree :: Gen Shape
tree = Gen.recursive Gen.choice [L <$> q] [N <$> Gen.int (Range.linear 0 3) <*> q <*> tree <*> tree]

-- A row of four features, read by index.
point :: Gen [Q]
point = Gen.list (Range.singleton 4) q

at :: [Q] -> Int -> Q
at xs j = xs !! (j `mod` 4)

-- A network of d inputs and h hidden units (w, b, W1, b1, W2), and one input.
network :: Gen (([Q], Q, [[Q]], [Q], [Q]), [Q])
network = do
  d <- Gen.int (Range.linear 1 4)
  h <- Gen.int (Range.linear 0 3)
  let vec n = Gen.list (Range.singleton n) q
  p <- (,,,,) <$> vec d <*> q <*> Gen.list (Range.singleton h) (vec d) <*> vec h <*> vec h
  z <- vec d
  pure (p, z)

params :: ([Q], Q, [[Q]], [Q], [Q]) -> A.NsParams Q
params (w, b, w1, b1, w2) = A.Ns w b w1 b1 w2

clip :: Q -> Q
clip t = max (-1) (min t 1)

linear :: A.NsParams Q -> [Q] -> Q
linear p z = A.dot (A.w p) z + A.b p

-- Rows whose errors f - y lie in [lo, hi].
band :: Q -> Q -> Gen [Row Q]
band lo hi = some $ do
  y <- q
  t <- Gen.element [0, 1 / 4, 1 / 2, 3 / 4, 1]
  pure (y, y + lo + t * (hi - lo))

properties :: [(String, Property)]
properties =
  [ ("wape-nonneg", property $ do
      rs <- forAll rows
      assert (0 <= A.wape rs))
  , ("wape-perfect", property $ do
      ys <- forAll (list q)
      A.wape (A.perfect ys) === 0)
  , ("wape-scale", property $ do
      rs <- forAll rows
      c <- forAll (Gen.filter (/= 0) q)
      A.wape (A.scale c rs) === A.wape rs)
  , ("wape-++-le", property $ do
      rs <- forAll weighty
      qs <- forAll weighty
      assert (A.wape (rs ++ qs) <= max (A.wape rs) (A.wape qs)))
  , ("wape-mae", property $ do
      rs <- forAll weighty
      A.wape rs === A.mae rs `A.divZ` (A.actualSum rs `A.divZ` A.size rs))
  , ("jcs-sum", property $ do
      ws <- forAll (list nonneg)
      A.sumL (A.jcsShares ws) + A.jcsOutside ws === 1)
  , ("jcs-inside-lt-one", property $ do
      ws <- forAll (list nonneg)
      assert (A.sumL (A.jcsShares ws) < 1))
  , ("jcs-coherent", property $ do
      ws <- forAll (list nonneg)
      pool <- forAll nonneg
      assert (not (A.overPool (pool, A.jcsForecast pool ws))))
  , ("jcsShare-mono", property $ do
      ws <- forAll (list nonneg)
      a <- forAll q
      b <- forAll q
      assert (A.jcsShare ws (min a b) <= A.jcsShare ws (max a b)))
  , ("jcs-iia", property $ do
      ws <- forAll (list q)
      a <- forAll q
      b <- forAll q
      A.jcsShare ws a * b === A.jcsShare ws b * a)
  , ("jcs-rival", property $ do
      ws <- forAll (list nonneg)
      r <- forAll nonneg
      w <- forAll nonneg
      assert (A.jcsShare (r : ws) w <= A.jcsShare ws w))
  , ("jcs-odds", property $ do
      ws <- forAll (list nonneg)
      w <- forAll q
      A.jcsShare ws w `A.divZ` A.jcsOutside ws === w)
  , ("jcs-stable", property $ do
      ws <- forAll (list q)
      w <- forAll q
      k <- forAll pos
      A.stableShare k ws w === A.jcsShare ws w)
  , ("jcs-invert", property $ do
      ss <- forAll (Gen.filter ((< 1) . A.sumL) (list ((/ 8) <$> q)))
      A.jcsShares (A.invert ss) === ss)
  , ("jcs-diversion", property $ do
      a <- forAll nonneg
      rest <- forAll (list nonneg)
      b <- forAll q
      A.jcsShare rest b === A.jcsShare (a : rest) b `A.divZ` (1 - A.jcsShare (a : rest) a))
  , ("jcs-accounting", property $ do
      ws <- forAll (list nonneg)
      pool <- forAll q
      A.sumL (A.jcsForecast pool ws) + pool * A.jcsOutside ws === pool)
  , ("winner-scale", property $ do
      xs <- forAll (list q)
      c <- forAll pos
      A.winner (map (c *) xs) === A.winner xs)
  , ("jcs-winner", property $ do
      ws <- forAll (list nonneg)
      pool <- forAll pos
      A.winner (A.jcsForecast pool ws) === A.winner ws)
  , ("eval-between", property $ do
      t <- grow <$> forAll tree
      x <- at <$> forAll point
      assert (A.lo t <= A.eval x t && A.eval x t <= A.hi t))
  , ("predict-++", property $ do
      ts <- map grow <$> forAll (list tree)
      us <- map grow <$> forAll (list tree)
      base <- forAll q
      x <- at <$> forAll point
      A.predict base (ts ++ us) x === A.predict base ts x + A.treeSum x us)
  , ("ns-nests-jcs", property $ do
      ((w, b, w1, b1, w2), z) <- forAll network
      let off = params (w, b, w1, b1, map (const 0) w2)
      A.nsUtility clip off z === linear off z)
  , ("ns-bounded", property $ do
      (raw, z) <- forAll network
      let p = params raw
      assert (abs (A.nsUtility clip p z - linear p z) <= A.sumL (map abs (A.w2 p))))
  , ("resid-slot", property $ do
      pairs <- forAll (list ((,) <$> nonneg <*> q))
      let (ws, os) = unzip pairs
      A.sumL (A.resid (A.jcsShares ws) os) === (1 - A.sumL os) - A.jcsOutside ws)
  , ("resid-fit", property $ do
      os <- forAll (Gen.filter ((< 1) . A.sumL) (list ((/ 8) <$> q)))
      assert (all (== 0) (A.resid (A.jcsShares (A.invert os)) os)))
  , ("picks-sum", property $ do
      s <- forAll (list ((,) <$> Gen.int (Range.linear 0 3) <*> nonneg))
      let progs = [ A.Prog g h False | (g, h) <- s ]
      assert (and [ A.hype p + A.sumL (map A.hype others) == A.sumL (map A.hype progs) | (p, others) <- A.picks progs ]))
  , ("reconcile-coherent", property $ do
      rs <- forAll (some ((,) <$> q <*> q))
      p <- forAll q
      fsum (reconcile p rs) === p)
  , ("joint-gain", property $ do
      rs <- forAll (some ((,) <$> q <*> q))
      p <- forAll q
      A.size rs * (sse rs - sse (reconcile p rs)) === bias rs * bias rs - poolErr p rs * poolErr p rs)
  , ("joint-le", property $ do
      rs <- forAll rows
      t <- forAll (Gen.element [-1, -1 / 2, 0, 1 / 3, 1])
      let p = total rs + t * bias rs          -- so that |ε| = |t| |S| ≤ |S|
      assert (sse (reconcile p rs) <= sse rs))
  , ("joint-known", property $ do
      rs <- forAll (Gen.filter ((/= 0) . bias) (some ((,) <$> q <*> q)))
      assert (sse (reconcile (total rs) rs) < sse rs))
  , ("joint-common-bias", property $ do
      delta <- forAll nonneg
      rs <- forAll (some ((\y extra -> (y, y + delta + extra)) <$> q <*> nonneg))
      p <- forAll q
      slack <- forAll nonneg
      let eta = abs (poolErr p rs) + slack
          c = A.size rs
      assert ((c * delta) * (c * delta) - eta * eta <= c * (sse rs - sse (reconcile p rs))))
  , ("channel-no-worse", property $ do
      lo <- forAll nonneg
      t <- forAll (Gen.element [0, 1 / 2, 1])
      let hi = lo + t * lo                     -- lo ≤ hi ≤ 2 lo
      rs <- forAll (band lo hi)
      let k = step (total rs) rs
      assert (and [ abs (err (shiftRow k a)) <= abs (err a) | a <- rs ]))
  ]
