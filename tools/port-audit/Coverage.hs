-- How much of WAVEWATCH III chaceon translated, and how much of that its switches build, with Z3.
--
-- Two numbers, both in Fortran code lines of `model/src/*.F90` at chaceon's WW3 pin (lines that
-- are not blank, not a `!` comment and not a preprocessor line, the unit of chaceon's
-- `scripts/port_summary.py`):
--
-- * Translated: the lines of the routines that `rust/ports.tsv` lists, a row being a routine with
--   Rust. Each row's status is its evidence, weakest first: `translated`, `routine`, `host`, `spirv`.
-- * Integrated: the translated lines that a chaceon switch file compiles in. WW3 picks its physics
--   and its I/O with `#ifdef W3_<SWITCH>` blocks; a switch file (`switches/switch_chaceon_shrd`,
--   the port's target, and one file per capture build) lists the switches that are on.
--
-- Z3 decides the switches. A line's condition is the formula, over one Boolean per `W3_` macro, of
-- its file being built (WW3's CMake rules: `switches.json`, `src_list.cmake`, `CMakeLists.txt`)
-- and of its preprocessor blocks (`#ifdef`, `#ifndef`, `#if defined ... && ... || !...`, `#elif`,
-- `#else`, nested). A switch file compiles the line when the switch set implies the condition: Z3
-- finds no counterexample (`unsat`). A line is dead when no switch set that `check_switches.cmake`
-- accepts compiles it. Macros that are not switches (`TEST_*`, `ENABLE_*`, `COAMPS`,
-- `NOCGTABLE`...) are off, as in a WW3 build with no `-D` flag. One Z3 process answers every
-- question, through SBV's query mode, each question between a push and a pop.
--
--     tools/port-audit/run.sh coverage           # fetch the pins into port-audit/.cache, print the tables
--     tools/port-audit/run.sh coverage --write   # also write them into port-audit/README.md
--     tools/port-audit/run.sh coverage --check   # exit 1 when README.md is stale
--     tools/port-audit/run.sh coverage --chaceon DIR --ww3 DIR   # use checkouts already on disk
module Coverage
  ( Sources (..), readme, chaceonUrl, chaceonCommit, ww3Url, ww3Commit
  , measure, splice, splitlines
  ) where

import Control.Monad (forM, forM_, when)
import Data.Char (isAlphaNum, isDigit, isSpace)
import Data.List (isPrefixOf, nub, sort)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.SBV
import Data.SBV.Control
import qualified Json as J

-- | What the coverage is measured on, read from the two pins: the Fortran files of WW3's
-- `model/src` as (name, lines), sorted by name; `switches.json` and `src_list.cmake` of
-- `model/src/cmake`; chaceon's switch files as (name, text), sorted by name; its `rust/ports.tsv`.
data Sources = Sources
  { fortran :: [(String, [String])]
  , switchesJson :: String
  , srcList :: String
  , switchFiles :: [(String, String)]
  , ports :: String
  }

readme, chaceonUrl, chaceonCommit, ww3Url, ww3Commit, target :: String
readme = "port-audit/README.md"
chaceonUrl = "https://github.com/h0ffmann/chaceon"
chaceonCommit = "fe531e1e64950c0f3ce7987ae4ed0325a56adfbe" -- the same pin as Chaceon.hs
ww3Url = "https://github.com/metocean/WW3"
ww3Commit = "92e2cf66af6e15ae80eb12562f2b05d4a2d75df5" -- chaceon's WW3 submodule at chaceonCommit
target = "switch_chaceon_shrd"

beginMark, endMark :: String
beginMark = "<!-- coverage:begin -->"
endMark = "<!-- coverage:end -->"

evidence :: [String]
evidence = ["translated", "routine", "host", "spirv"] -- weakest first, as in rust/ports.tsv

------------------------------------------------------------------------------------------------
-- Text, as Python reads it

pySpace :: Char -> Bool
pySpace c = isSpace c || c `elem` ("\x1c\x1d\x1e\x1f\x85\x2028\x2029" :: String)

strip :: String -> String
strip = dropWhile pySpace . reverse . dropWhile pySpace . reverse

split :: String -> [String]
split s = case dropWhile pySpace s of
  "" -> []
  s' -> let (w, r) = break pySpace s' in w : split r

-- | str.splitlines().
splitlines :: String -> [String]
splitlines "" = []
splitlines s = go s
  where
    go "" = []
    go t = let (l, r) = break (`elem` ("\n\r\v\f\x1c\x1d\x1e\x85\x2028\x2029" :: String)) t in
      case r of
        [] -> [l]
        ('\r' : '\n' : r') -> l : go r'
        (_ : r') -> l : go r'

wordChar :: Char -> Bool
wordChar c = isAlphaNum c || c == '_'

-- | Every match of [A-Za-z_]\w*, as re.findall gives them.
macros :: String -> [String]
macros [] = []
macros s@(c : cs)
  | isAsciiLetter c || c == '_' = let (w, r) = span wordChar s in w : macros r
  | otherwise = macros cs
  where isAsciiLetter x = (x >= 'a' && x <= 'z') || (x >= 'A' && x <= 'Z')

------------------------------------------------------------------------------------------------
-- The preprocessor, as formulas

data F
  = FT
  | FF
  | FV String
  | FNot F
  | FAnd [F]
  | FOr [F]
  | FCount Ordering Int [F] -- the number of true formulas, compared with the Int: LT is <=, EQ is ==
  deriving (Eq, Ord, Show)

-- | The tokens of an `#if` expression, as the pattern
-- defined\s*\(\s*\w+\s*\)|defined\s+\w+|&&|\|\||!|\(|\)|\w+ finds them (other characters skipped).
tokens :: String -> [String]
tokens [] = []
tokens s
  | Just (t, r) <- definedParen s = t : tokens r
  | Just (t, r) <- definedSpace s = t : tokens r
  | "&&" `isPrefixOf` s = "&&" : tokens (drop 2 s)
  | "||" `isPrefixOf` s = "||" : tokens (drop 2 s)
  | c `elem` "!()" = [c] : tokens cs
  | wordChar c = let (w, r) = span wordChar s in w : tokens r
  | otherwise = tokens cs
  where
    (c : cs) = s
    definedParen x = do
      r0 <- stripPrefix' "defined" x
      let r1 = dropWhile isSpace r0
      r2 <- stripPrefix' "(" r1
      let r3 = dropWhile isSpace r2
          (w, r4) = span wordChar r3
      if null w then Nothing else do
        r5 <- stripPrefix' ")" (dropWhile isSpace r4)
        pure (take (length x - length r5) x, r5)
    definedSpace x = do
      r0 <- stripPrefix' "defined" x
      let (sp, r1) = span isSpace r0
          (w, r2) = span wordChar r1
      if null sp || null w then Nothing else pure (take (length x - length r2) x, r2)
    stripPrefix' p x = if p `isPrefixOf` x then Just (drop (length p) x) else Nothing

-- | The expression of `#if` or `#elif` as a formula. `defined X`, `defined(X)`, `!`, `&&`, `||`,
-- parentheses. A bare name is defined-ness too: WW3's switches are defined to nothing.
condition :: String -> F
condition text = case disjunction (tokens text) of
  (e, []) -> e
  _ -> error ("cannot read #if " ++ show text)
  where
    primary ("!" : r) = let (e, r') = primary r in (FNot e, r')
    primary ("(" : r) = case disjunction r of
      (e, ")" : r') -> (e, r')
      _ -> error text
    primary (t : r)
      | "defined" `isPrefixOf` t, (_ : name : _) <- macros t = (FV name, r)
      | all isDigit t = (if read t /= (0 :: Integer) then FT else FF, r)
      | otherwise = (FV t, r)
    primary [] = error text
    conjunction ts = let (e, r) = primary ts in go e r
      where go e ("&&" : r) = let (e2, r') = primary r in go (FAnd [e, e2]) r'
            go e r = (e, r)
    disjunction ts = let (e, r) = conjunction ts in go e r
      where go e ("||" : r) = let (e2, r') = conjunction r in go (FOr [e, e2]) r'
            go e r = (e, r)

-- | ^\s*#\s*(\w+)\s*(.*?)\s*$ : the kind and the argument of a directive line.
directive :: String -> Maybe (String, String)
directive line = case dropWhile isSpace line of
  '#' : r ->
    let (kind, rest) = span wordChar (dropWhile isSpace r)
    in if null kind then Nothing else Just (kind, rstripS (dropWhile isSpace rest))
  _ -> Nothing
  where rstripS = reverse . dropWhile isSpace . reverse

-- | For each line, the formula under which the preprocessor keeps it (Nothing for a directive).
guards :: [String] -> [Maybe F]
guards ls = go ls [] FT
  where
    -- stack of (guard of the enclosing block, condition of this branch, any earlier branch)
    go [] [] _ = []
    go [] _ _ = error "unbalanced #if"
    go (line : rest) stack current = case directive line of
      Just (kind, arg)
        | kind `elem` ["if", "ifdef", "ifndef"] ->
            let c0 = if kind == "if" then condition arg else FV (case split arg of (w : _) -> w; [] -> "")
                c = if kind == "ifndef" then FNot c0 else c0
            in Nothing : go rest ((current, c, c) : stack) (FAnd [current, c])
        | kind == "elif", ((outer, _, earlier) : st) <- stack ->
            let c = FAnd [FNot earlier, condition arg]
            in Nothing : go rest ((outer, c, FOr [earlier, c]) : st) (FAnd [outer, c])
        | kind == "else", ((outer, _, earlier) : st) <- stack ->
            Nothing : go rest ((outer, FNot earlier, FT) : st) (FAnd [outer, FNot earlier])
        | kind == "endif", ((outer, _, _) : st) <- stack -> Nothing : go rest st outer
        | otherwise -> Nothing : go rest stack current
      Nothing -> Just current : go rest stack current

isCode :: String -> Bool
isCode line = let s = strip line in not (null s) && not ("!" `isPrefixOf` s) && not ("#" `isPrefixOf` s)

------------------------------------------------------------------------------------------------
-- WW3's build rules (model/src/cmake/: switches.json, check_switches.cmake, src_list.cmake, and
-- the program lists of model/src/CMakeLists.txt)

-- Executables CMakeLists.txt always builds, and those it builds when NetCDF is found (chaceon has it).
programs :: [String]
programs =
  [ "ww3_strt", "ww3_grid", "ww3_bound", "ww3_outf", "ww3_outp", "ww3_trck", "ww3_grib", "ww3_gint"
  , "gx_outf", "gx_outp", "ww3_uprstr", "ww3_shel", "ww3_prep", "ww3_gspl", "ww3_multi", "ww3_systrk"
  , "ww3_ounf", "ww3_ounp", "ww3_bounc", "ww3_trnc", "ww3_prnc" ]

switch :: String -> F
switch name = FV ("W3_" ++ name)

-- | The build of one switch set. `valid` is check_switches.cmake: per category of switches.json,
-- "one" means exactly one option, "upto1" at most one, "upto2" at most two; an option's
-- `conflicts` must be off; each string of `requires` must be on, and of an array inside it, one.
-- `built f` is the condition under which CMake compiles the file f of model/src.
data Rules = Rules {ruleOptions :: [String], valid :: F, built :: String -> F}

rules :: String -> String -> Rules
rules json src = Rules opts (FAnd validParts) builtF
  where
    cats = J.list (J.parse json)
    optsOf c = J.list (J.field "valid-options" c)
    nameOf o = J.str (J.field "name" o)
    opts = sort (nub [nameOf o | c <- cats, o <- optsOf c])
    validParts = concat
      [ count c : concat [ [FOr [FNot me, FNot (switch (J.str x))] | x <- J.list (J.field "conflicts" o)]
                           ++ [FOr [FNot me, need r] | r <- J.list (J.field "requires" o)]
                         | o <- optsOf c, let me = switch (nameOf o) ]
      | c <- cats ]
    count c =
      let on = [switch (nameOf o) | o <- optsOf c]
      in case J.str (J.field "num_switches" c) of
           "one" -> FCount EQ 1 on
           "upto1" -> FCount LT 1 on
           "upto2" -> FCount LT 2 on
           other -> error ("num_switches " ++ other)
    need (J.Arr alternatives) = FOr [switch (J.str y) | y <- alternatives]
    need one = switch (J.str one)
    builtBy = M.fromListWith (flip (++))
      [ (J.str f, [switch (nameOf o)]) | c <- cats, o <- optsOf c, f <- J.list (J.field "build_files" o) ]
    core = split (takeWhile (/= ')') (afterOf "set(ftn_src" src))
    afterOf p s | p `isPrefixOf` s = drop (length p) s
                | (_ : r) <- s = afterOf p r
                | otherwise = error ("no " ++ p)
    pdlib = FAnd [switch "PDLIB", FOr [switch "SCOTCH", switch "METIS"]]
    table0 = M.map FOr builtBy
    table1 = foldl' (\t f -> M.insert f FT t) table0 (core ++ map (++ ".F90") programs)
    table2 = M.insert "w3ounfmetamd.F90" FT (M.insert "ww3_prtide.F90" (switch "TIDE") table1)
    table3 = foldl' (\t f -> M.insert f (FOr [M.findWithDefault FF f t, pdlib]) t) table2
               ["pdlib_field_vec.F90", "w3profsmd_pdlib.F90"]
    builtF f = M.findWithDefault FF f table3

------------------------------------------------------------------------------------------------
-- The ledger

-- | Rows of rust/ports.tsv as (file, first, last, status); last Nothing means the whole file.
ledger :: String -> [(String, Int, Maybe Int, String)]
ledger text =
  [ row line | line <- splitlines text
             , not ("#" `isPrefixOf` line), not ("routine\t" `isPrefixOf` line), not (null (strip line)) ]
  where
    row line =
      let cells = splitTab line
          (wher, status) = (cells !! 1, cells !! 3)
      in case range wher of
           Just (f, r) | status `elem` evidence -> case r of
             Nothing -> (f, 1, Nothing, status)
             Just (a, b) -> (f, a, Just b, status)
           _ -> error line
    splitTab s = case break (== '\t') s of
      (a, []) -> [a]
      (a, _ : r) -> a : splitTab r
    -- model/src/([\w.]+\.F90)(?::(\d+)-(\d+))?, the whole cell
    range w = do
      r0 <- if "model/src/" `isPrefixOf` w then Just (drop 10 w) else Nothing
      let (name, r1) = span (\c -> wordChar c || c == '.') r0
      if length name < 5 || reverse (take 4 (reverse name)) /= ".F90" then Nothing else case r1 of
        [] -> Just (name, Nothing)
        ':' : r2 -> case span isDigit r2 of
          (a@(_ : _), '-' : r3) -> case span isDigit r3 of
            (b@(_ : _), []) -> Just (name, Just (read a, read b))
            _ -> Nothing
          _ -> Nothing
        _ -> Nothing

------------------------------------------------------------------------------------------------
-- Z3, through one SBV query session

toS :: M.Map String SBool -> F -> SBool
toS env = go
  where
    go FT = sTrue
    go FF = sFalse
    go (FV n) = M.findWithDefault (error ("no macro " ++ n)) n env
    go (FNot a) = sNot (go a)
    go (FAnd as) = sAnd (map go as)
    go (FOr as) = sOr (map go as)
    go (FCount o k as) =
      let n = sum [oneIf (go a) | a <- as] :: SInteger
      in if o == EQ then n .== literal (fromIntegral k) else n .<= literal (fromIntegral k)

holdsUnder :: [SBool] -> Query CheckSatResult
holdsUnder cs = do
  push 1
  mapM_ constrain cs
  r <- checkSat
  pop 1
  case r of
    Unk -> error "unknown"
    _ -> pure r

-- | What Z3 answers for the measure: for each distinct condition the switch files that keep it
-- and whether it is dead; the rules each switch file breaks; the options no accepted set turns on.
data Answers = Answers
  { keptBy :: M.Map F (S.Set String), deadSet :: S.Set F, broken :: M.Map String [String], unreachable :: [String] }

ask :: Rules -> [String] -> [(String, S.Set String)] -> [F] -> IO Answers
ask rs names switches conds = runSMT $ do
  let allNames = S.toList (S.fromList (names ++ ["W3_" ++ o | o <- ruleOptions rs]))
  vars <- mapM sBool allNames
  let env = M.fromList (zip allNames vars)
      s = toS env
      off = [sNot (env M.! n) | n <- allNames, not ("W3_" `isPrefixOf` n)]
  query $ do
    -- kept(cond, on): the switch set implies cond, by refutation
    keptPairs <- fmap concat $ forM switches $ \(file, on) -> do
      push 1
      forM_ allNames $ \n ->
        constrain (env M.! n .== fromBool ("W3_" `isPrefixOf` n && S.member (drop 3 n) on))
      ks <- forM conds $ \c -> do
        r <- holdsUnder [sNot (s c)]
        pure [(c, file) | r == Unsat]
      pop 1
      pure (concat ks)
    -- dead(cond): no accepted switch set keeps it
    push 1
    constrain (s (valid rs))
    mapM_ constrain off
    deads <- forM conds $ \c -> do
      r <- holdsUnder [s c]
      pure [c | r == Unsat]
    pop 1
    -- the rules a switch file breaks (empty: CMake accepts it)
    brokenRules <- forM switches $ \(file, on) -> do
      r <- holdsUnder (s (valid rs) : [env M.! ("W3_" ++ o) .== fromBool (S.member o on) | o <- ruleOptions rs])
      let unknown = filter (`notElem` ruleOptions rs) (S.toAscList on)
      pure (file, if r == Sat then [] else if null unknown then ["switches.json"] else unknown)
    -- the options that no accepted switch set can turn on
    impossible <- forM (ruleOptions rs) $ \o -> do
      r <- holdsUnder [s (valid rs), s (switch o)]
      pure [o | r /= Sat]
    pure Answers
      { keptBy = M.fromListWith S.union [(c, S.singleton f) | (c, f) <- keptPairs] `M.union` M.fromList [(c, S.empty) | c <- conds]
      , deadSet = S.fromList (concat deads)
      , broken = M.fromList brokenRules
      , unreachable = concat impossible
      }

------------------------------------------------------------------------------------------------

-- | f"{x:.0f}" of 100 * a / b as a float: the exact binary value, ties to even.
pct :: Int -> Int -> String
pct _ 0 = "-"
pct a b = show (round (toRational (100 * fromIntegral a / fromIntegral b :: Double)) :: Integer) ++ "%"

-- | f"{n:,}".
n' :: Int -> String
n' x | x < 0 = '-' : n' (negate x)
     | otherwise = reverse (go (reverse (show x)))
  where go (a : b : c : r@(_ : _)) = a : b : c : ',' : go r
        go r = r

-- | The tables of port-audit/README.md, as Markdown.
measure :: Sources -> IO String
measure src = do
  let files = fortran src
      switches = [(name, S.fromList (split text)) | (name, text) <- switchFiles src]
  when (target `notElem` map fst switches) (error ("no " ++ target))
  let names = S.toList $ S.fromList
        [ name | (_, ls) <- files, line <- ls, Just (kind, arg) <- [directive line]
               , kind `elem` ["if", "ifdef", "ifndef", "elif"], name <- macros arg, name /= "defined" ]
      rs = rules (switchesJson src) (srcList src)
      fileLines = M.fromList files
      -- The status of each translated line: the strongest row of the ledger that covers it.
      rank st = length (takeWhile (/= st) evidence)
      status = foldl'
        (\m (f, first, lst, st) ->
           foldl' (\m' i -> M.insertWith (\new old -> if rank new > rank old then new else old) (f, i) st m') m
             [first .. maybe (length (fileLines M.! f)) id lst])
        M.empty (ledger (ports src))
      codeLines =
        [ (f, i, FAnd [built rs f, maybe FT id g])
        | (f, ls) <- files, ((line, g), i) <- zip (zip ls (guards ls)) [1 :: Int ..], isCode line ]
      conds = S.toList (S.fromList [c | (_, _, c) <- codeLines])
  answers <- ask rs names switches conds
  let lineFacts = [ (M.lookup (f, i) status, keptBy answers M.! c, S.member c (deadSet answers)) | (f, i, c) <- codeLines ]
      total = length lineFacts
      translated = length [() | (Just _, _, _) <- lineFacts]
      dead = length [() | (_, _, True) <- lineFacts]
      deadTranslated = length [() | (Just _, _, True) <- lineFacts]
      inBuild sw = length [() | (_, k, _) <- lineFacts, S.member sw k]
      integrated sw = length [() | (Just _, k, _) <- lineFacts, S.member sw k]
      byStatus st = ( length [() | (Just s', _, _) <- lineFacts, s' == st]
                    , length [() | (Just s', k, _) <- lineFacts, s' == st, S.member target k]
                    , length [() | (Just s', k, _) <- lineFacts, s' == st, not (S.null k)] )
      (targetLines, targetIntegrated) = (inBuild target, integrated target)
      anyIntegrated = sum [a | st <- evidence, let (_, _, a) = byStatus st]
      header =
        -- The header still names the Scala command, so the Scala and the Haskell check accept the
        -- same README until z3-scala/ is removed; that change renames it here and in the README.
        [ "Generated by `z3-scala/z3.sh coverage --write` from chaceon `" ++ take 8 chaceonCommit
            ++ "` (`rust/ports.tsv`, `switches/`) and WW3 `" ++ take 8 ww3Commit ++ "` (`model/src/*.F90`, "
            ++ show (length files) ++ " files, and its CMake rules). Unit: Fortran code lines."
        , ""
        , "| WW3 code lines | Lines | Share |"
        , "|---|---:|---:|"
        , "| All of `model/src/*.F90` | " ++ n' total ++ " | 100% |"
        , "| **Translated**: in a routine of `rust/ports.tsv` | " ++ n' translated ++ " | " ++ pct translated total ++ " |"
        , "| Compiled by `" ++ target ++ "`, the port's target build | " ++ n' targetLines ++ " | " ++ pct targetLines total ++ " |"
        , "| **Integrated**: translated and compiled by `" ++ target ++ "` | " ++ n' targetIntegrated ++ " | "
            ++ pct targetIntegrated targetLines ++ " of the target build |"
        , "| Translated, compiled only by a capture switch file | " ++ n' (anyIntegrated - targetIntegrated) ++ " | "
            ++ pct (anyIntegrated - targetIntegrated) translated ++ " of translated |"
        , "| Translated, compiled by no chaceon switch file | " ++ n' (translated - anyIntegrated) ++ " | "
            ++ pct (translated - anyIntegrated) translated ++ " of translated |"
        , "| Dead: no switch set that WW3's rules accept compiles it (Z3 `unsat`) | " ++ n' dead ++ " | " ++ pct dead total ++ " |"
        , ""
        , "| Evidence in `rust/ports.tsv` | Translated | Integrated in the target | In some chaceon switch file |"
        , "|---|---:|---:|---:|"
        ]
      evidenceRows = [ "| `" ++ st ++ "` | " ++ n' t ++ " | " ++ n' i ++ " | " ++ n' a ++ " |"
                     | st <- reverse evidence, let (t, i, a) = byStatus st ]
      switchRows =
        [ "| `" ++ sw ++ "` | " ++ verdict ++ " | " ++ n' (inBuild sw) ++ " | " ++ n' (integrated sw)
            ++ " (" ++ pct (integrated sw) (inBuild sw) ++ ") |"
        | (sw, _) <- switches
        , let b = broken answers M.! sw
        , let verdict = if null b then "accepted" else "breaks " ++ joinWith ", " ["`" ++ x ++ "`" | x <- b] ]
      footer =
        [ ""
        , "Translated lines that are dead: " ++ n' deadTranslated ++ ". Switch options that no accepted switch "
            ++ "set can turn on: " ++ (if null (unreachable answers) then "none"
                                       else joinWith ", " ["`" ++ o ++ "`" | o <- unreachable answers]) ++ "."
        ]
      out = header ++ evidenceRows ++ ["", "| Switch file | WW3's rules (Z3) | Compiles | Of it translated |", "|---|---|---:|---:|"]
              ++ switchRows ++ footer
  pure (rstripS (joinWith "\n" out) ++ "\n")
  where
    rstripS = reverse . dropWhile pySpace . reverse

joinWith :: String -> [String] -> String
joinWith _ [] = ""
joinWith sep (x : xs) = x ++ concatMap (sep ++) xs

-- | README.md with `table` between the coverage markers.
splice :: String -> String -> String
splice text table =
  let (headPart, rest) = breakOn beginMark text
      tailPart = drop (length endMark) (snd (breakOn endMark rest))
  in headPart ++ beginMark ++ "\n\n" ++ table ++ "\n" ++ endMark ++ tailPart
  where
    breakOn pat s = go "" s
      where go acc r@(c : cs) | pat `isPrefixOf` r = (reverse acc, r)
                              | otherwise = go (c : acc) cs
            go acc [] = (reverse acc, [])
