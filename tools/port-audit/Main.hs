-- The port audit of chaceon: its arithmetic (Chaceon.hs, statements Z3 checks through SBV) and its
-- coverage of WAVEWATCH III (Coverage.hs, tables measured on the two pins). port-audit/README.md
-- is the report.
--
--     tools/port-audit/run.sh chaceon
--     tools/port-audit/run.sh coverage [--write | --check] [--chaceon DIR --ww3 DIR]
module Main (main) where

import qualified Chaceon
import Control.Monad (when)
import qualified Coverage
import Data.List (elemIndex)
import qualified Pins
import qualified Report
import System.Directory (makeAbsolute)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)

exit :: Int -> IO a
exit 0 = exitWith ExitSuccess
exit n = exitWith (ExitFailure n)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  args <- getArgs
  case args of
    ("chaceon" : _) -> Report.run Chaceon.title Chaceon.statements >>= exit
    ("coverage" : rest) -> coverage rest >>= exit
    _ -> hPutStrLn stderr "usage: tools/port-audit/run.sh chaceon | coverage [--write | --check] [--chaceon DIR --ww3 DIR]" >> exit 64

-- | The coverage tables, printed; --write puts them into port-audit/README.md, --check fails when
-- the README holds other ones.
coverage :: [String] -> IO Int
coverage args = do
  let opt flag = case elemIndex flag args of
        Just i | i + 1 < length args -> Just (args !! (i + 1))
        _ -> Nothing
      (write, check) = ("--write" `elem` args, "--check" `elem` args)
  when (write && check) $ hPutStrLn stderr "coverage: --write and --check are exclusive" >> exit 2
  chaceonDir <- maybe Pins.chaceon makeAbsolute (opt "--chaceon")
  ww3Dir <- maybe Pins.ww3 makeAbsolute (opt "--ww3")
  table <- Coverage.measure =<< Pins.sources chaceonDir ww3Dir
  putStr table
  text <- readFile Coverage.readme
  let fresh = Coverage.splice text table
  length text `seq` pure ()
  if write then writeFile Coverage.readme fresh >> pure 0
  else if check && fresh /= text then do
    hPutStrLn stderr "coverage: README.md is stale; run tools/port-audit/run.sh coverage --write"
    pure 1
  else pure 0
