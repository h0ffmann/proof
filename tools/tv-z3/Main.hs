-- The Z3 checks of the JCS model of tv-audience and of its logit fit (TvZ3.hs).
-- tools/tv-z3/README.md is the report.
--
--     tools/tv-z3/run.sh
module Main (main) where

import qualified Report
import qualified TvZ3
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
    [] -> Report.run TvZ3.title TvZ3.statements >>= exit
    _ -> hPutStrLn stderr "usage: tools/tv-z3/run.sh" >> exit 64
