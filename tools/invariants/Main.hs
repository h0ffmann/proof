{-# LANGUAGE OverloadedStrings #-}

-- Check the repository against Invariants.lp.
--
-- Read the tracked files, the commits of this branch that main does not have, and the branch name;
-- write them as facts; solve the facts with Invariants.lp in clingo. The program decides; this tool
-- only reads. Exit 1 when a violation is not waived, or when a waiver excuses nothing.
--
--   tools/invariants/run.sh               # check the tree
--   tools/invariants/run.sh --facts       # print the facts and stop
--   tools/invariants/run.sh --self-test   # bad facts must give each violation
--
-- It reads text as Python's text mode did (tools/text-checks/Py.hs: UTF-8 with replacement,
-- universal newlines, PCRE with Unicode classes) and JSON with tools/port-audit/Json.hs.
module Main (main) where

import Control.Monad (filterM, forM, forM_, unless, when)
import qualified Data.ByteString as B
import Data.Char (isAlphaNum, isAscii)
import Data.List (nub, sort)
import Data.Maybe (fromMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Json as J
import Py (Match (..), Rx, dec, matches, re, search, splitlines, sub)
import System.Directory (doesFileExist, findExecutable)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hPutStrLn, hSetEncoding, stderr, stdout, utf8)
import System.Process (readCreateProcessWithExitCode, readProcessWithExitCode, proc, cwd)

die' :: String -> IO a
die' msg = hPutStrLn stderr msg >> exitWith (ExitFailure 1)

q :: Text -> Text
q s = "\"" <> T.replace "\"" "\\\"" (T.replace "\\" "\\\\" s) <> "\""

attribution, pair, issueRef, url, leanHole, leanAxiom, leanNative :: Rx
attribution = re "(?im)^\\s*(co-authored-by|claude-session|signed-off-by)\\s*:|(generated with|requested by)"
pair = re "(?<![\\w./-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]*[A-Za-z0-9_])"
issueRef = re "(?<![\\w./-])([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)#\\d+"
url = re "github\\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]*[A-Za-z0-9_])"
-- The same patterns as scripts/lean-hygiene.sh.
leanHole = re "\\b(sorry|admit)\\b"
leanAxiom = re "^\\s*((private|protected|noncomputable|unsafe|@\\[[^]]*\\])\\s+)*axiom(\\s|$)"
leanNative = re "\\bnative_decide\\b"

-- | A whole match of the pattern (Python's re.fullmatch).
fullmatch :: String -> Text -> Bool
fullmatch p = search (re ("\\A(?:" ++ p ++ ")\\z"))

groups :: Match -> [Text]
groups = map (fromMaybe "") . mGroups

git :: FilePath -> [String] -> IO Text
git root args = do
  (code, out, err) <- readCreateProcessWithExitCode ((proc "git" args) {cwd = Just root}) ""
  unless (code == ExitSuccess) $ die' ("git " ++ unwords args ++ ": " ++ err)
  return (T.pack out)

-- | A file as Python's open(encoding="utf-8", errors="replace").read() gives it.
readT :: FilePath -> FilePath -> IO Text
readT root p = universal . dec <$> B.readFile (root </> p)
  where universal = T.replace "\r" "\n" . T.replace "\r\n" "\n"

baseRef :: FilePath -> IO (Maybe String)
baseRef root = do
  ok <- filterM verify ["origin/main", "main"]
  return (case ok of (r : _) -> Just r; [] -> Nothing)
  where
    verify r = do
      (code, _, _) <- readCreateProcessWithExitCode ((proc "git" ["rev-parse", "-q", "--verify", r]) {cwd = Just root}) ""
      return (code == ExitSuccess)

facts :: FilePath -> IO [Text]
facts root = do
  listed <- filter (not . T.null) . T.splitOn "\0" <$> git root ["ls-files", "-z"]
  files <- filterM (doesFileExist' . T.unpack) listed
  let fs = S.fromList files
      notVendor f = not ("vendor/" `T.isPrefixOf` f)
      fileFacts = concat [("file(" <> q f <> ").") : ["pdf(" <> q f <> ")." | ".pdf" `T.isSuffixOf` f] | f <- files]

  leanFacts <- fmap concat . forM [f | f <- files, ".lean" `T.isSuffixOf` f, notVendor f] $ \f -> do
    text <- readT root (T.unpack f)
    let tokens = concat
          [ ["lean_token(" <> q f <> ", " <> tshow n <> ", " <> head' (groups m) <> ")." | m <- matches leanHole line]
            ++ ["lean_token(" <> q f <> ", " <> tshow n <> ", axiom)." | search leanAxiom line]
            ++ ["lean_token(" <> q f <> ", " <> tshow n <> ", native_decide)." | search leanNative line]
          | (n, line) <- zip [1 :: Int ..] (splitlines text) ]
    return (("lean(" <> q f <> ").") : ["lean_examples(" <> q f <> ")." | takeFileName (T.unpack f) == "Examples.lean"] ++ tokens)
  let packageFacts = concat
        [ ("lean_package(" <> q d <> ").") : ["lean_pinned(" <> q d <> ")." | joinT d "lean-toolchain" `S.member` fs]
        | f <- files, takeFileName (T.unpack f) `elem` ["lakefile.toml", "lakefile.lean"], notVendor f
        , let d = T.pack (dirname (T.unpack f)) ]

  base <- baseRef root
  commits <- maybe (return []) (\b -> T.words <$> git root ["rev-list", b ++ "..HEAD"]) base
  commitFacts <- fmap concat . forM commits $ \c -> do
    msg <- git root ["log", "-1", "--format=%B", T.unpack c]
    let two rx = nub [(a, b) | m <- matches rx msg, (a : b : _) <- [groups m]]
    return $ ("commit(" <> q c <> ").")
      : ["commit_trailer(" <> q c <> ", " <> q (T.toLower (firstNonEmpty (groups m))) <> ")." | m <- matches attribution msg]
      ++ ["commit_pair(" <> q c <> ", " <> q a <> ", " <> q b <> ")." | (a, b) <- two pair]
      ++ ["commit_issue_ref(" <> q c <> ", " <> q a <> ", " <> q b <> ")." | (a, b) <- two issueRef]
      ++ ["commit_url(" <> q c <> ", " <> q a <> ", " <> q b <> ")." | (a, b) <- two url]

  branch <- T.strip <$> git root ["rev-parse", "--abbrev-ref", "HEAD"]
  let branchFacts
        | branch `elem` ["HEAD", "main"] = []
        | otherwise = ("branch(" <> q branch <> ").") : concat
            [ ["branch_part(" <> q branch <> ", " <> q w <> ")." | not (T.null w)]
              ++ ["branch_part(" <> q branch <> ", " <> q "session" <> ")." | "session" `T.isPrefixOf` w || "cmsg" `T.isPrefixOf` w]
            | w <- T.split (not . isAsciiAlnum) (T.toLower branch) ]

  lockFacts <- if "flake.lock" `S.member` fs
    then do
      lock <- J.parse . T.unpack <$> readT root "flake.lock"
      return [ "flake_input_locked(" <> q (T.pack name) <> ")."
             | J.Obj nodes <- [J.field "nodes" lock], (name, node) <- nodes
             , truthy (J.field "rev" (J.field "locked" node)) || truthy (J.field "narHash" (J.field "locked" node)) ]
    else return []

  nixFacts <- if "flake.nix" `S.member` fs
    then do
      flake <- uncomment <$> readT root "flake.nix"
      let discovered = search (re "readDir\\s+\\./nix") flake
      shells <- if discovered
        then mapM (fmap uncomment . readT root . T.unpack) [f | f <- files, fullmatch "nix/[^/]+\\.nix" f]
        else return []
      let names = S.fromList (concat
            [ [p, sub (re "(-bin)?([-_]?\\d+)+$") "" (sub (re "_headless$") "" p)]
            | text <- flake : shells, m <- matches (re "\\bpkgs\\.([A-Za-z0-9_-]+)") text, (p : _) <- [groups m] ])
      return (["nix_shells_discovered." | discovered] ++ ["nix_package(" <> q p <> ")." | p <- S.toAscList names])
    else return []

  imports <- if "justfile" `S.member` fs
    then do
      j <- readT root "justfile"
      return [g | m <- matches (re "(?m)^\\s*import\\??\\s+['\"]([^'\"]+)['\"]") j, (g : _) <- [groups m]]
    else return []
  checkFacts <- fmap concat . forM files $ \f ->
    if fullmatch "checks/[^/]+\\.sh" f
      then do
        t <- readT root (T.unpack f)
        return (("check_script(" <> q f <> ").") : ["strict(" <> q f <> ")." | search (re "(?m)^\\s*set -euo pipefail") t])
      else return []
  let justFacts = ["just_import(" <> q f <> ")." | f <- imports]
        ++ concat [ ["just_file(" <> q f <> ")." | fullmatch "just/[^/]+\\.just" f] | f <- files ]

  workflowFacts <- fmap concat . forM [f | f <- files, fullmatch "\\.github/workflows/[^/]+\\.ya?ml" f] $ \f -> do
    t <- readT root (T.unpack f)
    return ["workflow_trigger(" <> q f <> ", " <> q tr <> ")." | tr <- triggers t]

  cabalFacts <- fmap concat . forM [f | f <- files, ".cabal" `T.isSuffixOf` f] $ \f -> do
    t <- readT root (T.unpack f)
    let name = [n | m <- take 1 (matches (re "(?m)^name:\\s*(\\S+)") t), (n : _) <- [groups m]]
        deps = [ d | m <- matches (re "build-depends:\\s*((?:.*\\n)(?:[ \\t]+[^:\\n]*\\n)*)") t, (block : _) <- [groups m]
                   , dep <- T.splitOn "," (T.replace "\n" " " block)
                   , let d = cut "=" (cut "<" (cut ">" (head' (T.splitOn " " (T.strip dep)))))
                   , not (T.null d) ]
    return (["cabal_package(" <> q n <> ")." | n <- name] ++ ["cabal_dep(" <> q f <> ", " <> q d <> ")." | d <- deps])

  return (fileFacts ++ leanFacts ++ packageFacts ++ commitFacts ++ branchFacts ++ lockFacts ++ nixFacts
          ++ justFacts ++ checkFacts ++ workflowFacts ++ cabalFacts)
  where
    doesFileExist' p = doesFileExist (root </> p)
    joinT d n = if T.null d then n else d <> "/" <> n
    dirname p = let d = takeDirectory p in if d == "." then "" else d
    cut c = head' . T.splitOn c
    truthy v = case v of
      J.Str s -> not (null s)
      J.Bool b -> b
      J.Num n -> n /= 0
      J.Obj kv -> not (null kv)
      J.Arr xs -> not (null xs)
      J.Null -> False
    isAsciiAlnum ch = isAscii ch && isAlphaNum ch
    firstNonEmpty gs = case filter (not . T.null) gs of (g : _) -> g; [] -> ""

head' :: [Text] -> Text
head' (x : _) = x
head' [] = ""

tshow :: Show a => a -> Text
tshow = T.pack . show

uncomment :: Text -> Text
uncomment = T.intercalate "\n" . map (fst . T.breakOn "#") . splitlines

-- | The keys under `on:` (or `true:`, as YAML 1.1 reads it), comments left out.
triggers :: Text -> [Text]
triggers text = concat (zipWith at [0 ..] ls)
  where
    ls = [T.stripEnd (fst (T.breakOn "#" l)) | l <- splitlines text]
    at :: Int -> Text -> [Text]
    at i line = case matches (re "^(on|\"on\"|'on'):\\s*(.*)$") line of
      (m : _) | mStart m == 0, (_ : inline0 : _) <- groups m ->
        let inline = T.strip inline0
         in if not (T.null inline)
              then filter (not . T.null) (map T.strip (T.splitOn "," (T.dropAround (`elem` ("[]" :: String)) inline)))
              else [k | sub' <- takeWhile (\s -> T.null s || T.head s == ' ' || T.head s == '\t' || T.head s `elem` ("\n\r\v\f" :: String)) (drop (i + 1) ls)
                      , m' <- take 1 (matches (re "^  ([A-Za-z_]+):") sub'), (k : _) <- [groups m']]
      _ -> []

clingoCmd :: IO FilePath
clingoCmd = findExecutable "clingo" >>= maybe (die' "invariants: no clingo (nix develop .#invariants)") return

solve :: FilePath -> [Text] -> IO [Text]
solve program factLines = do
  exe <- clingoCmd
  (code, out, err) <- readProcessWithExitCode exe ["--outf=2", "-", program] (T.unpack (T.intercalate "\n" factLines))
  -- clingo exits 10 or 30 on SATISFIABLE; the JSON says which.
  result <- case reads' out of
    Just v -> return v
    Nothing -> die' ("invariants: clingo failed (" ++ show code ++ "):\n" ++ err ++ out)
  case J.field "Result" result of
    J.Str "SATISFIABLE" -> return ()
    r -> die' ("invariants: clingo gave " ++ pyStr r ++ ":\n" ++ err)
  case reverse (J.list (J.field "Call" result)) of
    (call : _) | (w : _) <- reverse (J.list (J.field "Witnesses" call)) ->
      return [T.pack (J.str a) | a <- J.list (J.field "Value" w)]
    _ -> die' "invariants: clingo gave no witness"
  where
    reads' s = if all (`elem` (" \t\r\n" :: String)) s then Nothing else Just (J.parse s)
    pyStr (J.Str s) = s
    pyStr _ = "None"

report :: [Text] -> IO Int
report atoms = do
  let failing = filter ("failing(" `T.isPrefixOf`) atoms
      stale = filter ("stale_waiver(" `T.isPrefixOf`) atoms
      gaps = filter ("gap(" `T.isPrefixOf`) atoms
  forM_ (sort gaps) $ \a -> TIO.putStrLn ("invariants: gap   " <> a)
  forM_ (sort (failing ++ stale)) $ \a -> TIO.hPutStrLn stderr ("invariants: FAIL  " <> a)
  return (if null failing && null stale then 0 else 1)

bad :: [(Text, Text)]
bad =
  [ ("just_import(\"just/gone.just\").", "just_import_missing")
  , ("just_file(\"just/orphan.just\").", "just_file_not_imported")
  , ("check_script(\"checks/loose.sh\").", "check_not_strict")
  , ("commit(\"c1\"). commit_pair(\"c1\", \"piabrota\", \"room\").", "commit_mentions_repo")
  , ("commit(\"c2\"). commit_url(\"c2\", \"someone\", \"else\").", "commit_mentions_repo")
  , ("commit(\"c3\"). commit_issue_ref(\"c3\", \"someone\", \"else\").", "commit_mentions_repo")
  , ("commit(\"c4\"). commit_trailer(\"c4\", \"co-authored-by\").", "commit_attribution")
  , ("branch(\"claude/x\"). branch_part(\"claude/x\", \"claude\").", "branch_named_by_session")
  , ("lean_package(\"pkg\").", "lean_toolchain_unpinned")
  , ("lean(\"A.lean\"). lean_token(\"A.lean\", 2, sorry).", "lean_hole")
  , ("lean(\"A.lean\"). lean_token(\"A.lean\", 2, axiom).", "lean_hole")
  , ("lean(\"T.lean\"). lean_token(\"T.lean\", 3, native_decide).", "native_decide_outside_examples")
  , ("cabal_dep(\"x.cabal\", \"text\").", "haskell_dependency")
  , ("cabal_dep(\"tools/tv-validate/tv-validate.cabal\", \"lens\").", "haskell_dependency")
  , ("workflow_trigger(\"w.yml\", \"pull_request\").", "workflow_runs_by_itself")
  , ("file(\"a.pdf\"). pdf(\"a.pdf\").", "pdf_committed")
  ]

-- Facts that every case shares, so that only the case's own rule fires.
good :: [Text]
good =
  [ "file(\"flake.nix\").", "file(\"flake.lock\").", "flake_input_locked(\"paper\")."
  , "file(\"papers/fat-tails/fat-tails.pdf\").", "pdf(\"papers/fat-tails/fat-tails.pdf\")."
  , "file(\"papers/tv-audience/tv-audience.pdf\").", "pdf(\"papers/tv-audience/tv-audience.pdf\")."
  , "file(\"papers/practice-beats-theory/wave-models-on-gpus.pdf\")."
  , "pdf(\"papers/practice-beats-theory/wave-models-on-gpus.pdf\")." ]
  -- The libraries that Invariants.lp waives for tools/tv-validate/ and for no other cabal file.
  ++ [ "cabal_dep(\"tools/tv-validate/tv-validate.cabal\", \"" <> d <> "\")."
     | d <- [ "ad", "aeson", "bytestring", "cassava", "filepath", "hedgehog", "optparse-applicative"
            , "tasty", "tasty-hedgehog", "tasty-hunit", "text", "vector" ] ]

clean :: [Text]
clean = good ++
  [ "lean(\"E/Examples.lean\"). lean_examples(\"E/Examples.lean\"). lean_token(\"E/Examples.lean\", 1, native_decide)."
  , "commit(\"ok\"). commit_pair(\"ok\", \"h0ffmann\", \"proof\"). commit_pair(\"ok\", \"z3-scala\", \"z3.sh\")."
  , "cabal_package(\"contextual-bandit\"). cabal_dep(\"x.cabal\", \"base\"). cabal_dep(\"x.cabal\", \"contextual-bandit\"). cabal_dep(\"x.cabal\", \"liquidhaskell\")."
  , "workflow_trigger(\"w.yml\", \"workflow_dispatch\")."
  , "branch(\"add-invariants-lp\"). branch_part(\"add-invariants-lp\", \"invariants\")." ]

-- A file that makes the tree need a toolchain, a nixpkgs attribute that pins it, the toolchain.
needs :: [(Text, Text, Text)]
needs =
  [ ("file(\"house-pricing/rust/Cargo.toml\").", "cargo", "rust")
  , ("file(\"vendor/archify/package.json\").", "nodejs", "node")
  , ("file(\"pomodoro/pomodoro.zig\").", "zig", "zig")
  , ("file(\".claude/skills/roteiro-preview/preview.py\").", "ffmpeg-headless", "ffmpeg")
  , ("lean_package(\"cycle/lean\").", "lean4", "lean") ]

selfTest :: FilePath -> IO ()
selfTest program = do
  forM_ bad $ \(fact, rule) -> do
    atoms <- solve program (good ++ [fact])
    unless (any (("failing(" <> rule <> ",") `T.isPrefixOf`) atoms) $
      die' ("invariants: self-test: " ++ T.unpack fact ++ " did not give " ++ T.unpack rule ++ ": " ++ show atoms)
  atoms <- solve program clean
  when (any (\a -> "failing(" `T.isPrefixOf` a || "stale_waiver(" `T.isPrefixOf` a) atoms) $
    die' ("invariants: self-test: clean facts failed: " ++ show atoms)
  -- A tool the tree needs is a gap until a Nix shell names its package.
  forM_ needs $ \(need, pkg, tool) -> do
    let gap = "gap(toolchain_not_in_nix," <> tool <> ")"
    without <- solve program (good ++ [need])
    unless (gap `elem` without) $ die' ("invariants: self-test: " ++ T.unpack need ++ " gave no gap for " ++ T.unpack tool)
    with <- solve program (good ++ [need, "nix_package(\"" <> pkg <> "\")."])
    when (gap `elem` with) $
      die' ("invariants: self-test: nix_package(" ++ T.unpack pkg ++ ") did not close the gap of " ++ T.unpack tool)
  staleAtoms <- solve program (take 3 good)
  unless (any ("stale_waiver(" `T.isPrefixOf`) staleAtoms) $
    die' "invariants: self-test: a waiver that excuses nothing passed"
  putStrLn ("invariants: self-test passed (" ++ show (length bad) ++ " bad cases, 1 clean, 1 stale waiver, "
            ++ show (length needs) ++ " toolchains)")

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  root <- T.unpack . T.strip <$> git "." ["rev-parse", "--show-toplevel"]
  let program = root </> "Invariants.lp"
  args <- getArgs
  case args of
    ["--self-test"] -> selfTest program
    ["--facts"] -> facts root >>= mapM_ TIO.putStrLn
    [] -> do
      code <- report =<< solve program =<< facts root
      when (code == 0) $ putStrLn "invariants: ok"
      exitWith (if code == 0 then ExitSuccess else ExitFailure code)
    _ -> die' "usage: tools/invariants/run.sh [--facts | --self-test]"
