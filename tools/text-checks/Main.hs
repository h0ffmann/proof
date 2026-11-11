-- The text checks of the repository: the language rule, the PTC rules of the video script and
-- its PTC-9 noise catalogue. Each one measures text with regular expressions and asks Z3 (through
-- SBV) whether a unit breaks its rule. tools/text-checks/README.md lists the checks.
--
--     tools/text-checks/run.sh language | ptc [--self-test|--review] | ruido-ia [--self-test|--review|--level L]
module Main (main) where

import qualified Data.ByteString as B
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Language
import qualified NoiseCatalogue
import qualified Ptc
import Control.Exception (IOException, try)
import Py (decode)
import System.Directory (listDirectory)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import System.Process (readProcessWithExitCode)

usage :: String
usage = "usage: tools/text-checks/run.sh <check> [options]; checks: language, ptc, ruido-ia"

report :: ([Text], Int) -> IO ()
report (lines', code) = do
  mapM_ TIO.putStrLn lines'
  exitWith (if code == 0 then ExitSuccess else ExitFailure code)

-- | A file as Python's text mode reads it, or Nothing when it is missing or not UTF-8.
readTextIfAny :: FilePath -> IO (Maybe Text)
readTextIfAny path = do
  r <- try (B.readFile path) :: IO (Either IOException B.ByteString)
  pure (either (const Nothing) decode r)

-- | The script's Markdown files as (path from the repository root, text), sorted by path.
scriptFiles :: IO [(Text, Text)]
scriptFiles = do
  let dir = T.unpack Ptc.script
  names <- sort . filter (".md" `isSuffix`) <$> listDirectory dir
  mapM (\n -> do
          let path = dir ++ "/" ++ n
          t <- readTextIfAny path
          case t of
            Just text -> pure (T.pack path, text)
            Nothing -> failWith ("cannot read " ++ path) 2)
       names
  where isSuffix suf x = reverse suf == take (length suf) (reverse x)

failWith :: String -> Int -> IO a
failWith msg code = hPutStrLn stderr msg >> exitWith (ExitFailure code)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  args <- getArgs
  case args of
    ("language" : _) -> do
      (code, out, err) <- readProcessWithExitCode "git" ["ls-files"] ""
      if code /= ExitSuccess then failWith ("git ls-files failed:\n" ++ out ++ err) 2 else do
        let paths = Language.judged (T.pack out)
        files <- mapM (\p -> (,) p <$> readTextIfAny (T.unpack p)) paths
        Language.check files >>= report
    ("ptc" : rest)
      | "--self-test" `elem` rest -> Ptc.selfTest >>= report
      | otherwise -> do
          files <- scriptFiles
          Ptc.check files ("--review" `elem` rest) >>= report
    ("ruido-ia" : rest)
      | "--self-test" `elem` rest -> NoiseCatalogue.selfTest >>= report
      | otherwise -> case NoiseCatalogue.levelArg rest of
          Left msg -> failWith (T.unpack msg) 1
          Right lvl -> do
            files <- scriptFiles
            NoiseCatalogue.check files lvl ("--review" `elem` rest) >>= report
    _ -> failWith usage 64
