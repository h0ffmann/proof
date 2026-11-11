-- The common row of every source, and the readers of numbers and dates it needs.
module Ratings
  ( Rating (..)
  , header
  , csvRow
  , number
  , Decimal (..)
  , dates
  , focusChannels
  , focus
  ) where

import Data.Char (isDigit, isSpace, toLower)
import Data.List (intercalate, isPrefixOf)
import Numeric (showFFloat)
import Text.Printf (printf)

-- One published audience figure. `value` is in `unit`; a list with two metrics per programme
-- (Nielsen's viewers and household rating) gives two rows.
data Rating = Rating
  { source :: String     -- the source id of Sources.hs
  , market :: String     -- UK, US, BR
  , list :: String       -- which list of the source (Broadcast, special events, ...)
  , period :: String     -- the period as the page writes it
  , start :: String      -- the first date of the period, ISO 8601, or ""
  , end :: String        -- the last date, or ""
  , rank :: Int          -- 0 when the list has no rank
  , programme :: String
  , channel :: String    -- as the page writes it; "BBC/ITV" for a simulcast
  , metric :: String
  , value :: Double
  , unit :: String
  } deriving (Eq, Show)

header :: [String]
header =
  [ "source", "market", "list", "period", "start", "end", "rank", "programme", "channel"
  , "focus", "metric", "value", "unit" ]

csvRow :: Rating -> String
csvRow r = intercalate "," (map field
  [ source r, market r, list r, period r, start r, end r, show (rank r), programme r, channel r
  , if focus r then "1" else "0", metric r, showValue (value r), unit r ])
  where
    field s
      | any (`elem` ",\"\n") s = "\"" ++ concatMap (\c -> if c == '"' then "\"\"" else [c]) s ++ "\""
      | otherwise = s
    showValue v
      | v == fromIntegral (round v :: Integer) = show (round v :: Integer)
      | otherwise =
          -- six decimals, trailing zeros dropped: 28176 / 1000 is 28.176, not 28.176000000000002
          let t = showFFloat (Just 6) v ""
          in reverse (dropWhile (== '.') (dropWhile (== '0') (reverse t)))

-- The nine channels of the paper's ground-truth protocol (papers/tv-audience, Section 6). A row is
-- in focus when its channel names one of them, alone or in a simulcast; "ITV (LWT)", an ITV
-- franchise, counts as ITV.
focusChannels :: [(String, [String])]
focusChannels =
  [ ("UK", ["BBC One", "BBC1", "BBC", "ITV", "ITV1", "Channel 4"])
  , ("US", ["ABC", "CBS", "NBC"])
  , ("BR", ["Globo", "TV Globo", "Record", "RecordTV", "SBT"])
  ]

focus :: Rating -> Bool
focus r = case lookup (market r) focusChannels of
  Nothing -> False
  Just names -> any (`elem` names) (parts (channel r))
  where
    parts = map (trim . takeWhile (/= '(')) . splitOn "/|,"
    trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
    splitOn seps s = case break (`elem` seps) s of
      (a, []) -> [a]
      (a, _ : b) -> a : splitOn seps b

data Decimal = Point | Comma

-- The first number in a text: "28,176" is 28176 with a decimal point, "2,11 milhões" is 2.11 with
-- a decimal comma. Nothing when the text holds no digit.
number :: Decimal -> String -> Maybe Double
number d s = case dropWhile (not . isDigit) s of
  [] -> Nothing
  r ->
    let raw = takeWhile (\c -> isDigit c || c `elem` ".,\x202F\xA0" || c == ' ' ) r
        digitsOnly = trimEnd raw
        clean = case d of
          Point -> filter (\c -> isDigit c || c == '.') (filter (/= ',') digitsOnly)
          Comma -> map (\c -> if c == ',' then '.' else c) (filter (\c -> isDigit c || c == ',') digitsOnly)
        clean' = reverse (dropWhile (== '.') (reverse clean))
    in case reads clean' of
         [(v, "")] -> Just v
         _ -> case reads (clean' ++ "0") of
                [(v, "")] -> Just v
                _ -> Nothing
  where
    startsDigit (c : _) = isDigit c
    startsDigit [] = False
    -- a space ends the number unless digits in groups of three follow it ("59 864")
    trimEnd = go
      where
        go [] = []
        go (c : r)
          | c `elem` " \x202F\xA0" =
              let (g, rest) = span isDigit r
              in if length g == 3 && not (startsDigit rest) then g ++ go rest else []
          | otherwise = c : go r

-- Every date in a text, in order, as ISO 8601: "30 July 1966", "February 9, 2025",
-- "24 de junho de 1985", and Nielsen's "Week of Oct. 26 \x2013 Nov. 01, 2026", where the year is
-- written once at the end. A date without a year takes the year of the next date that has one, or
-- the year before when its month is later (a week from 29 December to 4 January).
dates :: String -> [String]
dates s = fill (scan (words (map clean s)))
  where
    clean c = if c `elem` ",.()\x2013\x2014-" then ' ' else toLower c
    fill :: [(Maybe Int, Int, Int)] -> [String]
    fill found = go found
      where
        go [] = []
        go ((Just y, m, d) : r) = iso y m d : go r
        go ((Nothing, m, d) : r) = case [(y, m') | (Just y, m', _) <- r] of
          ((y, m') : _) -> iso (if m > m' then y - 1 else y) m d : go r
          [] -> go r
    iso :: Int -> Int -> Int -> String
    iso = printf "%04d-%02d-%02d"
    scan :: [String] -> [(Maybe Int, Int, Int)]
    scan ws = case ws of
      (d : "de" : m : "de" : y : r) | Just dd <- day d, Just mm <- month m, Just yy <- year y ->
        (Just yy, mm, dd) : scan r
      (d : m : y : r) | Just dd <- day d, Just mm <- month m, Just yy <- year y -> (Just yy, mm, dd) : scan r
      (m : d : y : r) | Just mm <- month m, Just dd <- day d, Just yy <- year y -> (Just yy, mm, dd) : scan r
      (m : d : r) | Just mm <- month m, Just dd <- day d -> (Nothing, mm, dd) : scan r
      (_ : r) -> scan r
      [] -> []
    day w
      | not (null w), length w <= 2, all isDigit w, (read w :: Int) >= 1, (read w :: Int) <= 31 = Just (read w)
      | otherwise = Nothing
    year w = if length w == 4 && all isDigit w then Just (read w) else Nothing
    month w = lookup True [ (length w >= 3 && any (`isPrefixOf` w) ns, i) | (i, ns) <- months ]
    months :: [(Int, [String])]
    months = zip [1 ..]
      [ ["jan"], ["feb", "fev"], ["mar"], ["apr", "abr"], ["may", "mai"], ["jun"], ["jul"]
      , ["aug", "ago"], ["sep", "set"], ["oct", "out"], ["nov"], ["dec", "dez"] ]
