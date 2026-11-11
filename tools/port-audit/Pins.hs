-- The two pins the coverage is measured at, on disk: shallow, sparse git checkouts of chaceon and
-- of WW3 in port-audit/.cache, and the files Coverage.measure reads from them.
module Pins (chaceon, ww3, sources) where

import Control.Exception (IOException, try)
import Control.Monad (unless)
import qualified Data.ByteString as B
import Data.List (isPrefixOf, isSuffixOf, sort)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TE
import Coverage (Sources (..), chaceonCommit, chaceonUrl, splitlines, ww3Commit, ww3Url)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

cache :: FilePath
cache = "port-audit/.cache"

git :: FilePath -> [String] -> IO (ExitCode, String)
git dir args = do
  (code, out, err) <- readProcessWithExitCode "git" (["-C", dir] ++ args) ""
  pure (code, out ++ err)

gitOk :: FilePath -> [String] -> IO ()
gitOk dir args = do
  (code, out) <- git dir args
  unless (code == ExitSuccess) $ do
    hPutStrLn stderr ("git " ++ unwords args ++ " failed in " ++ dir ++ ":\n" ++ out)
    exitWith (ExitFailure 2)

-- | A shallow checkout of one commit, only the paths in `sparse`. Reused when it is at the commit.
fetch :: String -> String -> FilePath -> [String] -> IO FilePath
fetch url commit into sparse = do
  present <- doesDirectoryExist (into ++ "/.git")
  at <- if present then (\(_, o) -> filter (/= '\n') o) <$> git into ["rev-parse", "HEAD"] else pure ""
  if present && at == commit then pure into else do
    createDirectoryIfMissing True into
    unless present $ gitOk into ["init", "-q"] >> gitOk into ["remote", "add", "origin", url]
    gitOk into (["sparse-checkout", "set", "--no-cone"] ++ sparse)
    gitOk into ["fetch", "-q", "--depth", "1", "--filter=blob:none", "origin", commit]
    gitOk into ["checkout", "-q", "FETCH_HEAD"]
    pure into

chaceon, ww3 :: IO FilePath
chaceon = fetch chaceonUrl chaceonCommit (cache ++ "/chaceon") ["/rust/ports.tsv", "/switches/"]
ww3 = fetch ww3Url ww3Commit (cache ++ "/WW3") ["/model/src/"]

-- | A file as Python's text mode reads it: UTF-8 (bad bytes replaced when asked), universal newlines.
readText :: Bool -> FilePath -> IO String
readText replace path = do
  r <- try (B.readFile path) :: IO (Either IOException B.ByteString)
  bytes <- either (\e -> hPutStrLn stderr ("cannot read " ++ path ++ ": " ++ show e) >> exitWith (ExitFailure 2)) pure r
  text <- if replace then pure (TE.decodeUtf8With TE.lenientDecode bytes) else case TE.decodeUtf8' bytes of
    Right t -> pure t
    Left _ -> hPutStrLn stderr ("cannot read " ++ path ++ ": not UTF-8") >> exitWith (ExitFailure 2)
  pure (T.unpack (T.replace (T.pack "\r") (T.pack "\n") (T.replace (T.pack "\r\n") (T.pack "\n") text)))

named :: FilePath -> (String -> Bool) -> Bool -> IO [(String, String)]
named dir keep replace = do
  names <- sort . filter keep <$> listDirectory dir
  mapM (\n -> (,) n <$> readText replace (dir ++ "/" ++ n)) names

-- | What Coverage.measure reads, from checkouts of chaceon and WW3.
sources :: FilePath -> FilePath -> IO Sources
sources chaceonDir ww3Dir = do
  let src = ww3Dir ++ "/model/src"
  fortranFiles <- named src (".F90" `isSuffixOf`) True
  json <- readText False (src ++ "/cmake/switches.json")
  srcL <- readText False (src ++ "/cmake/src_list.cmake")
  sw <- named (chaceonDir ++ "/switches") ("switch_" `isPrefixOf`) False
  ps <- readText False (chaceonDir ++ "/rust/ports.tsv")
  pure (Sources [(n, splitlines t) | (n, t) <- fortranFiles] json srcL sw ps)
