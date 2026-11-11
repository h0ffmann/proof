{-# LANGUAGE OverloadedStrings #-}

-- The two generated badges of README.md: lines of code and preprints.
--
-- Lines of code: the badge sits between `<!-- loc:start -->` and `<!-- loc:end -->` and gives the
-- total over every language of `languages`. What counts: every file tracked by git, outside
-- `vendor/` (other people's code), whose extension names a language below. A line of code is a
-- line that is not blank and not only a comment. Line comments and block comments are recognised
-- per language; a block comment that opens after code on the same line leaves that line counted.
--
-- Preprints: the badge is the line `[![preprints: N](...)](papers)` in the header, found by its
-- pattern rather than by markers, because an HTML comment inside the header's run of badges would
-- split it into paragraphs and stack the badges. A folder `papers/<slug>/` is a preprint when its
-- `metadata.md` has a `version:` line that says "preprint" (docs/paper-fabric.md), or when it has
-- no `metadata.md` and holds a PDF (papers/practice-beats-theory). papers/cycle, whose version
-- does not say "preprint", is not counted.
--
--     tools/badges/run.sh loc [--check|--print]
--     tools/badges/run.sh preprints [--check|--print]
--
-- Both are generated: edit this file, not the badges. GHC's bundled libraries only.
module Main (main) where

import Control.Monad (filterM, unless)
import qualified Data.ByteString as B
import Data.Char (isAlphaNum, isAscii, isDigit, isSpace)
import Data.List (find, isPrefixOf, isSuffixOf, sort)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import System.Process (CreateProcess (..), StdStream (..), createProcess, proc, waitForProcess)
import Text.Printf (printf)

readmePath :: FilePath
readmePath = "README.md"

-- language: extensions or file names, line comment prefixes, block comment (open, close) pairs.
-- The order matters only where two languages share an extension (none do).
languages :: [(String, ([String], [T.Text], [(T.Text, T.Text)]))]
languages =
  [ ("Scala", ([".scala", ".sbt"], ["//"], [("/*", "*/")]))
  , ("Python", ([".py"], ["#"], []))
  , ("Lean 4", ([".lean"], ["--"], [("/-", "-/")]))
  , ("Haskell", ([".hs"], ["--"], [("{-", "-}")]))
  , ("Rust", ([".rs"], ["//"], [("/*", "*/")]))
  , ("Gleam", ([".gleam"], ["//"], []))
  , ("Zig", ([".zig"], ["//"], []))
  , ("Erlang", ([".erl"], ["%"], []))
  , ("Shell", ([".sh"], ["#"], []))
  , ("Nix", ([".nix"], ["#"], [("/*", "*/")]))
  , ("JavaScript", ([".js", ".mjs"], ["//"], [("/*", "*/")]))
  , ("TeX", ([".tex"], ["%"], []))
  , ("just", (["justfile", ".just"], ["#"], []))
  , ("ASP (clingo)", ([".lp"], ["%"], [("%*", "*%")]))
  , ("TPTP", ([".p"], ["%"], [("/*", "*/")]))
  ]

languageOf :: FilePath -> Maybe String
languageOf path = fst <$> find matches languages
  where
    name = reverse (takeWhile (/= '/') (reverse path))
    matches (_, (exts, _, _)) =
      name `elem` exts || any (\e -> "." `isPrefixOf` e && e `isSuffixOf` name) exts

-- Python's str.isspace: GHC's isSpace plus the separators it leaves out.
pySpace :: Char -> Bool
pySpace c = isSpace c || c `elem` ("\x1c\x1d\x1e\x1f\x85\x2028\x2029" :: String)

-- Python's str.splitlines.
splitLines :: T.Text -> [T.Text]
splitLines t
  | T.null t = []
  | otherwise =
      let (a, rest) = T.break (`elem` breaks) t
       in case T.uncons rest of
            Nothing -> [a]
            Just ('\r', r) | Just ('\n', r') <- T.uncons r -> a : splitLines r'
            Just (_, r) -> a : splitLines r
  where
    breaks = "\n\r\v\f\x1c\x1d\x1e\x85\x2028\x2029" :: String

-- Lines that are not blank and not only a comment.
countCode :: [T.Text] -> [(T.Text, T.Text)] -> T.Text -> Int
countCode lineCs blocks text = snd (foldl' step (Nothing, 0) (splitLines text))
  where
    step (close, n) raw =
      let (close', code) = go close (T.dropAround pySpace raw)
       in (close', if code then n + 1 else n)
    go close s
      | T.null s = (close, False)
      | Just c <- close =
          let (_, after) = T.breakOn c s
           in if T.null after
                then (close, False)
                else go Nothing (T.dropAround pySpace (T.drop (T.length c) after))
      -- a block opener first: clingo's `%*` also starts with its line comment `%`
      | Just (o, c) <- find ((`T.isPrefixOf` s) . fst) blocks = go (Just c) (T.drop (T.length o) s)
      | any (`T.isPrefixOf` s) lineCs = (Nothing, False)
      | otherwise = (Nothing, True) -- code first; a comment later on the line does not matter

trackedFiles :: IO [FilePath]
trackedFiles = do
  (_, Just h, _, ph) <- createProcess (proc "git" ["ls-files", "-z"]) {std_out = CreatePipe}
  out <- B.hGetContents h
  code <- waitForProcess ph
  unless (code == ExitSuccess) $ die' "git ls-files failed"
  -- the paths as UTF-8 text, as Python's decode() reads them, whatever the locale
  return [T.unpack p | p <- T.splitOn "\0" (TE.decodeUtf8 out), not (T.null p), not ("vendor/" `T.isPrefixOf` p)]

-- language -> (files, lines of code)
measure :: IO (M.Map String (Int, Int))
measure = do
  paths <- trackedFiles
  foldl' (\m (l, loc) -> M.insertWith add l (1, loc) m) M.empty <$> mapM count
    [(p, l) | p <- paths, Just l <- [languageOf p]]
  where
    add (f1, l1) (f2, l2) = (f1 + f2, l1 + l2)
    count (p, l) = do
      bytes <- B.readFile p
      let (_, lineCs, blocks) = maybe ([], [], []) id (lookup l languages)
      return (l, countCode lineCs blocks (TE.decodeUtf8With lenientDecode bytes))

-- Python's urllib.parse.quote with safe="_": unreserved ASCII stays, every other UTF-8 byte is %XX.
quote :: T.Text -> String
quote = concatMap enc . B.unpack . TE.encodeUtf8
  where
    enc w
      | isAscii c && (isAlphaNum c || c `elem` ("_.-~" :: String)) = [c]
      | otherwise = printf "%%%02X" w
      where
        c = toEnum (fromIntegral w)

-- A shields.io static badge in Markdown; `-` and `_` are doubled as shields asks.
locBadge :: T.Text -> T.Text -> T.Text
locBadge label message =
  T.concat ["![", label, ": ", message, "](", T.pack url, ")"]
  where
    esc = quote . T.replace " " "_" . T.replace "_" "__" . T.replace "-" "--"
    url = "https://img.shields.io/badge/" ++ esc label ++ "-" ++ esc message ++ "-1b3a5c?style=flat-square"

-- Python's format(n, ",").
thousands :: Int -> String
thousands n
  | n < 0 = '-' : thousands (negate n)
  | otherwise = reverse (go (reverse (show n)))
  where
    go (a : b : c : rest@(_ : _)) = a : b : c : ',' : go rest
    go s = s

renderLoc :: M.Map String (Int, Int) -> T.Text
renderLoc totals =
  locBadge "lines of code" (T.pack (thousands loc ++ " in " ++ show files ++ " files"))
  where
    files = sum (map fst (M.elems totals))
    loc = sum (map snd (M.elems totals))

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitWith (ExitFailure 1)

-- Python's read_text: UTF-8 and universal newlines.
readText :: FilePath -> IO T.Text
readText p = T.replace "\r" "\n" . T.replace "\r\n" "\n" . TE.decodeUtf8 <$> B.readFile p

writeText :: FilePath -> T.Text -> IO ()
writeText p = B.writeFile p . TE.encodeUtf8

spliceLoc :: T.Text -> T.Text -> IO T.Text
spliceLoc readme badge = do
  let ls = splitLines readme
      idx m = lookup m (zip ls [0 :: Int ..])
  case (idx start, idx end) of
    (Just a, Just b)
      | b < a -> die' (T.unpack end ++ " comes before " ++ T.unpack start ++ " in README.md")
      | otherwise -> return (T.intercalate "\n" (take (a + 1) ls ++ [badge] ++ drop b ls) <> "\n")
    _ -> die' ("README.md needs the markers " ++ T.unpack start ++ " and " ++ T.unpack end ++ ", on lines of their own")
  where
    start = "<!-- loc:start -->"
    end = "<!-- loc:end -->"

-- `^version:\s*(.*)$`, multiline, first match: `\s*` may run past the end of the line.
versionOf :: T.Text -> Maybe T.Text
versionOf t = case filter ("version:" `T.isPrefixOf`) (lineStarts t) of
  (s : _) -> Just (T.takeWhile (/= '\n') (T.dropWhile pySpace (T.drop 8 s)))
  [] -> Nothing
  where
    lineStarts u = u : [T.drop 1 r | r <- T.tails u, "\n" `T.isPrefixOf` r]

isPreprint :: FilePath -> IO Bool
isPreprint folder = do
  let meta = folder </> "metadata.md"
  hasMeta <- doesFileExist meta
  if hasMeta
    then maybe False (T.isInfixOf "preprint" . T.toLower) . versionOf <$> readText meta
    else any (".pdf" `isSuffixOf`) <$> listDirectory folder

preprints :: IO [String]
preprints = do
  names <- listDirectory "papers"
  sort <$> filterM (\d -> (&&) <$> doesDirectoryExist ("papers" </> d) <*> isPreprint ("papers" </> d)) names

preprintsBadge :: Int -> T.Text
preprintsBadge n =
  T.pack ("[![preprints: " ++ show n ++ "](https://img.shields.io/badge/preprints-" ++ show n ++ "-2a78d6?style=flat-square)](papers)")

-- `^\[!\[preprints: \d+\]\([^)]*\)\]\(papers\)$`
isPreprintsLine :: T.Text -> Bool
isPreprintsLine l = case T.stripPrefix "[![preprints: " l of
  Nothing -> False
  Just r ->
    let (ds, r1) = T.span isDigit r
     in not (T.null ds) && case T.stripPrefix "](" r1 of
          Nothing -> False
          Just r2 -> let (_, r3) = T.break (== ')') r2 in r3 == ")](papers)"

splicePreprints :: T.Text -> T.Text -> IO T.Text
splicePreprints readme badge = do
  let ls = T.splitOn "\n" readme
  unless (length (filter isPreprintsLine ls) == 1) $
    die' "README.md needs exactly one line `[![preprints: N](...)](papers)`"
  return (T.intercalate "\n" [if isPreprintsLine l then badge else l | l <- ls])

data Mode = Write | Check | Print

-- Write, check or print a badge; `what` names it in the messages, `printed` follows it under --print.
run :: Mode -> T.Text -> Maybe [T.Text] -> (T.Text -> IO T.Text) -> String -> String -> String -> IO ()
run mode badge printed splice what stale updated = case mode of
  Print -> TIO.putStrLn badge >> unless (null printed') (mapM_ TIO.putStrLn printed')
  _ -> do
    old <- readText readmePath
    new <- splice old
    case mode of
      Check
        | new /= old -> putStrLn ("README.md: the " ++ what ++ " badge is out of date" ++ stale) >> exitWith (ExitFailure 1)
        | otherwise -> putStrLn ("README.md: the " ++ what ++ " badge is current" ++ current)
      _
        | new /= old -> writeText readmePath new >> putStrLn ("README.md: " ++ what ++ " badge updated" ++ updated)
        | otherwise -> putStrLn ("README.md: " ++ what ++ " badge already current")
  where
    current = takeWhile (/= ';') stale
    printed' = case printed of
      Nothing -> []
      Just [] -> [""] -- Python prints the join of no lines: an empty line
      Just ls -> ls

main :: IO ()
main = do
  hSetEncoding stdout utf8
  args <- getArgs
  let mode
        | "--print" `elem` args = Print
        | "--check" `elem` args = Check
        | otherwise = Write
  case args of
    ("loc" : _) -> do
      badge <- renderLoc <$> measure
      run mode badge Nothing (`spliceLoc` badge) "lines-of-code" "; run `just loc`" ""
    ("preprints" : _) -> do
      found <- preprints
      let n = length found
          badge = preprintsBadge n
      run mode badge (Just [T.pack ("  papers/" ++ s) | s <- found]) (`splicePreprints` badge)
        "preprints" (" (" ++ show n ++ " preprints); run `just preprints`") (" to " ++ show n)
    _ -> die' "usage: tools/badges/run.sh loc|preprints [--check|--print]"
