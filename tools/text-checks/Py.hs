-- What the text checks need to read and print text exactly as they did in Python and in Scala:
-- Python's whitespace, strip, split and splitlines, its UTF-8 text mode, and its regular
-- expressions, with Unicode word classes and case folding. The patterns run on PCRE 8.44
-- (regex-pcre-builtin) in UTF-8 mode with Unicode properties, so \w, \b, \d and \s are Unicode
-- as in Python's `re` and in Java's UNICODE_CHARACTER_CLASS.
--
-- Offsets are byte offsets into the UTF-8 text. A match starts and ends on a character boundary,
-- so a slice by those offsets is always valid UTF-8.
module Py
  ( Rx, re, reI, reS, Match (..)
  , matches, matchesFrom, findAll, search, matchStart, sub, subWith, splitRx
  , isSpace, strip, lstrip, rstrip, stripChars, lstripChars, split, splitlines
  , decode, len, take', ljust, repr
  , Bytes, enc, dec, sliceB
  ) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Unsafe as BU
import Data.Bits ((.|.))
import Data.Char (ord)
import qualified Data.Char as C
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TE
import System.IO.Unsafe (unsafePerformIO)
import Text.Regex.PCRE.Wrap
  (CompOption (..), Regex, compCaseless, compDotAll, compUTF8, execBlank, wrapCompile, wrapMatch)

type Bytes = B.ByteString

enc :: Text -> Bytes
enc = TE.encodeUtf8

dec :: Bytes -> Text
dec = TE.decodeUtf8With TE.lenientDecode

sliceB :: Int -> Int -> Bytes -> Bytes
sliceB a b = B.take (b - a) . B.drop a

-- | A compiled pattern.
newtype Rx = Rx Regex

-- PCRE_UCP: \w, \d, \s and \b by Unicode properties (pcre.h, 0x20000000).
compUCP :: CompOption
compUCP = CompOption 0x20000000

compileWith :: CompOption -> String -> Rx
compileWith extra p = unsafePerformIO $ do
  r <- B.useAsCString (B.snoc (enc (T.pack p)) 0) $ \cs ->
    wrapCompile (compUTF8 .|. compUCP .|. extra) execBlank cs
  case r of
    Left (off, msg) -> error ("regex " ++ show p ++ " at " ++ show off ++ ": " ++ msg)
    Right rx -> pure (Rx rx)
{-# NOINLINE compileWith #-}

-- | A pattern; reI ignores case, reS lets . match a newline.
re, reI, reS :: String -> Rx
re = compileWith (CompOption 0)
reI = compileWith compCaseless
reS = compileWith compDotAll

-- | A match: its byte span and its groups (Nothing for a group that did not take part).
data Match = Match {mStart :: !Int, mEnd :: !Int, mText :: Text, mGroups :: [Maybe Text]}

execAt :: Rx -> Bytes -> Int -> Maybe [(Int, Int)]
execAt (Rx rx) s from = unsafePerformIO $
  BU.unsafeUseAsCStringLen (if B.null s then B.pack [0] else s) $ \(p, n) -> do
    r <- wrapMatch from rx (p, if B.null s then 0 else n)
    pure $ case r of
      Right (Just spans) -> Just spans
      _ -> Nothing

toMatch :: Bytes -> [(Int, Int)] -> Match
toMatch s spans = case spans of
  ((a, b) : groups) -> Match a b (dec (sliceB a b s)) (map grp groups)
  [] -> error "empty match array"
  where
    grp (a, b) | a < 0 = Nothing
               | otherwise = Just (dec (sliceB a b s))

-- | Every match from byte offset `from`, as Java's Matcher.find() gives them in a loop: after an
-- empty match the search moves on by one character.
matchesFrom :: Rx -> Int -> Text -> [Match]
matchesFrom rx from0 t = go from0
  where
    s = enc t
    n = B.length s
    go from
      | from > n = []
      | otherwise = case execAt rx s from of
          Nothing -> []
          Just spans ->
            let m = toMatch s spans
                next | mEnd m > mStart m = mEnd m
                     | otherwise = nextChar (mEnd m)
            in m : go next
    nextChar i
      | i >= n = n + 1
      | otherwise = i + 1 + length (takeWhile cont [i + 1 .. n - 1])
    cont j = let w = B.index s j in w >= 0x80 && w < 0xC0

matches :: Rx -> Text -> [Match]
matches rx = matchesFrom rx 0

findAll :: Rx -> Text -> [Text]
findAll rx = map mText . matches rx

search :: Rx -> Text -> Bool
search rx t = not (null (take 1 (matches rx t)))

-- | A match that starts at the beginning (Java's lookingAt, Python's re.match).
matchStart :: Rx -> Text -> Maybe Match
-- PCRE tries the start first, so the first match starts at 0 exactly when one there exists.
matchStart rx t = case take 1 (matches rx t) of
  [m] | mStart m == 0 -> Just m
  _ -> Nothing

-- | Every match replaced by what the function makes of it.
subWith :: Rx -> (Match -> Text) -> Text -> Text
subWith rx f t = TE.decodeUtf8 (B.concat (go 0 (matches rx t)))
  where
    s = enc t
    go at [] = [B.drop at s]
    go at (m : ms) = sliceB at (mStart m) s : enc (f m) : go (mEnd m) ms

-- | Java's replaceAll with a literal replacement, or with $1 for the first group.
sub :: Rx -> Text -> Text -> Text
sub rx repl = subWith rx $ \m ->
  if repl == T.pack "$1" then (case mGroups m of (Just g : _) -> g; _ -> T.empty) else repl

-- | Java's Pattern.split(s, -1): trailing empty strings stay; a zero-width match at the start
-- gives no leading empty string.
splitRx :: Rx -> Text -> [Text]
splitRx rx t = map dec (go 0 ms)
  where
    s = enc t
    ms = [m | m <- matches rx t, not (mStart m == 0 && mEnd m == 0)]
    go at [] = [B.drop at s]
    go at (m : rest) = sliceB at (mStart m) s : go (mEnd m) rest

-- | Python's str.isspace, one character.
isSpace :: Char -> Bool
isSpace c = C.isSpace c || C.generalCategory c `elem` [C.Space, C.LineSeparator, C.ParagraphSeparator]
  || (o >= 0x1c && o <= 0x1f) || o == 0x85
  where o = ord c

strip, lstrip, rstrip :: Text -> Text
strip = lstrip . rstrip
lstrip = T.dropWhile isSpace
rstrip = T.dropWhileEnd isSpace

stripChars, lstripChars :: String -> Text -> Text
stripChars cs = T.dropAround (`elem` cs)
lstripChars cs = T.dropWhile (`elem` cs)

-- | str.split() with no argument: runs of whitespace, no empty strings.
split :: Text -> [Text]
split = filter (not . T.null) . T.split isSpace

-- | str.splitlines().
splitlines :: Text -> [Text]
splitlines t
  | T.null t = []
  | otherwise = go t
  where
    go s | T.null s = []
         | otherwise =
             let (line, rest) = T.break brk s
             in case T.uncons rest of
                  Nothing -> [line]
                  Just ('\r', r) | Just ('\n', r') <- T.uncons r -> line : go r'
                  Just (_, r) -> line : go r
    brk c = c `elem` ("\n\r\v\f\x1c\x1d\x1e\x85\x2028\x2029" :: String)

-- | A file's bytes as Python's text mode reads them: UTF-8, universal newlines. Nothing when the
-- bytes are not UTF-8.
decode :: Bytes -> Maybe Text
decode bs = case TE.decodeUtf8' bs of
  Left _ -> Nothing
  Right t -> Just (T.replace (T.pack "\r") (T.pack "\n") (T.replace (T.pack "\r\n") (T.pack "\n") t))

len :: Text -> Int
len = T.length

take' :: Int -> Text -> Text
take' = T.take

ljust :: Int -> Text -> Text
ljust w s = s <> T.replicate (w - T.length s) (T.pack " ")

-- | Python's repr() of a str, for the self-test failures.
repr :: Text -> Text
repr s
  | T.any (== '\'') s && not (T.any (== '"') s) = T.concat [T.pack "\"", s, T.pack "\""]
  | otherwise = T.concat [T.pack "'", T.replace (T.pack "'") (T.pack "\\'") (T.replace (T.pack "\\") (T.pack "\\\\") s), T.pack "'"]
