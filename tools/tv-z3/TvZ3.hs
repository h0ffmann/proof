-- Z3 checks of the JCS model of tv-audience and of its logit fit, the port audit's way: one
-- statement a line, proved by refutation over the exact reals. The statements mirror the theorems
-- of agda/src/TvAudience/ name for name (Jcs, JcsTheory, Neural, LogitFit); Agda proves each one
-- for every slot length under --safe, Z3 re-checks the shape at two or three channels here. The
-- loss of the fit itself needs the exponential, which neither side has: both take the weights
-- w = exp(u) >= 0 and the observed shares as given, and prove the resid layer of the gradient.
module TvZ3 (title, statements) where

import Data.SBV
import Report (Statement (..))

title :: String
title = "tv-audience (Z3)"

reals :: [String] -> Symbolic [SReal]
reals = mapM sReal

proves :: String -> Symbolic ([SBool], SBool) -> Statement
proves name = Proves name ""

refutes :: String -> String -> Symbolic ([SBool], SBool) -> Statement
refutes name why = Refutes name why

suml :: [SReal] -> SReal
suml = foldr (+) 0

conj :: [SBool] -> SBool
conj = foldr (.&&) sTrue

-- One slot: its channel weights (w = exp(u) >= 0; the outside option has the weight 1).
denom :: [SReal] -> SReal
denom ws = 1 + suml ws

share :: [SReal] -> SReal -> SReal
share ws w = w / denom ws

shares :: [SReal] -> [SReal]
shares ws = map (share ws) ws

outside :: [SReal] -> SReal
outside ws = 1 / denom ws

nonneg :: [SReal] -> [SBool]
nonneg = map (.>= 0)

-- The exact-fit weights of observed shares: w = s / s0, with the outside share s0 = 1 - Σ s.
invert :: [SReal] -> [SReal]
invert os = map (/ (1 - suml os)) os

-- The residuals of a slot: s - s_obs, channel by channel (Neural.agda's `resid`).
resid :: [SReal] -> [SReal] -> [SReal]
resid = zipWith (-)

-- One feature's coordinate of the gradient: Σ resid * z, z one column of Z.
featureGrad :: [SReal] -> [SReal] -> SReal
featureGrad z rs = suml (zipWith (*) rs z)

-- One channel's forecast: the pool forecast times its share.
forecast :: SReal -> [SReal] -> [SReal]
forecast p ws = map (p *) (shares ws)

statements :: [Statement]
statements =
  -- ==========================================================================================
  -- The share layer (Jcs.agda)
  [ proves "jcs-sum" $ do
      ws <- reals ["w1", "w2", "w3"]
      -- The shares and the outside share add up to 1.
      pure (nonneg ws, suml (shares ws) + outside ws .== 1)

  , proves "jcs-inside-lt-one" $ do
      ws <- reals ["w1", "w2"]
      -- So the channels together hold less than the whole pool: the outside option keeps a share.
      pure (nonneg ws, suml (shares ws) .< 1)

  , proves "jcs-coherent" $ do
      p <- sReal "pool"
      ws <- reals ["w1", "w2", "w3"]
      -- The C forecasts of a slot never add up to more than its pool forecast.
      pure ((p .>= 0) : nonneg ws, suml (forecast p ws) .<= p)

  , proves "jcs-iia" $ do
      ws <- reals ["w1", "w2", "w3"]
      [a, b] <- reals ["wa", "wb"]
      -- The ratio of two shares does not depend on the rivals (independence of irrelevant
      -- alternatives): share a * w b = share b * w a.
      pure (nonneg ws ++ nonneg [a, b], share ws a * b .== share ws b * a)

  , proves "jcs-rival" $ do
      [w1, w2, r] <- reals ["w1", "w2", "r"]
      -- A rival of weight r >= 0 added to the slot never raises a channel's share.
      pure (nonneg [w1, w2, r], share (r : [w1, w2]) w1 .<= share [w1, w2] w1)

  , proves "jcs-odds" $ do
      ws <- reals ["w1", "w2", "w3"]
      w <- sReal "w"
      -- A share over the outside share is its weight, so the log-odds the features
      -- logodds, lo_lag7 and lo_lag_mean read is the utility u.
      pure (nonneg ws ++ [w .>= 0], share ws w / outside ws .== w)

  , proves "jcs-own" $ do
      [a, a2, w2] <- reals ["a", "a2", "w2"]
      -- A larger weight a2 >= a raises the channel's own share.
      pure (nonneg [a, a2, w2] ++ [a .<= a2], share [a, w2] a .<= share [a2, w2] a2)

  , proves "jcs-cross" $ do
      [a, a2, w] <- reals ["a", "a2", "w"]
      -- ... and lowers every rival's.
      pure (nonneg [a, a2, w] ++ [a .<= a2], share [a2, w] w .<= share [a, w] w)

  , proves "jcs-diversion" $ do
      [a, b] <- reals ["a", "b"]
      -- When a channel leaves the slot, each other channel's share becomes s / (1 - s_a): its
      -- viewers go to the rest in proportion to their shares, the outside option included.
      pure (nonneg [a, b], share [b] b .== share [a, b] b / (1 - share [a, b] a))

  , proves "jcs-pool-scale" $ do
      [c, p] <- reals ["c", "pool"]
      ws <- reals ["w1", "w2"]
      -- A pool forecast off by a factor c moves every channel's forecast by c.
      pure (nonneg ws, conj (zipWith (.==) (forecast (c * p) ws) (map (c *) (forecast p ws))))

  -- ==========================================================================================
  -- From shares back to weights (JcsTheory.agda)
  , proves "jcs-invert" $ do
      os@(o1 : o2 : o3 : _) <- reals ["o1", "o2", "o3"]
      -- Any shares with a sum below 1 come from one set of weights: w = s / s0.
      pure (nonneg os ++ [suml os .< 1], conj (zipWith (.==) (shares (invert os)) [o1, o2, o3]))

  , proves "fit-unique" $ do
      [w1, w2] <- reals ["w1", "w2"]
      [v1, v2] <- reals ["v1", "v2"]
      -- The exact fit is the only one: two weight lists with the same shares are the same
      -- weights. Z3 checks the two-channel shape; Agda proves it for every length.
      pure (nonneg [w1, w2] ++ nonneg [v1, v2] ++ zipWith (.==) (shares [w1, w2]) (shares [v1, v2]),
            w1 .== v1 .&& w2 .== v2)

  -- ==========================================================================================
  -- The residual layer of the logit fit (Neural.agda, LogitFit.agda)
  , proves "resid-slot" $ do
      ws <- reals ["w1", "w2", "w3"]
      os <- reals ["o1", "o2", "o3"]
      -- The residuals sum over a slot to the outside option's: s0,obs - s0.
      pure (nonneg ws, suml (resid (shares ws) os) .== (1 - suml os) - outside ws)

  , proves "gradBias-fit" $ do
      os <- reals ["o1", "o2", "o3"]
      -- At the exact fit every residual is 0, so the intercept's coordinate of the gradient,
      -- Σ resid, is 0: the exact fit is a stationary point of the unpenalised loss.
      pure (nonneg os ++ [suml os .< 1], suml (resid (shares (invert os)) os) .== 0)

  , proves "featureGrad-fit" $ do
      os <- reals ["o1", "o2", "o3"]
      z <- reals ["z1", "z2", "z3"]
      -- ... and every feature's coordinate Σ resid * z is 0, for every column z of Z.
      pure (nonneg os ++ [suml os .< 1], featureGrad z (resid (shares (invert os)) os) .== 0)

  , proves "l2-stationary-zero" $ do
      os <- reals ["o1", "o2"]
      [z1, z2, l, c] <- reals ["z1", "z2", "l2", "c"]
      -- With the L2 penalty, if one feature's penalised coordinate is 0 at an exact fit, the
      -- coefficient is 0: the coordinate is the penalty term 2 l2 c alone there.
      let rs = resid (shares (invert os)) os
      pure (nonneg os ++ [suml os .< 1, l .> 0, featureGrad [z1, z2] rs + 2 * l * c .== 0], c .== 0)

  , refutes "l2-moves-off" "the penalised optimum is not the exact fit" $ do
      os <- reals ["o1", "o2"]
      ws <- reals ["w1", "w2"]
      [z1, z2, l, c] <- reals ["z1", "z2", "l2", "c"]
      -- Away from the exact fit the penalised coordinate can be 0 with a non-zero coefficient:
      -- the L2 pulls the linear part off the exact shares (the experiment's l2 is positive).
      let rs = resid (shares ws) os
      pure (nonneg ws ++ nonneg os ++ [suml os .< 1, l .> 0, c ./= 0,
                                       featureGrad [z1, z2] rs + 2 * l * c .== 0], c .== 0)
  ]
