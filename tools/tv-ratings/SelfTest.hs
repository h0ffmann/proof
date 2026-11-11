-- The self-test: small pages written for this test in the shape of each source (not copies of
-- them), the numbers and dates they must give, and broken pages that must fail. No network.
module SelfTest (selfTest) where

import Control.Monad (unless)
import Data.Either (isLeft)
import System.Exit (exitFailure)

import Html
import Ratings
import Sources

data Check = Check String Bool String

selfTest :: IO ()
selfTest = do
  oks <- mapM report checks
  unless (and oks) exitFailure
  where
    report (Check name ok detail) = do
      putStrLn ((if ok then "OK   " else "FAIL ") ++ name ++ (if ok then "" else "  " ++ detail))
      pure ok

checks :: [Check]
checks =
  [ eq "number: thousands separator" (number Point "28,176") (Just 28176)
  , eq "number: decimal point and a footnote mark" (number Point "30.15 \8224") (Just 30.15)
  , eq "number: decimal comma" (number Comma "2,11 milh\245es") (Just 2.11)
  , eq "number: points" (number Comma "74 pontos") (Just 74)
  , eq "number: grouped by spaces" (number Comma "59 864") (Just 59864)
  , eq "number: none" (number Point "Data unavailable") Nothing
  , eq "dates: day month year" (dates "30 July 1966") ["1966-07-30"]
  , eq "dates: month day, year" (dates "February 9, 2025") ["2025-02-09"]
  , eq "dates: Portuguese, a range" (dates "24 de junho de 1985 at\233 22 de fevereiro de 1986")
      ["1985-06-24", "1986-02-22"]
  , eq "dates: a Nielsen week" (dates "Week of Oct. 26 \8211 Nov. 01, 2026") ["2026-10-26", "2026-11-01"]
  , eq "dates: a week across the new year" (dates "Week of Dec. 29 \8211 Jan. 04, 2027")
      ["2026-12-29", "2027-01-04"]
  , eq "html: entities" (decode "AT&amp;T &#8211; &#x41;&nbsp;b") "AT&T \8211 A b"
  , eq "html: rowspan and colspan" (map (map cellText) (concatMap grid (take 1 (tables (tokens spans)))))
      [["a", "b", "b"], ["a", "c", "d"]]
  , eq "html: footnotes, sort keys, scripts and comments are dropped"
      (map (map cellText) (concatMap grid (take 1 (tables (tokens noise))))) [["32.30", "BBC ITV"]]
  , eq "nielsen: 4 lists of 10 programmes, 2 metrics each" (length <$> nielsenRows) (Right 80)
  , eq "nielsen: first broadcast row"
      (fmap (take 2 . filter ((== "Traditional TV, Broadcast") . list)) nielsenRows)
      (Right [ Rating "nielsen-us" "US" "Traditional TV, Broadcast" "Week of Oct. 26 \8211 Nov. 01, 2026"
                 "2026-10-26" "2026-11-01" 1 "SHOW 1" "CBS" "viewers P2+" 21.5 "millions"
             , Rating "nielsen-us" "US" "Traditional TV, Broadcast" "Week of Oct. 26 \8211 Nov. 01, 2026"
                 "2026-10-26" "2026-11-01" 1 "SHOW 1" "CBS" "household rating" 9.5 "%" ])
  , eq "nielsen: the nine channels" (length . filter focus <$> nielsenRows) (Right 48)
  , Check "nielsen: a page without the tabs fails" (isLeft (nielsen "nielsen-us" (tables (tokens (nielsenPage False))))) ""
  , Check "nielsen: a table of 9 rows fails" (isLeft (nielsen "nielsen-us" (tables (tokens nielsenShort)))) ""
  , eq "wikipedia: a spec reads its table" (fromSpecs "w" "UK" [ukSpec] (tables (tokens wikiPage)))
      (Right [ Rating "w" "UK" "special events" "30 July 1966" "1966-07-30" "1966-07-30" 1
                 "World Cup final" "BBC/ITV" "average audience" 32.3 "millions"
             , Rating "w" "UK" "special events" "6 September 1997" "1997-09-06" "1997-09-06" 2
                 "A funeral" "BBC One" "average audience" 32.1 "millions" ])
  , eq "wikipedia: a simulcast is on the nine channels"
      (map focus <$> fromSpecs "w" "UK" [ukSpec] (tables (tokens wikiPage))) (Right [True, True])
  , Check "wikipedia: a renamed column fails"
      (isLeft (fromSpecs "w" "UK" [ukSpec { progCol = "Programme" }] (tables (tokens wikiPage)))) ""
  , eq "csv: a field with a comma is quoted"
      (csvRow (Rating "s" "BR" "l" "p" "" "" 1 "Roque, Santeiro" "Globo" "m" 74 "points"))
      "s,BR,l,p,,,1,\"Roque, Santeiro\",Globo,1,m,74,points"
  ]
  where
    eq :: (Eq a, Show a) => String -> a -> a -> Check
    eq name got want = Check name (got == want) ("got " ++ show got ++ ", want " ++ show want)
    nielsenRows = nielsen "nielsen-us" (tables (tokens (nielsenPage True)))
    ukSpec = Spec "special events" (Just "Rank") "Event" "Network(s)" "Date(s)"
      [("Average audience (millions)", "average audience", Point, 1, "millions")]

spans :: String
spans = "<table><tr><td rowspan=\"2\">a</td><td colspan=2>b</td></tr><tr><td>c</td><td>d</td></tr></table>"

noise :: String
noise = concat
  [ "<!-- a comment <table> --><script>var t = '<table>';</script><table><tr>"
  , "<td><span class=\"sortkey\" style=\"display:none\">0032</span>32.30<sup class=\"reference\">[1]</sup></td>"
  , "<td>BBC<br>ITV</td></tr></table>" ]

-- Four tables under the four tabs, ten programmes each, on channels in turn CBS, NBC, ABC, FOX
-- and two others; a programme of rank k has 22 - k/2 million viewers and a rating of 10 - k/2.
nielsenPage :: Bool -> String
nielsenPage tabs = concat
  ( [ "<html><body><div>Traditional TV Top 10</div>" ]
    ++ (if tabs then ["<nav><span>Total</span><span>Broadcast</span><span>Cable</span><span>Syndication</span></nav>"] else [])
    ++ [ nielsenTable 10 | _ <- [1 :: Int .. 4] ]
    ++ [ "</body></html>" ] )

nielsenShort :: String
nielsenShort = concat
  ( [ "<nav><span>Total</span><span>Broadcast</span><span>Cable</span><span>Syndication</span></nav>" ]
    ++ [ nielsenTable n | n <- [10, 9, 10, 10] ] )

nielsenTable :: Int -> String
nielsenTable n = concat
  ( [ "<div class=\"weeklyDiv\"><p>Week of Oct. 26 &#8211; Nov. 01, 2026</p></div><table>"
    , "<tr><th>PROGRAM</th><th>RANK</th><th>VIEWERS P2+ (000)</th><th>HHLD RATING</th><th>ORIGINATOR</th></tr>" ]
    ++ [ "<tr><td>SHOW " ++ show k ++ "</td><td>" ++ show k ++ "</td><td>"
           ++ commas (22000 - 500 * k) ++ "</td><td>" ++ show (10 - fromIntegral k / 2 :: Double)
           ++ "</td><td>" ++ (cycle ["CBS", "NBC", "ABC", "FOX", "ESPN", "PRIME VIDEO"] !! (k - 1))
           ++ "</td></tr>"
       | k <- [1 .. n] ]
    ++ [ "</table>" ] )
  where
    commas v = let s = show v in if length s > 3 then take (length s - 3) s ++ "," ++ drop (length s - 3) s else s

wikiPage :: String
wikiPage = concat
  [ "<p>Most watched special events</p><table class=\"wikitable\">"
  , "<tr><th>Rank</th><th>Event</th><th>Average audience<br>(millions)</th><th>Date(s)</th><th>Network(s)</th></tr>"
  , "<tr><th>1</th><td>World Cup final</td><td>32.30<sup class=\"reference\">[2]</sup></td><td>30 July 1966</td><td>BBC/ITV</td></tr>"
  , "<tr><th>2</th><td>A funeral</td><td>32.10</td><td>6 September 1997</td><td>BBC One</td></tr>"
  , "<tr><th>3</th><td>Data unavailable</td><td>Data unavailable</td><td></td><td></td></tr>"
  , "</table>" ]
