-- The public sources of TV audience figures, and how each page becomes rows of Ratings.Rating.
-- A source that changes its page fails with a message; it never gives rows from a column it did
-- not recognise.
module Sources
  ( Source (..)
  , sources
  , Spec (..)
  , fromSpecs
  , nielsen
  ) where

import Data.List (findIndex, isPrefixOf, tails)
import Data.Maybe (mapMaybe)

import Html
import Ratings

data Source = Source
  { sid :: String
  , sourceMarket :: String
  , url :: String
  , licence :: String
  , extract :: [Table] -> Either String [Rating]
  }

-- Nielsen's page is read as it is on the day of the fetch. A Wikipedia page is read at a pinned
-- revision, so two fetches give the same rows; move the revision on purpose.
sources :: [Source]
sources =
  [ Source "nielsen-us" "US" "https://www.nielsen.com/data-center/top-ten/"
      "Nielsen; figures quoted from its public top 10 page"
      (nielsen "nielsen-us")
  , Source "wikipedia-uk" "UK"
      (wiki "en" "List_of_most_watched_television_broadcasts_in_the_United_Kingdom" "1383607932")
      "Wikipedia, CC BY-SA 4.0"
      (fromSpecs "wikipedia-uk" "UK" ukSpecs)
  , Source "wikipedia-us" "US"
      (wiki "en" "List_of_most_watched_television_broadcasts_in_the_United_States" "1377092844")
      "Wikipedia, CC BY-SA 4.0"
      (fromSpecs "wikipedia-us" "US" usSpecs)
  , Source "wikipedia-br" "BR"
      (wiki "pt" "Lista_de_telenovelas_brasileiras_com_maior_audi%C3%AAncia" "71477955")
      "Wikipedia, CC BY-SA 4.0"
      (fromSpecs "wikipedia-br" "BR" brSpecs)
  ]
  where
    wiki lang title rev = "https://" ++ lang ++ ".wikipedia.org/api/rest_v1/page/html/" ++ title ++ "/" ++ rev

-- ── Nielsen ──────────────────────────────────────────────────────────────────

-- The Traditional TV block of Nielsen's top 10 page: four tables under the tabs Total,
-- Broadcast, Cable and Syndication, each with PROGRAM, RANK, VIEWERS P2+ (000), HHLD RATING and
-- ORIGINATOR, and a "Week of ..." line above it. Each programme gives two rows: viewers aged 2
-- and over, in millions, and the household rating, in percent of TV homes.
nielsen :: String -> [Table] -> Either String [Rating]
nielsen name ts = do
  let ours = [t | t <- ts, matches (take 1 (grid t))]
      labels = ["Total", "Broadcast", "Cable", "Syndication"]
  case ours of
    (first : _) | length ours == 4, labels `isSublistOf` before first -> Right ()
    _ -> Left (name ++ ": expected the four tables under the tabs " ++ unwords labels
                 ++ ", found " ++ show (length ours) ++ " tables with Nielsen's columns")
  concat <$> mapM one (zip labels ours)
  where
    matches [r] = case map cellText r of
      (p : rk : v : h : o : _) -> p == "PROGRAM" && rk == "RANK" && "VIEWERS P2+" `isPrefixOf` v
                                    && "HHLD RATING" `isPrefixOf` h && o == "ORIGINATOR"
      _ -> False
    matches _ = False
    one (label, t) = do
      week <- case filter ("Week of" `isPrefixOf`) (before t) of
        [] -> Left (name ++ ": no \"Week of\" line above the " ++ label ++ " table")
        ws -> Right (last ws)
      let (s, e) = startEnd week
          row r = case map cellText r of
            (prog : rk : v : h : orig : _) | Just n <- number Point rk, Just viewers <- number Point v
                                           , Just hh <- number Point h ->
              Just [ base label week s e (round n) prog orig "viewers P2+" (viewers / 1000) "millions"
                   , base label week s e (round n) prog orig "household rating" hh "%" ]
            _ -> Nothing
          rows = mapMaybe row (drop 1 (grid t))
      if length rows == 10 then Right (concat rows)
        else Left (name ++ ": the " ++ label ++ " table has " ++ show (length rows) ++ " rows, not 10")
    base label week s e n prog orig = Rating name "US" ("Traditional TV, " ++ label) week s e n prog orig

isSublistOf :: Eq a => [a] -> [a] -> Bool
isSublistOf xs ys = any (xs `isPrefixOf`) (tails ys)

startEnd :: String -> (String, String)
startEnd txt = case dates txt of
  [] -> ("", "")
  ds@(d : _) -> (d, last ds)

-- ── Wikipedia tables ────────────────────────────────────────────────────────

-- One table of a page: the header names it must have, and which of them hold what.
data Spec = Spec
  { specList :: String
  , rankCol :: Maybe String    -- Nothing: the list has no rank (rank 0)
  , progCol :: String
  , chanCol :: String
  , dateCol :: String
  , metrics :: [(String, String, Decimal, Double, String)]  -- column, metric, decimal, factor, unit
  }

-- Every spec must find its table, and its table must give at least one row.
fromSpecs :: String -> String -> [Spec] -> [Table] -> Either String [Rating]
fromSpecs name mkt specs ts = concat <$> mapM one specs
  where
    one sp = case [ (t, i) | t <- ts, Just i <- [headerRow sp t] ] of
      [] -> Left (name ++ ": no table with the columns " ++ show (needed sp))
      ((t, i) : _) ->
        let hdr = map cellText (grid t !! i)
            col c = findIndex (== c) hdr
            body = filter (not . all isHeader) (drop (i + 1) (grid t))
            rows = concat (mapMaybe (row sp col) body)
        in if null rows then Left (name ++ ": the table " ++ show (specList sp) ++ " gave no row")
           else Right rows
    needed sp = maybe [] pure (rankCol sp) ++ [progCol sp, chanCol sp, dateCol sp]
                  ++ [c | (c, _, _, _, _) <- metrics sp]
    headerRow sp t = findIndex (\r -> let hs = map cellText r in all (`elem` hs) (needed sp)) (take 3 (grid t))
    row sp col r = do
      let cell c = col c >>= \j -> case drop j r of
            (x : _) -> Just (cellText x)
            [] -> Nothing
      prog <- cell (progCol sp)
      chan <- cell (chanCol sp)
      date <- cell (dateCol sp)
      n <- case rankCol sp of
        Nothing -> Just 0
        Just c -> cell c >>= number Point >>= Just . round
      let (s, e) = startEnd date
          vals = [ Rating name mkt (specList sp) date s e n prog chan m (v * f) u
                 | (c, m, d, f, u) <- metrics sp, Just txt <- [cell c], Just v <- [number d txt] ]
      if null vals then Nothing else Just vals

ukSpecs :: [Spec]
ukSpecs =
  [ Spec "special events" (Just "Rank") "Event" "Network(s)" "Date(s)"
      [("Average audience (millions)", "average audience", Point, 1, "millions")]
  , Spec "programmes" (Just "Rank") "Programme" "Network" "Date"
      [("Viewers (millions)", "average audience", Point, 1, "millions")]
  , Spec "films" (Just "Rank") "Title" "Network" "Date"
      [("Viewers (millions)", "average audience", Point, 1, "millions")]
  , Spec "most watched of each year" Nothing "Programme" "Network" "Date"
      [("Viewers (millions)", "average audience", Point, 1, "millions")]
  ]

usSpecs :: [Spec]
usSpecs =
  [ Spec "telecasts" (Just "Rank") "Broadcast" "Network(s)" "Date"
      [("Average viewers", "average audience", Point, 1e-6, "millions")]
  , Spec "telecasts excluding Super Bowls" (Just "Rank") "Broadcast" "Network" "Date"
      [("Average viewers (millions)", "average audience", Point, 1, "millions")]
  , Spec "telecasts by household rating" (Just "Rank") "Broadcast" "Network" "Date"
      [ ("Rating", "household rating", Point, 1, "%")
      , ("Share", "household share", Point, 1, "%") ]
  ]

brSpecs :: [Spec]
brSpecs =
  [ Spec "telenovelas por m\233dia geral" (Just "#") "T\237tulo" "Emissora" "Exibi\231\227o original"
      [ ("M\233dia geral", "household rating, Grande S\227o Paulo", Comma, 1, "points")
      , ("Total de domic\237lios", "households, Grande S\227o Paulo", Comma, 1, "millions") ]
  ]
