{-# LANGUAGE OverloadedStrings #-}

-- Reads what export.py wrote: the test rows with every model's forecast (cassava, by column
-- name), the panel, the share designs, the fitted weights and the two results.json files (aeson).
module TvValidate.Load
  ( Run (..), TestRow (..), PanelRow (..), ShareRow (..), Logit (..), NsWeights (..)
  , Results (..), loadRun, loadResults, number, interval, forecast, firstOf
  ) where

import qualified Data.Aeson as J
import qualified Data.ByteString.Char8 as B8
import qualified Data.ByteString.Lazy as BL
import qualified Data.Csv as C
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as U
import System.FilePath ((</>))

-- One channel of one slot of the test period, as the experiment scores it.
data TestRow = TestRow
  { sid, day :: !Int
  , market, channel :: !Text
  , slot :: !Int
  , audience, pool :: !Double
  , big, clash, event :: !Bool
  , lag7, lagMean, poolHat, otherHat :: !Double
  , forecasts :: !(M.Map Text Double)   -- by model: naive, xgb, xgb_rival, dnn, jcs, ns_jcs, ...
  }

-- The first row of a slot; a slot of the files has at least one row.
firstOf :: [a] -> a
firstOf (x : _) = x
firstOf [] = error "tv-validate: an empty slot"

forecast :: Text -> TestRow -> Double
forecast m r = forecasts r M.! m

data PanelRow = PanelRow { pMarket, pChannel :: !Text, pSlot, pDay :: !Int, pAudience :: !Double }

-- A row of the share design: the slot, the observed share (0 for a test row) and the features.
data ShareRow = ShareRow { sSid :: !Int, sObs :: !Double, sX :: !(U.Vector Double) }

data Logit = Logit { lW :: [Double], lL2 :: Double }

data NsWeights = NsWeights
  { nW :: [Double], nB :: Double, nW1 :: [[Double]], nB1, nW2, nMu, nSd :: [Double] }

instance J.FromJSON Logit where
  parseJSON = J.withObject "logit" $ \o -> Logit <$> o J..: "w" <*> o J..: "l2"

instance J.FromJSON NsWeights where
  parseJSON = J.withObject "ns" $ \o ->
    NsWeights <$> o J..: "w" <*> o J..: "b" <*> o J..: "W1" <*> o J..: "b1" <*> o J..: "W2"
              <*> o J..: "mu" <*> o J..: "sd"

data Models = Models Logit NsWeights

instance J.FromJSON Models where
  parseJSON = J.withObject "model" $ \o -> Models <$> o J..: "logit" <*> o J..: "ns"

-- A results.json of experiment.py: its meta block, and each model's numbers by key.
data Results = Results { meta :: M.Map Text J.Value, results :: M.Map Text (M.Map Text J.Value) }

instance J.FromJSON Results where
  parseJSON = J.withObject "results" $ \o -> Results <$> o J..: "meta" <*> o J..: "results"

number :: J.Value -> Maybe Double
number v = case J.fromJSON v of J.Success x -> Just x; _ -> Nothing

interval :: J.Value -> Maybe (Double, Double)
interval v = case J.fromJSON v of J.Success [a, b] -> Just (a, b); _ -> Nothing

data Run = Run
  { testRows :: [TestRow]
  , panel :: [PanelRow]
  , shareTrain, shareTest :: [ShareRow]
  , logit :: Logit
  , ns :: NsWeights
  , resamples :: [[Int]]          -- evaluate's 500 day resamples, as indices of the sorted days
  , fresh :: Results              -- the results.json this run of the experiment wrote
  , committed :: Results          -- tv-audience/results.json
  }

orDie :: FilePath -> Either String a -> IO a
orDie path = either (\e -> ioError (userError ("tv-validate: " ++ path ++ ": " ++ e))) pure

loadResults :: FilePath -> IO Results
loadResults path = J.eitherDecodeFileStrict' path >>= orDie path

loadRun :: FilePath -> FilePath -> IO Run
loadRun dir committedPath = do
  let csv name f = do { b <- BL.readFile (dir </> name); orDie (dir </> name) (f b) }
  rows <- csv "test.csv" $ \b -> do
    (hdr, recs) <- C.decodeByName b
    let models = [ n | n <- V.toList hdr, "p_" `B8.isPrefixOf` n ]
        flag r n = (/= (0 :: Int)) <$> r C..: n
        row r = TestRow <$> r C..: "sid" <*> r C..: "day" <*> r C..: "market" <*> r C..: "channel"
          <*> r C..: "slot" <*> r C..: "audience" <*> r C..: "pool"
          <*> flag r "big" <*> flag r "clash" <*> flag r "event"
          <*> r C..: "lag7" <*> r C..: "lag_mean" <*> r C..: "pool_hat" <*> r C..: "other_hat"
          <*> (M.fromList <$> traverse (\n -> (,) (TE.decodeUtf8 (B8.drop 2 n)) <$> r C..: n) models)
    traverse (C.runParser . row) (V.toList (recs :: V.Vector C.NamedRecord))
  pan <- csv "panel.csv" $ \b ->
    map (\(m, c, s, d, a) -> PanelRow m c s d a) . V.toList <$> C.decode C.HasHeader b
  let design skip b = map (share skip) . V.toList <$> C.decode C.HasHeader b
      share skip v = ShareRow (round (v U.! 0)) (if skip == 2 then v U.! 1 else 0) (U.drop skip v)
  tr <- csv "share_train.csv" (design (2 :: Int))
  te <- csv "share_test.csv" (design 1)
  picks <- csv "bootstrap.csv" $ \b -> map U.toList . V.toList <$> C.decode C.NoHeader b
  Models lg nsw <- J.eitherDecodeFileStrict' (dir </> "model.json") >>= orDie (dir </> "model.json")
  Run rows pan tr te lg nsw picks <$> loadResults (dir </> "results.json") <*> loadResults committedPath
