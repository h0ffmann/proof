-- A small HTML reader, enough for the tables of the public ratings pages: a tokenizer, entity
-- decoding, and the tables of a page as a grid of cells with rowspan and colspan expanded.
-- It is not a full HTML5 parser. It reads well-formed tables and keeps going on bad markup.
module Html
  ( Token (..)
  , tokens
  , decode
  , Cell (..)
  , Table (..)
  , tables
  , squash
  ) where

import Data.Char (chr, isAlphaNum, isDigit, isHexDigit, isSpace, toLower)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as M
import Numeric (readHex)

data Token
  = Open String [(String, String)]
  | Close String
  | Text String
  deriving (Eq, Show)

-- The tokens of a page. Comments, doctypes and the bodies of script and style are dropped.
tokens :: String -> [Token]
tokens [] = []
tokens s@('<' : rest)
  | "!--" `isPrefixOf` rest = tokens (dropComment (drop 3 rest))
  | ('!' : _) <- rest = tokens (drop 1 (dropWhile (/= '>') rest))
  | ('/' : r) <- rest =
      let (name, r') = span isNameChar r
      in if null name then Text "<" : tokens rest
         else Close (map toLower name) : tokens (drop 1 (dropWhile (/= '>') r'))
  | (c : _) <- rest, isNameChar c =
      let (name0, r) = span isNameChar rest
          name = map toLower name0
          (attrs, r') = attributes r
      in if name `elem` ["script", "style"]
           then tokens (skipRaw name r')
           else Open name attrs : tokens r'
  | otherwise = Text "<" : tokens (drop 1 s)
tokens s = let (t, rest) = break (== '<') s in Text (decode t) : tokens rest

isNameChar :: Char -> Bool
isNameChar c = isAlphaNum c || c == '-' || c == ':'

dropComment :: String -> String
dropComment s
  | null s = s
  | "-->" `isPrefixOf` s = drop 3 s
  | otherwise = dropComment (drop 1 s)

-- After the opening tag of script or style: everything up to its closing tag.
skipRaw :: String -> String -> String
skipRaw name = go
  where
    end = "</" ++ name
    go [] = []
    go s@(_ : r)
      | map toLower (take (length end) s) == end = drop 1 (dropWhile (/= '>') s)
      | otherwise = go r

-- The attributes of a tag, and the text after its '>'.
attributes :: String -> ([(String, String)], String)
attributes s0 = go (dropWhile isSpace s0) []
  where
    go [] acc = (reverse acc, [])
    go ('>' : r) acc = (reverse acc, r)
    go ('/' : r) acc = go (dropWhile isSpace r) acc
    go s acc =
      let (k, r) = span (\c -> not (isSpace c) && c `notElem` "=>/") s
          r1 = dropWhile isSpace r
      in if null k then go (drop 1 s) acc
         else case r1 of
           ('=' : r2) ->
             let r3 = dropWhile isSpace r2
                 (v, r4) = value r3
             in go (dropWhile isSpace r4) ((map toLower k, decode v) : acc)
           _ -> go r1 ((map toLower k, "") : acc)
    value ('"' : r) = let (v, r') = break (== '"') r in (v, drop 1 r')
    value ('\'' : r) = let (v, r') = break (== '\'') r in (v, drop 1 r')
    value r = span (\c -> not (isSpace c) && c /= '>') r

-- Character references: the named ones these pages use, and every numeric one.
decode :: String -> String
decode [] = []
decode ('&' : r)
  | ('#' : x : r') <- r, x `elem` "xX"
  , (h, ';' : r'') <- span isHexDigit r', not (null h)
  , [(n, "")] <- readHex h = safeChr n : decode r''
  | ('#' : r') <- r, (d, ';' : r'') <- span isDigit r', not (null d) = safeChr (read d) : decode r''
  | (name, ';' : r') <- span isAlphaNum r, Just c <- lookup name named = c : decode r'
decode (c : r) = c : decode r

safeChr :: Int -> Char
safeChr n = if n > 0 && n < 0x110000 then chr n else '\xFFFD'

named :: [(String, Char)]
named =
  [ ("amp", '&'), ("lt", '<'), ("gt", '>'), ("quot", '"'), ("apos", '\''), ("nbsp", ' ')
  , ("ndash", '\x2013'), ("mdash", '\x2014'), ("rsquo", '\x2019'), ("lsquo", '\x2018')
  , ("ldquo", '\x201C'), ("rdquo", '\x201D'), ("hellip", '\x2026'), ("eacute", '\xE9')
  , ("aacute", '\xE1'), ("atilde", '\xE3'), ("ccedil", '\xE7'), ("otilde", '\xF5')
  ]

-- One space between words, none at the ends.
squash :: String -> String
squash = unwords . words . map (\c -> if isSpace c || c == '\xA0' then ' ' else c)

data Cell = Cell { isHeader :: Bool, cellText :: String }
  deriving (Eq, Show)

-- A table as a grid (each row as wide as its cells and their colspans), and the text of the page
-- before it, so that a reader can find a heading or a "Week of" line above the table.
data Table = Table { before :: [String], grid :: [[Cell]] }
  deriving (Eq, Show)

-- Every table of a page, outer tables first. The text of a nested table goes into the cell that
-- holds it. Footnote markers (<sup class="reference">) and hidden sort keys are left out.
tables :: [Token] -> [Table]
tables = go []
  where
    go _ [] = []
    go seen (Open "table" _ : ts) =
      let (body, rest) = untilClose 1 ts
      in Table (reverse (take 30 seen)) (expand (rowsOf body)) : go seen rest
    go seen (Text t : ts) = let t' = squash t in go (if null t' then seen else t' : seen) ts
    go seen (_ : ts) = go seen ts

-- The tokens up to the </table> that closes depth d.
untilClose :: Int -> [Token] -> ([Token], [Token])
untilClose _ [] = ([], [])
untilClose d (t : ts) = case t of
  Open "table" _ -> keep (d + 1)
  Close "table" | d == 1 -> ([], ts)
                | otherwise -> keep (d - 1)
  _ -> keep d
  where keep d' = let (a, b) = untilClose d' ts in (t : a, b)

-- A raw cell: header or not, its spans, its text.
data Raw = Raw Bool Int Int String

rowsOf :: [Token] -> [[Raw]]
rowsOf = filter (not . null) . splitRows
  where
    splitRows [] = []
    splitRows ts =
      let ts1 = dropWhile (not . isRowStart) ts
      in case ts1 of
           [] -> []
           (_ : r) -> let (row, rest) = break isRowStart r in cells row : splitRows rest
    isRowStart (Open "tr" _) = True
    isRowStart _ = False
    cells [] = []
    cells (Open n as : r) | n `elem` ["td", "th"] =
      let (inside, rest) = cellBody 0 r
          sp k = maybe 1 (max 1 . readInt) (lookup k as)
      in Raw (n == "th") (sp "rowspan") (sp "colspan") (squash (textOf inside)) : cells rest
    cells (_ : r) = cells r
    -- A cell ends at the next td, th or tr of its own table, or at its own close tag.
    cellBody :: Int -> [Token] -> ([Token], [Token])
    cellBody _ [] = ([], [])
    cellBody d (t : r) = case t of
      Open "table" _ -> keep (d + 1)
      Close "table" -> keep (d - 1)
      Open n _ | d == 0, n `elem` ["td", "th", "tr"] -> ([], t : r)
      Close n | d == 0, n `elem` ["td", "th"] -> ([], r)
      _ -> keep d
      where keep d' = let (a, b) = cellBody d' r in (t : a, b)

readInt :: String -> Int
readInt s = case takeWhile isDigit (dropWhile isSpace s) of
  [] -> 1
  ds -> read ds

-- The visible text of a cell: <br> is a space, footnotes and hidden sort keys are dropped.
textOf :: [Token] -> String
textOf [] = []
textOf (Open "br" _ : r) = ' ' : textOf r
textOf (Open n as : r)
  | hidden n as = textOf (skipElem n 1 r)
textOf (Open n _ : r) | n `elem` ["td", "th", "tr", "p", "div", "li"] = ' ' : textOf r
textOf (Close n : r) | n `elem` ["td", "th", "tr", "p", "div", "li"] = ' ' : textOf r
textOf (Text t : r) = t ++ textOf r
textOf (_ : r) = textOf r

hidden :: String -> [(String, String)] -> Bool
hidden n as =
  (n == "sup" && "reference" `isIn` cls)
    || "sortkey" `isIn` cls
    || "display:none" `isIn` filter (not . isSpace) (maybe "" (map toLower) (lookup "style" as))
  where
    cls = maybe "" id (lookup "class" as)
    isIn a b = any (a `isPrefixOf`) (suffixes b)
    suffixes xs = case xs of [] -> [[]]; (_ : ys) -> xs : suffixes ys

skipElem :: String -> Int -> [Token] -> [Token]
skipElem _ _ [] = []
skipElem n d (t : r) = case t of
  Open m _ | m == n -> skipElem n (d + 1) r
  Close m | m == n -> if d == 1 then r else skipElem n (d - 1) r
  _ -> skipElem n d r

-- Rowspan and colspan, expanded: a cell that spans k columns appears k times in its row, and a
-- cell that spans k rows appears in each of them, at the same column.
expand :: [[Raw]] -> [[Cell]]
expand = go M.empty
  where
    go _ [] = []
    go pending (row : rows) =
      let (cellsOut, pending') = place 0 row pending M.empty []
      in cellsOut : go pending' rows
    -- col: the next column; carry: rowspans still running from rows above (column -> (rows
    -- left, cell)); next: the rowspans for the row below.
    place :: Int -> [Raw] -> M.Map Int (Int, Cell) -> M.Map Int (Int, Cell) -> [Cell]
          -> ([Cell], M.Map Int (Int, Cell))
    place col raws carry next acc
      | Just (n, c) <- M.lookup col carry =
          let next' = if n > 1 then M.insert col (n - 1, c) next else next
          in place (col + 1) raws (M.delete col carry) next' (c : acc)
    place col [] carry next acc
      | M.null carry = (reverse acc, next)
      | otherwise =
          -- a rowspan from above that sits right of every cell of this row
          let (k, _) = M.findMin carry
          in if k > col then place k [] carry next (replicate (k - col) (Cell False "") ++ acc)
             else place (col + 1) [] (M.delete col carry) next acc
    place col (Raw h rs cs t : raws) carry next acc =
      let c = Cell h t
          cols = [col .. col + cs - 1]
          next' = if rs > 1 then foldr (\k -> M.insert k (rs - 1, c)) next cols else next
      in place (col + cs) raws carry next' (replicate cs c ++ acc)
