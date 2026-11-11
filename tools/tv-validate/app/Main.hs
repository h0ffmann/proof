-- tv-validate: the validation pipeline of tv-audience/, as one Tasty tree.
--
--   tv-validate --run DIR [--committed FILE] [-- TASTY OPTIONS]   every property and every line
--   tv-validate --run DIR --self-test                             changes to the run that must fail
--
-- DIR is what tools/tv-validate/export.py wrote. A line that says FAIL fails its test, so the
-- exit code is 1; a NOTE passes and prints its measurement. `-- -p metrics` runs one group.
module Main (main) where

import Data.String (fromString)
import Options.Applicative
import System.Environment (withArgs)
import Test.Tasty (TestTree, defaultMain, localOption, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, testCaseInfo)
import Test.Tasty.Hedgehog (HedgehogTestLimit (..), testPropertyNamed)

import TvValidate.Checks
import TvValidate.Load
import TvValidate.Properties

data Options = Options { runDir :: FilePath, committedFile :: FilePath, selfTest :: Bool, tastyArgs :: [String] }

options :: Parser Options
options = Options
  <$> strOption (long "run" <> metavar "DIR" <> help "the folder that export.py wrote")
  <*> strOption (long "committed" <> metavar "FILE" <> value "tv-audience/results.json" <> showDefault
                 <> help "the results.json the paper's numbers come from")
  <*> switch (long "self-test" <> help "change the run in ways that one line each must catch")
  <*> many (strArgument (metavar "TASTY OPTIONS"))

lineTest :: Line -> TestTree
lineTest (Line name status detail) = testCaseInfo name $ case status of
  OK -> pure detail
  NOTE -> pure ("NOTE " ++ detail)
  FAIL -> assertFailure detail

pipeline :: Run -> TestTree
pipeline r = testGroup "tv-validate" $
  localOption (HedgehogTestLimit (Just 200))
    (testGroup "properties" [ testPropertyNamed name (fromString name) p | (name, p) <- properties ])
  : [ testGroup g (map lineTest (f c)) | (g, f) <- groups ]
  where c = context r

-- Each change must turn its line from OK to FAIL.
selfTestTree :: Run -> TestTree
selfTestTree r = testGroup "tv-validate self-test"
  [ testCase (what ++ ": " ++ g ++ " / " ++ name) $
      case (statusOf r, statusOf (change r)) of
        (Just OK, Just FAIL) -> pure ()
        (before, after) -> assertFailure ("expected OK then FAIL, got " ++ show before ++ " then " ++ show after)
  | (what, change, g, name) <- selfTests
  , let statusOf run = do
          f <- lookup g groups
          lookup name [ (lineName l, lineStatus l) | l <- f (context run) ] ]

main :: IO ()
main = do
  o <- execParser (info (options <**> helper)
         (fullDesc <> progDesc "Validate tv-audience/python against agda/src/TvAudience/ on the experiment's own numbers"))
  r <- loadRun (runDir o) (committedFile o)
  withArgs (tastyArgs o) (defaultMain (if selfTest o then selfTestTree r else pipeline r))
