-- The TV ratings pipeline: fetch the public pages of Sources.hs, read their tables, and write one
-- CSV of published audience figures for tv-audience/.
--
--   tv-ratings [fetch|parse|all] [--raw DIR] [--out DIR] [SOURCE ...]
--   tv-ratings --self-test
--
-- fetch: curl each page into DIR (default tools/tv-ratings/build/raw), with the time of the fetch.
-- parse: read the fetched pages and write ratings.csv and sources.csv into the out directory
--        (default tv-audience/real). No network.
-- all:   fetch, then parse (the default).
-- Every source prints one line, OK or FAIL; the exit code is 1 when one fails.
module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forM, unless, when)
import Data.List (intercalate)
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import System.Directory (createDirectoryIfMissing, doesFileExist, renameFile)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitFailure)
import System.IO
import System.Process (readProcessWithExitCode)

import Html (tables, tokens)
import Ratings
import SelfTest (selfTest)
import Sources

data Opts = Opts { cmd :: String, rawDir :: FilePath, outDir :: FilePath, only :: [String] }

parseArgs :: [String] -> Either String Opts
parseArgs = go (Opts "all" "tools/tv-ratings/build/raw" "tv-audience/real" [])
  where
    go o [] = Right o
    go o ("--raw" : d : r) = go o { rawDir = d } r
    go o ("--out" : d : r) = go o { outDir = d } r
    go o (c : r) | c `elem` ["fetch", "parse", "all"] = go o { cmd = c } r
    go o (a@('-' : _) : _) = const (Left ("unknown option " ++ a)) o
    go o (s : r)
      | s `elem` map sid sources = go o { only = only o ++ [s] } r
      | otherwise = Left ("unknown source " ++ s ++ "; the sources are " ++ unwords (map sid sources))

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  if args == ["--self-test"] then selfTest else
    case parseArgs args of
      Left e -> hPutStrLn stderr ("tv-ratings: " ++ e) >> exitFailure
      Right o -> do
        let chosen = [s | s <- sources, null (only o) || sid s `elem` only o]
        okF <- if cmd o `elem` ["fetch", "all"] then fetchAll o chosen else pure True
        okP <- if cmd o `elem` ["parse", "all"] then parseAll o chosen else pure True
        unless (okF && okP) exitFailure

-- ── fetch ──────────────────────────────────────────────────────────────────

-- curl follows redirects, retries a 429 or a 5xx after the server's Retry-After, and fails on
-- any other error status. The user agent names the tool and no person.
fetchAll :: Opts -> [Source] -> IO Bool
fetchAll o srcs = do
  createDirectoryIfMissing True (rawDir o)
  oks <- forM (zip [0 :: Int ..] srcs) $ \(i, s) -> do
    when (i > 0) (threadDelay 2000000)
    let file = rawDir o ++ "/" ++ sid s ++ ".html"
    (code, _, err) <- readProcessWithExitCode "curl"
      [ "--fail", "--silent", "--show-error", "--location", "--compressed"
      , "--retry", "4", "--retry-delay", "5", "--max-time", "120"
      , "--user-agent", "tv-ratings/0.1 (research pipeline; curl)"
      , "--output", file ++ ".part", url s ] ""
    case code of
      ExitSuccess -> do
        now <- getCurrentTime
        renameFile (file ++ ".part") file
        writeFile (rawDir o ++ "/" ++ sid s ++ ".fetched")
          (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now ++ "\n")
        putStrLn ("OK   fetch " ++ sid s ++ "  " ++ url s)
        pure True
      ExitFailure n -> do
        putStrLn ("FAIL fetch " ++ sid s ++ "  curl exit " ++ show n ++ ": " ++ unwords (lines err))
        pure False
  pure (and oks)

-- ── parse ──────────────────────────────────────────────────────────────────

readUtf8 :: FilePath -> IO String
readUtf8 f = do
  h <- openFile f ReadMode
  hSetEncoding h utf8
  s <- hGetContents h
  length s `seq` hClose h
  pure s

parseAll :: Opts -> [Source] -> IO Bool
parseAll o srcs = do
  results <- forM srcs $ \s -> do
    let file = rawDir o ++ "/" ++ sid s ++ ".html"
    have <- doesFileExist file
    if not have
      then putStrLn ("FAIL parse " ++ sid s ++ "  no " ++ file ++ "; run fetch first") >> pure Nothing
      else do
        page <- readUtf8 file
        stampFile <- doesFileExist (rawDir o ++ "/" ++ sid s ++ ".fetched")
        stamp <- if stampFile then concat . take 1 . lines <$> readUtf8 (rawDir o ++ "/" ++ sid s ++ ".fetched")
                 else pure ""
        case extract s (tables (tokens page)) of
          Left e -> putStrLn ("FAIL parse " ++ e) >> pure Nothing
          Right rs -> do
            putStrLn ("OK   parse " ++ sid s ++ "  " ++ show (length rs) ++ " rows, "
                        ++ show (length (filter focus rs)) ++ " on the nine channels")
            pure (Just (s, stamp, rs))
  let good = [r | Just r <- results]
  unless (null good) $ do
    createDirectoryIfMissing True (outDir o)
    writeUtf8 (outDir o ++ "/ratings.csv")
      (unlines (intercalate "," header : [csvRow r | (_, _, rs) <- good, r <- rs]))
    writeUtf8 (outDir o ++ "/sources.csv")
      (unlines ("source,market,url,fetched,rows,licence"
                 : [ intercalate "," [sid s, sourceMarket s, url s, stamp, show (length rs), quote (licence s)]
                   | (s, stamp, rs) <- good ]))
    putStrLn ("wrote " ++ outDir o ++ "/ratings.csv and " ++ outDir o ++ "/sources.csv")
  pure (all (/= Nothing) (map (fmap (const ())) results))
  where
    quote s = "\"" ++ concatMap (\c -> if c == '"' then "\"\"" else [c]) s ++ "\""

writeUtf8 :: FilePath -> String -> IO ()
writeUtf8 f s = withFile f WriteMode (\h -> hSetEncoding h utf8 >> hPutStr h s)
